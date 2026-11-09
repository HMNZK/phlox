#!/usr/bin/env python3
"""隔離アプリで長いカード、独立した入力履歴、直接ジャンプを検査する。

compact-test経由で固有bundle IDの --app と新しい --work-dir を指定する。
--self-check は合成履歴の前提だけを確認し、製品の成功とは扱わない。
"""
import base64
import hashlib
import http.client
import importlib.util
import io
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import time
import unittest
import uuid


spec = importlib.util.spec_from_file_location(
    "semantic_long_message", Path(__file__).with_name("session-runtime-long-user-message.test.py"))
long_message = importlib.util.module_from_spec(spec)
spec.loader.exec_module(long_message)
lifecycle = long_message.lifecycle

SESSION_ID = {"rawValue": "5B0CA76B-89A0-4EA8-B376-40C3B1D71110"}
TITLE = "Semantic chat acceptance"
INPUT_COUNT = 128
WORK_COUNT = 3000
LAST_INPUT = "semantic-input-0127"
TASK_ID = "semantic-check"
FIRST_INPUT_TEXT = "Semantic oldest input. " + "あいうえお" * 200_000
FINAL_TEXT = "Semantic final response after 3000 completed commands."
STAMP = 800_000_000
MAX_RESPONSE_BYTES = 256 * 1024
GRID_IDS = [{"rawValue": f"5B0CA76B-89A0-4EA8-B376-40C3B1D7{index:04d}"} for index in range(1101, 1109)]


def fake_codex(root, arguments):
    if ".verification" not in root.parts or not (root / "ownership.json").is_file():
        raise AssertionError("Fixture requires its owned verification directory")
    if "app-server" not in arguments:
        return long_message.fake_codex(root, arguments)
    fixture = importlib.util.spec_from_file_location("semantic_grid_agent",
        Path(__file__).with_name("session-runtime-large-history-fake-agent.py"))
    module = importlib.util.module_from_spec(fixture)
    fixture.loader.exec_module(module)
    module.HISTORY_ITEMS = 0
    class GridAgent(module.LargeHistoryAgent):
        def emit_item(self, identifier, text):
            self.notify("item/started", dict(threadId=self.thread_id, turnId=self.turn_id,
                item=dict(type="commandExecution", id="semantic-grid-work", status="inProgress",
                    command="printf semantic-grid-live", aggregatedOutput="", cwd=str(root / "project"))))
            super().emit_item(identifier, text)
    agent = GridAgent(root, "codex", "structured")
    agent.thread_id = "synthetic-" + os.environ["PHLOX_SESSION_ID"]
    agent.structured()


def synthetic_transcript():
    items = []
    for index in range(INPUT_COUNT):
        timestamp = STAMP + index * 20
        text = FIRST_INPUT_TEXT if index == 0 else f"Semantic input {index:04d}"
        items.append(dict(userMessage=dict(id=f"semantic-input-{index:04d}", text=text,
            timestamp=timestamp, attachments=[], turnEnd=dict(outcome="completed", at=timestamp + 10))))
        if index < INPUT_COUNT - 1:
            items.append(dict(agentMessage=dict(id=f"semantic-answer-{index:04d}",
                text=f"Semantic answer {index:04d}", timestamp=timestamp + 9)))
    timestamp = STAMP + (INPUT_COUNT - 1) * 20
    items.append(dict(taskList=dict(id="semantic-task-start", tasks=[dict(id=TASK_ID,
        title="Validate semantic long card", status="in_progress")], timestamp=timestamp + 0.1)))
    items.extend(dict(commandExecution=dict(id=f"semantic-work-{index:04d}",
        command=f"printf semantic-work-{index:04d}", output=f"Synthetic command result {index:04d}. " + "x" * 128,
        timestamp=timestamp + 1 + index / 1000, completedAt=timestamp + 1.1 + index / 1000))
        for index in range(WORK_COUNT))
    items.append(dict(taskList=dict(id="semantic-task-done", tasks=[dict(id=TASK_ID,
        title="Validate semantic long card", status="completed")], timestamp=timestamp + 8)))
    items.append(dict(agentMessage=dict(id="semantic-final", text=FINAL_TEXT, timestamp=timestamp + 9)))
    return items


