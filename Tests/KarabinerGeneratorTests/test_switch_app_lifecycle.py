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


if __name__ == "__main__":
    unittest.main()
