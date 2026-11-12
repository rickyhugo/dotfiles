# Global agent instructions

## General

When responding, always be extremely concise. Sacrifice grammar for the sake of
concision. If the user explicitly asks for an explanation, use ASD-STE100
Simplified Technical English.

## Installed skills

Skill IDs have source prefixes. When a skill names another skill, use the same
collection, not another collection's skill with the same name.

Local sources:

- pstack: `~/.dotfiles/agents/pstack/skills/<name>/SKILL.md`.
- Cursor Team Kit: `~/.dotfiles/agents/cursor-team-kit/skills/<name>/SKILL.md`.
- tstack: `~/.dotfiles/agents/tstack/skills/<name>/SKILL.md`.

Before using a local collection, read its root `AGENTS.md` once. Harness guidance
lives there, outside the skills.

Other sources remain under `~/.external-skills/`, including Matt Pocock's skills
in `mattpocock-skills/skills/<set>/<name>/`. Keep external checkouts read-only.

If a requested or referenced skill is hidden from the catalog, read its
`SKILL.md` directly. Drop the source prefix when finding the directory. Resolve
relative references from a symlink's real source, and use registered IDs when
showing the user how to invoke a skill.
