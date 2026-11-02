#!/usr/bin/env python3
"""大履歴受入検査専用のCodex。実CLIを実行しない。"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import sys


spec = importlib.util.spec_from_file_location(
    "runtime_lifecycle_fake", Path(__file__).with_name("session-runtime-fake-agent.py"))
lifecycle_fake = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lifecycle_fake)

HISTORY_ITEMS = 2200
ITEM_PADDING = "x" * 1536


class LargeHistoryAgent(lifecycle_fake.FakeAgent):
    def structured(self):
        self.state.update(sendTexts=[], interruptCount=0, emittedHistoryItems=0)
        self.save()
        for raw in sys.stdin:
            message = json.loads(raw)
            method = message.get("method")
            if "id" not in message:
                continue
            self.state["methods"] = (self.state["methods"] + [method])[-32:]
            if method == "initialize":
                result = dict(codexHome=str(self.root / "codex-home"), platformFamily="unix",
                    platformOs="macos", userAgent="runtime-large-history-fixture/1")
            elif method == "config/read":
                result = dict(config=dict(developer_instructions=None))
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
            elif method == "thread/backgroundTerminals/list":
                result = dict(terminals=[])
            elif method in ("account/read", "account/rateLimits/read", "turn/start", "turn/interrupt",
                    "thread/backgroundTerminals/terminate", "thread/settings/update"):
                result = {}
            else:
                self.emit(dict(jsonrpc="2.0", id=message["id"], error=dict(
                    code=-32601, message=f"Large-history fixture does not implement {method}")))
                self.save()
                continue
            self.emit(dict(jsonrpc="2.0", id=message["id"], result=result))
            if method == "turn/start":
                text = "".join(item.get("text", "") for item in message.get("params", {}).get("input", []))
                self.state["sendTexts"].append(text)
                turn_number = len(self.state["sendTexts"])
                self.turn_id = f"large-turn-{turn_number}"
                self.notify("turn/started", dict(threadId=self.thread_id,
                    turn=dict(id=self.turn_id, status="inProgress", items=[])))
                if turn_number == 1:
                    for index in range(HISTORY_ITEMS):
                        self.emit_item(f"large-history-{index:04d}", f"large-history:{index:04d} " + ITEM_PADDING)
                    self.state["emittedHistoryItems"] = HISTORY_ITEMS
                    self.notify("turn/completed", dict(threadId=self.thread_id,
                        turn=dict(id=self.turn_id, status="completed", items=[])))
                else:
                    self.emit_item(f"large-tail-{turn_number}", f"large-tail:{turn_number} {text}")
            elif method == "turn/interrupt":
                self.state["interruptCount"] += 1
                self.notify("turn/completed", dict(threadId=self.thread_id,
                    turn=dict(id=self.turn_id, status="interrupted", items=[])))
            self.save()

    def emit_item(self, identifier, text):
        self.notify("item/completed", dict(threadId=self.thread_id, turnId=self.turn_id,
            item=dict(type="agentMessage", id=identifier, text=text)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--provider", choices=["codex"], required=True)
    parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    root = args.work_dir.resolve()
    if ".verification" not in root.parts or not (root / "ownership.json").is_file():
        parser.error("The fixture requires its owned .verification directory")
    if "app-server" in args.arguments:
        LargeHistoryAgent(root, "codex", "structured").structured()
    elif "--version" in args.arguments:
        print("runtime-large-history-fixture 0.147.0")
    else:
        print(json.dumps(dict(models=[], data=[])))


if __name__ == "__main__":
    main()
