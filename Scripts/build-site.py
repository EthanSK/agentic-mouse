#!/usr/bin/env python3
"""Build the Pages artifact from Swift source; never install or contact the native app."""

import hashlib
import html
import json
from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / ".build" / "site"


def build():
    raw = subprocess.check_output(["swift", "run", "agentic-mouse-site"], cwd=ROOT)
    data = json.loads(raw)
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    data["revision"] = revision
    raw = (json.dumps(data, sort_keys=True, ensure_ascii=False, separators=(",", ":")) + "\n").encode()
    files = [item for item in (ROOT / "docs").rglob("*") if item.is_file() and not item.is_symlink() and item.suffix in {".html", ".css", ".js", ".mjs", ".svg", ".webp", ".png", ".jpg", ".ico", ".webmanifest", ".xml", ".txt", ".glb", ".wasm"}]
    digest = hashlib.sha256(raw)
    for item in sorted(files):
        digest.update(str(item.relative_to(ROOT / "docs")).encode())
        digest.update(item.read_bytes())
    version = digest.hexdigest()[:16]
    if OUTPUT.is_symlink():
        raise RuntimeError("Refusing a symlinked site output directory")
    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)  # Only this command's disposable artifact is replaced; Swift products and source files remain untouched.
    OUTPUT.mkdir(parents=True)
    for item in files:
        destination = OUTPUT / item.relative_to(ROOT / "docs")
        destination.parent.mkdir(parents=True, exist_ok=True)
        if item.suffix in {".html", ".js", ".mjs", ".css"}:
            destination.write_text(item.read_text().replace("__SITE_VERSION__", version))
        else:
            shutil.copyfile(item, destination)
    (OUTPUT / "simulator-data.json").write_bytes(raw)
    (OUTPUT / ".nojekyll").touch()
    (OUTPUT / "mouse-map.html").write_text(full_map(data, version))  # Both public views use this native export; do not restore a second hand-written map. (Codex task: 01a06ee5-4aa0-7a61-a029-704e5c44a8f2)
    print(f"Built {OUTPUT} · {len(data['apps'])} apps · source {revision[:7]} · assets {version}")


def full_map(data, version):
    """Generate a readable, no-JavaScript reference alongside the interactive walkthrough."""
    sections = []
    for hand, source in data["sources"].items():
        modes = []
        for name, mode in source["modes"].items():
            if name == "unsupported":
                continue
            rows = []
            for control in mode["controls"]:
                destination = source["modes"].get(control.get("next"), {}).get("title", "")
                wheel = control.get("wheel")
                detail = f"Opens {destination}" if destination else ""
                if wheel:
                    detail = f"Wheel up: {wheel.get('up') or 'No action'}. Wheel down: {wheel.get('down') or 'No action'}."
                if control.get("reportedBroken"):
                    detail += " Reported physical issue."
                rows.append(f"<tr><th>{control['printed']}</th><td>{html.escape(control['title'])}</td><td>{html.escape(detail)}</td></tr>")
            modes.append(f"<details><summary>{html.escape(mode['title'])}</summary><table><thead><tr><th>Button</th><th>Action</th><th>Gesture</th></tr></thead><tbody>{''.join(rows)}</tbody></table></details>")
        sections.append(f"<section><h2>{hand.title()}</h2>{''.join(modes)}</section>")
    return ((ROOT / "docs" / "mouse-map.html").read_text()
            .replace("__SITE_VERSION__", version)
            .replace("__MAP_SECTIONS__", "".join(sections))
            .replace("__SOURCE_REVISION__", data["revision"])
            .replace("__SHORT_REVISION__", data["revision"][:7]))


if __name__ == "__main__":
    build()
