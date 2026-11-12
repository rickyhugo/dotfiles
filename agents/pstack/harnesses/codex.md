# Codex

Use the session's spawn and wait tools. Choose agent types from their schema;
the general agent plus a bundled role file is sufficient. Report-only work still
needs access to all required sources.

Apply the role's `codex` target only if the native API exposes those per-agent
controls. Some sessions expose agent types without per-call model selection.
In that case inherit and report the limitation; a chat model listing does not
enable an unsupported spawn parameter.

Use explicit worktrees for concurrent writers and native session tools for
history. Preserve the user's project and approval boundaries.
