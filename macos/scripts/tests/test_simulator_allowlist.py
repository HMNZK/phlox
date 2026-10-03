"""公開前の Xcode build 照合が、許可リストと取得失敗を正しく扱うか検査する。"""
import importlib.util
import pathlib
import subprocess
import unittest
from unittest import mock


MACOS = pathlib.Path(__file__).resolve().parents[2]


class 許可リストの公開前検査(unittest.TestCase):
    def setUp(self):
        spec = importlib.util.spec_from_file_location(
            "verify_simulator_allowlist", MACOS / "scripts/verify-simulator-allowlist.py"
        )
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)

    def 実行(self, output, source=None):
        process = subprocess.CompletedProcess(["xcodebuild", "-version"], 0, output, "")
        with mock.patch.object(self.module.subprocess, "run", return_value=process) as run:
            if source is None:
                result = self.module.main()
            else:
                with mock.patch.object(pathlib.Path, "read_text", return_value=source):
                    result = self.module.main()
            run.assert_called_once_with(
                ["xcodebuild", "-version"], check=True, capture_output=True, text=True
            )
        return result

    def test_記録された正式版の組を許可する(self):
        self.assertEqual(self.実行("Xcode 26.2\nBuild version 17C52\n"), 0)

    def test_未記録のビルドを拒否する(self):
        self.assertEqual(self.実行("Xcode 27.0\nBuild version 18A1\n"), 1)

    def test_ビルドの部分一致を拒否する(self):
        self.assertEqual(self.実行("Xcode 26.2\nBuild version 17C5\n"), 1)

    def test_許可リスト外のエントリーやコメントは数えない(self):
        source = '''
// Entry(xcodeBuild: "18A1", runtimeIdentifier: "ios", supportsInput: true)
static let sample = Entry(xcodeBuild: "18A1", runtimeIdentifier: "ios", supportsInput: true)
static let verified = SimulatorPolicy(entries: [
    // Entry(xcodeBuild: "18A1", runtimeIdentifier: "ios", supportsInput: true)
    Entry(xcodeBuild: "17C52", runtimeIdentifier: "ios", supportsInput: false),
])
'''
        self.assertEqual(self.実行("Xcode 27.0\nBuild version 18A1\n", source), 1)

    def test_ビルド取得失敗を拒否する(self):
        with mock.patch.object(self.module.subprocess, "run", side_effect=
                               subprocess.CalledProcessError(1, "xcodebuild", stderr="失敗")):
            self.assertEqual(self.module.main(), 1)

    def test_形式不明の出力を拒否する(self):
        self.assertEqual(self.実行("Xcode 26.2\n"), 1)

    def test_公開手順より先に照合を置く(self):
        document = (MACOS / "docs/operations/site-deploy-and-release.md").read_text()
        self.assertLess(document.index("### シミュレーターの許可リスト"),
                        document.index("リリース時は **3 箇所**"))
        self.assertIn("python3 macos/scripts/verify-simulator-allowlist.py", document)

    def test_表示品質ゲートは許可リスト検査もラッパー経由で実行する(self):
        gate = (MACOS / "scripts/verify-simulator-display.sh").read_text()
        self.assertIn('"$HOME/.agents/scripts/compact-test" simulator-allowlist ' + "\\\n"
                      + '  python3 "$MACOS_DIR/scripts/tests/test_simulator_allowlist.py"', gate)

    def test_ハーネスは互換性検査を明示し実行モードを結果へ記録する(self):
        runner = (MACOS / "Tests/SimulatorInputHarness/run.py").read_text()
        host = (MACOS / "Tests/SimulatorInputHarness/Host/InputHarness.swift").read_text()
        self.assertIn('parser.add_argument("--compatibility-check"', runner)
        self.assertIn('"実行モード":', runner)
        self.assertIn('args.compatibility_check', runner)
        self.assertIn('contains("--compatibility-check")', host)
        self.assertIn('connection.configureForCompatibilityCheck(runtime: runtime)', host)
        self.assertIn('connection.configureVerifiedRuntime(runtime)', host)

    def test_互換性検査の入口はDebugビルドだけに置く(self):
        src = (MACOS / "Packages/DashboardFeature/Sources/DashboardFeature/Simulator/SimulatorDisplayConnection.swift").read_text()
        entry = src.index("func configureForCompatibilityCheck(")
        start = src.rindex("#if DEBUG", 0, entry)
        self.assertNotIn("#endif", src[start:entry])
        self.assertLess(entry, src.index("#endif", entry))

    def test_背景タップはフォーカス準備でも前面化しない(self):
        host = (MACOS / "Tests/SimulatorInputHarness/Host/InputHarness.swift").read_text()
        focus = host.split('private func focusScreen() throws {', 1)[1].split('private func scroll', 1)[0]
        guard = focus.index('if !ProcessInfo.processInfo.arguments.contains("--background-tap")')
        self.assertLess(guard, focus.index('window?.makeKeyAndOrderFront(nil)'))
        self.assertLess(guard, focus.index('NSApplication.shared.activate(ignoringOtherApps: true)'))


if __name__ == "__main__":
    unittest.main(verbosity=2)
