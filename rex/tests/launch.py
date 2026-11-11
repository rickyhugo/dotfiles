import argparse
import json
import os
import select
import shutil
import statistics
import subprocess
import time
import uuid
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--rex", default=shutil.which("rex"), required=not shutil.which("rex")
    )
    parser.add_argument("--client", required=True)
    parser.add_argument("--restore-session", required=True)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument(
        "--variant",
        action="append",
        help="name=init.lua; omit to test the loaded config",
    )
    parser.add_argument("--profile", action="store_true")
    parser.add_argument("--require-stable", action="store_true")
    parser.add_argument(
        "--cached-driver",
        type=Path,
        help="Lua driver that caches variant actions so config loading is outside launch timing",
    )
    parser.add_argument("--output", type=Path, required=True)
    options = parser.parse_args()
    variants = [item.split("=", 1) for item in options.variant or []] or [
        ("live", None)
    ]
    results = []
    driver = None
    load_before = os.getloadavg()

    def reply():
        assert select.select([driver.stdout], [], [], 15)[0], (
            "Cached action driver timed out"
        )
        line = driver.stdout.readline()
        assert line, "Cached action driver exited: " + driver.stderr.read()
        return line.strip()

    def command(*args):
        result = subprocess.run(
            [options.rex, "--autostart=false", *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, result.stderr.strip()
        return json.loads(result.stdout or "null")

    def api(name, **args):
        return command("api", "call", name, json.dumps(args))

    def view(session):
        return api("session.view", session_id=session)

    for existing in api("session.list").get("sessions") or []:
        for window in view(existing["session_id"]).get("windows") or []:
            for layer in window["layers"]:
                assert not (
                    layer["kind"] == "floating"
                    and any(
                        (block.get("label") or "").startswith("rex.picker.")
                        for block in layer.get("blocks") or []
                    )
                ), "Close existing pickers before measuring launches"

    label = "picker-launch-test-" + uuid.uuid4().hex[:8]
    fixture = api(
        "session.create",
        label=label,
        initial_windows=[
            {
                "window_label": "Launch test",
                "layout": {
                    "block": {
                        "flavor": "com.superlogical.terminal.shell",
                        "options": {"command": ["/bin/sleep", "300"]},
                    }
                },
            }
        ],
    )
    session = fixture["session_id"]
    candidate = None
    candidate_label = label + "-target"
    try:
        candidate = api("session.create", label=candidate_label)["session_id"]
        command(
            "-C",
            options.client,
            "do",
            "session.select",
            "session_id=" + session,
            "--json",
        )
        base = fixture["initial_windows"][0]["block_ids"][0]
        deadline = time.monotonic() + 15
        while True:
            size = api(
                "block.method",
                session_id=session,
                block_id=base,
                method="size",
                args={},
            )
            if size.get("owner") == options.client:
                break
            assert time.monotonic() < deadline, "App did not present the fixture"
        if options.cached_driver:
            assert all(script for _, script in variants), (
                "Cached actions require explicit variants"
            )
            driver = subprocess.Popen(
                [
                    options.rex,
                    "--autostart=false",
                    "-C",
                    options.client,
                    "do",
                    str(options.cached_driver),
                    "-s",
                    session,
                    "--args",
                    json.dumps({"variants": variants, "client_id": options.client}),
                ],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert reply() == "READY", "Cached action driver did not initialize"
        for iteration in range(options.runs):
            for source in ("projects", "sessions"):
                for name, script in (
                    variants if iteration % 2 == 0 else reversed(variants)
                ):
                    action = (
                        "project_picker" if source == "projects" else "session_picker"
                    )
                    argv = ["-C", options.client, "do"]
                    argv += [script, "--action", action] if script else [action]
                    argv += ["-s", session, "client_id=" + options.client, "--json"]
                    trace = {
                        "variant": name,
                        "source": source,
                        "iteration": iteration,
                        "bounds": [],
                        "processes": [],
                    }
                    results.append(trace)
                    start = time.monotonic()
                    if driver:
                        driver.stdin.write(
                            json.dumps({"variant": name, "action": action}) + "\n"
                        )
                        driver.stdin.flush()
                        response = json.loads(reply())
                        assert response["ok"], response["result"]
                        popup = response["result"]
                    else:
                        popup = command(*argv)
                    trace["action_ms"] = (time.monotonic() - start) * 1000
                    block = popup["block_ids"][0]
                    first_rows = None
                    try:
                        while True:
                            now = time.monotonic()
                            assert now - start < 15, "Picker did not render usable rows"
                            layers = [
                                layer
                                for window in view(session).get("windows") or []
                                for layer in window["layers"]
                            ]
                            layer = next(
                                layer
                                for layer in layers
                                if layer["layer_id"] == popup["layer_id"]
                            )
                            bounds = layer["bounds"]
                            if (
                                not trace["bounds"]
                                or trace["bounds"][-1]["rect"] != bounds
                            ):
                                trace["bounds"].append(
                                    {"ms": (now - start) * 1000, "rect": bounds}
                                )
                            screen = api(
                                "block.method",
                                session_id=session,
                                block_id=block,
                                method="format",
                                args={"format": "text", "trim": True},
                            )["content"]
                            expected = (
                                ".dotfiles" if source == "projects" else candidate_label
                            )
                            prompt = "project>" if source == "projects" else "session>"
                            if (
                                expected in screen
                                and prompt in screen
                                and "╭" in screen
                                and "╰" in screen
                                and first_rows is None
                            ):
                                first_rows = time.monotonic()
                                trace["rows_ms"] = (first_rows - start) * 1000
                                trace["work_verified"] = True
                            if options.profile:
                                process = api(
                                    "block.method",
                                    session_id=session,
                                    block_id=block,
                                    method="process",
                                    args={},
                                )
                                names = [
                                    process[key]["name"]
                                    for key in ("child", "foreground")
                                    if process.get(key)
                                ]
                                child = process.get("child", {}).get("pid")
                                if child:
                                    listing = subprocess.run(
                                        ["ps", "-axo", "pid=,ppid=,comm="],
                                        capture_output=True,
                                        text=True,
                                        check=True,
                                    ).stdout
                                    descendants = {child}
                                    children = [
                                        line.split(None, 2)
                                        for line in listing.splitlines()
                                    ]
                                    for _ in range(5):
                                        descendants.update(
                                            int(pid)
                                            for pid, parent, _ in children
                                            if int(parent) in descendants
                                        )
                                    names += sorted(
                                        Path(executable).name
                                        for pid, _, executable in children
                                        if int(pid) in descendants and int(pid) != child
                                    )
                                if (
                                    not trace["processes"]
                                    or trace["processes"][-1]["names"] != names
                                ):
                                    trace["processes"].append(
                                        {
                                            "ms": (time.monotonic() - start) * 1000,
                                            "names": names,
                                        }
                                    )
                            if (
                                first_rows is not None
                                and time.monotonic() - first_rows > 0.2
                            ):
                                break
                        trace["bounds_changes"] = len(trace["bounds"]) - 1
                        if options.require_stable:
                            assert trace["bounds_changes"] == 0, (
                                "Picker resized after creation"
                            )
                        trace["ok"] = True
                    finally:
                        command("send-key", "-s", session, "-b", block, "escape")
                    deadline = time.monotonic() + 5
                    while any(
                        layer["layer_id"] == popup["layer_id"]
                        for window in view(session).get("windows") or []
                        for layer in window["layers"]
                    ):
                        assert time.monotonic() < deadline, (
                            "Escape did not close the picker"
                        )
    except Exception as error:
        if results:
            results[-1]["error"] = str(error)
        raise
    finally:
        if driver:
            driver.stdin.close()
            try:
                driver.wait(timeout=5)
            except subprocess.TimeoutExpired:
                driver.kill()
                driver.wait()
        options.output.parent.mkdir(parents=True, exist_ok=True)
        options.output.write_text(
            json.dumps(
                {
                    "profiled": options.profile,
                    "cached_actions": bool(driver),
                    "config_loading": "outside_timer"
                    if driver
                    else "included"
                    if options.variant
                    else "server_cached",
                    "variants": variants,
                    "cpu_count": os.cpu_count(),
                    "load_before": load_before,
                    "load_after": os.getloadavg(),
                    "results": results,
                },
                indent=2,
            )
            + "\n"
        )
        try:
            command(
                "-C",
                options.client,
                "do",
                "session.select",
                "session_id=" + options.restore_session,
                "--json",
            )
        finally:
            try:
                if candidate:
                    api("session.destroy", session_id=candidate)
            finally:
                api("session.destroy", session_id=session)
    assert all(row.get("ok") and row.get("work_verified") for row in results)
    for name, _ in variants:
        for source in ("projects", "sessions"):
            rows = [
                row
                for row in results
                if row["variant"] == name and row["source"] == source
            ]
            times = [row["rows_ms"] for row in rows]
            print(
                f"{name} {source}: {len(rows)} successful launches, rows median {statistics.median(times):.0f} ms, "
                f"range {min(times):.0f}-{max(times):.0f} ms, bounds changes {[row['bounds_changes'] for row in rows]}"
            )


if __name__ == "__main__":
    main()
