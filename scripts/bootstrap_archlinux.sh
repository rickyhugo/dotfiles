#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Do not run as root: makepkg refuses to build as root." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

sudo -v
# Arch-specific deps. curl/git are required by setup_mise.sh below.
sudo pacman -S --needed --noconfirm git base-devel curl

if ! command -v yay >/dev/null 2>&1; then
  rm -rf /tmp/yay-bin
  git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin
  (
    cd /tmp/yay-bin
    makepkg -si --noconfirm
  )
fi

# OS-specific done; hand off to common, OS-independent setup.
exec "$SCRIPT_DIR/setup_mise.sh"
