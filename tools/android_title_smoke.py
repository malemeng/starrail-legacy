"""Check the published game on an already booted, isolated Android 16 emulator."""

from io import BytesIO
import os
from pathlib import Path
import re
import subprocess
import time
import xml.etree.ElementTree as ET

from PIL import Image

PACKAGE = "com.malemeng.starraillegacy"
ACTIVITY = PACKAGE + "/com.godot.game.GodotAppLauncher"
RESULTS = Path("results")


def adb(*args):
    return subprocess.check_output(["adb", *map(str, args)], timeout=90)


def shell(*args):
    return adb("shell", *args).decode().strip()


def screenshot(directory, name):
    data = adb("exec-out", "screencap", "-p")
    (directory / (name + ".png")).write_bytes(data)
    return Image.open(BytesIO(data)).convert("RGB")


def primary_button(image):
    # At the same y, three points across the menu share its gold fill.
    width, height = image.size
    if width <= height:
        return None
    def gold(x, y):
        r, g, b = image.getpixel((int(width*x), y))
        return r > 195 and 150 < g < 230 and r > g+14 and g > b+18
    rows = [y for y in range(int(height*.36), int(height*.77))
            if all(gold(x, y) for x in (.18, .21, .24))]
    if len(rows) >= height*.02:
        return int(width*.23), rows[len(rows)//2]
    return None


def at_port(image):
    width, height = image.size
    for y in range(int(height*.01), int(height*.11)):
        colors = [image.getpixel((int(width*x), y)) for x in (.2, .3, .5, .65, .8)]
        if all(g > 95 and b > 100 and g > r+28 for r, g, b in colors):
            return True
    return False


def report_visible(image):
    w, h = image.size
    center = image.crop((int(w*.42),int(h*.43),int(w*.58),int(h*.54))).resize((30,15))
    return sum(45 < r < 90 and max(r,g,b)-min(r,g,b) < 12
               for r,g,b in center.getdata()) > 200


def dismiss_launcher_anr(image):
    # Some Google API images raise a system dialog for Pixel Launcher at boot.
    # A game ANR must remain on screen and fail this test.
    w,h = image.size
    center = image.crop((int(w*.3),int(h*.25),int(w*.7),int(h*.75))).resize((20,20))
    if sum(min(rgb) > 210 for rgb in center.getdata()) < 230:
        return False
    path = "/data/local/tmp/qa-foreground.xml"
    if "dumped" not in shell("uiautomator","dump",path).lower():
        return False
    nodes = list(ET.fromstring(shell("cat",path)).iter("node"))
    if not any("pixel launcher" in n.get("text","").lower() and "responding" in n.get("text","").lower() for n in nodes):
        return False
    button = next((n for n in nodes if n.get("resource-id") == "android:id/aerr_close" or n.get("text") == "Close app"),None)
    if button is None:
        return False
    x1,y1,x2,y2 = map(int,re.findall(r"\d+",button.attrib["bounds"]))
    shell("input","tap",(x1+x2)//2,(y1+y2)//2)
    print("Dismissed confirmed Pixel Launcher ANR; game retained its process")
    time.sleep(1)
    return True


def wait_screen(directory, name, matches):
    deadline = time.monotonic()+65
    missing_since = None
    while time.monotonic() < deadline:
        image = screenshot(directory, name)
        if matches(image):
            return image
        if dismiss_launcher_anr(image):
            continue
        pid = subprocess.run(["adb","shell","pidof",PACKAGE], capture_output=True, timeout=10)
        if pid.stdout.strip():
            missing_since = None
        elif missing_since is None:
            missing_since = time.monotonic()
        elif time.monotonic()-missing_since > 4:
            raise RuntimeError(f"Game process exited before {name}")
        time.sleep(1)
    raise RuntimeError(f"Did not reach {name}")


def start():
    shell("am", "start", "-W", "-n", ACTIVITY)


def check_foreground(pid):
    assert shell("pidof", PACKAGE) == pid, "Game process changed"
    activities = shell("dumpsys", "activity", "activities").splitlines()
    assert any(PACKAGE in line and ("topResumedActivity" in line or "mResumedActivity" in line)
               for line in activities), "Lost foreground"


def observe_port(directory, name, pid):
    wait_screen(directory, name, at_port)
    check_foreground(pid)
    since = time.monotonic()
    for second in (10, 60):
        time.sleep(max(0, second - (time.monotonic() - since)))
        check_foreground(pid)
        image = screenshot(directory, f"{name}-{second}s")
        assert at_port(image), f"Port disappeared in {name} after {second}s"
        print(name, "at port in foreground", second, "seconds, pid", pid, flush=True)


def thumb_top(image, right_inset):
    # Both lists anchor their scrollbar to the right with a fixed logical margin.
    w, h = image.size
    x = w - round(h * right_inset)
    length = 0
    for y in range(int(h * .15), int(h * .93)):
        r, g, b = image.getpixel((x, y))
        if 35 <= r <= 60 and 70 <= g <= 100 and 95 <= b <= 130:
            length += 1
            if length >= h * .12:
                return (y - length + 1) / h
        else:
            length = 0
    return 1.0


def check_button_scroll(directory):
    top = wait_screen(directory, "creator", lambda frame: .19 < thumb_top(frame, .026) < .24)
    initial_position = thumb_top(top, .026)
    h = top.height
    # Start on the outfit selector. Its popup used to capture the initial press.
    x = round(h * .66)
    shell("input", "swipe", x, round(h * .81), x, round(h * .37), 450)
    wait_screen(directory, "swipe-on-option", lambda frame: .25 < thumb_top(frame, .026) < .40)
    # The newly revealed Random Appearance button must scroll back without rerolling.
    x = round(h * .20)
    shell("input", "swipe", x, round(h * .85), x, round(h * .98), 400)
    restored = wait_screen(directory, "swipe-on-button", lambda frame: thumb_top(frame, .026) == initial_position)
    portrait = tuple(round(h * edge) for edge in (.15, .275, .29, .43))
    assert top.crop(portrait).tobytes() == restored.crop(portrait).tobytes(), "Drag activated the button"
    print("Dragged from an option and a button in both directions; portrait unchanged", flush=True)


def check_market_scroll(directory, w, h):
    # Open the warehouse from the station briefing.
    shell("input", "tap", w - round(h * .56), round(h * .31))
    at_top = lambda frame: at_port(frame) and .15 <= thumb_top(frame, .043) < .21
    wait_screen(directory, "warehouse", at_top)
    x = w - round(h * .08)
    shell("input", "swipe", x, round(h * .75), x, round(h * .25), 450)
    wait_screen(directory, "warehouse-swiped", lambda frame: at_port(frame) and .30 < thumb_top(frame, .043) < .80)
    shell("input", "swipe", x, round(h * .31), x, round(h * .91), 450)
    wait_screen(directory, "warehouse-restored", at_top)
    shell("input", "tap", x, round(h * .75))
    # The quick quote dialog covers the HUD and draws its top border at 14.5% height.
    def quote_open(frame):
        return not at_port(frame) and any(
            all(frame.getpixel((round(w * f), y)) == (72, 96, 114) for f in (.30, .50, .70))
            for y in range(round(h * .145) - 2, round(h * .145) + 3))
    wait_screen(directory, "warehouse-quote", quote_open)
    print("Warehouse trade button scrolled the list; a separate tap opened the quote", flush=True)


def exercise(tag, candidate):
    directory = RESULTS / tag
    directory.mkdir(exist_ok=True)
    adb("install", "-r", Path("downloads") / tag / "StarrailLegacy-Android.apk")
    shell("am", "force-stop", PACKAGE)
    adb("logcat", "-c")
    try:
        start()
        image = wait_screen(directory, "title", primary_button)
        pid = shell("pidof", PACKAGE)
        assert pid.isdigit(), "No game process at title"
        since = time.monotonic()
        for second in ([10, 30, 120] if candidate else [10, 45]):
            time.sleep(max(0, second-(time.monotonic()-since)))
            check_foreground(pid)
            image = screenshot(directory, f"idle-{second}s")
            if not primary_button(image) and dismiss_launcher_anr(image):
                image = screenshot(directory, f"idle-{second}s")
            assert primary_button(image), f"Title disappeared at {second}s"
            print(tag, "title in foreground", second, "seconds, pid", pid)
        if candidate:
            w, h = image.size
            shell("input", "tap", w - int(h*.24), int(h*.94))
            wait_screen(directory, "exit-report", report_visible)
            # Restart to exercise a second cold launch before entering the campaign.
            shell("am", "force-stop", PACKAGE)
            start()
            image = wait_screen(directory, "second-launch", primary_button)
            pid = shell("pidof", PACKAGE)
            shell("input", "tap", *primary_button(image))
            check_button_scroll(directory)
            shell("input", "tap", int(h*.11), int(h*.92))
            observe_port(directory, "new-campaign", pid)
            # New Game writes an arrival save. Continue must load it in a fresh process.
            shell("am", "force-stop", PACKAGE)
            start()
            image = wait_screen(directory, "title-with-save", primary_button)
            pid = shell("pidof", PACKAGE)
            shell("input", "tap", *primary_button(image))
            observe_port(directory, "continued-campaign", pid)
            check_market_scroll(directory, w, h)
    finally:
        logs = adb("logcat", "-d")
        (directory / "logcat.txt").write_bytes(logs)
        (directory / "exit-info.txt").write_text(shell("dumpsys","activity","exit-info",PACKAGE))
    if candidate:
        assert b"SCRIPT ERROR:" not in logs, "Godot script error; see logcat"
        assert ("ANR in "+PACKAGE).encode() not in logs, "Game ANR; see logcat"


def main():
    sdk = shell("getprop", "ro.build.version.sdk")
    assert sdk == "36", f"Expected Android 16, found API {sdk}"
    (RESULTS / "device.txt").write_text("\n".join([
        "API "+sdk, shell("getprop","ro.build.fingerprint"),
        "ABIs "+shell("getprop","ro.product.cpu.abilist"), shell("wm", "size"),
        "page size "+shell("getconf","PAGE_SIZE")]))
    if os.environ.get("BASELINE"):
        try:
            exercise(os.environ["BASELINE"], False)
        except (RuntimeError, AssertionError, subprocess.SubprocessError) as e:
            print("Baseline failed:",e,flush=True)
    exercise(os.environ["RELEASE"], True)


if __name__ == "__main__":
    main()
