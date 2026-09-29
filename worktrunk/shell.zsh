# Source after `wt config shell init zsh` to keep Worktrunk's shell integration.
functions -c wt _worktrunk_wt

wt() {
  if [[ "${1:-}" == switch ]]; then
    local arg
    for arg in "$@"; do
      # Leave explicit commands and machine-readable output alone.
      if [[ "$arg" == -x* || "$arg" == --execute* || "$arg" == --format* ]]; then
        _worktrunk_wt "$@"
        return
      fi
    done

    _worktrunk_wt "$@" --execute sh -- "$HOME/.dotfiles/worktrunk/open-tmux-session.sh"
  else
    _worktrunk_wt "$@"
  fi
}
