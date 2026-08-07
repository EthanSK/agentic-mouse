#!/usr/bin/env python3
"""Build Karabiner complex modifications from named semantic action sources."""

from __future__ import annotations

import argparse
import copy
import json
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ACTIONS = ROOT / "Karabiner" / "actions"
DEFAULT_BINDINGS = ROOT / "Karabiner" / "bindings" / "bindings.json"
DEFAULT_OUTPUT = ROOT / "Karabiner" / "generated" / "agentic-mouse.json"
DEFAULT_CATALOG = ROOT / "Karabiner" / "generated" / "action-catalog.json"

ACTION_ID = re.compile(r"^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$")
OUTPUT_FIELDS = {
    "to",
    "to_after_key_up",
    "to_delayed_action",
    "to_if_alone",
    "to_if_held_down",
}
FORBIDDEN_ACTION_FIELDS = {"from", "type", "manipulators"}


class GenerationError(ValueError):
    """Raised when a source file cannot safely produce a Karabiner rule."""


def _json_text(value: Any) -> str:
    return json.dumps(value, indent=2, ensure_ascii=False) + "\n"


def _load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise GenerationError(f"missing file: {path}") from error
    except json.JSONDecodeError as error:
        raise GenerationError(f"invalid JSON in {path}: {error}") from error


def _load_action(path: Path, actions_root: Path) -> dict[str, Any]:
    text = path.read_text(encoding="utf-8")
    first_content = next((line.strip() for line in text.splitlines() if line.strip()), "")
    if not first_content.startswith("//"):
        raise GenerationError(f"{path}: first content line must be a behavior comment")

    json_lines = [
        line for line in text.splitlines() if not line.lstrip().startswith("//")
    ]
    try:
        action = json.loads("\n".join(json_lines))
    except json.JSONDecodeError as error:
        raise GenerationError(f"invalid JSONC in {path}: {error}") from error

    if not isinstance(action, dict):
        raise GenerationError(f"{path}: action must be an object")
    for field in ("id", "title", "description", "manipulator"):
        if field not in action:
            raise GenerationError(f"{path}: missing {field}")

    action_id = action["id"]
    if not isinstance(action_id, str) or not ACTION_ID.fullmatch(action_id):
        raise GenerationError(f"{path}: invalid action id {action_id!r}")
    if path.stem != action_id:
        raise GenerationError(
            f"{path}: filename must match action id ({action_id}.jsonc)"
        )
    if not isinstance(action["title"], str) or not action["title"].strip():
        raise GenerationError(f"{path}: title must be non-empty")
    if not isinstance(action["description"], str) or not action["description"].strip():
        raise GenerationError(f"{path}: description must be non-empty")

    manipulator = action["manipulator"]
    if not isinstance(manipulator, dict):
        raise GenerationError(f"{path}: manipulator must be an object")
    forbidden = FORBIDDEN_ACTION_FIELDS.intersection(manipulator)
    if forbidden:
        raise GenerationError(
            f"{path}: semantic actions cannot contain binding fields {sorted(forbidden)}"
        )
    if not OUTPUT_FIELDS.intersection(manipulator):
        raise GenerationError(f"{path}: manipulator has no output field")
    if "conditions" in manipulator and not isinstance(manipulator["conditions"], list):
        raise GenerationError(f"{path}: conditions must be an array")
    if "parameters" in manipulator and not isinstance(manipulator["parameters"], dict):
        raise GenerationError(f"{path}: parameters must be an object")

    action["source"] = path.relative_to(actions_root).as_posix()
    return action


def load_actions(actions_root: Path) -> dict[str, dict[str, Any]]:
    paths = sorted(actions_root.rglob("*.jsonc"))
    if not paths:
        raise GenerationError(f"no action sources found under {actions_root}")

    actions: dict[str, dict[str, Any]] = {}
    for path in paths:
        action = _load_action(path, actions_root)
        action_id = action["id"]
        if action_id in actions:
            raise GenerationError(f"duplicate action id: {action_id}")
        actions[action_id] = action
    return actions


