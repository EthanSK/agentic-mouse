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
DEFAULT_RUNTIME_OUTPUT = (
    ROOT / "Karabiner" / "generated" / "agentic-mouse-runtime.json"
)
DEFAULT_CATALOG = ROOT / "Karabiner" / "generated" / "action-catalog.json"

ACTION_ID = re.compile(r"^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$")
VARIABLE_NAME = re.compile(r"^[a-z][a-z0-9_]*$")
MAXIMUM_LEASE_WINDOW_MILLISECONDS = 15_000
MODE_PAGE_UTILITY = 1
MODE_PAGE_KEYS = 2
MODE_PAGE_APP_SELECTOR = 3
MODE_PAGE_APP_SPECIFIC = 4
MODE_PAGE_KEYPAD = 5
APP_SELECTOR_TARGET_CELLS = {1, 4, 7}
KEYS_MODE_OUTPUT_BY_PHYSICAL_CELL = {
    1: {"key_code": "left_arrow", "repeat": False},
    3: {"key_code": "z", "modifiers": ["left_command"], "repeat": False},
    4: {"key_code": "down_arrow", "repeat": False},
    5: {"key_code": "up_arrow", "repeat": False},
    7: {"key_code": "right_arrow", "repeat": False},
    8: {"key_code": "spacebar", "repeat": False},
    9: {"consumer_key_code": "scan_next_track", "repeat": False},
    11: {"key_code": "delete_or_backspace", "repeat": False},
    12: {"key_code": "return_or_enter", "repeat": False},
}
RAZER_KEYS_MODE_OUTPUT_OVERRIDES = {
    1: {"key_code": "right_arrow", "repeat": False},
    7: {"key_code": "left_arrow", "repeat": False},
}
OUTPUT_FIELDS = {
    "to",
    "to_after_key_up",
    "to_delayed_action",
    "to_if_alone",
    "to_if_held_down",
}
EXTERNAL_OUTPUT_FIELDS = {
    "consumer_key_code",
    "key_code",
    "mouse_key",
    "pointing_button",
    "select_input_source",
    "send_user_command",
    "shell_command",
    "software_function",
    "sticky_modifier",
}
FORBIDDEN_ACTION_FIELDS = {"from", "type", "manipulator", "manipulators"}
BINDING_VARIABLE_PLACEHOLDER = "$binding_variable"


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
    for field in ("id", "title", "description"):
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

    has_single = "manipulator" in action
    has_multiple = "manipulators" in action
    if has_single == has_multiple:
        raise GenerationError(f"{path}: provide exactly one of manipulator or manipulators")
    templates = [action["manipulator"]] if has_single else action["manipulators"]
    if not isinstance(templates, list) or not templates:
        raise GenerationError(f"{path}: manipulators must be a non-empty array")
    for index, manipulator in enumerate(templates):
        if not isinstance(manipulator, dict):
            raise GenerationError(f"{path}: manipulator {index} must be an object")
        forbidden = FORBIDDEN_ACTION_FIELDS.intersection(manipulator)
        if forbidden:
            raise GenerationError(
                f"{path}: semantic actions cannot contain binding fields {sorted(forbidden)}"
            )
        if not OUTPUT_FIELDS.intersection(manipulator):
            raise GenerationError(f"{path}: manipulator {index} has no output field")
        if "conditions" in manipulator and not isinstance(manipulator["conditions"], list):
            raise GenerationError(f"{path}: manipulator {index} conditions must be an array")
        if "parameters" in manipulator and not isinstance(manipulator["parameters"], dict):
            raise GenerationError(f"{path}: manipulator {index} parameters must be an object")

    action["_manipulator_templates"] = templates

    action["source"] = path.relative_to(actions_root).as_posix()
    return action


def _expand_binding_placeholders(value: Any, binding_id: str) -> Any:
    """Give multi-manipulator actions isolated Karabiner state per physical binding."""
    variable = f"agentic_mouse_{binding_id.replace('-', '_')}_pending"
    if isinstance(value, str):
        return variable if value == BINDING_VARIABLE_PLACEHOLDER else value
    if isinstance(value, list):
        return [_expand_binding_placeholders(item, binding_id) for item in value]
    if isinstance(value, dict):
        return {
            key: _expand_binding_placeholders(item, binding_id)
            for key, item in value.items()
        }
    return value


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


