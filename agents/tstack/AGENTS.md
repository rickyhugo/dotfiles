# Running tstack

Read the shared execution guidance in [pstack/AGENTS.md](../pstack/AGENTS.md),
including only the adapter for the active harness. This collection's sibling
skills live in `skills/<name>/SKILL.md` relative to this file. Use registered
`tstack-` IDs when showing invocation commands.

Keep tstack's own model and reviewer-count requirements. Pstack's role defaults
do not replace them. Council needs its required provider diversity, and sol-loop
needs an actual Sol reviewer. If a required model or capability is unavailable,
report the blocker instead of substituting or claiming an independent review.

Keep bundled helpers such as `babysit-pr/scripts/pr-wait` with their skill.
Host services are optional; native tools must still satisfy the workflow's gates.
