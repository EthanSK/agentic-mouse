"""Reject stale checkouts and raced candidates using isolated fake app bundles."""
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("provenance", ROOT / "Scripts/install-provenance.py")
P = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(P)


class InstallProvenanceTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.repo = self.root / "canonical"
        (self.repo / "Sources").mkdir(parents=True)
        (self.repo / "Sources/control.swift").write_text("Speed + Wheel")
        self.installed = self.root / "installed.app"
        self.candidate = self.root / "candidate.app"
        self.app(self.installed, "1.0.255", 261, b"running app")
        self.app(self.candidate, "1.0.256", 262, b"combined candidate")
        fake_git = patch.object(P.subprocess, "check_output", return_value="head\n")
        fake_git.start()
        self.addCleanup(fake_git.stop)
        self.manifest = P.prepare(self.repo, self.installed, "1.0.256", 262)
        (self.candidate / P.MANIFEST).write_text(json.dumps(self.manifest))

    def app(self, path, marketing, build, executable):
        (path / "Contents/MacOS").mkdir(parents=True)
        (path / "Contents/Resources").mkdir()
        (path / "Contents/MacOS/AgenticMouse").write_bytes(executable)
        (path / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleShortVersionString": marketing, "CFBundleVersion": str(build)}))

    def test_combined_source_candidate_is_accepted(self):
        P.verify(self.candidate, self.installed)

    def test_new_version_from_different_checkout_is_refused(self):
        (self.installed / P.MANIFEST).write_text(json.dumps(self.manifest))
        stale = self.root / "stale"
        stale.mkdir()
        with self.assertRaisesRegex(ValueError, "different source checkout"):
            P.prepare(stale, self.installed, "1.0.999", 999)

    def test_higher_marketing_with_reused_build_is_refused(self):
        with self.assertRaisesRegex(ValueError, "advance both versions"):
            P.prepare(self.repo, self.installed, "1.0.256", 261)

    def test_lower_marketing_with_higher_build_is_refused(self):
        with self.assertRaisesRegex(ValueError, "advance both versions"):
            P.prepare(self.repo, self.installed, "1.0.254", 999)

    def test_concurrent_install_invalidates_prepared_candidate(self):
        (self.installed / "Contents/MacOS/AgenticMouse").write_bytes(b"another chat installed")
        with self.assertRaisesRegex(ValueError, "installed app changed"):
            P.verify(self.candidate, self.installed)

    def test_edit_during_packaging_invalidates_source_snapshot(self):
        (self.repo / "Sources/control.swift").write_text("Spare")
        with self.assertRaisesRegex(ValueError, "source changed"):
            P.check_source(self.manifest)

    def test_untracked_feature_is_part_of_source_digest(self):
        (self.repo / "Sources/uncommitted.swift").write_text("new feature")
        with self.assertRaisesRegex(ValueError, "source differs"):
            P.verify(self.candidate, self.installed)

    def test_candidate_version_must_match_signed_manifest(self):
        info = self.candidate / "Contents/Info.plist"
        info.write_bytes(plistlib.dumps({"CFBundleShortVersionString": "1.0.999", "CFBundleVersion": "999"}))
        with self.assertRaisesRegex(ValueError, "version differs"):
            P.verify(self.candidate, self.installed)

    def test_first_install_without_parent_is_supported(self):
        missing = self.root / "absent.app"
        manifest = P.prepare(self.repo, missing, "1.0.256", 262)
        self.assertIsNone(manifest["parentExecutableSHA256"])


if __name__ == "__main__":
    unittest.main()
