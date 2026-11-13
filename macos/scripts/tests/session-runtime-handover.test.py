#!/usr/bin/env python3
"""計画的な実行サービス更新（ADR 0233）の受入。隔離した署名済みDebugアプリ2つとフェイクCLIだけを使う（実CLIなし）。

旧（--app）と新（--update-app）は、同じソース・同じ固有bundle IDから、CFBundleVersionだけを変えて作ったDebugビルド
（新は managed-build の別の key で、xcodebuild に CURRENT_PROJECT_VERSION=<旧と違う値> を渡す）。
切り替えは利用者と同じ経路で要求する（旧の画面を閉じ、新の画面を開く → 新の画面が旧ホストへ handover を送る）。
1回の実行で1シナリオ。--work-dir は毎回新しい空のディレクトリ。

  ~/.agents/scripts/compact-test --full runtime-handover python3 -B <this-file> \\
    --app <旧 Phlox.app> --update-app <新 Phlox.app> \\
    --work-dir <worktree>/.verification/<作業名>/<新しい空ディレクトリ> --scenario planned|adoption-failure

planned: PTY・Cursorが動く間は延期され何も変わらない。それらを外すと切り替わり、Codex（質問待ち・出力中）と
  Claude（承認待ち）の子とholderが同じプロセスのまま新ホストへ移る。出力の欠落・重複なし、回答は子へ一度だけ、
  旧世代の操作は409、切り替え後の送信と新規チャット（新ホストのholder）が通る。
adoption-failure: ClaudeのholderのソケットをPermission 000にしてから切り替える。Claudeは復旧待ち（子とholderは生存、
  確定点に項目が残る、送信・resumeChatで新しいCLIを起動しない）。Codexは採用され確定点から外れる。
証拠は <work-dir>/ownership.json（観測の時系列）と <work-dir>/logs/handover-diagnostics.json（止まった段・世代・PID・子の受信記録）。
lifecycle受入（session-runtime-lifecycle.test.py）の隔離・所有確認・後片付けを継承する。
"""
import argparse
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import socket
import stat
import sys
import time
import unittest
import uuid

spec = importlib.util.spec_from_file_location("lifecycle", Path(__file__).with_name("session-runtime-lifecycle.test.py"))
lifecycle = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = lifecycle
spec.loader.exec_module(lifecycle)
process_info, same_process = lifecycle.process_info, lifecycle.same_process

STREAM = re.compile(r"runtime-stream:(\d+)")
RECOVERY = "handover recovery needed"
DEFERRED = "更新を延期しました"
HANDOVER = None


def uuid_text(identifier):
    """SessionIDのJSON（{"rawValue": "<UUID>"}）を、holder.json・確定点と比べる大文字のUUID文字列にする。"""
    value = identifier["rawValue"] if isinstance(identifier, dict) else identifier
    return value.upper()


def build_number(version, label):
    """CFBundleVersionを比較用の整数の並びにする（HostBuildOrderと同じ規則。末尾の0は比較に影響しない）。"""
    parts = version.split(".")
    if not all(part.isascii() and part.isdigit() for part in parts):
        raise AssertionError(f"{label} has a CFBundleVersion that is not numeric: {version!r}")
    numbers = [int(part) for part in parts]
    while numbers and numbers[-1] == 0:
        numbers.pop()
    return tuple(numbers)


