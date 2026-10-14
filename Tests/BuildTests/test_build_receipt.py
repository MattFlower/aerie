import importlib.util
import json
import plistlib
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/check-app-build.py"
spec = importlib.util.spec_from_file_location("aerie_build_check", SCRIPT)
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class BuildReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.app = Path(self.temporary.name) / "Aerie.app"
        (self.app / "Contents/MacOS").mkdir(parents=True)
        self.executable = self.app / "Contents/MacOS/Aerie"
        self.executable.write_bytes(b"synthetic executable fixture")
        (self.app / "Contents/Resources").mkdir()
        self.icon = self.app / "Contents/Resources/AppIcon.icns"
        # Synthetic container payload; real image decoding is a separate native bundle check.
        self.icon.write_bytes(b"icns" + (12).to_bytes(4, "big") + b"test")
        self.revision = "1" * 40
        self.info = {"CFBundleIdentifier": "app.aerie.monitor", "CFBundleIconFile": "AppIcon.icns",
                     "AerieSourceRevision": self.revision, "AerieSourceModified": False}
        self.save_info()

    def save_info(self):
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps(self.info))

    def receipt(self):
        return build.write_receipt(self.app, self.revision, False)

    def test_matching_revision_and_exact_binary_are_accepted_without_launch(self):
        expected = self.receipt()
        self.assertEqual(build.verify_metadata(self.app, self.revision), expected)
        self.assertEqual(set(expected), {"format", "sourceRevision", "sourceModified", "binarySHA256", "appIconSHA256"})

    def test_stale_revision_is_rejected(self):
        self.receipt()
        with self.assertRaises(build.BuildMismatch):
            build.verify_metadata(self.app, "2" * 40)

    def test_replaced_executable_is_rejected(self):
        self.receipt()
        self.executable.write_bytes(b"different synthetic binary")
        with self.assertRaises(build.BuildMismatch):
            build.verify_metadata(self.app, self.revision)

    def test_old_unstamped_bundle_is_rejected(self):
        self.info.pop("AerieSourceRevision")
        self.save_info()
        with self.assertRaises(build.BuildMismatch):
            build.verify_metadata(self.app, self.revision)

    def test_modified_build_and_modified_checkout_are_rejected(self):
        self.receipt()
        with self.assertRaises(build.BuildMismatch):
            build.verify_metadata(self.app, self.revision, current_modified=True)
        self.info["AerieSourceModified"] = True
        self.save_info()
        build.write_receipt(self.app, self.revision, True)
        with self.assertRaises(build.BuildMismatch):
            build.verify_metadata(self.app, self.revision)

    def test_mismatched_and_oversized_receipts_are_rejected(self):
        record = self.receipt()
        record["sourceRevision"] = "2" * 40
        build.receipt_path(self.app).write_text(json.dumps(record))
        with self.assertRaises(build.BuildMismatch):
            build.verify_metadata(self.app, self.revision)
        build.receipt_path(self.app).write_bytes(b" " * 8193)
        with self.assertRaises(build.BuildMismatch):
            build.verify_metadata(self.app, self.revision)

    def test_receipt_cannot_certify_another_bundle_or_source_state(self):
        with self.assertRaises(build.BuildMismatch):
            build.write_receipt(self.app, "2" * 40, False)
        self.info["CFBundleIdentifier"] = "example.synthetic.other"
        self.save_info()
        with self.assertRaises(build.BuildMismatch):
            self.receipt()

    def test_missing_or_replaced_icon_is_rejected(self):
        self.receipt()
        self.icon.write_bytes(b"icns" + (13).to_bytes(4, "big") + b"other")
        with self.assertRaises(build.BuildMismatch):
            build.verify_metadata(self.app, self.revision)
        self.icon.unlink()
        with self.assertRaises(build.BuildMismatch):
            build.verify_metadata(self.app, self.revision)

    def test_invalid_icon_metadata_and_container_are_rejected(self):
        self.info["CFBundleIconFile"] = "../Other.icns"
        self.save_info()
        with self.assertRaises(build.BuildMismatch):
            self.receipt()
        self.info["CFBundleIconFile"] = "AppIcon.icns"
        self.save_info()
        self.icon.write_bytes(b"icns" + (500).to_bytes(4, "big") + b"test")
        with self.assertRaises(build.BuildMismatch):
            self.receipt()

    def test_missing_receipt_is_rejected(self):
        with self.assertRaises(build.BuildMismatch):
            build.verify_metadata(self.app, self.revision)


if __name__ == "__main__":
    unittest.main()
