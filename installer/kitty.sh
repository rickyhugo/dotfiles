#!/usr/bin/env bash

curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n
ln -s "$HOME"/.local/kitty.app/bin/kitty "$HOME"/.local/bin/kitty
kitty +kitten themes catppuccin-mocha
kitty --version
