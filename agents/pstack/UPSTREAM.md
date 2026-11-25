# Upstream source

- Repository: https://github.com/cursor/plugins
- Subdirectory: `pstack/`
- Upstream baseline: `5866df557357d005b3c0c9d3da0d9e739b4bdde3`
- Last reviewed upstream commit: `41e400932eca14f289e7db717a70455256b6d388`
- Imported into dotfiles: 2026-11-11.
- License: MIT; see [LICENSE](LICENSE).

This is a locally maintained, selective copy, not a plugin or an automatic mirror.
It includes the workflows, principles, required resources, and task helpers.
Tests, generated copies, plugin packaging, and config executables are omitted.
Harness guidance and plain model configuration are local changes.

For an update, compare upstream's `pstack/` changes against the last reviewed
commit. Bring over useful changes with their required resources. Keep local
adapters and configuration, and leave tests and packaging out. After reviewing
the whole change window, advance the last-reviewed commit here, including when
some changes were intentionally rejected. Do not replace this tree wholesale.

## Rejected changes

- Through `41e4009`: model slugs, Gemini panel seats, `.mdc` model rules and the
  large/medium/small budget. Local routing stays role-based in `config/`.
- Through `41e4009`: Cursor-specific harness notes in `docs/harness/claude-code.md`.
