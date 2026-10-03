#!/usr/bin/env python3
"""作成した専用端末だけで、本番の入力経路を観測する。削除はしない。"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--compatibility-check", action="store_true", help="許可リストへの追加前に未確認の組として検査する")
    parser.add_argument("--device-type", default="com.apple.CoreSimulator.SimDeviceType.iPhone-17")
    args = parser.parse_args()
    records = ROOT / ".build" / ("Records-" + time.strftime("%Y%m%d-%H%M%S"))
    records.mkdir(parents=True, exist_ok=False)

    def run(*command):
        result = subprocess.run(command, text=True, capture_output=True)
        with (records / "commands.log").open("a") as log:
            log.write("$ " + " ".join(map(str, command)) + "\n")
            log.write(result.stdout + result.stderr + f"終了コード: {result.returncode}\n")
        result.check_returncode()
        return result.stdout.strip()

    def devices():
        return json.loads(run("xcrun", "simctl", "list", "devices", "-j"))

    (records / "devices-before.json").write_text(json.dumps(devices(), ensure_ascii=False, indent=2))
    udid = run("xcrun", "simctl", "create", "Phlox-S5-" + time.strftime("%Y%m%d-%H%M%S"), args.device_type, args.runtime)
    host = None
    try:
        host_app = ROOT / ".build/DerivedData/Build/Products/Debug/SimulatorInputHarness.app"
        observer = ROOT / ".build/ObserverDerivedData/Build/Products/Debug-iphonesimulator/InputObserver.app"
        binaries = [path for path in host_app.rglob("*") if path.is_file() and (path.suffix == ".dylib" or path.parent.name == "MacOS")]
        metadata = {"UDID": udid, "runtime": args.runtime, "端末型": args.device_type,
                    "Xcode": run("xcodebuild", "-version"), "macOS": run("sw_vers"),
                    "ビルド": run("git", "rev-parse", "HEAD"), "未コミット変更": run("git", "status", "--short"),
                    "本体と補助プロセスSHA256": {str(path.relative_to(host_app)): hashlib.sha256(path.read_bytes()).hexdigest() for path in binaries}}
        metadata["観測アプリSHA256"] = {str(path.relative_to(observer)): hashlib.sha256(path.read_bytes()).hexdigest()
                                     for path in observer.rglob("*") if path.is_file() and (path.suffix == ".dylib" or path.name == "InputObserver")}
        (records / "device.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2))
        print("専用端末 UDID:", udid, flush=True)
        run("xcrun", "simctl", "boot", udid)
        run("xcrun", "simctl", "bootstatus", udid, "-b")
        run("xcrun", "simctl", "install", udid, str(observer))
        run("xcrun", "simctl", "launch", udid, "com.phlox.tests.InputObserver")
        container = Path(run("xcrun", "simctl", "get_app_container", udid, "com.phlox.tests.InputObserver", "data"))
        events_path = container / "Documents/events.json"
        deadline = time.monotonic() + 30
        while not events_path.exists():
            if time.monotonic() > deadline:
                raise RuntimeError("専用アプリの起動記録を確認できません")
            time.sleep(0.1)
        startup = json.loads(events_path.read_text())[0]
        metadata.update(幅=startup["幅"], 高さ=startup["高さ"], 倍率=startup["倍率"])
        (records / "device.json").write_text(json.dumps(metadata, ensure_ascii=False, indent=2))
        environment = os.environ.copy()
        environment.update(INPUT_UDID=udid, INPUT_RUNTIME=args.runtime, INPUT_WIDTH=str(startup["幅"]), INPUT_HEIGHT=str(startup["高さ"]))
        binary = ROOT / ".build/DerivedData/Build/Products/Debug/SimulatorInputHarness.app/Contents/MacOS/SimulatorInputHarness"
        with (records / "host.log").open("w") as output:
            command = [str(binary)]
            if args.compatibility_check:
                command.append("--compatibility-check")
            host = subprocess.Popen(command, env=environment, stdout=output, stderr=output)
            host.wait(timeout=60)
        rows = json.loads(events_path.read_text())
        (records / "events.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2))
        tap_time = next((row["時刻"] for row in rows if row.get("タップ", 0) >= 2), None)
        checks = {
            "タップ": any(row.get("タップ", 0) >= 1 for row in rows),
            "ドラッグ": any(row.get("ドラッグ状態") == 3 and row.get("移動X", 0) > 100 for row in rows),
            "スクロール": any(row.get("スクロール", 0) > 0 for row in rows),
            "英字と修飾キー": any("aB" in row.get("文字", "") for row in rows),
            "貼り付け": any("貼付" in row.get("文字", "") for row in rows),
            "フォーカス喪失による接触解放": any(row.get("接触状態") in ("解放", "取消") and abs(row.get("接触X", 0) - 120) < 10 for row in rows),
            "フォーカス喪失によるキー解放": any(row.get("キー状態") == "押下" and row.get("HIDコード") == 6 for row in rows)
                and any(row.get("キー状態") == "解放" and row.get("HIDコード") == 6 for row in rows),
            "ホーム": any(row.get("バックグラウンド") for row in rows),
            "スクロール中断後のタップと保留接触取消": tap_time is not None and not any(
                row.get("全接触状態") in (0, 1) and 320 <= row.get("全接触Y", 0) <= 420 and row["時刻"] > tap_time
                for row in rows),
        }
        intervals = [json.loads(line.split("検査区間:", 1)[1]) for line in (records / "host.log").read_text().splitlines()
                     if line.startswith("検査区間:")]
        measurements = []
        for name in ["ホイール100pt", "トラックパッド100pt", "ボタン上の小量ホイール", "ボタン上の小量トラックパッド"]:
            interval = next((value for value in intervals if value["名前"] == name), None)
            if interval is None:
                checks[name] = False
                continue
            before = [row for row in rows if row["時刻"] < interval["開始"]]
            during = [row for row in rows if interval["開始"] <= row["時刻"] <= interval["終了"]]
            if name.endswith("100pt"):
                initial = next((row["スクロール"] for row in reversed(before) if "スクロール" in row), 0)
                final = next((row["スクロール"] for row in reversed(during) if "スクロール" in row), initial)
                distance = final - initial
                checks[name + "（±20%）"] = 0.8 * interval["入力量"] <= distance <= 1.2 * interval["入力量"]
                velocities = [row for row in during if "スクロール終了速度Y" in row]
                checks[name + "の終了速度ゼロ"] = bool(velocities) and all(
                    row["スクロール終了速度X"] == 0 and row["スクロール終了速度Y"] == 0 for row in velocities)
                measurements.append({"名前": name, "入力量": interval["入力量"], "移動量": distance,
                                     "終了速度": velocities})
            else:
                checks[name + "でタップしない"] = not any("タップ" in row for row in during)
        (records / "measurements.json").write_text(json.dumps(measurements, ensure_ascii=False, indent=2))
        results = {"実行モード": "互換性検査（未確認）" if args.compatibility_check else "許可リスト", **checks}
        (records / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2))
        print(json.dumps(checks, ensure_ascii=False, indent=2))
        if host.returncode != 0:
            raise RuntimeError(f"確認ホストの終了コード: {host.returncode}（host.log 参照）")
        if not all(checks.values()):
            raise RuntimeError("未達の入力があります。events.json と host.log を参照してください")
    finally:
        try:
            if host and host.poll() is None:
                # 自分が起動した子プロセスのみ終了する。
                host.terminate()
                host.wait(timeout=5)
        finally:
            run("xcrun", "simctl", "shutdown", udid)
            (records / "devices-after.json").write_text(json.dumps(devices(), ensure_ascii=False, indent=2))
            print("専用端末を shutdown しました（削除せず保持）:", udid)
            print("実行記録:", records)


if __name__ == "__main__":
    main()
