#!/usr/bin/env bash

curl https://mise.run | sh
~/.local/bin/mise --version
echo 'eval "$(~/.local/bin/mise activate zsh)"' >>~/.zshrc
.local/bin/mise use -g python
.local/bin/mise use -g node
.local/bin/mise use -g go
.local/bin/mise use -g ruby
