#!/usr/bin/env bash

curl -L https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin launch=n
sudo ln -s ~/.local/kitty.app/bin/kitty /usr/local/bin/kitty
kitty +kitten themes catppuccin-mocha
kitty --version
