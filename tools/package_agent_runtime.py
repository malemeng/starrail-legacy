"""Build the Windows release's tools directory using 64-bit CPython 3.14."""

import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import sysconfig
import tempfile
import urllib.request
from zipfile import ZipFile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tools_dir", type=Path, help="tools directory in the release staging area")
    args = parser.parse_args()
    if sysconfig.get_platform() != "win-amd64" or sys.version_info[:2] != (3, 14):
        parser.error("Build the cp314 Windows wheels with 64-bit CPython 3.14.")
    args.tools_dir.mkdir(parents=True, exist_ok=True)
    destination = args.tools_dir / "agent-runtime"
    if destination.exists():
        parser.error("Build in a fresh staging directory so older wheels cannot enter the release.")
    with tempfile.TemporaryDirectory(dir=args.tools_dir) as temp:
        staging = Path(temp)
        archive = staging / "python.zip"
        release = "3.14.7"
        url = f"https://www.python.org/ftp/python/{release}/python-{release}-embed-amd64.zip"
        urllib.request.urlretrieve(url, archive)
        runtime = staging / "runtime"
        with ZipFile(archive) as bundle:
            bundle.extractall(runtime)
        (runtime / ".gdignore").touch()
        subprocess.run(
            [sys.executable, "-m", "pip", "install", "--only-binary=:all:", "--no-compile",
             "--target", str(runtime / "packages"), "smolagents==1.26.0", "openai==3.57.0"],
            check=True,
        )
        (runtime / "python314._pth").write_text("python314.zip\n.\npackages\n", encoding="ascii")
        runner = Path(__file__).with_name("smolagents_runner.py")
        subprocess.run([str(runtime / "python.exe"), "-B", str(runner), "--help"], check=True)
        shutil.copy2(runner, args.tools_dir / runner.name)
        runtime.rename(destination)


if __name__ == "__main__":
    main()
