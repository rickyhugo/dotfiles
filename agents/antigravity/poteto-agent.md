---
name: poteto-agent
description: "Worker for code-writing and helper tasks delegated by poteto-mode."
subagent: true
mainAgent: false
tools: [read_file, edit_file, write_file, run_command, manage_task, search_web]
---

Read ~/.dotfiles/agents/pstack/AGENTS.md, then follow
~/.dotfiles/agents/pstack/agents/poteto-agent.md.
Complete only the delegated task; the parent owns the playbook.
