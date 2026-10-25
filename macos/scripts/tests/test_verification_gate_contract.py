"""Independent review/catalog contracts; every Git repository is synthetic and isolated."""
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "verification-gate.py"
SPEC = importlib.util.spec_from_file_location("verification_gate_contract_subject", SCRIPT)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


class ReviewContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        base = SCRIPT.parents[2] / ".verification"
        base.mkdir(exist_ok=True)
        cls.run_temp = tempfile.TemporaryDirectory(prefix="review-contract-", dir=base)
        cls.run_root = Path(cls.run_temp.name)
        (cls.run_root / "OWNER.json").write_text(json.dumps({
            "purpose": "synthetic review/catalog Git fixtures, never physical observations",
            "session": cls.run_root.name,
            "pid": os.getpid(),
            "executable": sys.executable,
            "output": str(cls.run_root),
        }))

    @classmethod
    def tearDownClass(cls):
        cls.run_temp.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=self.run_root)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.env.update(GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull)
        self.git("init", "--quiet")
        self.write("src/session.swift", "let value = 1\n")
        self.write("src/history.swift", "let history = true\n")
        self.write("tests/Acceptance.swift", "struct SessionAcceptance {}\n")
        self.write("macos/docs/notes.md", "Non-requirement reference\n")
        self.requirements = (
            "---\nreviewed: old\n---\n"
            "| AC-1 | Show [running](old-url) until completion | Observe state |\n"
            "| AC-2 | Keep the reading position | Pull and cancel |\n"
            "| AC-99 | Unrelated requirement | Other observation |\n"
        )
        self.write("macos/docs/requirements.md", self.requirements)
        self.catalog = {"schemaVersion": 1, "scenarios": [
            {
                "scenarioID": ident,
                "revision": 1,
                "requirement": "macos/docs/requirements.md#" + ac,
                "requirementIDs": [ac],
                "codePaths": [path],
                "testIDs": ["tests/Acceptance.swift::SessionAcceptance"],
                "procedure": procedure,
                "expected": expected,
                "method": "physical-device",
                "required": True,
            }
            for ident, ac, path, procedure, expected in (
                ("session", "AC-1", "src/session.swift", "Run then complete", "Running ends on completion"),
                ("history", "AC-2", "src/history.swift", "Pull then cancel", "Reading position is retained"),
            )
        ]}
        self.write_json(gate.SCENARIOS, self.catalog)
        self.write_json(gate.REVIEWS, {"schemaVersion": 1, "reviews": []})
        # Running the actual CLI from this copy gives it the fixture ROOT without mocks.
        self.write("macos/scripts/verification-gate.py", SCRIPT.read_text())
        self.base = self.commit()

    def git(self, *args):
        return subprocess.check_output(
            ["git", "-c", "user.name=Contract fixture", "-c", "user.email=fixture@example.invalid", *args],
            cwd=self.root, env=self.env, text=True, stderr=subprocess.PIPE,
        ).strip()

    def write(self, name, value):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    def write_json(self, name, value):
        self.write(name, json.dumps(value, ensure_ascii=False, indent=2) + "\n")

    def commit(self):
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "Synthetic contract fixture")
        return self.git("rev-parse", "HEAD")

    def review(self, target, **changes):
        record = {
            "baseOID": self.base,
            "targetOID": target,
            "diffSHA256": gate.diff_hash(self.base, target, self.root),
            "scenarioIDs": ["session", "history"],
            "reviewer": {"kind": "ai", "id": "independent-synthetic-reviewer"},
            "independent": True,
            "reviewedAt": "2026-10-25T01:00:00+00:00",
            "decision": "pass",
            "reason": "Synthetic independent review of the mapped change and acceptance content",
        }
        record.update(changes)
        return record

    def store_reviews(self, *reviews):
        self.write_json(gate.REVIEWS, {"schemaVersion": 1, "reviews": list(reviews)})

    def validate(self, target):
        scenarios = gate.validate_scenarios(self.root)
        gate.validate_reviews(self.base, target, scenarios, self.root)

    def approved_change(self):
        self.write("src/session.swift", "let value = 2\n")
        target = self.commit()
        review = self.review(target)
        self.store_reviews(review)
        self.validate(target)
        return target, review

    def test_valid_catalog_and_independent_review_allow_mapped_change(self):
        target, _ = self.approved_change()
        self.validate(target)

    def test_non_requirement_docs_add_edit_delete_need_no_review(self):
        for content in ("New reference\n", "Edited reference\n", None):
            with self.subTest(content=content):
                path = self.root / "macos/docs/new-reference.md"
                if content is None:
                    path.unlink()
                else:
                    self.write("macos/docs/new-reference.md", content)
                self.validate(self.commit())

    def test_existing_pass_survives_automatic_document_metadata_and_link_changes(self):
        self.approved_change()
        self.write("macos/docs/requirements.md", self.requirements.replace(
            "reviewed: old", "reviewed: new"
        ).replace("old-url", "new-url").replace("Unrelated requirement", "Unrelated correction"))
        self.write("macos/docs/notes.md", "Updated non-requirement reference\n")
        self.validate(self.commit())

    def test_selected_requirement_change_invalidates_existing_pass(self):
        self.approved_change()
        self.write("macos/docs/requirements.md", self.requirements.replace(
            "until completion", "even after completion"
        ))
        with self.assertRaises(gate.GateError):
            self.validate(self.commit())

    def test_changed_procedure_or_expected_invalidates_existing_pass(self):
        self.approved_change()
        for field, text in (("procedure", "Do not run"), ("expected", "Stay running after completion")):
            with self.subTest(field=field):
                changed = copy.deepcopy(self.catalog)
                changed["scenarios"][0][field] = text
                self.write_json(gate.SCENARIOS, changed)
                with self.assertRaises(gate.GateError):
                    self.validate(self.commit())

    def test_unclassified_code_cannot_be_authorized_by_a_matching_review(self):
        self.write("src/unmapped.swift", "let unreviewed = true\n")
        target = self.commit()
        self.store_reviews(self.review(target))
        with self.assertRaisesRegex(gate.GateError, "Unclassified change"):
            self.validate(target)

    def test_required_scenario_deletion_requires_user_decision_even_after_ai_pass(self):
        changed = copy.deepcopy(self.catalog)
        changed["scenarios"].pop()
        self.write_json(gate.SCENARIOS, changed)
        target = self.commit()
        self.store_reviews(self.review(target))
        with self.assertRaisesRegex(gate.GateError, "User decision required"):
            self.validate(target)

    def test_required_scenario_cannot_be_made_optional_by_ai_review_alone(self):
        changed = copy.deepcopy(self.catalog)
        changed["scenarios"][0]["required"] = False
        self.write_json(gate.SCENARIOS, changed)
        target = self.commit()
        self.store_reviews(self.review(target))
        with self.assertRaisesRegex(gate.GateError, "User decision required"):
            self.validate(target)

    def test_newer_needs_changes_overrides_old_pass_independent_of_array_order(self):
        target, passed = self.approved_change()
        rejected = self.review(target, decision="needs_changes", reviewedAt="2026-10-25T02:00:00+00:00")
        for reviews in ((passed, rejected), (rejected, passed)):
            with self.subTest(order=[row["decision"] for row in reviews]):
                self.store_reviews(*reviews)
                with self.assertRaisesRegex(gate.GateError, "Latest independent review"):
                    self.validate(target)

    def test_latest_explicit_pass_can_resolve_previous_needs_changes(self):
        target, passed = self.approved_change()
        rejected = self.review(target, decision="needs_changes", reviewedAt="2026-10-25T00:00:00+00:00")
        self.store_reviews(passed, rejected)
        self.validate(target)

    def test_review_hash_target_schema_and_missing_decision_fail_closed(self):
        target, review = self.approved_change()
        for field, value in (("diffSHA256", "0" * 64), ("targetOID", self.base), ("decision", None)):
            with self.subTest(field=field):
                changed = copy.deepcopy(review)
                if value is None:
                    changed.pop(field)
                else:
                    changed[field] = value
                self.store_reviews(changed)
                with self.assertRaises(gate.GateError):
                    self.validate(target)
        self.write_json(gate.REVIEWS, {"schemaVersion": 99, "reviews": [review]})
        with self.assertRaisesRegex(gate.GateError, "Unsupported schema"):
            self.validate(target)

    def test_review_must_be_independent_identified_and_cover_affected_scenario(self):
        target, review = self.approved_change()
        for field, value in (("independent", False), ("reviewer", {"kind": "ai", "id": ""}), ("scenarioIDs", ["history"])):
            with self.subTest(field=field):
                changed = copy.deepcopy(review)
                changed[field] = value
                self.store_reviews(changed)
                with self.assertRaises(gate.GateError):
                    self.validate(target)

    def test_catalog_rejects_invalid_schema_and_broken_references(self):
        self.assertEqual(len(gate.validate_scenarios(self.root)), 2)
        mutations = (
            ("schema", lambda data: data.update(schemaVersion=99)),
            ("empty", lambda data: data.update(scenarios=[])),
            ("duplicate", lambda data: data["scenarios"][1].update(scenarioID="session")),
            ("requirement file", lambda data: data["scenarios"][0].update(requirement="macos/docs/missing.md#AC-1")),
            ("requirement anchor", lambda data: data["scenarios"][0].update(requirement="macos/docs/requirements.md#AC-missing")),
            ("selected requirement", lambda data: data["scenarios"][0].update(requirementIDs=["AC-missing"])),
            ("test file", lambda data: data["scenarios"][0].update(testIDs=["tests/missing.swift::SessionAcceptance"])),
            ("test symbol", lambda data: data["scenarios"][0].update(testIDs=["tests/Acceptance.swift::MissingAcceptance"])),
            ("code scope", lambda data: data["scenarios"][0].update(codePaths=["src/missing.swift"])),
        )
        for name, mutate in mutations:
            with self.subTest(mutation=name):
                changed = copy.deepcopy(self.catalog)
                mutate(changed)
                self.write_json(gate.SCENARIOS, changed)
                with self.assertRaises(gate.GateError):
                    gate.validate_scenarios(self.root)

    def test_review_input_cli_reports_actual_change_without_writing_repository(self):
        target, _ = self.approved_change()
        def snapshot():
            files = {path.relative_to(self.root).as_posix(): path.read_bytes()
                     for path in self.root.rglob("*") if path.is_file() and ".git" not in path.relative_to(self.root).parts}
            return self.git("rev-parse", "HEAD"), self.git("status", "--porcelain"), self.git("ls-files", "--stage"), files
        before = snapshot()
        expected = [{"path": "src/session.swift", "before": {"mode": "100644", "sha256": hashlib.sha256(b"let value = 1\n").hexdigest()},
                     "after": {"mode": "100644", "sha256": hashlib.sha256(b"let value = 2\n").hexdigest()}}]
        for extra in (("--target", target), ()):
            with self.subTest(arguments=extra):
                result = subprocess.run(
                    [sys.executable, "-B", str(self.root / "macos/scripts/verification-gate.py"), "review-input", "--base", self.base, *extra],
                    cwd=self.root, env=self.env, capture_output=True, text=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                output = json.loads(result.stdout)
                self.assertEqual(output["schemaVersion"], 1)
                self.assertEqual((output["baseOID"], output["targetOID"]), (self.base, target))
                self.assertEqual(output["changes"], expected)
                serialized = json.dumps(expected, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()
                self.assertEqual(output["diffSHA256"], hashlib.sha256(serialized).hexdigest())
                self.assertEqual(snapshot(), before)


if __name__ == "__main__":
    unittest.main()
