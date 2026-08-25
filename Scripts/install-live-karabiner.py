#!/usr/bin/env python3
"""Replace only the selected profile's contiguous Agentic Mouse rule block."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import tempfile
import time


PREFIX = "Agentic Mouse — "
RUNTIME_MODES_DESCRIPTION = "Agentic Mouse — Modes (expiring, exact-device)"
MOUSE_SOURCES = ("corsair", "razer")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def agentic(rule: object) -> bool:
    return (
        isinstance(rule, dict)
        and isinstance(rule.get("description"), str)
        and rule["description"].startswith(PREFIX)
    )


def selected_rules(document: dict) -> list[dict]:
    profiles = [profile for profile in document.get("profiles", []) if profile.get("selected")]
    if len(profiles) != 1:
        raise ValueError(f"expected one selected profile, found {len(profiles)}")
    rules = profiles[0].get("complex_modifications", {}).get("rules")
    if not isinstance(rules, list):
        raise ValueError("selected profile has no complex-modification rule list")
    return rules


def close_runtime_modes() -> None:
    socket_path = Path(
        f"/Library/Application Support/org.pqrs/tmp/user/{os.geteuid()}/"
        "user_command_receiver.sock"
    )
    if not socket_path.exists():
        raise RuntimeError("Agentic Mouse must own its command socket before a live reload")
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as command_socket:
        for source in MOUSE_SOURCES:
            command_socket.sendto(
                json.dumps(
                    {
                        "command": "agentic_mouse_mode_picker",
                        "action": "close",
                        "source": source,
                        "physical_cell": 10,
                        "phase": "press",
                    },
                    separators=(",", ":"),
                ).encode(),
                str(socket_path),
            )
    time.sleep(0.1)  # A Karabiner reload can erase the lease while its HUD is still open, so close both app coordinators even when no lease remains. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)
    print(f"closed Agentic Mouse runtime modes before reload: {', '.join(MOUSE_SOURCES)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--live", type=Path, required=True)
    parser.add_argument("--generated", type=Path, required=True)
    parser.add_argument("--expected-live-sha256", required=True)
    parser.add_argument("--backup", type=Path, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()

    actual_before = sha256(args.live)
    if actual_before != args.expected_live_sha256:
        raise SystemExit(
            f"live Karabiner changed: expected {args.expected_live_sha256}, got {actual_before}"
        )

    live = json.loads(args.live.read_text())
    generated = json.loads(args.generated.read_text())
    generated_rules = generated.get("rules")
    if not isinstance(generated_rules, list) or not generated_rules:
        raise SystemExit("generated runtime contains no rules")
    if not all(agentic(rule) for rule in generated_rules):
        raise SystemExit("generated runtime contains a non-Agentic rule")
    if sum(rule.get("description") == RUNTIME_MODES_DESCRIPTION for rule in generated_rules) != 1:
        raise SystemExit(
            "generated candidate must contain exactly one runtime Modes rule; "
            "use Karabiner/generated/agentic-mouse-runtime.json"
        )

    rules = selected_rules(live)
    indices = [index for index, rule in enumerate(rules) if agentic(rule)]
    if not indices:
        raise SystemExit("selected profile contains no existing Agentic Mouse block")
    expected_indices = list(range(indices[0], indices[-1] + 1))
    if indices != expected_indices:
        raise SystemExit("existing Agentic Mouse rules are not one contiguous block")

    non_agentic_before = [rule for rule in rules if not agentic(rule)]
    rules[indices[0] : indices[-1] + 1] = generated_rules
    if [rule for rule in rules if not agentic(rule)] != non_agentic_before:
        raise SystemExit("candidate changed a non-Agentic rule")

    print(
        f"candidate replaces {len(indices)} Agentic rules with {len(generated_rules)}; "
        f"preserves {len(non_agentic_before)} non-Agentic rules"
    )
    if not args.apply:
        print("dry run only")
        return 0
    if args.backup.exists():
        raise SystemExit(f"refusing to overwrite backup: {args.backup}")

    close_runtime_modes()
    args.backup.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.live, args.backup)
    mode = args.live.stat().st_mode
    serialized = json.dumps(live, indent=4, ensure_ascii=False) + "\n"
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=".agentic-mouse-karabiner-",
        suffix=".json",
        dir=args.live.parent,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(serialized)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, mode)
        if sha256(args.live) != args.expected_live_sha256:
            raise SystemExit("live Karabiner changed during candidate construction")
        os.replace(temporary, args.live)
    finally:
        temporary.unlink(missing_ok=True)

    print(f"before={actual_before}")
    print(f"after={sha256(args.live)}")
    print(f"backup={args.backup}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
