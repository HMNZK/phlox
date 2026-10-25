"""Gate regressions using measured Swift Testing events and isolated Git fixtures."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import shutil
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
            return rows + [{"version": 0, "kind": "event", "payload": {"kind": "testSkipped", "testID": "OptionalTests.Suite/optIn()/file.swift:1:1"}}]
        result = gate.check_regular_events([self.event_file("swift-testing-regular.jsonl", skip)])
        self.assertEqual(result["skippedIDs"], ["OptionalTests.Suite/optIn()"])
        self.assertTrue(result["passedIDs"])

    def test_zero_tests_and_unknown_text_summary_are_not_success(self):
        for text in ("✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.\n", "Build complete!\n"):
            log = self.root / "zero.log"
            log.write_text(text)
            with self.assertRaises(gate.GateError):
                gate.check_test_log(log)

    def git_repo(self):
        subprocess.run(["git", "init", "--quiet", str(self.root)], check=True)
        return self.root

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
            artifact = file(platform + ".bin", ("SYNTHETIC " + platform).encode())
            settings = [{"buildSettings": {"PRODUCT_BUNDLE_IDENTIFIER": "fixture." + platform, "MARKETING_VERSION": "1", "CURRENT_PROJECT_VERSION": "2", "PLATFORM_NAME": "macosx" if platform == "macos" else "iphoneos", "CODE_SIGNING_ALLOWED": "YES", "CODE_SIGN_IDENTITY": "Fixture only"}}]
            settings_file = file(platform + "-settings.json", json.dumps(settings).encode())
            provenance = {"schemaVersion": 1, "sourceOID": source, "platform": platform, "startedAt": "2026-10-24T01:00:00+00:00", "finishedAt": "2026-10-24T02:00:00+00:00", "inputManifest": manifest, "toolchain": {"xcode": "Fixture Xcode", "sdk": "Fixture SDK"}, "settingsSHA256": gate.digest(gate.canonical(settings)), "settingsPath": settings_file["path"], "externalInputs": [settings_file], "bundleID": "fixture." + platform, "version": "1", "buildNumber": "2", "artifact": artifact}
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
        args = SimpleNamespace(evidence_root=str(self.root), artifact="fixture-output/captured.bin", output="fixture-output/captured.json", settings="fixture-output/macos-settings.json", external_input=[], platform="macos", bundle_id="fixture.macos", version="1", build_number="2", command=["fixture-builder", "--output", "{build_dir}"])
        commands = []
        def build(command, log):
            commands.append(command)
            (self.root / args.artifact).write_bytes(b"SYNTHETIC CAPTURED ARTIFACT")
        with patch.object(gate, "ROOT", self.root), patch.object(gate, "git", side_effect=self.git_in_fixture), patch.object(gate, "toolchain", return_value={"xcode": "Historical Xcode", "sdk": "Historical SDK"}), patch.object(gate, "run_stage", side_effect=build), redirect_stdout(io.StringIO()):
            gate.capture_build(args)
        record = json.loads((self.root / args.output).read_text())
        self.assertEqual(record["sourceOID"], self.saved_git("rev-parse", "HEAD", root=self.root))
        self.assertEqual(record["artifact"]["sha256"], gate.digest((self.root / args.artifact).read_bytes()))
        self.assertNotIn(str(self.root), json.dumps(record))
        self.assertIn("managed-build.py", " ".join(commands[0]))
        (self.root / args.artifact).unlink()
        (self.root / args.output).unlink()
        def mutate(command, log):
            build(command, log)
            (self.root / "app.swift").write_text("let fixture = false\n")
        with patch.object(gate, "ROOT", self.root), patch.object(gate, "git", side_effect=self.git_in_fixture), patch.object(gate, "toolchain", return_value={"xcode": "Historical Xcode", "sdk": "Historical SDK"}), patch.object(gate, "run_stage", side_effect=mutate), self.assertRaisesRegex(gate.GateError, "inputs changed"):
            gate.capture_build(args)
        self.assertFalse((self.root / args.output).exists())

    def test_release_uses_explicit_evidence_root_and_historical_toolchain(self):
        data, scenarios, manifest, tools = self.physical_fixture()
        path = self.root / "fixture-output/records.json"
        path.write_text(json.dumps(data))
        self.saved_git = gate.git
        head = self.saved_git("rev-parse", "HEAD", root=self.root)
        args = SimpleNamespace(record=str(path), evidence_root=str(self.root), dmg="fixture-output/macos.bin")
        with patch.object(gate, "ROOT", self.root), patch.object(gate, "git", side_effect=self.git_in_fixture), patch.object(gate, "validate_scenarios", return_value=scenarios), patch.object(gate, "toolchain", side_effect=AssertionError("Current SDK must not invalidate a historical artifact")), patch.dict(os.environ, {"GITFLOW_MERGE_CANDIDATE": head, "GITFLOW_MERGE_TO": head}, clear=True), redirect_stdout(io.StringIO()):
            gate.release(args)
            duplicate = self.root / "fixture-output/copy.bin"
            duplicate.write_bytes((self.root / args.dmg).read_bytes())
            args.dmg = duplicate.relative_to(self.root).as_posix()
            with self.assertRaisesRegex(gate.GateError, "DMG"):
                gate.release(args)
        with self.assertRaises(gate.GateError):
            gate.verify_file({"path": "/not-a-relative-proof", "sha256": "0" * 64}, self.root)

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
        self.assertEqual(len(commands), 7)
        self.assertIn("discover", commands[0])
        self.assertIn("test_verification_gate*.py", commands[0])
        self.assertIn("macos/scripts/tests/run-swift-tests-output.test.sh", commands[1])
        self.assertIn("TerminalUI", commands[2])
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
