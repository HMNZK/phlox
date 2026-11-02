#!/usr/bin/env python3
"""隔離アプリで2200項目以上の履歴の転送・送信・中断・保存を検査する。

compact-test経由で --app と新しい --work-dir を指定する。
--inspection-pause-seconds はAPI検査後のGUI操作用。API時間を入力遅延と扱わない。
"""
import copy
import hashlib
import http.client
import importlib.util
import io
import json
from pathlib import Path
import shlex
import statistics
import sys
import threading
import time
import unittest


spec = importlib.util.spec_from_file_location(
    "runtime_lifecycle", Path(__file__).with_name("session-runtime-lifecycle.test.py"))
lifecycle = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = lifecycle
spec.loader.exec_module(lifecycle)

ROUNDS = 5
HISTORY_ITEMS = 2200


def session_key(value):
    return value["rawValue"]


def apply_update(update, baseline=None):
    restored = copy.deepcopy(update["snapshot"])
    if "baseSequence" not in update:
        assert not update["chatPatches"], "A full response must not contain patches"
        return dict(sequence=update["sequence"], snapshot=restored)
    assert baseline is not None and update["baseSequence"] == baseline["sequence"]
    previous = {session_key(entry["chat"]["_0"]["id"]): entry["chat"]["_0"]
                for entry in baseline["snapshot"]["sessions"] if "chat" in entry}
    current = {session_key(entry["chat"]["_0"]["id"]): entry["chat"]["_0"]
               for entry in restored["sessions"] if "chat" in entry}
    seen = set()
    for patch in update["chatPatches"]:
        key = session_key(patch["id"])
        assert key not in seen
        seen.add(key)
        old, new = previous[key], current[key]
        assert patch["executionID"] == old["executionID"] == new["executionID"]
        assert new["transcript"] == []
        new["transcript"] = apply_array(patch["transcript"], old["transcript"])
        assert new["rawEventLog"] == []
        retained = patch["rawEventLog"]["retainedSuffixCount"]
        assert isinstance(retained, int) and 0 <= retained <= len(old["rawEventLog"])
        new["rawEventLog"] = (old["rawEventLog"][-retained:] if retained else []) + patch["rawEventLog"]["appended"]
        for child, change in patch["subAgentTranscripts"].items():
            assert new["subAgents"]["transcripts"][child] == []
            new["subAgents"]["transcripts"][child] = apply_array(change, old["subAgents"]["transcripts"][child])
        for flag, field in (("reusedSkillSelection", "skillSelection"),
                            ("reusedHistoryEntries", "historyEntries"),
                            ("reusedHistorySummaries", "historySummaries")):
            if patch[flag]:
                if field in old:
                    new[field] = old[field]
                else:
                    new.pop(field, None)
    return dict(sequence=update["sequence"], snapshot=restored)


def apply_array(patch, baseline):
    count = patch["prefixCount"]
    assert isinstance(count, int) and 0 <= count <= len(baseline)
    return baseline[:count] + patch["suffix"]


