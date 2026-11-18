import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
ACTION = (
    ROOT
    / "Karabiner"
    / "actions"
    / "app-switching"
    / "hold-open-app-switcher.jsonc"
)


def load_jsonc(path: Path) -> dict:
    return json.loads(
        "\n".join(
            line
            for line in path.read_text(encoding="utf-8").splitlines()
            if not line.lstrip().startswith("//")
        )
    )


class SwitchAppLifecycleTests(unittest.TestCase):
    def test_action_sends_one_command_tab_then_holds_command_until_source_release(self):
        action = load_jsonc(ACTION)
        manipulator = action["manipulator"]

        self.assertEqual(
            manipulator["to"],
            [
                {"set_variable": {"name": "$binding_variable", "value": 1, "key_up_value": 0}},
                {
                    "key_code": "tab",
                    "modifiers": ["left_command"],
                    "repeat": False,
                },
                {
                    "key_code": "left_command",
                    "repeat": True,
                },
            ],
        )

        serialized = json.dumps(manipulator)
        self.assertNotIn("sticky_modifier", serialized)
        self.assertNotIn("send_user_command", serialized)
        self.assertNotIn("parameters", manipulator)
        self.assertNotIn("to_after_key_up", manipulator)
        self.assertNotIn("to_delayed_action", manipulator)
        self.assertNotIn("to_if_held_down", manipulator)
        self.assertNotIn("to_if_alone", manipulator)

    def test_wheel_click_cancels_before_showing_windows_and_keeps_plain_play_pause(self):
        runtime = json.loads((ROOT / "Karabiner/generated/agentic-mouse-runtime.json").read_text())
        for name, other, vendor, product, switch_key in (
            ("corsair", "razer", 6940, 11008, "keypad_hyphen"),
            ("razer", "corsair", 5426, 141, "hyphen"),
        ):
            with self.subTest(source=name):
                rule = next(r for r in runtime["rules"] if r["description"] == f"Agentic Mouse — {name.title()} base layer")
                hold = next(m for m in rule["manipulators"] if m["from"].get("key_code") == switch_key)
                variable = hold["to"][0]["set_variable"]
                self.assertEqual((variable["value"], variable["key_up_value"]), (1, 0))
                wheel_routes = [m for m in rule["manipulators"] if m["from"].get("pointing_button") == "button3"]
                expose, suppress, play_pause = wheel_routes
                for route in wheel_routes:
                    self.assertIn({
                        "type": "device_if",
                        "identifiers": [{"vendor_id": vendor, "product_id": product, "is_pointing_device": True}],
                    }, route["conditions"])
                self.assertEqual(expose["from"]["modifiers"], {
                    "mandatory": ["left_command"],
                    "optional": ["caps_lock"],
                })
                self.assertIn({"type": "variable_if", "name": variable["name"], "value": 1}, expose["conditions"])
                self.assertTrue(any(other in c.get("expression", "") and c["type"] == "expression_if"
                                    for c in expose["conditions"]))
                self.assertTrue(any(f"mode_picker_{name}_expires_at" in c.get("expression", "")
                                    and c["type"] == "expression_unless" for c in expose["conditions"]))
                outputs = [{k: v for k, v in e.items() if k != "conditions"} for e in expose["to"]]
                self.assertEqual(outputs, [
                    {"key_code": "escape", "modifiers": ["left_command"], "repeat": False},
                    {"key_code": "down_arrow", "modifiers": ["left_control", "fn"], "repeat": False},
                    {"set_variable": {"name": variable["name"], "value": 2}},
                ])
                self.assertTrue(all(e["conditions"] for e in expose["to"][:2]), "native output must stay unlock-gated")
                self.assertEqual(suppress["to"], [])
                self.assertEqual(play_pause["from"]["modifiers"], {"optional": ["any"]})
                self.assertEqual(play_pause["to"][0]["consumer_key_code"], "play_or_pause")


if __name__ == "__main__":
    unittest.main()
