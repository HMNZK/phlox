#!/usr/bin/env python3
"""Project verification entry points. Only measured results may satisfy a gate."""
import argparse
import datetime as dt
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
import xml.parsers.expat as expat
import zipfile


ROOT = Path(__file__).resolve().parents[2]
SCENARIOS = "release/verification-scenarios.json"
REVIEWS = "release/verification-reviews.json"
RECORDS = "release/verification-records.json"
MACOS_PACKAGES = "APNsClient AgentConfigKit AgentDomain AppBootstrap ClaudeAgentKit CodexAppServerKit ControlServer CursorAgentKit DashboardFeature DesignSystem HookServer LocalHTTPServer MessageStore MobileProxy PTYKit SessionFeature SimulatorBridgeKit StructuredChatKit TerminalUI".split()
KNOWN_ISSUE = "DashboardFeatureTests.GitHistoryWorkflowTests/GTWRegression_改名前の名前を再利用しても利用順を混同しない()"
FAKE_TESTS = {
    "E2EFakeAgentSmokeTests": ["fakeAgent_inputEchoThenSilenceReachesIdleCompletion", "fakeAgent_exitAfterZeroCompletesWithoutStuckRunning"],
    "E2ESessionLifecycleTests": ["sessionLifecycle_hookDrivenSendAndStopCompletion", "sessionLifecycle_exitAfterOneRoundTripThenCompletes", "sessionLifecycle_killTerminatesChildProcess"],
    "E2EControlServerTests": [
        "s4_phloxListSendRead",
        "s4_invalidTokenAndMissingRecipient",
        "s5_apiSpawnRecordsParentAndKillParentEndsChild",
    ],
    "E2EPersistenceTests": ["s2_restartRestoresSessionNamesAndProjectPlacement", "s2_corruptSessionsJSONStartsWithEmptyState", "s6_projectPlacementSurvivesRestart", "s9a_bypassTogglesClaudeHooksSettingsFileSelectionAndContent"],
    "E2ERealPTYTests": ["realPTY_deterministic_inputEchoThenSilenceReachesIdleCompletion"],
}
OPTIONAL_SKIPS = {
    "ClaudeAgentKitTests.ClaudeUsageLiveTests",
    "ClaudeAgentKitTests.ClaudeUsageLiveTests/conversationDeliversUsageWithoutGetUsage()",
    "ClaudeAgentKitTests.ClaudeUsageLiveTests/dedicatedThreeCyclesWithoutConversation()",
    "CodexAppServerKitTests.CodexAppServerE2ETests/initializeThreadTurnReadAndResume()",
    "CodexAppServerKitTests.CodexAppServerE2ETests/threadStartWithExplicitSources()",
    "CodexAppServerKitTests.CodexAppServerE2ETests/updateThreadSettingsEmitsNotification()",
    "DashboardFeatureTests.LargeFilePerformanceTests/longLineKeepsPreparedGlyphsAfterChanges(change:)",
    "DashboardFeatureTests.LargeFilePerformanceTests/measureDocumentAndSwiftUIUpdates()",
    "DashboardFeatureTests.RealClaudeReadinessE2ETests/realClaude_inputAcceptedAfterSessionStartHook()",
    "DashboardFeatureTests.ThemeRenderingTests/CodeSyntaxPerformanceTests/measureEditorInputAndHighlightCompletion()",
} | {f"DashboardFeatureTests.{suite}/{name}()" for suite, names in FAKE_TESTS.items() for name in names}
OPTIONAL_XCTEST_SKIP = "-[DashboardFeatureTests.MarkdownScrollPerformanceTests testScrollFrames]"


class GateError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise GateError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()


def now():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def git(*args, root=ROOT):
    return subprocess.check_output(["git", *args], cwd=root).decode().strip()


def session_name():
    value = Path(os.environ["GITFLOW_VERIFICATION_DIR"]).name if os.environ.get("GITFLOW_VERIFICATION_DIR") else git("branch", "--show-current") or git("rev-parse", "--short=12", "HEAD")
    safe = re.sub(r"[^A-Za-z0-9_.-]", "-", value)
    if safe != value:
        value = safe + "-" + digest(value.encode())[:8]
    require(re.fullmatch(r"[A-Za-z0-9_.-]+", value) and value not in (".", ".."), "Invalid verification session")
    return value


def read_json(path):
    with Path(path).open() as stream:
        value = json.load(stream)
    require(isinstance(value, dict) and value.get("schemaVersion") == 1, f"Unsupported schema: {path}")
    return value


def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def timestamp(value):
    require(isinstance(value, str), "Missing timestamp")
    parsed = dt.datetime.fromisoformat(value)
    require(parsed.tzinfo is not None, "Timestamp requires a timezone")
    return parsed


def text_field(obj, key):
    require(isinstance(obj.get(key), str) and obj[key].strip(), f"Missing {key}")
    return obj[key]


def excluded_input(path):
    # These documents are never compilation inputs; scenario content is checked separately.
    return (path in (SCENARIOS, REVIEWS, RECORDS)
            or (path.startswith(("macos/docs/", "ios/docs/")) and path.endswith((".md", ".html")))
            or ("/" not in path and path.startswith("README") and path.endswith(".md"))
            or (path.startswith("release/notes-") and path.endswith(".md")))


def input_manifest(root=ROOT, oid=None):
    entries = []
    if oid:
        rows = subprocess.check_output(["git", "ls-tree", "-rz", oid], cwd=root).split(b"\0")
        for row in rows:
            if not row:
                continue
            info, name = row.split(b"\t", 1)
            mode, kind, blob = info.decode().split()
            path = os.fsdecode(name)
            if excluded_input(path) or path == "site/appcast.xml":
                continue
            require(kind == "blob", f"Unresolved build input: {path}")
            data = subprocess.check_output(["git", "cat-file", "blob", blob], cwd=root)
            entries.append({"path": path, "mode": mode, "sha256": digest(data)})
    else:
        rows = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=root).split(b"\0")
        for name in sorted(set(rows)):
            if not name:
                continue
            path = os.fsdecode(name)
            if excluded_input(path) or path == "site/appcast.xml":
                continue
            require(not Path(path).name.startswith(".env"), f"Forbidden build input: {path}")
            file = root / path
            require(file.exists() or file.is_symlink(), f"Missing build input: {path}")
            if file.is_symlink():
                data, mode = os.fsencode(os.readlink(file)), "120000"
                require(file.resolve().is_relative_to(root.resolve()), f"External symlink: {path}")
            else:
                require(file.is_file(), f"Unresolved build input: {path}")
                data, mode = file.read_bytes(), "100755" if file.stat().st_mode & 0o111 else "100644"
            entries.append({"path": path, "mode": mode, "sha256": digest(data)})
    entries.sort(key=lambda entry: entry["path"])
    return {"files": entries, "sha256": digest(canonical(entries))}


