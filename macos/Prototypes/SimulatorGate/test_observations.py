"""配送の戻り値ではなく、保存された実行結果を検査する。"""
import json
from pathlib import Path
import unittest
import subprocess

ROOT = Path(__file__).resolve().parent / "Records"


def rows(name):
    return [json.loads(line) for line in (ROOT / name).read_text().splitlines()]


class Observations(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.host = rows("host.jsonl")
        cls.service = rows("service.jsonl")
        cls.events = json.loads((ROOT / "events.json").read_text())

    def test_frameworks_loaded_in_service(self):
        self.assertEqual(sum("読み込み成功" in row for row in self.service), 2)
        self.assertFalse(any("読み込み失敗" in row or "例外" in row for row in self.service))

    def test_shared_surface_updates(self):
        samples = [row for row in self.host if "surfaceID" in row and row["経過秒"] < 12]
        self.assertGreater(len(samples), 30)
        self.assertGreater(len({row["seed"] for row in samples}), 30)
        self.assertTrue(all(row["幅"] == 1206 and row["高さ"] == 2622 for row in self.service if "surfaceID" in row))

    def test_all_display_modes_sampled(self):
        self.assertEqual({row["表示方式"] for row in self.host if "表示方式" in row},
                         {"初回設定のみ", "同じsurface再設定", "nil後に再設定"})
        for second in [2, 3, 6, 7, 10, 11, 23, 27]:
            self.assertGreater((ROOT / f"host-{second:02}.png").stat().st_size, 1000)

    def test_animation_pixels_change_in_each_mode(self):
        rendered = {row["秒"]: row for row in json.loads((ROOT / "render.json").read_text())}
        for first, second in [(2, 3), (6, 7), (10, 11)]:
            for point in [first, second]:
                self.assertGreater(rendered[point]["赤画素"] + rendered[point]["緑画素"], 10000)
            self.assertNotEqual(rendered[first]["左端X"], rendered[second]["左端X"])

    def test_tap_received(self):
        self.assertTrue(any(row.get("タップ") == 1 for row in self.events))

    def test_drag_received(self):
        self.assertTrue(any(row.get("ドラッグ状態") == 3 and row.get("移動X", 0) > 100 for row in self.events))

    def test_key_and_modifier_received(self):
        self.assertTrue(any(row.get("文字") == "aB" for row in self.events))

    def test_home_received(self):
        home = next(row for row in self.host if "ホーム配送" in row)
        self.assertTrue(any(row.get("バックグラウンド") and abs(row["時刻"] - home["時刻"]) < 2 for row in self.events))

    def test_signing_and_private_framework_isolation(self):
        app = ROOT.parent / ".build/DerivedData/Build/Products/Release/SimulatorGate.app"
        output = []
        for bundle in [app / "Contents/XPCServices/SimulatorGateService.xpc", app]:
            verify = subprocess.run(["codesign", "--verify", "--strict", "--verbose=2", str(bundle)], capture_output=True, text=True)
            output.append(verify.stdout + verify.stderr)
            self.assertEqual(verify.returncode, 0)
            info = subprocess.run(["codesign", "--display", "--verbose=4", "--entitlements", "-", str(bundle)], capture_output=True, text=True)
            output.append(info.stdout + info.stderr)
            self.assertEqual(info.returncode, 0)
            self.assertIn("runtime", info.stderr)
            self.assertNotIn("disable-library-validation", info.stdout)
        linked = subprocess.run(["otool", "-L", str(app / "Contents/MacOS/SimulatorGate")], capture_output=True, text=True)
        output.append(linked.stdout + linked.stderr)
        (ROOT / "signing.log").write_text("\n".join(output))
        self.assertEqual(linked.returncode, 0)
        self.assertNotIn("CoreSimulator.framework", linked.stdout)
        self.assertNotIn("SimulatorKit.framework", linked.stdout)

    def test_existing_devices_unchanged_and_dedicated_device_shutdown(self):
        before = json.loads((ROOT / "devices-before.json").read_text())["devices"]
        after = json.loads((ROOT / "devices-after.json").read_text())["devices"]
        states = {d["udid"]: d["state"] for group in after.values() for d in group}
        for group in before.values():
            for device in group:
                self.assertEqual(states[device["udid"]], device["state"])
        udid = json.loads((ROOT / "device.json").read_text())["UDID"]
        self.assertEqual(states[udid], "Shutdown")


if __name__ == "__main__":
    unittest.main()
