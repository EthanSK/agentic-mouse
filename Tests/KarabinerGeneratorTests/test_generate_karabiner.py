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
        self.assertIn("12 semantic actions and 0 physical bindings", result.stdout)

    def test_action_sources_are_one_file_each_with_behavior_comments(self):
        paths = sorted(ACTIONS.rglob("*.jsonc"))
        self.assertEqual(len(paths), 12)
        for path in paths:
            first = next(line.strip() for line in path.read_text().splitlines() if line.strip())
            self.assertTrue(first.startswith("//"), path)
            payload = "\n".join(
                line
                for line in path.read_text().splitlines()
                if not line.lstrip().startswith("//")
            )
            action = json.loads(payload)
            self.assertEqual(path.stem, action["id"])
            self.assertNotIn("from", action["manipulator"])

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
        action_ids = []
        for path in sorted(ACTIONS.rglob("*.jsonc")):
            payload = "\n".join(
                line
                for line in path.read_text().splitlines()
                if not line.lstrip().startswith("//")
            )
            action_ids.append(json.loads(payload)["id"])

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
                                "from": {"key_code": f"f{index + 1}"},
                                "conditions": [exact_test_device_condition()],
                            }
                            for index, action_id in enumerate(action_ids)
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
            self.assertEqual(len(document["rules"][0]["manipulators"]), len(action_ids))

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
