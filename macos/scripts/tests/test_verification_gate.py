"""Gate regressions using measured Swift Testing events and isolated Git fixtures."""
import copy
import base64
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import shutil
import stat
import zipfile
from unittest.mock import patch
from types import SimpleNamespace
from contextlib import redirect_stdout, ExitStack
import io


SCRIPT = Path(__file__).resolve().parents[1] / "verification-gate.py"
SPEC = importlib.util.spec_from_file_location("verification_gate", SCRIPT)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)
FIXTURES = Path(__file__).with_name("fixtures")


class GateTests(unittest.TestCase):
    def setUp(self):
        base = gate.ROOT / ".verification" / gate.session_name() / "gate-unit-tests"
        base.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=base)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.managed_builder = gate.managed

    def managed_test_command(self, key, command):
        # The quality worker already owns the project's managed-build lock.
        if os.environ.get("MANAGED_BUILD_DIR"):
            output = Path(os.environ["MANAGED_BUILD_DIR"]) / "gate-unit" / key
            output.mkdir(parents=True, exist_ok=True)
            return [str(Path.home() / ".agents/scripts/compact-test"), "--full", key,
                    *(argument.replace("{build_dir}", str(output)) for argument in command)]
        return self.managed_builder(key, command)

    def event_file(self, name, transform):
        rows = [json.loads(line) for line in (FIXTURES / name).read_text().splitlines()]
        target = self.root / "events.jsonl"
        target.write_text("\n".join(json.dumps(row) for row in transform(rows)) + "\n")
        return target

    def test_measured_fake_run_has_exactly_thirteen_successful_ids(self):
        self.assertEqual(len(gate.check_fake_events(FIXTURES / "swift-testing-fake.jsonl")), 13)

    def test_fake_missing_completion_run_end_skip_issue_and_unknown_version_fail(self):
        transforms = [
            lambda rows: [row for row in rows if row["payload"]["kind"] != "testEnded"],
            lambda rows: rows[:-1],
            lambda rows: [{**row, "version": 99} for row in rows],
            lambda rows: rows + [{"version": 0, "kind": "event", "payload": {"kind": "testSkipped"}}],
            lambda rows: rows + [{"version": 0, "kind": "event", "payload": {"kind": "issueRecorded", "issue": {"isKnown": True}}}],
            lambda rows: [],
        ]
        for transform in transforms:
            with self.subTest(transform=transform), self.assertRaises(gate.GateError):
                gate.check_fake_events(self.event_file("swift-testing-fake.jsonl", transform))

    def test_unselected_function_and_nonpassing_completion_fail(self):
        def rename(rows):
            rows[1]["payload"]["testID"] = "DashboardFeatureTests.RealClaudeReadinessE2ETests/realClaude_inputAcceptedAfterSessionStartHook()/file.swift:1:1"
            return rows
        with self.assertRaises(gate.GateError):
            gate.check_fake_events(self.event_file("swift-testing-fake.jsonl", rename))
        def nonpassing(rows):
            for row in rows:
                if row["payload"]["kind"] == "testEnded" and "/" in row["payload"].get("testID", ""):
                    row["payload"]["messages"] = [{"symbol": "passWithKnownIssue"}]
                    break
            return rows
        with self.assertRaises(gate.GateError):
            gate.check_fake_events(self.event_file("swift-testing-fake.jsonl", nonpassing))

    def test_only_existing_known_issue_is_preserved_and_not_a_pass(self):
        combined = self.root / "combined.jsonl"
        combined.write_bytes((FIXTURES / "swift-testing-regular.jsonl").read_bytes() + (FIXTURES / "swift-testing-known.jsonl").read_bytes())
        result = gate.check_regular_events([combined])
        self.assertEqual(len(result["unresolvedKnownIssues"]), 1)
        self.assertNotIn(gate.KNOWN_ISSUE, result["passedIDs"])
        def unknown(rows):
            for row in rows:
                if row["payload"]["kind"] == "issueRecorded":
                    row["payload"]["testID"] = "OtherTests.Suite/unknown()"
            return rows
        with self.assertRaises(gate.GateError):
            gate.check_regular_events([self.event_file("swift-testing-known.jsonl", unknown)])

    def test_optional_skip_does_not_make_an_ordinary_run_fail(self):
        def skip(rows):
            return rows + [{"version": 0, "kind": "event", "payload": {"kind": "testSkipped", "testID": "CodexAppServerKitTests.CodexAppServerE2ETests/threadStartWithExplicitSources()/file.swift:1:1"}}]
        result = gate.check_regular_events([self.event_file("swift-testing-regular.jsonl", skip)])
        self.assertEqual(result["skippedIDs"], ["CodexAppServerKitTests.CodexAppServerE2ETests/threadStartWithExplicitSources()"])
        self.assertTrue(result["passedIDs"])

    def test_unknown_mandatory_or_suite_skip_is_rejected(self):
        for ident in ("APNsClientTests.APNsSenderTests/sendUsesProductionHost()", "OptionalTests.Suite/optIn()", "APNsClientTests.APNsSenderTests", ""):
            def skip(rows):
                return rows + [{"version": 0, "kind": "event", "payload": {"kind": "testSkipped", "testID": ident}}]
            with self.subTest(ident=ident), self.assertRaises(gate.GateError):
                gate.check_regular_events([self.event_file("swift-testing-regular.jsonl", skip)])

    def test_xctest_skip_requires_explicit_optional_classification(self):
        log = self.root / "xctest.log"
        summary = "✔ Test run with 1 test in 1 suite passed after 0.001 seconds.\n"
        allowed = "Test Case '-[DashboardFeatureTests.MarkdownScrollPerformanceTests testScrollFrames]' skipped (0.001 seconds).\n"
        log.write_text(allowed + summary)
        self.assertEqual(gate.check_test_log(log)["skipped"], [allowed.strip()])
        for ident in ("-[APNsClientTests.APNsSenderTests testSend]", "-[OtherTests.MarkdownScrollPerformanceTests testScrollFrames]"):
            log.write_text(f"Test Case '{ident}' skipped (0.001 seconds).\n" + summary)
            with self.subTest(ident=ident), self.assertRaises(gate.GateError):
                gate.check_test_log(log)

    def test_nested_optional_function_does_not_allow_skipping_its_mandatory_sibling(self):
        prefix = "DashboardFeatureTests.ThemeRenderingTests/CodeSyntaxPerformanceTests/"
        for name, optional in (("measureEditorInputAndHighlightCompletion", True), ("oversizedAndLongLineDocumentsRemainPlain", False)):
            ident = prefix + name + "()"
            def skip(rows):
                return rows + [{"version": 0, "kind": "event", "payload": {"kind": "testSkipped", "testID": ident + "/CodeSyntaxPerformanceTests.swift:20:6"}}]
            path = self.event_file("swift-testing-regular.jsonl", skip)
            if optional:
                self.assertIn(ident, gate.check_regular_events([path])["skippedIDs"])
            else:
                with self.assertRaises(gate.GateError):
                    gate.check_regular_events([path])

    def test_top_level_function_success_does_not_require_a_suite_path(self):
        ident = "CursorAgentKitTests.cursorTurnStartOmitsModelAndModeWhenUnset()"
        path = self.root / "top-level.jsonl"
        rows = [{"version": 0, "kind": "event", "payload": {"kind": kind, **extra}} for kind, extra in (
            ("runStarted", {}), ("testStarted", {"testID": ident + "/CursorAgentKitTests.swift:1:6"}),
            ("testEnded", {"testID": ident + "/CursorAgentKitTests.swift:1:6", "messages": [{"symbol": "pass"}]}), ("runEnded", {}))]
        path.write_text("\n".join(json.dumps(row) for row in rows) + "\n")
        self.assertEqual(gate.check_regular_events([path])["passedIDs"], [ident])

    def test_zero_tests_and_unknown_text_summary_are_not_success(self):
        for text in ("✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.\n", "Build complete!\n"):
            log = self.root / "zero.log"
            log.write_text(text)
            with self.assertRaises(gate.GateError):
                gate.check_test_log(log)

    def git_repo(self):
        subprocess.run(["git", "init", "--quiet", str(self.root)], check=True)
        return self.root

    def test_appcast_signature_update_preserves_build_inputs_but_requires_review(self):
        self.git_repo()
        (self.root / "app.swift").write_text("let release = 1\n")
        (self.root / "site").mkdir()
        feed = self.root / "site/appcast.xml"
        feed.write_text("<rss><channel/></rss>\n")
        source = self.tree_commit()
        before = gate.input_manifest(self.root)
        feed.write_text('<rss><channel><item signature="generated-after-build"/></channel></rss>\n')
        target = self.tree_commit()
        self.assertNotEqual(gate.diff_hash(source, target, self.root), gate.diff_hash(source, source, self.root))
        self.assertEqual(gate.input_manifest(self.root, source), gate.input_manifest(self.root, target))
        self.assertEqual(before, gate.input_manifest(self.root))

    def tree_commit(self):
        subprocess.run(["git", "add", "."], cwd=self.root, check=True)
        tree = gate.git("write-tree", root=self.root)
        previous = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=self.root, capture_output=True, text=True)
        parents = ["-p", previous.stdout.strip()] if previous.returncode == 0 else []
        oid = subprocess.check_output(["git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit-tree", tree, *parents], cwd=self.root, input=b"Synthetic test fixture\n").decode().strip()
        subprocess.run(["git", "update-ref", "HEAD", oid], cwd=self.root, check=True)
        return oid

    def test_document_add_delete_is_not_build_input_but_new_code_is(self):
        self.git_repo()
        (self.root / "app.swift").write_text("let value = 1\n")
        first = self.tree_commit()
        (self.root / "macos/docs").mkdir(parents=True)
        (self.root / "macos/docs/note.md").write_text("documentation\n")
        second = self.tree_commit()
        self.assertEqual(gate.input_manifest(self.root, first), gate.input_manifest(self.root, second))
        (self.root / "new.swift").write_text("let another = 2\n")
        third = self.tree_commit()
        self.assertNotEqual(gate.input_manifest(self.root, first), gate.input_manifest(self.root, third))
        (self.root / "macos/docs/note.md").unlink()
        fourth = self.tree_commit()
        self.assertEqual(gate.input_manifest(self.root, third), gate.input_manifest(self.root, fourth))

    def test_review_and_record_additions_do_not_change_content_diff(self):
        self.git_repo()
        (self.root / "app.swift").write_text("let value = 1\n")
        first = self.tree_commit()
        (self.root / "app.swift").write_text("let value = 2\n")
        second = self.tree_commit()
        (self.root / "release").mkdir()
        (self.root / gate.REVIEWS).write_text('{"schemaVersion":1,"reviews":[]}\n')
        (self.root / gate.RECORDS).write_text('{"schemaVersion":1,"builds":[]}\n')
        third = self.tree_commit()
        self.assertEqual(gate.diff_hash(first, second, self.root), gate.diff_hash(first, third, self.root))
        self.assertEqual(gate.input_manifest(self.root, second), gate.input_manifest(self.root, third))

    def test_scenario_hash_tracks_selected_content_without_link_metadata(self):
        doc = self.root / "requirements.md"
        doc.write_text("---\ndate: old\n---\n| AC-1 | Observe [state](old-url) |\n| AC-2 | Other |\n")
        scenario = {"scenarioID": "fixture", "revision": 1, "method": "physical-device", "required": True, "procedure": "Observe", "expected": "Correct state", "requirement": "requirements.md#AC-1"}
        first = gate.scenario_hash(scenario, self.root)
        doc.write_text(doc.read_text().replace("date: old", "date: new").replace("old-url", "new-url").replace("Other", "Unrelated"))
        self.assertEqual(first, gate.scenario_hash(scenario, self.root))
        doc.write_text(doc.read_text().replace("Observe", "Stop observing"))
        self.assertNotEqual(first, gate.scenario_hash(scenario, self.root))

    def test_environment_cannot_reduce_scope_or_enable_external_agents(self):
        for key in ("SWIFT_TEST_SKIP", "SWIFT_TEST_FILTER", "SWIFT_TEST_PACKAGES", "SWIFT_TEST_GIT_SUITES", "SWIFT_TEST_SERIAL_PACKAGES", "SWIFT_TESTING_FILTER", "SWT_TEST_FILTER", "_SWT_TEST_FILTER", "XCTestConfigurationFilePath"):
            with self.subTest(key=key), patch.dict(os.environ, {key: "1"}, clear=True), self.assertRaises(gate.GateError):
                gate.clean_environment()

    def test_live_flags_and_private_app_inputs_do_not_reach_children(self):
        private = {"PHLOX_USAGE_LIVE": "1", "PHLOX_CODEX_E2E": "1", "PHLOX_SCROLL_PERFORMANCE": "1", "PHLOX_GATE_INTERACTIVE": "1", "PHLOX_DESIGN_SNAPSHOTS": "1", "PHLOX_DATA_DIR": "/private-fixture", "PHLOX_TOKEN": "fixture-only-token", "PHLOX_E2E": "1", "PATH": "/fixture-bin"}
        with patch.dict(os.environ, private, clear=True):
            child = gate.clean_environment()
            self.assertEqual({key for key in child if key.startswith("PHLOX_")}, {"PHLOX_E2E"})
            self.assertEqual(child["PHLOX_E2E"], "0")
            self.assertEqual(child["PATH"], "/fixture-bin")
            fake = dict(child, PHLOX_E2E="1")
            self.assertEqual(fake["PHLOX_E2E"], "1")
            self.assertEqual(os.environ["PHLOX_DATA_DIR"], "/private-fixture")

    def test_effective_settings_reject_simulator_wrong_build_and_no_signing(self):
        settings = [{"buildSettings": {"PRODUCT_BUNDLE_IDENTIFIER": "fixture.app", "MARKETING_VERSION": "1", "CURRENT_PROJECT_VERSION": "2", "PLATFORM_NAME": "iphoneos", "CODE_SIGNING_ALLOWED": "YES", "CODE_SIGN_IDENTITY": "Fixture signing"}}]
        gate.validate_build_settings(settings, "ios", "fixture.app", "1", "2")
        for key, value in (("PLATFORM_NAME", "iphonesimulator"), ("CURRENT_PROJECT_VERSION", "3"), ("CODE_SIGNING_ALLOWED", "NO")):
            wrong = copy.deepcopy(settings)
            wrong[0]["buildSettings"][key] = value
            with self.subTest(key=key), self.assertRaises(gate.GateError):
                gate.validate_build_settings(wrong, "ios", "fixture.app", "1", "2")

    def test_missing_real_observation_and_mismatched_evidence_fail(self):
        scenario = {"scenarioID": "fixture", "required": True, "method": "physical-device"}
        with self.assertRaisesRegex(gate.GateError, "not_run"):
            gate.validate_physical_records({"schemaVersion": 1, "builds": [], "devices": [], "executions": []}, [scenario], {}, {}, self.root)
        evidence = self.root / "evidence.txt"
        evidence.write_text("actual bytes")
        with self.assertRaisesRegex(gate.GateError, "hash mismatch"):
            gate.verify_file({"path": evidence.name, "sha256": "0" * 64}, self.root)

    def ios_artifact(self, app_changes=None, widget_changes=None):
        app = {"CFBundleIdentifier": "fixture.ios", "CFBundleShortVersionString": "1", "CFBundleVersion": "2"}
        widget = {**app, "CFBundleIdentifier": "fixture.ios.PhloxWidget"}
        app.update(app_changes or {})
        widget.update(widget_changes or {})
        output = io.BytesIO()
        with zipfile.ZipFile(output, "w") as archive:
            archive.writestr("Payload/Fixture.app/Info.plist", gate.plistlib.dumps(app))
            archive.writestr("Payload/Fixture.app/PlugIns/Widget.appex/Info.plist", gate.plistlib.dumps(widget))
        return output.getvalue()

    def test_ios_ipa_requires_actual_identity_for_app_and_widget(self):
        path = self.root / "fixture.ipa"
        path.write_bytes(self.ios_artifact())
        gate.validate_ios_artifact(path, "fixture.ios", "1", "2")
        for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"):
            for bundle in ("app", "widget"):
                with self.subTest(key=key, bundle=bundle):
                    changes = {key: "wrong"}
                    path.write_bytes(self.ios_artifact(changes if bundle == "app" else None,
                                                       changes if bundle == "widget" else None))
                    with self.assertRaisesRegex(gate.GateError, "iOS bundle identity"):
                        gate.validate_ios_artifact(path, "fixture.ios", "1", "2")
        for data in (b"not a ZIP", io.BytesIO().getvalue()):
            path.write_bytes(data)
            with self.assertRaises(gate.GateError):
                gate.validate_ios_artifact(path, "fixture.ios", "1", "2")
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("Payload/Fixture.app/Info.plist", b"not a plist")
        with self.assertRaises(gate.GateError):
            gate.validate_ios_artifact(path, "fixture.ios", "1", "2")

    def physical_fixture(self):
        self.git_repo()
        (self.root / ".gitignore").write_text("fixture-output/\n.verification/\n")
        (self.root / "app.swift").write_text("let fixture = true\n")
        (self.root / "macos/docs").mkdir(parents=True)
        (self.root / "macos/docs/requirements.md").write_text("| AC-1 | Observe the actual result |\n")
        source = self.tree_commit()
        manifest = gate.input_manifest(self.root, source)
        out = self.root / "fixture-output"
        out.mkdir()
        def file(name, data):
            path = out / name
            path.write_bytes(data)
            return {"path": path.relative_to(self.root).as_posix(), "sha256": gate.digest(data)}
        evidence = file("evidence.txt", b"SYNTHETIC UNIT TEST EVIDENCE, NOT A REAL OBSERVATION\n")
        scenario = {"scenarioID": "fixture", "revision": 1, "method": "physical-device", "required": True, "procedure": "Observe", "expected": "Actual result", "requirement": "macos/docs/requirements.md#AC-1"}
        data = {"schemaVersion": 1, "builds": [], "devices": [], "executions": []}
        pair = {}
        for platform in ("macos", "ios"):
            artifact = file(platform + ".bin", self.ios_artifact() if platform == "ios" else b"SYNTHETIC macos")
            settings = [{"buildSettings": {"PRODUCT_BUNDLE_IDENTIFIER": "fixture." + platform, "MARKETING_VERSION": "1", "CURRENT_PROJECT_VERSION": "2", "PLATFORM_NAME": "macosx" if platform == "macos" else "iphoneos", "CODE_SIGNING_ALLOWED": "YES", "CODE_SIGN_IDENTITY": "Fixture only"}}]
            settings_file = file(platform + "-settings.json", json.dumps(settings).encode())
            provenance = {"schemaVersion": 1, "sourceOID": source, "platform": platform, "startedAt": "2026-10-24T01:00:00+00:00", "finishedAt": "2026-10-24T02:00:00+00:00", "inputManifest": manifest, "toolchain": {"xcode": "Fixture Xcode", "sdk": "Fixture SDK"}, "settingsSHA256": gate.digest(gate.canonical(settings)), "settingsPath": settings_file["path"], "externalInputs": [settings_file], "bundleID": "fixture." + platform, "version": "1", "buildNumber": "2", "artifact": artifact}
            if platform == "macos":
                provenance["sparkleZIP"] = file("Phlox-1.zip", b"SYNTHETIC ZIP, NOT A DISTRIBUTION")
            provenance_file = file(platform + "-provenance.json", json.dumps(provenance).encode())
            data["builds"].append({"buildID": platform, "provenance": provenance_file})
            data["devices"].append({"deviceID": platform, "platform": platform, "physical": True, "model": "fixture", "osVersion": "1", "osBuild": "fixture", "identityEvidence": evidence})
            pair[platform] = {"buildID": platform, "deviceID": platform, "bundleID": "fixture." + platform, "version": "1", "buildNumber": "2", "artifactSHA256": artifact["sha256"], "installationEvidence": evidence}
        data["executions"].append({"scenarioID": "fixture", "revision": 1, "scenarioSHA256": gate.scenario_hash(scenario, self.root), "result": "passed", "observer": {"kind": "human", "id": "synthetic-test-only"}, "executedAt": "2026-10-24T03:00:00+00:00", "observations": "SYNTHETIC TEST FIXTURE", "pair": pair, "evidence": [evidence]})
        return data, [scenario], manifest, {"fixture": True}

    def test_physical_record_fixture_and_required_negative_cases(self):
        data, scenarios, manifest, tools = self.physical_fixture()
        gate.validate_physical_records(data, scenarios, manifest, tools, self.root)
        mutations = [
            lambda d: d["devices"][0].update(physical=False),
            lambda d: d["devices"][0].pop("model"),
            lambda d: d["devices"][0].pop("osBuild"),
            lambda d: d["executions"][0].update(result="not_run"),
            lambda d: d["executions"][0].update(revision=2),
            lambda d: d["executions"][0].update(scenarioSHA256="0" * 64),
            lambda d: d["executions"][0].update(observer={"kind": "ai", "id": "reviewer"}),
            lambda d: d["executions"][0].update(executedAt="2026-10-24T03:00:00"),
            lambda d: d["executions"][0].update(evidence=[]),
            lambda d: d["executions"][0]["pair"]["macos"].update(buildID="ios"),
            lambda d: d["executions"][0]["pair"]["ios"].update(buildNumber="other"),
            lambda d: d["executions"][0]["pair"]["macos"].update(artifactSHA256="0" * 64),
        ]
        for mutation in mutations:
            changed = copy.deepcopy(data)
            mutation(changed)
            with self.subTest(mutation=mutation), self.assertRaises(gate.GateError):
                gate.validate_physical_records(changed, scenarios, manifest, tools, self.root)
        with self.assertRaisesRegex(gate.GateError, "DMG"):
            gate.validate_physical_records(data, scenarios, manifest, tools, self.root, dmg_sha256="0" * 64)

    def test_ios_provenance_rejects_wrong_embedded_version_even_with_matching_hashes(self):
        data, scenarios, manifest, tools = self.physical_fixture()
        build = next(b for b in data["builds"] if b["buildID"] == "ios")
        provenance_path = self.root / build["provenance"]["path"]
        provenance = json.loads(provenance_path.read_text())
        artifact = self.root / provenance["artifact"]["path"]
        artifact.write_bytes(self.ios_artifact({"CFBundleShortVersionString": "1.0"}))
        provenance["artifact"]["sha256"] = gate.digest(artifact.read_bytes())
        data["executions"][0]["pair"]["ios"]["artifactSHA256"] = provenance["artifact"]["sha256"]
        provenance_path.write_text(json.dumps(provenance))
        build["provenance"]["sha256"] = gate.digest(provenance_path.read_bytes())
        with self.assertRaisesRegex(gate.GateError, "iOS bundle identity"):
            gate.validate_physical_records(data, scenarios, manifest, tools, self.root)

    def test_docs_only_build_reuse_but_source_change_is_stale(self):
        data, scenarios, manifest, tools = self.physical_fixture()
        (self.root / "macos/docs/new.md").write_text("New document\n")
        docs = self.tree_commit()
        gate.validate_physical_records(data, scenarios, gate.input_manifest(self.root, docs), tools, self.root)
        (self.root / "new.swift").write_text("let additional = true\n")
        code = self.tree_commit()
        with self.assertRaisesRegex(gate.GateError, "Stale build inputs"):
            gate.validate_physical_records(data, scenarios, gate.input_manifest(self.root, code), tools, self.root)

    def test_latest_physical_failure_cannot_be_hidden_by_old_pass_placement(self):
        data, scenarios, manifest, tools = self.physical_fixture()
        old_pass = copy.deepcopy(data["executions"][0])
        old_pass["executedAt"] = "2026-10-24T05:00:00+02:00"
        new_failure = copy.deepcopy(old_pass)
        new_failure.update(result="failed", executedAt="2026-10-24T04:00:00+00:00")
        for rows in ([new_failure, old_pass], [old_pass, new_failure]):
            data["executions"] = rows
            with self.subTest(order=[row["result"] for row in rows]), self.assertRaisesRegex(gate.GateError, "not passed"):
                gate.validate_physical_records(data, scenarios, manifest, tools, self.root)

    def test_latest_physical_pass_recovers_from_old_failure(self):
        data, scenarios, manifest, tools = self.physical_fixture()
        old_failure = copy.deepcopy(data["executions"][0])
        old_failure.update(result="failed", executedAt="2026-10-24T05:00:00+02:00")
        new_pass = copy.deepcopy(old_failure)
        new_pass.update(result="passed", executedAt="2026-10-24T04:00:00+00:00")
        for rows in ([new_pass, old_failure], [old_failure, new_pass]):
            data["executions"] = rows
            with self.subTest(order=[row["result"] for row in rows]):
                gate.validate_physical_records(data, scenarios, manifest, tools, self.root)

    def test_conflicting_physical_results_at_same_instant_are_rejected(self):
        data, scenarios, manifest, tools = self.physical_fixture()
        passed = copy.deepcopy(data["executions"][0])
        failed = copy.deepcopy(passed)
        failed.update(result="failed", executedAt="2026-10-24T05:00:00+02:00")
        for rows in ([failed, passed], [passed, failed]):
            data["executions"] = rows
            with self.subTest(order=[row["result"] for row in rows]), self.assertRaisesRegex(gate.GateError, "Conflicting"):
                gate.validate_physical_records(data, scenarios, manifest, tools, self.root)
        data["executions"] = [passed, copy.deepcopy(passed)]
        gate.validate_physical_records(data, scenarios, manifest, tools, self.root)

    def test_ascii_lf_keeps_measured_unicode_separators_inside_json_strings(self):
        raw = (FIXTURES / "swift-testing-unicode.jsonl").read_bytes()
        self.assertGreater(len(raw.decode().splitlines()), 1)
        path = self.root / "unicode.jsonl"
        path.write_bytes(raw + (FIXTURES / "swift-testing-regular.jsonl").read_bytes())
        self.assertTrue(gate.check_regular_events([path])["passedIDs"])

    def test_each_ordinary_stream_must_have_its_own_success_and_end(self):
        regular = FIXTURES / "swift-testing-regular.jsonl"
        zero = self.root / "zero.jsonl"
        zero.write_text('\n'.join(json.dumps({"version": 0, "kind": "event", "payload": {"kind": kind}}) for kind in ("runStarted", "testSkipped", "runEnded")) + '\n')
        for paths in ([regular, zero], [regular, FIXTURES / "swift-testing-known.jsonl"]):
            with self.subTest(paths=paths), self.assertRaises(gate.GateError):
                gate.check_regular_events(paths)
        for drop in ("runStarted", "runEnded"):
            path = self.event_file("swift-testing-regular.jsonl", lambda rows: [row for row in rows if row["payload"]["kind"] != drop])
            with self.subTest(drop=drop), self.assertRaises(gate.GateError):
                gate.check_regular_events([path])

    def test_mac_event_set_is_exactly_twenty_files_and_package_drift_stops(self):
        events = self.root / "events"
        events.mkdir()
        names = [f"{p}-all.jsonl" for p in gate.MACOS_PACKAGES if p != "DashboardFeature"] + ["DashboardFeature-main.jsonl", "DashboardFeature-git.jsonl"]
        for name in names:
            (events / name).write_bytes((FIXTURES / "swift-testing-regular.jsonl").read_bytes())
        self.assertEqual(len(gate.regular_event_paths(events, gate.MACOS_PACKAGES)), 20)
        (events / names[0]).unlink()
        with self.assertRaises(gate.GateError):
            gate.regular_event_paths(events, gate.MACOS_PACKAGES)
        (events / names[0]).touch()
        (events / "unexpected.jsonl").touch()
        with self.assertRaises(gate.GateError):
            gate.regular_event_paths(events, gate.MACOS_PACKAGES)
        for package in gate.MACOS_PACKAGES:
            path = self.root / "macos/Packages" / package / "Package.swift"
            path.parent.mkdir(parents=True)
            path.write_text("// fixture manifest\n")
        gate.validate_package_scope(self.root)
        (self.root / "macos/Packages/NewPackage").mkdir()
        (self.root / "macos/Packages/NewPackage/Package.swift").touch()
        with self.assertRaises(gate.GateError):
            gate.validate_package_scope(self.root)

    def test_reused_build_number_other_mac_and_empty_physical_set_fail(self):
        data, scenarios, manifest, tools = self.physical_fixture()
        reference = data["builds"][0]["provenance"]
        original = json.loads((self.root / reference["path"]).read_text())
        other = copy.deepcopy(original)
        artifact = self.root / "fixture-output/other-mac.bin"
        artifact.write_bytes(b"SYNTHETIC DIFFERENT MAC BUILD")
        other["artifact"] = {"path": artifact.relative_to(self.root).as_posix(), "sha256": gate.digest(artifact.read_bytes())}
        proof = self.root / "fixture-output/other-mac.json"
        proof.write_text(json.dumps(other))
        changed = copy.deepcopy(data)
        changed["builds"].append({"buildID": "other-mac", "provenance": {"path": proof.relative_to(self.root).as_posix(), "sha256": gate.digest(proof.read_bytes())}})
        with self.assertRaisesRegex(gate.GateError, "Build number reused"):
            gate.validate_physical_records(changed, scenarios, manifest, tools, self.root)
        other["buildNumber"] = "3"
        settings = self.root / "fixture-output/other-settings.json"
        values = json.loads((self.root / original["settingsPath"]).read_text())
        values[0]["buildSettings"]["CURRENT_PROJECT_VERSION"] = "3"
        settings.write_text(json.dumps(values))
        other.update(settingsPath=settings.relative_to(self.root).as_posix(), settingsSHA256=gate.digest(gate.canonical(values)), externalInputs=[{"path": settings.relative_to(self.root).as_posix(), "sha256": gate.digest(settings.read_bytes())}])
        proof.write_text(json.dumps(other))
        changed["builds"][-1]["provenance"]["sha256"] = gate.digest(proof.read_bytes())
        changed["executions"][0]["pair"]["macos"].update(buildID="other-mac", buildNumber="3", artifactSHA256=other["artifact"]["sha256"])
        with self.assertRaisesRegex(gate.GateError, "DMG"):
            gate.validate_physical_records(changed, scenarios, manifest, tools, self.root, dmg_sha256=original["artifact"]["sha256"])
        with self.assertRaisesRegex(gate.GateError, "set disappeared"):
            gate.validate_physical_records(data, [], manifest, tools, self.root)

    def git_in_fixture(self, *args, **kwargs):
        return self.saved_git(*args, root=self.root)

    def test_capture_measures_before_and_after_and_writes_relative_provenance(self):
        # This standalone fixture must not inherit another repository's merge context.
        self.enterContext(patch.dict(os.environ, {key: value for key, value in os.environ.items() if not key.startswith("GITFLOW_")}, clear=True))
        self.physical_fixture()
        self.saved_git = gate.git
        args = SimpleNamespace(evidence_root=str(self.root), artifact="fixture-output/captured.bin", zip="fixture-output/captured.zip", output="fixture-output/captured.json", settings="fixture-output/macos-settings.json", external_input=[], platform="macos", bundle_id="fixture.macos", version="1", build_number="2", command=["fixture-builder", "--output", "{build_dir}"])
        commands = []
        def build(command, log):
            commands.append(command)
            (self.root / args.artifact).write_bytes(b"SYNTHETIC CAPTURED ARTIFACT")
            (self.root / args.zip).write_bytes(b"SYNTHETIC CAPTURED ZIP")
        with patch.object(gate, "ROOT", self.root), patch.object(gate, "git", side_effect=self.git_in_fixture), patch.object(gate, "toolchain", return_value={"xcode": "Historical Xcode", "sdk": "Historical SDK"}), patch.object(gate, "run_stage", side_effect=build), redirect_stdout(io.StringIO()):
            gate.capture_build(args)
        record = json.loads((self.root / args.output).read_text())
        self.assertEqual(record["sourceOID"], self.saved_git("rev-parse", "HEAD", root=self.root))
        self.assertEqual(record["artifact"]["sha256"], gate.digest((self.root / args.artifact).read_bytes()))
        self.assertEqual(record["sparkleZIP"]["sha256"], gate.digest((self.root / args.zip).read_bytes()))
        self.assertNotIn(str(self.root), json.dumps(record))
        self.assertIn("managed-build.py", " ".join(commands[0]))
        (self.root / args.artifact).unlink()
        (self.root / args.zip).unlink()
        (self.root / args.output).unlink()
        def mutate(command, log):
            build(command, log)
            (self.root / "app.swift").write_text("let fixture = false\n")
        with patch.object(gate, "ROOT", self.root), patch.object(gate, "git", side_effect=self.git_in_fixture), patch.object(gate, "toolchain", return_value={"xcode": "Historical Xcode", "sdk": "Historical SDK"}), patch.object(gate, "run_stage", side_effect=mutate), self.assertRaisesRegex(gate.GateError, "inputs changed"):
            gate.capture_build(args)
        self.assertFalse((self.root / args.output).exists())

    def test_ios_capture_rejects_embedded_version_before_writing_provenance(self):
        data, _, _, _ = self.physical_fixture()
        settings = next(b for b in data["builds"] if b["buildID"] == "ios")
        record = json.loads((self.root / settings["provenance"]["path"]).read_text())
        args = SimpleNamespace(evidence_root=str(self.root), artifact="fixture-output/captured.ipa", zip=None,
                               settings=record["settingsPath"], output="fixture-output/capture.json", external_input=[],
                               platform="ios", bundle_id="fixture.ios", version="1", build_number="2",
                               command=["fixture-builder", "{build_dir}"])
        def build(command, log):
            (self.root / args.artifact).write_bytes(self.ios_artifact(widget_changes={"CFBundleShortVersionString": "1.0"}))
        self.saved_git = gate.git
        fixture_oid = self.saved_git("rev-parse", "HEAD", root=self.root)
        with patch.dict(os.environ, {"GITFLOW_MERGE_CANDIDATE": fixture_oid}), \
                patch.object(gate, "ROOT", self.root), patch.object(gate, "git", side_effect=self.git_in_fixture), \
                patch.object(gate, "toolchain", return_value={"xcode": "Fixture Xcode", "sdk": "Fixture SDK"}), \
                patch.object(gate, "run_stage", side_effect=build), redirect_stdout(io.StringIO()), \
                self.assertRaisesRegex(gate.GateError, "iOS bundle identity"):
            gate.capture_build(args)
        self.assertFalse((self.root / args.output).exists())

    def test_release_uses_explicit_evidence_root_and_historical_toolchain(self):
        data, scenarios, manifest, tools = self.physical_fixture()
        path = self.root / "fixture-output/records.json"
        path.write_text(json.dumps(data))
        self.saved_git = gate.git
        head = self.saved_git("rev-parse", "HEAD", root=self.root)
        args = SimpleNamespace(record=str(path), evidence_root=str(self.root), dmg="fixture-output/macos.bin", zip="fixture-output/Phlox-1.zip")
        with patch.object(gate, "ROOT", self.root), patch.object(gate, "git", side_effect=self.git_in_fixture), patch.object(gate, "validate_scenarios", return_value=scenarios), patch.object(gate, "validate_distribution") as packaging, patch.object(gate, "toolchain", side_effect=AssertionError("Current SDK must not invalidate a historical artifact")), patch.dict(os.environ, {"GITFLOW_MERGE_CANDIDATE": head, "GITFLOW_MERGE_TO": head}, clear=True), redirect_stdout(io.StringIO()):
            gate.release(args)
            self.assertEqual(packaging.call_count, 1)
            copied_zip = self.root / "fixture-output/other.zip"
            copied_zip.write_bytes((self.root / args.zip).read_bytes())
            args.zip = copied_zip.relative_to(self.root).as_posix()
            with self.assertRaisesRegex(gate.GateError, "ZIP differs"):
                gate.release(args)
            args.zip = "fixture-output/Phlox-1.zip"
            duplicate = self.root / "fixture-output/copy.bin"
            duplicate.write_bytes((self.root / args.dmg).read_bytes())
            args.dmg = duplicate.relative_to(self.root).as_posix()
            with self.assertRaisesRegex(gate.GateError, "DMG"):
                gate.release(args)
        with self.assertRaises(gate.GateError):
            gate.verify_file({"path": "/not-a-relative-proof", "sha256": "0" * 64}, self.root)

    def distribution_app(self):
        app = self.root / "Phlox.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        executable = app / "Contents/MacOS/Phlox"
        executable.write_bytes(b"SYNTHETIC EXECUTABLE")
        executable.chmod(0o755)
        (app / "Contents/link").symlink_to("MacOS/Phlox")
        (app / "Contents/Info.plist").write_bytes(b"SYNTHETIC METADATA")
        return app

    def distribution_zip(self, app, transform=lambda entries: entries):
        entries = []
        for relative, (kind, size, sha, executable) in gate.app_contents(app).items():
            path = app / relative
            info = zipfile.ZipInfo(app.name + "/" + relative)
            info.external_attr = ((stat.S_IFLNK | 0o777) if kind == "symlink" else (stat.S_IFREG | 0o644 | executable)) << 16
            entries.append((info, os.fsencode(os.readlink(path)) if kind == "symlink" else path.read_bytes()))
        path = self.root / "Phlox-1.zip"
        with zipfile.ZipFile(path, "w") as archive:
            for info, content in transform(entries):
                archive.writestr(info, content)
        return path

    def test_zip_must_match_every_app_file_symlink_and_executable_permission(self):
        app = self.distribution_app()
        gate.compare_zip_app(self.distribution_zip(app), app)
        def changed_content(entries):
            return [(info, b"X" + data[1:] if info.filename.endswith("MacOS/Phlox") else data) for info, data in entries]
        def changed_mode(entries):
            for info, data in entries:
                if info.filename.endswith("MacOS/Phlox"):
                    info.external_attr = (stat.S_IFREG | 0o644) << 16
            return entries
        def changed_link(entries):
            return [(info, b"MacOS/Other" if info.filename.endswith("/link") else data) for info, data in entries]
        for transform in (lambda entries: entries[:-1], changed_content, changed_mode, changed_link):
            with self.subTest(transform=transform), self.assertRaises(gate.GateError):
                gate.compare_zip_app(self.distribution_zip(app, transform), app)
        for name in ("../escape", "/absolute", "Phlox.app/../escape", "Phlox.app/Contents/extra", "Other.app/file", "Phlox.app\\escape"):
            def extra(entries):
                info = zipfile.ZipInfo(name)
                info.external_attr = (stat.S_IFREG | 0o644) << 16
                return entries + [(info, b"extra")]
            with self.subTest(name=name), self.assertRaises(gate.GateError):
                gate.compare_zip_app(self.distribution_zip(app, extra), app)
        (app / "Contents/external").symlink_to(self.root)
        with self.assertRaisesRegex(gate.GateError, "External app symlink"):
            gate.app_contents(app)

    def test_zip_appledouble_requires_a_real_target_and_valid_metadata_header(self):
        app = self.distribution_app()
        for prefix in ("", "__MACOSX/"):
            def metadata(entries):
                info = zipfile.ZipInfo(prefix + "Phlox.app/Contents/MacOS/._Phlox")
                info.external_attr = (stat.S_IFREG | 0o644) << 16
                return entries + [(info, bytes.fromhex("0005160700020000"))]
            gate.compare_zip_app(self.distribution_zip(app, metadata), app)
        for name, mode, data in (
            ("Phlox.app/Contents/._missing", stat.S_IFREG | 0o644, bytes.fromhex("0005160700020000")),
            ("Phlox.app/Contents/MacOS/._Phlox", stat.S_IFREG | 0o644, b"not metadata"),
            ("__MACOSX/Phlox.app/Contents/MacOS/._Phlox", stat.S_IFLNK | 0o777, b"/outside"),
            ("Phlox.app/Contents/MacOS/", stat.S_IFLNK | 0o777, b"/outside"),
            ("__MACOSX/Phlox.app/Contents/extra", stat.S_IFREG | 0o644, b"extra"),
        ):
            def invalid(entries):
                info = zipfile.ZipInfo(name)
                info.external_attr = mode << 16
                return entries + [(info, data)]
            with self.subTest(name=name), self.assertRaises(gate.GateError):
                gate.compare_zip_app(self.distribution_zip(app, invalid), app)

    def test_mac_provenance_requires_the_original_zip_hash(self):
        data, scenarios, manifest, tools = self.physical_fixture()
        proof = data["builds"][0]["provenance"]
        path = self.root / proof["path"]
        record = json.loads(path.read_text())
        for invalid in (None, {"path": "fixture-output/Phlox-1.zip", "sha256": "0" * 64}):
            changed = {**record, "sparkleZIP": invalid}
            path.write_text(json.dumps(changed))
            proof["sha256"] = gate.digest(path.read_bytes())
            with self.subTest(invalid=invalid), self.assertRaises(gate.GateError):
                gate.validate_physical_records(data, scenarios, manifest, tools, self.root)

    def test_appcast_requires_unique_matching_build_url_length_and_signature(self):
        archive = self.root / "Phlox-1.zip"
        archive.write_bytes(b"SYNTHETIC ZIP")
        feed = self.root / "appcast.xml"
        build = {"version": "1", "buildNumber": "2"}
        item = '<item><sparkle:version>2</sparkle:version><sparkle:shortVersionString>1</sparkle:shortVersionString><enclosure url="https://github.com/HMNZK/phlox-dist/releases/download/updates/Phlox-1.zip" length="13" type="application/octet-stream" sparkle:edSignature="public-test-signature"/></item>'
        def write(items):
            feed.write_text('<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>' + items + '</channel></rss>')
        write(item)
        self.assertEqual(gate.distribution_signature(feed, build, archive), "public-test-signature")
        for changed in (item + item, item.replace(">2<", ">3<"), item.replace(">1<", ">0<"), item.replace("length=\"13\"", "length=\"12\""), item.replace("phlox-dist", "other"), item.replace("application/octet-stream", "text/plain"), item.replace('sparkle:edSignature="public-test-signature"', "")):
            write(changed)
            with self.subTest(changed=changed), self.assertRaises(gate.GateError):
                gate.distribution_signature(feed, build, archive)

    def test_appcast_rejects_dtd_external_entities_and_entity_expansion(self):
        feed = self.root / "appcast.xml"
        for declaration in ('<!DOCTYPE rss SYSTEM "file:///unread-external-file">', '<!DOCTYPE rss [<!ENTITY external SYSTEM "file:///unread-external-file">]>', '<!DOCTYPE rss [<!ENTITY value "expanded"><!ENTITY repeated "&value;&value;">]>'):
            feed.write_text(declaration + '<rss><channel/></rss>')
            with self.subTest(declaration=declaration), self.assertRaisesRegex(gate.GateError, "DTD/entity"):
                gate.read_appcast(feed)

    def test_cryptokit_verifies_real_ed25519_and_rejects_modified_content_and_key(self):
        # RFC 8032 test 1: public key and signature for an empty message; no private key.
        public = bytes.fromhex("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
        signature = bytes.fromhex("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b")
        message = self.root / "message.zip"
        message.touch()
        def verify(key, sig):
            command = self.managed_test_command("signature-unit-tests", ["xcrun", "swift", "-module-cache-path", "{build_dir}/module-cache", str(SCRIPT.with_name("verify-sparkle-signature.swift")), str(message), base64.b64encode(sig).decode(), base64.b64encode(key).decode()])
            return subprocess.run(command, capture_output=True, text=True)
        result = verify(public, signature)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        message.write_bytes(b"changed")
        self.assertNotEqual(verify(public, signature).returncode, 0)
        message.write_bytes(b"")
        self.assertNotEqual(verify(bytes(32), signature).returncode, 0)
        self.assertNotEqual(verify(public, signature[:-1]).returncode, 0)

    def test_native_distribution_path_verifies_signature_app_and_detaches_after_failure(self):
        output = self.root / "native-fixture"
        command = self.managed_test_command("native-distribution-unit", ["xcrun", "swift", "-module-cache-path", "{build_dir}/module-cache", str(FIXTURES / "distribution-app.swift"), "{build_dir}", str(output)])
        made = subprocess.run(command, capture_output=True, text=True)
        self.assertEqual(made.returncode, 0, made.stdout + made.stderr)
        self.git_repo()
        scripts = self.root / "macos/scripts"
        scripts.mkdir(parents=True)
        shutil.copy2(SCRIPT.with_name("verify-sparkle-signature.swift"), scripts)
        dmg, archive = output / "Phlox.dmg", output / "Phlox-1.zip"
        build = {"bundleID": "test.phlox.distribution", "version": "1", "buildNumber": "2", "artifact": {"sha256": gate.file_sha256(dmg)}, "sparkleZIP": {"sha256": gate.file_sha256(archive)}}
        signature = json.loads((output / "signature.json").read_text())["signature"]
        site = self.root / "site"
        site.mkdir()
        feed = site / "appcast.xml"
        def write(signature):
            feed.write_text(f'<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:version>2</sparkle:version><sparkle:shortVersionString>1</sparkle:shortVersionString><enclosure url="https://github.com/HMNZK/phlox-dist/releases/download/updates/Phlox-1.zip" length="{archive.stat().st_size}" type="application/octet-stream" sparkle:edSignature="{signature}"/></item></channel></rss>')
        write(signature)
        with patch.object(gate, "ROOT", self.root), patch.object(gate, "managed", side_effect=self.managed_test_command):
            gate.validate_distribution(dmg, archive, build, self.root)
            write(base64.b64encode(bytes(64)).decode())
            with self.assertRaisesRegex(gate.GateError, "Stage failed"):
                gate.validate_distribution(dmg, archive, build, self.root)
            write(signature)
            wrong_identity = {**build, "bundleID": "test.wrong"}
            with self.assertRaisesRegex(gate.GateError, "identity/version"):
                gate.validate_distribution(dmg, archive, wrong_identity, self.root)
        inspections = list((self.root / "distribution-checks").glob("inspection-*"))
        self.assertEqual(len(inspections), 3)
        self.assertTrue(all(not os.path.ismount(path / "volume") for path in inspections))

    def test_quality_evidence_survives_candidate_deletion(self):
        candidate = self.root / "candidate"
        candidate.mkdir()
        (candidate / "release").mkdir()
        (candidate / gate.SCENARIOS).write_text('{"schemaVersion":1,"scenarios":[]}\n')
        outside = self.root / "merge-run"
        commands = []
        with patch.object(gate, "ROOT", candidate), patch.object(gate, "candidate", return_value="1" * 40), patch.object(gate, "input_manifest", return_value={"sha256": "fixture", "files": []}), patch.object(gate, "validate_scenarios", return_value=[]), patch.object(gate, "run_stage", side_effect=lambda command, log, **kwargs: commands.append((command, log))), patch.dict(os.environ, {"GITFLOW_VERIFICATION_DIR": str(outside)}, clear=True), redirect_stdout(io.StringIO()):
            gate.quality(SimpleNamespace())
        self.assertTrue(commands)
        log = commands[0][1]
        self.assertTrue(log.is_relative_to(outside))
        shutil.rmtree(candidate)
        self.assertTrue((log.parent / "owner.json").is_file())

    def test_session_is_stable_for_prefixed_branch_and_uses_common_run(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(gate, "git", return_value="feature/gates"):
            session = gate.session_name()
            self.assertEqual(session, gate.session_name())
            self.assertNotIn("/", session)
        with patch.dict(os.environ, {"GITFLOW_VERIFICATION_DIR": "/fixture/gitflow-merge.unique"}, clear=True):
            self.assertEqual(gate.session_name(), "gitflow-merge.unique")

    def test_quality_worker_runs_required_stages_and_isolates_generated_sources(self):
        self.physical_fixture()
        for package in gate.MACOS_PACKAGES:
            path = self.root / "macos/Packages" / package / "Package.swift"
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("// fixture\n")
        original = self.root / "ios/App/Info.plist"
        original.parent.mkdir(parents=True)
        original.write_text("original source plist")
        self.tree_commit()
        out = self.root / ".verification/quality-fixture"
        build = self.root / ".verification/managed-output"
        out.mkdir(parents=True)
        build.mkdir()
        commands = []
        regular = (FIXTURES / "swift-testing-regular.jsonl").read_bytes()
        summary = "✔ Test run with 7 tests in 1 suite passed after 1.000 seconds.\n"
        def stage(command, log, **kwargs):
            commands.append(command)
            child_env = kwargs["env"]
            self.assertNotIn("PHLOX_USAGE_LIVE", child_env)
            self.assertNotIn("PHLOX_DATA_DIR", child_env)
            self.assertEqual(child_env["PHLOX_E2E"], "1" if log.name == "fake-e2e.log" else "0")
            log.write_text(summary)
            if log.name == "macos.log":
                events = out / "macos-events"
                events.mkdir()
                for package in gate.MACOS_PACKAGES:
                    labels = ["main", "git"] if package == "DashboardFeature" else ["all"]
                    for label in labels:
                        (events / f"{package}-{label}.jsonl").write_bytes(regular)
            elif log.name == "ios-tests.log":
                (out / "ios-events/PhloxKit.jsonl").write_bytes(regular)
            elif log.name == "ios-build.log":
                copied = build / "_ios-source" / out.name / "ios/App/Info.plist"
                self.assertTrue(copied.is_file())
                copied.write_text("generated fixture plist")
            elif log.name == "fake-e2e.log":
                (out / "events").mkdir()
                (out / "events/DashboardFeature-filtered.jsonl").write_bytes((FIXTURES / "swift-testing-fake.jsonl").read_bytes())
        self.saved_git = gate.git
        with patch.object(gate, "ROOT", self.root), patch.object(gate, "git", side_effect=self.git_in_fixture), patch.object(gate, "run_stage", side_effect=stage), patch.object(gate.shutil, "which", return_value="/fixture/xcodegen"), patch.dict(os.environ, {"MANAGED_BUILD_DIR": str(build), "PHLOX_USAGE_LIVE": "1", "PHLOX_DATA_DIR": "/private-fixture"}, clear=True), redirect_stdout(io.StringIO()):
            gate.quality_worker(SimpleNamespace(output=str(out), build_dir=str(build)))
        self.assertEqual(original.read_text(), "original source plist")
        self.assertEqual(len(commands), 9)
        self.assertIn("discover", commands[0])
        self.assertIn("test_verification_gate*.py", commands[0])
        self.assertIn("test_prepare_ad_hoc.py", commands[1])
        self.assertIn("macos/scripts/tests/run-swift-tests-output.test.sh", commands[2])
        self.assertIn("test_session_runtime_lifecycle_api.py", commands[3])
        self.assertIn("TerminalUI", commands[4])
        self.assertTrue((out / "result.json").is_file())
        self.assertFalse((out / "source").exists())

    def test_make_preserves_first_xcode_failure_without_retry(self):
        binary = self.root / "bin"
        binary.mkdir()
        calls = self.root / "calls.txt"
        scripts = {"xcodegen": "exit 0", "xcrun": "exit 0", "xcodebuild": 'printf "build\\n" >> "$FIXTURE_CALLS"\nexit 37'}
        for name, body in scripts.items():
            script = binary / name
            script.write_text("#!/bin/sh\n" + body + "\n")
            script.chmod(0o755)
        env = dict(os.environ, PATH=str(binary) + os.pathsep + os.environ["PATH"], FIXTURE_CALLS=str(calls))
        result = subprocess.run(["make", "-f", str(SCRIPT.parents[2] / "ios/Makefile"), "build", "DESTINATION=generic/platform=iOS Simulator", "XCODEGEN=" + str(binary / "xcodegen")], cwd=self.root, env=env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("37", result.stderr)
        self.assertEqual(calls.read_text(), "build\n")


if __name__ == "__main__":
    unittest.main()
