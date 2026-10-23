#!/usr/bin/env python3
"""Claude/Cursor の独立 runtime 受入検証専用。実 CLI・ネットワークは使用しない。

--work-dir は ownership.json を持つ .verification 配下の既存ディレクトリ。
fake-state/<PID>.json の controlDirectory 配下へ、ターンごとに次を置く。
turn-N.approval / turn-N.question は Claude の control_request を各一度送る。
turn-N.release は保留回答が無ければ成功完了、turn-N.fail は失敗完了する。
stop はプロセスを終了する。マーカーは読み取るだけで、削除・実行しない。
Claude は完了後も stdin の次ターンを待つ。Cursor は完了後に終了する。
"""

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import select
import signal
import stat
import sys
import time
import uuid


MAX_INPUT_BYTES = 2 * 1024 * 1024
HEARTBEAT_SECONDS = 0.5


def emit(message):
    remaining = memoryview((json.dumps(message, separators=(",", ":")) + "\n").encode())
    while remaining:
        written = os.write(sys.stdout.fileno(), remaining)
        remaining = remaining[written:]


def control_response(request_id, response=None, error=None):
    envelope = dict(subtype="error" if error else "success", request_id=request_id)
    envelope["error" if error else "response"] = error if error else (response or {})
    emit(dict(type="control_response", response=envelope))


def rate_limits():
    return dict(rate_limits_available=True, rate_limits=dict(
        five_hour=dict(utilization=0, resets_at="2099-01-01T00:00:00Z"),
        seven_day=dict(utilization=0, resets_at="2099-01-07T00:00:00Z")))


def private_directory(path):
    try:
        path.mkdir(mode=0o700)
    except FileExistsError:
        metadata = path.lstat()
        if not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid():
            raise ValueError(f"fixture directory is not owned or is a symlink: {path}")


def validate_root(parser, path):
    root = path.resolve(strict=True)
    ownership = root / "ownership.json"
    if ".verification" not in root.parts or root.stat().st_uid != os.getuid():
        parser.error("--work-dir requires an owned .verification directory")
    if ownership.is_symlink() or not ownership.is_file() or ownership.stat().st_uid != os.getuid():
        parser.error("--work-dir requires its owned ownership.json")
    return root


