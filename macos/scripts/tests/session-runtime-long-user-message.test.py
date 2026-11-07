#!/usr/bin/env python3
"""隔離したアプリで巨大なユーザー発言の復元と会話切替を検査する。

compact-test経由で固有bundle IDの --app と空の --work-dir を指定する。
実データは使わず、約496万文字の本文を保存先へ合成する。
"""
import ctypes
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shlex
import sys
import time
import unittest


spec = importlib.util.spec_from_file_location(
    "runtime_lifecycle", Path(__file__).with_name("session-runtime-lifecycle.test.py"))
lifecycle = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = lifecycle
spec.loader.exec_module(lifecycle)

LONG_ID = {"rawValue": "4F895E90-EA27-426B-9BC1-BA78DAA85A40"}
OTHER_ID = {"rawValue": "A5647363-346C-470E-B7E3-B29BB5639AF7"}
LONG_TITLE = "Long message regression"
OTHER_TITLE = "Other conversation regression"
OTHER_TEXT = "Other conversation remains available."


def fake_codex(root, arguments):
    if ".verification" not in root.parts or not (root / "ownership.json").is_file():
        raise AssertionError("Fixture requires an owned verification directory")
    if "app-server" in arguments:
        fixture = importlib.util.spec_from_file_location("long_message_agent",
            Path(__file__).with_name("session-runtime-fake-agent.py"))
        module = importlib.util.module_from_spec(fixture)
        fixture.loader.exec_module(module)
        agent = module.FakeAgent(root, "codex", "structured")
        agent.thread_id = "synthetic-" + os.environ["PHLOX_SESSION_ID"]
        agent.structured()
    elif "--version" in arguments:
        print("long-message-fixture 0.147.0")
    else:
        print(json.dumps(dict(models=[], data=[])))


def accessibility_action(identity, expected, *, press=False, identifier=False):
    if not lifecycle.same_process(identity):
        return dict(targetExited=True, matched=False)
    ax = ctypes.CDLL("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")
    cf = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
    ax.AXUIElementCreateApplication.argtypes = [ctypes.c_int32]
    ax.AXUIElementCreateApplication.restype = ctypes.c_void_p
    ax.AXUIElementSetMessagingTimeout.argtypes = [ctypes.c_void_p, ctypes.c_float]
    ax.AXUIElementCopyAttributeValue.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
    ax.AXUIElementPerformAction.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    cf.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
    cf.CFStringCreateWithCString.restype = ctypes.c_void_p
    cf.CFArrayGetCount.argtypes = [ctypes.c_void_p]
    cf.CFArrayGetCount.restype = ctypes.c_long
    cf.CFArrayGetValueAtIndex.argtypes = [ctypes.c_void_p, ctypes.c_long]
    cf.CFArrayGetValueAtIndex.restype = ctypes.c_void_p
    cf.CFGetTypeID.argtypes = [ctypes.c_void_p]
    cf.CFGetTypeID.restype = ctypes.c_ulong
    cf.CFStringGetTypeID.restype = ctypes.c_ulong
    cf.CFArrayGetTypeID.restype = ctypes.c_ulong
    cf.CFStringGetCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.c_uint32]
    cf.CFStringGetCString.restype = ctypes.c_bool
    cf.CFRetain.argtypes = [ctypes.c_void_p]
    cf.CFRetain.restype = ctypes.c_void_p
    cf.CFRelease.argtypes = [ctypes.c_void_p]
    keys = {name: cf.CFStringCreateWithCString(None, name.encode(), 0x08000100)
            for name in ("AXWindows", "AXChildren", "AXTitle", "AXDescription", "AXValue", "AXIdentifier", "AXPress")}
    app = ax.AXUIElementCreateApplication(identity.pid)
    retained, visited = [], set()
    result = dict(matched=False)
    deadline = time.monotonic() + 5

    def visit(element):
        if element in visited or len(visited) >= 2000 or time.monotonic() >= deadline:
            return False
        visited.add(element)
        retained.append(cf.CFRetain(element))
        for name in (("AXIdentifier",) if identifier else ("AXTitle", "AXDescription", "AXValue")):
            value = ctypes.c_void_p()
            if ax.AXUIElementCopyAttributeValue(element, keys[name], ctypes.byref(value)) != 0 or not value.value:
                continue
            try:
                if cf.CFGetTypeID(value) == cf.CFStringGetTypeID():
                    buffer = ctypes.create_string_buffer(32768)
                    if cf.CFStringGetCString(value, buffer, len(buffer), 0x08000100):
                        text = buffer.value.decode("utf-8")
                        if (text == expected if identifier else expected in text):
                            result["matched"] = True
                            if press:
                                result["actionStatus"] = ax.AXUIElementPerformAction(element, keys["AXPress"])
                            return True
            finally:
                cf.CFRelease(value)
        for name in ("AXWindows", "AXChildren"):
            value = ctypes.c_void_p()
            if ax.AXUIElementCopyAttributeValue(element, keys[name], ctypes.byref(value)) != 0 or not value.value:
                continue
            try:
                if cf.CFGetTypeID(value) == cf.CFArrayGetTypeID():
                    for index in range(cf.CFArrayGetCount(value)):
                        if visit(cf.CFArrayGetValueAtIndex(value, index)):
                            return True
            finally:
                cf.CFRelease(value)
        return False

    started = time.monotonic()
    try:
        result["timeoutStatus"] = ax.AXUIElementSetMessagingTimeout(app, ctypes.c_float(1))
        visit(app)
        result.update(nodesRead=len(visited), seconds=time.monotonic() - started)
        return result
    finally:
        for element in retained:
            cf.CFRelease(element)
        cf.CFRelease(app)
        for key in keys.values():
            cf.CFRelease(key)