class LargeHistoryTests(lifecycle.SessionRuntimeLifecycleTests):
    def setUp(self):
        super().setUp()
        self.report["purpose"] = "Isolated large-history transfer and API responsiveness acceptance"
        fixture = Path(__file__).with_name("session-runtime-large-history-fake-agent.py").resolve(strict=True)
        wrapper = Path(self.agents["codex"])
        arguments = [sys.executable, str(fixture), "--work-dir", str(self.root), "--provider", "codex", "--"]
        wrapper.write_text("#!/bin/sh\nexec " + " ".join(shlex.quote(value) for value in arguments) + ' "$@"\n')
        wrapper.chmod(0o700)
        self.report["largeHistorySourceHashes"] = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in (Path(__file__).resolve(), fixture)}
        self.metrics = dict(failures=[], full=[], updates=[], send=[], interrupt=[], pollRequests=0,
                            uiInputLatencyMeasured=False, apiRounds=ROUNDS, validationComplete=False)
        self.write_report()

    def measured_snapshot(self, path, base_sequence=None):
        connection = http.client.HTTPConnection("127.0.0.1", self.api.port, timeout=20)
        headers = {"Authorization": "Bearer " + self.api._token,
            "X-Phlox-Runtime-Protocol": str(self.api.protocol),
            "X-Phlox-Runtime-Generation": self.api.generation}
        if base_sequence is not None:
            headers["X-Phlox-Runtime-Snapshot-Base"] = str(base_sequence)
        started = time.perf_counter()
        try:
            connection.request("GET", path, headers=headers)
            response = connection.getresponse()
            data = response.read(64 * 1024 * 1024 + 1)
            elapsed = time.perf_counter() - started
            self.assertEqual(response.status, 200)
            self.assertLessEqual(len(data), 64 * 1024 * 1024)
            value = json.loads(data)
            return value, dict(responseBytes=len(data), responseSeconds=elapsed,
                              decodeSeconds=time.perf_counter() - started - elapsed, status=response.status)
        finally:
            connection.close()

    def record_command(self, command, kind):
        operation = self.api.operation(command)
        started = time.perf_counter()
        first = self.api.request("POST", "/command", operation)
        elapsed = time.perf_counter() - started
        self.assertEqual(self.api.request("POST", "/command", operation), first,
                         "Replaying one operation must return the same result")
        self.metrics[kind].append(dict(responseSeconds=elapsed, operationReplays=1))

    def test_large_history_delta_and_commands_preserve_content(self):
        gui, gui_identity = self.start_gui(self.original_app)
        discovery = lifecycle.eventually("the isolated runtime", self.read_ready_discovery, timeout=90)
        self.assertEqual(lifecycle.file_url(discovery["storeURL"]), self.store.resolve())
        runtime = lifecycle.process_info(discovery["pid"])
        self.assertIsNotNone(runtime)
        self.runtime_identity = runtime[0]
        self.assertTrue(Path(self.runtime_identity.executable).is_relative_to(self.store / "session-runtime-bundles"))
        self.remember(self.runtime_identity, "runtime")
        self.api = lifecycle.RuntimeAPI(self.store, discovery, self.observe, self.capture_runtime_timeout)
        handshake = self.api.request("GET", "/handshake")[1]
        self.assertTrue(handshake.get("supportsSnapshotUpdates"), "The app does not support snapshot updates")
        application = self.api.request("GET", "/application-snapshot")[1]
        self.assertEqual(application["claudeBinaryPath"], self.agents["claudeCode"])
        identifier = self.spawn("codex", "appServer")
        self.api.command({"renameSession": {"_0": identifier, "_1": "大履歴検証"}})
        fake = lifecycle.eventually("the dedicated Codex fake", lambda: self.fake_state("structured"))
        child = lifecycle.process_info(fake["pid"])
        self.assertIsNotNone(child)
        self.assertEqual(child[1], self.runtime_identity.pid)
        self.remember(child[0], "large-history-fake")
        chat = lifecycle.eventually("the ready chat", lambda: self.get_session(identifier, "chat"))
        lifecycle.eventually("chat readiness", lambda: "starting" not in self.get_session(identifier, "chat")["status"])
        self.api.command(self.session_command(chat, {"send": dict(text="large-history-seed", submit=True, attachments=[])}))

        def seeded_chat():
            value = self.get_session(identifier, "chat")
            seeded = [item for item in value["transcript"] if item.get("agentMessage", {}).get("id", "").startswith("large-history-")]
            return value if len(seeded) == HISTORY_ITEMS and "running" not in value["status"] else None

        chat = lifecycle.eventually("2200 persisted fixture outputs", seeded_chat, timeout=90)
        self.assertEqual(self.fake_state("structured")["emittedHistoryItems"], HISTORY_ITEMS)
        seed_items = [item for item in chat["transcript"] if item.get("agentMessage", {}).get("id", "").startswith("large-history-")]
        self.assertGreaterEqual(sum(len(item["agentMessage"]["text"].encode()) for item in seed_items), 3 * 1024 * 1024)
        self.observe("large-history-ready", itemCount=len(seed_items), guiPID=gui_identity.pid,
                     guiExecutable=gui_identity.executable, runtimePID=self.runtime_identity.pid)
        # 単一クライアントで差分の基準を固定し、GUIのpollによるcache退去を分ける。
        quit_result = lifecycle.quit_application(gui_identity, wait_for_reply=True)
        self.assertEqual(quit_result["sendStatus"], 0)
        self.assertIn(quit_result.get("replyError"), (None, 0))
        self.assertEqual(gui.wait(timeout=30), 0)
        initial, _ = self.measured_snapshot("/snapshot-update")
        baseline = apply_update(initial)
        for _ in range(ROUNDS):
            complete, full_metric = self.measured_snapshot("/snapshot")
            update, update_metric = self.measured_snapshot("/snapshot-update", baseline["sequence"])
            self.assertEqual(update.get("baseSequence"), baseline["sequence"])
            baseline = apply_update(update, baseline)
            self.assertEqual(lifecycle.session_value(baseline["snapshot"], identifier, "chat"),
                             lifecycle.session_value(complete["snapshot"], identifier, "chat"))
            self.assertLess(update_metric["responseBytes"], full_metric["responseBytes"] // 10)
            self.metrics["full"].append(full_metric)
            self.metrics["updates"].append(update_metric)

        stopped = threading.Event()
        poll_failures = []
        poll_events = []

        def poll_full_snapshots():
            api = lifecycle.RuntimeAPI(self.store, discovery,
                lambda event, **values: poll_events.append(dict(event=event, **values)),
                lambda: poll_events.append(dict(event="poll-timeout-diagnostic-deferred")))
            while not stopped.is_set():
                try:
                    api.snapshot()
                    self.metrics["pollRequests"] += 1
                except (OSError, AssertionError, ValueError, http.client.HTTPException) as error:
                    poll_failures.append(type(error).__name__)
                    return
                stopped.wait(0.02)

        poller = threading.Thread(target=poll_full_snapshots, name="large-history-snapshot-load")
        poller.start()
        try:
            for index in range(ROUNDS):
                text = f"large-history-round-{index}"
                chat = self.get_session(identifier, "chat")
                self.record_command(self.session_command(chat,
                    {"send": dict(text=text, submit=True, attachments=[])}), "send")
                lifecycle.eventually("one send at the fake", lambda: self.fake_state("structured")["sendTexts"].count(text) == 1)
                lifecycle.eventually("an active turn", lambda: "running" in self.get_session(identifier, "chat")["status"])
                chat = self.get_session(identifier, "chat")
                self.record_command(self.session_command(chat, {"interrupt": {}}), "interrupt")
                lifecycle.eventually("one interrupt at the fake", lambda: self.fake_state("structured")["interruptCount"] == index + 1)
                lifecycle.eventually("turn interruption", lambda: "running" not in self.get_session(identifier, "chat")["status"])
        finally:
            stopped.set()
            poller.join(timeout=30)
            self.assertFalse(poller.is_alive(), "The owned snapshot load thread did not stop")
        self.assertEqual(poll_failures, [])
        self.assertGreater(self.metrics["pollRequests"], 0)
        self.metrics["pollEvents"] = poll_events
        fake = self.fake_state("structured")
        self.assertEqual(fake["sendTexts"], ["large-history-seed"] + [f"large-history-round-{i}" for i in range(ROUNDS)])
        self.assertEqual(fake["interruptCount"], ROUNDS)
        final_chat = self.get_session(identifier, "chat")
        actual_seed = [item for item in final_chat["transcript"] if item.get("agentMessage", {}).get("id", "").startswith("large-history-")]
        self.assertEqual(actual_seed, seed_items, "Heavy history changed during send and interrupt")
        final_chat = self.assert_tail_update(identifier)
        self.write_metrics()

        if lifecycle.OPTIONS.inspection_pause_seconds:
            gui, gui_identity = self.start_gui(self.original_app, new_instance=False)
            self.assertIsNone(gui.poll())
            before = self.fake_state("structured")
            self.observe("large-history-ui-inspection-ready", guiPID=gui_identity.pid,
                guiExecutable=gui_identity.executable, pauseSeconds=lifecycle.OPTIONS.inspection_pause_seconds,
                inspectionDeadlineUnix=time.time() + lifecycle.OPTIONS.inspection_pause_seconds,
                sessionTitle="大履歴検証", itemCount=len(final_chat["transcript"]), apiRoundsFinished=ROUNDS)
            deadline = time.monotonic() + lifecycle.OPTIONS.inspection_pause_seconds
            while time.monotonic() < deadline:
                time.sleep(min(0.2, max(0, deadline - time.monotonic())))
            after = self.fake_state("structured")
            self.observe("large-history-ui-inspection-finished", additionalSends=len(after["sendTexts"]) - len(before["sendTexts"]),
                         additionalInterrupts=after["interruptCount"] - before["interruptCount"])
            final_chat = self.get_session(identifier, "chat")
        self.assert_persisted(identifier, final_chat["transcript"])
        self.metrics["validationComplete"] = True
        self.write_metrics()

    def assert_tail_update(self, identifier):
        initial, _ = self.measured_snapshot("/snapshot-update")
        baseline = apply_update(initial)
        chat = lifecycle.session_value(baseline["snapshot"], identifier, "chat")
        self.api.command(self.session_command(chat, {"send": dict(text="large-history-tail-patch", submit=True, attachments=[])}))
        lifecycle.eventually("the controlled tail output", lambda:
            self.fake_state("structured")["sendTexts"][-1] == "large-history-tail-patch")
        attempts = []
        deadline = time.monotonic() + 10
        while True:
            update, metric = self.measured_snapshot("/snapshot-update", baseline["sequence"])
            self.assertEqual(update.get("baseSequence"), baseline["sequence"])
            restored = apply_update(update, baseline)
            patch = next(patch for patch in update["chatPatches"] if patch["id"] == identifier)
            actual = lifecycle.session_value(restored["snapshot"], identifier, "chat")
            attempts.append(metric)
            if any("large-history-tail-patch" in item.get("agentMessage", {}).get("text", "")
                   for item in patch["transcript"]["suffix"]):
                break
            self.assertLess(time.monotonic(), deadline, "The tail output never reached a delta response")
            baseline = restored
            time.sleep(0.01)
        self.assertGreaterEqual(patch["transcript"]["prefixCount"], HISTORY_ITEMS)
        self.assertGreater(len(patch["transcript"]["suffix"]), 0)
        payload = lifecycle.session_value(update["snapshot"], identifier, "chat")
        self.observe("large-history-tail-response-observation", responseBytes=metric["responseBytes"],
            fields={key: len(json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode())
                    for key, value in payload.items()},
            transcriptPrefixCount=patch["transcript"]["prefixCount"],
            transcriptSuffixItems=len(patch["transcript"]["suffix"]))
        self.assertLess(metric["responseBytes"], 128 * 1024)
        complete = self.get_session(identifier, "chat")
        self.assertEqual(actual["transcript"], complete["transcript"])
        self.api.command(self.session_command(complete, {"interrupt": {}}))
        lifecycle.eventually("tail turn interruption", lambda: "running" not in self.get_session(identifier, "chat")["status"])
        self.metrics["tailUpdate"] = metric
        self.metrics["tailUpdateAttempts"] = attempts
        return self.get_session(identifier, "chat")

    def assert_persisted(self, identifier, transcript):
        path = self.store / "transcripts" / (identifier["rawValue"].upper() + ".json")

        def saved_matches():
            if not path.exists():
                return False
            saved = json.loads(path.read_text())
            return saved == transcript

        lifecycle.eventually("final history saved without loss or reordering", saved_matches, timeout=45)
        self.observe("large-history-content-and-save-match", transcriptItems=len(transcript),
                     persistedBytes=path.stat().st_size)

    def write_metrics(self):
        for kind in ("send", "interrupt", "full", "updates"):
            values = [sample["responseSeconds"] for sample in self.metrics[kind]]
            self.metrics[kind + "Summary"] = dict(count=len(values), medianSeconds=statistics.median(values),
                minimumSeconds=min(values), maximumSeconds=max(values))
        (self.root / "logs/large-history-metrics.json").write_text(json.dumps(self.metrics, indent=2))


if __name__ == "__main__":
    lifecycle.OPTIONS, remaining = lifecycle.parse_options()
    if remaining:
        raise SystemExit("Unexpected arguments: " + " ".join(remaining))
    output = io.StringIO()
    suite = unittest.TestSuite([LargeHistoryTests("test_large_history_delta_and_commands_preserve_content")])
    result = unittest.TextTestRunner(stream=output, verbosity=2).run(suite)
    log = output.getvalue()
    sys.stderr.write(log)
    if (lifecycle.OPTIONS.work_dir / "logs").is_dir():
        (lifecycle.OPTIONS.work_dir / "logs/test-result.log").write_text(log)
    sys.exit(0 if result.wasSuccessful() else 1)
