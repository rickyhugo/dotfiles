#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///

"""Build configured skill plugins and deploy global links with mise."""

import argparse
import fcntl
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


ROOT = Path(__file__).resolve().parents[1]
SKILLS = ROOT / "agent-skills"
SCHEDULE_LABEL = "dev.dotfiles.agent-skills-sync"
LEGACY_LABEL = "dev.dotfiles.pstack-sync"
HOSTS = {
    "opencode": ".config/opencode/agents",
    "claude": ".claude/agents",
    "codex": ".codex/agents",
}


def read_json(path, default=None):
    return json.loads(path.read_text()) if path.exists() else default


def write_json(path, value):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def validate_id(value):
    if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", value):
        raise ValueError(f"Invalid source, plugin, skill, or agent ID: {value!r}")
    return value


def local_path(root, relative):
    path = root / relative
    if not path.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"Path escapes its source directory: {relative!r}")
    return path


def plugin_definition(value):
    if isinstance(value, str):
        return {"path": value, "skill_sets": ["skills"]}
    if not isinstance(value, dict) or not isinstance(value.get("path"), str):
        raise ValueError("Plugin definitions must be a path or an object with a path")
    definition = dict(value)
    skill_sets = definition.setdefault("skill_sets", ["skills"])
    if (
        not isinstance(skill_sets, list)
        or not skill_sets
        or not all(isinstance(item, str) and item for item in skill_sets)
    ):
        raise ValueError("Plugin skill_sets must be a non-empty list of paths")
    return {"path": definition["path"], "skill_sets": skill_sets}


def plugin_skill_roots(plugin_root, definition):
    roots = []
    for relative in definition["skill_sets"]:
        root = local_path(plugin_root, relative)
        if not root.is_dir():
            raise ValueError(f"Plugin skill set is not a directory: {root}")
        roots.append(root)
    return roots


def skill_directories(plugin_root, definition):
    directories = {}
    for root in plugin_skill_roots(plugin_root, definition):
        for child in sorted(root.iterdir()):
            if (child / "SKILL.md").is_file():
                directories[child] = None
    return list(directories)


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


def fetch_source(root, source_id, pin):
    validate_id(source_id)
    if not re.fullmatch(r"[0-9a-f]{40}", pin["revision"]):
        raise ValueError("Source revision must be a full commit SHA")
    selection = json.dumps(
        {"repository": pin["repository"], "plugins": pin["plugins"]}, sort_keys=True
    )
    fingerprint = hashlib.sha256(selection.encode()).hexdigest()[:12]
    cache = root / ".cache" / source_id / f"{pin['revision']}-{fingerprint}"
    if cache.exists():
        for plugin_id, value in pin["plugins"].items():
            definition = plugin_definition(value)
            if not skill_directories(cache / validate_id(plugin_id), definition):
                raise ValueError(f"Incomplete source cache: {cache}")
        return cache
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
            timeout=180,
            env={**os.environ, "GIT_TERMINAL_PROMPT": "0"},
        )
        paths = []
        for value in pin["plugins"].values():
            definition = plugin_definition(value)
            local_path(repo, definition["path"])
            paths.append(definition["path"])
        subprocess.run(
            [
                "git",
                "-C",
                str(repo),
                "checkout",
                "--quiet",
                "FETCH_HEAD",
                "--",
                *dict.fromkeys(paths),
            ],
            check=True,
        )
        staged = Path(tmp) / "plugins"
        for plugin_id, value in pin["plugins"].items():
            validate_id(plugin_id)
            definition = plugin_definition(value)
            shutil.copytree(
                local_path(repo, definition["path"]),
                staged / plugin_id,
                ignore=shutil.ignore_patterns(".git"),
            )
        staged.rename(cache)
    return cache


def collect_plugins(sources, root, offline):
    plugins = {}
    for source_id, pin in sources.items():
        validate_id(source_id)
        cache = None if source_id in offline else fetch_source(root, source_id, pin)
        for plugin_id, value in pin["plugins"].items():
            validate_id(plugin_id)
            if plugin_id in plugins:
                raise ValueError(f"Duplicate plugin ID across sources: {plugin_id}")
            definition = plugin_definition(value)
            plugin = (
                local_path(offline[source_id], definition["path"])
                if cache is None
                else cache / plugin_id
            )
            if not skill_directories(plugin, definition):
                raise ValueError(f"Plugin has no skills: {plugin}")
            plugins[plugin_id] = {
                "root": plugin,
                "skill_sets": definition["skill_sets"],
            }
    return plugins


