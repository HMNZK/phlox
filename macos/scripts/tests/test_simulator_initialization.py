"""通常起動とシミュレーター検証入口が初期化を共有する配線を検査する。"""
import pathlib
import unittest


APP = (pathlib.Path(__file__).resolve().parents[2] / "App/PhloxApp.swift").read_text()


class 初期化の配線検査(unittest.TestCase):
    def test_通常起動と検証入口は同じ初期化を待つ(self):
        normal = APP.split("private func initialize() async {", 1)[1].split("} catch {", 1)[0]
        debug = APP.split("func applicationDidFinishLaunching", 1)[1].split("#endif", 1)[0]
        self.assertIn("appDelegate.simulatorVerificationComposition()", normal)
        self.assertIn("self.simulatorVerificationComposition()", debug)
        self.assertNotIn("CompositionRoot()", debug)

    def test_初期化中も完了後も既存のタスクを再利用する(self):
        self.assertTrue("func simulatorVerificationComposition()" in APP, "共有する初期化が必要")
        method = APP.split("func simulatorVerificationComposition()", 1)[1].split("\n    #endif", 1)[0]
        self.assertLess(method.index("if let task = simulatorVerificationInitialization"),
                        method.index("try await CompositionRoot"))
        self.assertLess(method.index("simulatorVerificationInitialization = task"),
                        method.index("do { return try await task.value }"))
        self.assertIn("simulatorVerificationInitializationID == id", method)


if __name__ == "__main__":
    unittest.main(verbosity=2)
