import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "Scripts" / "generate-karabiner.py"
ACTIONS = ROOT / "Karabiner" / "actions"
BINDINGS = ROOT / "Karabiner" / "bindings" / "bindings.json"
KARABINER_CLI = Path(
    "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
)


def exact_test_device_condition():
    return {
        "type": "device_if",
        "identifiers": [
            {"vendor_id": 5426, "product_id": 141, "is_keyboard": True}
        ],
    }


def exact_corsair_keyboard_condition():
    return {
        "type": "device_if",
        "identifiers": [
            {"vendor_id": 6940, "product_id": 65535, "is_keyboard": True}
        ],
    }


def vscode_if_condition():
    return {
        "type": "frontmost_application_if",
        "bundle_identifiers": [r"^com\.microsoft\.VSCode(?:Insiders)?$"],
    }


def vscode_unless_condition():
    return {
        "type": "frontmost_application_unless",
        "bundle_identifiers": [r"^com\.microsoft\.VSCode(?:Insiders)?$"],
    }


def exact_corsair_pointing_condition():
    return {
        "type": "device_if",
        "identifiers": [
            {"vendor_id": 6940, "product_id": 11008, "is_pointing_device": True}
        ],
    }


def exact_razer_pointing_condition():
    return {
        "type": "device_if",
        "identifiers": [
            {"vendor_id": 5426, "product_id": 141, "is_pointing_device": True}
        ],
    }


