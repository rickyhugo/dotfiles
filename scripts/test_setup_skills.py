import json
from pathlib import Path
import tempfile
import unittest

from setup_skills import build


class RemovedSkillsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        base = Path(self.temporary.name)
        self.root = base / "agent-skills"
        self.home = base / "home"
        self.generated = self.root / ".generated"
        self.generated.mkdir(parents=True)
        (self.root / "compat.md").write_text("Compatibility notes")
        self.source = self.generated / "plugins/example/skills/removed"
        self.source.mkdir(parents=True)
        (self.source / "SKILL.md").write_text("Preserved generated content")
        self.destination = self.home / ".agents/skills/removed"
        self.destination.parent.mkdir(parents=True)
        self.destination.symlink_to(self.source)
        (self.generated / "manifest.json").write_text(
            json.dumps({"links": {str(self.destination): str(self.source)}})
        )

    def test_removal_requires_explicit_opt_in(self):
        with self.assertRaisesRegex(ValueError, "Rerun with --prune"):
            build({}, self.root, self.home)
        self.assertTrue(self.destination.is_symlink())

    def test_prune_removes_link_but_preserves_generated_files(self):
        _, links = build({}, self.root, self.home, prune=True)
        self.assertFalse(self.destination.is_symlink())
        self.assertTrue((self.source / "SKILL.md").is_file())
        self.assertNotIn(str(self.destination), links)
        manifest = json.loads((self.generated / "manifest.json").read_text())
        self.assertNotIn(str(self.destination), manifest["links"])
        build({}, self.root, self.home)

    def test_prune_refuses_replacement_file(self):
        self.destination.unlink()
        self.destination.write_text("User content")
        with self.assertRaises(FileExistsError):
            build({}, self.root, self.home, prune=True)
        self.assertEqual(self.destination.read_text(), "User content")

    def test_prune_refuses_unrelated_symlink(self):
        self.destination.unlink()
        self.destination.symlink_to(self.home / "unrelated")
        with self.assertRaises(FileExistsError):
            build({}, self.root, self.home, prune=True)
        self.assertTrue(self.destination.is_symlink())

    def test_prune_accepts_already_missing_link(self):
        self.destination.unlink()
        build({}, self.root, self.home, prune=True)

    def test_prune_removes_broken_managed_symlink(self):
        (self.source / "SKILL.md").unlink()
        self.source.rmdir()
        build({}, self.root, self.home, prune=True)
        self.assertFalse(self.destination.is_symlink())


if __name__ == "__main__":
    unittest.main()
