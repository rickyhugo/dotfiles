#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

"""Build a pinned pstack overlay; let mise manage its global symlinks."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import fcntl


ROOT = Path(__file__).resolve().parents[1]
LAYER = ROOT / "agent-skills/pstack"
SCHEDULE_LABEL = "dev.dotfiles.pstack-sync"


def latest_pin(pin):
    branch = pin.get("branch", "main")
    result = subprocess.run(
        ["git", "ls-remote", pin["repository"], f"refs/heads/{branch}"],
        check=True,
        capture_output=True,
        text=True,
        timeout=120,
        env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
    )
    revision = result.stdout.split()[0] if result.stdout.split() else ""
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError(f"Could not resolve upstream branch {branch!r}")
    return {**pin, "revision": revision}


def split_skill(text):
    if not text.startswith("---\n") or "\n---\n" not in text[4:]:
        raise ValueError("Expected SKILL.md YAML frontmatter")
    end = text.index("\n---\n", 4) + 5
    return text[:end], text[end:]


def adapt_skill(text, name, compat, setup):
    header, body = split_skill(text)
    # Cursor allows display names with spaces; Codex expects portable skill IDs.
    lines = header.splitlines()
    lines = [f"name: {name}" if line.startswith("name:") else line for line in lines]
    if name == "setup-pstack":
        lines = [
            "description: Configure pstack's per-host model roles for OpenCode, Claude Code, or Codex. Use for setup-pstack or changing pstack models."
            if line.startswith("description:")
            else line
            for line in lines
        ]
        body = setup
    return "\n".join(lines) + "\n\n" + compat + "\n\n" + body.lstrip()


def agent_files(source, generated):
    files = {}
    for name in ("poteto-agent", "comment-sicko"):
        _, upstream_body = split_skill((source / "agents" / f"{name}.md").read_text())
        description = (
            "Worker for code-writing and helper tasks delegated by poteto-mode."
            if name == "poteto-agent"
            else "Read-only comment and code-quality reviewer."
        )
        prompt = (
            f"Read {generated / 'COMPAT.md'} before starting.\n"
            f"The installed poteto-mode skill is {generated / 'skills/poteto-mode/SKILL.md'}.\n"
        )
        if name == "poteto-agent":
            prompt += (
                "Read that skill in full, including its principles, before doing any work. "
                "Use its leaf principle skills when relevant. Complete only the delegated "
                "task; the parent owns the overall playbook. Do not search Cursor plugin paths.\n"
            )
        else:
            prompt += "Report findings only. Do not edit any files.\n" + upstream_body
        opencode_header = f"---\ndescription: {description}\nmode: subagent\n"
        if name == "comment-sicko":
            opencode_header += (
                "permissions:\n  - action: edit\n    resource: '*'\n    effect: deny\n"
                "  - action: shell\n    resource: '*'\n    effect: deny\n"
            )
        files[f"agents/opencode/{name}.md"] = opencode_header + "---\n\n" + prompt
        claude_header = (
            f"---\nname: {name}\ndescription: {description}\nmodel: inherit\n"
        )
        if name == "comment-sicko":
            claude_header += "tools: Read, Grep, Glob, WebFetch, WebSearch, Skill\n"
        files[f"agents/claude/{name}.md"] = claude_header + "---\n\n" + prompt
        files[f"agents/codex/{name}.toml"] = (
            f"name = {json.dumps(name)}\ndescription = {json.dumps(description)}\n"
            f"developer_instructions = {json.dumps(prompt)}\n"
        )
    return files


def fetch_source(layer, pin):
    cache = layer / ".cache" / pin["revision"]
    if not (cache / "pstack/skills").is_dir():
        cache.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=cache.parent) as tmp:
            repo = Path(tmp) / "repo"
            subprocess.run(["git", "init", "--quiet", str(repo)], check=True)
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo),
                    "fetch",
                    "--depth=1",
                    pin["repository"],
                    pin["revision"],
                ],
                check=True,
            )
            subprocess.run(
                [
                    "git",
                    "-C",
                    str(repo),
                    "checkout",
                    "--quiet",
                    "FETCH_HEAD",
                    "--",
                    "pstack",
                ],
                check=True,
            )
            shutil.copytree(repo / "pstack", cache / "pstack")
    return cache / "pstack"


def build(source, layer=LAYER, home=None):
    home = home or Path.home()
    generated = layer / ".generated"
    compat = (layer / "compat.md").read_text()
    setup = (layer / "setup.md").read_text()
    # Build in memory first so malformed upstream skills don't cause a partial build.
    files = {"COMPAT.md": compat}
    for path in sorted(source.rglob("*")):
        if path.is_file():
            files[str(path.relative_to(source))] = path.read_bytes()
    for relative in list(files):
        path = Path(relative)
        if path.name == "SKILL.md" and path.parts[0] == "skills":
            files[relative] = adapt_skill(
                files[relative].decode(), path.parent.name, compat, setup
            )
    files.update(agent_files(source, generated))
    links = {}
    for path in sorted((source / "skills").iterdir()):
        if (path / "SKILL.md").is_file():
            for root in (".agents/skills", ".claude/skills"):
                links[str(home / root / path.name)] = str(
                    generated / "skills" / path.name
                )
    for host, root, extension in (
        ("opencode", ".config/opencode/agents", "md"),
        ("claude", ".claude/agents", "md"),
        ("codex", ".codex/agents", "toml"),
    ):
        for name in ("poteto-agent", "comment-sicko"):
            filename = f"{name}.{extension}"
            links[str(home / root / filename)] = str(
                generated / "agents" / host / filename
            )
    links[str(home / ".config/pstack/models.json")] = str(layer / "models.json")
    previous = generated / "manifest.json"
    if previous.exists():
        removed = set(json.loads(previous.read_text())["links"]) - set(links)
        if removed:
            raise ValueError(
                "Upstream removed installed skills; review and remove their managed links "
                "and the old manifest before updating:\n" + "\n".join(sorted(removed))
            )
    preflight(links, home)
    generated.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for relative, content in files.items():
        data = content.encode() if isinstance(content, str) else content
        destination = generated / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        upstream = source / relative
        destination.chmod(
            upstream.stat().st_mode & 0o777 if upstream.is_file() else 0o644
        )
        hashes[relative] = hashlib.sha256(data).hexdigest()
    config = "\n".join(
        f'[dotfiles.{json.dumps(dest)}]\nsource = {json.dumps(src)}\nmode = "symlink"\n'
        for dest, src in links.items()
    )
    (generated / "mise.toml").write_text(config)
    (generated / "manifest.json").write_text(
        json.dumps({"files": hashes, "links": links}, indent=2) + "\n"
    )
    return generated, links


def preflight(links, home):
    for dest, src in links.items():
        destination = Path(dest)
        if not os.path.lexists(destination):
            continue
        if destination.is_symlink():
            actual = destination.resolve()
            legacy = home / ".local/share/agent-skills/pstack/skills" / destination.name
            if actual == Path(src).resolve() or (
                destination.parent in (home / ".agents/skills", home / ".claude/skills")
                and actual == legacy.resolve()
            ):
                continue
        raise FileExistsError(
            f"Refusing to replace unrelated file or link: {destination}"
        )


def check(generated):
    manifest = json.loads((generated / "manifest.json").read_text())
    for relative, expected in manifest["files"].items():
        actual = hashlib.sha256((generated / relative).read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f"Generated file changed: {relative}")
    for dest, src in manifest["links"].items():
        if (
            not Path(dest).is_symlink()
            or Path(dest).resolve() != Path(src).resolve()
            or not Path(src).exists()
        ):
            raise ValueError(f"Missing or incorrect link: {dest}")
    print(
        f"Verified {len(manifest['links'])} global links and {len(manifest['files'])} generated files."
    )


def deploy(generated, links):
    # Restrict --force to preflighted targets, never unrelated global dotfiles.
    preflight(links, Path.home())
    subprocess.run(
        ["mise", "-C", str(generated), "dotfiles", "apply", "--force", "--yes", *links],
        check=True,
    )


def schedule_config(home, mise, root):
    logs = home / "Library/Logs/pstack"
    return {
        "Label": SCHEDULE_LABEL,
        "ProgramArguments": [str(mise), "-C", str(root), "run", "pstack:update"],
        "WorkingDirectory": str(root),
        "StartCalendarInterval": {"Hour": 9, "Minute": 0},
        "RunAtLoad": True,
        "ProcessType": "Background",
        "EnvironmentVariables": {
            "PATH": ":".join(
                [
                    str(home / ".local/bin"),
                    str(home / ".local/share/mise/shims"),
                    "/opt/homebrew/bin",
                    "/usr/local/bin",
                    "/usr/bin",
                    "/bin",
                    "/usr/sbin",
                    "/sbin",
                ]
            ),
            "GIT_TERMINAL_PROMPT": "0",
            "PYTHONUNBUFFERED": "1",
        },
        "StandardOutPath": str(logs / "sync.log"),
        "StandardErrorPath": str(logs / "sync-error.log"),
    }


def schedule(action):
    if sys.platform != "darwin":
        raise ValueError("Daily scheduling currently supports macOS launchd only")
    domain = f"gui/{os.getuid()}"
    service = f"{domain}/{SCHEDULE_LABEL}"
    if action == "status":
        subprocess.run(["launchctl", "print", service], check=True)
        return
    loaded = (
        subprocess.run(
            ["launchctl", "list", SCHEDULE_LABEL], capture_output=True
        ).returncode
        == 0
    )
    if action == "disable":
        if loaded:
            subprocess.run(["launchctl", "bootout", service], check=True)
        target = Path.home() / "Library/LaunchAgents" / f"{SCHEDULE_LABEL}.plist"
        source = LAYER / ".generated/schedule" / target.name
        if target.is_symlink() and target.resolve() == source.resolve():
            target.unlink()
        print("Daily pstack sync disabled.")
        return
    home = Path.home()
    mise = shutil.which("mise")
    if not mise:
        raise ValueError("mise must be on PATH")
    generated = LAYER / ".generated/schedule"
    target = home / "Library/LaunchAgents" / f"{SCHEDULE_LABEL}.plist"
    source = generated / target.name
    links = {str(target): str(source)}
    preflight(links, home)
    generated.mkdir(parents=True, exist_ok=True)
    (home / "Library/Logs/pstack").mkdir(parents=True, exist_ok=True)
    source.write_bytes(plistlib.dumps(schedule_config(home, mise, ROOT)))
    (generated / "mise.toml").write_text(
        f'[dotfiles.{json.dumps(str(target))}]\nsource = {json.dumps(str(source))}\nmode = "symlink"\n'
    )
    deploy(generated, links)
    if loaded:
        subprocess.run(["launchctl", "bootout", service], check=True)
    subprocess.run(["launchctl", "bootstrap", domain, str(target)], check=True)
    print("Daily pstack sync enabled at 09:00 local time and login.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        help="Offline pstack source directory (otherwise fetch the pin)",
    )
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument(
        "--update",
        action="store_true",
        help="Install latest upstream branch and record its pin",
    )
    parser.add_argument("--schedule", choices=("enable", "disable", "status"))
    args = parser.parse_args()
    if args.schedule:
        schedule(args.schedule)
        return
    if args.update and (args.source or args.check):
        parser.error("--update cannot be combined with --source or --check")
    if args.check:
        check(LAYER / ".generated")
        return
    # launchd and manual installs must not write the same generated tree at once.
    lockfile = LAYER / ".cache/install.lock"
    lockfile.parent.mkdir(parents=True, exist_ok=True)
    with lockfile.open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        pin = json.loads((LAYER / "upstream.json").read_text())
        selected = latest_pin(pin) if args.update else pin
        source = args.source.resolve() if args.source else fetch_source(LAYER, selected)
        generated, links = build(source)
        if args.install or args.update:
            deploy(generated, links)
            check(generated)
            if args.update:
                (LAYER / "upstream.json").write_text(
                    json.dumps(selected, indent=2) + "\n"
                )
                print(
                    f"Upstream sync successful: {pin['revision']} -> {selected['revision']}"
                )
        else:
            print(f"Built compatibility layer in {generated}")


if __name__ == "__main__":
    main()