class KarabinerGeneratorTests(unittest.TestCase):
    def run_generator(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(GENERATOR), *arguments],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_committed_generated_files_match_sources(self):
        result = self.run_generator("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        action_count = len(list(ACTIONS.rglob("*.jsonc")))
        binding_count = len(json.loads(BINDINGS.read_text())["bindings"])
        self.assertIn(
            f"{action_count} semantic actions and {binding_count} physical bindings",
            result.stdout,
        )

    def test_modes_is_exact_device_expiring_and_colour_proof_is_not_generated(self):
        source = json.loads(BINDINGS.read_text())
        generated_base = json.loads(
            (ROOT / "Karabiner/generated/agentic-mouse.json").read_text()
        )
        generated = json.loads(
            (ROOT / "Karabiner/generated/agentic-mouse-runtime.json").read_text()
        )
        picker = source["modePicker"]
        self.assertNotIn("colorProof", source)
        self.assertEqual(picker["entryPhysicalCell"], 12)
        self.assertEqual(picker["exitPhysicalCell"], 10)
        self.assertEqual(picker["interceptPhysicalCells"], list(range(1, 13)))
        self.assertEqual(
            set(picker["leaseVariablesBySource"]), {"corsair", "razer"}
        )
        self.assertEqual(len(set(picker["leaseVariablesBySource"].values())), 2)
        self.assertEqual(
            set(picker["appSelectionVariablesBySource"]), {"corsair", "razer"}
        )
        self.assertEqual(len(set(picker["appSelectionVariablesBySource"].values())), 2)
        corsair = picker["bindingsBySource"]["corsair"]
        razer = picker["bindingsBySource"]["razer"]
        self.assertEqual(len(corsair), 12)
        self.assertEqual(len(razer), 12)
        self.assertEqual(len(set(corsair + razer)), 24)
        self.assertEqual(corsair[11], "corsair-side-12-agentic-runtime")
        self.assertEqual(razer[11], "razer-side-10-agentic-runtime")

        descriptions = [item["description"] for item in generated["rules"]]
        self.assertNotIn(
            "Agentic Mouse — Colour proof mode (expiring, exact-device)", descriptions
        )
        self.assertNotIn(
            "Agentic Mouse — Colour proof mode (expiring, exact-device)",
            [item["description"] for item in generated_base["rules"]],
        )

        rule = next(
            item for item in generated["rules"]
            if item["description"] == "Agentic Mouse — Modes (expiring, exact-device)"
        )
        self.assertEqual(len(rule["manipulators"]), 62)
        actions = []
        legend_toggles = []
        for manipulator in rule["manipulators"]:
            condition_types = {item["type"] for item in manipulator["conditions"]}
            self.assertIn("device_if", condition_types)
            self.assertTrue({"expression_if", "expression_unless"} & condition_types)
            frontmost_conditions = {
                "frontmost_application_if", "frontmost_application_unless"
            } & condition_types
            if frontmost_conditions:
                self.assertEqual(
                    manipulator["from"]["key_code"],
                    "keypad_plus" if any(
                        condition.get("identifiers", [{}])[0].get("vendor_id") == 6940
                        for condition in manipulator["conditions"]
                        if condition["type"] == "device_if"
                    ) else "0",
                )
                self.assertTrue(
                    any(
                        condition.get("type") == "expression_if"
                        and condition.get("expression", "").endswith("_app_selection == 0")
                        for condition in manipulator["conditions"]
                    ),
                    "only automatic app selection may consult the real frontmost app",
                )
            immediate_commands = [
                event for event in manipulator.get("to", [])
                if "send_user_command" in event
            ]
            if immediate_commands and immediate_commands[0]["send_user_command"]["payload"]["command"] == "agentic_mouse_default_map_toggle":
                legend_toggles.append(
                    immediate_commands[0]["send_user_command"]["payload"]
                )
                continue
            if immediate_commands:
                command = immediate_commands[0]
            else:
                command = next(
                    event
                    for event in manipulator["to_delayed_action"]["to_if_invoked"]
                    if "send_user_command" in event
                )
            payload = command["send_user_command"]["payload"]
            self.assertEqual(payload["command"], "agentic_mouse_mode_picker")
            self.assertEqual(payload["phase"], "press")
            actions.append(payload["action"])
            if payload["action"] == "select" and "to_after_key_up" in manipulator:
                release = manipulator["to_after_key_up"][0]["send_user_command"]["payload"]
                self.assertEqual(release["phase"], "release")
                self.assertEqual(release["source"], payload["source"])
                self.assertEqual(release["physical_cell"], payload["physical_cell"])

        self.assertEqual(actions[:2], ["close", "close"])
        self.assertEqual(actions.count("select"), 38)
        self.assertEqual(actions.count("selectNative"), 18)
        self.assertEqual(actions[-2:], ["open", "open"])
        self.assertEqual(
            {(item["source"], item["physical_cell"]) for item in legend_toggles},
            {("corsair", 10), ("razer", 10)},
        )

        for source_name, source_key, legend_key in (
            ("corsair", "keypad_plus", "keypad_0"),
            ("razer", "0", "equal_sign"),
        ):
            source_manipulators = [
                item for item in rule["manipulators"]
                if any(
                    event.get("send_user_command", {}).get("payload", {}).get("source")
                    == source_name
                    for event in item.get("to", [])
                )
            ]
            legend = next(
                item for item in source_manipulators
                if any(
                    event.get("send_user_command", {}).get("payload", {}).get("command")
                    == "agentic_mouse_default_map_toggle"
                    for event in item["to"]
                )
            )
            self.assertEqual(legend["from"]["key_code"], legend_key)
            self.assertNotIn("to_delayed_action", legend)
            utility = next(
                item for item in source_manipulators
                if any(
                    event.get("send_user_command", {}).get("payload", {}).get("action")
                    == "open"
                    for event in item["to"]
                )
            )
            self.assertEqual(utility["from"]["key_code"], source_key)
            self.assertNotIn("to_delayed_action", utility)

        for source_name in ("corsair", "razer"):
            page_variable = picker["pageVariablesBySource"][source_name]
            source_manipulators = [
                item for item in rule["manipulators"]
                if any(
                    event.get("send_user_command", {}).get("payload", {}).get("source")
                    == source_name
                    for event in item.get("to", [])
                )
            ]
            close = next(
                item for item in source_manipulators
                if any(
                    event.get("send_user_command", {}).get("payload", {}).get("action")
                    == "close"
                    for event in item["to"]
                )
            )
            self.assertEqual(
                next(
                    event["send_user_command"]["payload"]["physical_cell"]
                    for event in close["to"] if "send_user_command" in event
                ),
                10,
            )
            self.assertFalse(
                any(page_variable in condition.get("expression", "") for condition in close["conditions"]),
                "the universal exit must work from every active page",
            )
            self.assertFalse(
                any(
                    any(
                        event.get("set_variable", {}).get("name") == page_variable
                        and event.get("set_variable", {}).get("value") == 3
                        for event in item["to"]
                    )
                    and any(
                        condition.get("expression") == f"{page_variable} == 4"
                        for condition in item["conditions"]
                    )
                    for item in source_manipulators
                ),
                "app children retain their own cell 12 action; universal cell 10 exits",
            )
            utility_to_keys = next(
                item for item in source_manipulators
                if any(
                    event.get("set_variable", {}).get("name") == page_variable
                    and event.get("set_variable", {}).get("value") == 2
                    for event in item["to"]
                )
                and any(
                    event.get("send_user_command", {}).get("payload", {}).get("physical_cell")
                    == 9
                    for event in item["to"]
                )
            )
            self.assertIn(
                {"type": "expression_if", "expression": f"{page_variable} == 1"},
                utility_to_keys["conditions"],
            )
            self.assertFalse(
                any(
                    any(event.get("key_code") == "return_or_enter" for event in item["to"])
                    and any(
                        condition.get("expression") == f"{page_variable} == 2"
                        for condition in item["conditions"]
                    )
                    for item in source_manipulators
                ),
                "Keys cell 12 is spare; only Keypad retains Return",
            )
            for target_cell in (1, 4, 7):
                target = next(
                    item for item in source_manipulators
                    if any(
                        event.get("set_variable", {}).get("value") == 4
                        for event in item["to"]
                    )
                    and any(
                        event.get("send_user_command", {}).get("payload", {}).get("physical_cell")
                        == target_cell
                        for event in item["to"]
                    )
                )
                self.assertIn(
                    {
                        "type": "expression_if",
                        "expression": f"{page_variable} == 3",
                    },
                    target["conditions"],
                )

            keypad_cell_three = next(
                item
                for item in source_manipulators
                if "to_after_key_up" in item
                and any(
                    event.get("send_user_command", {}).get("payload", {}).get("action")
                    == "select"
                    and event["send_user_command"]["payload"]["physical_cell"] == 3
                    for event in item["to"]
                )
            )
            self.assertNotIn(
                {
                    "type": "expression_unless",
                    "expression": f"{page_variable} == 5",
                },
                keypad_cell_three["conditions"],
                "Keypad cell 3 must reach the app as DEF instead of being reserved for a HUD toggle",
            )
            release = keypad_cell_three["to_after_key_up"][0]["send_user_command"]["payload"]
            self.assertEqual(release["physical_cell"], 3)
            self.assertEqual(release["phase"], "release")

        page_variables = picker["pageVariablesBySource"]
        native_keys = {
            "corsair": {
                "keypad_1": {"key_code": "left_arrow"},
                "keypad_3": {"key_code": "z", "modifiers": ["left_command"]},
                "keypad_4": {"key_code": "down_arrow"},
                "keypad_5": {"key_code": "up_arrow"},
                "keypad_7": {"key_code": "right_arrow"},
                "keypad_8": {"key_code": "spacebar"},
                "keypad_hyphen": {"key_code": "delete_or_backspace"},
            },
            "razer": {
                "3": {"key_code": "right_arrow"},
                "1": {"key_code": "z", "modifiers": ["left_command"]},
                "6": {"key_code": "down_arrow"},
                "5": {"key_code": "up_arrow"},
                "9": {"key_code": "left_arrow"},
                "8": {"key_code": "spacebar"},
                "hyphen": {"key_code": "delete_or_backspace"},
            },
        }
        for source_name, expected in native_keys.items():
            for transport, output in expected.items():
                native = next(
                    manipulator
                    for manipulator in rule["manipulators"]
                    if manipulator.get("from", {}).get("key_code") == transport
                    and any(
                        event.get("send_user_command", {}).get("payload", {}).get("action")
                        == "selectNative"
                        for event in manipulator.get("to", [])
                    )
                    and {
                        "type": "expression_if",
                        "expression": f"{page_variables[source_name]} == 2",
                    }
                    in manipulator.get("conditions", [])
                )
                for output_field, output_value in output.items():
                    self.assertEqual(native["to"][-1][output_field], output_value)
                self.assertIs(native["to"][-1]["repeat"], False)
                self.assertTrue(
                    any(
                        condition["type"] == "expression_if"
                        and "agentic_mouse_session_unlocked_expires_at"
                        in condition["expression"]
                        for condition in native["to"][-1]["conditions"]
                    )
                )
                self.assertIn(
                    {
                        "type": "expression_if",
                        "expression": f'{page_variables[source_name]} == 2',
                    },
                    native["conditions"],
                )

        for source_name, transport in {"corsair": "keypad_9", "razer": "7"}.items():
            page_variable = page_variables[source_name]
            tracks_wheel = next(
                manipulator
                for manipulator in rule["manipulators"]
                if manipulator.get("from", {}).get("key_code") == transport
                and any(
                    event.get("send_user_command", {}).get("payload", {}).get("action")
                    == "select"
                    and event["send_user_command"]["payload"]["physical_cell"] == 9
                    for event in manipulator.get("to", [])
                )
                and {
                    "type": "expression_unless",
                    "expression": f"{page_variable} == 1",
                }
                in manipulator.get("conditions", [])
            )
            self.assertFalse(
                any("consumer_key_code" in event for event in tracks_wheel["to"]),
                "Keys cell 9 must arm the wheel without skipping a track on press",
            )
            release = tracks_wheel["to_after_key_up"][0]["send_user_command"]["payload"]
            self.assertEqual(release["physical_cell"], 9)
            self.assertEqual(release["phase"], "release")

        for source_name, transports in {
            "corsair": ("keypad_3", "keypad_6"),
            "razer": ("1", "4"),
        }.items():
            for transport in transports:
                utility_native = [
                    manipulator
                    for manipulator in rule["manipulators"]
                    if manipulator.get("from", {}).get("key_code") == transport
                    and any(
                        event.get("send_user_command", {}).get("payload", {}).get("action")
                        == "selectNative"
                        for event in manipulator.get("to", [])
                    )
                    and {
                        "type": "expression_if",
                        "expression": f'{page_variables[source_name]} == 1',
                    }
                    in manipulator.get("conditions", [])
                ]
                self.assertEqual(
                    utility_native,
                    [],
                    "Utility clipboard and Magnet wheel controls must reach Agentic Mouse on press and release",
                )

        for source_name in ("corsair", "razer"):
            page_variable = page_variables[source_name]
            keypad_navigation = next(
                manipulator
                for manipulator in rule["manipulators"]
                if {
                    "type": "expression_if",
                    "expression": f"{page_variable} == 2",
                }
                in manipulator.get("conditions", [])
                and any(
                    event.get("set_variable", {}).get("name") == page_variable
                    and event["set_variable"].get("value") == 5
                    for event in manipulator.get("to", [])
                )
            )
            payload = keypad_navigation["to"][-1]["send_user_command"]["payload"]
            self.assertEqual(payload["action"], "select")
            self.assertEqual(payload["source"], source_name)
            self.assertEqual(payload["physical_cell"], 6)

        for source_name in ("corsair", "razer"):
            page_variable = page_variables[source_name]
            for physical_cell in (1, 2, 3, 6):
                ordinary = next(
                    manipulator
                    for manipulator in rule["manipulators"]
                    if any(
                        event.get("send_user_command", {}).get("payload", {}).get("action")
                        == "select"
                        and event["send_user_command"]["payload"]["source"] == source_name
                        and event["send_user_command"]["payload"]["physical_cell"]
                        == physical_cell
                        for event in manipulator.get("to", [])
                    )
                    and "to_after_key_up" in manipulator
                )
                self.assertNotIn(
                    {
                        "type": "expression_unless",
                        "expression": f"{page_variable} == 1",
                    },
                    ordinary["conditions"],
                    "the held Utility control must keep both press and release visible to the app",
                )

        for source_name, base_description in (
            ("corsair", "Agentic Mouse — Corsair base layer"),
            ("razer", "Agentic Mouse — Razer base layer"),
        ):
            variable = picker["leaseVariablesBySource"][source_name]
            page_variable = picker["pageVariablesBySource"][source_name]
            app_selection_variable = picker["appSelectionVariablesBySource"][source_name]
            picker_expression = (
                f'({variable} > system.now.milliseconds) and '
                f'({variable} <= system.now.milliseconds + 15000)'
            )
            base = next(item for item in generated["rules"] if item["description"] == base_description)
            gated = [
                manipulator for manipulator in base["manipulators"]
                if {"type": "expression_unless", "expression": picker_expression}
                in manipulator.get("conditions", [])
            ]
            self.assertEqual(len(gated), 12)
            other_source = "razer" if source_name == "corsair" else "corsair"
            other_variable = picker["leaseVariablesBySource"][other_source]
            self.assertFalse(
                any(
                    other_variable in condition.get("expression", "")
                    for manipulator in base["manipulators"]
                    for condition in manipulator.get("conditions", [])
                ),
                "one mouse's mode lease must not suppress the other mouse's base",
            )
            direct_entry_keys = {
                "corsair": {"keypad_2", "keypad_9"},
                "razer": {"2", "7"},
            }[source_name]
            direct_entries = [
                manipulator
                for manipulator in base["manipulators"]
                if manipulator.get("from", {}).get("key_code") in direct_entry_keys
            ]
            self.assertEqual(len(direct_entries), 2)
            for manipulator in direct_entries:
                bootstrap = manipulator["to"][0]["set_variable"]
                self.assertEqual(bootstrap["name"], variable)
                self.assertEqual(
                    bootstrap["expression"],
                    f'system.now.milliseconds + {picker["bootstrapMilliseconds"]}',
                )
                page = manipulator["to"][1]["set_variable"]
                self.assertEqual(page["name"], page_variable)
                command = next(
                    event["send_user_command"]["payload"]
                    for event in manipulator["to"]
                    if "send_user_command" in event
                )
                self.assertEqual(command["source"], source_name)
                self.assertIn(command["action"], {"openKeys", "openAppSpecific"})
                self.assertEqual(
                    page["value"],
                    2 if command["action"] == "openKeys" else 4,
                )
                if command["action"] == "openAppSpecific":
                    self.assertIn(
                        {
                            "set_variable": {
                                "name": app_selection_variable,
                                "value": 0,
                            }
                        },
                        manipulator["to"],
                    )

            voice_transport = "keypad_plus" if source_name == "corsair" else "0"
            voice_routes = [
                manipulator
                for manipulator in rule["manipulators"]
                if manipulator.get("from", {}).get("key_code") == voice_transport
                and {
                    "type": "expression_if",
                    "expression": f"{page_variable} == 4",
                }
                in manipulator.get("conditions", [])
            ]
            self.assertEqual(len(voice_routes), 4)
            native_voice_routes = [
                manipulator
                for manipulator in voice_routes
                if any(
                    event.get("send_user_command", {}).get("payload", {}).get("action")
                    == "selectNative"
                    for event in manipulator["to"]
                )
            ]
            self.assertEqual(len(native_voice_routes), 2)
            for manipulator in native_voice_routes:
                self.assertEqual(
                    manipulator["to"][-1],
                    {
                        "key_code": "period",
                        "modifiers": ["left_control", "left_shift"],
                        "repeat": False,
                        "conditions": [
                            {
                                "type": "expression_if",
                                "expression": (
                                    "(agentic_mouse_session_unlocked_expires_at > system.now.milliseconds) and "
                                    "(agentic_mouse_session_unlocked_expires_at <= system.now.milliseconds + 15000)"
                                ),
                            }
                        ],
                    },
                )

        for rule in generated_base["rules"]:
            for manipulator in rule["manipulators"]:
                self.assertFalse(
                    any(
                        condition.get("type", "").startswith("expression_")
                        and any(
                            lease_variable in condition.get("expression", "")
                            for lease_variable in picker["leaseVariablesBySource"].values()
                        )
                        for condition in manipulator.get("conditions", [])
                    ),
                    "the ordinary artifact remains a source-only base without live mode gates",
                )

    def test_default_controls_use_release_screenshot_and_final_switch_app_cell(self):
        ordinary = json.loads(
            (ROOT / "Karabiner/generated/agentic-mouse.json").read_text()
        )
        cases = (
            (
                "Agentic Mouse — Corsair base layer",
                exact_corsair_keyboard_condition(),
                "keypad_3",
                "keypad_hyphen",
                "corsair",
            ),
            (
                "Agentic Mouse — Razer base layer",
                exact_test_device_condition(),
                "1",
                "hyphen",
                "razer",
            ),
        )
        for description, device, screenshot_key, switch_key, source in cases:
            rule = next(item for item in ordinary["rules"] if item["description"] == description)
            screenshot_toggle = next(
                item for item in rule["manipulators"]
                if item.get("from", {}).get("key_code") == screenshot_key
                and device in item.get("conditions", [])
            )
            self.assertEqual(
                screenshot_toggle["to_after_key_up"][0]["send_user_command"]["payload"],
                {
                    "command": "agentic_mouse_selected_area_screenshot_toggle",
                    "source": source,
                    "physical_cell": 3,
                },
            )
            switch_app = next(
                item for item in rule["manipulators"]
                if item.get("from", {}).get("key_code") == switch_key
                and device in item.get("conditions", [])
            )
            self.assertEqual(
                [
                    {key: value for key, value in event.items() if key != "conditions"}
                    for event in switch_app["to"]
                ],
                [
                    {"key_code": "tab", "modifiers": ["left_command"], "repeat": False},
                    {"key_code": "left_command", "repeat": True},
                ],
            )

    def test_voiceink_action_fires_only_after_source_key_up(self):
        action_path = ACTIONS / "productivity/toggle-voiceink-speech-to-text.jsonc"
        action = json.loads(
            "\n".join(
                line
                for line in action_path.read_text().splitlines()
                if not line.lstrip().startswith("//")
            )
        )
        manipulator = action["manipulator"]
        self.assertNotIn("to", manipulator)
        self.assertEqual(
            manipulator["to_after_key_up"],
            [
                {
                    "key_code": "left_shift",
                    "modifiers": ["left_control", "left_option"],
                    "repeat": False,
                }
            ],
        )

    def test_voiceink_press_fallback_fires_immediately_without_repeat(self):
        action_path = ACTIONS / "productivity/toggle-voiceink-speech-to-text-on-press.jsonc"
        action = json.loads(
            "\n".join(
                line
                for line in action_path.read_text().splitlines()
                if not line.lstrip().startswith("//")
            )
        )
        manipulator = action["manipulator"]
        self.assertNotIn("to_after_key_up", manipulator)
        self.assertEqual(
            manipulator["to"],
            [
                {
                    "key_code": "left_shift",
                    "modifiers": ["left_control", "left_option"],
                    "repeat": False,
                }
            ],
        )

    def test_committed_adapters_match_the_proven_device_namespaces(self):
        bindings = json.loads(BINDINGS.read_text())["bindings"]
        self.assertEqual(len(bindings), 37)

        corsair_bindings = [
            binding for binding in bindings if binding["id"].startswith("corsair-")
        ]
        razer_bindings = [
            binding for binding in bindings if binding["id"].startswith("razer-")
        ]
        self.assertEqual(len(corsair_bindings), 18)
        self.assertEqual(len(razer_bindings), 19)

        corsair_dpi = next(
            binding
            for binding in corsair_bindings
            if binding["id"] == "corsair-dpi-toggle-voiceink"
        )
        self.assertEqual(corsair_dpi["action"], "toggle-voiceink-speech-to-text")
        self.assertEqual(
            corsair_dpi["from"],
            {"key_code": "f19", "modifiers": {"optional": ["any"]}},
        )
        self.assertIn(exact_corsair_keyboard_condition(), corsair_dpi["conditions"])

        corsair_wheel = next(
            binding
            for binding in corsair_bindings
            if binding["id"] == "corsair-wheel-play-pause"
        )
        self.assertEqual(corsair_wheel["action"], "play-pause-current-media")
        self.assertEqual(
            corsair_wheel["from"],
            {"pointing_button": "button3", "modifiers": {"optional": ["any"]}},
        )
        self.assertIn(exact_corsair_pointing_condition(), corsair_wheel["conditions"])

        razer_wheel = next(
            binding
            for binding in razer_bindings
            if binding["id"] == "razer-wheel-play-pause"
        )
        self.assertEqual(razer_wheel["action"], "play-pause-current-media")
        self.assertEqual(
            razer_wheel["from"],
            {"pointing_button": "button3", "modifiers": {"optional": ["any"]}},
        )
        self.assertIn(exact_razer_pointing_condition(), razer_wheel["conditions"])

        razer_dpi_up = next(
            binding
            for binding in razer_bindings
            if binding["id"] == "razer-dpi-up-voiceink"
        )
        self.assertEqual(razer_dpi_up["action"], "toggle-voiceink-speech-to-text")
        self.assertEqual(
            razer_dpi_up["from"],
            {"key_code": "f21", "modifiers": {"optional": ["any"]}},
        )
        self.assertIn(exact_test_device_condition(), razer_dpi_up["conditions"])

        razer_dpi_down = next(
            binding
            for binding in razer_bindings
            if binding["id"] == "razer-dpi-down-voiceink"
        )
        self.assertEqual(razer_dpi_down["action"], "toggle-voiceink-speech-to-text")
        self.assertEqual(
            razer_dpi_down["from"],
            {"key_code": "f22", "modifiers": {"optional": ["any"]}},
        )
        self.assertIn(exact_test_device_condition(), razer_dpi_down["conditions"])

        expected_transport_by_side = {
            1: "keypad_1",
            2: "keypad_2",
            3: "keypad_3",
            4: "keypad_4",
            5: "keypad_5",
            6: "keypad_6",
            7: "keypad_7",
            8: "keypad_8",
            9: "keypad_9",
            10: "keypad_0",
            11: "keypad_hyphen",
            12: "keypad_plus",
        }
        expected_corsair_action_by_side = {
            1: "hold-horizontal-scroll-wheel-corsair",
            2: "open-app-specific-mode-corsair",
            3: "toggle-selected-screen-area-corsair",
            4: "hold-copy-paste-wheel-corsair",
            5: "hold-youtube-volume-modifier-corsair",
            6: "hold-youtube-scrub-wheel-corsair",
            7: "press-enter",
            8: "go-back",
            9: "open-keys-mode-corsair",
            10: "suppress-neutral-transport",
            11: "hold-open-app-switcher",
            12: "suppress-neutral-transport",
        }
        bindings_by_side = {
            side: [
                binding
                for binding in corsair_bindings
                if binding["id"].startswith(f"corsair-side-{side:02d}-")
            ]
            for side in expected_transport_by_side
        }

        self.assertTrue(all(bindings_by_side.values()))
        self.assertEqual(
            {side: len(values) for side, values in bindings_by_side.items()},
            {side: 1 for side in expected_transport_by_side},
        )

        expected_device = {
            "type": "device_if",
            "identifiers": [
                {"vendor_id": 6940, "product_id": 65535, "is_keyboard": True}
            ],
        }
        for side, side_bindings in bindings_by_side.items():
            for binding in side_bindings:
                self.assertEqual(binding["action"], expected_corsair_action_by_side[side])
                self.assertEqual(
                    binding["from"],
                    {
                        "key_code": expected_transport_by_side[side],
                        "modifiers": {"optional": ["any"]},
                    },
                )
                self.assertIn(expected_device, binding["conditions"])

        expected_razer_transport_by_side = {
            1: "1",
            2: "2",
            3: "3",
            4: "4",
            5: "5",
            6: "6",
            7: "7",
            8: "8",
            9: "9",
            10: "0",
            11: "hyphen",
            12: "equal_sign",
        }
        expected_razer_actions_by_side = {
            1: ["toggle-selected-screen-area-razer"],
            2: ["open-app-specific-mode-razer"],
            3: ["hold-horizontal-scroll-wheel-razer"],
            4: ["hold-youtube-scrub-wheel-razer"],
            5: ["hold-youtube-volume-modifier-razer"],
            6: ["hold-copy-paste-wheel-razer"],
            7: ["open-keys-mode-razer"],
            8: ["go-back"],
            9: ["press-enter"],
            10: ["suppress-neutral-transport"],
            11: ["hold-open-app-switcher"],
            12: ["suppress-neutral-transport"],
        }
        expected_razer_device = exact_test_device_condition()
        for side, key_code in expected_razer_transport_by_side.items():
            side_bindings = [
                binding
                for binding in razer_bindings
                if binding["id"].startswith(f"razer-side-{side:02d}-")
            ]
            self.assertEqual(
                sorted(binding["action"] for binding in side_bindings),
                sorted(expected_razer_actions_by_side[side]),
            )
            for binding in side_bindings:
                self.assertEqual(
                    binding["from"],
                    {
                        "key_code": key_code,
                        "modifiers": {"optional": ["any"]},
                    },
                )
                self.assertIn(expected_razer_device, binding["conditions"])

        self.assertEqual(
            {binding["rule"] for binding in bindings},
            {
                "Corsair base layer",
                "Corsair VS Code layer",
                "Razer base layer",
                "Razer VS Code layer",
            },
        )
        for binding in bindings:
            condition_types = {
                condition["type"] for condition in binding.get("conditions", [])
            }
            self.assertNotIn("frontmost_application_if", condition_types)

        base_exclusions = {
            binding["id"]
            for binding in bindings
            if vscode_unless_condition() in binding.get("conditions", [])
        }
        self.assertEqual(
            base_exclusions,
            {
                "corsair-side-05-forward",
                "corsair-side-08-back",
                "razer-side-05-forward",
                "razer-side-08-back",
            },
        )

        self.assertFalse(
            any(binding["action"] == "play-previous-track" for binding in bindings),
            "Ethan intentionally has no Previous Track side-button binding",
        )

        razer_hint = next(
            binding
            for binding in razer_bindings
            if binding["id"] == "razer-side-10-agentic-runtime"
        )
        self.assertEqual(razer_hint["from"]["key_code"], "0")
        self.assertIn(expected_razer_device, razer_hint["conditions"])

    def test_top_level_wheel_chords_preserve_exact_source_until_release(self):
        generated = json.loads(
            (ROOT / "Karabiner/generated/agentic-mouse.json").read_text()
        )
        for description, key_code, source, control in (
            ("Agentic Mouse — Corsair base layer", "keypad_1", "corsair", "horizontalScroll"),
            ("Agentic Mouse — Razer base layer", "3", "razer", "horizontalScroll"),
            ("Agentic Mouse — Corsair base layer", "keypad_4", "corsair", "clipboard"),
            ("Agentic Mouse — Razer base layer", "6", "razer", "clipboard"),
        ):
            rule = next(
                item for item in generated["rules"]
                if item["description"] == description
            )
            manipulator = next(
                item for item in rule["manipulators"]
                if item.get("from", {}).get("key_code") == key_code
                and item.get("to", [{}])[0]
                    .get("send_user_command", {})
                    .get("payload", {})
                    .get("command") == "agentic_mouse_wheel_chord"
            )
            press = manipulator["to"][0]["send_user_command"]["payload"]
            release = manipulator["to_after_key_up"][0]["send_user_command"]["payload"]
            self.assertEqual(
                press,
                {
                    "command": "agentic_mouse_wheel_chord",
                    "control": control,
                    "source": source,
                    "phase": "press",
                },
            )
            self.assertEqual(release, {**press, "phase": "release"})
            self.assertIs(manipulator["to"][0]["repeat"], False)
            self.assertIs(manipulator["to_after_key_up"][0]["repeat"], False)

    def test_both_razer_dpi_releases_share_one_voiceink_action(self):
        generated = json.loads(
            (ROOT / "Karabiner/generated/agentic-mouse.json").read_text()
        )
        rule = next(
            item
            for item in generated["rules"]
            if item["description"] == "Agentic Mouse — Razer base layer"
        )
        dpi = {
            item["from"]["key_code"]: item
            for item in rule["manipulators"]
            if item.get("from", {}).get("key_code") in {"f21", "f22"}
        }
        self.assertEqual(set(dpi), {"f21", "f22"})
        self.assertEqual(dpi["f21"]["to_after_key_up"], dpi["f22"]["to_after_key_up"])
        self.assertIn(exact_test_device_condition(), dpi["f21"]["conditions"])
        self.assertIn(exact_test_device_condition(), dpi["f22"]["conditions"])

    def test_screenshot_toggle_is_bound_once_per_exact_device_on_physical_cell_three(self):
        generated = json.loads(
            (ROOT / "Karabiner/generated/agentic-mouse.json").read_text()
        )
        screenshots = []
        for rule in generated["rules"]:
            for manipulator in rule["manipulators"]:
                if any(
                    event.get("send_user_command", {}).get("payload", {}).get("command")
                    == "agentic_mouse_selected_area_screenshot_toggle"
                    for event in manipulator.get("to_after_key_up", [])
                ):
                    screenshots.append(manipulator)

        self.assertEqual(len(screenshots), 2)
        self.assertEqual(
            {item["from"]["key_code"] for item in screenshots},
            {"keypad_3", "1"},
        )
        self.assertTrue(
            all(
                any(condition["type"] == "device_if" for condition in item["conditions"])
                for item in screenshots
            )
        )

    def test_locked_session_sink_and_output_time_guards_cover_every_mouse_transport(self):
        source = json.loads(BINDINGS.read_text())
        expected_variable = source["security"]["unlockedLeaseVariable"]
        expected_expression = (
            f"({expected_variable} > system.now.milliseconds) and "
            f"({expected_variable} <= system.now.milliseconds + 15000)"
        )
        for artifact in (
            ROOT / "Karabiner/generated/agentic-mouse.json",
            ROOT / "Karabiner/generated/agentic-mouse-runtime.json",
        ):
            generated = json.loads(artifact.read_text())
            sink = generated["rules"][0]
            self.assertEqual(
                sink["description"],
                "Agentic Mouse — Locked-session transport sink (exact-device)",
            )
            self.assertEqual(len(sink["manipulators"]), 29)
            for manipulator in sink["manipulators"]:
                self.assertEqual(manipulator["to"], [{"key_code": "vk_none"}])
                self.assertTrue(
                    any(condition["type"] == "device_if" for condition in manipulator["conditions"])
                )
                self.assertIn(
                    {"type": "expression_unless", "expression": expected_expression},
                    manipulator["conditions"],
                )

            for rule in generated["rules"][1:]:
                for manipulator in rule["manipulators"]:
                    self.assertIn(
                        {"type": "expression_if", "expression": expected_expression},
                        manipulator["conditions"],
                    )
                    for field in ("to", "to_after_key_up", "to_delayed_action", "to_if_alone", "to_if_held_down"):
                        for event in self.external_output_events(manipulator.get(field, [])):
                            self.assertIn(
                                {"type": "expression_if", "expression": expected_expression},
                                event.get("conditions", []),
                                f"deferred/release output is not lock-gated: {event}",
                            )

    def external_output_events(self, value):
        external_fields = {
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
        events = []
        if isinstance(value, list):
            for item in value:
                events.extend(self.external_output_events(item))
        elif isinstance(value, dict):
            if external_fields & set(value):
                events.append(value)
            for item in value.values():
                events.extend(self.external_output_events(item))
        return events

    def test_vscode_overrides_are_exact_device_non_repeating_and_transport_matched(self):
        generated = json.loads(
            (ROOT / "Karabiner/generated/agentic-mouse.json").read_text()
        )
        rules = {rule["description"]: rule for rule in generated["rules"]}
        rule_order = [rule["description"] for rule in generated["rules"]]
        self.assertLess(
            rule_order.index("Agentic Mouse — Corsair VS Code layer"),
            rule_order.index("Agentic Mouse — Corsair base layer"),
        )
        self.assertLess(
            rule_order.index("Agentic Mouse — Razer VS Code layer"),
            rule_order.index("Agentic Mouse — Razer base layer"),
        )

        cases = (
            (
                "Agentic Mouse — Corsair VS Code layer",
                exact_corsair_keyboard_condition(),
                "keypad_5",
                "keypad_4",
                "agentic_mouse_corsair_vscode_side_05_previous_change_pending",
                "keypad_8",
                "keypad_7",
                "agentic_mouse_corsair_vscode_side_08_next_change_pending",
            ),
            (
                "Agentic Mouse — Razer VS Code layer",
                exact_test_device_condition(),
                "5",
                "6",
                "agentic_mouse_razer_vscode_side_05_previous_change_pending",
                "8",
                "9",
                "agentic_mouse_razer_vscode_side_08_next_change_pending",
            ),
        )
        gesture_variables = set()
        for (
            rule_name,
            device_condition,
            previous_source,
            previous_chord_source,
            previous_variable,
            next_source,
            next_chord_source,
            next_variable,
        ) in cases:
            rule = rules[rule_name]
            self.assertEqual(len(rule["manipulators"]), 6)
            by_source = {}
            for manipulator in rule["manipulators"]:
                by_source.setdefault(manipulator["from"]["key_code"], []).append(manipulator)
            self.assertEqual(
                set(by_source),
                {previous_source, previous_chord_source, next_source, next_chord_source},
            )
            self.assertEqual(len(by_source[previous_source]), 1)
            self.assertEqual(len(by_source[previous_chord_source]), 2)
            self.assertEqual(len(by_source[next_source]), 1)
            self.assertEqual(len(by_source[next_chord_source]), 2)
            for manipulators in by_source.values():
                for manipulator in manipulators:
                    self.assertIn(device_condition, manipulator["conditions"])
                    self.assertIn(vscode_if_condition(), manipulator["conditions"])
                    self.assertNotIn(vscode_unless_condition(), manipulator["conditions"])
                    self.assertNotIn("to_delayed_action", manipulator)
                    self.assertNotIn("to_if_alone", manipulator)

            previous = by_source[previous_source][0]
            self.assertEqual(
                previous["to"],
                [{"set_variable": {"name": previous_variable, "value": 1}}],
            )
            self.assertEqual(previous["to_after_key_up"][0]["key_code"], "f17")
            self.assertIs(previous["to_after_key_up"][0]["repeat"], False)
            self.assertIn(
                {"type": "variable_if", "name": previous_variable, "value": 1},
                previous["to_after_key_up"][0]["conditions"],
            )
            self.assertEqual(
                previous["to_after_key_up"][1],
                {
                    "set_variable": {
                        "name": previous_variable,
                        "expression": "system.now.milliseconds + 1000",
                    }
                },
            )

            next_change = by_source[next_source][0]
            self.assertEqual(
                next_change["to"],
                [{"set_variable": {"name": next_variable, "value": 1}}],
            )
            self.assertEqual(next_change["to_after_key_up"][0]["key_code"], "f13")
            self.assertIs(next_change["to_after_key_up"][0]["repeat"], False)
            self.assertIn(
                {"type": "variable_if", "name": next_variable, "value": 1},
                next_change["to_after_key_up"][0]["conditions"],
            )
            self.assertEqual(
                next_change["to_after_key_up"][1],
                {
                    "set_variable": {
                        "name": next_variable,
                        "expression": "system.now.milliseconds + 1000",
                    }
                },
            )

            for chord_source, gesture_variable, function_key in (
                (previous_chord_source, previous_variable, "f19"),
                (next_chord_source, next_variable, "f18"),
            ):
                chord, cooldown = by_source[chord_source]
                self.assertIn(
                    {"type": "variable_if", "name": gesture_variable, "value": 1},
                    chord["conditions"],
                )
                self.assertEqual(
                    chord["to"][0],
                    {"set_variable": {"name": gesture_variable, "value": 2}},
                )
                self.assertEqual(chord["to"][1]["key_code"], function_key)
                self.assertIs(chord["to"][1]["repeat"], False)
                self.assertIn(
                    {
                        "type": "expression_if",
                        "expression": (
                            f"({gesture_variable} > system.now.milliseconds) and "
                            f"({gesture_variable} <= system.now.milliseconds + 1000)"
                        ),
                    },
                    cooldown["conditions"],
                )
                self.assertEqual(
                    cooldown["to"][0],
                    {"set_variable": {"name": gesture_variable, "value": 0}},
                )
                self.assertEqual(cooldown["to"][1]["key_code"], function_key)
                self.assertIs(cooldown["to"][1]["repeat"], False)
                gesture_variables.add(gesture_variable)

        self.assertEqual(
            len(gesture_variables),
            4,
            "each direction and mouse must keep an independent gesture variable",
        )

        base_cases = (
            (
                "Agentic Mouse — Corsair base layer",
                exact_corsair_keyboard_condition(),
                "keypad_5",
                "keypad_4",
                "keypad_7",
                "button4",
                "corsair",
            ),
            (
                "Agentic Mouse — Razer base layer",
                exact_test_device_condition(),
                "5",
                "6",
                "9",
                "button4",
                "razer",
            ),
        )
        for (
            rule_name,
            device_condition,
            forward_source,
            clipboard_source,
            enter_source,
            back_button,
            mouse_source,
        ) in base_cases:
            rule = rules[rule_name]
            forward = next(
                manipulator
                for manipulator in rule["manipulators"]
                if manipulator["from"].get("key_code") == forward_source
            )
            back = next(
                manipulator
                for manipulator in rule["manipulators"]
                if manipulator["from"].get("key_code") in {"keypad_8", "8"}
            )
            enter = next(
                manipulator
                for manipulator in rule["manipulators"]
                if manipulator["from"].get("key_code") == enter_source
            )
            clipboard = next(
                manipulator
                for manipulator in rule["manipulators"]
                if manipulator["from"].get("key_code") == clipboard_source
            )
            for manipulator in [forward, back]:
                self.assertIn(device_condition, manipulator["conditions"])
                self.assertIn(vscode_unless_condition(), manipulator["conditions"])
            self.assertEqual(back["to"][0]["pointing_button"], back_button)
            self.assertIn(device_condition, enter["conditions"])
            self.assertNotIn(vscode_unless_condition(), enter["conditions"])
            self.assertEqual(enter["to"][0]["key_code"], "return_or_enter")
            self.assertIn(device_condition, clipboard["conditions"])
            self.assertNotIn(vscode_unless_condition(), clipboard["conditions"])
            self.assertEqual(
                clipboard["to"][0]["send_user_command"]["payload"]["control"],
                "clipboard",
            )
            self.assertEqual(
                forward["to"][0]["send_user_command"]["payload"],
                {
                    "command": "agentic_mouse_youtube_volume_modifier",
                    "source": mouse_source,
                    "phase": "press",
                },
            )
            self.assertEqual(
                forward["to_after_key_up"][0]["send_user_command"]["payload"],
                {
                    "command": "agentic_mouse_youtube_volume_modifier",
                    "source": mouse_source,
                    "phase": "release",
                },
            )

        youtube_scrub_cases = (
            (
                "Agentic Mouse — Corsair base layer",
                exact_corsair_keyboard_condition(),
                "keypad_6",
                "corsair",
            ),
            (
                "Agentic Mouse — Razer base layer",
                exact_test_device_condition(),
                "4",
                "razer",
            ),
        )
        for rule_name, device_condition, source, mouse_source in youtube_scrub_cases:
            youtube_scrub = next(
                manipulator
                for manipulator in rules[rule_name]["manipulators"]
                if manipulator["from"].get("key_code") == source
            )
            self.assertIn(device_condition, youtube_scrub["conditions"])
            self.assertNotIn(vscode_unless_condition(), youtube_scrub["conditions"])
            self.assertEqual(
                youtube_scrub["to"][0]["send_user_command"]["payload"],
                {
                    "command": "agentic_mouse_wheel_chord",
                    "control": "youtubeScrub",
                    "source": mouse_source,
                    "phase": "press",
                },
            )
            self.assertEqual(
                youtube_scrub["to_after_key_up"][0]["send_user_command"]["payload"],
                {
                    "command": "agentic_mouse_wheel_chord",
                    "control": "youtubeScrub",
                    "source": mouse_source,
                    "phase": "release",
                },
            )
            for lifecycle in [youtube_scrub["to"][0], youtube_scrub["to_after_key_up"][0]]:
                self.assertIs(lifecycle["repeat"], False)
                self.assertTrue(
                    any(
                        condition["type"] == "expression_if"
                        and "agentic_mouse_session_unlocked_expires_at"
                        in condition["expression"]
                        for condition in lifecycle["conditions"]
                    )
                )

    def test_action_sources_are_one_file_each_with_behavior_comments(self):
        paths = sorted(ACTIONS.rglob("*.jsonc"))
        self.assertTrue(paths)
        action_ids = []
        for path in paths:
            first = next(line.strip() for line in path.read_text().splitlines() if line.strip())
            self.assertTrue(first.startswith("//"), path)
            payload = "\n".join(
                line
                for line in path.read_text().splitlines()
                if not line.lstrip().startswith("//")
            )
            action = json.loads(payload)
            action_ids.append(action["id"])
            self.assertEqual(path.stem, action["id"])
            templates = action.get("manipulators", [action.get("manipulator")])
            self.assertTrue(templates)
            for template in templates:
                self.assertNotIn("from", template)
        self.assertIn("suppress-neutral-transport", action_ids)
        self.assertIn("hold-youtube-scrub-wheel-corsair", action_ids)
        self.assertIn("hold-youtube-scrub-wheel-razer", action_ids)
        self.assertNotIn("open-codex-intelligence-on-demand", action_ids)

    def test_binding_resolves_action_and_preserves_device_condition(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            bindings = temp / "bindings.json"
            output = temp / "agentic-mouse.json"
            catalog = temp / "catalog.json"
            bindings.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "bindings": [
                            {
                                "id": "test-razer-back",
                                "description": "Test-only Razer Back binding",
                                "action": "go-back",
                                "rule": "Test Razer layer",
                                "from": {"key_code": "1"},
                                "conditions": [exact_test_device_condition()],
                            }
                        ],
                    }
                )
            )
            result = self.run_generator(
                "--bindings",
                str(bindings),
                "--output",
                str(output),
                "--catalog-output",
                str(catalog),
            )
            self.assertEqual(result.returncode, 0, result.stderr)

            document = json.loads(output.read_text())
            self.assertEqual(document["rules"][0]["description"], "Agentic Mouse — Test Razer layer")
            manipulator = document["rules"][0]["manipulators"][0]
            self.assertEqual(manipulator["from"], {"key_code": "1"})
            self.assertEqual(manipulator["to"], [{"pointing_button": "button4"}])
            self.assertEqual(manipulator["conditions"][0]["type"], "device_if")

    def test_unknown_action_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            bindings = temp / "bindings.json"
            bindings.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "bindings": [
                            {
                                "id": "unknown-action-test",
                                "description": "Must fail",
                                "action": "does-not-exist",
                                "from": {"key_code": "f24"},
                                "conditions": [exact_test_device_condition()],
                            }
                        ],
                    }
                )
            )
            result = self.run_generator(
                "--bindings",
                str(bindings),
                "--output",
                str(temp / "out.json"),
                "--catalog-output",
                str(temp / "catalog.json"),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("unknown action", result.stderr)

    def test_binding_without_exact_device_condition_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            bindings = temp / "bindings.json"
            bindings.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "bindings": [
                            {
                                "id": "unsafe-global-binding",
                                "description": "Must not reach every keyboard",
                                "action": "go-back",
                                "from": {"key_code": "f24"},
                            }
                        ],
                    }
                )
            )
            result = self.run_generator(
                "--bindings",
                str(bindings),
                "--output",
                str(temp / "out.json"),
                "--catalog-output",
                str(temp / "catalog.json"),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("exact device_if", result.stderr)

    def test_every_action_compiles_to_lintable_karabiner_rules(self):
        actions = []
        for path in sorted(ACTIONS.rglob("*.jsonc")):
            payload = "\n".join(
                line
                for line in path.read_text().splitlines()
                if not line.lstrip().startswith("//")
            )
            actions.append(json.loads(payload))

        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            bindings = temp / "bindings.json"
            output = temp / "agentic-mouse.json"
            bindings.write_text(
                json.dumps(
                    {
                        "schemaVersion": 1,
                        "bindings": [
                            {
                                "id": f"test-{action_id}",
                                "description": f"Test-only {action_id}",
                                "action": action_id,
                                # Karabiner supports F1...F24. The semantic
                                # action catalog is intentionally larger than
                                # that, and these isolated test transports do
                                # not need to be unique.
                                "from": {"key_code": f"f{(index % 24) + 1}"},
                                "conditions": [exact_test_device_condition()],
                            }
                            for index, action in enumerate(actions)
                            for action_id in [action["id"]]
                        ],
                    }
                )
            )
            result = self.run_generator(
                "--bindings",
                str(bindings),
                "--output",
                str(output),
                "--catalog-output",
                str(temp / "catalog.json"),
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            document = json.loads(output.read_text())
            expected_manipulators = sum(
                len(action.get("manipulators", [action.get("manipulator")]))
                for action in actions
            )
            self.assertEqual(len(document["rules"][0]["manipulators"]), expected_manipulators)

            if KARABINER_CLI.is_file():
                lint = subprocess.run(
                    [
                        str(KARABINER_CLI),
                        "--lint-complex-modifications",
                        str(output),
                    ],
                    cwd=ROOT,
                    text=True,
                    capture_output=True,
                    check=False,
                )
                self.assertEqual(lint.returncode, 0, lint.stdout + lint.stderr)


if __name__ == "__main__":
    unittest.main()