def load_bindings(
    path: Path,
) -> tuple[
    list[dict[str, Any]],
    dict[str, Any] | None,
    dict[str, Any] | None,
    dict[str, Any] | None,
]:
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
    def validate_mode_metadata(name: str, metadata: Any) -> dict[str, Any] | None:
        if metadata is None:
            return None
        if not isinstance(metadata, dict):
            raise GenerationError(f"{path}: {name} must be an object")
        variables_by_source = metadata.get("leaseVariablesBySource")
        if variables_by_source is None:
            variable = metadata.get("leaseVariable")
            if not isinstance(variable, str) or not VARIABLE_NAME.fullmatch(variable):
                raise GenerationError(f"{path}: {name}.leaseVariable is invalid")
        else:
            if (
                not isinstance(variables_by_source, dict)
                or set(variables_by_source) != {"corsair", "razer"}
                or any(
                    not isinstance(variable, str) or not VARIABLE_NAME.fullmatch(variable)
                    for variable in variables_by_source.values()
                )
                or len(set(variables_by_source.values())) != 2
            ):
                raise GenerationError(
                    f"{path}: {name}.leaseVariablesBySource must contain distinct valid corsair and razer variables"
                )
        bootstrap = metadata.get("bootstrapMilliseconds")
        if not isinstance(bootstrap, int) or not 100 <= bootstrap <= 5_000:
            raise GenerationError(
                f"{path}: {name}.bootstrapMilliseconds must be an integer from 100 to 5000"
            )
        entry_cell = metadata.get("entryPhysicalCell")
        if not isinstance(entry_cell, int) or not 1 <= entry_cell <= 12:
            raise GenerationError(f"{path}: {name}.entryPhysicalCell must be 1...12")
        intercept_cells = metadata.get("interceptPhysicalCells")
        if intercept_cells is not None:
            if (
                not isinstance(intercept_cells, list)
                or not intercept_cells
                or any(not isinstance(cell, int) or not 1 <= cell <= 12 for cell in intercept_cells)
                or len(set(intercept_cells)) != len(intercept_cells)
                or entry_cell not in intercept_cells
            ):
                raise GenerationError(
                    f"{path}: {name}.interceptPhysicalCells must be unique cells 1...12 including the entry cell"
                )
        by_source = metadata.get("bindingsBySource")
        if not isinstance(by_source, dict) or set(by_source) != {"corsair", "razer"}:
            raise GenerationError(
                f"{path}: {name}.bindingsBySource must contain exactly corsair and razer"
            )
        known = {binding["id"]: binding for binding in bindings}
        claimed: set[str] = set()
        for source in ("corsair", "razer"):
            identifiers = by_source[source]
            if not isinstance(identifiers, list) or len(identifiers) != 12:
                raise GenerationError(
                    f"{path}: {name} {source} list must map physical cells 1...12"
                )
            for identifier in identifiers:
                if not isinstance(identifier, str) or identifier not in known:
                    raise GenerationError(
                        f"{path}: {name} references unknown binding {identifier!r}"
                    )
                if not identifier.startswith(f"{source}-side-"):
                    raise GenerationError(
                        f"{path}: {name} {source} references the wrong device binding {identifier}"
                    )
                if identifier in claimed:
                    raise GenerationError(
                        f"{path}: {name} binding {identifier} is mapped more than once"
                    )
                claimed.add(identifier)
        return metadata

    security = document.get("security")
    if security is not None:
        if not isinstance(security, dict):
            raise GenerationError(f"{path}: security must be an object")
        variable = security.get("unlockedLeaseVariable")
        if not isinstance(variable, str) or not VARIABLE_NAME.fullmatch(variable):
            raise GenerationError(f"{path}: security.unlockedLeaseVariable is invalid")
        additional = security.get("additionalLockedSources", [])
        if not isinstance(additional, list):
            raise GenerationError(f"{path}: security.additionalLockedSources must be an array")
        for index, source in enumerate(additional):
            if not isinstance(source, dict) or not isinstance(source.get("from"), dict):
                raise GenerationError(
                    f"{path}: security.additionalLockedSources[{index}] needs from"
                )
            conditions = source.get("conditions")
            if not isinstance(conditions, list) or not any(
                isinstance(condition, dict) and condition.get("type") == "device_if"
                for condition in conditions
            ):
                raise GenerationError(
                    f"{path}: security.additionalLockedSources[{index}] needs exact device_if"
                )

    color_proof = validate_mode_metadata("colorProof", document.get("colorProof"))
    mode_picker = validate_mode_metadata("modePicker", document.get("modePicker"))
    if mode_picker:
        exit_cell = mode_picker.get("exitPhysicalCell")
        if (
            not isinstance(exit_cell, int)
            or not 1 <= exit_cell <= 12
            or exit_cell == mode_picker["entryPhysicalCell"]
            or exit_cell not in mode_picker.get("interceptPhysicalCells", range(1, 13))
        ):
            raise GenerationError(
                f"{path}: modePicker.exitPhysicalCell must be an intercepted cell 1...12 distinct from entryPhysicalCell"
            )
        page_variables = mode_picker.get("pageVariablesBySource")
        if (
            not isinstance(page_variables, dict)
            or set(page_variables) != {"corsair", "razer"}
            or any(
                not isinstance(variable, str) or not VARIABLE_NAME.fullmatch(variable)
                for variable in page_variables.values()
            )
            or len(set(page_variables.values())) != 2
            or set(page_variables.values()) & set(_lease_variables(mode_picker).values())
        ):
            raise GenerationError(
                f"{path}: modePicker.pageVariablesBySource must contain distinct valid corsair and razer variables"
            )
    if color_proof and mode_picker:
        color_variables = set(_lease_variables(color_proof).values())
        picker_variables = set(_lease_variables(mode_picker).values())
        if color_variables & picker_variables:
            raise GenerationError(f"{path}: runtime modes need distinct lease variables")
        if color_proof["bindingsBySource"] != mode_picker["bindingsBySource"]:
            raise GenerationError(f"{path}: runtime modes must share one physical crosswalk")

    return bindings, color_proof, mode_picker, security