class RuntimeHandoverAcceptance(lifecycle.SessionRuntimeLifecycleTests):
    test_pty_and_codex_survive_gui_lifecycle_until_explicit_stop = None  # 継承元の受入は別に実行する

    def setUp(self):
        self.started_at = time.time()
        self.stage = "setup"
        self.blocked_sockets = {}
        self.socket_directories = set()
        # 今開いている画面（同時に1つだけ）。dict(process, identity, build="old"|"new")。閉じたらNone。
        self.gui = None
        super().setUp()
        # 後に登録したものが先に走る: 診断 → 自分のストアのプロセスを後片付けの対象へ → 継承元の後片付け。
        self.addCleanup(self.adopt_store_processes_for_cleanup)
        self.addCleanup(self.write_diagnostics)
        self.update_app = self.root / "update/Phlox.app"
        shutil.copytree(HANDOVER.update_app, self.update_app, symlinks=True)
        with (self.update_app / "Contents/Info.plist").open("rb") as handle:
            update_info = plistlib.load(handle)
        signed = self.run_helper(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(self.update_app)], timeout=30)
        self.assertEqual(signed.returncode, 0, "The update app failed strict code signature verification")
        self.assertEqual(update_info["CFBundleIdentifier"], self.bundle_id, "Both builds must share the isolated bundle ID")
        self.assertEqual(update_info["CFBundleExecutable"], self.info["CFBundleExecutable"])
        # 画面が更新を要求するのは、自分のビルド番号がホストより数値で大きいときだけ（HostBuildOrder）。
        self.assertGreater(build_number(update_info["CFBundleVersion"], "--update-app"),
                           build_number(self.info["CFBundleVersion"], "--app"),
                           "The update app must have a numerically greater CFBundleVersion")
        self.assertIsNotNone(self.info.get("PhloxHandoverFormat"), "The builds do not declare PhloxHandoverFormat")
        self.assertEqual(update_info.get("PhloxHandoverFormat"), self.info["PhloxHandoverFormat"])
        self.old_build, self.new_build = self.info["CFBundleVersion"], update_info["CFBundleVersion"]
        executable = self.update_app / "Contents/MacOS" / update_info["CFBundleExecutable"]
        self.observe("update-app", path=str(self.update_app), oldBuild=self.old_build, newBuild=self.new_build,
                     scenario=HANDOVER.scenario, executableSHA256=hashlib.sha256(executable.read_bytes()).hexdigest(),
                     testSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())

    def test_handover(self):
        {"planned": self.run_planned, "adoption-failure": self.run_adoption_failure}[HANDOVER.scenario]()

    # MARK: - 観測

    def set_stage(self, name, **values):
        self.stage = name
        self.observe("stage", stage=name, **values)

    def wait(self, description, predicate, timeout=40):
        return lifecycle.eventually(f"{description} [stage: {self.stage}]", predicate, timeout=timeout)

    def discovery(self):
        return lifecycle.private_json(self.store / "session-runtime/discovery.json")

    def holder_records(self):
        records = []
        for path in sorted((self.store / "session-runtime/holders").glob("*/holder.json")):
            try:
                records.append(json.loads(path.read_text()))
            except (OSError, ValueError):
                continue  # holderが書き換え中（原子的に置き換わる）
        return records

    def live_holders(self, session_id):
        return [record for record in self.holder_records()
                if record.get("metadata", {}).get("session", "").upper() == uuid_text(session_id)
                and process_info(record["holderPID"]) is not None]

    def fake(self, pid):
        path = self.root / "fake-state" / f"{pid}.json"
        return json.loads(path.read_text()) if path.exists() else None

    def provider_pids(self, provider):
        states = [json.loads(path.read_text()) for path in (self.root / "fake-state").glob("*.json")]
        return {state["pid"] for state in states if state["role"] == "structured" and state["provider"] == provider}

    def chat(self, identifier):
        return self.get_session(identifier, "chat")

    def pending_questions(self, identifier):
        return [item["userQuestion"] for item in self.chat(identifier)["transcript"]
                if item.get("userQuestion", {}).get("state") == "pending"]

    def stream_tokens(self, identifier):
        texts = [item["agentMessage"]["text"] for item in self.chat(identifier)["transcript"] if "agentMessage" in item]
        return [int(value) for text in texts for value in STREAM.findall(text)]

    def checkpoint(self, name="checkpoint.json"):
        path = self.store / "session-runtime/handover" / name
        return json.loads(path.read_text()) if path.exists() else None

    # MARK: - 操作

    def adopt_runtime(self, discovery):
        """discoveryの常駐サービスを検査対象にする（所有・キャッシュのバンドル・フェイクCLIの適用を確かめる）。"""
        self.assertEqual(lifecycle.file_url(discovery["storeURL"]), self.store.resolve())
        current = process_info(discovery["pid"])
        self.assertIsNotNone(current, "The published runtime is not running")
        self.assertTrue(Path(current[0].executable).is_relative_to(self.store / "session-runtime-bundles"))
        self.runtime_identity = current[0]
        self.remember(current[0], "runtime")
        self.api = lifecycle.RuntimeAPI(self.store, discovery, self.observe, self.capture_runtime_timeout)
        application = self.api.request("GET", "/application-snapshot")[1]
        self.assertEqual(application["claudeBinaryPath"], self.agents["claudeCode"],
                         "Fake binary override was not applied; real CLI execution is forbidden")
        return current[0]

    def start_runtime(self):
        self.open_gui("old")
        discovery = self.wait("the ready runtime", self.read_ready_discovery, timeout=90)
        self.adopt_runtime(discovery)
        self.assertEqual(discovery.get("runtimeBuild"), self.old_build)
        self.assertTrue(discovery.get("supportsHandover"), "The runtime does not declare handover support")
        return discovery

    def open_gui(self, build):
        """画面を開く（旧="old"・新="new"）。開いている画面があれば取り違えなので失敗させる。新の画面は開くと更新を要求する。"""
        self.assertIsNone(self.gui, f"A {self.gui and self.gui['build']} GUI is still open")
        process, identity = self.start_gui(self.original_app if build == "old" else self.update_app)
        self.gui = dict(process=process, identity=identity, build=build)
        self.observe("gui-open", guiPID=identity.pid, build=build)

    def close_gui(self):
        """開いている画面を通常の終了で閉じる（実行サービスは止まらない）。"""
        self.assertIsNotNone(self.gui, "No GUI is open")
        gui, self.gui = self.gui, None
        result = lifecycle.quit_application(gui["identity"])
        self.observe("gui-quit", guiPID=gui["identity"].pid, build=gui["build"], **result)
        self.assertEqual(result["sendStatus"], 0, "Normal quit AppleEvent did not receive a reply")
        self.assertIn(result.get("replyError"), (None, 0), "Normal quit AppleEvent was rejected by the GUI")
        self.assertEqual(gui["process"].wait(timeout=30), 0, "The GUI did not quit successfully")

    def spawn_chat(self, provider):
        identifier = self.spawn(provider, "appServer")
        if provider == "claudeCode":
            self.api.command(self.session_command(self.chat(identifier), {"spawnPermission": {"_0": "manual"}}))
            self.wait("Claude manual permission mode",
                      lambda: self.chat(identifier).get("selectedPermissionProfile") == "manual")
        return identifier

    def send(self, identifier, text):
        operation = self.api.operation(self.session_command(self.chat(identifier), {
            "send": dict(text=text, submit=True, attachments=[])}))
        self.api.request("POST", "/command", operation)
        return operation

    def held_child(self, session_id):
        """セッションの子と、それを持つholder（holder.jsonのmetadata.session）。今の常駐サービスが起動したものに限る。"""
        record = self.wait("the holder of session " + uuid_text(session_id),
                           lambda: (lambda found: found[0] if len(found) == 1 else None)(self.live_holders(session_id)))
        child, holder = process_info(record["childPID"]), process_info(record["holderPID"])
        self.assertIsNotNone(child, "The held child is gone")
        self.assertIsNotNone(holder, "The holder is gone")
        self.assertEqual(child[1], holder[0].pid, "The child is not held by its recorded holder")
        self.assertEqual(holder[0].executable, self.runtime_identity.executable, "The holder is not this runtime's bundle")
        self.assertEqual(holder[1], self.runtime_identity.pid, "The holder was not started by this runtime")
        self.remember(holder[0], "holder")
        self.remember(child[0], "structured-child")
        directory = str(Path(record["socketPath"]).parent)
        if directory not in self.socket_directories:
            # holderはSIGTERMで後始末せずに終わるので、ソケットのディレクトリが残る。後片付けの対象として記録する。
            self.socket_directories.add(directory)
            self.observe("holder-socket-directory", path=directory)
        self.wait("the fixture state of the held child", lambda: self.fake(child[0].pid))
        return dict(session=uuid_text(session_id), record=record, child=child[0], holder=holder[0])

    def start_codex_turn(self, identifier, answer_approval):
        codex = self.held_child(identifier)
        pid = codex["child"].pid
        self.send(identifier, "handover-codex")
        approval = self.wait("the Codex approval", lambda: self.chat(identifier)["pendingApprovals"])
        if answer_approval:
            self.api.command(self.session_command(self.chat(identifier), {
                "approval": {"_0": approval[0]["id"], "decision": "accept"}}))
            self.wait("one Codex approval reply", lambda: len(self.fake(pid)["approvalReplies"]) == 1)
            codex["question"] = self.wait("the Codex question", lambda: self.pending_questions(identifier))[0]["requestId"]
        self.wait("Codex output during the turn", lambda: len(self.stream_tokens(identifier)) >= 3)
        return codex

    def assert_control_check(self, claude, marker):
        """子が受け継いだURL・トークンでControl APIを呼び、200で届くことを確かめる。"""
        (claude["controls"] / marker).touch()
        check = self.wait(f"the retained Control API call ({marker})", lambda: next((item for item in self.fake(
            claude["child"].pid)["controlChecks"] if item["marker"] == marker), None))
        self.assertEqual(check.get("status"), 200, f"The original child's Control API credential failed: {check}")
        return check

    def start_claude_turn(self, identifier):
        text = "handover-claude-" + str(uuid.uuid4())
        operation = self.send(identifier, text)
        claude = self.held_child(identifier)
        pid = claude["child"].pid
        state = self.wait("the active Claude turn", lambda: (lambda s: s if s and s["active"] else None)(self.fake(pid)))
        claude["controls"] = Path(state["controlDirectory"])
        self.assertTrue(claude["controls"].is_relative_to(self.root / "fake-control"))
        (claude["controls"] / "turn-1.approval").touch()
        question = self.wait("the Claude tool approval", lambda: self.pending_questions(identifier))[0]
        self.assertIsNotNone(question["questions"][0].get("permission"))
        claude.update(text=text, operation=operation, question=question["requestId"],
                      answerKey=question["questions"][0].get("id") or question["questions"][0]["question"])
        return claude

    def answer_once(self, identifier, command, replies):
        """同じ操作の再送は同じ結果、新しい操作は対象なし（false）。子の受信は1回だけ。"""
        command = self.session_command(self.chat(identifier), command)
        operation = self.api.operation(command)
        first = self.api.request("POST", "/command", operation)
        self.assertEqual(self.api.request("POST", "/command", operation), first)
        self.wait("one reply at the original child", lambda: len(replies()) == 1)
        self.assertEqual(self.api.command(command), {"session": {"_0": {"bool": {"_0": False}}}})
        self.assertEqual(len(replies()), 1)

    def wait_for_deferral(self, before):
        def deferred():
            current = self.discovery()
            if current["generation"] != before["generation"]:
                raise AssertionError("The runtime was replaced while unsupported executions were running")
            return current if (current.get("updateStatus") or "").startswith(DEFERRED) else None
        return self.wait("a deferred update", deferred, timeout=60)

    def wait_for_new_generation(self, before):
        """新しい世代の準備完了。起動失敗は待たずに失敗させる。一時的な延期は画面の自動再要求（30秒ごと）に任せ、
        期限切れでは最後の延期・中止の理由（updateStatus）を出す（中止の理由はdiscoveryにしか出ない）。"""
        latest, statuses = {}, []

        def ready():
            path = self.store / "session-runtime/discovery.json"
            if not path.exists():
                return None
            current = lifecycle.private_json(path)
            latest.clear()
            latest.update(current)
            status = current.get("updateStatus")
            if status and status != before.get("updateStatus") and status not in statuses:
                statuses.append(status)
                self.observe("update-status", generation=current["generation"], status=status)
            if current["state"] == "failed":
                raise AssertionError(f"The runtime failed [stage: {self.stage}]: {current.get('failure')}")
            if current["generation"] == before["generation"]:
                return None
            return current if current["state"] == "ready" and current.get("desktopURL") else None

        try:
            return self.wait("a new runtime generation", ready, timeout=120)
        except AssertionError as error:
            raise AssertionError(f"{error}; latest state={latest.get('state')} generation={latest.get('generation')} "
                                 f"updateStatus history={statuses}") from None
        finally:
            self.observe("handover-discovery", **{key: latest.get(key) for key in (
                "generation", "pid", "state", "runtimeBuild", "updateStatus", "failure")})

    def request_handover(self, before, before_wait=None):
        """画面が閉じた状態から新の画面を開き（新の画面が旧ホストへ切り替えを要求する）、新しい世代を検査対象にする。
        `before`は要求の直前に読んだdiscovery。戻り値は新しい世代のdiscovery（新の画面は開いたまま）。"""
        self.assertIsNone(self.gui, "Close the open GUI before requesting the handover")
        self.open_gui("new")
        if before_wait is not None:
            before_wait()
        new = self.wait_for_new_generation(before)
        old_runtime = self.runtime_identity
        self.adopt_runtime(new)
        self.assertNotEqual(new["generation"], before["generation"])
        self.assertNotEqual(self.runtime_identity.pid, old_runtime.pid)
        self.assertEqual(new.get("runtimeBuild"), self.new_build, "The new runtime is not the update build")
        self.assertNotEqual(self.runtime_identity.executable, old_runtime.executable,
                            "The new runtime does not run from the update bundle copy")
        self.wait("the old runtime to exit", lambda: not same_process(old_runtime))
        return new

    def assert_same_children(self, *items):
        for item in items:
            self.assertTrue(same_process(item["child"]), f"Child of {item['session']} changed or exited")
            self.assertTrue(same_process(item["holder"]), f"Holder of {item['session']} changed or exited")
            self.assertEqual(process_info(item["child"].pid)[1], item["holder"].pid)

    def assert_rejected_without_new_cli(self, identifier, claude, command, is_send):
        """操作が処理された証拠（応答。送信は受付後に失敗が公開される）を確かめてから、新しいClaudeの子とholderが現れないことを見る。"""
        pids, markers = self.provider_pids("claudeCode"), self.fake(claude["child"].pid)["inputMarkers"]
        status, _ = self.api.request("POST", "/command", self.api.operation(command), accepted=(200, 400))
        if status == 200 and is_send:
            self.wait("the published send failure", lambda: self.chat(identifier).get("sendFailure"), timeout=15)
        time.sleep(3)  # 起動が遅れて始まる場合の観測時間
        self.assertEqual(self.provider_pids("claudeCode"), pids, "A new Claude CLI was started")
        self.assertEqual(len(self.live_holders(identifier)), 1, "A new holder was started for the recovery session")
        self.assertEqual(self.fake(claude["child"].pid)["inputMarkers"], markers, "The original child received input")
        self.assert_same_children(claude)
        return status

    # MARK: - シナリオ

    def run_planned(self):
        # 画面の流れ: 旧を開く → 実行を始める → 旧を閉じ新を開く（延期） → 新を閉じてから阻害要因を外す
        # → 新を開く（切り替え。以後は新が開いたまま）。
        discovery = self.start_runtime()
        self.set_stage("start-executions")
        codex_id, claude_id = self.spawn_chat("codex"), self.spawn_chat("claudeCode")
        codex = self.start_codex_turn(codex_id, answer_approval=True)
        claude = self.start_claude_turn(claude_id)
        pty_id = self.spawn("claudeCode", "pty")
        pty = process_info(self.wait("the fake PTY child", lambda: self.fake_state("pty"))["pid"])
        self.assertEqual(pty[1], self.runtime_identity.pid)
        self.remember(pty[0], "pty")
        cursor_id = self.spawn_chat("cursor")
        self.send(cursor_id, "handover-cursor")
        cursor_state = self.wait("the active Cursor turn", lambda: self.provider_state("cursor"))
        cursor = process_info(cursor_state["pid"])
        self.assertEqual(cursor[1], self.runtime_identity.pid)
        self.remember(cursor[0], "cursor")

        self.set_stage("deferral")
        self.close_gui()  # 旧
        self.open_gui("new")
        deferred = self.wait_for_deferral(discovery)
        self.assertIn("端末セッション", deferred["updateStatus"], "The PTY was not a deferral reason")
        self.assertIn("未対応", deferred["updateStatus"], "The Cursor execution was not a deferral reason")
        self.assertEqual(deferred["pid"], self.runtime_identity.pid)
        self.assertIsNone(self.checkpoint(), "A deferred update wrote a checkpoint")
        pty_beat, codex_streamed = self.fake(pty[0].pid)["heartbeat"], len(self.fake(codex["child"].pid)["streamed"]["runtime-turn-1"])
        self.wait("PTY progress while deferred", lambda: self.fake(pty[0].pid)["heartbeat"] > pty_beat + 2)
        self.wait("Codex output while deferred",
                  lambda: len(self.fake(codex["child"].pid)["streamed"]["runtime-turn-1"]) > codex_streamed + 2)
        self.assertTrue(same_process(self.runtime_identity) and same_process(pty[0]) and same_process(cursor[0]))
        self.assert_same_children(codex, claude)
        self.assertEqual([q["requestId"] for q in self.pending_questions(codex_id)], [codex["question"]])
        self.assertEqual([q["requestId"] for q in self.pending_questions(claude_id)], [claude["question"]])
        self.observe("deferred-without-change", updateStatus=deferred["updateStatus"], generation=deferred["generation"])
        # 新の画面は開いたままだと30秒ごとに再要求するので、阻害要因を外す前に閉じる（以後、画面は開いていない）。
        self.close_gui()
        (Path(cursor_state["controlDirectory"]) / "turn-1.release").touch()
        self.wait("the Cursor turn to finish", lambda: not same_process(cursor[0]))
        for identifier in (cursor_id, pty_id):
            self.assertEqual(self.api.command({"removeSession": {"_0": identifier}}), {"bool": {"_0": True}})
        self.wait("the removed PTY child to exit", lambda: not same_process(pty[0]))

        # 切り替え前の同じ検査が通ることを先に確かめる（切り替え後の失敗を切り替えに帰属させる）。
        self.assert_control_check(claude, "control-check-before-handover")

        self.set_stage("handover")
        before = self.discovery()
        codex_counts = self.fake(codex["child"].pid)["methodCounts"]
        claude_counts = self.fake(claude["child"].pid)["methodCounts"]
        with socket.create_connection(("127.0.0.1", self.api.port), timeout=10) as pending:
            pending.settimeout(10)
            pending.sendall((
                "GET /sessions HTTP/1.1\r\nHost: 127.0.0.1\r\n"
                f"Authorization: Bearer {self.api._token}\r\n"
                f"X-Phlox-Runtime-Protocol: {self.api.protocol}\r\n"
                f"X-Phlox-Runtime-Generation: {self.api.generation}\r\n"
                "Connection: close\r\n"
            ).encode())
            time.sleep(0.25)  # 旧ホストが接続を受付け、ヘッダーの終わりを待つ。
            old_runtime = self.runtime_identity

            def finish_pending_request():
                self.wait("the old host to commit the handover", lambda: self.discovery()["state"] == "stopping")
                time.sleep(4.2)  # 旧実装の3秒の排水期限を越えても、受付済みの要求を切らない。
                self.assertTrue(same_process(old_runtime), "The old host exited before answering an accepted request")
                pending.sendall(b"\r\n")
                status = pending.recv(4096).split(b"\r\n", 1)[0]
                self.assertIn(b" 200 ", status, f"The accepted request did not complete: {status!r}")
                self.observe("accepted-control-request-drained", status=status.decode())

            new = self.request_handover(before, before_wait=finish_pending_request)

        self.set_stage("adopted")
        self.assert_same_children(codex, claude)
        self.assertIsNone(self.checkpoint(), "The checkpoint was not consumed")
        consumed = self.checkpoint("consumed.json")
        self.assertIsNotNone(consumed, "The consumed checkpoint is missing")
        self.assertEqual(consumed["sourceGeneration"].upper(), before["generation"].upper())
        self.assertEqual({item["sessionID"].upper() for item in consumed["sessions"]}, {uuid_text(codex_id), uuid_text(claude_id)})
        self.assertFalse([item for item in consumed["sessions"] if "token" in item],
                         "The consumed checkpoint still carries child tokens")
        stale = lifecycle.RuntimeAPI(self.store, dict(new, generation=before["generation"]), self.observe,
                                     self.capture_runtime_timeout)
        stale.request_once("POST", "/command", claude["operation"], accepted=(409,))
        self.assertEqual(sum(claude["text"] in marker for marker in self.fake(claude["child"].pid)["inputMarkers"]), 1,
                         "The pre-handover send was executed more than once")
        for counts, pid in ((codex_counts, codex["child"].pid), (claude_counts, claude["child"].pid)):
            after = self.fake(pid)["methodCounts"]
            for method in ("initialize", "thread/start", "thread/resume", "turn/start", "user"):
                self.assertEqual(after.get(method, 0), counts.get(method, 0), f"{method} was re-issued to PID {pid}")
        self.assertEqual(codex_counts.get("thread/resume", 0), 0)
        # 保存側のカードは再投入より先に戻るので、質問待ちの状態（再投入で戻る）も合わせて待つ。
        self.wait("the Codex question presented once and awaited",
                  lambda: [q["requestId"] for q in self.pending_questions(codex_id)] == [codex["question"]]
                  and self.chat(codex_id)["status"] == {"awaitingUserQuestion": {}})
        self.wait("the Claude approval presented once",
                  lambda: [q["requestId"] for q in self.pending_questions(claude_id)] == [claude["question"]])
        self.assertEqual(self.fake(codex["child"].pid)["questionReplies"], [])
        self.assertEqual(self.fake(claude["child"].pid)["approvalReplies"], [])
        mark = max(self.fake(codex["child"].pid)["streamed"]["runtime-turn-1"])
        self.wait("Codex output after the handover", lambda: max(self.stream_tokens(codex_id), default=0) > mark)
        self.assertEqual(self.chat(codex_id)["status"], {"awaitingUserQuestion": {}},
                         "The adopted Codex session left the question wait")
        self.assertEqual([q["requestId"] for q in self.pending_questions(codex_id)], [codex["question"]])
        check = self.assert_control_check(claude, "control-check-after-handover")
        self.observe("adopted-same-children", codexPID=codex["child"].pid, claudePID=claude["child"].pid,
                     outputMark=mark, controlStatus=check.get("status"))

        self.set_stage("answer-after-handover")
        completed = self.chat(codex_id)["completedTurnSeq"]
        self.answer_once(codex_id, {"question": dict(requestId=codex["question"], answers={"runtime-choice": ["Continue"]})},
                         lambda: self.fake(codex["child"].pid)["questionReplies"])
        self.assertEqual(self.fake(codex["child"].pid)["questionReplies"][0],
                         {"answers": {"runtime-choice": {"answers": ["Continue"]}}})
        self.wait("the Codex turn to complete", lambda: self.chat(codex_id)["completedTurnSeq"] > completed)
        expected = self.fake(codex["child"].pid)["streamed"]["runtime-turn-1"]
        observed = []

        def delivered():
            observed[:] = self.stream_tokens(codex_id)
            return observed == expected
        try:
            self.wait("every Codex output line exactly once", delivered, timeout=20)
        except AssertionError:
            (self.root / "logs/codex-stream.json").write_text(json.dumps(dict(expected=expected, observed=observed)))
            missing = sorted(set(expected) - set(observed))
            duplicated = sorted({value for value in observed if observed.count(value) > 1})
            raise AssertionError(f"Codex output differs across the handover: missing={missing[:20]} "
                                 f"duplicated={duplicated[:20]} extra={sorted(set(observed) - set(expected))[:20]}")
        self.assertTrue(min(expected) <= mark < max(expected), "The checked output does not span the handover")
        revision = self.chat(claude_id)["transcriptRevision"]
        completed = self.chat(claude_id)["completedTurnSeq"]
        self.answer_once(claude_id, {"question": dict(requestId=claude["question"], answers={claude["answerKey"]: ["Allow"]})},
                         lambda: self.fake(claude["child"].pid)["approvalReplies"])
        self.assertEqual(self.fake(claude["child"].pid)["duplicateReplies"], [])
        self.wait("Claude output after the approval", lambda: self.chat(claude_id)["transcriptRevision"] > revision)
        (claude["controls"] / "turn-1.release").touch()
        self.wait("the Claude turn to complete", lambda: self.chat(claude_id)["completedTurnSeq"] > completed)
        self.observe("answered-once-after-handover", codexQuestion=codex["question"], claudeApproval=claude["question"],
                     codexOutputLines=len(expected))

        self.set_stage("send-after-handover")
        self.send(codex_id, "after-handover-codex")
        self.wait("the next Codex turn at the same child", lambda: self.fake(codex["child"].pid)["methodCounts"].get(
            "turn/start", 0) == codex_counts.get("turn/start", 0) + 1)
        self.wait("the next Codex turn's approval", lambda: self.chat(codex_id)["pendingApprovals"])
        claude_pids = self.provider_pids("claudeCode")
        self.send(claude_id, "after-handover-claude")
        self.wait("the next Claude turn at the same child", lambda: any(
            "after-handover-claude" in marker for marker in self.fake(claude["child"].pid)["inputMarkers"]))
        self.assertEqual(self.provider_pids("claudeCode"), claude_pids, "Sending after the handover started a new Claude CLI")
        self.assert_same_children(codex, claude)
        self.assertEqual(self.fake(codex["child"].pid).get("unexpectedReplies", []), [],
                         "The Codex child received a reply to an answered or unknown request")

        self.set_stage("new-chat")
        fresh_id = self.spawn_chat("codex")
        fresh = self.held_child(fresh_id)  # 新ホストと同じ実行ファイルのholderで、親が新ホスト
        self.send(fresh_id, "new-chat-after-handover")
        self.wait("the new chat's turn", lambda: self.fake(fresh["child"].pid)["methodCounts"].get("turn/start") == 1)
        self.observe("new-chat-on-new-runtime", pid=fresh["child"].pid, holderPID=fresh["holder"].pid,
                     holderExecutable=fresh["holder"].executable, runtimePID=self.runtime_identity.pid)

    def run_adoption_failure(self):
        # 画面の流れ: 旧を開く → 実行を始める → ソケットを塞ぐ → 旧を閉じ新を開く（切り替え。以後は新が開いたまま）。
        self.start_runtime()
        self.set_stage("start-executions")
        codex_id, claude_id = self.spawn_chat("codex"), self.spawn_chat("claudeCode")
        codex = self.start_codex_turn(codex_id, answer_approval=False)
        claude = self.start_claude_turn(claude_id)

        self.set_stage("block-claude-holder")
        socket = claude["record"]["socketPath"]  # 自分のストアのholder.jsonが指すものだけ
        info = os.lstat(socket)
        self.assertTrue(stat.S_ISSOCK(info.st_mode) and info.st_uid == os.getuid(), "Unexpected holder socket")
        self.blocked_sockets[socket] = stat.S_IMODE(info.st_mode)
        os.chmod(socket, 0)
        self.observe("holder-socket-blocked", socket=socket, originalMode=oct(self.blocked_sockets[socket]),
                     holderPID=claude["holder"].pid)

        self.set_stage("handover")
        before = self.discovery()
        self.close_gui()  # 旧
        self.request_handover(before)

        self.set_stage("recovery-needed")
        self.assert_same_children(codex, claude)
        restore = self.wait("the published recovery state", lambda: (lambda value: value if RECOVERY in json.dumps(
            value, ensure_ascii=False) else None)(self.chat(claude_id).get("restoreState")))
        remaining = self.checkpoint()
        self.assertIsNotNone(remaining, "The checkpoint item of the failed adoption was consumed")
        self.assertEqual([item["sessionID"].upper() for item in remaining["sessions"]], [uuid_text(claude_id)],
                         "Only the failed session must remain in the checkpoint")
        # 再試行の採用で子のトークンを再登録するため、残る項目はトークンを保つ（値は出さない）。
        self.assertTrue(remaining["sessions"][0].get("token"), "The remaining checkpoint item lost the child token")
        self.wait("the Codex approval presented once", lambda: len(self.chat(codex_id)["pendingApprovals"]) == 1)
        self.assertEqual(self.fake(codex["child"].pid)["approvalReplies"], [])
        send_status = self.assert_rejected_without_new_cli(claude_id, claude, self.session_command(
            self.chat(claude_id), {"send": dict(text="send-while-recovery-needed", submit=True, attachments=[])}), True)
        resume_status = self.assert_rejected_without_new_cli(claude_id, claude, {"resumeChat": {"_0": claude_id}}, False)
        self.observe("recovery-needed-kept-alive", claudePID=claude["child"].pid, holderPID=claude["holder"].pid,
                     restoreState=restore, sendStatus=send_status, resumeStatus=resume_status,
                     remainingSessions=[item["sessionID"] for item in remaining["sessions"]])

    # MARK: - 後片付けと診断

    def adopt_store_processes_for_cleanup(self):
        """holderはsetsid済みで旧ホストの終了後も残る。自分のストアが指すプロセスを、照合してから後片付けの対象に加える。"""
        for socket, mode in self.blocked_sockets.items():
            try:
                os.chmod(socket, mode)
                self.observe("holder-socket-restored", socket=socket, mode=oct(mode))
            except OSError as error:
                self.observe("holder-socket-restore-failed", socket=socket, errorType=type(error).__name__)
        cache = self.store / "session-runtime-bundles"
        candidates = []
        try:
            candidates.append((self.discovery()["pid"], True))
        except (OSError, ValueError, KeyError, AssertionError):
            pass
        for record in self.holder_records():
            candidates += [(record.get("holderPID"), True), (record.get("childPID"), False)]
        for path in (self.root / "fake-state").glob("*.json"):
            try:
                candidates.append((json.loads(path.read_text())["pid"], False))
            except (OSError, ValueError, KeyError):
                continue
        for pid, from_cache in candidates:
            if not isinstance(pid, int) or pid <= 1 or pid in self.owned:
                continue
            info = process_info(pid)
            if info is None or info[0].start_seconds + 1 < self.started_at:
                continue  # PIDの再利用（このテストより前に始まったプロセス）には触れない
            if from_cache and not Path(info[0].executable).is_relative_to(cache):
                continue
            self.remember(info[0], "store-owned")

    def write_diagnostics(self):
        result = dict(stage=self.stage, recordedAtUnix=time.time(), gui=None if self.gui is None else dict(
            pid=self.gui["identity"].pid, build=self.gui["build"], alive=same_process(self.gui["identity"]),
            bundleVersion=self.old_build if self.gui["build"] == "old" else getattr(self, "new_build", None)))
        for key, read in (("discovery", self.discovery), ("holders", self.holder_records),
                          ("checkpoint", self.checkpoint), ("consumed", lambda: self.checkpoint("consumed.json"))):
            try:
                value = read()
                if key in ("checkpoint", "consumed") and value:
                    value = dict(sourceGeneration=value.get("sourceGeneration"), sessions=[dict(
                        sessionID=item["sessionID"], agent=item["agent"], appliedSeq=item["appliedSeq"],
                        holderPID=item["holder"]["holderPID"], childPID=item["holder"]["childPID"]) for item in value["sessions"]])
                result[key] = value
            except Exception as error:  # 診断の失敗で元の失敗を隠さない
                result[key] = dict(error=type(error).__name__)
        fakes = {}
        for path in (self.root / "fake-state").glob("*.json"):
            try:
                state = json.loads(path.read_text())
                fakes[path.stem] = dict({key: state.get(key) for key in (
                    "provider", "role", "parent", "phase", "active", "turn", "heartbeat", "methodCounts", "inputMarkers",
                    "approvalReplies", "questionReplies", "duplicateReplies", "controlChecks", "exitCode")},
                    alive=process_info(state["pid"]) is not None)
            except (OSError, ValueError, KeyError):
                continue
        result["fakes"] = fakes
        try:
            result["sessions"] = [dict(kind=kind, id=value["id"], status=value.get("status"),
                restoreState=value.get("restoreState"), sendFailure=value.get("sendFailure"),
                pendingApprovals=len(value.get("pendingApprovals", [])), completedTurnSeq=value.get("completedTurnSeq"),
                pendingQuestions=[item["userQuestion"]["requestId"] for item in value.get("transcript", [])
                                  if item.get("userQuestion", {}).get("state") == "pending"])
                for session in self.api.snapshot()["sessions"] for kind, wrapped in session.items()
                for value in [wrapped["_0"]]]
        except Exception as error:
            result["sessions"] = dict(error=type(error).__name__)
        (self.root / "logs/handover-diagnostics.json").write_text(json.dumps(result, ensure_ascii=False, indent=2, default=str))


