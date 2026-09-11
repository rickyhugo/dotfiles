#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Do not run as root: Homebrew refuses to run as root." >&2
  exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script is for macOS only." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Xcode Command Line Tools (provides git, compilers; required by Homebrew).
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Installing Xcode Command Line Tools..."
  xcode-select --install
  echo "Rerun this script after the install finishes." >&2
  exit 1
fi

# Homebrew, idempotent.
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "brew not found after install." >&2
  exit 1
fi

# curl/git required by setup_mise.sh below. curl is keg-only, so prefer it explicitly.
brew list curl >/dev/null 2>&1 || brew install curl
brew list git >/dev/null 2>&1 || brew install git
if [[ -d "$(brew --prefix curl)/bin" ]]; then
  export PATH="$(brew --prefix curl)/bin:$PATH"
fi

# OS-specific done; hand off to common, OS-independent setup.
exec "$SCRIPT_DIR/setup_mise.sh"