def _lease_variables(metadata: dict[str, Any]) -> dict[str, str]:
    variables = metadata.get("leaseVariablesBySource")
    if variables is not None:
        return variables
    return {source: metadata["leaseVariable"] for source in ("corsair", "razer")}


def _page_variables(metadata: dict[str, Any]) -> dict[str, str]:
    return metadata["pageVariablesBySource"]


def _active_expression(variable: str) -> str:
    return (
        f"({variable} > system.now.milliseconds) and "
        f"({variable} <= system.now.milliseconds + {MAXIMUM_LEASE_WINDOW_MILLISECONDS})"
    )


def _guard_external_outputs(value: Any, expression: str) -> None:
    """Re-check the session lease when deferred/release output actually fires."""
    if isinstance(value, list):
        for item in value:
            _guard_external_outputs(item, expression)
        return
    if not isinstance(value, dict):
        return
    if EXTERNAL_OUTPUT_FIELDS.intersection(value):
        condition = {"type": "expression_if", "expression": expression}
        conditions = value.setdefault("conditions", [])
        if condition not in conditions:
            conditions.append(condition)
    for item in value.values():
        _guard_external_outputs(item, expression)


def _secure_rules(rules: list[dict[str, Any]], security: dict[str, Any]) -> None:
    expression = _active_expression(security["unlockedLeaseVariable"])
    condition = {"type": "expression_if", "expression": expression}
    for rule in rules:
        for manipulator in rule["manipulators"]:
            conditions = manipulator.setdefault("conditions", [])
            if condition not in conditions:
                conditions.append(copy.deepcopy(condition))
            for field in OUTPUT_FIELDS:
                if field in manipulator:
                    _guard_external_outputs(manipulator[field], expression)


