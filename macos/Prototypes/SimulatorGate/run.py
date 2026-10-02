#!/usr/bin/env python3
"""専用端末だけを操作し、実行記録と表示画像を保存する。"""
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parent
RECORDS = ROOT / "Records"


def run(*args):
    result = subprocess.run(args, text=True, capture_output=True)
    with (RECORDS / "commands.log").open("a") as log:
        log.write("$ " + " ".join(map(str, args)) + "\n")
        log.write(result.stdout + result.stderr + f"終了コード: {result.returncode}\n")
    result.check_returncode()
    return result.stdout.strip()


def devices():
    return json.loads(run("xcrun", "simctl", "list", "devices", "-j"))


def main():
    RECORDS.mkdir(exist_ok=True)
    if (RECORDS / "device.json").exists():
        raise RuntimeError("既存の記録を上書きしません。前回の Records を別名で保存してください")
    before = devices()
    (RECORDS / "devices-before.json").write_text(json.dumps(before, ensure_ascii=False, indent=2))
    udid = run("xcrun", "simctl", "create", "Phlox-SimulatorGate-" + time.strftime("%Y%m%d-%H%M%S"),
               "com.apple.CoreSimulator.SimDeviceType.iPhone-17", "com.apple.CoreSimulator.SimRuntime.iOS-26-2")
    (RECORDS / "device.json").write_text(json.dumps({"UDID": udid}, ensure_ascii=False, indent=2))
    host = None
    try:
        run("xcrun", "simctl", "boot", udid)
        run("xcrun", "simctl", "bootstatus", udid, "-b")
        test_app = ROOT / ".build/TestDerivedData/Build/Products/Release-iphonesimulator/GateTest.app"
        run("xcrun", "simctl", "install", udid, str(test_app))
        run("xcrun", "simctl", "launch", udid, "com.phlox.prototype.GateTest")
        container = run("xcrun", "simctl", "get_app_container", udid, "com.phlox.prototype.GateTest", "data")
        events = Path(container) / "Documents/events.json"
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            if events.exists() and any(row.get("アニメーション", 0) >= 60 for row in json.loads(events.read_text())):
                break
            time.sleep(0.1)
        else:
            raise RuntimeError("専用アプリのアニメーション開始を確認できません")
        environment = os.environ.copy()
        environment.update(GATE_UDID=udid, GATE_DEVELOPER=run("xcode-select", "-p"),
                           GATE_HOST_LOG=str(RECORDS / "host.jsonl"),
                           GATE_SERVICE_LOG=str(RECORDS / "service.jsonl"), GATE_AUTOMATE="1")
        (RECORDS / "host.jsonl").touch()
        (RECORDS / "service.jsonl").touch()
        binary = ROOT / ".build/DerivedData/Build/Products/Release/SimulatorGate.app/Contents/MacOS/SimulatorGate"
        with (RECORDS / "process.log").open("w") as output:
            host = subprocess.Popen([str(binary)], env=environment, stdout=output, stderr=output)
            started = time.monotonic()
            snapshots = [2, 3, 6, 7, 10, 11, 23, 27]
            captured = set()
            while host.poll() is None and time.monotonic() - started < 40:
                rows = [json.loads(line) for line in (RECORDS / "host.jsonl").read_text().splitlines()]
                window = next((row for row in rows if "ウィンドウ番号" in row), None)
                elapsed = time.time() - window["時刻"] if window else 0
                for second in snapshots:
                    if window and elapsed >= second and second not in captured:
                        run("screencapture", "-x", "-o", "-l" + str(window["ウィンドウ番号"]), str(RECORDS / f"host-{second:02}.png"))
                        run("xcrun", "simctl", "io", udid, "screenshot", str(RECORDS / f"device-{second:02}.png"))
                        captured.add(second)
                time.sleep(0.1)
            if host.poll() is None:
                raise RuntimeError("試作ホストが40秒以内に終了しませんでした")
            if host.returncode:
                raise RuntimeError(f"試作ホストの終了コード: {host.returncode}")
        (RECORDS / "events.json").write_bytes(events.read_bytes())
    finally:
        if host and host.poll() is None:
            # 自分が起動した PID のみ終了する。
            host.terminate()
            host.wait(timeout=5)
        run("xcrun", "simctl", "shutdown", udid)
        (RECORDS / "devices-after.json").write_text(json.dumps(devices(), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
