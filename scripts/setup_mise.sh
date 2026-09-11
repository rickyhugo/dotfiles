#!/usr/bin/env bash
set -euo pipefail

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required to install mise (install it via your OS bootstrap first)." >&2
  exit 1
fi

# Idempotent install: only install if missing. OS-independent.
if ! command -v mise >/dev/null 2>&1 && [[ ! -x "$HOME/.local/bin/mise" ]]; then
  curl -fsSL https://mise.run | sh
fi

# Needed for this shell only; ensure shims work via `mise x` below.
export PATH="$HOME/.local/bin:$PATH"

if ! command -v mise >/dev/null 2>&1; then
  echo "mise not found after install." >&2
  exit 1
fi

mise use -g gh

# Only prompt for login when not already authenticated; safe to re-run.
if ! mise x gh -- gh auth status --hostname github.com >/dev/null 2>&1; then
  mise x gh -- gh auth login --hostname github.com --git-protocol ssh --web
fi
mise x gh -- gh auth setup-git --hostname github.com

# Common, OS-independent dev setup.
mise bootstrap --adopt rickyhugo/mise-setup