def _build_locked_transport_sink(
    bindings: list[dict[str, Any]], security: dict[str, Any]
) -> dict[str, Any]:
    expression = _active_expression(security["unlockedLeaseVariable"])
    candidates = [
        {"from": binding["from"], "conditions": binding.get("conditions", [])}
        for binding in bindings
    ] + security.get("additionalLockedSources", [])
    unique: dict[str, dict[str, Any]] = {}
    for candidate in candidates:
        device_conditions = [
            copy.deepcopy(condition)
            for condition in candidate.get("conditions", [])
            if condition.get("type") in {"device_if", "device_unless"}
        ]
        key = json.dumps(
            {"from": candidate["from"], "conditions": device_conditions},
            sort_keys=True,
        )
        unique[key] = {
            "type": "basic",
            "from": copy.deepcopy(candidate["from"]),
            "to": [{"key_code": "vk_none"}],
            "conditions": device_conditions
            + [{"type": "expression_unless", "expression": expression}],
        }
    return {
        "description": "Agentic Mouse — Locked-session transport sink (exact-device)",
        "manipulators": [unique[key] for key in sorted(unique)],
    }


def _any_active_expression(metadata: dict[str, Any]) -> str:
    return " or ".join(
        f"({_active_expression(variable)})"
        for variable in dict.fromkeys(_lease_variables(metadata).values())
    )


def _direct_mode_entry(manipulator: dict[str, Any]) -> tuple[str, str] | None:
    """Return the exact source and page action for a direct mode request."""
    for event in manipulator.get("to", []):
        payload = event.get("send_user_command", {}).get("payload", {})
        if (
            payload.get("command") == "agentic_mouse_mode_picker"
            and payload.get("action") in {"openKeys", "openAppSpecific"}
            and payload.get("source") in {"corsair", "razer"}
        ):
            return payload["source"], payload["action"]
    return None


def build_documents(
    actions: dict[str, dict[str, Any]],
    bindings: list[dict[str, Any]],
    color_proof: dict[str, Any] | None = None,
    mode_picker: dict[str, Any] | None = None,
    security: dict[str, Any] | None = None,
) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    grouped: dict[str, list[tuple[str, dict[str, Any]]]] = defaultdict(list)
    proof_grouped: dict[str, list[tuple[str, dict[str, Any]]]] = defaultdict(list)
    lease_exclusions_by_binding: dict[str, list[str]] = defaultdict(list)
    for metadata in (color_proof, mode_picker):
        if not metadata:
            continue
        intercepted_cells = metadata.get("interceptPhysicalCells", range(1, 13))
        for source, identifiers in metadata["bindingsBySource"].items():
            expression = _active_expression(_lease_variables(metadata)[source])
            for physical_cell in intercepted_cells:
                lease_exclusions_by_binding[identifiers[physical_cell - 1]].append(expression)

    for binding in bindings:
        action_id = binding["action"]
        action = actions.get(action_id)
        if action is None:
            raise GenerationError(
                f"binding {binding['id']} references unknown action {action_id}"
            )

        for index, source_template in enumerate(action["_manipulator_templates"]):
            template = _expand_binding_placeholders(copy.deepcopy(source_template), binding["id"])
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
            sort_id = f"{binding['id']}:{index}"
            grouped[rule_name].append((sort_id, manipulator))
            proof_manipulator = copy.deepcopy(manipulator)
            # Direct top-level entry through physical cells 6 or 2 needs the
            # same fail-closed bootstrap as the cell-12 Utility entry. Without
            # it, a rapid second press can reach the ordinary base before the
            # app receives the command and writes its renewable lease.
            direct_entry = _direct_mode_entry(proof_manipulator)
            if direct_entry is not None and mode_picker is not None:
                direct_source, direct_action = direct_entry
                variable = _lease_variables(mode_picker)[direct_source]
                page_variable = _page_variables(mode_picker)[direct_source]
                proof_manipulator.setdefault("to", []).insert(
                    0,
                    {
                        "set_variable": {
                            "name": variable,
                            "expression": (
                                "system.now.milliseconds + "
                                f'{mode_picker["bootstrapMilliseconds"]}'
                            ),
                        }
                    },
                )
                proof_manipulator["to"].insert(
                    1,
                    {
                        "set_variable": {
                            "name": page_variable,
                            "value": (
                                MODE_PAGE_KEYS
                                if direct_action == "openKeys"
                                else MODE_PAGE_APP_SPECIFIC
                            ),
                        }
                    },
                )
            for expression in lease_exclusions_by_binding.get(binding["id"], []):
                proof_manipulator.setdefault("conditions", []).append(
                    {"type": "expression_unless", "expression": expression}
                )
            proof_grouped[rule_name].append((sort_id, proof_manipulator))

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

    if security:
        _secure_rules(rules, security)
        rules.insert(0, _build_locked_transport_sink(bindings, security))

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
                **(
                    {"manipulator": action["manipulator"]}
                    if "manipulator" in action
                    else {"manipulators": action["manipulators"]}
                ),
            }
            for action in sorted(actions.values(), key=lambda item: item["id"])
        ],
    }
    runtime_rules = (
        ([build_mode_picker_rule(bindings, mode_picker, color_proof)] if mode_picker else [])
        + ([build_color_proof_rule(bindings, color_proof, mode_picker)] if color_proof else [])
        + [
            {
                "description": f"Agentic Mouse — {rule_name}",
                "manipulators": [
                    manipulator
                    for _, manipulator in sorted(
                        proof_grouped[rule_name], key=lambda pair: pair[0]
                    )
                ],
            }
            for rule_name in sorted(proof_grouped)
        ]
        if color_proof or mode_picker
        else []
    )
    if security:
        _secure_rules(runtime_rules, security)
        runtime_rules.insert(0, _build_locked_transport_sink(bindings, security))

    runtime_document = {
        "title": "Agentic Mouse runtime modes — complete exact-device replacement",
        "rules": runtime_rules,
    }
    return karabiner, catalog, runtime_document


