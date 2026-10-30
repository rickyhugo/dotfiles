---
name: gh-auth
description: Use this machine's saved GitHub PAT for autonomous gh commands. Use for gh login, keeping gh logged in, or recovering from gh authentication errors.
---

# GitHub CLI authentication

Use `gh-agent` for GitHub CLI operations on this Mac. It reads the PAT for
`rickyhugo` on `github.com` from macOS Keychain and passes it as `GH_TOKEN` only
to the child `gh` process. The PAT stays out of chat, dotfiles, shell profiles,
command arguments, and parent environments. The ordinary `gh` login is preserved.

## Use the saved PAT

```sh
gh-agent --check
gh-agent pr list
```

Replace `gh` with `gh-agent` for the originally requested command. The helper
accepts the same arguments. If PATH does not include it, use
`~/.local/bin/gh-agent` or this skill's `scripts/gh-agent` directly. A successful
`--check` reports only account, host, and credential store as JSON after a real
identity request. Reuse the saved PAT without browser authorization.

Treat PAT permissions separately from authentication: a repository 403 or 404
can indicate missing repository access, organization approval, SSO, or scopes.
Diagnose the original failure rather than replacing a token whose identity check
succeeds. Network failures also need their own remedy. Do not retry a write
unless it is still authorized and its prior outcome is known.

## Import or replace the PAT

When the user has a new PAT, request it through the host's private secret tool.
In T3 Code call `request_secret` yourself with `delivery: "file"`. Pass only
the returned private file path to:

```sh
gh-agent --import-pat-file /path/returned/by/the/private/secret/tool
```

The helper reads the file internally, verifies the intended GitHub account,
stores the PAT through the native Keychain API, verifies it can be read back,
and deletes the delivery file even if verification or storage fails. An invalid
or wrong-account PAT is rejected before replacing the saved credential. Never
read the delivery file through a tool that displays its contents. Outside hosts
with private file delivery, use an approved private secret-input mechanism.

After import run `gh-agent --check` in a fresh terminal process, then retry the
original read-only or still-authorized command. Keep existing SSH keys and Git
transport unchanged. If the helper is missing, deploy it with this repository's
`mise run skills:install`.

## Recovery boundaries

The helper disables Keychain interaction: inaccessible credentials fail promptly
instead of hanging an unattended agent on an OS dialog. If access is denied,
check the OS user, login-keychain lock state, and permission for the Python
executable running the helper. One-time Keychain access may need the user;
avoid weakening access controls globally.

A PAT is reusable while valid, but cannot renew itself after expiry or
revocation. Request its replacement through the private secret tool when needed.
Use browser login only if the user explicitly chooses that alternative; it is
not the normal PAT recovery path. Never print a token, enable HTTP debugging,
or invoke `auth token` or `auth status --show-token` through the helper.

Report the verified account, host, credential store, and any remaining access
problem. The skill runs on demand; no background login loop is installed.

References: [CLI token authentication](https://cli.github.com/manual/gh_auth_login)
and [token environment](https://cli.github.com/manual/gh_help_environment).
