# dotfiles

## Setup

```sh
git clone git@github.com:rickyhugo/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

Run the bootstrap for your OS (installs OS deps, then `setup_mise.sh`):

```sh
./scripts/bootstrap_archlinux.sh  # Arch Linux
./scripts/bootstrap_macos.sh      # macOS
```

## Profiles

`MISE_ENV` selects the mise profile (e.g. `personal` or `work`):

```sh
export MISE_ENV=personal  # or: work
./scripts/setup_mise.sh
```

Set it in your shell rc to persist, then re-run `mise bootstrap` or `mise install` after switching.