def git_content(root, oid, path):
    result = subprocess.run(["git", "show", f"{oid}:{path}"], cwd=root, capture_output=True)
    if result.returncode:
        require(not git("ls-tree", oid, "--", path, root=root), f"Cannot read {oid}:{path}")
        return None
    return result.stdout


def normalized_document(document):
    document = re.sub(r"\A---\n.*?\n---\n", "", document, count=1, flags=re.S)
    return " ".join(re.sub(r"\[([^]]+)\]\([^)]+\)", r"\1", document).split())


def requirement_hash(scenario, document, root):
    if document is None:
        return None
    if scenario["method"] != "physical-device":
        return digest(normalized_document(document).encode())
    ids = scenario.get("requirementIDs", [scenario["requirement"].split("#", 1)[1]])
    if any(not re.search(r"^\|\s*" + re.escape(ident) + r"\s*\|", document, re.M) for ident in ids):
        return None
    return scenario_hash(scenario, root, document)


def normalized_changes(base, target, root=ROOT):
    paths = git("diff", "--name-only", "-z", base, target, root=root).split("\0")
    catalog_data = git_content(root, target, SCENARIOS)
    scenarios = json.loads(catalog_data)["scenarios"] if catalog_data else []
    changes = []
    for path in sorted(paths):
        if not path or path in (REVIEWS, RECORDS):
            continue
        mapped = [s for s in scenarios if s["requirement"].split("#")[0] == path]
        if excluded_input(path) and path != SCENARIOS and not mapped:
            continue
        sides = []
        for oid in (base, target):
            result = subprocess.run(["git", "ls-tree", oid, "--", path], cwd=root, capture_output=True, text=True, check=True)
            if not result.stdout:
                sides.append(None)
            else:
                mode, kind, blob = result.stdout.split("\t", 1)[0].split()
                require(kind == "blob", f"Unresolved diff input: {path}")
                data = subprocess.check_output(["git", "cat-file", "blob", blob], cwd=root)
                if mapped:
                    values = [requirement_hash(s, data.decode(), root) for s in mapped]
                    data = canonical(values)
                elif path.endswith(".json"):
                    data = canonical(json.loads(data))
                sides.append({"mode": mode, "sha256": digest(data)})
        if sides[0] != sides[1]:
            changes.append({"path": path, "before": sides[0], "after": sides[1]})
    return changes


def diff_hash(base, target, root=ROOT):
    return digest(canonical(normalized_changes(base, target, root)))


def validate_scenarios(root=ROOT):
    data = read_json(root / SCENARIOS)
    scenarios = data.get("scenarios")
    require(isinstance(scenarios, list) and scenarios, "Empty scenario catalog")
    ids = set()
    for scenario in scenarios:
        ident = text_field(scenario, "scenarioID")
        require(ident not in ids, f"Duplicate scenario: {ident}")
        ids.add(ident)
        require(type(scenario.get("revision")) is int and scenario["revision"] > 0, f"Invalid revision: {ident}")
        require(scenario.get("method") in ("automatic", "render", "physical-device"), f"Invalid method: {ident}")
        require(type(scenario.get("required")) is bool, f"Missing required flag: {ident}")
        for key in ("requirement", "procedure", "expected"):
            text_field(scenario, key)
        requirement_path, anchor = scenario["requirement"].split("#", 1)
        require((root / requirement_path).is_file() and anchor in (root / requirement_path).read_text(), f"Broken requirement: {ident}")
        if scenario["method"] == "physical-device":
            selected = scenario.get("requirementIDs", [anchor])
            require(isinstance(selected, list) and selected and all(isinstance(value, str) and value for value in selected) and anchor in selected, f"Invalid selected requirements: {ident}")
            scenario_hash(scenario, root)
        require(scenario.get("codePaths") and scenario.get("testIDs"), f"Missing mapping: {ident}")
        for test_id in scenario["testIDs"]:
            path, symbol = test_id.split("::", 1)
            require((root / path).is_file() and re.search(r"\b" + re.escape(symbol) + r"\b", (root / path).read_text()), f"Missing test: {test_id}")
        for pattern in scenario["codePaths"]:
            require(list(root.glob(pattern)), f"Unmatched code path: {pattern}")
    return scenarios


def scenario_hash(scenario, root=ROOT, document=None):
    path, anchor = scenario["requirement"].split("#", 1)
    ids = scenario.get("requirementIDs", [anchor])
    if document is None:
        document = (root / path).read_text()
    rows = [line for line in document.splitlines() if any(re.match(r"\|\s*" + re.escape(ident) + r"\s*\|", line) for ident in ids)]
    require(len(rows) == len(ids), f"Missing/ambiguous requirement content: {ids}")
    def normalized(value):
        return " ".join(re.sub(r"\[([^]]+)\]\([^)]+\)", r"\1", value).split())
    content = {key: scenario[key] for key in ("scenarioID", "revision", "method", "required")}
    content.update(procedure=normalized(scenario["procedure"]), expected=normalized(scenario["expected"]), requirementContent=[normalized(row) for row in rows])
    return digest(canonical(content))


