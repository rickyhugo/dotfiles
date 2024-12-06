#!/usr/bin/env bash

sudo apt update
sudo apt install btop -y

git clone https://github.com/catppuccin/btop.git
cp -r btop/themes/* ~/.config/btop/themes/
rm -rf btop
