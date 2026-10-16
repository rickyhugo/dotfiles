# pstack compatibility

Portable discovery, model configuration, and worker-agent definitions for
OpenCode V2, Claude Code, and current Codex. Upstream skills remain the source
of the engineering workflows; this layer translates host assumptions, not the
entire Cursor runtime.

From the dotfiles directory:

```sh
mise run pstack:install
mise run pstack:check
mise run pstack:test
```

Installation needs uv, Git, mise with `dotfiles` support, and network access on
the first run. The script declares Python 3.11+ in inline metadata; uv selects
or downloads a compatible interpreter. It fetches the exact commit in `upstream.json`. To update,
review and change that pin, then rerun installation. Previous cached revisions
remain available. For an offline source, run
`uv run --script scripts/setup_pstack.py --source /path/to/pstack --install` instead;
the caller is responsible for verifying that offline source's revision.

## Daily upstream sync (macOS)

```sh
mise run pstack:update          # Update now from upstream main
mise run pstack:daily:enable    # Install a LaunchAgent through mise
mise run pstack:daily:status
mise run pstack:daily:disable
```

The LaunchAgent runs at **09:00 local time** and when loaded at login. A missed
calendar run while asleep runs on wake. It runs only as your logged-in user;
offline failures retry at the next scheduled run or manually with `pstack:update`.
Logs are at `~/Library/Logs/pstack/sync.log` and `sync-error.log`. Disabling unloads
the job and removes only its managed plist symlink; skills remain installed.

Sync resolves `upstream.json`'s `branch` (default `main`), fetches that commit,
rebuilds/deploys the adapter, verifies it, and only then writes the new revision
to `upstream.json`. It does **not** pull, commit, or push your dotfiles repository.
The updated pin will appear as a local Git change. Model choices stay untouched.
Manual installs and scheduled updates share a lock to prevent concurrent writes.

This opts into automatically trusting new upstream skill instructions. It does
not prove behavioral compatibility with future changes. Malformed skills,
collisions, and removed installed skills stop the update for manual review;
inspect the error log. In particular, skill removals are not silently pruned.

## Layout

- `compat.md` is inserted after every skill's frontmatter, before upstream text.
- `setup.md` replaces Cursor's setup workflow in the generated copy only.
- `models.json` stores per-host role choices. Unspecified roles inherit the
  parent model. Panel roles default to two independent workers on that model.
- `.cache/` holds pristine pinned upstream source, including its MIT license.
- `.generated/` holds the adapted tree, native agents, deployment manifest, and
  generated mise dotfile configuration. Both directories are ignored by Git.

The Python builder generates native `poteto-agent` and `comment-sicko` definitions
for each host. It normalizes skill names to directory IDs for Codex compatibility
and preserves upstream explicit-invocation settings. Supporting files and relative
skill references stay together. Model choices are read when a skill is invoked;
they do not change the host's global model configuration.

## Global deployment

The installer invokes `mise dotfiles apply` for only these targets:

- `~/.agents/skills/<skill>` for OpenCode and Codex.
- `~/.claude/skills/<skill>` for Claude Code (also discovered by OpenCode).
- `~/.config/opencode/agents/{poteto-agent,comment-sicko}.md`.
- `~/.claude/agents/{poteto-agent,comment-sicko}.md`.
- `~/.codex/agents/{poteto-agent,comment-sicko}.toml`.
- `~/.config/pstack/models.json`, linked to this directory's versioned file.

Existing links to our earlier `~/.local/share/agent-skills/pstack/skills` download
are migrated. Other collisions abort before deployment; no unrelated skills,
synced skills, agents, or global configuration files are replaced. The original
download is kept. Generated files are disposable: change sources here and rerun,
not files under `.generated/`. Move a conflicting customization aside yourself
if you intentionally want to replace it.

Start fresh host sessions after installation. Try `@poteto-mode` in OpenCode,
`/poteto-mode` in Claude Code, or `$poteto-mode` in Codex. Ask the host to use
`poteto-agent` for a small read-only task to smoke-test native delegation.

## Boundaries

This is a prompt-level compatibility adapter, not a guarantee that every
upstream workflow runs unchanged. Native tool schemas, permissions, user scope,
and approvals always take precedence. No permission bypasses are installed.

Cursor cloud agents, UI automation, loops, history APIs, and `cursor-team-kit`
are not bundled. Missing capabilities must be reported or replaced with an
available equivalent, never claimed as completed. A same-model review panel is
not a diverse-model panel. OpenCode/Claude enforce tool restrictions on
`comment-sicko`; Codex inherits the parent sandbox, so its read-only scope is
instructional rather than a separate security boundary.

`pstack:test` checks generation, formats, reruns, collision handling, and source
preservation. `pstack:check` checks deployed links and file hashes. Neither test
proves model behavior or replaces an end-to-end host delegation test.
