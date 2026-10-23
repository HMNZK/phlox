#!/usr/bin/env python3
"""Lifecycle専用。実CLIは呼ばず、通信は自身のloopback Control/hookだけ。"""
import argparse
import http.client
import json
import os
from pathlib import Path
import re
import select
import subprocess
import sys
import threading
import time
import tty
import urllib.parse


class FakeAgent:
    def __init__(self, work_dir, provider, role):
        self.root = work_dir
        self.path = work_dir / "fake-state" / f"{os.getpid()}.json"
        self.lock = threading.RLock()
        self.output_lock = threading.Lock()
        self.state = dict(pid=os.getpid(), parent=os.getppid(), provider=provider,
                          role=role, heartbeat=0, dsrResponses=0, daResponses=0,
                          inputMarkers=[], approvalReplies=[], questionReplies=[], methods=[])
        self.thread_id = f"runtime-thread-{os.getpid()}"
        self.turn_id = "runtime-turn-1"
        self.active = False
        self.running = True
        self.save()

    def save(self):
        with self.lock:
            temporary = self.path.with_suffix(".writing")
            descriptor = os.open(temporary, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0o600)
            with os.fdopen(descriptor, "w") as handle:
                json.dump(self.state, handle)
            os.replace(temporary, self.path)

    def emit(self, obj):
        with self.output_lock:
            print(json.dumps(obj, separators=(",", ":")), flush=True)

    def notify(self, method, params):
        self.emit(dict(jsonrpc="2.0", method=method, params=params))

    def delta(self, text):
        self.notify("item/agentMessage/delta", dict(threadId=self.thread_id,
                    turnId=self.turn_id, itemId="runtime-answer", delta=text))

    def question(self):
        self.emit(dict(jsonrpc="2.0", id=7002, method="item/tool/requestUserInput",
            params=dict(threadId=self.thread_id, turnId=self.turn_id, itemId="runtime-question",
                questions=[dict(id="runtime-choice", header="Lifecycle", question="Continue?",
                    options=[dict(label="Continue", description="Continue the isolated fixture")],
                    isOther=False, isSecret=False)])))

    def beat(self, terminal=False):
        while self.running:
            time.sleep(0.5)
            with self.lock:
                self.state["heartbeat"] += 1
                counter = self.state["heartbeat"]
                self.save()
            if terminal:
                with self.output_lock:
                    os.write(1, f"runtime-heartbeat:{counter}\r\n\x1b[6n\x1b[c".encode())
            elif self.active:
                self.delta(f" runtime-stream:{counter}")

    def terminal(self):
        tty.setraw(0)
        threading.Thread(target=self.beat, kwargs=dict(terminal=True), daemon=True).start()
        pending = b""
        while True:
            readable, _, _ = select.select([0], [], [], 1)
            if not readable:
                continue
            chunk = os.read(0, 8192)
            if not chunk:
                return
            pending = (pending + chunk)[-16384:]
            dsr = list(re.finditer(rb"\x1b\[[0-9]+;[0-9]+R", pending))
            da = list(re.finditer(rb"\x1b\[\?[0-9;]+c", pending))
            markers = list(re.finditer(rb"runtime-input:[0-9a-f-]+[\r\n]", pending))
            hooks = list(re.finditer(rb"runtime-hook:[0-9a-f-]+[\r\n]", pending))
            with self.lock:
                self.state["dsrResponses"] += len(dsr)
                self.state["daResponses"] += len(da)
                for match in markers:
                    marker = match.group().strip().decode("ascii")
                    self.state["inputMarkers"].append(marker)
                    self.state["inputMarkers"] = self.state["inputMarkers"][-16:]
                    with self.output_lock:
                        os.write(1, f"runtime-echo:{marker}\r\n".encode())
                self.save()
            for match in hooks:
                self.check_retained_hook(match.group().strip().decode("ascii"))
            matches = dsr + da + markers + hooks
            if matches:
                pending = pending[max(match.end() for match in matches):]

    def check_retained_hook(self, turn_id):
        result = dict(turnID=turn_id)
        try:
            endpoint = urllib.parse.urlsplit(os.environ["PHLOX_API_URL"])
            hook = urllib.parse.urlsplit(os.environ["CLAUDE_HOOKS_URL"])
            if any(value.scheme != "http" or value.hostname != "127.0.0.1" or not value.port
                   for value in (endpoint, hook)):
                raise ValueError("The fixture only permits loopback services")
            dispatcher = Path(json.loads((self.root / "hook-challenge.json").read_text())["dispatcher"]).resolve()
            if not dispatcher.is_relative_to((self.root / "data/session-runtime-bundles").resolve()):
                raise ValueError("Dispatcher is outside the owned cached bundle")
            connection = http.client.HTTPConnection("127.0.0.1", endpoint.port, timeout=10)
            try:
                connection.request("GET", "/sessions", headers={
                    "Authorization": "Bearer " + os.environ["PHLOX_TOKEN"]})
                response = connection.getresponse()
                response.read(1024 * 1024)
                result["controlStatus"] = response.status
            finally:
                connection.close()
            environment = dict(os.environ, CURL_HOME=str(self.root / "home"),
                               NO_PROXY="127.0.0.1", no_proxy="127.0.0.1")
            process = subprocess.Popen(["/bin/bash", str(dispatcher), "userPromptSubmit"],
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=environment)
            with self.lock:
                helpers = self.state.setdefault("helperProcesses", [])
                helpers.append(dict(pid=process.pid, executable="/bin/bash", script=str(dispatcher)))
                self.state["helperProcesses"] = helpers[-16:]
                self.save()
            try:
                process.communicate(input=json.dumps(dict(turn_id=turn_id)).encode(), timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()
                raise TimeoutError("The owned hook helper timed out") from None
            result["hookExitCode"] = process.returncode
        except (OSError, ValueError, KeyError, http.client.HTTPException, TimeoutError) as error:
            # Store the type only: exception text, child output and environment can contain secrets.
            result["error"] = type(error).__name__
        with self.lock:
            challenges = self.state.setdefault("hookChallenges", [])
            challenges.append(result)
            self.state["hookChallenges"] = challenges[-16:]
            self.save()

    def structured(self):
        threading.Thread(target=self.beat, daemon=True).start()
        for raw in sys.stdin:
            message = json.loads(raw)
            method = message.get("method")
            if method is None:
                with self.lock:
                    if message.get("id") == 7001:
                        self.state["approvalReplies"].append(message.get("result"))
                        self.save()
                        self.question()
                    elif message.get("id") == 7002:
                        self.state["questionReplies"].append(message.get("result"))
                        self.save()
                        self.delta(" runtime-question-answered")
                        self.active = False
                        self.notify("turn/completed", dict(threadId=self.thread_id,
                            turn=dict(id=self.turn_id, status="completed", items=[])))
                continue
            with self.lock:
                self.state["methods"] = (self.state["methods"] + [method])[-32:]
                self.save()
            if "id" not in message:
                continue
            if method == "initialize":
                result = dict(codexHome=str(self.root / "codex-home"), platformFamily="unix",
                              platformOs="macos", userAgent="runtime-lifecycle-fixture/1")
            elif method in ("thread/start", "thread/resume", "thread/read"):
                result = dict(thread=dict(id=self.thread_id, status=dict(type="idle"),
                                          cwd=str(self.root / "project"), turns=[]))
            elif method == "model/list":
                result = dict(data=[dict(id="fake-model", model="fake-model", displayName="Fixture",
                    supportedReasoningEfforts=[dict(reasoningEffort="medium", description="Fixture")],
                    defaultReasoningEffort="medium", isDefault=True, inputModalities=["text"])])
            elif method == "skills/list":
                directories = message.get("params", {}).get("cwds") or [os.getcwd()]
                result = dict(data=[dict(cwd=directory, errors=[], skills=[]) for directory in directories])
            elif method in ("thread/list", "permissionProfile/list", "collaborationMode/list"):
                result = dict(data=[])
            elif method in ("turn/start", "turn/interrupt", "thread/backgroundTerminals/terminate", "thread/settings/update"):
                result = {}
            elif method == "thread/backgroundTerminals/list":
                result = dict(terminals=[])
            elif method in ("account/read", "account/rateLimits/read"):
                result = {}
            else:
                self.emit(dict(jsonrpc="2.0", id=message["id"], error=dict(
                    code=-32601, message=f"Fixture does not implement {method}")))
                continue
            self.emit(dict(jsonrpc="2.0", id=message["id"], result=result))
            if method == "turn/start":
                self.notify("turn/started", dict(threadId=self.thread_id,
                    turn=dict(id=self.turn_id, status="inProgress", items=[])))
                self.notify("item/started", dict(threadId=self.thread_id, turnId=self.turn_id,
                    item=dict(type="agentMessage", id="runtime-answer", text="")))
                self.active = True
                self.emit(dict(jsonrpc="2.0", id=7001, method="item/commandExecution/requestApproval",
                    params=dict(threadId=self.thread_id, turnId=self.turn_id, itemId="runtime-approval",
                        startedAtMs=int(time.time() * 1000), command="runtime-fixture-only", cwd=str(self.root))))
        self.running = False


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--provider", choices=["claudeCode", "codex", "cursor"], required=True)
    parser.add_argument("--additional-structured", action="store_true")
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    root = args.work_dir.resolve()
    marker = root / "ownership.json"
    if ".verification" not in root.parts or not marker.is_file():
        parser.error("Fixture requires an owned .verification directory")
    if args.provider == "codex" and "app-server" in args.arguments:
        FakeAgent(root, args.provider, "structured").structured()
    elif sys.stdin.isatty():
        FakeAgent(root, args.provider, "pty").terminal()
    elif args.additional_structured and args.provider in ("claudeCode", "cursor"):
        fixture = Path(__file__).with_name("session-runtime-structured-fake-agent.py").resolve(strict=True)
        arguments = args.arguments[1:] if args.arguments[:1] == ["--"] else args.arguments
        os.execv(sys.executable, [sys.executable, str(fixture), "--work-dir", str(root),
                                "--provider", args.provider, "--", *arguments])
    elif "--version" in args.arguments:
        print("runtime-lifecycle-fixture 0.147.0")
    else:
        # モデル一覧やusage調査も実CLIへフォールバックさせない。
        print(json.dumps(dict(models=[], data=[])))


if __name__ == "__main__":
    main()
