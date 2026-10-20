import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SCRATCH = ROOT.parents[1] / ".verification/pstack-codex/tests"
SCRATCH.mkdir(parents=True, exist_ok=True)


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


build = load("build")
configure = load("configure")


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=SCRATCH)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.lock = {"revision": "a" * 40, "sha256": "", "upstream_version": "1.0.0", "adapter_version": "1.0.0-codex.1"}
        self.files = {
            "pstack/plugin.json": (b'{"version":"1.0.0"}', False),
            "pstack/LICENSE": (b"pstack license", False),
            "cursor-team-kit/LICENSE": (b"kit license", False),
            "pstack/README.md": (b"[guide](docs/guide.md)", False),
            "pstack/docs/guide.md": (b"guide", False),
            "pstack/skills/poteto-mode/SKILL.md": (b"---\nname: poteto-mode\ndescription: test\ndisable-model-invocation: true\nicon: crown\n---\n# Test\n[guide](../../docs/guide.md)\n", False),
            "pstack/skills/setup-pstack/SKILL.md": (b"---\nname: setup-pstack\ndescription: configure\n---\n# Setup\n", False),
            "pstack/skills/poteto-mode/scripts/helper.sh": (b"#!/bin/sh\nprintf '%s' example\n", True),
            "pstack/agents/poteto-agent.md": (b"---\nname: poteto-agent\n---\n# Delegate\n", False),
        }
        for dependency in build.DEPENDENCIES:
            self.files[f"cursor-team-kit/skills/{dependency}/SKILL.md"] = (
                f"---\nname: {dependency}\ndescription: dependency\n---\n# Helper\n".encode(), False
            )

    def test_package_preserves_resources_and_dependency_notices(self):
        rendered = build.render(self.files, self.lock)
        prefix = "plugins/pstack-codex/"
        self.assertEqual(rendered[prefix + "LICENSE"][0], b"pstack license")
        self.assertEqual(rendered[prefix + "LICENSE-cursor-team-kit"][0], b"kit license")
        for dependency in build.DEPENDENCIES:
            self.assertIn(prefix + f"skills/{dependency}/SKILL.md", rendered)
        self.assertEqual(rendered[prefix + "skills/poteto-mode/scripts/helper.sh"], self.files["pstack/skills/poteto-mode/scripts/helper.sh"])
        self.assertIn(prefix + "skills/poteto-mode/agents/openai.yaml", rendered)
        self.assertIn(b"../../codex.md", rendered[prefix + "skills/poteto-mode/SKILL.md"][0])
        self.assertIn(prefix + "scripts/configure.py", rendered)

    def test_same_inputs_have_identical_output_and_executable_modes(self):
        rendered = build.render(self.files, self.lock)
        first = self.root / "one"
        second = self.root / "two"
        build.publish(rendered, first)
        build.publish(build.render(self.files, self.lock), second)
        build.publish(rendered, first, check=True)
        for name in rendered:
            self.assertEqual((first / name).read_bytes(), (second / name).read_bytes())
            self.assertEqual(bool((first / name).stat().st_mode & 0o111), rendered[name][1])

    def test_large_skill_uses_short_entry_and_preserves_complete_workflow(self):
        path = "pstack/skills/poteto-mode/SKILL.md"
        original = self.files[path][0] + b"Important instruction.\n" * 1000
        self.files[path] = (original, False)
        rendered = build.render(self.files, self.lock)
        entry = rendered["plugins/pstack-codex/skills/poteto-mode/SKILL.md"][0]
        workflow = rendered["plugins/pstack-codex/skills/poteto-mode/workflow.md"][0]
        self.assertLess(len(entry), 8000)
        self.assertIn(b"workflow.md", entry)
        self.assertIn(b"../../codex.md", entry)
        self.assertTrue(workflow.endswith(b"Important instruction.\n" * 1000))
        self.assertIn(b"[guide](../../docs/guide.md)", workflow)

    def test_existing_manual_edit_is_preserved(self):
        rendered = build.render(self.files, self.lock)
        build.publish(rendered, self.root)
        readme = self.root / "plugins/pstack-codex/README.md"
        readme.write_text("user edit")
        with self.assertRaisesRegex(ValueError, "existing files were not changed"):
            build.publish(rendered, self.root)
        self.assertEqual(readme.read_text(), "user edit")

    def test_symlink_output_is_not_followed(self):
        target = self.root / "target"
        target.mkdir()
        link = self.root / "link"
        link.symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink"):
            build.publish(build.render(self.files, self.lock), link)
        self.assertEqual(list(target.iterdir()), [])

    def test_broken_reference_fails_before_output(self):
        self.files["pstack/docs/guide.md"] = (b"[missing](absent.md)", False)
        with self.assertRaisesRegex(ValueError, "Missing reference"):
            build.render(self.files, self.lock)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_reference_cannot_escape_package(self):
        with self.assertRaisesRegex(ValueError, "escapes"):
            build.validate_links({"docs/example.md": (b"[escape](../../secret.md)", False)})

    def test_reference_style_missing_target_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Missing reference"):
            build.validate_links({"README.md": (b"[guide][details]\n\n[details]: docs/missing.md\n", False)})

    def test_valid_markdown_destinations_are_accepted(self):
        for href, target in (("<docs/guide.md>", "docs/guide.md"),
                             ("docs/guide(v1).md", "docs/guide(v1).md"),
                             ("<docs/a guide.md>", "docs/a guide.md"),
                             ("docs/guide%20v1.md", "docs/guide v1.md")):
            with self.subTest(href=href):
                build.validate_links({"README.md": (f"[guide]({href})\n".encode(), False), target: (b"# Guide\n", False)})

    def test_skill_identity_mismatch_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "identity"):
            build.convert_skill(b"---\nname: different\ndescription: a\n---\nbody", "skills/example/SKILL.md")

    def test_multiline_description_survives_conversion(self):
        raw = b"---\nname: example\ndescription: >-\n  first line\n  second line\nicon: crown\n---\n# Example\n"
        result, _ = build.convert_skill(raw, "skills/example/SKILL.md")
        self.assertIn(b"description: >-\n  first line\n  second line\n---", result)
        self.assertNotIn(b"icon:", result)

    def test_changed_source_is_rejected_even_with_matching_revision(self):
        for name, (data, executable) in self.files.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            path.chmod(0o755 if executable else 0o644)
        self.lock["sha256"] = build.digest(build.source_files(self.root))
        with patch.object(subprocess, "check_output", return_value=self.lock["revision"] + "\n"):
            build.verify_source(self.root, self.lock)
            (self.root / "pstack/LICENSE").write_text("changed")
            with self.assertRaisesRegex(ValueError, "contents differ"):
                build.verify_source(self.root, self.lock)

    def test_revision_mismatch_is_rejected(self):
        with patch.object(subprocess, "check_output", return_value="b" * 40):
            with self.assertRaisesRegex(ValueError, "revision differs"):
                build.verify_source(self.root, self.lock)