def build_color_proof_rule(
    bindings: list[dict[str, Any]],
    color_proof: dict[str, Any],
    mode_picker: dict[str, Any] | None = None,
) -> dict[str, Any]:
    by_id = {binding["id"]: binding for binding in bindings}
    variable = _lease_variables(color_proof)["corsair"]
    active_expression = _active_expression(variable)
    entry_index = color_proof["entryPhysicalCell"] - 1
    picker_expression = None
    if mode_picker:
        picker_expression = _any_active_expression(mode_picker)

    def device_conditions(binding: dict[str, Any], *, active: bool) -> list[dict[str, Any]]:
        # A runtime mode owns physical cells independently of the ordinary
        # app-specific semantic layer. Preserve only hardware attribution;
        # carrying a VS Code if/unless condition here would make the same
        # physical cell disappear inside a mode when the frontmost app changes.
        conditions = [
            copy.deepcopy(condition)
            for condition in binding.get("conditions", [])
            if condition.get("type") in {"device_if", "device_unless"}
        ]
        conditions.append(
            {
                "type": "expression_if" if active else "expression_unless",
                "expression": active_expression,
            }
        )
        if picker_expression:
            conditions.append(
                {"type": "expression_unless", "expression": picker_expression}
            )
        return conditions

    def command_event(action: str, source: str, physical_cell: int) -> dict[str, Any]:
        return {
            "send_user_command": {
                "payload": {
                    "command": "agentic_mouse_color_proof",
                    "action": action,
                    "source": source,
                    "physical_cell": physical_cell,
                }
            },
            "repeat": False,
        }

    manipulators: list[dict[str, Any]] = []

    # Active entry cells exit before the general active-cell selectors.
    for source in ("corsair", "razer"):
        binding = by_id[color_proof["bindingsBySource"][source][entry_index]]
        manipulators.append(
            {
                "type": "basic",
                "from": copy.deepcopy(binding["from"]),
                "to": [
                    {"set_variable": {"name": variable, "value": 0}},
                    command_event("exit", source, entry_index + 1),
                ],
                "conditions": device_conditions(binding, active=True),
            }
        )

    for source in ("corsair", "razer"):
        for index, binding_id in enumerate(color_proof["bindingsBySource"][source]):
            binding = by_id[binding_id]
            manipulators.append(
                {
                    "type": "basic",
                    "from": copy.deepcopy(binding["from"]),
                    "to": [command_event("select", source, index + 1)],
                    "conditions": device_conditions(binding, active=True),
                }
            )

    # An inactive entry gets a short bootstrap lease. The app must acknowledge
    # and renew it; otherwise ordinary mappings recover automatically.
    for source in ("corsair", "razer"):
        binding = by_id[color_proof["bindingsBySource"][source][entry_index]]
        manipulators.append(
            {
                "type": "basic",
                "from": copy.deepcopy(binding["from"]),
                "to": [
                    {
                        "set_variable": {
                            "name": variable,
                            "expression": (
                                "system.now.milliseconds + "
                                f'{color_proof["bootstrapMilliseconds"]}'
                            ),
                        }
                    },
                    command_event("enter", source, entry_index + 1),
                ],
                "conditions": device_conditions(binding, active=False),
            }
        )

    return {
        "description": "Agentic Mouse — Colour proof mode (expiring, exact-device)",
        "manipulators": manipulators,
    }


