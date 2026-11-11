#!/usr/bin/env python3
"""隔離アプリで長いカード、入力履歴、直接ジャンプ、タスク変更後の本文復旧を検査する。

compact-test経由で固有bundle IDの --app と新しい --work-dir を指定する。
--self-check は合成履歴の前提だけを確認し、製品の成功とは扱わない。
--content-recovery-only は本文復旧だけを検査し、出力は --work-dir/content-recovery に置く。
"""
import base64
import ctypes
import hashlib
import http.client
import http.server
import importlib.util
import io
import json
import os
from pathlib import Path
import shlex
import stat
import subprocess
import sys
import threading
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

FIXTURE_GRID_TILE_IDS = frozenset("grid-tile-" + value["rawValue"] for value in [SESSION_ID] + GRID_IDS)
RUNNING_GRID_TILE_IDS = frozenset("grid-tile-" + value["rawValue"] for value in GRID_IDS)
RECOVERY_TITLE = "Content recovery acceptance"
RECOVERY_OLD_TASK = "Inspect recovery original task"
RECOVERY_NEW_TASK = "Inspect recovery renamed task"


def fake_content_recovery(root, arguments):
    if ".verification" not in root.parts or not (root / "ownership.json").is_file():
        raise AssertionError("Fixture requires its owned verification directory")
    if "app-server" not in arguments:
        return long_message.fake_codex(root, arguments)
    fixture = importlib.util.spec_from_file_location("content_recovery_agent",
        Path(__file__).with_name("session-runtime-large-history-fake-agent.py"))
    module = importlib.util.module_from_spec(fixture)
    fixture.loader.exec_module(module)
    module.HISTORY_ITEMS = 0

    class RecoveryAgent(module.LargeHistoryAgent):
        def plan(self, title):
            self.notify("turn/plan/updated", dict(threadId=self.thread_id, turnId=self.turn_id,
                explanation=None, plan=[] if title is None else [dict(step=title, status="inProgress")]))

        def output(self, number):
            self.notify("item/completed", dict(threadId=self.thread_id, turnId=self.turn_id,
                item=dict(type="commandExecution", id=f"recovery-work-{number}", status="completed",
                    command=f"printf recovery-work-{number}", aggregatedOutput=f"Recovery output {number}",
                    cwd=str(root / "project"))))
            super().emit_item(f"recovery-answer-{number}", f"Recovery response {number}")

        def emit_item(self, identifier, text):
            self.plan(RECOVERY_OLD_TASK)
            self.output(0)
            self.state["recoveryTransition"] = 0
            self.save()
            self.transitions = threading.Thread(target=self.advance, daemon=True)
            self.transitions.start()

        def advance(self):
            for number, title in ((1, RECOVERY_NEW_TASK), (2, RECOVERY_NEW_TASK), (3, None), (4, None)):
                while not (root / f"recovery-trigger-{number}").is_file():
                    if not self.running:
                        return
                    threading.Event().wait(0.05)
                if number in (1, 3):
                    self.plan(title)
                self.output(number)
                with self.lock:
                    self.state["recoveryTransition"] = number
                    self.save()

        def structured(self):
            try:
                super().structured()
            finally:
                self.running = False
                if hasattr(self, "transitions"):
                    self.transitions.join(timeout=2)

    agent = RecoveryAgent(root, "codex", "structured")
    agent.thread_id = "synthetic-" + os.environ["PHLOX_SESSION_ID"]
    agent.structured()


class AXPair(ctypes.Structure):
    _fields_ = [("first", ctypes.c_double), ("second", ctypes.c_double)]


def balanced_grid_state():
    identifiers = [SESSION_ID] + GRID_IDS
    rows = [dict(kind="split", id=f"semantic-row-{row}", axis="horizontal",
        children=[dict(kind="leaf", id=f"semantic-leaf-{index}", session=identifiers[index])
            for index in range(row * 3, row * 3 + 3)], weights=[1 / 3] * 3) for row in range(3)]
    tree = dict(schemaVersion=1, root=dict(kind="split", id="semantic-grid-root", axis="vertical",
        children=rows, weights=[1 / 3] * 3))
    return dict(schemaVersion=1, state=dict(custom={"_0": dict(tree=tree,
        presetState=dict(preset="balanced", isAdjusted=False), canvasMinimum=[0, 0])}))


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


class SemanticContentAPI(lifecycle.RuntimeAPI):
    def __init__(self, api, session, target, maximum_bytes):
        self.api = api
        self.observe = api.observe
        self.backpressure_counts = api.backpressure_counts
        self.target = next(iter(target))
        self.maximum_bytes = maximum_bytes
        self.attempts = 0
        self.response_bytes = 0
        payload = dict(sessionID=session["id"], executionID=session["executionID"], target=target)
        encoded = base64.b64encode(json.dumps(payload, separators=(",", ":")).encode()).decode()
        self.headers = {"Authorization": "Bearer " + api._token,
            "X-Phlox-Runtime-Protocol": str(api.protocol),
            "X-Phlox-Runtime-Generation": api.generation,
            "X-Phlox-Runtime-Content-Request": encoded}

    def request_once(self, method, path, payload=None, accepted=(200,)):
        self.attempts += 1
        connection = http.client.HTTPConnection("127.0.0.1", self.api.port, timeout=20)
        started, requested_at = time.monotonic(), time.time()
        try:
            connection.request(method, path, headers=self.headers)
            response = connection.getresponse()
            limit = self.maximum_bytes if response.status == 200 else 8192
            body = response.read(limit + 1)
            self.response_bytes = len(body)
            failure_body = None if response.status == 200 else body[:8192].decode(errors="replace").replace(
                self.api._token, "[redacted]")
            self.observe("semantic-content-http-attempt", target=self.target, method=method, path=path,
                attempt=self.attempts, status=response.status, bytes=len(body), bodyTruncated=len(body) > limit,
                errorBody=failure_body, requestedAtUnix=requested_at, seconds=time.monotonic() - started,
                retryDeadlineSeconds=5, socketTimeoutSeconds=20)
            if len(body) > limit:
                raise AssertionError("Semantic content exceeded its encoded byte limit")
            try:
                value = json.loads(body)
            except (ValueError, UnicodeDecodeError):
                raise AssertionError(f"Semantic content returned non-JSON HTTP {response.status}") from None
            if response.status == 503 and value != {"message": "実行サービスの操作数が上限に達しています。"}:
                raise AssertionError("Semantic content returned an unrecognized HTTP 503 response")
            if response.status not in accepted:
                raise AssertionError(f"Semantic content returned HTTP {response.status}")
            return response.status, value
        except TimeoutError:
            self.observe("semantic-content-http-timeout", target=self.target, attempt=self.attempts,
                requestedAtUnix=requested_at, seconds=time.monotonic() - started)
            self.api.on_timeout()
            raise
        finally:
            connection.close()


