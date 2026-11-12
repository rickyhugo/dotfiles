#!/usr/bin/env python3
"""Check the installed Zsh config without changing its live completion cache."""

import os
from pathlib import Path
import subprocess
import tempfile


home = Path.home()
rc = (home / ".zshrc").read_text()
compinit = "autoload -Uz compinit && compinit"
if rc.count(compinit) != 1:
    raise SystemExit("Cannot locate compinit in ~/.zshrc; update this probe.")

clean_env = {
    key: os.environ[key]
    for key in ("HOME", "USER", "LOGNAME", "LANG", "TMPDIR")
    if key in os.environ
}
clean_env.update(
    PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin", TERM="xterm-256color"
)

with tempfile.TemporaryDirectory(
    prefix="zsh-startup-", dir=os.environ.get("TMPDIR")
) as tmp:
    directory = Path(tmp)
    cache = directory / "completions"
    for name in (".zshenv", ".zprofile"):
        if (home / name).exists():
            (directory / name).write_text(f'source "$HOME/{name}"\n')
    (directory / ".zshrc").write_text(
        rc.replace(compinit, f'{compinit} -w -d "{cache}"') + "\nHISTFILE=/dev/null\n"
    )

    def shell(env, command="exit"):
        result = subprocess.run(
            ["/bin/zsh", "-lic", command],
            env=dict(env, ZDOTDIR=str(directory)),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        if result.returncode:
            raise SystemExit(f"Shell startup failed: exit {result.returncode}")
        return result

    # Model a child shell inheriting the completion paths of an initialized shell.
    inherited_env = dict(os.environ)
    inherited_env["FPATH"] = (
        shell(clean_env, 'print -r -- "$FPATH"').stdout.decode().strip()
    )
    headers = []
    for env in (inherited_env, clean_env, inherited_env, clean_env):
        result = shell(env)
        headers.append(cache.read_text().splitlines()[0])
        if len(headers) > 1 and b"regenerating" in result.stderr:
            raise SystemExit(
                "FAIL: compinit rebuilds when switching shell environments"
            )
    if len(set(headers)) != 1:
        raise SystemExit(
            "FAIL: completion file counts differ between shell environments"
        )
    print("PASS: parent and fresh shells reuse the same completion cache")
