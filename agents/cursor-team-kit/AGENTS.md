# Running Cursor Team Kit

Read the shared execution guidance in [pstack/AGENTS.md](../pstack/AGENTS.md),
including only the adapter for the active harness. It defines native delegation,
tool access, isolation, history, and unsupported-capability handling.

This collection's sibling skills live at `skills/<name>/SKILL.md` relative to
this file, not in pstack. Use their registered `cursor-` IDs when available.
Bundled roles live in `agents/`; native wrappers can load those files directly.
Reviewers report only unless the caller explicitly requests implementation.

Treat Cursor tool names in role prompts as intent, using the active native tool
schema. Cursor-only frontmatter such as `model: fast` is not model routing.
Inherit the session model unless the user or caller selects an explicit model
or a configured pstack role. No plugin install or legacy model rule is required.
