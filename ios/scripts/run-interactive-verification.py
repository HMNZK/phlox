#!/usr/bin/env python3
"""Launch one interactive UI test and surface its ready request immediately."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--udid", required=True)
    parser.add_argument("--window-title", required=True)
    parser.add_argument("--step-timeout-seconds", type=int, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("-- の後に起動コマンドが必要です")
    if args.step_timeout_seconds <= 0:
        parser.error("期限は正の秒数にしてください")
    output, log = args.output.resolve(), args.log.resolve()
    if output.exists() or log.exists():
        parser.error("出力先とログは新規パスにしてください")
    output.mkdir(parents=True)
    log.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["TEST_RUNNER_PHLOX_REMAINING_OUTPUT"] = str(output)
    env["TEST_RUNNER_PHLOX_REMAINING_INTERACTIVE"] = "1"
    env["TEST_RUNNER_PHLOX_REMAINING_HOLD"] = "1"
    env["TEST_RUNNER_PHLOX_SNAPSHOT_EXTERNAL_AX_WINDOW_TITLE"] = args.window_title
    owner = {"pid": None, "argv": command, "log": str(log), "output": str(output),
             "expectedUDID": args.udid, "expectedWindowTitle": args.window_title,
             "startedAt": time.time()}
    with log.open("x") as stream:
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT, env=env)
        owner["pid"] = process.pid
        (output / "OWNER.json").write_text(json.dumps(owner, indent=2), encoding="utf-8")
        print(json.dumps({"pid": process.pid, "output": str(output), "log": str(log)}), flush=True)
        surfaced: set[Path] = set()
        mismatch = False
        test_pid = None
        seen_nonces: set[str] = set()
        while True:
            for ready_path in output.rglob("*-ready.json"):
                if ready_path in surfaced:
                    continue
                try:
                    ready = json.loads(ready_path.read_text(encoding="utf-8"))
                except (json.JSONDecodeError, OSError):
                    continue
                surfaced.add(ready_path)
                notice = {key: ready.get(key) for key in
                          ("step", "instruction", "ackFile", "nonce", "pid", "udid", "windowTitle")}
                notice["deadlineAt"] = ready.get("requestedAt", time.time()) + args.step_timeout_seconds
                notice["timeoutSeconds"] = args.step_timeout_seconds
                print(json.dumps(notice, ensure_ascii=False), flush=True)
                if test_pid is None:
                    test_pid = ready.get("pid")
                if (ready.get("udid") != args.udid or ready.get("windowTitle") != args.window_title
                        or not isinstance(test_pid, int) or ready.get("pid") != test_pid
                        or not isinstance(ready.get("nonce"), str) or not ready["nonce"]
                        or ready["nonce"] in seen_nonces or ready.get("phase") != "awaitingCUA"
                        or not ready.get("ackFile")):
                    mismatch = True
                    print("対象識別情報が一致しません。ACKを作らず停止します。", flush=True)
                    process.terminate()
                    break
                seen_nonces.add(ready["nonce"])
                ack_path = Path(ready["ackFile"]).resolve()
                if ack_path.parent != ready_path.parent:
                    mismatch = True
                    print("ACK配置先がready JSONの場所と一致しません。停止します。", flush=True)
                    process.terminate()
                    break
                try:
                    ready_path.resolve().relative_to(output)
                    ack_path.resolve().relative_to(output)
                except ValueError:
                    mismatch = True
                    print("ready/ACKが専用出力先の外にあります。停止します。", flush=True)
                    process.terminate()
                    break
            if mismatch:
                break
            if process.poll() is not None:
                break
            time.sleep(0.05)
        code = process.wait()
    (output / "STATUS.json").write_text(json.dumps({"exitCode": code, "readyCount": len(surfaced),
        "targetMismatch": mismatch, "finishedAt": time.time()}, indent=2), encoding="utf-8")
    if mismatch:
        return 2
    if code == 0 and not surfaced:
        print("対話検査のready通知がありません。検査未実施として失敗します。", flush=True)
        return 3
    return code


if __name__ == "__main__":
    raise SystemExit(main())
