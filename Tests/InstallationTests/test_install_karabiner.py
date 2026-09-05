import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/install-live-karabiner.py"
SPEC = importlib.util.spec_from_file_location("install_karabiner", SCRIPT)
INSTALLER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALLER)


class KarabinerInstallationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.live = self.root / "karabiner.json"
        self.backup = self.root / "backup.json"
        self.generated = ROOT / "Karabiner/generated/agentic-mouse-runtime.json"
        self.runtime = json.loads(self.generated.read_text())["rules"]
        self.original = {
            "global": {"show_in_menu_bar": True},
            "profiles": [
                {"selected": True, "name": "My profile", "complex_modifications": {
                    "parameters": {"basic.to_if_alone_timeout_milliseconds": 250},
                    "rules": [{"description": "Keep my keyboard rule", "manipulators": []}],
                }},
                {"selected": False, "name": "Other", "devices": [{"example": "preserve"}]},
            ],
        }
        self.write(self.original)

    def write(self, document):
        self.live.write_text(json.dumps(document, indent=2) + "\n")

    def run_installer(self, *flags, digest=None, generated=None):
        arguments = [str(SCRIPT), "--live", str(self.live), "--generated", str(generated or self.generated),
                     "--expected-live-sha256", digest or hashlib.sha256(self.live.read_bytes()).hexdigest(),
                     "--backup", str(self.backup), *flags]
        with patch("sys.argv", arguments):
            return INSTALLER.main()

    def test_first_install_dry_run_preserves_all_bytes_and_creates_no_backup(self):
        before = self.live.read_bytes()
        with patch.object(INSTALLER, "close_runtime_modes") as close:
            self.assertEqual(self.run_installer("--initialize"), 0)
            close.assert_not_called()
        self.assertEqual(self.live.read_bytes(), before)
        self.assertFalse(self.backup.exists())

    def test_first_install_backs_up_and_preserves_every_unrelated_setting(self):
        before = self.live.read_bytes()
        with patch.object(INSTALLER, "close_runtime_modes") as close:
            self.run_installer("--initialize", "--apply")
            close.assert_not_called()
        expected = copy.deepcopy(self.original)
        expected["profiles"][0]["complex_modifications"]["rules"] = self.runtime + expected["profiles"][0]["complex_modifications"]["rules"]
        self.assertEqual(json.loads(self.live.read_text()), expected)
        self.assertEqual(self.backup.read_bytes(), before)

    def test_first_install_accepts_a_fresh_profile_without_a_rules_list(self):
        self.original["profiles"][0].pop("complex_modifications")
        self.write(self.original)
        self.run_installer("--initialize", "--apply")
        installed = json.loads(self.live.read_text())
        self.assertEqual(installed["profiles"][0]["complex_modifications"]["rules"], self.runtime)
        self.assertEqual(installed["profiles"][1], self.original["profiles"][1])

    def test_initialization_refuses_existing_block_without_touching_files(self):
        self.original["profiles"][0]["complex_modifications"]["rules"] += self.runtime
        self.write(self.original)
        before = self.live.read_bytes()
        with self.assertRaisesRegex(SystemExit, "already exist"):
            self.run_installer("--initialize", "--apply")
        self.assertEqual(self.live.read_bytes(), before)
        self.assertFalse(self.backup.exists())

    def test_update_still_requires_a_receiver_and_preserves_the_original_block_position(self):
        rules = self.original["profiles"][0]["complex_modifications"]["rules"]
        rules += self.runtime + [{"description": "Last unrelated rule", "manipulators": []}]
        self.write(self.original)
        before = self.live.read_bytes()
        with patch.object(INSTALLER, "close_runtime_modes", side_effect=RuntimeError("no receiver")):
            with self.assertRaisesRegex(RuntimeError, "no receiver"):
                self.run_installer("--apply")
        self.assertFalse(self.backup.exists())
        self.assertEqual(self.live.read_bytes(), before)
        with patch.object(INSTALLER, "close_runtime_modes") as close:
            self.run_installer("--apply")
            close.assert_called_once_with()
        self.assertEqual(json.loads(self.live.read_text()), self.original)

    def test_stale_digest_and_existing_backup_refuse_writes(self):
        before = self.live.read_bytes()
        with self.assertRaisesRegex(SystemExit, "live Karabiner changed"):
            self.run_installer("--initialize", "--apply", digest="0" * 64)
        self.backup.write_text("keep this backup")
        with self.assertRaisesRegex(SystemExit, "overwrite backup"):
            self.run_installer("--initialize", "--apply")
        self.assertEqual(self.live.read_bytes(), before)
        self.assertEqual(self.backup.read_text(), "keep this backup")

    def test_partial_base_artifact_is_rejected_for_first_install(self):
        with self.assertRaisesRegex(SystemExit, "exactly one runtime Modes rule"):
            self.run_installer("--initialize", "--apply", generated=ROOT / "Karabiner/generated/agentic-mouse.json")
        self.assertFalse(self.backup.exists())

    def test_interleaved_existing_rules_are_not_reordered_by_update(self):
        self.original["profiles"][0]["complex_modifications"]["rules"] = [self.runtime[0], {"description": "My rule"}, *self.runtime[1:]]
        self.write(self.original)
        with self.assertRaisesRegex(SystemExit, "contiguous"):
            self.run_installer("--apply")
        self.assertFalse(self.backup.exists())


if __name__ == "__main__":
    unittest.main()
