#!/usr/bin/env bash

sudo apt update && sudo apt install tmux -y
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
tmux source ~/.tmux.conf
# NOTE: press '<C-t>+I' to install plugins

go install github.com/go-tmux/kube-tmux@latest
cargo install tmux-sessionizer
