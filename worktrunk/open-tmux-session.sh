#!/bin/sh
# Worktrunk runs --execute in the selected worktree, with the terminal attached.
set -eu

dir=$PWD
name=$(printf %s "${dir##*/}" | LC_ALL=C tr -c '[:alnum:]_-' '_')
hash=$(printf %s "$dir" | shasum -a 256 | cut -c 1-8)
session="$name-$hash"

if ! tmux has-session -t "=$session" 2>/dev/null; then
  tmux new-session -d -s "$session" -c "$dir"
fi

if [ "${TMUX:-}" != "" ]; then
  tmux switch-client -t "=$session"
else
  tmux attach-session -t "=$session"
fi
