## Cursor Team Kit compatibility

`ci-watcher` and `thermo-nuclear-code-quality-review` are native helper agents.
They report findings; CI watching does not authorize modifying code, checks, PRs,
or GitHub workflows. Native models inherit the parent, not Cursor's `fast` alias.

`control-cli` and `control-ui` are harness-building instructions. They do not
install browser, Playwright, tmux, or CDP tools. Discover project dependencies and
available tools first. Capture real evidence or report missing verification.
Keep debug ports on loopback and use isolated test profiles, not the user's
authenticated browser. Do not install new dependencies without permission.

`workflow-from-chats` must use accessible, user-authorized history and native
host instruction locations, not Cursor rules or paths. Other workflows that
commit, push, or open PRs must remain within the user's requested scope.
