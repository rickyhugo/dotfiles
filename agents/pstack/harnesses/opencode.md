# OpenCode

Use `subagent` with an exposed `agent` ID. Use `general` with the bundled role
file when no matching custom agent exists. `explore` is suitable only when its
available tools cover the read-only investigation.

Apply the role's `opencode` target using exact supported native parameters.
Configured model IDs must match the provider/model listing; include a variant
only when explicitly configured and confirmed. Do not convert an effort value
into an invented variant or pass unsupported effort/background fields.

Use native completion notifications where offered. Create separate worktrees
for writers rather than treating a Cursor cloud field as a tool parameter.
Use exposed session APIs for history, not direct database inspection.