def read_content(api, session, target, *, maximum_bytes=MAX_RESPONSE_BYTES):
    payload = dict(sessionID=session["id"], executionID=session["executionID"], target=target)
    encoded = base64.b64encode(json.dumps(payload, separators=(",", ":")).encode()).decode()
    headers = {"Authorization": "Bearer " + api._token,
        "X-Phlox-Runtime-Protocol": str(api.protocol),
        "X-Phlox-Runtime-Generation": api.generation,
        "X-Phlox-Runtime-Content-Request": encoded}
    connection = http.client.HTTPConnection("127.0.0.1", api.port, timeout=20)
    started = time.monotonic()
    try:
        connection.request("GET", "/session-content", headers=headers)
        response = connection.getresponse()
        body = response.read(maximum_bytes + 1)
        if response.status != 200:
            raise AssertionError(f"Semantic content returned HTTP {response.status}")
        if len(body) > maximum_bytes:
            raise AssertionError("Semantic content exceeded its encoded byte limit")
        return json.loads(body), dict(bytes=len(body), seconds=time.monotonic() - started)
    finally:
        connection.close()


def response_page(response, name):
    if set(response) != {name}:
        raise AssertionError(f"Expected {name}, received {list(response)}")
    return response[name]["_0"]


class SemanticChatAcceptance(lifecycle.SessionRuntimeLifecycleTests):
    def setUp(self):
        super().setUp()
        self.report["purpose"] = "Native semantic cards and independent input history acceptance"
        arguments = [sys.executable, str(Path(__file__).resolve()), "--fake-codex", str(self.root), "--"]
        Path(self.agents["codex"]).write_text("#!/bin/sh\nexec " +
            " ".join(shlex.quote(value) for value in arguments) + ' "$@"\n')
        self.report["semanticSourceHashes"] = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (Path(__file__).resolve(), Path(long_message.__file__).resolve(),
                Path(__file__).with_name("session-runtime-large-history-fake-agent.py").resolve())}
        self.store.mkdir()
        transcripts = self.store / "transcripts"
        transcripts.mkdir()
        descriptor = dict(id=SESSION_ID, kind="codex", name=TITLE, titleSource="manual",
            workingDirectory=str(self.root / "project"), startedAt=STAMP, command=self.agents["codex"],
            args=["app-server"], env={}, backend="appServer", codexThreadId="synthetic-" + SESSION_ID["rawValue"],
            launchContext="interactive")
        descriptors = [descriptor]
        for index, identifier in enumerate(GRID_IDS, 1):
            grid = dict(descriptor, id=identifier, name=f"Semantic grid {index:02d}",
                codexThreadId="synthetic-" + identifier["rawValue"])
            descriptors.append(grid)
            (transcripts / (identifier["rawValue"] + ".json")).write_text(json.dumps([
                dict(userMessage=dict(id=f"grid-input-{index}", text=f"Grid fixture {index}",
                    timestamp=STAMP, attachments=[], turnEnd=dict(outcome="completed", at=STAMP + 1))),
                dict(agentMessage=dict(id=f"grid-answer-{index}", text=f"Grid fixture ready {index}", timestamp=STAMP + 1))]))
        (self.store / "sessions.json").write_text(json.dumps(dict(schemaVersion=1, sessions=descriptors)))
        self.transcript_file = transcripts / (SESSION_ID["rawValue"] + ".json")
        self.transcript_file.write_text(json.dumps(synthetic_transcript(), ensure_ascii=False))
        self.transcript_hash = hashlib.sha256(self.transcript_file.read_bytes()).hexdigest()
        self.observe("semantic-fixture-seeded", inputs=INPUT_COUNT, workItems=WORK_COUNT,
            firstInputBytes=len(FIRST_INPUT_TEXT.encode()), transcriptSHA256=self.transcript_hash)

    def assert_native(self, identity, expected, *, identifier=False):
        latest = {}
        def present():
            nonlocal latest
            latest = long_message.accessibility_action(identity, expected, identifier=identifier)
            return latest["matched"]
        try:
            lifecycle.eventually("semantic native content", present, timeout=20)
        finally:
            self.observe("semantic-native-content", expected=expected, identifier=identifier, **latest)

    def press_native(self, identity, expected, *, identifier=False):
        self.assert_native(identity, expected, identifier=identifier)
        result = long_message.accessibility_action(identity, expected, press=True, identifier=identifier)
        self.observe("semantic-native-action", expected=expected, **result)
        self.assertTrue(result["matched"])
        self.assertEqual(result.get("actionStatus"), 0, "The native accessibility action failed")

    def screenshot(self, identity, name):
        import Quartz
        windows = [window for window in Quartz.CGWindowListCopyWindowInfo(
            Quartz.kCGWindowListOptionAll, Quartz.kCGNullWindowID)
            if window.get("kCGWindowOwnerPID") == identity.pid and window.get("kCGWindowLayer") == 0
            and window.get("kCGWindowBounds", {}).get("Width", 0) > 500]
        self.assertTrue(windows, "The isolated native window is missing")
        window = max(windows, key=lambda value: value["kCGWindowBounds"]["Width"])
        path = self.root / "logs" / (name + ".png")
        result = self.run_helper(["/usr/sbin/screencapture", "-x", "-o", "-l" +
            str(window["kCGWindowNumber"]), str(path)], timeout=15)
        self.assertEqual(result.returncode, 0, "Native window capture failed")
        self.assertGreater(path.stat().st_size, 1000)
        self.observe("semantic-native-screenshot", path=str(path), guiPID=identity.pid)

    def content(self, session, target, kind):
        response, metrics = read_content(self.api, session, target)
        self.observe("semantic-content-query", target=next(iter(target)), **metrics)
        return response_page(response, kind)

    def remember_fixture_children(self):
        def child_state():
            values = [json.loads(path.read_text()) for path in (self.root / "fake-state").glob("*.json")]
            children = [value for value in values if value["role"] == "structured"]
            return children if len(children) == 9 else None
        states = lifecycle.eventually("the nine owned synthetic agents", child_state)
        for state in states:
            child = lifecycle.process_info(state["pid"])
            self.assertIsNotNone(child)
            self.assertEqual(child[1], self.runtime_identity.pid)
            self.remember(child[0], "synthetic-codex")

    def assert_semantic_contract(self, session):
        tail = self.content(session, {"chatReadTail": {}}, "chatReadPage")
        cards = [block["content"]["card"]["_0"] for block in tail["blocks"] if "card" in block["content"]]
        self.assertEqual(cards[-1]["inputID"], LAST_INPUT)
        self.assertEqual(cards[-1]["id"], "status-card-" + LAST_INPUT)
        self.assertEqual(cards[-1]["header"]["state"], {"completed": {}})
        self.assertLessEqual(len(tail["blocks"]), 50)
        history = self.content(session, {"inputHistory": {}}, "inputHistoryPage")
        self.assertEqual(history["totalCount"], 128)
        self.assertEqual(history["entries"][-1]["id"], LAST_INPUT)
        self.assertLessEqual(len(history["entries"]), 50)
        self.assertIsNotNone(history.get("olderCursor"))
        oldest = self.content(session, {"chatReadAround": {"inputID": "semantic-input-0000"}}, "chatReadPage")
        block = next(block for block in oldest["blocks"] if block["id"] == "semantic-input-0000")
        reference = block["content"]["item"]["_0"]
        self.assertIn("deferred", reference, "Huge input was eagerly hydrated in a view page")
        self.assertEqual(reference["deferred"]["_0"]["id"], "semantic-input-0000")
        rows = self.content(session, {"chatCardRows": {"inputID": LAST_INPUT}}, "cardRowsPage")
        task = next(row for row in rows["rows"] if row["id"] == "task-" + TASK_ID)
        self.assertEqual(task["totalActionCount"], 3000)
        self.assertEqual(task["kind"]["task"]["state"], {"completed": {}})
        entries = self.content(session, {"chatRowEntries": {"inputID": LAST_INPUT,
            "rowID": task["id"]}}, "cardEntriesPage")
        self.assertLessEqual(len(entries["entries"]), 50)
        self.assertIsNotNone(entries.get("nextCursor"))
        self.observe("semantic-api-contract-passed", cardID=cards[-1]["id"],
            taskActions=task["totalActionCount"], totalInputs=history["totalCount"], directOldest=True,
            hugeInputDeferred=True, nativeUIVerified=False)

    def assert_identifier_count(self, identity, identifier, expected_count, *, prefix=False):
        script = '''tell application "System Events"
set targetProcess to first application process whose unix id is %d
set foundCount to 0
repeat with element in entire contents of window 1 of targetProcess
try
if value of attribute "AXIdentifier" of element %s "%s" then set foundCount to foundCount + 1
end try
end repeat
return foundCount
end tell''' % (identity.pid, 'starts with' if prefix else 'is', identifier)
        def matches():
            result = self.run_helper(["/usr/bin/osascript", "-e", script], timeout=30)
            self.assertEqual(result.returncode, 0, "Native accessibility enumeration failed")
            return result.stdout.decode().strip() == str(expected_count)
        lifecycle.eventually("the expected native accessibility count", matches, timeout=20)
        self.observe("semantic-native-count", identifier=identifier, count=expected_count)

    def assert_grid_and_input_response(self, identity):
        snapshot = self.api.snapshot()
        sessions = [lifecycle.session_value(snapshot, identifier, "chat") for identifier in GRID_IDS]
        def send_all(prefix):
            for index, session in enumerate(sessions):
                self.api.command(self.session_command(session, {"send": dict(text=f"{prefix}-{index}",
                    submit=True, attachments=[])}))
        def all_idle():
            snapshot = self.api.snapshot()
            return all("running" not in lifecycle.session_value(snapshot, identifier, "chat")["status"]
                for identifier in GRID_IDS)
        send_all("semantic-grid-prime")
        lifecycle.eventually("the eight fixture priming turns", all_idle)
        self.press_native(identity, "view-mode-grid", identifier=True)
        self.assert_identifier_count(identity, "grid-tile-", 9, prefix=True)
        send_all("semantic-grid-running")
        self.assert_native(identity, "printf semantic-grid-live")
        self.assert_identifier_count(identity, "GridTile.statusLine", 8)
        self.screenshot(identity, "semantic-nine-sessions-running")
        self.press_native(identity, "view-mode-single", identifier=True)
        self.press_native(identity, TITLE)
        draft = "Semantic responsive draft while eight sessions run."
        script = '''tell application "System Events"
set targetProcess to first application process whose unix id is %d
repeat with element in entire contents of window 1 of targetProcess
try
if value of attribute "AXIdentifier" of element is "ChatComposer.input" then
set value of element to "%s"
set observed to value of element
set value of element to ""
return observed
end if
end try
end repeat
error "The native composer was not found"
end tell''' % (identity.pid, draft)
        result = self.run_helper(["/usr/bin/osascript", "-e", script], timeout=30)
        self.assertEqual(result.returncode, 0, "The composer failed during nine-session load")
        self.assertEqual(result.stdout.decode().strip(), draft)
        self.observe("semantic-native-input-response", backgroundRunningSessions=8, draftRoundTrip=True)
        self.press_native(identity, "view-mode-grid", identifier=True)
        for session in sessions:
            self.api.command(self.session_command(session, {"interrupt": {}}))
        lifecycle.eventually("the eight interrupted fixture turns", all_idle)
        self.assert_identifier_count(identity, "GridTile.statusLine", 0)
        self.screenshot(identity, "semantic-nine-sessions-interrupted")
        self.press_native(identity, "view-mode-single", identifier=True)
        self.press_native(identity, TITLE)

    def test_long_card_and_history_remain_available_across_native_jump_and_reconnect(self):
        gui, identity = self.start_gui(self.original_app)
        discovery = lifecycle.eventually("the isolated semantic runtime", self.read_ready_discovery, timeout=90)
        self.runtime_identity = lifecycle.process_info(discovery["pid"])[0]
        self.assertTrue(Path(self.runtime_identity.executable).is_relative_to(self.store / "session-runtime-bundles"))
        self.remember(self.runtime_identity, "runtime")
        self.api = lifecycle.RuntimeAPI(self.store, discovery, self.observe, self.capture_runtime_timeout)
        handshake = self.api.request("GET", "/handshake")[1]
        self.assertTrue(handshake.get("supportsChatReadModel"), "The runtime lacks semantic-read support")
        application = self.api.request("GET", "/application-snapshot")[1]
        self.assertEqual(application["claudeBinaryPath"], self.agents["claudeCode"])
        session = self.get_session(SESSION_ID, "chat")
        self.remember_fixture_children()
        self.assert_semantic_contract(session)
        self.press_native(identity, TITLE)
        self.assert_native(identity, "AgentStatusCard", identifier=True)
        self.assert_native(identity, FINAL_TEXT)
        self.assert_identifier_count(identity, "ChatInputHistoryScrubber.tick", 12)
        self.screenshot(identity, "semantic-card-and-history")
        self.press_native(identity, "Validate semantic long card")
        self.assert_native(identity, f"printf semantic-work-{WORK_COUNT - 1:04d}")
        self.screenshot(identity, "semantic-card-expanded")
        self.press_native(identity, "ChatInputHistoryScrubber", identifier=True)
        self.assert_native(identity, "ChatInputHistoryScrubber.panel", identifier=True)
        self.press_native(identity, "ChatInputHistoryScrubber.loadEarlier", identifier=True)
        self.assert_native(identity, "Semantic input 0028")
        self.screenshot(identity, "semantic-history-page")
        self.press_native(identity, "ChatInputHistoryScrubber.loadEarlier", identifier=True)
        self.assert_native(identity, "Semantic oldest input.")
        self.press_native(identity, "Semantic oldest input.")
        self.assert_native(identity, "ChatTranscript.showFullItem", identifier=True)
        self.screenshot(identity, "semantic-oldest-direct-jump")
        self.press_native(identity, "ChatTranscript.jumpToLatest", identifier=True)
        self.assert_native(identity, FINAL_TEXT)
        self.screenshot(identity, "semantic-returned-to-tail")
        self.assert_grid_and_input_response(identity)
        quit_result = lifecycle.quit_application(identity)
        self.assertEqual(quit_result["sendStatus"], 0)
        self.assertEqual(gui.wait(timeout=30), 0)
        _, reconnected = self.start_gui(self.original_app)
        self.press_native(reconnected, TITLE)
        self.assert_native(reconnected, "AgentStatusCard", identifier=True)
        self.assert_native(reconnected, FINAL_TEXT)
        self.assert_identifier_count(reconnected, "ChatInputHistoryScrubber.tick", 12)
        saved = json.loads(self.transcript_file.read_text())
        self.assertEqual(saved[0]["userMessage"]["text"], FIRST_INPUT_TEXT)
        self.assertEqual(saved[-1]["agentMessage"]["text"], FINAL_TEXT)
        self.observe("semantic-native-acceptance-passed", card=True, independentHistory=True,
            nativeJump=True, nativeExpansion=True, nativeReturnToTail=True, guiReconnect=True,
            sourceBodyPreserved=True, nineSessionGridTested=True)


