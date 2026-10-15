#!/usr/bin/env python3
"""Bind a signed local candidate to its source checkout and installed parent.

This is a foreground packaging/install gate, never a background synchronizer.
The private checkout path stays inside the locally signed app, not in Git.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess

MANIFEST = Path("Contents/Resources/BuildProvenance.json")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None


def source_digest(repo):
    paths = []
    for name in ("Sources", "Scripts", "Tests", "Karabiner/actions", "Karabiner/bindings"):
        folder = repo / name
        if folder.exists():
            paths.extend(p for p in folder.rglob("*") if p.is_file()
                         and "__pycache__" not in p.parts and p.suffix != ".pyc")
    paths.extend(p for name in ("Package.swift", "Package.resolved", "Makefile")
                 if (p := repo / name).is_file())
    result = hashlib.sha256()
    for path in sorted(paths):
        result.update(str(path.relative_to(repo)).encode() + b"\0")
        result.update(path.read_bytes() + b"\0")
    return result.hexdigest()


def version(app):
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    return tuple(map(int, info["CFBundleShortVersionString"].split("."))), int(info["CFBundleVersion"])


def prepare(repo, installed, marketing, build):
    repo = repo.resolve()
    if installed.exists():
        current_version, current_build = version(installed)
        if tuple(map(int, marketing.split("."))) <= current_version or build <= current_build:
            raise ValueError("candidate must advance both versions beyond the installed app")
        if (installed / MANIFEST).exists():
            previous = json.loads((installed / MANIFEST).read_text())
            if Path(previous["sourceRoot"]).resolve() != repo:
                raise ValueError("different source checkout: reconcile into the installed app's sourceRoot before packaging")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
    return {"schemaVersion": 1, "sourceRoot": str(repo), "gitHead": head,
            "sourceTreeSHA256": source_digest(repo), "marketingVersion": marketing,
            "buildVersion": build,
            "parentExecutableSHA256": digest(installed / "Contents/MacOS/AgenticMouse")}


def check_source(manifest):
    if source_digest(Path(manifest["sourceRoot"])) != manifest["sourceTreeSHA256"]:
        raise ValueError("source changed during packaging; discard candidate and rebuild")


def verify(candidate, installed):
    manifest = json.loads((candidate / MANIFEST).read_text())
    if manifest["schemaVersion"] != 1:
        raise ValueError("unsupported build provenance")
    if digest(installed / "Contents/MacOS/AgenticMouse") != manifest["parentExecutableSHA256"]:
        raise ValueError("installed app changed since packaging; discard candidate and reconcile before rebuilding")
    expected = prepare(Path(manifest["sourceRoot"]), installed,
                       manifest["marketingVersion"], manifest["buildVersion"])
    if version(candidate) != (tuple(map(int, manifest["marketingVersion"].split("."))), manifest["buildVersion"]):
        raise ValueError("candidate version differs from its signed provenance")
    if expected != manifest:
        raise ValueError("candidate source differs from the current checkout; rebuild")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["prepare", "check-source", "verify"])
    parser.add_argument("--repo", type=Path)
    parser.add_argument("--installed", type=Path, default=Path("/Applications/AgenticMouse.app"))
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--marketing")
    parser.add_argument("--build", type=int)
    args = parser.parse_args()
    try:
        if args.operation == "prepare":
            args.manifest.write_text(json.dumps(prepare(args.repo, args.installed, args.marketing, args.build), indent=2) + "\n")
        elif args.operation == "check-source":
            check_source(json.loads(args.manifest.read_text()))
        else:
            verify(args.candidate, args.installed)
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(65, f"install provenance refused: {error}\n")


if __name__ == "__main__":
    main()