def split_skill(text):
    if not text.startswith("---\n") or "\n---\n" not in text[4:]:
        raise ValueError("Expected SKILL.md YAML frontmatter")
    end = text.index("\n---\n", 4) + 5
    return text[:end], text[end:]


def apply_replacements(text, replacements):
    for old, new in replacements.items():
        if not isinstance(old, str) or not old or not isinstance(new, str):
            raise ValueError("body_replacements must map non-empty strings to strings")
        text = text.replace(old, new)
    return text


def adapt_skill(text, name, compat, override, adapter, replacements=None):
    header, body = split_skill(text)
    lines = header.splitlines()
    if not any(line.startswith("name:") for line in lines):
        lines.insert(1, f"name: {name}")
    lines = [f"name: {name}" if line.startswith("name:") else line for line in lines]
    if "description" in override:
        lines = [line for line in lines if not line.startswith("description:")]
        lines.insert(1, "description: " + json.dumps(override["description"]))
    if "body" in override:
        body = local_path(adapter, override["body"]).read_text()
    body = apply_replacements(body, replacements or {})
    return (
        "\n".join(lines)
        + "\n\n"
        + compat
        + "\n\n## Upstream instructions\n\n"
        + body.lstrip()
    )


def agent_files(source, generated_plugin, adapter, definitions):
    files = {}
    for name, definition in definitions.items():
        validate_id(name)
        description = definition["description"]
        prompt = f"Read {generated_plugin / 'COMPAT.md'} before starting.\n"
        if "prompt" in definition:
            prompt += (
                local_path(adapter, definition["prompt"])
                .read_text()
                .replace("{{plugin_root}}", str(generated_plugin))
            )
        if definition.get("include_upstream", True):
            _, body = split_skill((source / "agents" / f"{name}.md").read_text())
            prompt += "\n" + body
        read_only = definition.get("read_only", False)
        shell = definition.get("shell", True)
        opencode = f"---\ndescription: {json.dumps(description)}\nmode: subagent\n"
        if read_only:
            opencode += (
                "permissions:\n  - action: edit\n    resource: '*'\n    effect: deny\n"
            )
        if not shell:
            if not read_only:
                opencode += "permissions:\n"
            opencode += "  - action: shell\n    resource: '*'\n    effect: deny\n"
        files[f"agents/opencode/{name}.md"] = opencode + "---\n\n" + prompt
        claude = f"---\nname: {name}\ndescription: {json.dumps(description)}\nmodel: inherit\n"
        if read_only:
            claude += "tools: Read, Grep, Glob, " + (
                "Bash\n" if shell else "WebFetch, WebSearch, Skill\n"
            )
        elif not shell:
            claude += "disallowedTools: Bash, PowerShell\n"
        files[f"agents/claude/{name}.md"] = claude + "---\n\n" + prompt
        files[f"agents/codex/{name}.toml"] = (
            f"name = {json.dumps(name)}\ndescription = {json.dumps(description)}\n"
            f"developer_instructions = {json.dumps(prompt)}\n"
        )
    return files


def manifests(root):
    return [
        read_json(path, {})
        for path in (
            root / ".generated/manifest.json",
            root / "pstack/.generated/manifest.json",
        )
    ]


def ownership(root):
    owned = {}
    for manifest in manifests(root):
        for dest, targets in manifest.get("previous_links", {}).items():
            owned.setdefault(dest, set()).update(targets)
        for dest, src in manifest.get("links", {}).items():
            owned.setdefault(dest, set()).add(src)
    return owned


def preflight(links, home, owned=None):
    owned = owned or {}
    for dest, src in links.items():
        destination = Path(dest)
        if not os.path.lexists(destination):
            continue
        if destination.is_symlink():
            actual = destination.resolve()
            allowed = {
                Path(src).resolve(),
                *(Path(p).resolve() for p in owned.get(dest, [])),
            }
            legacy = home / ".local/share/agent-skills/pstack/skills" / destination.name
            if destination.parent in (home / ".agents/skills", home / ".claude/skills"):
                allowed.add(legacy.resolve())
            if actual in allowed:
                continue
        raise FileExistsError(
            f"Refusing to replace unrelated file or link: {destination}"
        )


def add_link(links, destination, source):
    destination = str(destination)
    if destination in links:
        raise ValueError(f"Duplicate link destination: {destination}")
    links[destination] = str(source)


