#!/usr/bin/env python3
"""隔離した署名済みアプリの独立runtimeを検査するunittest。

親がmanaged-buildでDebugアプリを用意してから実行する。
~/.agents/scripts/compact-test runtime-lifecycle python3 <this-file> \
  --app <unique-bundle-id.app> --work-dir <project>/.verification/<unique-run>

既定はPTY + Codex。--include-additional-structured でClaude persistentと
Cursor oneshotを追加する。状態は管理API、再接続GUIの固有内容はAXで検査する。
--include-additional-structured --snapshot-soak-seconds 60 は4実行中にGET負荷を掛ける。
--interactive-ui-smoke は別runで親のGUI承認/質問回答を各120秒待つ。API代理回答なし。
fixtureは隣のsession-runtime-fake-agent.pyとsession-runtime-structured-fake-agent.py。
LaunchServices fresh起動を使う。ウィンドウ復元、異なる版との互換性、画面の見た目は対象外。
"""
import argparse
import base64
import ctypes
from dataclasses import asdict, dataclass
import hashlib
import http.client
import io
import json
import os
from pathlib import Path
import plistlib
import shlex
import shutil
import signal
import select
import stat
import struct
import subprocess
import sys
import time
import unittest
import urllib.parse
import uuid


PROJECT = Path(__file__).resolve().parents[3]
SWIFT_EPOCH = 978307200
OPTIONS = None


def eventually(description, predicate, timeout=40):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.2)
    raise AssertionError(f"Timed out waiting for {description}")


class BSDInfo(ctypes.Structure):
    _fields_ = [(name, ctypes.c_uint32) for name in (
        "flags", "status", "xstatus", "pid", "ppid", "uid", "gid", "ruid", "rgid",
        "svuid", "svgid", "rfu")]
    _fields_ += [("comm", ctypes.c_char * 16), ("name", ctypes.c_char * 32)]
    _fields_ += [(name, ctypes.c_uint32) for name in (
        "nfiles", "pgid", "pjobc", "tdev", "tpgid", "nice")]
    _fields_ += [("start_seconds", ctypes.c_uint64), ("start_microseconds", ctypes.c_uint64)]


@dataclass(frozen=True)
class ProcessIdentity:
    pid: int
    executable: str
    start_seconds: int
    start_microseconds: int


class ObservedApplication:
    def __init__(self, identity):
        self.pid = identity.pid
        self.args = [identity.executable]
        self.returncode = None
        self.events = select.kqueue()
        # LaunchServicesの子ではwaitpidできないため、kernelの実終了statusを監視する。
        event = select.kevent(self.pid, filter=select.KQ_FILTER_PROC,
            flags=select.KQ_EV_ADD | select.KQ_EV_ENABLE,
            fflags=select.KQ_NOTE_EXIT | 0x04000000)
        self.events.control([event], 0, 0)

    def _collect(self, timeout):
        if self.returncode is not None:
            return self.returncode
        events = self.events.control(None, 1, timeout)
        if events:
            event = events[0]
            if event.flags & select.KQ_EV_ERROR:
                raise OSError(event.data, "Application exit observation failed")
            if not event.fflags & 0x04000000:
                raise AssertionError("Kernel did not provide the application's exit status")
            self.returncode = os.waitstatus_to_exitcode(event.data)
        return self.returncode

    def poll(self):
        return self._collect(0)

    def wait(self, timeout=None):
        result = self._collect(timeout)
        if result is None:
            raise subprocess.TimeoutExpired(self.args, timeout)
        return result

    def close(self):
        self.events.close()


def process_info(pid):
    library = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    library.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    library.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64,
                                    ctypes.c_void_p, ctypes.c_int]
    path = ctypes.create_string_buffer(4096)
    ctypes.set_errno(0)
    if library.proc_pidpath(pid, path, len(path)) <= 0:
        if ctypes.get_errno() in (0, 3):
            return None
        raise OSError(ctypes.get_errno(), "proc_pidpath failed")
    info = BSDInfo()
    ctypes.set_errno(0)
    size = library.proc_pidinfo(pid, 3, 0, ctypes.byref(info), ctypes.sizeof(info))
    if size != ctypes.sizeof(info):
        if ctypes.get_errno() == 3:
            return None
        raise RuntimeError(f"proc_pidinfo did not return a complete identity (size={size}, errno={ctypes.get_errno()})")
    if info.status == 5:
        return None
    identity = ProcessIdentity(pid, os.fsdecode(path.value), info.start_seconds, info.start_microseconds)
    return identity, info.ppid


def same_process(identity):
    current = process_info(identity.pid)
    return current is not None and current[0] == identity


