# Model configuration

Agents read these JSON files directly, from lowest to highest precedence:

1. Bundled [defaults](../config/defaults.json), which define all role names.
2. `$XDG_CONFIG_HOME/pstack/config.json`, normally `~/.config/pstack/config.json`.
3. `$XDG_CONFIG_HOME/pstack/config.local.json`, for this machine.

Sync the shared file through dotfiles if useful. Keep the local file unsynced,
or deploy a different one with each mise machine/profile. There is no hostname
detection. `PSTACK_CONFIG`, when set to an absolute path, replaces both user files.
Missing files use defaults. Report malformed or inconsistent config before running
explicit model routing; do not silently treat an invalid file as missing.

Merge roles by key and profiles by name. Each role value or named profile replaces
the whole lower-precedence value; lists replace rather than append. `inherit` is
reserved and means no model override. Unconfigured roles inherit the parent.
Validate version 1, known roles, profile references, and role shapes when editing.

## Shared choices

Profiles hold exact native parameter objects per harness. The following IDs and
options are examples; confirm availability and tool support before using them.

```json
{
  "version": 1,
  "models": {
    "sonnet": {
      "family": "anthropic",
      "targets": {
        "claude-code": { "model": "sonnet", "effort": "high" }
      }
    },
    "sol": {
      "family": "openai",
      "targets": {
        "opencode": { "model": "openai/gpt-6.1-sol" }
      }
    }
  },
  "roles": {
    "feature": "sonnet",
    "hardest": "sol",
    "arena-runners": ["sonnet", "sol"],
    "arena-judges": ["sol", "sonnet"]
  }
}
```

Keep native nested objects when a harness nests model/options fields. A target
must actually select the configured model; reasoning-only options do not establish
its identity. `family` is an explicit grouping for cross-family review, not a
prefix parsed from a model name. A missing target inherits with a warning and
does not retain that profile's family for judging.

## This machine

`config.local.json` can change only the roles this machine should run differently:

```json
{
  "version": 1,
  "roles": {
    "feature": "sol",
    "refactoring": "sol",
    "bug-fix": "sol"
  }
}
```

Ordinary roles take one profile name. `arena-runners`, `architect-runners`, and
`interrogate-reviewers` take nonempty lists; repeated profiles are separate seats.
`arena-judges` is an ordered selection pool and may be empty. Defaults use two
inherited panel seats and no cross-family judge.

Changes apply the next time the agent reads the files. No resolver, model-rule
generation, runtime dependency, or restart is needed. Setup shows the effective
choices before saving. A legacy Cursor/Claude model rule can be migrated after
confirming native IDs; keep it until the user approves removal. This fork does
not load or write those rules.