def load_bindings(path: Path) -> list[dict[str, Any]]:
    document = _load_json(path)
    if not isinstance(document, dict) or document.get("schemaVersion") != 1:
        raise GenerationError(f"{path}: schemaVersion must be 1")
    bindings = document.get("bindings")
    if not isinstance(bindings, list):
        raise GenerationError(f"{path}: bindings must be an array")

    seen: set[str] = set()
    for binding in bindings:
        if not isinstance(binding, dict):
            raise GenerationError(f"{path}: every binding must be an object")
        for field in ("id", "description", "action", "from"):
            if field not in binding:
                raise GenerationError(f"{path}: binding is missing {field}")
        binding_id = binding["id"]
        if not isinstance(binding_id, str) or not ACTION_ID.fullmatch(binding_id):
            raise GenerationError(f"{path}: invalid binding id {binding_id!r}")
        if binding_id in seen:
            raise GenerationError(f"{path}: duplicate binding id {binding_id}")
        seen.add(binding_id)
        if not isinstance(binding["description"], str) or not binding["description"].strip():
            raise GenerationError(f"{path}: {binding_id} needs a description")
        if not isinstance(binding["action"], str):
            raise GenerationError(f"{path}: {binding_id} action must be a string")
        if not isinstance(binding["from"], dict) or not binding["from"]:
            raise GenerationError(f"{path}: {binding_id} from must be a non-empty object")
        if "conditions" in binding and not isinstance(binding["conditions"], list):
            raise GenerationError(f"{path}: {binding_id} conditions must be an array")
        conditions = binding.get("conditions", [])
        device_conditions = [
            condition
            for condition in conditions
            if isinstance(condition, dict) and condition.get("type") == "device_if"
        ]
        if not device_conditions:
            raise GenerationError(
                f"{path}: {binding_id} must include an exact device_if condition"
            )
        for condition in device_conditions:
            identifiers = condition.get("identifiers")
            if not isinstance(identifiers, list) or not identifiers:
                raise GenerationError(
                    f"{path}: {binding_id} device_if needs at least one identifier"
                )
            for identifier in identifiers:
                if not isinstance(identifier, dict):
                    raise GenerationError(
                        f"{path}: {binding_id} device identifier must be an object"
                    )
                if not isinstance(identifier.get("vendor_id"), int) or not isinstance(
                    identifier.get("product_id"), int
                ):
                    raise GenerationError(
                        f"{path}: {binding_id} device identifier needs integer vendor_id and product_id"
                    )
                if "device_address" in identifier:
                    raise GenerationError(
                        f"{path}: {binding_id} must not commit a private device_address"
                    )
        if "parameters" in binding and not isinstance(binding["parameters"], dict):
            raise GenerationError(f"{path}: {binding_id} parameters must be an object")
        if "rule" in binding and not isinstance(binding["rule"], str):
            raise GenerationError(f"{path}: {binding_id} rule must be a string")
    return bindings


def build_documents(
    actions: dict[str, dict[str, Any]], bindings: list[dict[str, Any]]
) -> tuple[dict[str, Any], dict[str, Any]]:
    grouped: dict[str, list[tuple[str, dict[str, Any]]]] = defaultdict(list)

    for binding in bindings:
        action_id = binding["action"]
        action = actions.get(action_id)
        if action is None:
            raise GenerationError(
                f"binding {binding['id']} references unknown action {action_id}"
            )

        template = copy.deepcopy(action["manipulator"])
        action_conditions = template.pop("conditions", [])
        action_parameters = template.pop("parameters", {})

        manipulator: dict[str, Any] = {
            "type": "basic",
            "from": copy.deepcopy(binding["from"]),
            **template,
        }
        conditions = action_conditions + copy.deepcopy(binding.get("conditions", []))
        if conditions:
            manipulator["conditions"] = conditions
        parameters = {**action_parameters, **copy.deepcopy(binding.get("parameters", {}))}
        if parameters:
            manipulator["parameters"] = parameters

        rule_name = binding.get("rule", "Base layer")
        grouped[rule_name].append((binding["id"], manipulator))

    rules = []
    for rule_name in sorted(grouped):
        manipulators = [
            manipulator for _, manipulator in sorted(grouped[rule_name], key=lambda pair: pair[0])
        ]
        rules.append(
            {
                "description": f"Agentic Mouse — {rule_name}",
                "manipulators": manipulators,
            }
        )

    karabiner = {
        "title": "Agentic Mouse — generated semantic bindings",
        "rules": rules,
    }
    catalog = {
        "schemaVersion": 1,
        "actions": [
            {
                "id": action["id"],
                "title": action["title"],
                "description": action["description"],
                "source": action["source"],
                "manipulator": action["manipulator"],
            }
            for action in sorted(actions.values(), key=lambda item: item["id"])
        ],
    }
    return karabiner, catalog


def _write_or_check(path: Path, content: str, check: bool) -> None:
    if check:
        if not path.exists() or path.read_text(encoding="utf-8") != content:
            raise GenerationError(
                f"generated artifact is stale: {path}; run Scripts/generate-karabiner.py"
            )
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--actions-dir", type=Path, default=DEFAULT_ACTIONS)
    parser.add_argument("--bindings", type=Path, default=DEFAULT_BINDINGS)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--catalog-output", type=Path, default=DEFAULT_CATALOG)
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail if committed generated artifacts differ from their sources",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        actions = load_actions(args.actions_dir)
        bindings = load_bindings(args.bindings)
        karabiner, catalog = build_documents(actions, bindings)
        _write_or_check(args.output, _json_text(karabiner), args.check)
        _write_or_check(args.catalog_output, _json_text(catalog), args.check)
    except (GenerationError, OSError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    verb = "checked" if args.check else "generated"
    print(
        f"{verb} {len(actions)} semantic actions and {len(bindings)} physical bindings"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