def applications_at_executable(executable):
    library = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    library.proc_listpids.argtypes = [ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p, ctypes.c_int]
    library.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    size = library.proc_listpids(4, os.getuid(), None, 0)
    if size <= 0:
        raise OSError(ctypes.get_errno(), "Could not enumerate the current user's processes")
    identifiers = (ctypes.c_int * (size // ctypes.sizeof(ctypes.c_int) + 128))()
    count = library.proc_listpids(4, os.getuid(), identifiers, ctypes.sizeof(identifiers))
    if count < 0:
        raise OSError(ctypes.get_errno(), "Could not read the current user's process identifiers")
    matches = []
    for pid in identifiers[:count // ctypes.sizeof(ctypes.c_int)]:
        if pid <= 0:
            continue
        path = ctypes.create_string_buffer(4096)
        if library.proc_pidpath(pid, path, len(path)) > 0 and Path(os.fsdecode(path.value)).resolve() == executable:
            info = process_info(pid)
            if info is not None:
                matches.append(info[0])
    return matches


def send_owned_signal(identity, number):
    if not same_process(identity):
        return False
    os.kill(identity.pid, number)
    return True


def quit_application(identity, wait_for_reply=True):
    if not same_process(identity):
        raise AssertionError("GUI identity changed before normal quit")

    class Descriptor(ctypes.Structure):
        _fields_ = [("type", ctypes.c_uint32), ("handle", ctypes.c_void_p)]

    def code(text):
        return int.from_bytes(text.encode("ascii"), "big")

    carbon = ctypes.CDLL("/System/Library/Frameworks/Carbon.framework/Carbon")
    carbon.AECreateDesc.argtypes = [ctypes.c_uint32, ctypes.c_void_p, ctypes.c_long,
                                  ctypes.POINTER(Descriptor)]
    carbon.AECreateAppleEvent.argtypes = [ctypes.c_uint32, ctypes.c_uint32,
        ctypes.POINTER(Descriptor), ctypes.c_int16, ctypes.c_int32, ctypes.POINTER(Descriptor)]
    carbon.AESendMessage.argtypes = [ctypes.POINTER(Descriptor), ctypes.POINTER(Descriptor),
                                   ctypes.c_int32, ctypes.c_long]
    carbon.AEDisposeDesc.argtypes = [ctypes.POINTER(Descriptor)]
    carbon.AEGetParamPtr.argtypes = [ctypes.POINTER(Descriptor), ctypes.c_uint32, ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_uint32), ctypes.c_void_p, ctypes.c_long, ctypes.POINTER(ctypes.c_long)]
    target, event, reply = Descriptor(), Descriptor(), Descriptor()
    pid = ctypes.c_int32(identity.pid)
    try:
        status = carbon.AECreateDesc(code("kpid"), ctypes.byref(pid), ctypes.sizeof(pid), ctypes.byref(target))
        if status == 0:
            status = carbon.AECreateAppleEvent(code("aevt"), code("quit"), ctypes.byref(target),
                                               -1, 0, ctypes.byref(event))
        if status == 0:
            mode = 0x1013 if wait_for_reply else 0x1011
            status = carbon.AESendMessage(ctypes.byref(event), ctypes.byref(reply), mode, 600)
        result = dict(sendStatus=status, replyPresent=bool(reply.handle),
                      sendMode="wait-reply" if wait_for_reply else "no-reply")
        if status == 0 and reply.handle:
            error_number, actual_type, actual_size = ctypes.c_int32(), ctypes.c_uint32(), ctypes.c_long()
            parameter_status = carbon.AEGetParamPtr(ctypes.byref(reply), code("errn"), code("long"),
                ctypes.byref(actual_type), ctypes.byref(error_number), ctypes.sizeof(error_number),
                ctypes.byref(actual_size))
            result["errorParameterStatus"] = parameter_status
            if parameter_status == 0:
                result["replyError"] = error_number.value
        return result
    finally:
        for descriptor in (reply, event, target):
            if descriptor.handle:
                carbon.AEDisposeDesc(ctypes.byref(descriptor))


def accessibility_window_state(identity, expected_text=None):
    if not same_process(identity):
        return dict(targetExited=True)
    framework = ctypes.CDLL("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices")
    foundation = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
    framework.AXUIElementCreateApplication.argtypes = [ctypes.c_int32]
    framework.AXUIElementCreateApplication.restype = ctypes.c_void_p
    framework.AXUIElementSetMessagingTimeout.argtypes = [ctypes.c_void_p, ctypes.c_float]
    framework.AXUIElementCopyAttributeValue.argtypes = [ctypes.c_void_p, ctypes.c_void_p,
                                                      ctypes.POINTER(ctypes.c_void_p)]
    foundation.CFStringCreateWithCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_uint32]
    foundation.CFStringCreateWithCString.restype = ctypes.c_void_p
    foundation.CFArrayGetCount.argtypes = [ctypes.c_void_p]
    foundation.CFArrayGetCount.restype = ctypes.c_long
    foundation.CFArrayGetValueAtIndex.argtypes = [ctypes.c_void_p, ctypes.c_long]
    foundation.CFArrayGetValueAtIndex.restype = ctypes.c_void_p
    foundation.CFGetTypeID.argtypes = [ctypes.c_void_p]
    foundation.CFGetTypeID.restype = ctypes.c_ulong
    foundation.CFStringGetTypeID.restype = ctypes.c_ulong
    foundation.CFArrayGetTypeID.restype = ctypes.c_ulong
    foundation.CFStringGetCString.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_long, ctypes.c_uint32]
    foundation.CFStringGetCString.restype = ctypes.c_bool
    foundation.CFRelease.argtypes = [ctypes.c_void_p]
    app = framework.AXUIElementCreateApplication(identity.pid)
    key = foundation.CFStringCreateWithCString(None, b"AXWindows", 0x08000100)
    windows = ctypes.c_void_p()
    try:
        timeout_status = framework.AXUIElementSetMessagingTimeout(app, ctypes.c_float(1))
        status = framework.AXUIElementCopyAttributeValue(app, key, ctypes.byref(windows))
        result = dict(axWindowsStatus=status, axTimeoutStatus=timeout_status)
        if status == 0 and windows.value:
            result["axWindowCount"] = foundation.CFArrayGetCount(windows)
            if expected_text is not None:
                keys = {name: foundation.CFStringCreateWithCString(None, name.encode(), 0x08000100)
                        for name in ("AXTitle", "AXDescription", "AXValue", "AXChildren")}
                visited = set()
                texts = []
                deadline = time.monotonic() + 5

                def contains(element):
                    if element in visited or len(visited) >= 2000 or time.monotonic() >= deadline:
                        return False
                    visited.add(element)
                    for name, attribute in keys.items():
                        value = ctypes.c_void_p()
                        copied = framework.AXUIElementCopyAttributeValue(element, attribute, ctypes.byref(value))
                        if copied != 0 or not value.value:
                            continue
                        try:
                            kind = foundation.CFGetTypeID(value)
                            if kind == foundation.CFStringGetTypeID():
                                buffer = ctypes.create_string_buffer(16384)
                                if foundation.CFStringGetCString(value, buffer, len(buffer), 0x08000100):
                                    text = buffer.value.decode("utf-8")
                                    if text and text not in texts and len(texts) < 1000:
                                        texts.append(text)
                                    if expected_text in text:
                                        return True
                            elif name == "AXChildren" and kind == foundation.CFArrayGetTypeID():
                                for index in range(foundation.CFArrayGetCount(value)):
                                    if contains(foundation.CFArrayGetValueAtIndex(value, index)):
                                        return True
                        finally:
                            foundation.CFRelease(value)
                    return False

                try:
                    result["expectedTextPresent"] = any(contains(foundation.CFArrayGetValueAtIndex(windows, index))
                        for index in range(foundation.CFArrayGetCount(windows)))
                    result["axNodesRead"] = len(visited)
                    result["visibleTexts"] = texts
                finally:
                    for attribute in keys.values():
                        foundation.CFRelease(attribute)
        return result
    finally:
        if windows.value:
            foundation.CFRelease(windows)
        foundation.CFRelease(key)
        foundation.CFRelease(app)


def private_json(path):
    flags = os.O_RDONLY | os.O_NOFOLLOW
    descriptor = os.open(path, flags)
    with os.fdopen(descriptor, "r") as handle:
        info = os.fstat(handle.fileno())
        if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600 or not stat.S_ISREG(info.st_mode):
            raise AssertionError("Runtime metadata is not a private regular file")
        return json.load(handle)


def file_url(value):
    parts = urllib.parse.urlsplit(value)
    if parts.scheme != "file" or parts.netloc not in ("", "localhost"):
        raise AssertionError("Expected a local file URL")
    return Path(urllib.parse.unquote(parts.path)).resolve()