def read_content(api, session, target, *, maximum_bytes=MAX_RESPONSE_BYTES):
    reader = SemanticContentAPI(api, session, target, maximum_bytes)
    started, requested_at = time.monotonic(), time.time()
    try:
        _, value = reader.request("GET", "/session-content")
    except (AssertionError, OSError):
        api.observe("semantic-content-http-failed", target=reader.target, attempts=reader.attempts,
            requestedAtUnix=requested_at, seconds=time.monotonic() - started, retryDeadlineSeconds=5)
        raise
    return value, dict(bytes=reader.response_bytes, seconds=time.monotonic() - started,
        requestedAtUnix=requested_at, attempts=reader.attempts)


def native_ax_probe(identity, identifier=None, *, prefix=False, role=None, label=None, scope_identifier=None, press=False, draft=None, include_nodes=False, window_frame=None):
    probe_scope = "ownedWindow" if window_frame is not None else "fullTree"
    if not lifecycle.same_process(identity):
        return dict(targetExited=True, complete=False, count=0, probeScope=probe_scope, treeScanned=False)
    ax = ctypes.CDLL("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")
    cf = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
    ax.AXUIElementCreateApplication.argtypes = [ctypes.c_int32]
    ax.AXUIElementCreateApplication.restype = ctypes.c_void_p
    ax.AXUIElementSetMessagingTimeout.argtypes = [ctypes.c_void_p, ctypes.c_float]
    ax.AXUIElementCopyAttributeValue.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_void_p)]
    ax.AXUIElementIsAttributeSettable.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.POINTER(ctypes.c_bool)]
    ax.AXUIElementSetAttributeValue.argtypes = [ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p]
    ax.AXUIElementPerformAction.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    ax.AXValueCreate.argtypes = [ctypes.c_uint32, ctypes.c_void_p]
    ax.AXValueCreate.restype = ctypes.c_void_p
    ax.AXValueGetValue.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_void_p]
    ax.AXValueGetValue.restype = ctypes.c_bool
    cf.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
    cf.CFStringCreateWithCString.restype = ctypes.c_void_p
    cf.CFArrayGetCount.argtypes = [ctypes.c_void_p]
    cf.CFArrayGetCount.restype = ctypes.c_long
    cf.CFArrayGetValueAtIndex.argtypes = [ctypes.c_void_p, ctypes.c_long]
    cf.CFArrayGetValueAtIndex.restype = ctypes.c_void_p
    cf.CFGetTypeID.argtypes = [ctypes.c_void_p]
    cf.CFGetTypeID.restype = ctypes.c_ulong
    cf.CFStringGetTypeID.restype = ctypes.c_ulong
    cf.CFNumberGetTypeID.restype = ctypes.c_ulong
    cf.CFNumberGetValue.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
    cf.CFNumberGetValue.restype = ctypes.c_bool
    cf.CFArrayGetTypeID.restype = ctypes.c_ulong
    cf.CFStringGetCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.c_uint32]
    cf.CFStringGetCString.restype = ctypes.c_bool
    cf.CFEqual.argtypes = [ctypes.c_void_p, ctypes.c_void_p]
    cf.CFEqual.restype = ctypes.c_bool
    cf.CFRetain.argtypes = [ctypes.c_void_p]
    cf.CFRetain.restype = ctypes.c_void_p
    cf.CFRelease.argtypes = [ctypes.c_void_p]
    keys = {name: cf.CFStringCreateWithCString(None, name.encode(), 0x08000100)
        for name in ("AXWindows", "AXChildren", "AXIdentifier", "AXValue", "AXRole", "AXTitle", "AXDescription", "AXPress", "AXPosition", "AXSize", "AXVerticalScrollBar")}
    app = ax.AXUIElementCreateApplication(identity.pid)
    retained, visited, matches, editors = [], set(), [], []
    grid_ids_seen, match_owners = set(), set()
    node_context = {app: dict(role="AXApplication")}
    result = dict(complete=True, count=0, gridTileCount=0, gridTileRawCount=0, unownedMatchCount=0, windowCount=0, windowFrames=[], gridTileFrames=[], errors=[])
    result.update(probeScope=probe_scope, treeScanned=False)
    if include_nodes:
        result["nodes"] = []
        result["scrollAreas"] = []
    deadline = time.monotonic() + 10

    def attribute(element, name):
        value = ctypes.c_void_p()
        status = ax.AXUIElementCopyAttributeValue(element, keys[name], ctypes.byref(value))
        if status not in (0, -25205, -25212):
            result["complete"] = False
            result["errors"].append(dict(attribute=name, status=status, **node_context.get(element, {})))
        return value

    def string(value):
        if not value or cf.CFGetTypeID(value) != cf.CFStringGetTypeID():
            return None
        buffer = ctypes.create_string_buffer(32768)
        return buffer.value.decode("utf-8") if cf.CFStringGetCString(value, buffer, len(buffer), 0x08000100) else None

    def geometry(element):
        pairs = []
        for name, kind in (("AXPosition", 1), ("AXSize", 2)):
            value = attribute(element, name)
            pair = AXPair()
            try:
                if not value or not ax.AXValueGetValue(value, kind, ctypes.byref(pair)):
                    result["complete"] = False
                    result["errors"].append(dict(attribute=name, reason="Missing AX geometry", **node_context.get(element, {})))
                    return None
                pairs.extend([pair.first, pair.second])
            finally:
                if value: cf.CFRelease(value)
        return dict(x=pairs[0], y=pairs[1], width=pairs[2], height=pairs[3])

    def visit(element, within_scope=False, owner_tile_id=None, scroll_ancestor=None):
        if element in visited:
            return
        if len(visited) >= 10000 or time.monotonic() >= deadline:
            result["complete"] = False
            result["limitReached"] = True
            return
        visited.add(element)
        retained.append(cf.CFRetain(element))
        context = dict(nodeIndex=len(visited) - 1)
        node_context[element] = context
        fields = {}
        value = attribute(element, "AXIdentifier")
        try:
            fields["AXIdentifier"] = string(value)
        finally:
            if value: cf.CFRelease(value)
        found = fields["AXIdentifier"]
        if found: context["identifier"] = found[:512]
        if found and found.startswith("grid-tile-"):
            owner_tile_id = found
            result["gridTileRawCount"] += 1
            if found not in grid_ids_seen:
                grid_ids_seen.add(found)
                result["gridTileCount"] += 1
                result["gridTileFrames"].append(dict(identifier=found, frame=geometry(element),
                    scrollAreaNodeIndex=scroll_ancestor))
        if owner_tile_id: context["ownerTileID"] = owner_tile_id
        within_scope = within_scope or scope_identifier is None or found == scope_identifier
        if include_nodes or (label is not None and within_scope):
            value = attribute(element, "AXRole")
            try:
                fields["AXRole"] = string(value)
            finally:
                if value: cf.CFRelease(value)
            if fields.get("AXRole"): context["role"] = fields["AXRole"]
        if include_nodes or (label is not None and within_scope and fields.get("AXRole") == role):
            for name in ("AXTitle", "AXDescription", "AXValue"):
                value = attribute(element, name)
                try:
                    fields[name] = string(value)
                finally:
                    if value: cf.CFRelease(value)
        if include_nodes and fields.get("AXRole") == "AXScrollArea":
            scroll_ancestor = context["nodeIndex"]
            area = dict(nodeIndex=scroll_ancestor, frame=geometry(element))
            scrollbar = attribute(element, "AXVerticalScrollBar")
            try:
                if scrollbar:
                    value = attribute(scrollbar.value, "AXValue")
                    try:
                        scalar = ctypes.c_double()
                        if value and cf.CFGetTypeID(value) == cf.CFNumberGetTypeID() and cf.CFNumberGetValue(value, 13, ctypes.byref(scalar)):
                            area["verticalScrollBarValue"] = scalar.value
                        else:
                            area["verticalScrollBarValue"] = string(value)
                    finally:
                        if value: cf.CFRelease(value)
            finally:
                if scrollbar: cf.CFRelease(scrollbar)
            result["scrollAreas"].append(area)
        identifier_matches = identifier is not None and found and (found.startswith(identifier) if prefix else found == identifier)
        label_matches = within_scope and label is not None and fields.get("AXRole") == role and label in (
            fields.get("AXTitle"), fields.get("AXDescription"), fields.get("AXValue"))
        if identifier_matches or label_matches:
            matches.append(element)
            if owner_tile_id:
                match_owners.add(owner_tile_id)
            else:
                result["unownedMatchCount"] += 1
            if label is not None:
                result.setdefault("matchedElements", []).append({key: value[:512] for key, value in fields.items() if value is not None})
        if include_nodes and within_scope:
            node = {key: value[:512] for key, value in fields.items() if value is not None}
            if owner_tile_id: node["ownerTileID"] = owner_tile_id
            if scroll_ancestor is not None: node["scrollAreaNodeIndex"] = scroll_ancestor
            result["nodes"].append(node)
        value = attribute(element, "AXChildren")
        try:
            if value and cf.CFGetTypeID(value) == cf.CFArrayGetTypeID():
                for index in range(cf.CFArrayGetCount(value)):
                    visit(cf.CFArrayGetValueAtIndex(value, index), within_scope, owner_tile_id, scroll_ancestor)
        finally:
            if value: cf.CFRelease(value)

    editable_visited = set()
    def find_editors(element):
        if element in editable_visited:
            return
        if len(editable_visited) >= 10000 or time.monotonic() >= deadline:
            result["complete"] = False
            result["limitReached"] = True
            return
        editable_visited.add(element)
        value = attribute(element, "AXRole")
        try:
            editor_role = string(value)
        finally:
            if value: cf.CFRelease(value)
        if editor_role == "AXTextArea":
            node_context.setdefault(element, {})["role"] = editor_role
            settable = ctypes.c_bool()
            status = ax.AXUIElementIsAttributeSettable(element, keys["AXValue"], ctypes.byref(settable))
            if status not in (0, -25205, -25212):
                result["complete"] = False
                result["errors"].append(dict(attribute="AXValue(settable)", status=status,
                    **node_context.get(element, {})))
            if status == 0 and settable.value and not any(cf.CFEqual(element, editor) for editor in editors):
                editors.append(cf.CFRetain(element))
        value = attribute(element, "AXChildren")
        try:
            if value and cf.CFGetTypeID(value) == cf.CFArrayGetTypeID():
                for index in range(cf.CFArrayGetCount(value)):
                    find_editors(cf.CFArrayGetValueAtIndex(value, index))
        finally:
            if value: cf.CFRelease(value)

    started = time.monotonic()
    try:
        result["timeoutStatus"] = ax.AXUIElementSetMessagingTimeout(app, ctypes.c_float(1))
        windows = attribute(app, "AXWindows")
        try:
            if windows and cf.CFGetTypeID(windows) == cf.CFArrayGetTypeID():
                result["windowCount"] = cf.CFArrayGetCount(windows)
                if window_frame is not None and result["windowCount"] == 1 and lifecycle.same_process(identity):
                    window = cf.CFArrayGetValueAtIndex(windows, 0)
                    value = attribute(window, "AXRole")
                    try:
                        result["windowRole"] = string(value)
                    finally:
                        if value: cf.CFRelease(value)
                    if result["windowRole"] != "AXWindow":
                        result["complete"] = False
                        result["errors"].append(dict(attribute="AXRole", reason="The owned target is not an AXWindow"))
                    result["previousWindowFrame"] = geometry(window)
                    result["windowResizeStatus"] = {}
                    if result["complete"]:
                        for name, kind, values in (("AXSize", 2, window_frame[2:]), ("AXPosition", 1, window_frame[:2])):
                            pair = AXPair(*values)
                            value = ax.AXValueCreate(kind, ctypes.byref(pair))
                            try:
                                result["windowResizeStatus"][name] = ax.AXUIElementSetAttributeValue(window, keys[name], value)
                            finally:
                                if value: cf.CFRelease(value)
                for index in range(result["windowCount"]):
                    window = cf.CFArrayGetValueAtIndex(windows, index)
                    result["windowFrames"].append(geometry(window))
                    if window_frame is None:
                        result["treeScanned"] = True
                        visit(window)
        finally:
            if windows: cf.CFRelease(windows)
        if window_frame is not None and (result["windowCount"] != 1 or result.get("windowRole") != "AXWindow"):
            result["complete"] = False
            result["errors"].append(dict(reason="Resize requires exactly one owned AXWindow"))
        result.update(count=len(matches), rawNodeCount=len(matches), matchedOwnerTileCount=len(match_owners),
            nodesRead=len(visited), gridTileIDs=sorted(grid_ids_seen),
            matchedOwnerTileIDs=sorted(match_owners))
        frames = [tile["frame"] for tile in result["gridTileFrames"] if tile["frame"]]
        result["visibleGridTileCount"] = sum(1 for frame in frames if frame["width"] >= 240 and frame["height"] >= 160
            and any(window and frame["x"] >= window["x"] - 1 and frame["y"] >= window["y"] - 1
                and frame["x"] + frame["width"] <= window["x"] + window["width"] + 1
                and frame["y"] + frame["height"] <= window["y"] + window["height"] + 1
                for window in result["windowFrames"]))
        result["gridTilesOverlap"] = any(min(a["x"] + a["width"], b["x"] + b["width"]) - max(a["x"], b["x"]) > 1
            and min(a["y"] + a["height"], b["y"] + b["height"]) - max(a["y"], b["y"]) > 1
            for index, a in enumerate(frames) for b in frames[index + 1:])
        if press and len(matches) == 1 and result["complete"] and lifecycle.same_process(identity):
            result["actionStatus"] = ax.AXUIElementPerformAction(matches[0], keys["AXPress"])
        if draft is not None:
            for scope in matches:
                find_editors(scope)
            result["actualEditorCount"] = len(editors)
            if result["complete"] and result["windowCount"] > 0 and len(editors) == 1 and lifecycle.same_process(identity):
                target = editors[0]
                original = attribute(target, "AXValue")
                try:
                    result["editorValueReadable"] = string(original) is not None
                    if result["complete"] and result["editorValueReadable"]:
                        replacement = cf.CFStringCreateWithCString(None, draft.encode(), 0x08000100)
                        try:
                            result["mutationAttempted"] = True
                            result["setStatus"] = ax.AXUIElementSetAttributeValue(target, keys["AXValue"], replacement)
                            observed = attribute(target, "AXValue")
                            try:
                                result["observed"] = string(observed)
                            finally:
                                if observed: cf.CFRelease(observed)
                        finally:
                            result["restoreStatus"] = ax.AXUIElementSetAttributeValue(target, keys["AXValue"], original)
                            cf.CFRelease(replacement)
                finally:
                    if original: cf.CFRelease(original)
        result["seconds"] = time.monotonic() - started
        return result
    finally:
        for editor in editors: cf.CFRelease(editor)
        for element in retained: cf.CFRelease(element)
        for key in keys.values(): cf.CFRelease(key)
        cf.CFRelease(app)


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
        self.seeded_defaults_suite = self.environment["PHLOX_DEFAULTS_SUITE"]
        self.assertEqual(self.seeded_defaults_suite, "com.phlox.lifecycle." + self.run_id)
        preferences = [Path.home() / "Library/Preferences" / (self.seeded_defaults_suite + ".plist"),
            self.root / "home/Library/Preferences" / (self.seeded_defaults_suite + ".plist")]
        self.seeded_preference_paths = preferences
        self.report["externalPreferencePaths"] = [str(path) for path in preferences]
        layout = json.dumps(balanced_grid_state(), separators=(",", ":")).encode()
        result = self.run_helper(["/usr/bin/defaults", "write", self.seeded_defaults_suite,
            "phlox.grid.layoutState", "-data", layout.hex()], timeout=10, environment=self.environment)
        self.assertEqual(result.returncode, 0, "The owned balanced grid fixture could not be configured")
        self.observe("semantic-owned-grid-layout-seeded", suite=self.seeded_defaults_suite,
            storeKey="phlox.grid.layoutState", preset="balanced", canvasMinimum=[0, 0], leafCount=9)
        self.native_gui_identity = None
        self.native_passed = False
        self.addCleanup(self.capture_native_failure)

    def cleanup_owned_processes(self):
        try:
            super().cleanup_owned_processes()
        finally:
            suite = getattr(self, "seeded_defaults_suite", None)
            if suite and not any(lifecycle.same_process(identity) for identity in self.owned.values()):
                self.assertEqual(suite, "com.phlox.lifecycle." + self.run_id)
                result = self.run_helper(["/usr/bin/defaults", "delete", suite], timeout=10, environment=self.environment)
                self.observe("semantic-owned-defaults-cleanup", suite=suite, exitCode=result.returncode,
                    paths=[str(path) for path in self.seeded_preference_paths])
                self.assertEqual(result.returncode, 0, "The owned preferences suite was not removed")
                for path in self.seeded_preference_paths:
                    self.assertEqual(path.name, suite + ".plist")
                    try:
                        info = path.lstat()
                    except FileNotFoundError:
                        continue
                    self.assertFalse(stat.S_ISLNK(info.st_mode), "An owned preference path became a symlink")
                    self.assertTrue(stat.S_ISREG(info.st_mode))
                    self.assertEqual(info.st_uid, os.getuid())
                    self.assertIn(path.parent.resolve(), (
                        (Path.home() / "Library/Preferences").resolve(),
                        (self.root / "home/Library/Preferences").resolve()))
                    removed = self.run_helper(["/usr/bin/trash", str(path)], timeout=10)
                    self.observe("semantic-owned-preference-file-cleanup", method="Trash",
                        path=str(path), uid=info.st_uid, exitCode=removed.returncode,
                        existsAfter=path.exists() or path.is_symlink())
                    self.assertTrue(removed.returncode == 0 or not (path.exists() or path.is_symlink()),
                        "The owned preference file was not moved to Trash")
                lifecycle.eventually("the owned preference files to be removed",
                    lambda: not any(path.exists() or path.is_symlink() for path in self.seeded_preference_paths), timeout=10)

    def capture_native_failure(self):
        identity = self.native_gui_identity
        if self.native_passed or identity is None or not lifecycle.same_process(identity):
            return
        try:
            self.screenshot(identity, "semantic-failure-" + str(identity.pid))
        except (OSError, AssertionError, RuntimeError) as error:
            self.observe("semantic-failure-capture-error", kind="window", error=str(error))
        try:
            diagnostics = native_ax_probe(identity, include_nodes=True)
            path = self.root / "logs" / ("semantic-failure-ax-" + str(identity.pid) + ".json")
            path.write_text(json.dumps(diagnostics, ensure_ascii=False, indent=2))
            self.observe("semantic-failure-ax-capture", path=str(path), guiPID=identity.pid)
        except (OSError, AssertionError, RuntimeError) as error:
            self.observe("semantic-failure-capture-error", kind="accessibility", error=str(error))

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

    def assert_native_button(self, identity, label, *, scope_identifier=None):
        latest = {}
        def present():
            nonlocal latest
            latest = native_ax_probe(identity, role="AXButton", label=label, scope_identifier=scope_identifier)
            return latest["complete"] and latest.get("windowCount", 0) > 0 and latest["count"] == 1
        try:
            lifecycle.eventually("the expected native button role and label", present, timeout=20)
        finally:
            self.observe("semantic-native-button", role="AXButton", label=label, **latest)

    def press_native_button(self, identity, label, *, scope_identifier):
        self.assert_native_button(identity, label, scope_identifier=scope_identifier)
        result = native_ax_probe(identity, role="AXButton", label=label,
            scope_identifier=scope_identifier, press=True)
        self.observe("semantic-native-button-action", label=label, scopeIdentifier=scope_identifier, observedAtUnix=time.time(), **result)
        self.assertTrue(result["complete"])
        self.assertEqual(result["count"], 1)
        self.assertEqual(result.get("actionStatus"), 0)

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
            and window.get("kCGWindowBounds", {}).get("Width", 0) > 500
            and window.get("kCGWindowBounds", {}).get("Height", 0) > 300]
        self.assertTrue(windows, "The isolated native main window is missing")
        window = max(windows, key=lambda value: value["kCGWindowBounds"]["Width"] * value["kCGWindowBounds"]["Height"])
        path = self.root / "logs" / (name + ".png")
        result = self.run_helper(["/usr/sbin/screencapture", "-x", "-o", "-l" +
            str(window["kCGWindowNumber"]), str(path)], timeout=15)
        bounds = dict(window["kCGWindowBounds"])
        self.observe("semantic-native-window-capture", path=str(path), guiPID=identity.pid,
            windowID=window["kCGWindowNumber"], bounds=bounds, exitCode=result.returncode,
            stderr=result.stderr.decode(errors="replace")[:4096])
        self.assertEqual(result.returncode, 0, "Native window capture failed")
        info = self.run_helper(["/usr/bin/sips", "-g", "pixelWidth", "-g", "pixelHeight", str(path)], timeout=15)
        self.assertEqual(info.returncode, 0, "Native window PNG dimensions could not be read")
        dimensions = {}
        for line in info.stdout.decode().splitlines():
            key, _, value = line.strip().partition(":")
            if key in ("pixelWidth", "pixelHeight"):
                dimensions[key] = int(value.strip())
        self.observe("semantic-native-screenshot", path=str(path), guiPID=identity.pid,
            windowID=window["kCGWindowNumber"], bounds=bounds, **dimensions)
        self.assertGreaterEqual(dimensions.get("pixelWidth", 0), 500)
        self.assertGreaterEqual(dimensions.get("pixelHeight", 0), 300)
        self.assertAlmostEqual(dimensions["pixelWidth"] / dimensions["pixelHeight"],
            bounds["Width"] / bounds["Height"], delta=0.05,
            msg="Captured PNG proportions differ from the selected main window")
        self.assertGreater(path.stat().st_size, 1000)

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
        self.initial_history_page = history
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

    def oldest_history_label(self, session):
        earlier = self.content(session, {"inputHistory": {"before": self.initial_history_page["olderCursor"]}}, "inputHistoryPage")
        oldest = self.content(session, {"inputHistory": {"before": earlier["olderCursor"]}}, "inputHistoryPage")
        summary = oldest["entries"][0]
        self.assertEqual(summary["id"], "semantic-input-0000")
        self.assertTrue(summary["preview"]["text"].startswith("Semantic oldest input."))
        self.assertTrue(summary["preview"]["truncated"])
        label = summary["preview"]["text"] + "…"
        self.observe("semantic-history-click-selector", inputID=summary["id"],
            role="AXButton", scopeIdentifier="ChatInputHistoryScrubber.panel", exactLabel=label)
        return label

    def observe_around_item_control_read(self, session):
        target = {"chatReadAroundItem": {"itemID": "semantic-input-0000"}}
        response, metrics = read_content(self.api, session, target)
        path = self.root / "logs/semantic-around-oldest-control-read.json"
        path.write_text(json.dumps(response, ensure_ascii=False, indent=2))
        page = response_page(response, "chatReadPage")
        self.observe("semantic-around-item-control-read", source="independent control read; not GUI response capture",
            inputID="semantic-input-0000", sessionID=page["sessionID"], executionID=page["executionID"],
            transcriptRevision=page["transcriptRevision"], revision=page["revision"], startIndex=page["startIndex"],
            blockIDs=[block["id"] for block in page["blocks"]],
            ownerInputIDs=[block.get("ownerInputID") for block in page["blocks"]],
            revealTarget=page.get("revealTarget"), responsePath=str(path), **metrics)
        self.assertEqual(page["executionID"], session["executionID"])
        self.assertEqual(page["revealTarget"]["itemID"], "semantic-input-0000")
        block = next(block for block in page["blocks"] if block["id"] == "semantic-input-0000")
        self.assertEqual(block["content"]["item"]["_0"]["deferred"]["_0"]["id"], "semantic-input-0000")

    def assert_identifier_count(self, identity, identifier, expected_count, *, prefix=False, required_grid_tiles=None, expected_owner_tile_ids=None):
        latest = {}
        def matches():
            nonlocal latest
            latest = native_ax_probe(identity, identifier, prefix=prefix)
            if (not latest["complete"] or latest.get("windowCount", 0) == 0
                    or latest["probeScope"] != "fullTree" or not latest["treeScanned"]):
                return False
            if expected_owner_tile_ids is not None:
                matches_expected = (set(latest["matchedOwnerTileIDs"]) == set(expected_owner_tile_ids)
                    and len(latest["matchedOwnerTileIDs"]) == expected_count and latest["unownedMatchCount"] == 0)
            elif prefix and identifier == "grid-tile-":
                matches_expected = latest["gridTileCount"] == expected_count
            else:
                matches_expected = latest["count"] == expected_count
            return (latest["complete"] and latest["windowCount"] > 0 and matches_expected
                and (required_grid_tiles is None or (latest["gridTileCount"] == required_grid_tiles
                    and set(latest["gridTileIDs"]) == FIXTURE_GRID_TILE_IDS
                    and latest["visibleGridTileCount"] == required_grid_tiles and not latest["gridTilesOverlap"])))
        try:
            lifecycle.eventually("the expected native accessibility count", matches, timeout=20)
        finally:
            self.observe("semantic-native-count", identifier=identifier, expectedCount=expected_count,
                requiredGridTileCount=required_grid_tiles,
                expectedOwnerTileIDs=None if expected_owner_tile_ids is None else sorted(expected_owner_tile_ids), **latest)

    def nudge_owned_grid_window(self, identity):
        latest = {}
        def current_grid():
            nonlocal latest
            latest = native_ax_probe(identity)
            return (latest["complete"] and latest["probeScope"] == "fullTree" and latest["treeScanned"]
                and set(latest.get("gridTileIDs", [])) == FIXTURE_GRID_TILE_IDS)
        lifecycle.eventually("the returned grid before owned window resize", current_grid, timeout=20)
        for stage, frame in (("nudge", (40, 40, 1190, 780)), ("restore", (40, 40, 1200, 900))):
            previous_widths = sorted((tile["identifier"], tile["frame"]["width"])
                for tile in latest["gridTileFrames"] if tile["frame"])
            resized = native_ax_probe(identity, window_frame=frame)
            self.observe("semantic-owned-grid-window-nudge", stage=stage, requestedFrame=list(frame), **resized)
            self.assertEqual(resized["probeScope"], "ownedWindow")
            self.assertFalse(resized["treeScanned"])
            self.assertTrue(resized["complete"])
            self.assertEqual(resized.get("windowResizeStatus"), dict(AXSize=0, AXPosition=0))
            def relaid_out():
                if not current_grid():
                    return False
                widths = sorted((tile["identifier"], tile["frame"]["width"])
                    for tile in latest["gridTileFrames"] if tile["frame"])
                return abs(latest["windowFrames"][0]["width"] - frame[2]) <= 1 and widths != previous_widths
            lifecycle.eventually("the grid layout after owned window resize", relaid_out, timeout=20)
            self.observe("semantic-owned-grid-window-relayout", stage=stage, **latest)

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
        resized = native_ax_probe(identity, window_frame=(40, 40, 1200, 900))
        self.observe("semantic-owned-window-resize", requestedFrame=[40, 40, 1200, 900], **resized)
        self.assertEqual(resized["probeScope"], "ownedWindow")
        self.assertFalse(resized["treeScanned"])
        self.assertTrue(resized["complete"])
        self.assertEqual(resized.get("windowResizeStatus"), dict(AXSize=0, AXPosition=0))
        self.assertAlmostEqual(resized["windowFrames"][0]["width"], 1200, delta=1)
        self.assertGreater(resized["windowFrames"][0]["height"], 0)
        self.assertLessEqual(resized["windowFrames"][0]["height"], 901)
        self.press_native(identity, "view-mode-grid", identifier=True)
        self.assert_native(identity, "レイアウト: バランス")
        self.assert_identifier_count(identity, "grid-tile-", 9, prefix=True, required_grid_tiles=9)
        send_all("semantic-grid-running")
        self.assert_native(identity, "printf semantic-grid-live")
        self.assert_identifier_count(identity, "GridTile.statusLine", 8, required_grid_tiles=9,
            expected_owner_tile_ids=RUNNING_GRID_TILE_IDS)
        self.screenshot(identity, "semantic-nine-sessions-running")
        self.press_native(identity, "view-mode-single", identifier=True)
        self.press_native(identity, TITLE)
        draft = "Semantic responsive draft while eight sessions run."
        response = {}
        attempt = 0
        def edit_ready_composer():
            nonlocal response, attempt
            attempt += 1
            response = native_ax_probe(identity, "ChatComposer.input", draft=draft)
            self.observe("semantic-native-editor-probe", attempt=attempt, backgroundRunningSessions=8, **response)
            return response.get("mutationAttempted", False)
        lifecycle.eventually("one stable editable composer in the complete native tree", edit_ready_composer, timeout=20)
        self.observe("semantic-native-input-response", backgroundRunningSessions=8, **response)
        self.assertTrue(response["complete"])
        self.assertEqual(response.get("actualEditorCount"), 1)
        self.assertEqual(response.get("setStatus"), 0, "The native composer rejected its AXValue update")
        self.assertEqual(response.get("observed"), draft)
        self.assertEqual(response.get("restoreStatus"), 0, "The native composer draft was not restored")
        self.press_native(identity, "view-mode-grid", identifier=True)
        self.nudge_owned_grid_window(identity)
        for session in sessions:
            self.api.command(self.session_command(session, {"interrupt": {}}))
        lifecycle.eventually("the eight interrupted fixture turns", all_idle)
        self.assert_identifier_count(identity, "GridTile.statusLine", 0, required_grid_tiles=9,
            expected_owner_tile_ids=frozenset())
        self.screenshot(identity, "semantic-nine-sessions-interrupted")
        self.press_native(identity, "view-mode-single", identifier=True)
        self.press_native(identity, TITLE)

    def test_long_card_and_history_remain_available_across_native_jump_and_reconnect(self):
        gui, identity = self.start_gui(self.original_app)
        self.native_gui_identity = identity
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
        self.press_native_button(identity, self.oldest_history_label(session),
            scope_identifier="ChatInputHistoryScrubber.panel")
        self.observe_around_item_control_read(session)
        self.assert_native(identity, "Semantic oldest input.")
        self.assert_native_button(identity, "全文を表示")
        self.screenshot(identity, "semantic-oldest-direct-jump")
        self.press_native(identity, "ChatTranscript.jumpToLatest", identifier=True)
        self.assert_native(identity, FINAL_TEXT)
        self.screenshot(identity, "semantic-returned-to-tail")
        self.assert_grid_and_input_response(identity)
        quit_result = lifecycle.quit_application(identity)
        self.assertEqual(quit_result["sendStatus"], 0)
        self.assertEqual(gui.wait(timeout=30), 0)
        _, reconnected = self.start_gui(self.original_app)
        self.native_gui_identity = reconnected
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
        self.native_passed = True