def validate_reviews(base, target, scenarios, root=ROOT):
    relevant = [item["path"] for item in normalized_changes(base, target, root)]
    if not relevant:
        return
    reviews = read_json(root / REVIEWS).get("reviews", [])
    expected_hash = diff_hash(base, target, root)
    affected = set()
    for path in relevant:
        matches = []
        for scenario in scenarios:
            if any(fnmatch.fnmatchcase(path, pattern) for pattern in scenario["codePaths"]):
                matches.append(scenario["scenarioID"])
            elif path == scenario["requirement"].split("#")[0]:
                old = git_content(root, base, path)
                new = git_content(root, target, path)
                if requirement_hash(scenario, old.decode() if old else None, root) != requirement_hash(scenario, new.decode() if new else None, root):
                    matches.append(scenario["scenarioID"])
        if not excluded_input(path) and path.endswith((".swift", ".sh", ".py", ".yml", ".json", ".xcconfig", ".entitlements")):
            require(matches or path == SCENARIOS or path == RECORDS, f"Unclassified change: {path}")
        affected.update(matches)
    matches = [review for review in reviews if review.get("diffSHA256") == expected_hash]
    require(matches, "Independent scenario review missing for this diff")
    for review in matches:
        timestamp(review.get("reviewedAt"))
    latest = max(enumerate(matches), key=lambda pair: (timestamp(pair[1]["reviewedAt"]), pair[0]))[1]
    require(latest.get("decision") == "pass", "Latest independent review is missing, unknown or needs_changes")
    for review in [latest]:
        require(review.get("reviewer", {}).get("kind") in ("ai", "human"), "Invalid reviewer kind")
        text_field(review["reviewer"], "id")
        require(review.get("independent") is True, "Review must be independent")
        timestamp(review.get("reviewedAt"))
        text_field(review, "reason")
        review_target = text_field(review, "targetOID")
        require(git("rev-parse", review_target, root=root) == review_target, "Review requires a full target OID")
        review_base = text_field(review, "baseOID")
        require(git("rev-parse", review_base, root=root) == review_base, "Review requires a full base OID")
        require(diff_hash(review_base, review_target, root) == expected_hash, "Review target does not describe this diff")
        require(affected <= set(review.get("scenarioIDs", [])), "Review omits affected scenarios")
    old_catalog = subprocess.run(["git", "show", f"{base}:{SCENARIOS}"], cwd=root, capture_output=True, text=True)
    if old_catalog.returncode == 0:
        old = {s["scenarioID"]: s for s in json.loads(old_catalog.stdout)["scenarios"]}
        current = {s["scenarioID"]: s for s in scenarios}
        reductions = []
        for ident, previous in old.items():
            if not previous["required"]:
                continue
            scenario = current.get(ident)
            if scenario is None or not scenario["required"] or scenario["method"] != previous["method"]:
                reductions.append(ident)
                continue
            old_ids = set(previous.get("requirementIDs", [previous["requirement"].split("#", 1)[1]]))
            new_ids = set(scenario.get("requirementIDs", [scenario["requirement"].split("#", 1)[1]]))
            if not old_ids <= new_ids:
                reductions.append(ident)
        for ident in reductions:
            approvals = [r.get("userApproval", {}) for r in [latest] if ident in r.get("scenarioIDs", [])]
            require(any(a.get("kind") == "human" and a.get("id") and a.get("reason") and a.get("approvedAt") for a in approvals), f"User decision required for reduced requirement: {ident}")
            for approval in approvals:
                timestamp(approval.get("approvedAt"))


def toolchain():
    return {"xcode": subprocess.check_output(["xcodebuild", "-version"], text=True).strip(),
            "sdk": subprocess.check_output(["xcodebuild", "-showsdks"], text=True).strip()}


def run_stage(command, log, *, env=None, cwd=ROOT):
    started = now()
    with Path(log).open("x") as stream:
        child = subprocess.Popen(command, cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT)
        write_json(str(log) + ".owner.json", {"purpose": "verification stage", "pid": child.pid, "parentPID": os.getpid(), "executable": command[0], "argv": command, "cwd": str(cwd), "startedAt": started})
        code = child.wait()
    write_json(str(log) + ".result.json", {"exitCode": code, "startedAt": started, "finishedAt": now()})
    print(f"{Path(log).stem}: exit={code}, log={log}", flush=True)
    require(code == 0, f"Stage failed (exit {code}): {log}")


def managed(key, command):
    home = Path.home() / ".agents/scripts"
    return [str(home / "compact-test"), "--full", key, "python3", "-B", str(home / "managed-build.py"), "run", "--project", str(ROOT), "--session", session_name(), "--key", key, "--", *command]


def clean_environment():
    forbidden = [key for key in os.environ if (key.startswith("SWIFT_TEST_") and key != "SWIFT_TEST_OUTPUT") or key.startswith(("SWIFT_TESTING", "SWT_", "_SWT_", "XCTest"))]
    require(not forbidden, f"Gate rejects inherited range/configuration overrides: {', '.join(forbidden)}")
    env = {key: value for key, value in os.environ.items() if not key.startswith("PHLOX_")}
    env["PHLOX_E2E"] = "0"
    return env


def candidate():
    head = git("rev-parse", "HEAD")
    expected = os.environ.get("GITFLOW_MERGE_CANDIDATE")
    if expected:
        require(head == expected, "Candidate HEAD differs from GITFLOW_MERGE_CANDIDATE")
        require(not git("status", "--porcelain", "--untracked-files=all"), "Candidate is not clean")
    return head


def check_test_log(log):
    data = Path(log).read_text(errors="replace")
    counts = [int(value) for value in re.findall(r"^[✔✘] Test run with (\d+) tests?\b", data, re.M)]
    require(counts and all(count > 0 for count in counts), f"Zero tests or unknown result format: {log}")
    require(not re.search(r"^✘ Test run .* failed after", data, re.M), f"Failed test: {log}")
    for line in data.splitlines():
        if re.match(r"^Test Case .* skipped", line):
            require(line.startswith(f"Test Case '{OPTIONAL_XCTEST_SKIP}' skipped ("), f"Unclassified XCTest skip: {line}")
    return {"reportedTestCounts": counts, "skipped": [line for line in data.splitlines() if re.match(r"^➜ Test .* skipped\.|^Test Case .* skipped", line)],
            "knownIssues": [line for line in data.splitlines() if re.search(r"known issue|known issues", line, re.I)]}


def check_fake_events(path):
    """Read Swift Testing events rather than inferring identity from display names."""
    expected = {f"DashboardFeatureTests.{suite}/{name}()" for suite, names in FAKE_TESTS.items() for name in names}
    started, passed = set(), set()
    run_started = run_ended = False
    lines = event_lines(path)
    require(lines and all(line.strip() for line in lines), "Empty or malformed fake event stream")
    for line in lines:
        item = json.loads(line)
        require(item.get("version") == 0 and item.get("kind") in ("test", "event"), "Unknown Swift Testing event format")
        if item["kind"] != "event":
            continue
        payload = item["payload"]
        kind = payload["kind"]
        ident = "/".join(payload.get("testID", "").split("/")[:2])
        run_started |= kind == "runStarted"
        run_ended |= kind == "runEnded"
        if kind == "testStarted" and "/" in ident:
            require(ident in expected and ident not in started, f"Unexpected or duplicate fake test: {ident}")
            started.add(ident)
        if kind == "testEnded" and ident in expected:
            require(ident in started and ident not in passed, f"Unexpected fake completion: {ident}")
            require(any(message.get("symbol") == "pass" for message in payload.get("messages", [])), f"Non-passing fake completion: {ident}")
            passed.add(ident)
        require(kind not in ("issueRecorded", "testSkipped"), f"Fake E2E issue/skip: {payload}")
    require(run_started and run_ended and started == expected and passed == expected, f"Incomplete fake E2E run; IDs missing: {sorted(expected - (started & passed))}")
    return sorted(passed)