def parse_options():
    options, remaining = lifecycle.parse_options()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update-app", type=Path, required=True)
    parser.add_argument("--scenario", choices=["planned", "adoption-failure"], required=True)
    extra, remaining = parser.parse_known_args(remaining)
    extra.update_app = extra.update_app.resolve()
    verification = (lifecycle.PROJECT / ".verification").resolve()
    if not extra.update_app.is_relative_to(verification) or not (extra.update_app / "Contents/Info.plist").is_file():
        parser.error("--update-app must be a built .app inside this worktree's .verification directory")
    if extra.update_app == options.app or any(a.is_relative_to(b) for a, b in (
            (extra.update_app, options.work_dir), (options.work_dir, extra.update_app))):
        parser.error("--update-app must be a separate build outside --work-dir")
    options.include_additional_structured = True  # Claude・Cursor をストリーム JSON のフェイクで動かす
    return options, extra, remaining


if __name__ == "__main__":
    lifecycle.OPTIONS, HANDOVER, unittest_arguments = parse_options()
    output = io.StringIO()
    program = unittest.main(argv=[sys.argv[0]] + unittest_arguments, exit=False,
                            testRunner=unittest.TextTestRunner(stream=output, verbosity=2))
    sys.stderr.write(output.getvalue())
    if (lifecycle.OPTIONS.work_dir / "logs").is_dir():
        (lifecycle.OPTIONS.work_dir / "logs/test-result.log").write_text(output.getvalue())
    sys.exit(0 if program.result.wasSuccessful() else 1)