class SettingsTests(unittest.TestCase):
    def test_default_roles_use_inheritance_with_explicit_panel_seats(self):
        config = configure.validate(configure.defaults(), {})
        self.assertEqual(set(config["roles"]), set(configure.ROLES))
        self.assertEqual(len(config["roles"]["interrogate reviewers"]), 2)
        self.assertEqual(len(config["roles"]["bug-fix"]), 1)
        self.assertEqual({seat["model"] for seats in config["roles"].values() for seat in seats}, {"inherit-parent"})

    def test_model_and_effort_must_both_be_observed(self):
        config = configure.defaults()
        seat = config["roles"]["bug-fix"][0]
        seat.update(model="observed-model", reasoning_effort="high")
        with self.assertRaisesRegex(ValueError, "Unavailable model"):
            configure.validate(config, {})
        with self.assertRaisesRegex(ValueError, "Unavailable reasoning_effort"):
            configure.validate(config, {"models": ["observed-model"]})
        self.assertIs(configure.validate(config, {"models": ["observed-model"], "reasoning_efforts": ["high"]}), config)

    def test_malformed_roles_and_capabilities_are_rejected(self):
        bad = [None, {}, {"version": True, "roles": {}}, {"version": 1, "roles": {"unknown": []}}]
        for config in bad:
            with self.subTest(config=config), self.assertRaises(ValueError):
                configure.validate(config, {})
        for seats in ([], "inherit-parent", [{}], [{"model": None, "reasoning_effort": "inherit-parent"}]):
            config = {"version": 1, "roles": {"bug-fix": seats}}
            with self.subTest(seats=seats), self.assertRaises(ValueError):
                configure.validate(config, {})
        with self.assertRaises(ValueError):
            configure.validate(configure.defaults(), {"models": "a"})

    def test_invalid_settings_never_replace_existing_data(self):
        with tempfile.TemporaryDirectory(dir=SCRATCH) as directory:
            path = Path(directory) / "models.json"
            configure.save(path, configure.defaults(), {})
            original = path.read_bytes()
            config = copy.deepcopy(configure.defaults())
            config["roles"]["bug-fix"][0]["model"] = "not-observed"
            with self.assertRaises(ValueError):
                configure.save(path, config, {})
            self.assertEqual(path.read_bytes(), original)
            self.assertEqual(json.loads(original), configure.defaults())


if __name__ == "__main__":
    unittest.main()