def event_lines(path):
    # JSON strings may contain U+0085/U+2028; JSONL records are delimited by ASCII LF.
    lines = Path(path).read_bytes().split(b"\n")
    if lines and lines[-1] == b"":
        lines.pop()
    require(lines and all(line.strip() for line in lines), f"Empty/malformed event stream: {path}")
    return [line.decode("utf-8") for line in lines]


def check_regular_events(paths):
    require(paths, "Missing ordinary test event streams")
    issues, skipped, passed = [], [], set()
    for path in paths:
        ended = started = False
        local_passed, local_issues = set(), []
        for line in event_lines(path):
            item = json.loads(line)
            require(item.get("version") == 0 and item.get("kind") in ("test", "event"), "Unknown ordinary test event format")
            if item["kind"] != "event":
                continue
            event = item["payload"]
            ident = re.sub(r"/[^/]+\.swift:\d+:\d+$", "", event.get("testID", ""))
            kind = event["kind"]
            started |= kind == "runStarted"
            ended |= kind == "runEnded"
            if kind == "testEnded" and ident.endswith(")"):
                if any(message.get("symbol") == "pass" for message in event.get("messages", [])):
                    local_passed.add(ident)
            if kind == "testSkipped":
                require(ident in OPTIONAL_SKIPS, f"Unclassified ordinary test skip: {ident}")
                skipped.append(ident)
            if kind == "issueRecorded":
                require(ident == KNOWN_ISSUE and event.get("issue", {}).get("isKnown") is True, f"Unknown/unresolved test issue: {ident}")
                issues.append(event)
                local_issues.append(ident)
        local_passed.difference_update(local_issues)
        require(started and ended and local_passed, f"Incomplete/zero/all-skipped ordinary event stream: {path}")
        passed.update(local_passed)
    require(passed, "No ordinary tests passed")
    return {"passedIDs": sorted(passed), "skippedIDs": sorted(skipped), "unresolvedKnownIssues": issues}


def regular_event_paths(directory, packages):
    expected = {f"{package}-all.jsonl" for package in packages if package != "DashboardFeature"}
    if "DashboardFeature" in packages:
        expected.update(["DashboardFeature-main.jsonl", "DashboardFeature-git.jsonl"])
    actual = {path.name for path in Path(directory).glob("*.jsonl")}
    require(actual == expected, f"Ordinary event set differs: missing={sorted(expected - actual)}, extra={sorted(actual - expected)}")
    return [Path(directory) / name for name in sorted(expected)]


def validate_package_scope(root=ROOT):
    discovered = sorted(path.parent.name for path in (root / "macos/Packages").glob("*/Package.swift"))
    require(discovered == MACOS_PACKAGES, "Package set changed; classify and review the new verification scope")


