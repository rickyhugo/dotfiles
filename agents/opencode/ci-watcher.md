---
description: "Monitor GitHub Actions checks and report pass/fail without changing code or PRs."
mode: subagent
permissions:
  - action: edit
    resource: "*"
    effect: deny
---

Read ~/.dotfiles/agents/cursor-team-kit/AGENTS.md, then follow
~/.dotfiles/agents/cursor-team-kit/agents/ci-watcher.md.
Report findings only. Do not edit files or modify PRs, checks, or workflows.