class ContentRecoveryAcceptance(SemanticChatAcceptance):
    def setUp(self):
        original_work_dir = lifecycle.OPTIONS.work_dir
        lifecycle.OPTIONS.work_dir = original_work_dir / "content-recovery"
        self.addCleanup(setattr, lifecycle.OPTIONS, "work_dir", original_work_dir)
        lifecycle.SessionRuntimeLifecycleTests.setUp(self)
        self.report["purpose"] = "Opened task details recover after native plan rename and deletion"
        self.report["semanticSourceHashes"] = {str(Path(__file__).resolve()):
            hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
        arguments = [sys.executable, "-B", str(Path(__file__).resolve()),
            "--fake-content-recovery", str(self.root), "--"]
        Path(self.agents["codex"]).write_text("#!/bin/sh\nexec " +
            " ".join(shlex.quote(value) for value in arguments) + ' "$@"\n')
        transcripts = self.store / "transcripts"
        transcripts.mkdir(parents=True)
        descriptor = dict(id=SESSION_ID, kind="codex", name=RECOVERY_TITLE, titleSource="manual",
            workingDirectory=str(self.root / "project"), startedAt=STAMP, command=self.agents["codex"],
            args=["app-server"], env={}, backend="appServer", codexThreadId="synthetic-" + SESSION_ID["rawValue"],
            launchContext="interactive")
        (self.store / "sessions.json").write_text(json.dumps(dict(schemaVersion=1, sessions=[descriptor])))
        (transcripts / (SESSION_ID["rawValue"] + ".json")).write_text(json.dumps([
            dict(userMessage=dict(id="recovery-restored-input", text="Recovery restored seed", timestamp=STAMP,
                attachments=[], turnEnd=dict(outcome="completed", at=STAMP + 1))),
            dict(agentMessage=dict(id="recovery-restored-answer", text="Recovery restored ready", timestamp=STAMP + 1))]))
        self.native_gui_identity = None
        self.native_passed = False
        self.addCleanup(self.capture_native_failure)

    def assert_recovery_display(self, identity, response, *, task=None, command=None):
        latest = {}
        def recovered():
            nonlocal latest
            latest = native_ax_probe(identity, include_nodes=True)
            texts = [node.get(key, "") for node in latest.get("nodes", [])
                for key in ("AXTitle", "AXDescription", "AXValue")]
            return latest["complete"] and latest["windowCount"] > 0 and any(response in text for text in texts)
        try:
            lifecycle.eventually("new output after the plan transition", recovered, timeout=25)
        finally:
            path = self.root / "logs" / (response.replace(" ", "-") + "-ax.json")
            path.write_text(json.dumps(latest, ensure_ascii=False, indent=2))
            self.observe("content-recovery-native-display", response=response, axPath=str(path),
                runtimeGeneration=self.api.generation, guiPID=identity.pid, bundleID=self.bundle_id)
        card = native_ax_probe(identity, scope_identifier="AgentStatusCard", include_nodes=True)
        self.assertTrue(card["complete"])
        texts = [node.get(key, "") for node in card["nodes"] for key in ("AXTitle", "AXDescription", "AXValue")]
        self.assertTrue(card["nodes"], "The current card must remain visible")
        if task is not None:
            self.assertTrue(any(task in text for text in texts), "The current task is missing from its card")
        if command is not None:
            self.assertTrue(any(command in text for text in texts), "The loaded row details disappeared")
        if response in ("Recovery response 3", "Recovery response 4"):
            self.assertFalse(any(RECOVERY_NEW_TASK in text or RECOVERY_OLD_TASK in text for text in texts),
                "Deleted task rows remain in the current card")
        all_texts = [node.get(key, "") for node in latest["nodes"]
            for key in ("AXTitle", "AXDescription", "AXValue")]
        for forbidden in ("本文の取得位置が不正です。", "指定された本文が見つかりません。", "再試行"):
            self.assertFalse(any(forbidden in text for text in all_texts),
                "An obsolete content error remains in the conversation or card")

    def advance_recovery(self, number):
        (self.root / f"recovery-trigger-{number}").touch()
        state = lifecycle.eventually("the fake plan transition acknowledgement",
            lambda: (value if (value := self.fake_state("structured")).get("recoveryTransition") == number else None))
        self.observe("content-recovery-fixture-ack", transition=number, fakePID=state["pid"])

    def open_recovery_task(self, identity, title):
        identifier = "AgentStatusCard.row.task-codex-plan-0-" + title
        latest = {}
        def task_state():
            nonlocal latest
            latest = native_ax_probe(identity, identifier=identifier,
                scope_identifier=identifier, include_nodes=True)
            headers = [node.get("AXDescription", "") for node in latest.get("nodes", [])
                if node.get("AXIdentifier") == identifier and node.get("AXRole") == "AXButton"
                and title in node.get("AXDescription", "")]
            return headers[0] if latest["complete"] and len(headers) == 1 else ""
        description = lifecycle.eventually("the task disclosure state", task_state, timeout=20)
        if "折りたたみ済み" in description:
            self.press_native(identity, title)
        lifecycle.eventually("the expanded task disclosure", lambda: "展開済み" in task_state(), timeout=20)
        self.observe("content-recovery-task-expanded", title=title, **latest)

    def test_opened_task_details_recover_after_plan_rename_and_deletion(self):
        _, identity = self.start_gui(self.original_app)
        self.native_gui_identity = identity
        discovery = lifecycle.eventually("the isolated recovery runtime", self.read_ready_discovery, timeout=90)
        self.runtime_identity = lifecycle.process_info(discovery["pid"])[0]
        self.assertTrue(Path(self.runtime_identity.executable).is_relative_to(self.store / "session-runtime-bundles"))
        self.remember(self.runtime_identity, "runtime")
        self.api = lifecycle.RuntimeAPI(self.store, discovery, self.observe, self.capture_runtime_timeout)
        application = self.api.request("GET", "/application-snapshot")[1]
        self.assertEqual(application["claudeBinaryPath"], self.agents["claudeCode"])
        self.press_native(identity, RECOVERY_TITLE)
        def restored_child():
            states = [json.loads(path.read_text()) for path in (self.root / "fake-state").glob("*.json")]
            return next((state for state in states if state["role"] == "structured"), None)
        state = lifecycle.eventually("the restored recovery fake", restored_child)
        self.fixture_pids["structured"] = state["pid"]
        session = self.get_session(SESSION_ID, "chat")
        self.api.command(self.session_command(session, {"send": dict(text="Recovery prime", submit=True, attachments=[])}))
        lifecycle.eventually("the completed prime turn", lambda:
            self.fake_state("structured").get("sendTexts") == ["Recovery prime"] and
            "idle" in self.get_session(SESSION_ID, "chat")["status"])
        self.api.command(self.session_command(self.get_session(SESSION_ID, "chat"),
            {"send": dict(text="Recovery live input", submit=True, attachments=[])}))
        state = lifecycle.eventually("the live recovery fixture", lambda:
            (value if "recoveryTransition" in (value := self.fake_state("structured")) else None))
        child = lifecycle.process_info(state["pid"])
        self.assertEqual(child[1], self.runtime_identity.pid)
        self.remember(child[0], "synthetic-recovery-codex")
        self.open_recovery_task(identity, RECOVERY_OLD_TASK)
        self.assert_recovery_display(identity, "Recovery response 0", task=RECOVERY_OLD_TASK,
            command="printf recovery-work-0")
        self.advance_recovery(1)
        self.assert_recovery_display(identity, "Recovery response 1", task=RECOVERY_NEW_TASK)
        self.open_recovery_task(identity, RECOVERY_NEW_TASK)
        self.assert_native(identity, "printf recovery-work-1")
        self.advance_recovery(2)
        self.assert_recovery_display(identity, "Recovery response 2", task=RECOVERY_NEW_TASK,
            command="printf recovery-work-2")
        self.advance_recovery(3)
        self.assert_recovery_display(identity, "Recovery response 3")
        self.advance_recovery(4)
        self.assert_recovery_display(identity, "Recovery response 4")
        self.observe("content-recovery-native-acceptance-passed", transitions=4,
            openedRowBeforeRename=True, openedRowBeforeDeletion=True, errorsAbsent=True)
        self.native_passed = True


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


def content_retry_observation(responses):
    root = Path(__file__).resolve().parents[3] / ".verification/semantic-chat-read-20261110/native" / (
        "http-selfcheck-" + str(uuid.uuid4()))
    store = root / "data"
    credentials = store / "session-runtime/master-token"
    credentials.parent.mkdir(parents=True)
    credential = "fixture-only-" + str(uuid.uuid4())
    credentials.write_text(credential)
    credentials.chmod(0o600)
    observations, requests = [], []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            if self.headers.get("Authorization") != "Bearer " + credential:
                status, body = 401, b'{"message":"fixture authentication failed"}'
            else:
                status, body = responses[min(len(requests) - 1, len(responses) - 1)]
            self.send_response(status)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_args):
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=lambda: server.serve_forever(poll_interval=0.05), daemon=True)
    thread.start()

    def observe(event, **values):
        observations.append(dict(event=event, **values))

    api = lifecycle.RuntimeAPI(store, dict(desktopURL=f"http://127.0.0.1:{server.server_port}",
        generation="fixture-generation", protocolVersion=1), observe, lambda: None)
    value, failure = None, None
    try:
        try:
            value, _ = read_content(api, dict(id=SESSION_ID,
                executionID="471E1975-C117-4E61-B681-D5D8E65F0C17"), {"chatReadTail": {}})
        except AssertionError as error:
            failure = type(error).__name__
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    if thread.is_alive():
        raise AssertionError("The owned HTTP fixture did not stop")
    result = dict(response=value, failure=failure, requestCount=len(requests),
        backpressureCount=api.backpressure_counts.get("GET /session-content", 0),
        credentialLeaked=credential in json.dumps(observations), observations=observations)
    (root / "ownership.json").write_text(json.dumps(dict(session="semantic_native_acceptance",
        purpose="Content HTTP retry contract prerequisite", pid=os.getpid(), executable=sys.executable,
        serverStopped=True, result=result), ensure_ascii=False, indent=2))
    return result


