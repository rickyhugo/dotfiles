#!/usr/bin/env bash

sudo apt update && sudo apt install zsh -y
chsh -s "$(which zsh)" # NOTE: logout required
echo "$SHELL"
"$SHELL" --version

# NOTE: install catppuccin syntax highlighting
git clone https://github.com/catppuccin/zsh-fsh.git
cp -r zsh-fsh/themes/* ~/dotfiles/config/fsh/.config/fsh/
rm -rf zsh-fsh
# NOTE: set theme with `fast-theme XDG:catppuccin-mocha`