def quality(args):
    env = clean_environment()
    head, before = candidate(), input_manifest(ROOT)
    catalog_hash = digest((ROOT / SCENARIOS).read_bytes())
    evidence_root = Path(os.environ.get("GITFLOW_VERIFICATION_DIR", str(ROOT / ".verification" / session_name())))
    if os.environ.get("GITFLOW_VERIFICATION_DIR"):
        require(evidence_root.is_absolute() and not evidence_root.resolve().is_relative_to(ROOT.resolve()), "Merge evidence must live outside the disposable candidate")
    out = evidence_root / ("quality-" + dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%f"))
    out.mkdir(parents=True)
    write_json(out / "owner.json", {"purpose": "project quality gate", "pid": os.getpid(), "executable": sys.executable, "sourceOID": head, "candidate": os.environ.get("GITFLOW_MERGE_CANDIDATE"), "output": str(out)})
    scenarios = validate_scenarios(ROOT)
    if os.environ.get("GITFLOW_MERGE_TO"):
        validate_reviews(os.environ["GITFLOW_MERGE_TO"], head, scenarios, ROOT)
    run_stage(managed("macos-packages-debug", ["python3", "-B", str(Path(__file__).resolve()), "_quality-worker", "--output", str(out), "--build-dir", "{build_dir}"]), out / "driver.log", env=env)
    require(candidate() == head and input_manifest(ROOT) == before and digest((ROOT / SCENARIOS).read_bytes()) == catalog_hash, "Candidate inputs changed during verification")
    print(f"Quality passed; physical devices not verified. Results: {out}")


def quality_worker(args):
    require(os.environ.get("MANAGED_BUILD_DIR") == str(Path(args.build_dir).resolve()), "Quality worker requires managed-build")
    env = clean_environment()
    head, before = candidate(), input_manifest(ROOT)
    out, build_dir = Path(args.output), Path(args.build_dir)
    results = {}
    validate_package_scope(ROOT)
    write_json(out / "effective-settings.json", {"packages": MACOS_PACKAGES, "serialPackages": ["SessionFeature", "DashboardFeature"], "gitSuites": ["WorktreeIsolationSpawnTests", "AcceptanceRestoreAbortNoSpawnTests", "FileTreeGitTests"], "PHLOX_E2E": "0", "session": session_name(), "key": "macos-packages-debug"})
    command = ["env", f"SWIFT_TEST_SCRATCH_ROOT={build_dir}", "SWIFT_TEST_OUTPUT=full", f"SWIFT_TEST_EVENT_ROOT={out / 'macos-events'}", "bash", "macos/scripts/run-swift-tests.sh", *MACOS_PACKAGES]
    compact = str(Path.home() / ".agents/scripts/compact-test")
    run_stage([compact, "--full", "gate-unit", "python3", "-B", "-m", "unittest", "discover", "-s", "macos/scripts/tests", "-p", "test_verification_gate*.py"], out / "gate-unit.log", env=env)
    run_stage([compact, "--full", "ios-ad-hoc-unit", "python3", "-B", "-m", "unittest", "discover", "-s", "ios/scripts", "-p", "test_prepare_ad_hoc.py"], out / "ios-ad-hoc-unit.log", env=env)
    run_stage([compact, "--full", "standard-entry-regression", "bash", "macos/scripts/tests/run-swift-tests-output.test.sh"], out / "standard-entry.log", env=env)
    run_stage([compact, "--full", "macos-packages", *command], out / "macos.log", env=env)
    results["macos"] = check_test_log(out / "macos.log")
    results["macos"].update(check_regular_events(regular_event_paths(out / "macos-events", MACOS_PACKAGES)))
    run_stage(["make", "-C", "ios", "lint"], out / "ios-lint.log", env=env)
    (out / "ios-events").mkdir()
    run_stage([compact, "--full", "ios-packages", "make", "-C", "ios", "test", f"SWIFT_TEST_SCRATCH_ROOT={build_dir / '_ios-package'}", f"SWIFT_TEST_EVENT_ROOT={out / 'ios-events'}"], out / "ios-tests.log", env=env)
    results["ios"] = check_test_log(out / "ios-tests.log")
    results["ios"].update(check_regular_events([out / "ios-events/PhloxKit.jsonl"]))
    # XcodeGen also writes Info.plist beside sources. Generate in a source copy.
    source = build_dir / "_ios-source" / out.name
    source.mkdir(parents=True)
    for entry in before["files"]:
        src, dst = ROOT / entry["path"], source / entry["path"]
        dst.parent.mkdir(parents=True, exist_ok=True)
        if src.is_symlink():
            dst.symlink_to(os.readlink(src))
        else:
            shutil.copy2(src, dst)
    xcodegen = shutil.which("xcodegen")
    if not xcodegen and os.access("/opt/homebrew/bin/xcodegen", os.X_OK):
        xcodegen = "/opt/homebrew/bin/xcodegen"
    require(xcodegen, "XcodeGen is not installed")
    run_stage(["make", "-C", str(source / "ios"), "build", f"XCODEGEN={xcodegen}", "DESTINATION=generic/platform=iOS Simulator", f"DERIVED_DATA_PATH={build_dir / '_ios-app'}"], out / "ios-build.log", env=env)
    fake_env = env.copy()
    fake_env.update(PHLOX_E2E="1", SWIFT_TEST_OUTPUT="full", SWIFT_TEST_FILTER="|".join(f"^DashboardFeatureTests\\.{suite}/{name}\\(\\)(/|$)" for suite, names in FAKE_TESTS.items() for name in names), SWIFT_TEST_EVENT_ROOT=str(out / "events"))
    run_stage([compact, "--full", "fake-e2e", "env", f"SWIFT_TEST_SCRATCH_ROOT={build_dir}", "bash", "macos/scripts/run-swift-tests.sh", "DashboardFeature"], out / "fake-e2e.log", env=fake_env)
    results["fakeE2E"] = check_fake_events(out / "events/DashboardFeature-filtered.jsonl")
    require(candidate() == head and input_manifest(ROOT) == before, "Candidate inputs changed during verification")
    write_json(out / "result.json", {"schemaVersion": 1, "sourceOID": head, "inputSHA256": before["sha256"], "results": results, "finishedAt": now()})


def evidence_path(value, root):
    path = Path(value)
    path = path.resolve() if path.is_absolute() else (root / path).resolve()
    require(path.is_relative_to(root.resolve()), f"Path escapes evidence root: {value}")
    return path


def file_reference(path, evidence_root):
    file = evidence_path(path, evidence_root)
    require(file.is_file(), f"Missing evidence input: {file}")
    return {"path": file.relative_to(evidence_root).as_posix(), "sha256": digest(file.read_bytes())}


def external_inputs(paths, evidence_root):
    values = []
    for path in paths:
        file = evidence_path(path, evidence_root)
        require(file.is_file() and not file.name.startswith(".env"), f"Invalid external input: {file}")
        entry = file_reference(file, evidence_root)
        values.append(entry)
    require(values, "Explicit effective settings and resolved external inputs are required")
    return sorted(values, key=lambda item: item["path"])


def check_local_build_inputs(manifest, external, evidence_root):
    files = {entry["path"] for entry in manifest["files"]}
    declared = {evidence_path(entry["path"], evidence_root) for entry in external}
    pending = [ROOT / name for name in files if name.endswith(".xcconfig")]
    checked = set()
    while pending:
        file = pending.pop()
        if file in checked:
            continue
        checked.add(file)
        for optional, include in re.findall(r'^\s*#include(\??)\s+"([^"]+)"', file.read_text(), re.M):
            path = (file.parent / include).resolve()
            require(path.exists() or optional == "?", f"Unresolved xcconfig include: {path}")
            if path.exists():
                require(not path.name.startswith(".env"), "Forbidden external build input")
                require((path.is_relative_to(ROOT) and path.relative_to(ROOT).as_posix() in files) or path in declared, f"Undeclared external build input: {path}")
                pending.append(path)


def validate_build_settings(settings, platform, bundle_id, version, number):
    require(isinstance(settings, list) and settings and all(isinstance(item.get("buildSettings"), dict) for item in settings), "Settings must be measured xcodebuild -showBuildSettings -json output")
    matches = [item["buildSettings"] for item in settings if item["buildSettings"].get("PRODUCT_BUNDLE_IDENTIFIER") == bundle_id]
    require(len(matches) == 1, "Effective settings do not uniquely identify the built app")
    effective = matches[0]
    require(effective.get("MARKETING_VERSION") == version and effective.get("CURRENT_PROJECT_VERSION") == number, "Effective app version/build differs from the build record")
    require(effective.get("PLATFORM_NAME") == ("macosx" if platform == "macos" else "iphoneos"), "Physical build settings use the wrong platform or a simulator")
    require(effective.get("CODE_SIGNING_ALLOWED") == "YES" and effective.get("CODE_SIGN_IDENTITY"), "Physical build requires effective signing settings")
    return digest(canonical(settings))


def validate_ios_artifact(artifact, bundle_id, version, number):
    try:
        with zipfile.ZipFile(artifact) as archive:
            apps = [entry for entry in archive.infolist()
                    if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", entry.filename)]
            require(len(apps) == 1, "iOS IPA requires exactly one app Info.plist")
            prefix = apps[0].filename.removesuffix("Info.plist")
            widgets = [entry for entry in archive.infolist()
                       if re.fullmatch(re.escape(prefix) + r"PlugIns/[^/]+\.appex/Info\.plist", entry.filename)]
            require(len(widgets) == 1, "iOS IPA requires exactly one Widget Info.plist")
            for entry, ident in ((apps[0], bundle_id), (widgets[0], bundle_id + ".PhloxWidget")):
                require(entry.file_size <= 1024 * 1024, "Oversized iOS Info.plist")
                info = plistlib.loads(archive.read(entry))
                require(isinstance(info, dict) and info.get("CFBundleIdentifier") == ident
                        and info.get("CFBundleShortVersionString") == version
                        and info.get("CFBundleVersion") == number, "iOS bundle identity does not match the build record")
    except (OSError, ValueError, RuntimeError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        raise GateError(f"Invalid iOS artifact: {error}") from error


def capture_build(args):
    require(not git("status", "--porcelain", "--untracked-files=all"), "A reusable build must start from clean committed sources")
    require(args.command and args.command[0] != "--", "Missing build command")
    require(any("{build_dir}" in argument for argument in args.command), "Build command must explicitly route managed output through {build_dir}")
    require(Path(args.evidence_root).is_absolute(), "--evidence-root must be absolute")
    evidence_root = Path(args.evidence_root).resolve(strict=True)
    source, before, tools = candidate(), input_manifest(ROOT), toolchain()
    external = external_inputs(args.external_input + [args.settings], evidence_root)
    check_local_build_inputs(before, external, evidence_root)
    settings = json.loads(evidence_path(args.settings, evidence_root).read_text())
    settings_hash = validate_build_settings(settings, args.platform, args.bundle_id, args.version, args.build_number)
    started = now()
    artifact = evidence_path(args.artifact, evidence_root)
    require(not artifact.exists(), "Artifact must be newly produced by this build")
    require(bool(args.zip) == (args.platform == "macos"), "Mac builds require --zip; iOS builds must omit it")
    sparkle_zip = evidence_path(args.zip, evidence_root) if args.zip else None
    if sparkle_zip:
        require(sparkle_zip != artifact and not sparkle_zip.exists(), "ZIP must be a separate, newly produced artifact")
    out = evidence_path(args.output, evidence_root)
    require(not out.exists(), "Build record must be new")
    out.parent.mkdir(parents=True, exist_ok=True)
    run_stage(managed(f"release-{args.platform}", args.command), str(out) + ".log")
    require(candidate() == source and input_manifest(ROOT) == before and external_inputs(args.external_input + [args.settings], evidence_root) == external and toolchain() == tools, "Build inputs changed during compilation")
    require(not git("status", "--porcelain", "--untracked-files=all"), "Build changed its source tree")
    require(artifact.is_file(), "Missing build artifact")
    if args.platform == "ios":
        validate_ios_artifact(artifact, args.bundle_id, args.version, args.build_number)
    record = {"schemaVersion": 1, "sourceOID": source, "platform": args.platform, "startedAt": started, "finishedAt": now(), "inputManifest": before, "toolchain": tools, "settingsSHA256": settings_hash, "settingsPath": evidence_path(args.settings, evidence_root).relative_to(evidence_root).as_posix(), "externalInputs": external, "bundleID": args.bundle_id, "version": args.version, "buildNumber": args.build_number, "artifact": file_reference(artifact, evidence_root)}
    if sparkle_zip:
        require(sparkle_zip.is_file(), "Missing distribution ZIP")
        record["sparkleZIP"] = file_reference(sparkle_zip, evidence_root)
    write_json(out, record)
    print(f"Build provenance captured; installation and physical scenarios not verified: {out}")


def verify_file(value, root):
    require(isinstance(value, dict), "Missing file reference")
    path = Path(text_field(value, "path"))
    require(not path.is_absolute() and ".." not in path.parts, "Evidence references must be relative to --evidence-root")
    path = evidence_path(path, root)
    require(path.is_file(), f"Missing artifact/evidence: {path}")
    require(digest(path.read_bytes()) == value.get("sha256"), f"Artifact/evidence hash mismatch: {path}")
    return path


def validate_physical_records(data, scenarios, manifest, tools=None, root=ROOT, dmg_sha256=None, evidence_root=None, dmg_path=None):
    require(data.get("schemaVersion") == 1, "Unknown physical record schema")
    evidence_root = evidence_root or root
    required = [s for s in scenarios if s["required"] and s["method"] == "physical-device"]
    require(required, "Required physical scenario set disappeared")
    builds, devices = {}, {}
    identities = {}
    matching_mac_builds = set()
    for build in data.get("builds", []):
        ident = text_field(build, "buildID")
        require(ident not in builds, f"Duplicate build ID: {ident}")
        file = verify_file(build.get("provenance"), evidence_root)
        record = read_json(file)
        source = text_field(record, "sourceOID")
        require(re.fullmatch(r"[0-9a-f]{40}", source), "Build source requires a full OID")
        require(input_manifest(root, source) == record.get("inputManifest") == manifest, f"Stale build inputs: {ident}")
        require(isinstance(record.get("toolchain"), dict) and all(isinstance(record["toolchain"].get(key), str) and record["toolchain"][key].strip() for key in ("xcode", "sdk")), "Missing historical Xcode/SDK provenance")
        require(timestamp(record.get("finishedAt")) >= timestamp(record.get("startedAt")), "Invalid build time order")
        require(record.get("externalInputs"), "Missing effective external inputs")
        for external in record["externalInputs"]:
            verify_file(external, evidence_root)
        settings_path = evidence_path(text_field(record, "settingsPath"), evidence_root)
        require(any(external["path"] == record["settingsPath"] for external in record["externalInputs"]), "Effective settings are not in the external input manifest")
        settings = json.loads(settings_path.read_text())
        require(validate_build_settings(settings, record["platform"], record["bundleID"], record["version"], record["buildNumber"]) == record.get("settingsSHA256"), "Effective build settings changed")
        artifact = record.get("artifact")
        artifact_path = verify_file(artifact, evidence_root)
        if record["platform"] == "ios":
            validate_ios_artifact(artifact_path, record["bundleID"], record["version"], record["buildNumber"])
        identity = [artifact["sha256"]]
        if record["platform"] == "macos":
            require(verify_file(record.get("sparkleZIP"), evidence_root) != artifact_path, "DMG and ZIP must be separate artifacts")
            identity.append(record["sparkleZIP"]["sha256"])
        if record["platform"] == "macos" and (dmg_sha256 is None or artifact["sha256"] == dmg_sha256) and (dmg_path is None or artifact_path.samefile(dmg_path)):
            matching_mac_builds.add(ident)
        key = tuple(text_field(record, key) for key in ("platform", "bundleID", "version", "buildNumber"))
        require(key not in identities or identities[key] == identity, "Build number reused for different artifacts")
        identities[key] = identity
        builds[ident] = record
    for device in data.get("devices", []):
        ident = text_field(device, "deviceID")
        require(ident not in devices, f"Duplicate device ID: {ident}")
        require(device.get("physical") is True, f"Physical device required: {ident}")
        for key in ("model", "osVersion", "osBuild"):
            text_field(device, key)
        verify_file(device.get("identityEvidence"), evidence_root)
        devices[ident] = device
    for scenario in scenarios:
        if scenario not in required:
            continue
        executions = [row for row in data.get("executions", []) if row.get("scenarioID") == scenario["scenarioID"]]
        require(executions, f"Physical scenario not_run: {scenario['scenarioID']}")
        dated = [(timestamp(row.get("executedAt")), row) for row in executions]
        latest_at = max(when for when, _ in dated)
        latest = [row for when, row in dated if when == latest_at]
        require(len({canonical(row) for row in latest}) == 1, f"Conflicting physical executions at the latest time: {scenario['scenarioID']}")
        execution = latest[0]
        require(execution.get("result") == "passed", f"Physical scenario is not passed: {scenario['scenarioID']}")
        require(execution.get("revision") == scenario["revision"] and execution.get("scenarioSHA256") == scenario_hash(scenario, root), "Stale physical scenario")
        text_field(execution, "observations")
        observer = execution.get("observer", {})
        require(observer.get("kind") == "human", "AI review is not physical observation testimony")
        text_field(observer, "id")
        executed_at = latest_at
        pair = execution.get("pair", {})
        require(set(pair) == {"macos", "ios"}, "Actual Mac/iPhone build pair required")
        for platform, installation in pair.items():
            build = builds.get(installation.get("buildID"))
            device = devices.get(installation.get("deviceID"))
            require(build and device and build["platform"] == platform, "Missing or mismatched build/device pair")
            require(device.get("platform") == platform, "Wrong device platform")
            require(executed_at >= timestamp(build["finishedAt"]), "Physical observation predates build")
            for key in ("bundleID", "version", "buildNumber"):
                require(installation.get(key) == build[key], f"Installed {key} mismatch")
            require(installation.get("artifactSHA256") == build["artifact"]["sha256"], "Installed artifact mismatch")
            if platform == "macos" and dmg_sha256 is not None:
                require(installation["buildID"] in matching_mac_builds, "Stapler DMG differs from the actual physical Mac build")
            verify_file(installation.get("installationEvidence"), evidence_root)
        require(execution.get("evidence"), "Missing physical observation evidence")
        for evidence in execution["evidence"]:
            verify_file(evidence, evidence_root)
    require(matching_mac_builds, "No recorded physical Mac build matches the validated DMG")
    return [builds[ident] for ident in sorted(matching_mac_builds)]


def file_sha256(path):
    with Path(path).open("rb") as stream:
        return stream_sha256(stream)


def stream_sha256(stream):
    value = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
        value.update(chunk)
    return value.hexdigest()


def app_contents(app):
    contents = {}
    for directory, dirs, files in os.walk(app, followlinks=False):
        for name in dirs + files:
            path = Path(directory) / name
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode):
                require(path.resolve(strict=True).is_relative_to(app.resolve()), f"External app symlink: {path}")
                data = os.fsencode(os.readlink(path))
                value = ("symlink", len(data), digest(data), mode & 0o111)
            elif stat.S_ISREG(mode):
                value = ("file", path.stat().st_size, file_sha256(path), mode & 0o111)
            else:
                require(stat.S_ISDIR(mode), f"Unsupported app entry: {path}")
                continue
            contents[path.relative_to(app).as_posix()] = value
    require(contents, "Empty distribution app")
    return contents


def compare_zip_app(path, app):
    expected, seen, names = app_contents(app), set(), set()
    with zipfile.ZipFile(path) as archive:
        for entry in archive.infolist():
            name = entry.filename
            parts = name.rstrip("/").split("/")
            require(name not in names and all(part not in ("", ".", "..") for part in parts) and "\\" not in name and "\0" not in name, f"Unsafe/duplicate ZIP path: {name}")
            names.add(name)
            require(parts[0] in (app.name, "__MACOSX"), f"Unexpected ZIP root: {name}")
            mode = entry.external_attr >> 16
            if entry.is_dir():
                require(stat.S_ISDIR(mode), f"Unsupported ZIP directory: {name}")
                if parts[0] != "__MACOSX":
                    directory = app.joinpath(*parts[1:])
                    require(directory.is_dir() and not directory.is_symlink(), f"Unexpected ZIP directory: {name}")
                continue
            if parts[0] == "__MACOSX":
                parts = parts[1:]
                require(parts and parts[0] == app.name, f"Unexpected ZIP metadata root: {name}")
            relative = "/".join(parts[1:])
            if parts[-1].startswith("._") and relative not in expected:
                target = app.joinpath(*parts[1:-1], parts[-1][2:])
                require(stat.S_ISREG(mode) and (target.exists() or target.is_symlink()) and target.resolve(strict=True).is_relative_to(app.resolve()), f"Unmatched ZIP metadata: {name}")
                with archive.open(entry) as stream:
                    require(stream.read(8) == bytes.fromhex("0005160700020000"), f"Invalid AppleDouble metadata: {name}")
                continue
            require(not name.startswith("__MACOSX/"), f"Unexpected ZIP metadata: {name}")
            require(relative in expected, f"ZIP app has extra content: {name}")
            kind = "symlink" if stat.S_ISLNK(mode) else "file"
            require(stat.S_ISLNK(mode) or stat.S_ISREG(mode), f"Unsupported ZIP entry: {name}")
            wanted = expected[relative]
            require((kind, entry.file_size, mode & 0o111) == (wanted[0], wanted[1], wanted[3]), f"ZIP/DMG app metadata mismatch: {name}")
            with archive.open(entry) as stream:
                require(stream_sha256(stream) == wanted[2], f"ZIP/DMG app content mismatch: {name}")
            seen.add(relative)
    require(seen == set(expected), f"ZIP app is missing DMG app content: {sorted(set(expected) - seen)[:10]}")


def read_appcast(feed):
    parser, tree = expat.ParserCreate(namespace_separator="}"), ET.TreeBuilder()
    def name(value):
        return "{" + value if "}" in value else value
    def reject_declaration(*args):
        raise GateError("Appcast DTD/entity declarations are forbidden")
    parser.StartDoctypeDeclHandler = reject_declaration
    parser.EntityDeclHandler = reject_declaration
    parser.ExternalEntityRefHandler = reject_declaration
    parser.StartElementHandler = lambda tag, attrs: tree.start(name(tag), {name(key): value for key, value in attrs.items()})
    parser.EndElementHandler = lambda tag: tree.end(name(tag))
    parser.CharacterDataHandler = tree.data
    parser.Parse(Path(feed).read_bytes(), True)
    return tree.close()


def distribution_signature(feed, build, sparkle_zip):
    ns = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    items = [item for item in read_appcast(feed).findall("./channel/item")
             if item.findtext(ns + "version") == build["buildNumber"]
             and item.findtext(ns + "shortVersionString") == build["version"]]
    require(len(items) == 1, "Appcast must identify exactly one distribution build")
    enclosures = items[0].findall("enclosure")
    require(len(enclosures) == 1, "Appcast requires one full distribution enclosure")
    enclosure = enclosures[0]
    expected_url = f"https://github.com/HMNZK/phlox-dist/releases/download/updates/Phlox-{build['version']}.zip"
    require(sparkle_zip.name == f"Phlox-{build['version']}.zip" and enclosure.get("url") == expected_url, "Appcast distribution URL/version mismatch")
    require(enclosure.get("length") == str(sparkle_zip.stat().st_size) and enclosure.get("type") == "application/octet-stream", "Appcast ZIP size/type mismatch")
    return text_field(enclosure.attrib, ns + "edSignature")


def validate_distribution(dmg, sparkle_zip, build, evidence_root):
    parent = evidence_root / "distribution-checks"
    parent.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="inspection-", dir=parent))
    write_json(work / "owner.json", {"purpose": "read-only distribution verification", "session": session_name(), "pid": os.getpid(), "executable": sys.executable, "createdAt": now()})
    mount = work / "volume"
    mount.mkdir()
    try:
        copies = []
        for source, reference in ((dmg, build["artifact"]), (sparkle_zip, build["sparkleZIP"])):
            copy = work / source.name
            shutil.copyfile(source, copy)
            copy.chmod(0o400)
            require(file_sha256(copy) == reference["sha256"], "Distribution changed before inspection")
            copies.append(copy)
        subprocess.run(["hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), "-plist", str(copies[0])], check=True, stdout=subprocess.PIPE)
        require(os.path.ismount(mount), "DMG did not mount at the inspection path")
        apps = list(mount.glob("*.app"))
        require(len(apps) == 1 and apps[0].is_dir() and not apps[0].is_symlink(), "DMG must contain exactly one real app")
        app = apps[0]
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        require(all(info.get(key) == build[field] for key, field in (("CFBundleIdentifier", "bundleID"), ("CFBundleShortVersionString", "version"), ("CFBundleVersion", "buildNumber"))), "DMG app identity/version mismatch")
        compare_zip_app(copies[1], app)
        signature = distribution_signature(ROOT / "site/appcast.xml", build, copies[1])
        run_stage(managed("release-signature", ["xcrun", "swift", "-module-cache-path", "{build_dir}/module-cache", str(ROOT / "macos/scripts/verify-sparkle-signature.swift"), str(copies[1]), signature, text_field(info, "SUPublicEDKey")]), work / "signature.log")
        expanded = work / "expanded"
        subprocess.run(["ditto", "-x", "-k", str(copies[1]), str(expanded)], check=True)
        require(app_contents(expanded / app.name) == app_contents(app), "Extracted ZIP/DMG app mismatch")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(expanded / app.name)], check=True)
        require(file_sha256(dmg) == build["artifact"]["sha256"] and file_sha256(sparkle_zip) == build["sparkleZIP"]["sha256"], "Distribution changed during inspection")
    finally:
        if os.path.ismount(mount):
            subprocess.run(["hdiutil", "detach", str(mount)], check=True)
    # Keep the small owner/log record; the large inspection copies are disposable.
    for copy in work.iterdir():
        if copy.name in (dmg.name, sparkle_zip.name) and copy.is_file():
            copy.unlink()
    if any(path.name.startswith(".env") for path in expanded.rglob("*")):
        print(f"Inspection app retained because it contains a protected .env path: {expanded}")
    else:
        shutil.rmtree(expanded)
    mount.rmdir()