class StructuredFakeAgent:
    def __init__(self, root, provider, arguments, usage_only=False):
        self.provider = provider
        self.arguments = arguments
        self.usage_only = usage_only
        self.run_id = str(uuid.uuid4())
        self.session_id = f"runtime-{provider}-{os.getpid()}-{self.run_id}"
        for flag in ("--session-id", "--resume"):
            if flag in arguments and arguments.index(flag) + 1 < len(arguments):
                self.session_id = arguments[arguments.index(flag) + 1]
                break
        self.partial = "--include-partial-messages" in arguments
        self.running = True
        self.active = False
        self.turn = 0
        self.pending = None
        self.issued = set()
        self.resolved = set()
        self.signal_number = None
        self.exit_code = 0
        self.next_heartbeat = time.monotonic()
        self.input_buffer = bytearray()
        self.state_path = None
        self.control_directory = None
        self.state = dict(pid=os.getpid(), parent=os.getppid(), initialParent=os.getppid(),
                          provider=provider, role="structured", mode="oneshot" if provider == "cursor" else "persistent",
                          runID=self.run_id, sessionID=self.session_id,
                          startedAt=datetime.now(timezone.utc).isoformat(), heartbeat=0,
                          turn=0, active=False, running=True, phase="starting", emittedLines=0,
                          inputMarkers=[], methods=[], approvalReplies=[], questionReplies=[],
                          duplicateReplies=[], pendingRequest=None, signals=[], exitCode=None)
        if not usage_only:
            private_directory(root / "fake-state")
            private_directory(root / "fake-control")
            self.control_directory = root / "fake-control" / f"{os.getpid()}-{self.run_id}"
            private_directory(self.control_directory)
            self.state_path = root / "fake-state" / f"{os.getpid()}.json"
            self.state["controlDirectory"] = str(self.control_directory)
            self.save()

    def save(self):
        if self.state_path is None:
            return
        self.state.update(parent=os.getppid(), turn=self.turn, active=self.active,
                          running=self.running, pendingRequest=self.pending,
                          updatedAt=datetime.now(timezone.utc).isoformat())
        temporary = self.state_path.parent / f".{os.getpid()}-{self.run_id}.writing"
        descriptor = os.open(temporary, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
        with os.fdopen(descriptor, "w") as output:
            json.dump(self.state, output, separators=(",", ":"))
        os.replace(temporary, self.state_path)

    def output(self, message):
        emit(message)
        self.state["emittedLines"] += 1

    def on_signal(self, number, _frame):
        self.signal_number = number
        self.running = False

    def has_marker(self, name):
        if self.control_directory is None:
            return False
        path = self.control_directory / name
        return not path.is_symlink() and path.is_file()

    def turn_marker(self, action):
        return self.has_marker(f"turn-{self.turn}.{action}")

    def initialize(self):
        self.output(dict(type="system", subtype="init", session_id=self.session_id,
                         tools=["Bash", "AskUserQuestion"], slash_commands=["help"],
                         model="runtime-fixture", cwd=os.getcwd()))
        self.state["phase"] = "ready"
        self.save()

    def begin_turn(self, text):
        if self.active:
            raise ValueError("fixture received a second user turn before release or interruption")
        self.turn += 1
        self.active = True
        self.pending = None
        self.issued = set()
        self.resolved = set()
        self.state["phase"] = "streaming"
        self.state["inputMarkers"] = (self.state["inputMarkers"] + [text[-1024:]])[-16:]
        if self.provider == "claudeCode" and self.partial:
            self.output(dict(type="stream_event", session_id=self.session_id, event=dict(
                type="message_start", message=dict(id=self.message_id(), role="assistant", content=[]))))
            self.output(dict(type="stream_event", session_id=self.session_id, event=dict(
                type="content_block_start", index=0, content_block=dict(type="text", text=""))))
        self.progress(f"runtime-start:{self.turn}")
        self.save()

    def message_id(self):
        return f"runtime-answer-{self.turn}"

    def progress(self, text):
        if self.provider == "claudeCode" and self.partial:
            self.output(dict(type="stream_event", session_id=self.session_id, event=dict(
                type="content_block_delta", index=0, delta=dict(type="text_delta", text=text))))
        else:
            self.output(dict(type="assistant", session_id=self.session_id,
                             message=dict(id=self.message_id(), role="assistant",
                                          content=[dict(type="text", text=text)])))

    def request_permission(self, question=False):
        kind = "question" if question else "approval"
        request_id = f"runtime-{os.getpid()}-turn-{self.turn}-{kind}"
        tool = "AskUserQuestion" if question else "Bash"
        tool_input = dict(questions=[dict(question="Continue the isolated fixture?", header="Lifecycle",
            options=[dict(label="Continue", description="Fixture only"), dict(label="Pause")], multiSelect=False)]) if question else dict(command="runtime-fixture-only")
        self.pending = dict(requestId=request_id, kind=kind, toolName=tool, input=tool_input)
        self.issued.add(kind)
        self.state["phase"] = f"waiting-{kind}"
        self.output(dict(type="control_request", request_id=request_id, request=dict(
            subtype="can_use_tool", tool_name=tool, input=tool_input, tool_use_id=f"tool-{request_id}")))
        self.save()

    def receive_response(self, message):
        envelope = message.get("response")
        if not isinstance(envelope, dict):
            raise ValueError("control_response has no response envelope")
        request_id = envelope.get("request_id")
        body = envelope.get("response", {})
        if not isinstance(body, dict):
            raise ValueError("control_response response is not an object")
        if request_id in self.resolved:
            self.state["duplicateReplies"] = (self.state["duplicateReplies"] + [request_id])[-16:]
        elif self.pending and request_id == self.pending["requestId"]:
            key = "questionReplies" if self.pending["kind"] == "question" else "approvalReplies"
            self.state[key] = (self.state[key] + [dict(requestId=request_id, response=body)])[-16:]
            self.resolved.add(request_id)
            self.pending = None
            self.state["phase"] = "streaming"
            if envelope.get("subtype") == "error" or body.get("behavior") == "deny":
                self.complete(error="Fixture request was denied")
            else:
                self.progress(f" runtime-reply:{request_id}")
        else:
            raise ValueError(f"unexpected control_response request_id: {request_id}")
        self.save()

    def receive(self, message):
        if not isinstance(message, dict):
            raise ValueError("stdin protocol message is not an object")
        kind = message.get("type")
        if kind == "user":
            if self.usage_only:
                raise ValueError("usage fixture does not accept user turns")
            content = message.get("message", {}).get("content", [])
            text = content if isinstance(content, str) else "".join(
                item.get("text", "") for item in content if isinstance(item, dict) and item.get("type") == "text")
            self.begin_turn(text)
        elif kind == "control_response":
            self.receive_response(message)
        elif kind == "control_request":
            request_id = message.get("request_id")
            subtype = message.get("request", {}).get("subtype")
            self.state["methods"] = (self.state["methods"] + [subtype])[-32:]
            if subtype == "get_usage":
                control_response(request_id, rate_limits())
            elif subtype in ("initialize", "set_permission_mode", "set_model"):
                if subtype == "set_permission_mode":
                    self.state["permissionMode"] = message["request"].get("mode")
                elif subtype == "set_model":
                    self.state["model"] = message["request"].get("model")
                control_response(request_id)
            elif subtype == "interrupt":
                control_response(request_id)
                self.complete(error="Interrupted")
            else:
                control_response(request_id, error=f"Fixture does not implement {subtype}")
            self.save()
        else:
            raise ValueError(f"fixture does not implement stdin message type: {kind}")

    def complete(self, error=None):
        if not self.active:
            return
        self.output(dict(type="result", subtype="error_during_execution" if error else "success",
                         is_error=bool(error), session_id=self.session_id,
                         result=error or f"runtime-complete:{self.turn}",
                         errors=[error] if error else [], total_cost_usd=0,
                         usage=dict(input_tokens=0, output_tokens=0)))
        self.active = False
        self.pending = None
        self.state["phase"] = "failed" if error else "completed"
        if self.provider == "cursor":
            if error:
                print(error, file=sys.stderr, flush=True)
            self.exit_code = 1 if error else 0
            self.running = False
        self.save()

    def tick(self):
        if self.has_marker("stop"):
            self.state["phase"] = "marker-stop"
            self.running = False
            return
        if self.active:
            if self.turn_marker("fail"):
                self.complete(error="Controlled fixture failure")
            elif self.provider == "claudeCode" and self.pending is None:
                if self.turn_marker("approval") and "approval" not in self.issued:
                    self.request_permission()
                elif self.turn_marker("question") and "question" not in self.issued:
                    self.request_permission(question=True)
                elif self.turn_marker("release"):
                    self.complete()
            elif self.pending is None and self.turn_marker("release"):
                self.complete()
        if time.monotonic() >= self.next_heartbeat:
            self.next_heartbeat = time.monotonic() + HEARTBEAT_SECONDS
            self.state["heartbeat"] += 1
            if self.active:
                if self.pending:
                    self.output(dict(type="tool_progress", session_id=self.session_id,
                        tool_use_id=f"tool-{self.pending['requestId']}", elapsed_time_seconds=self.state["heartbeat"] / 2))
                else:
                    self.progress(f" runtime-stream:{self.state['heartbeat']}")
            self.save()

    def run(self):
        for number in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
            signal.signal(number, self.on_signal)
        try:
            self.initialize()
            if self.provider == "cursor":
                index = self.arguments.index("-p")
                self.begin_turn(self.arguments[index + 1])
            while self.running:
                self.tick()
                if not self.running:
                    break
                if self.provider == "cursor":
                    time.sleep(0.05)
                    continue
                ready, _, _ = select.select([sys.stdin.fileno()], [], [], 0.05)
                if not ready:
                    continue
                chunk = os.read(sys.stdin.fileno(), 65536)
                if not chunk:
                    if self.input_buffer.strip():
                        raise ValueError("fixture stdin ended in an incomplete JSON line")
                    self.state["phase"] = "stdin-eof"
                    self.running = False
                    break
                self.input_buffer.extend(chunk)
                if len(self.input_buffer) > MAX_INPUT_BYTES:
                    raise ValueError("fixture stdin line exceeds its bounded buffer")
                while b"\n" in self.input_buffer:
                    line, _, tail = self.input_buffer.partition(b"\n")
                    self.input_buffer = bytearray(tail)
                    if line.strip():
                        self.receive(json.loads(line))
        except BrokenPipeError:
            self.state["phase"] = "stdout-closed"
            self.exit_code = 74
        except (ValueError, OSError) as error:
            self.state["phase"] = "protocol-error"
            self.state["error"] = str(error)
            self.exit_code = 2
            print(f"structured runtime fixture: {error}", file=sys.stderr, flush=True)
        finally:
            self.running = False
            self.state["wasActiveOnExit"] = self.active
            self.active = False
            if self.signal_number is not None:
                self.state["signals"].append(self.signal_number)
                self.state["phase"] = "signal-stop"
                self.exit_code = 128 + self.signal_number
            self.state["exitCode"] = self.exit_code
            self.state["exitedAt"] = datetime.now(timezone.utc).isoformat()
            self.save()
        return self.exit_code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--provider", choices=["claudeCode", "cursor"], required=True)
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    root = validate_root(parser, options.work_dir)
    arguments = options.arguments[1:] if options.arguments[:1] == ["--"] else options.arguments
    if arguments in (["--version"], ["-v"]):
        print("2.1.280 (Claude Code runtime fixture)" if options.provider == "claudeCode" else "2026.10.23-runtime-fixture")
        return 0
    if arguments in (["models"], ["--list-models"]):
        print("Available models\nauto - Auto\nruntime-fixture - Isolated runtime fixture")
        return 0
    if arguments[:1] in (["usage"], ["--usage"], ["status"], ["--status"]):
        emit(rate_limits())
        return 0
    if options.provider == "claudeCode":
        if "--input-format" not in arguments or "stream-json" not in arguments:
            parser.error("Claude fixture requires --input-format stream-json")
        usage_only = "--safe-mode" in arguments and "--no-session-persistence" in arguments
        return StructuredFakeAgent(root, options.provider, arguments, usage_only=usage_only).run()
    if "-p" not in arguments or arguments.index("-p") + 1 == len(arguments):
        parser.error("Cursor fixture requires -p <prompt>")
    return StructuredFakeAgent(root, options.provider, arguments).run()


if __name__ == "__main__":
    sys.exit(main())