class LongUserMessageTests(lifecycle.SessionRuntimeLifecycleTests):
    def setUp(self):
        super().setUp()
        self.report["purpose"] = "Synthetic huge user message cold restoration and native GUI responsiveness"
        arguments = [sys.executable, str(Path(__file__).resolve()), "--fake-codex", str(self.root), "--"]
        wrapper = Path(self.agents["codex"])
        wrapper.write_text("#!/bin/sh\nexec " + " ".join(shlex.quote(value) for value in arguments) + ' "$@"\n')
        self.report["longMessageSourceSHA256"] = hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
        self.body = "Synthetic long message. " + ("あいうえお\n" * 826_662) + " END"
        self.assertEqual(len(self.body), 4_960_000)
        self.expected_digest = hashlib.sha256(self.body.encode()).hexdigest()
        self.seed_files()

    def seed_files(self):
        self.store.mkdir()
        transcripts = self.store / "transcripts"
        transcripts.mkdir()
        timestamp = time.time() - lifecycle.SWIFT_EPOCH
        def descriptor(identifier, title):
            return dict(id=identifier, kind="codex", name=title, titleSource="manual",
                        workingDirectory=str(self.root / "project"), startedAt=timestamp,
                        command=self.agents["codex"], args=["app-server"], env={}, backend="appServer",
                        codexThreadId="synthetic-" + identifier["rawValue"], launchContext="interactive")
        (self.store / "sessions.json").write_text(json.dumps(dict(schemaVersion=1,
            sessions=[descriptor(LONG_ID, LONG_TITLE), descriptor(OTHER_ID, OTHER_TITLE)])))
        self.long_file = transcripts / (LONG_ID["rawValue"] + ".json")
        original = [dict(userMessage=dict(id="synthetic-user", text=self.body, timestamp=timestamp, attachments=[]))]
        original += [dict(error=dict(id=f"synthetic-error-{index}", message=f"Synthetic error {index}", timestamp=timestamp))
                     for index in range(3)]
        self.long_file.write_text(json.dumps(original, ensure_ascii=False))
        self.other_file = transcripts / (OTHER_ID["rawValue"] + ".json")
        self.other_file.write_text(json.dumps([dict(userMessage=dict(id="other-user", text=OTHER_TEXT,
            timestamp=timestamp, attachments=[]))]))
        self.observe("synthetic-transcripts-seeded", characters=len(self.body), utf8Bytes=len(self.body.encode()),
                     sha256=self.expected_digest, sessionCount=2, errorCount=3)

    def assert_gui_text(self, identity, text, *, identifier=False):
        latest = {}
        def present():
            nonlocal latest
            latest = accessibility_action(identity, text, identifier=identifier)
            return latest["matched"]
        try:
            lifecycle.eventually("expected native GUI content", present, timeout=15)
        except AssertionError:
            self.capture_quit_diagnostics(identity, phase="long-message-unresponsive")
            raise
        finally:
            self.observe("gui-content-check", expected=text, **latest)

    def open_conversation(self, identity, title):
        self.assert_gui_text(identity, title)
        result = accessibility_action(identity, title, press=True)
        self.observe("gui-open-conversation", title=title, **result)
        self.assertTrue(result["matched"])
        self.assertEqual(result.get("actionStatus"), 0, "The native sidebar action failed")

    def remember_fixture_children(self):
        states = [json.loads(path.read_text()) for path in (self.root / "fake-state").glob("*.json")]
        children = [lifecycle.process_info(state["pid"]) for state in states if state["role"] == "structured"]
        self.assertEqual(len(children), 2)
        for child in children:
            self.assertIsNotNone(child)
            self.assertEqual(child[1], self.runtime_identity.pid)
            self.remember(child[0], "synthetic-codex")

    def assert_saved_body(self):
        saved = json.loads(self.long_file.read_text())
        self.assertEqual(len(saved), 4)
        self.assertEqual(saved[0]["userMessage"]["id"], "synthetic-user")
        body = saved[0]["userMessage"]["text"]
        self.assertEqual(len(body), 4_960_000)
        self.assertEqual(hashlib.sha256(body.encode()).hexdigest(), self.expected_digest)
        self.assertEqual(json.loads(self.other_file.read_text())[0]["userMessage"]["text"], OTHER_TEXT)
        self.observe("saved-body-unchanged", characters=len(body), sha256=self.expected_digest)

    def test_long_restored_message_keeps_gui_and_other_conversation_available(self):
        started = time.monotonic()
        gui, identity = self.start_gui(self.original_app)
        discovery = lifecycle.eventually("the isolated restored runtime", self.read_ready_discovery, timeout=90)
        current = lifecycle.process_info(discovery["pid"])
        self.assertIsNotNone(current)
        self.runtime_identity = current[0]
        self.assertTrue(Path(self.runtime_identity.executable).is_relative_to(self.store / "session-runtime-bundles"))
        self.remember(self.runtime_identity, "runtime")
        self.api = lifecycle.RuntimeAPI(self.store, discovery, self.observe, self.capture_runtime_timeout)
        self.observe("cold-runtime-ready", seconds=time.monotonic() - started)
        restored = self.get_session(LONG_ID, "chat")
        self.assertEqual(hashlib.sha256(restored["transcript"][0]["userMessage"]["text"].encode()).hexdigest(), self.expected_digest)
        self.assertEqual(len(self.api.snapshot()["sessions"]), 2)
        self.remember_fixture_children()
        self.open_conversation(identity, LONG_TITLE)
        self.assert_gui_text(identity, "先頭のみ表示")
        self.assert_gui_text(identity, "ChatMessage.copyButton.user.full", identifier=True)
        if lifecycle.OPTIONS.inspection_pause_seconds:
            self.observe("long-message-ui-inspection-ready", guiPID=identity.pid,
                         seconds=lifecycle.OPTIONS.inspection_pause_seconds)
            time.sleep(lifecycle.OPTIONS.inspection_pause_seconds)
        self.open_conversation(identity, OTHER_TITLE)
        self.assert_gui_text(identity, OTHER_TEXT)
        self.assert_saved_body()
        quit_result = lifecycle.quit_application(identity)
        self.assertEqual(quit_result["sendStatus"], 0)
        self.assertIn(quit_result.get("replyError"), (None, 0))
        self.assertEqual(gui.wait(timeout=30), 0)
        _, reconnected = self.start_gui(self.original_app)
        self.open_conversation(reconnected, LONG_TITLE)
        self.assert_gui_text(reconnected, "先頭のみ表示")
        self.open_conversation(reconnected, OTHER_TITLE)
        self.assert_gui_text(reconnected, OTHER_TEXT)
        self.assert_saved_body()
        self.observe("long-message-acceptance-passed", nativeActions=True, guiReconnect=True,
                     fullBodyPreserved=True, sessionCount=2)


if __name__ == "__main__":
    if sys.argv[1:2] == ["--fake-codex"]:
        fake_codex(Path(sys.argv[2]).resolve(), sys.argv[3:])
        sys.exit(0)
    lifecycle.OPTIONS, remaining = lifecycle.parse_options()
    output = io.StringIO()
    result = unittest.TextTestRunner(stream=output, verbosity=2).run(unittest.TestSuite([
        LongUserMessageTests("test_long_restored_message_keeps_gui_and_other_conversation_available")]))
    log = output.getvalue()
    sys.stderr.write(log)
    ownership = lifecycle.OPTIONS.work_dir / "ownership.json"
    if ownership.exists() and json.loads(ownership.read_text()).get("run") == lifecycle.OPTIONS.run_id:
        (lifecycle.OPTIONS.work_dir / "logs/test-result.log").write_text(log)
    sys.exit(0 if result.wasSuccessful() else 1)