def build(plugins, root=SKILLS, home=None):
    home = home or Path.home()
    generated = root / ".generated"
    shared = (root / "compat.md").read_text()
    files = {"COMPAT.md": shared}
    modes = {}
    links = {}
    skill_ids = set()
    configs = {}
    agent_ids = set()
    for plugin_id in plugins:
        validate_id(plugin_id)
        configs[plugin_id] = read_json(root / "plugins" / plugin_id / "plugin.json", {})
        definitions = configs[plugin_id].get("agents", {})
        if agent_ids.intersection(definitions):
            raise ValueError("Duplicate native agent ID across plugins")
        agent_ids.update(definitions)
    for plugin_id, source_config in sorted(plugins.items()):
        validate_id(plugin_id)
        source = source_config["root"]
        adapter = root / "plugins" / plugin_id
        config = configs[plugin_id]
        replacements = config.get("body_replacements", {})
        if not isinstance(replacements, dict):
            raise ValueError("body_replacements must be an object")
        compat = shared
        if (adapter / "compat.md").exists():
            compat += "\n\n" + (adapter / "compat.md").read_text()
        prefix = Path("plugins") / plugin_id
        skills = []
        for skill in skill_directories(
            source, {"skill_sets": source_config["skill_sets"]}
        ):
            upstream = validate_id(skill.name)
            override = config.get("skills", {}).get(upstream, {})
            name = validate_id(override.get("name", upstream))
            if name in skill_ids:
                raise ValueError(f"Duplicate skill ID across plugins: {name}")
            skill_ids.add(name)
            skills.append((skill, name, override))
        skill_names = {skill: name for skill, name, _ in skills}
        ordered_skills = sorted(
            skill_names, key=lambda path: len(path.parts), reverse=True
        )
        for path in sorted(source.rglob("*")):
            if not path.is_file():
                continue
            skill = next(
                (item for item in ordered_skills if path.is_relative_to(item)), None
            )
            relative = (
                prefix / path.relative_to(source)
                if skill is None
                else prefix / "skills" / skill_names[skill] / path.relative_to(skill)
            )
            files[str(relative)] = path.read_bytes()
            modes[str(relative)] = path.stat().st_mode & 0o777
        for skill, name, override in skills:
            relative = prefix / "skills" / name
            files[str(relative / "SKILL.md")] = adapt_skill(
                (skill / "SKILL.md").read_text(),
                name,
                compat,
                override,
                adapter,
                replacements,
            )
            for directory in (".agents/skills", ".claude/skills"):
                add_link(links, home / directory / name, generated / relative)
        files[str(prefix / "COMPAT.md")] = compat
        definitions = config.get("agents", {})
        files.update(agent_files(source, generated / prefix, adapter, definitions))
        for dest, relative in config.get("links", {}).items():
            if not dest.startswith("~/"):
                raise ValueError("Plugin link destinations must start with ~/")
            relative_dest = Path(dest[2:])
            if relative_dest.is_absolute() or ".." in relative_dest.parts:
                raise ValueError(f"Plugin link destination escapes home: {dest}")
            destination = str(home / relative_dest)
            add_link(links, destination, local_path(adapter, relative))
    for host, directory in HOSTS.items():
        for path in sorted(files):
            if path.startswith(f"agents/{host}/"):
                dest = str(home / directory / Path(path).name)
                add_link(links, dest, generated / path)
    for manifest in manifests(root):
        removed = set(manifest.get("links", {})) - set(links)
        if removed:
            raise ValueError(
                "Installed skills or links were removed; review them before updating:\n"
                + "\n".join(sorted(removed))
            )
    owned = ownership(root)
    preflight(links, home, owned)
    generated.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for relative, content in files.items():
        data = content.encode() if isinstance(content, str) else content
        destination = generated / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_suffix(destination.suffix + ".tmp")
        temporary.write_bytes(data)
        temporary.chmod(modes.get(relative, 0o644))
        temporary.replace(destination)
        hashes[relative] = hashlib.sha256(data).hexdigest()
    write_mise_config(generated, links)
    write_json(
        generated / "manifest.json",
        {
            "files": hashes,
            "links": links,
            "previous_links": {
                dest: sorted(targets) for dest, targets in owned.items()
            },
        },
    )
    return generated, links


def write_mise_config(generated, links):
    (generated / "mise.toml").write_text(
        "\n".join(
            f'[dotfiles.{json.dumps(dest)}]\nsource = {json.dumps(src)}\nmode = "symlink"\n'
            for dest, src in links.items()
        )
    )


def check(generated):
    manifest = json.loads((generated / "manifest.json").read_text())
    for relative, expected in manifest["files"].items():
        if hashlib.sha256((generated / relative).read_bytes()).hexdigest() != expected:
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


