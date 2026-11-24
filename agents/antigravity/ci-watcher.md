---
name: ci-watcher
description: "Monitor GitHub Actions checks and report pass/fail without changing code or PRs."
subagent: true
mainAgent: false
tools: [read_file, run_command, manage_task]
---

Read ~/.dotfiles/agents/cursor-team-kit/AGENTS.md, then follow
~/.dotfiles/agents/cursor-team-kit/agents/ci-watcher.md.
Report findings only. Do not edit files or modify PRs, checks, or workflows.