def build_mode_picker_rule(
    bindings: list[dict[str, Any]],
    mode_picker: dict[str, Any],
    color_proof: dict[str, Any] | None = None,
) -> dict[str, Any]:
    by_id = {binding["id"]: binding for binding in bindings}
    variables_by_source = _lease_variables(mode_picker)
    page_variables_by_source = _page_variables(mode_picker)
    proof_expression = None
    if color_proof:
        proof_expression = _any_active_expression(color_proof)
    entry_index = mode_picker["entryPhysicalCell"] - 1
    exit_index = mode_picker["exitPhysicalCell"] - 1
    intercepted_cells = mode_picker.get("interceptPhysicalCells", list(range(1, 13)))

    def device_conditions(
        binding: dict[str, Any], *, source: str, active: bool
    ) -> list[dict[str, Any]]:
        # Runtime input is source-scoped, not application-scoped. Only exact
        # device attribution crosses this boundary; ordinary VS Code/base
        # conditions remain on the gated semantic rules below.
        conditions = [
            copy.deepcopy(condition)
            for condition in binding.get("conditions", [])
            if condition.get("type") in {"device_if", "device_unless"}
        ]
        conditions.append(
            {
                "type": "expression_if" if active else "expression_unless",
                "expression": _active_expression(variables_by_source[source]),
            }
        )
        if proof_expression:
            conditions.append(
                {"type": "expression_unless", "expression": proof_expression}
            )
        return conditions

    def command_event(
        action: str,
        source: str,
        physical_cell: int,
        phase: str = "press",
    ) -> dict[str, Any]:
        return {
            "send_user_command": {
                "payload": {
                    "command": "agentic_mouse_mode_picker",
                    "action": action,
                    "source": source,
                    "physical_cell": physical_cell,
                    "phase": phase,
                }
            },
            "repeat": False,
        }

    manipulators: list[dict[str, Any]] = []
    for source in ("corsair", "razer"):
        variable = variables_by_source[source]
        page_variable = page_variables_by_source[source]
        exit_binding = by_id[mode_picker["bindingsBySource"][source][exit_index]]
        close_conditions = device_conditions(exit_binding, source=source, active=True)
        manipulators.append(
            {
                "type": "basic",
                "from": copy.deepcopy(exit_binding["from"]),
                "to": [
                    {"set_variable": {"name": variable, "value": 0}},
                    {"set_variable": {"name": page_variable, "value": 0}},
                    command_event("close", source, exit_index + 1),
                ],
                "conditions": close_conditions,
            }
        )
    for source in ("corsair", "razer"):
        page_variable = page_variables_by_source[source]
        for physical_cell in intercepted_cells:
            if physical_cell == exit_index + 1:
                continue
            index = physical_cell - 1
            binding_id = mode_picker["bindingsBySource"][source][index]
            binding = by_id[binding_id]
            ordinary_conditions = device_conditions(binding, source=source, active=True)
            keys_native_output = (
                RAZER_KEYS_MODE_OUTPUT_OVERRIDES.get(physical_cell)
                if source == "razer"
                else None
            ) or KEYS_MODE_OUTPUT_BY_PHYSICAL_CELL.get(physical_cell)
            if keys_native_output is not None:
                ordinary_conditions.append(
                    {
                        "type": "expression_unless",
                        "expression": f"{page_variable} == {MODE_PAGE_KEYS}",
                    }
                )
            if physical_cell == 6:
                ordinary_conditions.append(
                    {
                        "type": "expression_unless",
                        "expression": f"{page_variable} == {MODE_PAGE_KEYS}",
                    }
                )
            if physical_cell == 11:
                ordinary_conditions.append(
                    {
                        "type": "expression_unless",
                        "expression": f"{page_variable} == {MODE_PAGE_UTILITY}",
                    }
                )
            if physical_cell == 9:
                ordinary_conditions.append(
                    {
                        "type": "expression_unless",
                        "expression": f"{page_variable} == {MODE_PAGE_UTILITY}",
                    }
                )
            if physical_cell in APP_SELECTOR_TARGET_CELLS:
                ordinary_conditions.append(
                    {
                        "type": "expression_unless",
                        "expression": f"{page_variable} == {MODE_PAGE_APP_SELECTOR}",
                    }
                )
            manipulators.append(
                {
                    "type": "basic",
                    "from": copy.deepcopy(binding["from"]),
                    "to": [command_event("select", source, index + 1, "press")],
                    "to_after_key_up": [
                        command_event("select", source, index + 1, "release")
                    ],
                    "conditions": ordinary_conditions,
                }
            )
            if keys_native_output is not None:
                native_conditions = device_conditions(binding, source=source, active=True)
                native_conditions.append(
                    {
                        "type": "expression_if",
                        "expression": f"{page_variable} == {MODE_PAGE_KEYS}",
                    }
                )
                manipulators.append(
                    {
                        "type": "basic",
                        "from": copy.deepcopy(binding["from"]),
                        "to": [
                            command_event("selectNative", source, index + 1, "press"),
                            copy.deepcopy(keys_native_output),
                        ],
                        "conditions": native_conditions,
                    }
                )

            if physical_cell == 9:
                keys_navigation_conditions = device_conditions(
                    binding,
                    source=source,
                    active=True,
                )
                keys_navigation_conditions.append(
                    {
                        "type": "expression_if",
                        "expression": f"{page_variable} == {MODE_PAGE_UTILITY}",
                    }
                )
                manipulators.append(
                    {
                        "type": "basic",
                        "from": copy.deepcopy(binding["from"]),
                        "to": [
                            {
                                "set_variable": {
                                    "name": page_variable,
                                    "value": MODE_PAGE_KEYS,
                                }
                            },
                            command_event("select", source, physical_cell, "press"),
                        ],
                        "conditions": keys_navigation_conditions,
                    }
                )

            if physical_cell == 6:
                keypad_conditions = device_conditions(binding, source=source, active=True)
                keypad_conditions.append(
                    {
                        "type": "expression_if",
                        "expression": f"{page_variable} == {MODE_PAGE_KEYS}",
                    }
                )
                manipulators.append(
                    {
                        "type": "basic",
                        "from": copy.deepcopy(binding["from"]),
                        "to": [
                            {
                                "set_variable": {
                                    "name": page_variable,
                                    "value": MODE_PAGE_KEYPAD,
                                }
                            },
                            command_event("select", source, index + 1, "press"),
                        ],
                        "conditions": keypad_conditions,
                    }
                )

            if physical_cell == 11:
                selector_conditions = device_conditions(binding, source=source, active=True)
                selector_conditions.append(
                    {
                        "type": "expression_if",
                        "expression": f"{page_variable} == {MODE_PAGE_UTILITY}",
                    }
                )
                manipulators.append(
                    {
                        "type": "basic",
                        "from": copy.deepcopy(binding["from"]),
                        "to": [
                            {
                                "set_variable": {
                                    "name": page_variable,
                                    "value": MODE_PAGE_APP_SELECTOR,
                                }
                            },
                            command_event("select", source, index + 1, "press"),
                        ],
                        "conditions": selector_conditions,
                    }
                )

            if physical_cell in APP_SELECTOR_TARGET_CELLS:
                target_conditions = device_conditions(binding, source=source, active=True)
                target_conditions.append(
                    {
                        "type": "expression_if",
                        "expression": f"{page_variable} == {MODE_PAGE_APP_SELECTOR}",
                    }
                )
                manipulators.append(
                    {
                        "type": "basic",
                        "from": copy.deepcopy(binding["from"]),
                        "to": [
                            {
                                "set_variable": {
                                    "name": page_variable,
                                    "value": MODE_PAGE_APP_SPECIFIC,
                                }
                            },
                            command_event("select", source, index + 1, "press"),
                        ],
                        "conditions": target_conditions,
                    }
                )

    legend_index = mode_picker["exitPhysicalCell"] - 1

    def default_legend_event(source: str) -> dict[str, Any]:
        return {
            "send_user_command": {
                "payload": {
                    "command": "agentic_mouse_default_map_toggle",
                    "source": source,
                    "physical_cell": legend_index + 1,
                }
            },
            "repeat": False,
        }

    for source in ("corsair", "razer"):
        variable = variables_by_source[source]
        page_variable = page_variables_by_source[source]
        legend_binding = by_id[mode_picker["bindingsBySource"][source][legend_index]]
        entry_binding = by_id[mode_picker["bindingsBySource"][source][entry_index]]

        # Outside a runtime mode, the universal cell-10 control toggles this
        # mouse's persistent Default legend. Inside a mode, the higher active
        # manipulator above uses the same physical cell as universal Exit.
        manipulators.append(
            {
                "type": "basic",
                "from": copy.deepcopy(legend_binding["from"]),
                "to": [default_legend_event(source)],
                "conditions": device_conditions(
                    legend_binding,
                    source=source,
                    active=False,
                ),
            }
        )

        # Utility no longer waits for a possible second click because the
        # legend has its own dedicated top-level control.
        manipulators.append(
            {
                "type": "basic",
                "from": copy.deepcopy(entry_binding["from"]),
                "to": [
                    {
                        "set_variable": {
                            "name": variable,
                            "expression": (
                                "system.now.milliseconds + "
                                f'{mode_picker["bootstrapMilliseconds"]}'
                            ),
                        }
                    },
                    {
                        "set_variable": {
                            "name": page_variable,
                            "value": MODE_PAGE_UTILITY,
                        }
                    },
                    command_event("open", source, entry_index + 1),
                ],
                "conditions": device_conditions(
                    entry_binding,
                    source=source,
                    active=False,
                ),
            }
        )

    return {
        "description": "Agentic Mouse — Modes (expiring, exact-device)",
        "manipulators": manipulators,
    }


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
    parser.add_argument("--runtime-output", type=Path)
    parser.add_argument("--color-proof-output", type=Path, help=argparse.SUPPRESS)
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
        bindings, color_proof, mode_picker, security = load_bindings(args.bindings)
        karabiner, catalog, runtime_document = build_documents(
            actions, bindings, color_proof, mode_picker, security
        )
        if args.runtime_output is not None and args.color_proof_output is not None:
            raise GenerationError("provide only one of --runtime-output or --color-proof-output")
        runtime_output = args.runtime_output or args.color_proof_output
        if runtime_output is None:
            runtime_output = (
                DEFAULT_RUNTIME_OUTPUT
                if args.output == DEFAULT_OUTPUT
                else args.output.with_name(
                    f"{args.output.stem}-runtime{args.output.suffix}"
                )
            )
        _write_or_check(args.output, _json_text(karabiner), args.check)
        _write_or_check(
            runtime_output, _json_text(runtime_document), args.check
        )
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
