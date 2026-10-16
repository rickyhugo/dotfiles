import importlib.util
import json
from pathlib import Path
import tempfile
import tomllib
import unittest
from unittest.mock import patch
import plistlib
import subprocess


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location(
    "setup_pstack", ROOT / "scripts/setup_pstack.py"
)
setup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(setup)


class CompatibilityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.home = root / "home"
        self.layer = root / "layer"
        self.source = root / "upstream"
        self.layer.mkdir()
        for name in ("compat.md", "setup.md", "models.json"):
            (self.layer / name).write_bytes((setup.LAYER / name).read_bytes())
        for name in ("poteto-mode", "setup-pstack"):
            skill = self.source / "skills" / name
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text(
                "---\nname: Display Name\ndescription: Test skill\ndisable-model-invocation: true\n---\n\nUpstream body\n"
            )
            (skill / "reference.md").write_text("Reference remains unchanged\n")
        (self.source / "agents").mkdir()
        for name in ("poteto-agent", "comment-sicko"):
            (self.source / "agents" / f"{name}.md").write_text(
                f"---\nname: {name}\ndescription: Test agent\n---\n\nReport only.\n"
            )

    def build(self):
        return setup.build(self.source, self.layer, self.home)

    def test_portable_overlay_preserves_source_and_references(self):
        original = (self.source / "skills/poteto-mode/SKILL.md").read_bytes()
        generated, _ = self.build()
        skill = (generated / "skills/poteto-mode/SKILL.md").read_text()
        self.assertIn("name: poteto-mode\n", skill)
        self.assertIn("disable-model-invocation: true", skill)
        self.assertLess(
            skill.index("Local host compatibility"), skill.index("Upstream body")
        )
        self.assertEqual(
            (self.source / "skills/poteto-mode/SKILL.md").read_bytes(), original
        )
        self.assertEqual(
            (generated / "skills/poteto-mode/reference.md").read_text(),
            "Reference remains unchanged\n",
        )
        native_setup = (generated / "skills/setup-pstack/SKILL.md").read_text()
        self.assertIn("Configure pstack for this host", native_setup)
        self.assertNotIn("Upstream body", native_setup)

    def test_native_agents_and_mise_config_parse(self):
        generated, links = self.build()
        config = tomllib.loads((generated / "mise.toml").read_text())
        self.assertEqual(set(config["dotfiles"]), set(links))
        for name in ("poteto-agent", "comment-sicko"):
            agent = tomllib.loads((generated / f"agents/codex/{name}.toml").read_text())
            self.assertEqual(agent["name"], name)
            self.assertIn(str(generated / "COMPAT.md"), agent["developer_instructions"])
        self.assertIn(
            "mode: subagent",
            (generated / "agents/opencode/poteto-agent.md").read_text(),
        )
        self.assertIn(
            "effect: deny", (generated / "agents/opencode/comment-sicko.md").read_text()
        )
        self.assertIn(
            "model: inherit", (generated / "agents/claude/poteto-agent.md").read_text()
        )

    def test_legacy_links_can_be_migrated_but_unrelated_links_cannot(self):
        dest = self.home / ".agents/skills/poteto-mode"
        dest.parent.mkdir(parents=True)
        dest.symlink_to(
            self.home / ".local/share/agent-skills/pstack/skills/poteto-mode"
        )
        self.build()
        dest.unlink()
        dest.symlink_to(self.home / "my-own-skill")
        with self.assertRaises(FileExistsError):
            self.build()
        self.assertEqual(dest.readlink(), self.home / "my-own-skill")

    def test_collision_is_rejected_before_generated_files_are_written(self):
        dest = self.home / ".claude/agents/poteto-agent.md"
        dest.parent.mkdir(parents=True)
        dest.write_text("user agent")
        with self.assertRaises(FileExistsError):
            self.build()
        self.assertFalse((self.layer / ".generated").exists())
        self.assertEqual(dest.read_text(), "user agent")

    def test_rerun_and_verification_detect_missing_links_and_modified_files(self):
        generated, links = self.build()
        for dest, src in links.items():
            path = Path(dest)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.symlink_to(src)
        setup.check(generated)
        before = (generated / "manifest.json").read_bytes()
        self.build()
        self.assertEqual((generated / "manifest.json").read_bytes(), before)
        (generated / "COMPAT.md").write_text("changed")
        with self.assertRaises(ValueError):
            setup.check(generated)

    def test_models_are_preserved(self):
        models = {"codex": {"roles": {"bug-fix": "my-model"}}}
        (self.layer / "models.json").write_text(json.dumps(models))
        self.build()
        self.assertEqual(json.loads((self.layer / "models.json").read_text()), models)

    def test_supporting_scripts_keep_executable_permissions(self):
        script = self.source / "skills/poteto-mode/run.sh"
        script.write_text("#!/bin/sh\nexit 0\n")
        script.chmod(0o755)
        generated, _ = self.build()
        self.assertEqual(
            (generated / "skills/poteto-mode/run.sh").stat().st_mode & 0o777, 0o755
        )

    def test_latest_pin_resolves_branch_without_mutating_current_pin(self):
        old = {"repository": "https://example.com/plugins.git", "revision": "a" * 40}
        result = subprocess.CompletedProcess([], 0, "b" * 40 + "\trefs/heads/main\n")
        with patch.object(setup.subprocess, "run", return_value=result) as run:
            selected = setup.latest_pin(old)
        self.assertEqual(selected["revision"], "b" * 40)
        self.assertEqual(old["revision"], "a" * 40)
        self.assertEqual(run.call_args.args[0][-1], "refs/heads/main")

    def test_latest_pin_rejects_missing_branch(self):
        result = subprocess.CompletedProcess([], 0, "")
        with patch.object(setup.subprocess, "run", return_value=result):
            with self.assertRaises(ValueError):
                setup.latest_pin({"repository": "https://example.com/plugins.git"})

    def test_removed_upstream_skill_stops_before_changing_installation(self):
        generated, _ = self.build()
        before = (generated / "manifest.json").read_bytes()
        (self.source / "skills/setup-pstack/SKILL.md").unlink()
        with self.assertRaisesRegex(ValueError, "Upstream removed installed skills"):
            self.build()
        self.assertEqual((generated / "manifest.json").read_bytes(), before)

    def test_launchd_schedule_runs_mise(self):
        config = setup.schedule_config(self.home, self.home / ".local/bin/mise", ROOT)
        parsed = plistlib.loads(plistlib.dumps(config))
        self.assertEqual(parsed["StartCalendarInterval"], {"Hour": 9, "Minute": 0})
        self.assertTrue(parsed["RunAtLoad"])
        self.assertEqual(parsed["ProgramArguments"][-2:], ["run", "pstack:update"])
        self.assertIn(
            str(self.home / ".local/bin"), parsed["EnvironmentVariables"]["PATH"]
        )

    def test_update_records_pin_only_after_successful_deployment(self):
        old = {"repository": "https://example.com/plugins.git", "revision": "a" * 40}
        new = {**old, "revision": "b" * 40}
        pinfile = self.layer / "upstream.json"
        pinfile.write_text(json.dumps(old))
        with (
            patch.object(setup, "LAYER", self.layer),
            patch.object(setup.sys, "argv", ["setup_pstack.py", "--update"]),
            patch.object(setup, "latest_pin", return_value=new),
            patch.object(setup, "fetch_source", return_value=self.source),
            patch.object(setup, "build", return_value=(self.layer / ".generated", {})),
            patch.object(
                setup, "deploy", side_effect=RuntimeError("deploy failed")
            ) as deploy,
            patch.object(setup, "check") as check,
        ):
            with self.assertRaisesRegex(RuntimeError, "deploy failed"):
                setup.main()
            self.assertEqual(json.loads(pinfile.read_text()), old)
            check.assert_not_called()
            deploy.side_effect = None
            setup.main()
            check.assert_called_once()
            self.assertEqual(json.loads(pinfile.read_text()), new)


if __name__ == "__main__":
    unittest.main()
