# Global agent instructions

## Installed skills

Skills come from several repositories, and some share a name: pstack and Matt
Pocock both ship `tdd` and `teach`. Each host shows the source in the skill's
ID, such as `pstack-tdd` on Claude Code or `pstack:tdd` on Codex. When a skill
names another skill, as in `/poteto-mode`, "the tdd skill", or
`../poteto-mode/SKILL.md`, use the one from the same source as the skill you
are following, under the ID your skill list shows.

Each skill directory is a symlink into a mise-managed checkout under
`~/.external-skills/<repo>/`. Resolve relative paths from the skill's real path,
and keep those checkouts read-only.

## Cursor skills

Skills from pstack and Cursor Team Kit, under `~/.external-skills/cursor-plugins/`,
are written for Cursor. Before following one, read
`~/.dotfiles/agents/cursor-compat.md`.
