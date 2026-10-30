# Global agent instructions

## Installed skills

Skills come from several repositories, and some share a name: pstack and Matt
Pocock both ship `tdd` and `teach`. Each host shows the source in the skill's
ID, such as `pstack-tdd` on Claude Code or `pstack:tdd` on Codex. When a skill
names another skill, as in `/poteto-mode`, "the tdd skill", or
`../poteto-mode/SKILL.md`, use the one from the same source as the skill you
are following, under the ID your skill list shows.

Many skills set `disable-model-invocation`, so some hosts leave them out of the
skill list and the skill tool. When the user asks for a skill by name, or a
skill names another, and your skill tool does not offer it, read its
`SKILL.md` from the checkout and follow it: pstack and Team Kit skills live in
`~/.external-skills/cursor-plugins/{pstack,cursor-team-kit}/skills/<name>/`,
Matt Pocock's in `~/.external-skills/mattpocock-skills/skills/<set>/<name>/`, and
tstack's in `~/.external-skills/t3dotgg-tstack/skills/<name>/`. Drop the prefix
from the name, as in `pstack-poteto-mode` to `poteto-mode`.

Each skill directory is a symlink into a mise-managed checkout under
`~/.external-skills/<repo>/`. Resolve relative paths from the skill's real path,
and keep those checkouts read-only.

## Cursor skills

Skills from pstack and Cursor Team Kit, under `~/.external-skills/cursor-plugins/`,
are written for Cursor. Before following one, read
`~/.dotfiles/agents/cursor-compat.md`.
