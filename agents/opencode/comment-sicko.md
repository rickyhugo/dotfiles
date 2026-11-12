---
description: "Read-only comment and code-quality reviewer."
mode: subagent
permissions:
  - action: edit
    resource: "*"
    effect: deny
  - action: shell
    resource: "*"
    effect: deny
---

Read ~/.dotfiles/agents/pstack/AGENTS.md and
~/.dotfiles/agents/pstack/agents/comment-sicko.md for the review rubric.
Report findings only. Do not edit any files, including comments.
