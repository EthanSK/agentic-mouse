"""Exercise package preflight without building, signing, or touching an installed app."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class PackagePreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "Scripts").mkdir()
        (self.root / "Resources").mkdir()
        shutil.copy2(ROOT / "Scripts/package-app.sh", self.root / "Scripts/package-app.sh")
        shutil.copy2(ROOT / "Resources/Info.plist", self.root / "Resources/Info.plist")
        self.version = (self.root / "Resources/Info.plist").read_bytes()
        self.candidate = self.root / "build/AgenticMouse.app/preserved"
        self.candidate.parent.mkdir(parents=True)
        self.candidate.write_text("previous candidate")
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.fake("security", 'printf \'  1) ABC "Developer ID Application: Test Owner (TEST)"\\n\'')
        self.fake("swift", "exit 91")

    def fake(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\n" + body + "\n")
        path.chmod(0o755)

    def run_package(self, **values):
        env = {**os.environ, "PATH": str(self.bin) + ":" + os.environ["PATH"],
               "CODE_SIGN_IDENTITY": "-", "REQUIRE_ICUE_SDK": "1",
               "INSTALL_CANDIDATE": "1", "RELEASE_VERSION": "",
               "ICUE_SDK_FRAMEWORK": str(self.root / "absent")}
        env.update(values)
        result = subprocess.run(["bash", str(self.root / "Scripts/package-app.sh")],
                                env=env, text=True, capture_output=True)
        self.assertEqual(self.candidate.read_text(), "previous candidate")
        self.assertEqual((self.root / "Resources/Info.plist").read_bytes(), self.version)
        return result

    def test_ad_hoc_install_is_refused_before_build(self):
        result = self.run_package()
        self.assertEqual(result.returncode, 1)
        self.assertIn("requires a stable Developer ID", result.stderr)

    def test_missing_owner_identity_is_refused_before_build(self):
        result = self.run_package(CODE_SIGN_IDENTITY="Developer ID Application: Missing (NONE)")
        self.assertEqual(result.returncode, 1)
        self.assertIn("signing identity is unavailable", result.stderr)

    def test_required_sdk_is_refused_before_build(self):
        result = self.run_package(CODE_SIGN_IDENTITY="Developer ID Application: Test Owner (TEST)")
        self.assertEqual(result.returncode, 1)
        self.assertIn("set ICUE_SDK_FRAMEWORK", result.stderr)

    def test_explicit_sdk_free_candidate_reaches_build(self):
        result = self.run_package(CODE_SIGN_IDENTITY="Developer ID Application: Test Owner (TEST)",
                                  REQUIRE_ICUE_SDK="0")
        self.assertEqual(result.returncode, 91)

    def test_development_bundle_needs_neither_identity_nor_sdk(self):
        result = self.run_package(INSTALL_CANDIDATE="0")
        self.assertEqual(result.returncode, 91)

    def test_invalid_sdk_requirement_is_refused(self):
        result = self.run_package(INSTALL_CANDIDATE="0", REQUIRE_ICUE_SDK="maybe")
        self.assertEqual(result.returncode, 64)
        self.assertIn("must be 0 or 1", result.stderr)


if __name__ == "__main__":
    unittest.main()
