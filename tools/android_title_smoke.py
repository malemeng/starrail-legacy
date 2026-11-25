"""Check the published game on an already booted, isolated Android 16 emulator."""

from io import BytesIO
import os
from pathlib import Path
import subprocess
import time

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
            if all(gold(x, y) for x in (.19, .24, .31))]
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


def wait_screen(directory, name, matches):
    deadline = time.monotonic()+65
    while time.monotonic() < deadline:
        image = screenshot(directory, name)
        if matches(image):
            return image
        time.sleep(1)
    raise RuntimeError(f"Did not reach {name}")


def start():
    shell("am", "start", "-W", "-n", ACTIVITY)


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
            assert shell("pidof", PACKAGE) == pid, f"Process changed at {second}s"
            focus = shell("dumpsys", "activity", "activities")
            assert any(PACKAGE in line and ("topResumedActivity" in line or "mResumedActivity" in line)
                       for line in focus.splitlines()), "Lost foreground"
            image = screenshot(directory, f"idle-{second}s")
            assert primary_button(image), f"Title disappeared at {second}s"
            print(tag, "title in foreground", second, "seconds, pid", pid)
        if candidate:
            w, h = image.size
            shell("input", "tap", int(w*.865), int(h*.94))
            wait_screen(directory, "exit-report", report_visible)
            # Restart to exercise a second cold launch before entering the campaign.
            shell("am", "force-stop", PACKAGE)
            start()
            image = wait_screen(directory, "second-launch", primary_button)
            shell("input", "tap", *primary_button(image))
            wait_screen(directory, "creator", lambda frame: not primary_button(frame) and frame.getextrema()[1][1] > 150)
            time.sleep(1)
            shell("input", "tap", int(w*.065), int(h*.92))
            wait_screen(directory, "campaign", at_port)
            print(tag, "character creation and campaign reached")
    finally:
        logs = adb("logcat", "-d")
        (directory / "logcat.txt").write_bytes(logs)
        (directory / "exit-info.txt").write_text(shell("dumpsys","activity","exit-info",PACKAGE))
    if candidate:
        assert b"SCRIPT ERROR:" not in logs, "Godot script error; see logcat"


def main():
    sdk = shell("getprop", "ro.build.version.sdk")
    assert sdk == "36", f"Expected Android 16, found API {sdk}"
    (RESULTS / "device.txt").write_text("\n".join([
        "API "+sdk, shell("getprop","ro.build.fingerprint"),
        shell("getprop","ro.product.cpu.abi"), "page size "+shell("getconf","PAGE_SIZE")]))
    if os.environ.get("BASELINE"):
        try:
            exercise(os.environ["BASELINE"], False)
        except (RuntimeError, AssertionError, subprocess.SubprocessError) as e:
            print("Baseline failed:",e,flush=True)
    exercise(os.environ["RELEASE"], True)


if __name__ == "__main__":
    main()