def deploy(generated, links, root=SKILLS):
    if not links:
        return
    preflight(links, Path.home(), ownership(root))
    subprocess.run(
        [
            "mise",
            "--quiet",
            "-C",
            str(generated),
            "dotfiles",
            "apply",
            "--force",
            "--yes",
            *links,
        ],
        check=True,
    )


def schedule_config(home, mise, root):
    logs = home / "Library/Logs/agent-skills"
    return {
        "Label": SCHEDULE_LABEL,
        "ProgramArguments": [str(mise), "-C", str(root), "run", "skills:update"],
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


def legacy_schedule_owned(home, root):
    path = home / "Library/LaunchAgents" / f"{LEGACY_LABEL}.plist"
    expected = root / "pstack/.generated/schedule" / path.name
    return path.is_symlink() and path.resolve() == expected.resolve()


def retire_legacy_schedule(home, root):
    if not legacy_schedule_owned(home, root):
        return
    service = f"gui/{os.getuid()}/{LEGACY_LABEL}"
    if (
        subprocess.run(
            ["launchctl", "list", LEGACY_LABEL], capture_output=True
        ).returncode
        == 0
    ):
        subprocess.run(["launchctl", "bootout", service], check=True)
    (home / "Library/LaunchAgents" / f"{LEGACY_LABEL}.plist").unlink()


def schedule(action):
    if sys.platform != "darwin":
        raise ValueError("Daily scheduling currently supports macOS launchd only")
    home = Path.home()
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
    target = home / "Library/LaunchAgents" / f"{SCHEDULE_LABEL}.plist"
    generated = SKILLS / ".generated/schedule"
    source = generated / target.name
    if action == "disable":
        if loaded:
            subprocess.run(["launchctl", "bootout", service], check=True)
        if target.is_symlink() and target.resolve() == source.resolve():
            target.unlink()
        retire_legacy_schedule(home, SKILLS)
        print("Daily agent skills sync disabled.")
        return
    mise = shutil.which("mise")
    if not mise:
        raise ValueError("mise must be on PATH")
    links = {str(target): str(source)}
    preflight(links, home)
    generated.mkdir(parents=True, exist_ok=True)
    (home / "Library/Logs/agent-skills").mkdir(parents=True, exist_ok=True)
    source.write_bytes(plistlib.dumps(schedule_config(home, mise, ROOT)))
    write_mise_config(generated, links)
    deploy(generated, links)
    if loaded:
        subprocess.run(["launchctl", "bootout", service], check=True)
    subprocess.run(["launchctl", "bootstrap", domain, str(target)], check=True)
    retire_legacy_schedule(home, SKILLS)
    print("Daily agent skills sync enabled at 09:00 local time and login.")


def archive_legacy(root):
    for name in (".generated", ".cache"):
        old = root / "pstack" / name
        if old.exists():
            destination = root / ".cache/legacy-pstack" / name.lstrip(".")
            if destination.exists():
                raise FileExistsError(f"Legacy archive already exists: {destination}")
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(old), str(destination))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        action="append",
        default=[],
        metavar="ID=PATH",
        help="Use an offline checkout for a configured source (repeatable)",
    )
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--update", action="store_true")
    parser.add_argument("--schedule", choices=("enable", "disable", "status"))
    args = parser.parse_args()
    if args.schedule:
        schedule(args.schedule)
        return
    if args.update and (args.source or args.check):
        parser.error("--update cannot be combined with --source or --check")
    lockfile = SKILLS / ".cache/install.lock"
    lockfile.parent.mkdir(parents=True, exist_ok=True)
    with lockfile.open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if args.check:
            check(SKILLS / ".generated")
            return
        sources = read_json(SKILLS / "sources.json")
        offline = {}
        for value in args.source:
            name, separator, path = value.partition("=")
            if not separator or name not in sources or not path or name in offline:
                parser.error(
                    "--source expects a unique configured source ID and path: ID=PATH"
                )
            offline[name] = Path(path).expanduser().resolve()
        selected = (
            {name: latest_pin(pin) for name, pin in sources.items()}
            if args.update
            else sources
        )
        plugins = collect_plugins(selected, SKILLS, offline)
        generated, links = build(plugins)
        if args.install or args.update:
            deploy(generated, links)
            check(generated)
            if args.update:
                write_json(SKILLS / "sources.json", selected)
                for name, pin in selected.items():
                    print(
                        f"Upstream sync successful ({name}): {sources[name]['revision']} -> {pin['revision']}"
                    )
            if sys.platform == "darwin" and legacy_schedule_owned(Path.home(), SKILLS):
                schedule("enable")
            archive_legacy(SKILLS)
        else:
            print(f"Built agent skills in {generated}")


if __name__ == "__main__":
    main()