def release(args):
    require(os.environ.get("GITFLOW_MERGE_CANDIDATE"), "Release requires the final merge candidate OID environment")
    head, before = candidate(), input_manifest(ROOT)
    require(os.environ.get("GITFLOW_MERGE_TO"), "Release requires the merge base OID environment")
    scenarios = validate_scenarios(ROOT)
    validate_reviews(os.environ["GITFLOW_MERGE_TO"], head, scenarios, ROOT)
    data = read_json(args.record)
    require(Path(args.evidence_root).is_absolute(), "--evidence-root must be absolute")
    evidence_root = Path(args.evidence_root).resolve(strict=True)
    dmg = evidence_path(args.dmg, evidence_root)
    dmg_hash = digest(dmg.read_bytes())
    builds = validate_physical_records(data, scenarios, before, root=ROOT, evidence_root=evidence_root, dmg_sha256=dmg_hash, dmg_path=dmg)
    sparkle_zip = evidence_path(args.zip, evidence_root)
    for build in builds:
        require(verify_file(build["sparkleZIP"], evidence_root).samefile(sparkle_zip), "Distribution ZIP differs from recorded build")
        validate_distribution(dmg, sparkle_zip, build, evidence_root)
    require(candidate() == head and input_manifest(ROOT) == before, "Release inputs changed during verification")
    print("Physical release evidence matched. Existing version/notes/appcast/stapler checks must precede this command.")


