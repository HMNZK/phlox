"""署名設定と、本体に非公開部品が混入した場合の検出を検証する。"""
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[2]
PROJECT = (ROOT / "project.yml").read_text()
namespace = {"__name__": "署名検査"}
source = (ROOT / "scripts/tests/test_simulator_bridge_signing.sh").read_text().split("<<'PY'\n", 1)[1].rsplit("\nPY", 1)[0]
arguments = sys.argv
sys.argv = ["署名検査", str(ROOT), str(ROOT)]
exec(source.rsplit("unittest.main(verbosity=2)", 1)[0], namespace)
sys.argv = arguments


class 回帰検査(unittest.TestCase):
    def test_runtimeはXPCとteam付き本体に必須(self):
        original = ROOT.parent / ".build/DerivedData/Build/Products/Debug/Phlox.app"
        namespace["app"] = original
        for team, host_runtime, helper_runtime, succeeds in [
            ("not set", False, True, True),
            ("検証チーム", True, True, True),
            ("検証チーム", False, True, False),
            ("not set", False, False, False),
        ]:
            with self.subTest(team=team, host_runtime=host_runtime, helper_runtime=helper_runtime):
                def signing(*args):
                    runtime = host_runtime if args[-1] == str(original) else helper_runtime
                    signature = "TeamIdentifier=" + team + "\nflags=" + ("runtime" if runtime else "none")
                    return subprocess.CompletedProcess(args, 0, "", signature)
                with patch.dict(namespace, run=signing):
                    case = namespace["署名検査"]("test_両署名とhardenedRuntimeと実際の権限")
                    if succeeds:
                        case.test_両署名とhardenedRuntimeと実際の権限()
                    else:
                        with self.assertRaisesRegex(AssertionError, "runtime"):
                            case.test_両署名とhardenedRuntimeと実際の権限()

    def test_本体のadhoc署名にruntimeを強制しない(self):
        host = PROJECT.split("  Phlox:\n", 1)[1].split("  SimulatorBridgeService:\n", 1)[0]
        helper = PROJECT.split("  SimulatorBridgeService:\n", 1)[1].split("  PhloxUITests:\n", 1)[0]
        self.assertNotIn("OTHER_CODE_SIGN_FLAGS: --options runtime", host)
        self.assertIn("OTHER_CODE_SIGN_FLAGS: --options runtime", helper)

    def test_版はprojectの共通設定で一度だけ指定する(self):
        common = PROJECT.split("targets:\n", 1)[0]
        for key in ["MARKETING_VERSION", "CURRENT_PROJECT_VERSION"]:
            self.assertEqual(PROJECT.count(key + ":"), 1)
            self.assertIn(key + ":", common)

    def test_debug実体と入れ子のMachOのdlopenパスを検出する(self):
        for location in ["MacOS/Phlox.debug.dylib", "Frameworks/検証.framework/検証"]:
            for framework in ["CoreSimulator.framework", "SimulatorKit.framework"]:
                with self.subTest(location=location, framework=framework):
                    self.検査用アプリ(location, framework)

    def 検査用アプリ(self, location, framework):
        with tempfile.TemporaryDirectory(dir=ROOT.parent / ".build") as directory:
            app = pathlib.Path(directory) / "Phlox.app"
            contents = app / "Contents"
            (contents / "MacOS").mkdir(parents=True)
            original = ROOT.parent / ".build/DerivedData/Build/Products/Debug/Phlox.app/Contents"
            shutil.copy(original / "Info.plist", contents)
            shutil.copy(original / "MacOS/Phlox", contents / "MacOS")
            shutil.copy(original / "MacOS/Phlox.debug.dylib", contents / "MacOS")
            shutil.copytree(original / "XPCServices", contents / "XPCServices")
            binary = contents / location
            binary.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["xcrun", "clang", "-dynamiclib", "-x", "c", "-o", str(binary), "-"],
                           input='const char *部品 = "/Library/PrivateFrameworks/' + framework + '";',
                           text=True, capture_output=True, check=True)
            namespace["app"] = app
            case = namespace["署名検査"]("test_本体に非公開フレームワークをリンクしない")
            with self.assertRaisesRegex(AssertionError, framework):
                case.test_本体に非公開フレームワークをリンクしない()
            binary.unlink()
            debug = contents / "MacOS/Phlox.debug.dylib"
            shutil.copy(original / "MacOS/Phlox.debug.dylib", debug)
            case.test_本体に非公開フレームワークをリンクしない()
            debug.unlink()
            with self.assertRaisesRegex(AssertionError, "Debug の実体"):
                case.test_本体に非公開フレームワークをリンクしない()
            shutil.copy(original / "MacOS/Phlox.debug.dylib", debug)
            helper = next((contents / "XPCServices").glob("*.xpc"))
            helper_info = namespace["plist"](helper / "Contents/Info.plist")
            shutil.copy(original / "MacOS/Phlox", helper / "Contents/MacOS" / helper_info["CFBundleExecutable"])
            with self.assertRaisesRegex(AssertionError, "対照の XPC"):
                case.test_本体に非公開フレームワークをリンクしない()


if __name__ == "__main__":
    unittest.main(verbosity=2)
