# Global agent instructions

## Installed skills

Skills are installed under a prefix that names their source repository:
`pstack-` and `cursor-` (Cursor's pstack and Team Kit), `mp-` (Matt Pocock), and
`tstack-` (t3dotgg). Upstream text names skills without the prefix, as in
`/poteto-mode`, "the tdd skill", or `../poteto-mode/SKILL.md`. Resolve each such
name to the installed skill with the same prefix as the skill you are following.
When that prefix has no match, use the installed skill whose name ends in
`-<name>`, and name your pick when two match.

Each skill directory is a symlink into a mise-managed checkout under
`~/.external-skills/<repo>/`. Resolve relative paths from the skill's real path,
and keep those checkouts read-only.

## Cursor skills

`pstack-*` and `cursor-*` skills are written for Cursor. Before following one,
read `~/.dotfiles/agents/cursor-compat.md`.