def fixture_protocol_observation():
    root = Path(__file__).resolve().parents[3] / ".verification/semantic-chat-read-20261110/native" / (
        "selfcheck-" + str(uuid.uuid4()))
    root.mkdir(parents=True)
    (root / "fake-state").mkdir()
    ownership = dict(purpose="Synthetic grid agent protocol prerequisite", session="semantic_native_acceptance",
        executable=sys.executable, script=str(Path(__file__).resolve()))
    path = root / "ownership.json"
    path.write_text(json.dumps(ownership, indent=2))
    requests = [dict(id=1, method="initialize"), dict(id=2, method="thread/resume"),
        dict(id=3, method="turn/start", params=dict(input=[dict(text="prime")])),
        dict(id=4, method="turn/start", params=dict(input=[dict(text="live")])),
        dict(id=5, method="turn/interrupt")]
    environment = dict(os.environ, PHLOX_SESSION_ID="fixture-selfcheck")
    process = subprocess.Popen([sys.executable, "-B", str(Path(__file__).resolve()), "--fake-codex",
        str(root), "--", "app-server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, env=environment)
    ownership["pid"] = process.pid
    path.write_text(json.dumps(ownership, indent=2))
    try:
        output, diagnostics = process.communicate(
            input=("\n".join(json.dumps(request) for request in requests) + "\n").encode(), timeout=10)
    except subprocess.TimeoutExpired:
        process.kill()
        output, diagnostics = process.communicate()
        raise AssertionError("Synthetic grid agent did not finish after its input ended") from None
    finally:
        ownership.update(exitCode=process.returncode, exited=process.poll() is not None)
        path.write_text(json.dumps(ownership, indent=2))
    (root / "stdout.jsonl").write_bytes(output)
    (root / "stderr.log").write_bytes(diagnostics)
    if process.returncode != 0:
        raise AssertionError("Synthetic grid agent protocol failed; see " + str(root))
    events = [json.loads(line) for line in output.splitlines()]
    outcomes = [event["params"]["turn"]["status"] for event in events if event.get("method") == "turn/completed"]
    commands = [event["params"]["item"]["command"] for event in events
        if event.get("method") == "item/started" and event["params"]["item"].get("type") == "commandExecution"]
    return outcomes, commands


class FixturePrerequisiteTests(unittest.TestCase):
    def test_grid_fixture_exposes_one_live_command_and_finishes_only_on_interrupt(self):
        outcomes, commands = fixture_protocol_observation()
        self.assertEqual(outcomes, ["completed", "interrupted"])
        self.assertEqual(commands, ["printf semantic-grid-live"])

    def test_restored_fixture_places_the_card_input_beyond_a_raw_tail_and_has_a_huge_oldest_input(self):
        items = synthetic_transcript()
        self.assertEqual(items[0]["userMessage"]["id"], "semantic-input-0000")
        self.assertGreater(len(items[0]["userMessage"]["text"].encode()), 2 * 1024 * 1024)
        self.assertEqual(items[-2]["taskList"]["tasks"], [dict(id=TASK_ID,
            title="Validate semantic long card", status="completed")])
        self.assertEqual(items[-1]["agentMessage"]["text"], FINAL_TEXT)
        self.assertEqual([next(iter(item)) for item in items[-50:]][:48], ["commandExecution"] * 48)
        self.assertEqual(len(items), 3258)


if __name__ == "__main__":
    if sys.argv[1:2] == ["--fake-codex"]:
        fake_codex(Path(sys.argv[2]).resolve(), sys.argv[3:])
        sys.exit(0)
    if sys.argv[1:] == ["--self-check"]:
        result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(
            FixturePrerequisiteTests))
        sys.exit(0 if result.wasSuccessful() else 1)
    lifecycle.OPTIONS, remaining = lifecycle.parse_options()
    if remaining:
        raise SystemExit("Unexpected arguments: " + " ".join(remaining))
    output = io.StringIO()
    suite = unittest.TestSuite([SemanticChatAcceptance(
        "test_long_card_and_history_remain_available_across_native_jump_and_reconnect")])
    result = unittest.TextTestRunner(stream=output, verbosity=2).run(suite)
    log = output.getvalue()
    sys.stderr.write(log)
    if (lifecycle.OPTIONS.work_dir / "logs").is_dir():
        (lifecycle.OPTIONS.work_dir / "logs/test-result.log").write_text(log)
    sys.exit(0 if result.wasSuccessful() else 1)