def review_input(args, root=ROOT):
    base, target = git("rev-parse", args.base, root=root), git("rev-parse", args.target, root=root)
    changes = normalized_changes(base, target, root)
    print(json.dumps({"schemaVersion": 1, "baseOID": base, "targetOID": target, "diffSHA256": digest(canonical(changes)), "changes": changes}, ensure_ascii=False, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="mode", required=True)
    sub.add_parser("quality")
    review = sub.add_parser("review-input", help="Read-only normalized content diff for independent review")
    review.add_argument("--base", required=True)
    review.add_argument("--target", default="HEAD")
    worker = sub.add_parser("_quality-worker", help=argparse.SUPPRESS)
    worker.add_argument("--output", required=True)
    worker.add_argument("--build-dir", required=True)
    physical = sub.add_parser("release")
    physical.add_argument("--record", default=RECORDS)
    physical.add_argument("--dmg", required=True, help="Exactly the DMG path passed to the preceding stapler validation")
    physical.add_argument("--zip", required=True, help="The distribution ZIP captured with the physical Mac build")
    physical.add_argument("--evidence-root", required=True)
    capture = sub.add_parser("capture-build")
    capture.add_argument("--platform", required=True, choices=["macos", "ios"])
    capture.add_argument("--evidence-root", required=True)
    capture.add_argument("--zip", help="New distribution ZIP, required only for macos")
    for name in ("artifact", "settings", "output", "bundle-id", "version", "build-number"):
        capture.add_argument("--" + name, required=True)
    capture.add_argument("--external-input", action="append", default=[])
    capture.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    if args.mode == "capture-build" and args.command[:1] == ["--"]:
        args.command.pop(0)
    try:
        {"quality": quality, "_quality-worker": quality_worker, "capture-build": capture_build, "release": release, "review-input": review_input}[args.mode](args)
    except (GateError, OSError, ValueError, KeyError, TypeError, ET.ParseError, expat.ExpatError, zipfile.BadZipFile, subprocess.CalledProcessError) as error:
        print(f"verification-gate: inspection failed or incomplete: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
