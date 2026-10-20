#!/usr/bin/env python3
"""Check real Codex app-server discovery against a built plugin's skill set."""

import argparse
import json
import os
from pathlib import Path
import selectors
import subprocess
import time


def verify(cwd, plugin, record):
    expected = {path.parent.name for path in (plugin / "skills").glob("*/SKILL.md")}
    if not expected:
        raise ValueError("No built skills found")
    record.mkdir(parents=True, exist_ok=True)
    with (record / "stderr.log").open("w") as stderr:
        process = subprocess.Popen(["codex", "app-server", "--stdio"], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=stderr, cwd=cwd)
        (record / "process.json").write_text(json.dumps({"pid": process.pid, "executable": "codex app-server --stdio", "owned": True}))
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        buffer = b""
        notifications = []

        def send(message):
            process.stdin.write((json.dumps(message) + "\n").encode())
            process.stdin.flush()

        def response(request_id):
            nonlocal buffer
            deadline = time.monotonic() + 60
            while time.monotonic() < deadline:
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    event = json.loads(line)
                    if "method" in event:
                        notifications.append(event["method"])
                    if event.get("id") == request_id:
                        if "error" in event:
                            raise ValueError(event["error"])
                        return event["result"]
                if selector.select(timeout=min(1, max(0, deadline - time.monotonic()))):
                    chunk = os.read(process.stdout.fileno(), 65536)
                    if not chunk:
                        raise RuntimeError(f"Codex closed stdout, exit={process.poll()}")
                    buffer += chunk
            raise TimeoutError(f"Codex request timed out: {request_id}")

        try:
            send({"id": 1, "method": "initialize", "params": {"clientInfo": {"name": "pstack-discovery-check", "version": "1"}, "capabilities": {"experimentalApi": True}}})
            response(1)
            send({"method": "initialized", "params": {}})
            send({"id": 2, "method": "skills/list", "params": {"cwds": [str(cwd)], "forceReload": True}})
            result = response(2)
            entries = [entry for entry in result["data"] if entry["cwd"] == str(cwd)]
            if len(entries) != 1:
                raise ValueError("Missing cwd in skills/list")
            entry = entries[0]
            if entry.get("errors"):
                raise ValueError(f"Discovery errors: {entry['errors']}")
            skills = [skill for skill in entry["skills"] if Path(skill["path"]).is_relative_to(plugin)]
            actual = {skill["name"].split(":")[-1] for skill in skills if skill.get("enabled", True)}
            if actual != expected or len(skills) != len(expected):
                raise ValueError(f"Skill mismatch: missing={sorted(expected - actual)} extra={sorted(actual - expected)} count={len(skills)}")
            (record / "skills.json").write_text(json.dumps(skills, ensure_ascii=False, indent=2))
            deadline = time.monotonic() + 2
            while time.monotonic() < deadline:
                if selector.select(timeout=0.1):
                    chunk = os.read(process.stdout.fileno(), 65536)
                    if not chunk:
                        break
                    buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    event = json.loads(line)
                    if "method" in event:
                        notifications.append(event["method"])
            (record / "notifications.json").write_text(json.dumps(notifications))
            print(f"PASS: real skills/list discovered {len(skills)} enabled pstack skills without errors")
            print(f"Notifications after forceReload: {notifications}")
        finally:
            selector.close()
            process.stdin.close()
            if process.poll() is None:
                process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
            (record / "process.json").write_text(json.dumps({"pid": process.pid, "executable": "codex app-server --stdio", "owned": True, "stopped": True, "exit_code": process.returncode}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cwd", type=Path, required=True)
    parser.add_argument("--plugin", type=Path, required=True)
    parser.add_argument("--record", type=Path, required=True)
    args = parser.parse_args()
    verify(args.cwd.resolve(), args.plugin.resolve(), args.record.resolve())


if __name__ == "__main__":
    main()