def layout_leaves(node):
    if node["kind"] == "leaf":
        return [node["session"]]
    return [session for child in node["children"] for session in layout_leaves(child)]


class RecoveryFixtureTests(unittest.TestCase):
    def test_plan_transitions_use_real_wire_messages_and_acknowledge_each_trigger(self):
        root = Path(__file__).resolve().parents[3] / ".verification/body-content-recovery-implementation-20261111/native-fixture" / str(uuid.uuid4())
        root.mkdir(parents=True)
        (root / "fake-state").mkdir()
        ownership = dict(purpose="Content recovery fixture wire self-check", session="native_recovery_repro",
            executable=sys.executable, script=str(Path(__file__).resolve()))
        memo = root / "ownership.json"
        memo.write_text(json.dumps(ownership, indent=2))
        process = subprocess.Popen([sys.executable, "-B", str(Path(__file__).resolve()),
            "--fake-content-recovery", str(root), "--", "app-server"], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=dict(os.environ, PHLOX_SESSION_ID="recovery-selfcheck"))
        ownership["pid"] = process.pid
        memo.write_text(json.dumps(ownership, indent=2))
        try:
            requests = [dict(id=1, method="initialize"), dict(id=2, method="thread/start"),
                dict(id=3, method="turn/start", params=dict(input=[dict(text="prime")])),
                dict(id=4, method="turn/start", params=dict(input=[dict(text="live")]))]
            process.stdin.write(("\n".join(json.dumps(request) for request in requests) + "\n").encode())
            process.stdin.flush()
            state_path = root / "fake-state" / f"{process.pid}.json"
            def acknowledged(number):
                return state_path.is_file() and json.loads(state_path.read_text()).get("recoveryTransition") == number
            lifecycle.eventually("the initial recovery task", lambda: acknowledged(0), timeout=10)
            for number in (1, 2, 3, 4):
                (root / f"recovery-trigger-{number}").touch()
                lifecycle.eventually("the requested recovery transition", lambda: acknowledged(number), timeout=10)
            output, diagnostics = process.communicate(timeout=10)
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
            ownership.update(exitCode=process.returncode, exited=process.poll() is not None)
            memo.write_text(json.dumps(ownership, indent=2))
        (root / "stdout.jsonl").write_bytes(output)
        (root / "stderr.log").write_bytes(diagnostics)
        self.assertEqual(process.returncode, 0)
        events = [json.loads(line) for line in output.splitlines()]
        plans = [event["params"]["plan"] for event in events if event.get("method") == "turn/plan/updated"]
        self.assertEqual(plans, [[dict(step=RECOVERY_OLD_TASK, status="inProgress")],
            [dict(step=RECOVERY_NEW_TASK, status="inProgress")], []])
        commands = [event["params"]["item"]["command"] for event in events
            if event.get("method") == "item/completed" and event["params"]["item"].get("type") == "commandExecution"]
        self.assertEqual(commands, ["printf recovery-work-0", "printf recovery-work-1", "printf recovery-work-2",
            "printf recovery-work-3", "printf recovery-work-4"])


