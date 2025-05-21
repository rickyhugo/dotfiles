# HACK: prevent 'zsh-vi-mode' from overriding keybindings
ZVM_INIT_MODE=sourcing

# 📥
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
if [ ! -d "$ZINIT_HOME" ]; then
   mkdir -p "$(dirname $ZINIT_HOME)"
   git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi
source "${ZINIT_HOME}/zinit.zsh"

# 🔌
# NOTE: https://github.com/zdharma-continuum/fast-syntax-highlighting?tab=readme-ov-file#zinit
# NOTE: set theme with `fast-theme XDG:catppuccin-mocha`
zinit wait lucid light-mode for \
  atinit"ZINIT[COMPINIT_OPTS]=-C; zicompinit; zicdreplay -q" \
      zdharma-continuum/fast-syntax-highlighting \
      OMZP::colored-man-pages \
  atload"_zsh_autosuggest_start" \
      zsh-users/zsh-autosuggestions \
  blockf atpull'zinit creinstall -q .' \
      zsh-users/zsh-completions

zinit ice compile'async.zsh' pick'async.zsh' src'pure.zsh'
zinit light rickyhugo/pure

zinit wait lucid for \
  Aloxaf/fzf-tab \
  OMZP::tmux \
  OMZP::git \
  OMZP::ubuntu \
  OMZL::directories.zsh # NOTE: `cd` aliases

zinit ice depth=1; zinit light jeffreytse/zsh-vi-mode

# 📦
# NOTE: might not work if mise is activated after zinit since `go` would not be on path
zinit pack"default+keys" for fzf

# 💅
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'

# ⚡
alias vim='nvim'
alias vi='nvim'
alias v='nvim'
alias lzg='lazygit'
alias lzd='lazydocker'
alias cat='batcat'
alias c='batcat'
alias up='aguu -y && agar -y'
alias k='kubectl'
alias kctx='kubectl ctx'
alias kns='kubectl ns'
alias xclip='xclip -selection c'
alias 'tms k'='tms kill'

# 📚
HISTSIZE=5000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# ⚙️
export EDITOR='nvim'
export FZF_DEFAULT_COMMAND="rg -uu --files -H"
export FZF_PREVIEW_ADVANCED=true 
export FZF_COMPLETION_TRIGGER=';'
export TAPLO_CONFIG="$HOME/personal/dev/dotfiles/templates/.taplo.toml"

# ⏩
export PATH="$PATH:$HOME/.local/bin" # misc
export PATH="$HOME/.cargo/bin:$PATH" # rust
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH" # kubectl krew
export PATH="$HOME/sqlcl/bin:$PATH"

# 🧰
eval "$(~/.local/bin/mise activate zsh)"

# 🤖
# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
. "/home/huen/.deno/env"

# bun completions
[ -s "/home/huen/.bun/_bun" ] && source "/home/huen/.bun/_bun"
