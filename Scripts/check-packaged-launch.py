#!/usr/bin/env python3
"""Check every bundled loader path and run a hardware-free native launch probe."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys


def check(app: Path) -> None:
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    binary = app / "Contents/MacOS" / info["CFBundleExecutable"]
    architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(binary)], text=True).split()
    for architecture in architectures:
        commands = subprocess.check_output(["/usr/bin/otool", "-arch", architecture, "-l", str(binary)], text=True)
        rpaths = []
        for command in commands.split("Load command ")[1:]:
            lines = [line.strip() for line in command.splitlines()]
            if "cmd LC_RPATH" in lines:
                rpaths.extend(line.split(" (offset ", 1)[0][5:] for line in lines if line.startswith("path "))
        if "@executable_path/../Frameworks" not in rpaths:
            raise RuntimeError(f"{architecture}: packaged executable cannot find Contents/Frameworks")

    # Never let a runner's DYLD settings hide an incomplete application bundle.
    environment = {key: value for key, value in os.environ.items() if not key.startswith("DYLD_")}
    result = subprocess.run([str(binary), "--check-packaged-launch"], env=environment,
                            capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise RuntimeError(f"packaged launch failed ({result.returncode}): {result.stderr.strip()}")
    expected = {"packagedLaunch": "ok", "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"]}
    if json.loads(result.stdout) != expected:
        raise RuntimeError("packaged launch returned the wrong version or build")
    print(json.dumps({**expected, "architectures": architectures}, sort_keys=True))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: check-packaged-launch.py /path/to/AgenticMouse.app")
    try:
        check(Path(sys.argv[1]).resolve(strict=True))
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(f"error: {error}")