class FixturePrerequisiteTests(unittest.TestCase):
    def test_known_busy_content_retries_through_existing_runtime_policy(self):
        result = content_retry_observation([(503, json.dumps({"message": "実行サービスの操作数が上限に達しています。"}).encode()),
            (200, b'{"fixture":"bounded-success"}')])
        self.assertEqual(result["response"], {"fixture": "bounded-success"})
        self.assertIsNone(result["failure"])
        self.assertEqual(result["requestCount"], 2)
        self.assertEqual(result["backpressureCount"], 1)
        self.assertFalse(result["credentialLeaked"])

    def test_unknown_503_fails_without_retrying_or_accepting_next_success(self):
        result = content_retry_observation([(503, b'{"message":"Maintenance window."}'),
            (200, b'{"fixture":"bounded-success"}')])
        self.assertEqual(result["failure"], "AssertionError")
        self.assertEqual(result["requestCount"], 1)
        self.assertEqual(result["backpressureCount"], 0)
        self.assertFalse(result["credentialLeaked"])

    def test_invalid_json_503_fails_without_retrying_or_accepting_next_success(self):
        result = content_retry_observation([(503, b'{'), (200, b'{"fixture":"bounded-success"}')])
        self.assertEqual(result["failure"], "AssertionError")
        self.assertEqual(result["requestCount"], 1)
        self.assertEqual(result["backpressureCount"], 0)
        self.assertFalse(result["credentialLeaked"])

    def test_grid_fixture_restores_nine_balanced_panes_without_an_oversized_canvas(self):
        saved = balanced_grid_state()
        custom = saved["state"]["custom"]["_0"]
        self.assertEqual(saved["schemaVersion"], 1)
        self.assertEqual(custom["canvasMinimum"], [0, 0])
        self.assertEqual(custom["presetState"], dict(preset="balanced", isAdjusted=False))
        self.assertEqual(layout_leaves(custom["tree"]["root"]), [SESSION_ID] + GRID_IDS)
        self.assertEqual(len(layout_leaves(custom["tree"]["root"])), 9)

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
    if sys.argv[1:2] == ["--fake-content-recovery"]:
        fake_content_recovery(Path(sys.argv[2]).resolve(), sys.argv[3:])
        sys.exit(0)
    if sys.argv[1:2] == ["--fake-codex"]:
        fake_codex(Path(sys.argv[2]).resolve(), sys.argv[3:])
        sys.exit(0)
    if sys.argv[1:] in (["--self-check"], ["--content-recovery-self-check"]):
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(RecoveryFixtureTests)
        if sys.argv[1:] == ["--self-check"]:
            suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(FixturePrerequisiteTests))
        result = unittest.TextTestRunner(verbosity=2).run(suite)
        sys.exit(0 if result.wasSuccessful() else 1)
    recovery_only = "--content-recovery-only" in sys.argv
    if recovery_only:
        sys.argv.remove("--content-recovery-only")
    lifecycle.OPTIONS, remaining = lifecycle.parse_options()
    if remaining:
        raise SystemExit("Unexpected arguments: " + " ".join(remaining))
    output = io.StringIO()
    suite = unittest.TestSuite()
    if not recovery_only:
        suite.addTest(SemanticChatAcceptance(
            "test_long_card_and_history_remain_available_across_native_jump_and_reconnect"))
    suite.addTest(ContentRecoveryAcceptance("test_opened_task_details_recover_after_plan_rename_and_deletion"))
    result = unittest.TextTestRunner(stream=output, verbosity=2).run(suite)
    log = output.getvalue()
    sys.stderr.write(log)
    if (lifecycle.OPTIONS.work_dir / "logs").is_dir():
        (lifecycle.OPTIONS.work_dir / "logs/test-result.log").write_text(log)
    sys.exit(0 if result.wasSuccessful() else 1)