class RuntimeAPI:
    def __init__(self, store, discovery, observe, on_timeout):
        endpoint = urllib.parse.urlsplit(discovery["desktopURL"])
        if endpoint.scheme != "http" or endpoint.hostname != "127.0.0.1" or not endpoint.port:
            raise AssertionError("Runtime management endpoint is not loopback HTTP")
        self.port = endpoint.port
        self.generation = discovery["generation"]
        self.protocol = discovery["protocolVersion"]
        self.observe = observe
        self.on_timeout = on_timeout
        self.backpressure_counts = {}
        descriptor = os.open(store / "session-runtime/master-token", os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(descriptor, "r") as handle:
            info = os.fstat(handle.fileno())
            if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
                raise AssertionError("Runtime credential is not private")
            self._token = handle.read(4096).strip()

    def request(self, method, path, payload=None, accepted=(200,)):
        deadline = time.monotonic() + 5
        attempts = 0
        while True:
            result = self.request_once(method, path, payload, accepted=accepted + (503,))
            if result[0] != 503 or 503 in accepted:
                return result
            attempts += 1
            route = method + " " + path
            self.backpressure_counts[route] = self.backpressure_counts.get(route, 0) + 1
            self.observe("runtime-backpressure", method=method, path=path, status=503, attempt=attempts)
            if time.monotonic() >= deadline:
                raise AssertionError(f"Runtime {method} {path} returned HTTP 503 (attempt {attempts})")
            time.sleep(min(0.1, max(0, deadline - time.monotonic())))

    def request_once(self, method, path, payload=None, accepted=(200,)):
        connection = http.client.HTTPConnection("127.0.0.1", self.port, timeout=20)
        started_at = time.time()
        started = time.monotonic()
        headers = {"Authorization": "Bearer " + self._token,
            "X-Phlox-Runtime-Protocol": str(self.protocol),
            "X-Phlox-Runtime-Generation": self.generation, "Content-Type": "application/json"}
        body = None if payload is None else json.dumps(payload, separators=(",", ":")).encode()
        try:
            connection.request(method, path, body=body, headers=headers)
            response = connection.getresponse()
            data = response.read(64 * 1024 * 1024 + 1)
            if len(data) > 64 * 1024 * 1024:
                raise AssertionError("Runtime reply exceeded the test memory limit")
            if response.status not in accepted:
                raise AssertionError(f"Runtime {method} {path} returned HTTP {response.status}")
            return response.status, json.loads(data)
        except TimeoutError:
            socket_info = {}
            if connection.sock is not None:
                try:
                    socket_info = dict(localAddress=connection.sock.getsockname(), peerAddress=connection.sock.getpeername())
                except OSError as error:
                    socket_info = dict(socketInspectionError=type(error).__name__)
            self.observe("runtime-request-timeout", method=method, path=path,
                requestStartedAtUnix=started_at, observedAtUnix=time.time(),
                elapsedSeconds=time.monotonic() - started, **socket_info)
            self.on_timeout()
            raise
        finally:
            connection.close()

    def snapshot(self):
        return self.request("GET", "/snapshot")[1]["snapshot"]

    def operation(self, command):
        return dict(id=str(uuid.uuid4()).upper(), generation=self.generation,
            issuedAt=time.time() - SWIFT_EPOCH,
            payload=base64.b64encode(json.dumps(command, separators=(",", ":")).encode()).decode())

    def command(self, command):
        return self.request("POST", "/command", self.operation(command))[1]


def session_value(snapshot, identifier, kind):
    for session in snapshot["sessions"]:
        if kind in session:
            value = session[kind]["_0"]
            if value["id"] == identifier:
                return value
    raise AssertionError("Previously created session is missing from the runtime snapshot")


def terminal_text(snapshot):
    lines = []
    for line in snapshot["display"]["lines"]:
        data = base64.b64decode(line["data"], validate=True)
        offset, cells = 0, []
        while offset < len(data):
            offset += 15
            length = struct.unpack_from("<H", data, offset)[0]
            offset += 2
            cells.append(data[offset:offset + length].decode("utf-8"))
            offset += length
            hyperlink_length = struct.unpack_from("<H", data, offset)[0]
            offset += 2 + (0 if hyperlink_length == 65535 else hyperlink_length)
        if offset != len(data):
            raise AssertionError("Terminal display cell encoding is inconsistent")
        lines.append("".join(cells))
    return "\n".join(lines)


class SessionRuntimeLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.root = OPTIONS.work_dir
        self.root.mkdir(parents=True, exist_ok=True)
        self.assertEqual(list(self.root.iterdir()), [], "Use a new, empty work directory")
        self.root.chmod(0o700)
        self.run_id = OPTIONS.run_id
        self.store = self.root / "data"
        self.gui_processes = []
        self.owned = {}
        self.fixture_pids = {}
        self.report = dict(run=self.run_id, purpose="Isolated signed runtime lifecycle acceptance",
                           workDirectory=str(self.root), sourceApp=str(OPTIONS.app),
                           launchMode="LaunchServices open -n -F", windowRestorationTested=False,
                           interactiveUISmoke=OPTIONS.interactive_ui_smoke,
                           processes=[], observations=[], cleanup=[])
        self.write_report()
        self.addCleanup(self.cleanup_owned_processes)
        for name in ("agents", "fake-state", "project", "home", "claude-home", "logs"):
            (self.root / name).mkdir()
        self.original_app = self.root / "original/Phlox.app"
        shutil.copytree(OPTIONS.app, self.original_app, symlinks=True)
        with (self.original_app / "Contents/Info.plist").open("rb") as handle:
            self.info = plistlib.load(handle)
        self.bundle_id = self.info["CFBundleIdentifier"]
        self.assertNotIn(self.bundle_id, ("com.phlox.Phlox", "com.phlox.Phlox.debug"),
                         "The acceptance app must have a unique test bundle identifier")
        signed = self.run_helper(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(self.original_app)],
                                 timeout=30)
        self.assertEqual(signed.returncode, 0, "The isolated app failed strict code signature verification")
        fixture = Path(__file__).with_name("session-runtime-fake-agent.py").resolve()
        recorded_files = [path for path in (OPTIONS.app / "Contents/MacOS").iterdir() if path.is_file()]
        recorded_files += [Path(__file__).resolve(), fixture,
                           fixture.with_name("session-runtime-structured-fake-agent.py")]
        hashes = dict(recordedAtUnix=time.time(), files={str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                                                       for path in recorded_files})
        hashes_path = self.root / "logs/source-hashes.json"
        hashes_path.write_text(json.dumps(hashes, indent=2))
        self.report["sourceHashesPath"] = str(hashes_path)
        self.write_report()
        self.agents = {}
        for provider in ("claudeCode", "codex", "cursor"):
            wrapper = self.root / "agents" / provider
            arguments = [sys.executable, str(fixture), "--work-dir", str(self.root), "--provider", provider]
            if OPTIONS.include_additional_structured:
                arguments.append("--additional-structured")
            wrapper.write_text("#!/bin/sh\nexec " + " ".join(shlex.quote(value) for value in arguments + ["--"]) + ' "$@"\n')
            wrapper.chmod(0o700)
            self.agents[provider] = str(wrapper)
        self.environment = dict(os.environ)
        self.environment.update(PHLOX_TEST_AGENT_BINARY_PATHS=json.dumps(self.agents),
            PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN="1", PHLOX_TEST_EPHEMERAL_MOBILE_PORT="1",
            PHLOX_DATA_DIR=str(self.store), PHLOX_DEFAULTS_SUITE="com.phlox.lifecycle." + self.run_id,
            CFFIXED_USER_HOME=str(self.root / "home"), CLAUDE_CONFIG_DIR=str(self.root / "claude-home"))
        # CFFIXED_USER_HOME isolates the credentials file; explicit empty keys also
        # prevent inherited launchd credentials from configuring an APNs sender.
        for key in ("PHLOX_APNS_KEY_ID", "PHLOX_APNS_TEAM_ID", "PHLOX_APNS_AUTH_KEY_PEM", "PHLOX_APNS_AUTH_KEY_PATH"):
            self.environment[key] = ""

    def write_report(self):
        temporary = self.root / "ownership.writing"
        with temporary.open("w") as handle:
            json.dump(self.report, handle, indent=2)
        temporary.chmod(0o600)
        temporary.replace(self.root / "ownership.json")

    def remember(self, identity, role):
        self.owned[identity.pid] = identity
        self.report["processes"].append(dict(role=role, **asdict(identity)))
        self.write_report()

    def observe(self, event, **values):
        self.report["observations"].append(dict(event=event, **values))
        self.write_report()

    def run_helper(self, arguments, *, timeout, input_data=None, environment=None):
        process = subprocess.Popen(arguments, env=environment, stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        self.report["processes"].append(dict(role="transient-helper", pid=process.pid, executable=arguments[0]))
        self.write_report()
        try:
            output, diagnostics = process.communicate(input=input_data, timeout=timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            process.communicate()
            raise AssertionError("An owned test helper exceeded its timeout") from None
        return subprocess.CompletedProcess(arguments, process.returncode, output, diagnostics)

    def capture_quit_diagnostics(self, identity, phase="normal-quit"):
        if not same_process(identity):
            self.observe("quit-diagnostic-target-exited", pid=identity.pid)
            return
        sample_path = self.root / "logs" / f"{phase}-{identity.pid}.sample.txt"
        sampled = self.run_helper(["/usr/bin/sample", str(identity.pid), "3", "-file", str(sample_path)], timeout=15)
        (self.root / "logs" / f"{phase}-sample-diagnostics.log").write_bytes(sampled.stdout + sampled.stderr)
        process = self.run_helper(["/bin/ps", "-p", str(identity.pid), "-o",
            "pid,ppid,pgid,stat,%cpu,etime,comm"], timeout=5)
        (self.root / "logs" / f"{phase}-process.txt").write_bytes(process.stdout + process.stderr)
        self.observe(phase + "-diagnostics", pid=identity.pid, sampleExitCode=sampled.returncode,
                     samplePath=str(sample_path), psExitCode=process.returncode,
                     **accessibility_window_state(identity))

    def capture_runtime_timeout(self):
        identity = self.runtime_identity
        if not same_process(identity):
            self.observe("runtime-timeout-target-exited", pid=identity.pid)
            return
        try:
            sockets = self.run_helper(["/usr/sbin/lsof", "-nP", "-a", "-p",
                f"{identity.pid},{os.getpid()}", "-iTCP"], timeout=5)
            path = self.root / "logs/runtime-timeout-connections.txt"
            path.write_bytes(sockets.stdout + sockets.stderr)
            self.observe("runtime-timeout-sockets", runtimePID=identity.pid,
                harnessPID=os.getpid(), lsofExitCode=sockets.returncode, diagnostics=str(path))
            self.capture_quit_diagnostics(identity, phase="runtime-transport-timeout")
        except (OSError, AssertionError, RuntimeError) as error:
            # Preserve the transport failure and make diagnostic collection failure explicit.
            self.observe("runtime-timeout-diagnostic-failure", errorType=type(error).__name__)

    def start_gui(self, bundle, *, new_instance=True):
        executable = (bundle / "Contents/MacOS" / self.info["CFBundleExecutable"]).resolve()
        self.assertEqual(applications_at_executable(executable), [], "The isolated GUI copy is already running")
        log = self.root / "logs" / f"gui-{len(self.gui_processes)}.log"
        arguments = ["/usr/bin/open"] + (["-n"] if new_instance else [])
        arguments += ["-F", "-a", str(bundle), "--stdout", str(log), "--stderr", str(log)]
        keys = ["PHLOX_TEST_AGENT_BINARY_PATHS", "PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN",
            "PHLOX_TEST_EPHEMERAL_MOBILE_PORT", "PHLOX_DATA_DIR", "PHLOX_DEFAULTS_SUITE",
            "CFFIXED_USER_HOME", "CLAUDE_CONFIG_DIR", "PHLOX_APNS_KEY_ID", "PHLOX_APNS_TEAM_ID",
            "PHLOX_APNS_AUTH_KEY_PEM", "PHLOX_APNS_AUTH_KEY_PATH"]
        for key in keys:
            arguments.extend(["--env", key + "=" + self.environment[key]])
        launched_at = time.time()
        launched = self.run_helper(arguments, timeout=15)
        self.assertEqual(launched.returncode, 0, "LaunchServices rejected the isolated application launch")
        matches = eventually("the LaunchServices test GUI process identity",
            lambda: applications_at_executable(executable), timeout=15)
        self.assertEqual(len(matches), 1)
        identity = matches[0]
        self.assertGreaterEqual(identity.start_seconds + identity.start_microseconds / 1_000_000, launched_at - 1)
        self.assertTrue(same_process(identity))
        self.remember(identity, "gui")
        process = ObservedApplication(identity)
        self.gui_processes.append(process)
        self.observe("gui-launch", guiPID=identity.pid, executable=identity.executable, newInstance=new_instance)
        return process, identity

    def read_ready_discovery(self):
        path = self.store / "session-runtime/discovery.json"
        if not path.exists():
            return None
        discovery = private_json(path)
        if discovery["state"] == "failed":
            raise AssertionError("Runtime startup failed; inspect the isolated GUI log")
        return discovery if discovery["state"] == "ready" and discovery.get("desktopURL") else None

    def assert_gui_projection(self, identity, expected_text):
        latest = {}

        def visible():
            nonlocal latest
            latest = accessibility_window_state(identity, expected_text)
            return latest.get("expectedTextPresent")

        try:
            eventually("runtime session text in the reconnected GUI", visible, timeout=15)
        finally:
            path = self.root / "logs" / f"gui-projection-{identity.pid}.json"
            path.write_text(json.dumps(latest, indent=2))
            self.observe("gui-projection-observation", guiPID=identity.pid, expectedText=expected_text,
                         matched=latest.get("expectedTextPresent", False), diagnostics=str(path))

    def fake_state(self, role, pid=None):
        pid = pid if pid is not None else self.fixture_pids.get(role)
        for path in (self.root / "fake-state").glob("*.json"):
            state = json.loads(path.read_text())
            if state["role"] == role and (pid is None or state["pid"] == pid):
                if role == "structured" and "thread/start" not in state["methods"] and pid is None:
                    continue
                self.fixture_pids.setdefault(role, state["pid"])
                return state
        return None

    def get_session(self, identifier, kind):
        return session_value(self.api.snapshot(), identifier, kind)

    def session_command(self, session, command):
        return dict(session={"_0": session["id"], "_1": session["executionID"], "_2": command})

    def spawn(self, provider, backend):
        request = dict(ref=provider, backend=backend, launchContext="interactive", extraEnv={},
            workingDirectoryOverride=str(self.root / "project"), isolationOverride=False,
            worktreeStartPoint={"head": {}}, keepsRowOnLaunchFailure=False)
        return self.api.command({"spawn": {"_0": request}})["sessionID"]["_0"]

    def pending_question(self, identifier):
        session = self.get_session(identifier, "chat")
        for item in session["transcript"]:
            value = item.get("userQuestion")
            if value and value["state"] == "pending":
                return value
        return None

    def assert_existing_hook_and_control(self, pty_id, discovery, app_snapshot, dispatcher):
        endpoint = urllib.parse.urlsplit(discovery["controlURL"])
        self.assertEqual(endpoint.hostname, "127.0.0.1")
        self.assertIsNotNone(shutil.which("jq", path=app_snapshot["pathEnvironment"]),
                             "The existing hook dispatcher requires jq")
        # Session credentials intentionally never enter persisted sessions or this harness.
        # The retained PTY child exercises its own original inherited credentials.
        (self.root / "hook-challenge.json").write_text(json.dumps(dict(dispatcher=str(dispatcher))))
        turn_id = "runtime-hook:" + str(uuid.uuid4())
        self.api.command(self.session_command(self.get_session(pty_id, "pty"), {"input": {"_0":
            base64.b64encode((turn_id + "\r").encode()).decode()}}))
        result = eventually("the original child hook and Control challenge", lambda:
            next((item for item in self.fake_state("pty").get("hookChallenges", [])
                  if item["turnID"] == turn_id), None))
        self.assertEqual(result.get("controlStatus"), 200,
                         "The original session Control API credential stopped working")
        self.assertEqual(result.get("hookExitCode"), 0, "The retained hook dispatcher could not execute")
        self.assertNotIn("error", result, "The child challenge failed")
        eventually("hook delivery through the retained dispatcher", lambda:
            self.get_session(pty_id, "pty").get("activeTurnId") == turn_id)
        self.observe("retained-hook-and-control", authenticatedControl=True, hookDelivered=True)

    def assert_continues(self, pty_id, chat_id, pty_identity, chat_identity, phase):
        before_pty = self.fake_state("pty", pty_identity.pid)["heartbeat"]
        before_chat = self.fake_state("structured", chat_identity.pid)["heartbeat"]
        before_stream = self.get_session(chat_id, "chat")["transcriptRevision"]
        before_output = self.get_session(pty_id, "pty")["lastOutputAt"]
        eventually("PTY heartbeat after " + phase,
                   lambda: self.fake_state("pty", pty_identity.pid)["heartbeat"] > before_pty + 2)
        eventually("structured heartbeat after " + phase,
                   lambda: self.fake_state("structured", chat_identity.pid)["heartbeat"] > before_chat + 2)
        eventually("PTY consumer progress after " + phase,
                   lambda: self.get_session(pty_id, "pty")["lastOutputAt"] > before_output)
        eventually("structured transcript progress after " + phase,
                   lambda: self.get_session(chat_id, "chat")["transcriptRevision"] > before_stream)
        self.assertTrue(same_process(self.runtime_identity), "Runtime identity changed")
        self.assertTrue(same_process(pty_identity), "PTY child identity changed")
        self.assertTrue(same_process(chat_identity), "Structured child identity changed")
        self.observe(phase, runtimePID=self.runtime_identity.pid, ptyPID=pty_identity.pid, chatPID=chat_identity.pid,
            ptyHeartbeatBefore=before_pty, ptyHeartbeatAfter=self.fake_state("pty", pty_identity.pid)["heartbeat"],
            structuredHeartbeatBefore=before_chat,
            structuredHeartbeatAfter=self.fake_state("structured", chat_identity.pid)["heartbeat"],
            transcriptRevisionBefore=before_stream,
            transcriptRevisionAfter=self.get_session(chat_id, "chat")["transcriptRevision"])

    def test_pty_and_codex_survive_gui_lifecycle_until_explicit_stop(self):
        gui, gui_identity = self.start_gui(self.original_app)
        self.assertIsNone(gui.poll(), "The GUI exited during initialization")
        try:
            discovery = eventually("private ready runtime discovery", self.read_ready_discovery, timeout=90)
        except AssertionError:
            self.capture_quit_diagnostics(gui_identity, phase="startup-not-ready")
            raise
        self.assertEqual(file_url(discovery["storeURL"]), self.store.resolve())
        current = process_info(discovery["pid"])
        self.assertIsNotNone(current)
        runtime_identity = current[0]
        cache = self.store / "session-runtime-bundles"
        self.assertTrue(Path(runtime_identity.executable).is_relative_to(cache))
        self.runtime_identity = runtime_identity
        self.remember(self.runtime_identity, "runtime")
        self.assertNotEqual(self.runtime_identity.pid, gui.pid)
        assets = file_url(discovery["assetsRoot"])
        self.assertTrue(assets.is_relative_to(cache), "Runtime must use the immutable cached bundle assets")
        dispatcher = assets / "hook-dispatcher.sh"
        dispatcher_digest = hashlib.sha256(dispatcher.read_bytes()).hexdigest()
        self.api = RuntimeAPI(self.store, discovery, self.observe, self.capture_runtime_timeout)
        handshake = self.api.request("GET", "/handshake")[1]
        self.assertEqual(handshake["generation"], discovery["generation"])
        self.assertEqual(handshake["protocolVersion"], 1)
        app_snapshot = self.api.request("GET", "/application-snapshot")[1]
        self.assertEqual(app_snapshot["claudeBinaryPath"], self.agents["claudeCode"],
                         "Fake binary override was not applied; real CLI execution is forbidden")
        self.assertTrue(Path(app_snapshot["hookDispatcherPath"]).is_relative_to(cache))
        pty_id, chat_id = self.spawn("claudeCode", "pty"), self.spawn("codex", "appServer")
        pty_state = eventually("the fake PTY child", lambda: self.fake_state("pty"))
        chat_state = eventually("the fake Codex child", lambda: self.fake_state("structured"))
        pty_process = process_info(pty_state["pid"])
        chat_process = process_info(chat_state["pid"])
        self.assertIsNotNone(pty_process)
        self.assertIsNotNone(chat_process)
        self.assertEqual(pty_process[1], self.runtime_identity.pid)
        self.assertEqual(chat_process[1], self.runtime_identity.pid)
        pty_identity = pty_process[0]
        chat_identity = chat_process[0]
        for identity, role, state in ((pty_identity, "pty", pty_state), (chat_identity, "structured", chat_state)):
            self.assertEqual(state["parent"], self.runtime_identity.pid, "Child is not owned by this runtime")
            self.remember(identity, role)
        eventually("a terminal DSR response", lambda: self.fake_state("pty")["dsrResponses"] > 0)
        eventually("a terminal DA1 response", lambda: self.fake_state("pty")["daResponses"] > 0)
        pty_session = self.get_session(pty_id, "pty")
        marker = "runtime-input:" + str(uuid.uuid4())
        self.api.command(self.session_command(pty_session, {"input": {"_0":
            base64.b64encode((marker + "\r").encode()).decode()}}))
        eventually("PTY input echo in exported terminal cells", lambda:
            "runtime-echo:" + marker in terminal_text(self.get_session(pty_id, "pty")))
        chat = self.get_session(chat_id, "chat")
        self.api.command(self.session_command(chat, {"send": dict(text="runtime-test", submit=True, attachments=[])}))
        approval = eventually("a retained approval", lambda: self.get_session(chat_id, "chat")["pendingApprovals"])
        approval_id = approval[0]["id"]
        if OPTIONS.interactive_ui_smoke:
            self.assert_interactive_ui_replies(gui_identity, chat_id, approval_id)
            return
        if OPTIONS.inspection_pause_seconds:
            self.observe("inspection-ready", guiPID=gui_identity.pid, guiExecutable=gui_identity.executable,
                         pauseSeconds=OPTIONS.inspection_pause_seconds)
            deadline = time.monotonic() + OPTIONS.inspection_pause_seconds
            while time.monotonic() < deadline:
                time.sleep(min(0.2, max(0, deadline - time.monotonic())))
        try:
            quit_result = quit_application(gui_identity, wait_for_reply=OPTIONS.quit_reply_mode == "wait-reply")
            self.observe("normal-quit-apple-event", **quit_result)
            self.assertEqual(quit_result["sendStatus"], 0, "Normal quit AppleEvent did not receive a reply")
            self.assertIn(quit_result.get("replyError"), (None, 0), "Normal quit AppleEvent was rejected by the GUI")
            exit_code = gui.wait(timeout=30)
            self.observe("normal-quit-exit", kernelExitCode=exit_code)
            self.assertEqual(exit_code, 0, "Normal quit did not exit successfully")
        except (AssertionError, subprocess.TimeoutExpired):
            self.capture_quit_diagnostics(gui_identity)
            raise
        self.assert_continues(pty_id, chat_id, pty_identity, chat_identity, "normal-gui-quit")
        self.assertEqual(self.get_session(chat_id, "chat")["pendingApprovals"][0]["id"], approval_id)
        self.assertEqual(self.fake_state("structured")["approvalReplies"], [])
        gui, gui_identity = self.start_gui(self.original_app, new_instance=False)
        self.assertIsNone(gui.poll(), "The reconnected GUI exited during initialization")
        self.assertEqual(self.read_ready_discovery()["generation"], discovery["generation"])
        # The approval's working-directory label is exposed by SwiftUI AX; the
        # user transcript text is not. It uniquely identifies this run's request.
        self.assert_gui_projection(gui_identity, str(self.root))
        self.observe("normal-open-gui-projection-visible", guiPID=gui_identity.pid,
                     approvalID=approval_id, workingDirectory=str(self.root))
        self.assertEqual(self.get_session(chat_id, "chat")["pendingApprovals"][0]["id"], approval_id)
        approval_command = self.session_command(chat, {"approval": {"_0": approval_id, "decision": "accept"}})
        approval_operation = self.api.operation(approval_command)
        first = self.api.request("POST", "/command", approval_operation)
        self.assertEqual(self.api.request("POST", "/command", approval_operation), first)
        eventually("one approval response at the original child", lambda:
            len(self.fake_state("structured")["approvalReplies"]) == 1)
        self.assertEqual(self.fake_state("structured")["approvalReplies"][0], {"decision": "accept"})
        self.api.request("POST", "/command", self.api.operation(approval_command), accepted=(400,))
        question = eventually("a retained user question", lambda: self.pending_question(chat_id))
        question_id = question["requestId"]
        send_owned_signal(gui_identity, signal.SIGKILL)
        self.assertEqual(gui.wait(timeout=10), -signal.SIGKILL)
        self.assert_continues(pty_id, chat_id, pty_identity, chat_identity, "forced-gui-exit")
        self.assertEqual(self.pending_question(chat_id)["requestId"], question_id)
        self.assertEqual(self.fake_state("structured")["questionReplies"], [])
        replacement = self.root / "replacement/Phlox.app"
        shutil.copytree(self.original_app, replacement, symlinks=True)
        self.original_app.rename(self.original_app.with_name("RetiredPhlox.app"))
        gui, gui_identity = self.start_gui(replacement)
        self.assertEqual(self.read_ready_discovery()["pid"], self.runtime_identity.pid)
        self.assertEqual(self.read_ready_discovery()["generation"], discovery["generation"])
        self.assertEqual(hashlib.sha256(dispatcher.read_bytes()).hexdigest(), dispatcher_digest)
        self.assert_continues(pty_id, chat_id, pty_identity, chat_identity, "gui-bundle-path-replacement")
        self.assertIsNone(gui.poll(), "The replacement GUI exited during initialization")
        self.assert_existing_hook_and_control(pty_id, discovery, app_snapshot, dispatcher)
        self.assertEqual(self.pending_question(chat_id)["requestId"], question_id)
        additional_completed = False
        if OPTIONS.snapshot_soak_seconds:
            self.assert_claude_and_cursor_lifecycle(gui, gui_identity, replacement, discovery,
                other_sessions=((pty_id, "pty", pty_identity), (chat_id, "chat", chat_identity)))
            additional_completed = True
            self.assertEqual(self.pending_question(chat_id)["requestId"], question_id)
        question_command = self.session_command(chat, {"question": dict(
            requestId=question_id, answers={"runtime-choice": ["Continue"]})})
        question_operation = self.api.operation(question_command)
        answer = self.api.request("POST", "/command", question_operation)
        self.assertEqual(self.api.request("POST", "/command", question_operation), answer)
        eventually("one question response at the original child", lambda:
            len(self.fake_state("structured")["questionReplies"]) == 1)
        self.assertEqual(self.fake_state("structured")["questionReplies"][0],
            {"answers": {"runtime-choice": {"answers": ["Continue"]}}})
        self.assertEqual(self.api.command(question_command), {"session": {"_0": {"bool": {"_0": False}}}})
        self.assertEqual(len(self.fake_state("structured")["approvalReplies"]), 1)
        self.assertEqual(len(self.fake_state("structured")["questionReplies"]), 1)
        self.observe("same-request-answered-once", approvalID=approval_id, questionID=question_id,
                     approvalReplyCount=1, questionReplyCount=1)
        self.api.command(self.session_command(self.get_session(pty_id, "pty"), {"terminate": {}}))
        eventually("the explicitly stopped PTY child to exit", lambda: not same_process(pty_identity))
        self.assertTrue(same_process(chat_identity), "Stopping PTY also stopped structured execution")
        self.assertTrue(same_process(self.runtime_identity), "Stopping a session stopped the runtime")
        self.api.command(self.session_command(self.get_session(chat_id, "chat"), {"terminate": {}}))
        eventually("the explicitly stopped structured child to exit", lambda: not same_process(chat_identity))
        self.assertTrue(same_process(self.runtime_identity))
        self.observe("explicit-session-stops", sameRuntime=True, ptyStopped=True, structuredStopped=True)
        if OPTIONS.include_additional_structured and not additional_completed:
            self.assert_claude_and_cursor_lifecycle(gui, gui_identity, replacement, discovery)

    def provider_state(self, provider, pid=None):
        for path in (self.root / "fake-state").glob("*.json"):
            state = json.loads(path.read_text())
            if (state["provider"] == provider and state["role"] == "structured"
                    and state.get("active") and (pid is None or state["pid"] == pid)):
                return state
        return None

    def assert_claude_and_cursor_lifecycle(self, gui, gui_identity, bundle, discovery, other_sessions=()):
        sessions, identities = {}, {}
        for provider in ("claudeCode", "cursor"):
            identifier = self.spawn(provider, "appServer")
            sessions[provider] = identifier
            if provider == "claudeCode":
                self.api.command(self.session_command(self.get_session(identifier, "chat"), {
                    "spawnPermission": {"_0": "manual"}}))
                eventually("Claude manual permission mode", lambda:
                    self.get_session(identifier, "chat").get("selectedPermissionProfile") == "manual")
            self.api.command(self.session_command(self.get_session(identifier, "chat"), {
                "send": dict(text="runtime-additional-" + provider, submit=True, attachments=[])}))
            state = eventually("the active " + provider + " fixture", lambda: self.provider_state(provider))
            process = process_info(state["pid"])
            self.assertIsNotNone(process)
            self.assertEqual(process[1], self.runtime_identity.pid)
            identities[provider] = process[0]
            self.remember(process[0], provider + "-structured")
        claude_state = self.provider_state("claudeCode", identities["claudeCode"].pid)
        controls = Path(claude_state["controlDirectory"])
        self.assertTrue(controls.is_relative_to(self.root / "fake-control"))
        (controls / "turn-1.approval").touch()
        claude_id = sessions["claudeCode"]
        approval = eventually("the Claude tool permission question", lambda: self.pending_question(claude_id))
        approval_id = approval["requestId"]
        permission_question = approval["questions"][0]
        self.assertIsNotNone(permission_question.get("permission"))
        answer_key = permission_question.get("id") or permission_question["question"]
        if OPTIONS.snapshot_soak_seconds:
            self.assert_snapshot_soak(gui_identity, identities, other_sessions)

        def continues(phase):
            before = {provider: self.provider_state(provider, identity.pid) for provider, identity in identities.items()}
            for provider, identity in identities.items():
                eventually(provider + " heartbeat after " + phase, lambda provider=provider, identity=identity:
                    self.provider_state(provider, identity.pid)["heartbeat"] > before[provider]["heartbeat"] + 2)
                eventually(provider + " output after " + phase, lambda provider=provider, identity=identity:
                    self.provider_state(provider, identity.pid)["emittedLines"] > before[provider]["emittedLines"])
                self.assertTrue(same_process(identity))
            # Claude emits tool_progress while approval is pending; its real decoder
            # intentionally ignores that event. Cursor publishes its stream at turn end.
            self.assertTrue(same_process(self.runtime_identity))
            self.assertEqual(self.pending_question(claude_id)["requestId"], approval_id)
            self.assertEqual(self.provider_state("claudeCode", identities["claudeCode"].pid)["approvalReplies"], [])
            self.observe(phase, runtimePID=self.runtime_identity.pid,
                providers={provider: dict(pid=identity.pid,
                    heartbeatBefore=before[provider]["heartbeat"],
                    heartbeatAfter=self.provider_state(provider, identity.pid)["heartbeat"],
                    outputBefore=before[provider]["emittedLines"],
                    outputAfter=self.provider_state(provider, identity.pid)["emittedLines"])
                    for provider, identity in identities.items()}, approvalID=approval_id)

        quit_result = quit_application(gui_identity)
        self.observe("additional-normal-quit-apple-event", **quit_result)
        self.assertEqual(quit_result["sendStatus"], 0)
        self.assertEqual(quit_result.get("replyError"), 0)
        self.assertEqual(gui.wait(timeout=30), 0)
        continues("additional-normal-gui-quit")
        gui, gui_identity = self.start_gui(bundle)
        self.assertEqual(self.read_ready_discovery()["generation"], discovery["generation"])
        self.assertIsNone(gui.poll())
        # The most recently spawned session is selected on this fresh GUI.
        expected_label = "runtime-additional-cursor"
        self.assert_gui_projection(gui_identity, expected_label)
        self.observe("additional-gui-projection-visible", guiPID=gui_identity.pid, text=expected_label)
        send_owned_signal(gui_identity, signal.SIGKILL)
        self.assertEqual(gui.wait(timeout=10), -signal.SIGKILL)
        continues("additional-forced-gui-exit")
        replacement = self.root / "additional-replacement/Phlox.app"
        shutil.copytree(bundle, replacement, symlinks=True)
        bundle.rename(bundle.with_name("RetiredPhlox.app"))
        gui, gui_identity = self.start_gui(replacement)
        self.assertEqual(self.read_ready_discovery()["generation"], discovery["generation"])
        continues("additional-gui-bundle-path-replacement")
        self.assertIsNone(gui.poll())
        command = self.session_command(self.get_session(claude_id, "chat"), {
            "question": dict(requestId=approval_id, answers={answer_key: ["Allow"]})})
        operation = self.api.operation(command)
        first = self.api.request("POST", "/command", operation)
        self.assertEqual(self.api.request("POST", "/command", operation), first)
        eventually("one Claude approval reply", lambda:
            len(self.provider_state("claudeCode", identities["claudeCode"].pid)["approvalReplies"]) == 1)
        self.assertEqual(self.api.command(command), {"session": {"_0": {"bool": {"_0": False}}}})
        self.assertEqual(self.provider_state("claudeCode", identities["claudeCode"].pid)["duplicateReplies"], [])
        revision = self.get_session(claude_id, "chat")["transcriptRevision"]
        eventually("Claude transcript progress after the retained approval", lambda:
            self.get_session(claude_id, "chat")["transcriptRevision"] > revision)
        for provider, identifier in sessions.items():
            self.api.command(self.session_command(self.get_session(identifier, "chat"), {"terminate": {}}))
            eventually("explicit " + provider + " stop", lambda provider=provider:
                not same_process(identities[provider]))
            self.assertTrue(same_process(self.runtime_identity))
        self.observe("additional-explicit-session-stops", sameRuntime=True,
                     claudeStopped=True, cursorStopped=True, approvalReplyCount=1)

    def assert_snapshot_soak(self, gui_identity, identities, other_sessions):
        self.assertEqual(len(other_sessions), 2, "The soak requires all four execution processes")
        targets = list(identities.values()) + [entry[2] for entry in other_sessions]
        before = {identity.pid: json.loads((self.root / "fake-state" / f"{identity.pid}.json").read_text())
                  for identity in targets}
        busy_before = dict(self.api.backpressure_counts)
        counts = {path: 0 for path in ("/snapshot", "/application-snapshot")}
        maximum_latency = {path: 0.0 for path in counts}
        total_latency = {path: 0.0 for path in counts}
        started = time.monotonic()
        deadline = started + OPTIONS.snapshot_soak_seconds
        self.observe("snapshot-soak-start", durationSeconds=OPTIONS.snapshot_soak_seconds,
                     guiPID=gui_identity.pid, childPIDs=[identity.pid for identity in targets])
        try:
            while time.monotonic() < deadline:
                cycle_start = time.monotonic()
                for path in counts:
                    request_start = time.monotonic()
                    self.api.request("GET", path)
                    elapsed = time.monotonic() - request_start
                    counts[path] += 1
                    maximum_latency[path] = max(maximum_latency[path], elapsed)
                    total_latency[path] += elapsed
                self.assertTrue(same_process(gui_identity))
                self.assertTrue(same_process(self.runtime_identity))
                self.assertTrue(all(same_process(identity) for identity in targets))
                delay = min(0.1 - (time.monotonic() - cycle_start), deadline - time.monotonic())
                if delay > 0:
                    time.sleep(delay)
            for identity in targets:
                after = json.loads((self.root / "fake-state" / f"{identity.pid}.json").read_text())
                self.assertGreater(after["heartbeat"], before[identity.pid]["heartbeat"] + 2)
                if "emittedLines" in after:
                    self.assertGreater(after["emittedLines"], before[identity.pid]["emittedLines"])
        finally:
            self.observe("snapshot-soak-result", elapsedSeconds=time.monotonic() - started,
                successfulRequests=counts, maximumLatencySeconds=maximum_latency, totalLatencySeconds=total_latency,
                backpressure503={route: count - busy_before.get(route, 0)
                    for route, count in self.api.backpressure_counts.items()})

    def assert_interactive_ui_replies(self, gui_identity, chat_id, approval_id):
        self.observe("ui-approval-ready", guiPID=gui_identity.pid, guiExecutable=gui_identity.executable,
                     requestID=approval_id, waitSeconds=120)
        eventually("a real GUI approval response", lambda:
            len(self.fake_state("structured")["approvalReplies"]) == 1, timeout=120)
        self.assertEqual(self.get_session(chat_id, "chat")["pendingApprovals"], [])
        self.assertEqual(self.fake_state("structured")["approvalReplies"][0], {"decision": "accept"})
        question = eventually("the GUI question", lambda: self.pending_question(chat_id))
        self.observe("ui-question-ready", guiPID=gui_identity.pid, guiExecutable=gui_identity.executable,
                     requestID=question["requestId"], waitSeconds=120)
        eventually("a real GUI question response", lambda:
            len(self.fake_state("structured")["questionReplies"]) == 1, timeout=120)
        self.assertIsNone(self.pending_question(chat_id))
        self.assertEqual(self.fake_state("structured")["questionReplies"][0],
            {"answers": {"runtime-choice": {"answers": ["Continue"]}}})
        self.assertEqual(len(self.fake_state("structured")["approvalReplies"]), 1)
        self.assertEqual(len(self.fake_state("structured")["questionReplies"]), 1)
        self.observe("ui-replies-delivered-once", approvalID=approval_id,
                     questionID=question["requestId"], approvalReplyCount=1, questionReplyCount=1)

    def cleanup_owned_processes(self):
        errors = []
        if hasattr(self, "runtime_identity"):
            runtime = self.runtime_identity
        else:
            runtime = None
            if hasattr(self, "store"):
                try:
                    path = self.store / "session-runtime/discovery.json"
                    discovery = private_json(path) if path.exists() else None
                    if discovery:
                        current = process_info(discovery["pid"])
                        if current and Path(current[0].executable).is_relative_to(self.store / "session-runtime-bundles"):
                            runtime = current[0]
                            self.remember(runtime, "runtime-cleanup")
                except (OSError, ValueError, AssertionError, RuntimeError) as error:
                    errors.append("Runtime cleanup discovery failed (" + type(error).__name__ + ")")
        identities = list(self.owned.values())
        ordered = [identity for identity in identities if identity != runtime]
        if runtime is not None:
            ordered.append(runtime)
        for identity in ordered:
            try:
                sent = send_owned_signal(identity, signal.SIGTERM)
                if sent:
                    eventually("owned process cleanup", lambda: not same_process(identity), timeout=15)
                self.report["cleanup"].append(dict(pid=identity.pid, exited=not same_process(identity)))
            except (OSError, AssertionError, RuntimeError) as error:
                errors.append(f"PID {identity.pid} cleanup failed ({type(error).__name__})")
                if same_process(identity):
                    try:
                        send_owned_signal(identity, signal.SIGKILL)
                        eventually("owned process forced cleanup", lambda: not same_process(identity), timeout=10)
                    except (OSError, AssertionError, RuntimeError) as forced_error:
                        errors.append(f"PID {identity.pid} forced cleanup failed ({type(forced_error).__name__})")
        for process in self.gui_processes:
            if process.poll() is not None:
                process.wait()
            process.close()
        if self.owned:
            residual = self.run_helper(["/bin/ps", "-p", ",".join(str(pid) for pid in self.owned),
                                       "-o", "pid,ppid,stat,comm"], timeout=5)
            (self.root / "logs/residual-processes.txt").write_bytes(residual.stdout + residual.stderr)
            self.report["residualPsExitCode"] = residual.returncode
            self.report["ownedResidualPIDs"] = [pid for pid, identity in self.owned.items() if same_process(identity)]
            if self.report["ownedResidualPIDs"]:
                errors.append("Owned verification processes remain after cleanup")
        self.write_report()
        self.assertEqual(errors, [], "Cleanup needed forced termination; see ownership.json")


def parse_options():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--quit-reply-mode", choices=["wait-reply", "no-reply"], default="wait-reply")
    parser.add_argument("--inspection-pause-seconds", type=float, default=0)
    parser.add_argument("--include-additional-structured", action="store_true")
    parser.add_argument("--interactive-ui-smoke", action="store_true")
    parser.add_argument("--snapshot-soak-seconds", type=float, default=0)
    arguments, remaining = parser.parse_known_args()
    verification = (PROJECT / ".verification").resolve()
    arguments.app = arguments.app.resolve()
    arguments.work_dir = arguments.work_dir.resolve()
    for label, path in (("app", arguments.app), ("work-dir", arguments.work_dir)):
        if path == verification or not path.is_relative_to(verification):
            parser.error(f"--{label} must be inside this worktree's .verification directory")
    if not (arguments.app / "Contents/Info.plist").is_file():
        parser.error("--app must point to a built .app bundle")
    if arguments.app.is_relative_to(arguments.work_dir) or arguments.work_dir.is_relative_to(arguments.app):
        parser.error("--app and --work-dir must be separate owned paths")
    if sys.platform != "darwin":
        parser.error("This lifecycle acceptance test requires macOS")
    if not 0 <= arguments.inspection_pause_seconds <= 60:
        parser.error("--inspection-pause-seconds must be between 0 and 60")
    if arguments.interactive_ui_smoke and (arguments.include_additional_structured or arguments.inspection_pause_seconds):
        parser.error("--interactive-ui-smoke requires its own run without other scenario options")
    if not 0 <= arguments.snapshot_soak_seconds <= 120:
        parser.error("--snapshot-soak-seconds must be between 0 and 120")
    if arguments.snapshot_soak_seconds and not arguments.include_additional_structured:
        parser.error("--snapshot-soak-seconds requires --include-additional-structured")
    arguments.run_id = str(uuid.uuid4())
    return arguments, remaining


if __name__ == "__main__":
    OPTIONS, unittest_arguments = parse_options()
    test_output = io.StringIO()
    program = unittest.main(argv=[sys.argv[0]] + unittest_arguments, exit=False,
        testRunner=unittest.TextTestRunner(stream=test_output, verbosity=2))
    result_log = test_output.getvalue()
    sys.stderr.write(result_log)
    ownership = OPTIONS.work_dir / "ownership.json"
    if ownership.exists() and json.loads(ownership.read_text()).get("run") == OPTIONS.run_id:
        (OPTIONS.work_dir / "logs/test-result.log").write_text(result_log)
    sys.exit(0 if program.result.wasSuccessful() else 1)
