import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import zipfile

spec = importlib.util.spec_from_file_location("prepare_ad_hoc", Path(__file__).with_name("prepare-ad-hoc.py"))
distribution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(distribution)


class DistributionTests(unittest.TestCase):
    def test_archive_build_number_must_match_for_both_bundles(self):
        app = Path("App.app")
        widget = app / "PlugIns/Widget.appex"
        for versions, succeeds in ((("1", "1"), False), (("2", "1"), False),
                                   (("1", "2"), False), (("2", "2"), True)):
            with self.subTest(versions=versions), \
                    patch.object(Path, "glob", return_value=[widget]), \
                    patch.object(Path, "open"), \
                    patch.object(distribution.plistlib, "load", side_effect=[
                        {"CFBundleVersion": version} for version in versions]):
                if succeeds:
                    distribution.verify_build_number(app, 2)
                else:
                    with self.assertRaisesRegex(ValueError, "ビルド番号"):
                        distribution.verify_build_number(app, 2)

    def test_development_profile_is_rejected(self):
        team = "9JGGMW6UW6"
        entitlements = {"com.apple.developer.team-identifier": team, "get-task-allow": False}
        profile = {"TeamIdentifier": [team], "ProvisionedDevices": ["registered-device"],
                   "Entitlements": {"get-task-allow": True}}
        with patch.object(Path, "glob", return_value=[Path("Widget.appex")]), \
                patch.object(distribution, "run"), \
                patch.object(distribution.subprocess, "run", return_value=SimpleNamespace(stdout=plistlib.dumps(entitlements))), \
                patch.object(distribution.subprocess, "check_output", return_value=plistlib.dumps(profile)):
            with self.assertRaisesRegex(ValueError, "Ad Hoc"):
                distribution.verify_signatures(Path("App.app"), team)

    def test_url_boundary(self):
        self.assertEqual(distribution.base_url("https://mac.tail.ts.net/phlox ios"),
                         "https://mac.tail.ts.net/phlox%20ios/")
        for value in ("http://mac.tail.ts.net/", "https://example.com/", "https://ts.net/",
                      "https://user@mac.tail.ts.net/", "https://mac.tail.ts.net/?x=1",
                      "https://mac.tail.ts.net/#x", "https://mac.tail.ts.net/a/../b",
                      "https://mac.tail.ts.net/%2e%2e/", "https://mac.tail.ts.net:8443/"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                distribution.base_url(value)

    def test_manifest_and_widget_requirement(self):
        scratch = Path(__file__).resolve().parents[2] / ".verification"
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="ad-hoc-script-tests-", dir=scratch) as directory:
            root = Path(directory)
            (root / "OWNER.txt").write_text("用途: 配布スクリプトの一時テストデータ。作成: test_prepare_ad_hoc.py。常駐プロセスなし。\n")
            ipa = root / "PhloxMobile.ipa"
            app = {"CFBundleIdentifier": "com.phlox.mobile.PhloxMobile", "CFBundleVersion": "2",
                   "CFBundleShortVersionString": "0.1.0<&"}
            widget = {"CFBundleIdentifier": "com.phlox.mobile.PhloxMobile.PhloxWidget", "CFBundleVersion": "2"}
            with zipfile.ZipFile(ipa, "w") as archive:
                archive.writestr("Payload/PhloxMobile.app/Info.plist", plistlib.dumps(app))
            with self.assertRaisesRegex(ValueError, "Widget"):
                distribution.write_install_files(ipa, root, "https://mac.tail.ts.net/phlox/")
            with zipfile.ZipFile(ipa, "a") as archive:
                archive.writestr("Payload/PhloxMobile.app/PlugIns/PhloxWidget.appex/Info.plist", plistlib.dumps(widget))
            distribution.write_install_files(ipa, root, "https://mac.tail.ts.net/phlox/")
            manifest = plistlib.loads((root / "manifest.plist").read_bytes())
            self.assertEqual(manifest["items"][0]["assets"][0]["url"],
                             "https://mac.tail.ts.net/phlox/PhloxMobile.ipa")
            page = (root / "index.html").read_text()
            self.assertIn("0.1.0&lt;&amp;", page)
            self.assertIn("&amp;url=https%3A%2F%2Fmac.tail.ts.net%2Fphlox%2Fmanifest.plist", page)


if __name__ == "__main__":
    unittest.main()
