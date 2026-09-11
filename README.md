# dotfiles

## Setup

```sh
git clone git@github.com:rickyhugo/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

Run the bootstrap for your OS (installs OS deps, then `setup_mise.sh`).
Set `MISE_ENV` on the same command so it flows through to `mise bootstrap`:

```sh
MISE_ENV=personal ./scripts/bootstrap_archlinux.sh  # Arch Linux
MISE_ENV=work ./scripts/bootstrap_macos.sh           # macOS
```

`MISE_ENV` selects the mise profile (e.g. `personal` or `work`).
Persist it in your shell rc, then re-run `mise install` after switching.
