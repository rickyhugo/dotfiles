import argparse
import json
import shutil
import subprocess
import tempfile
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rex", default=shutil.which("rex"))
    parser.add_argument("--client", required=True)
    parser.add_argument("--restore-session", required=True)
    options = parser.parse_args()
    if not options.rex:
        parser.error("Pass --rex with the installed Rex executable")
    owned = []
    repository = None

    def command(*args, text=False):
        result = subprocess.run(
            [options.rex, "--autostart=false", *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode:
            raise AssertionError(result.stderr.strip())
        return result.stdout if text else json.loads(result.stdout or "null")

    def api(name, **args):
        return command("api", "call", name, json.dumps(args))

    def eventually(check, message):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            result = check()
            if result:
                return result
            time.sleep(0.1)
        raise AssertionError(message)

    def create(label):
        session = api("session.create", label=label)["session_id"]
        owned.append(session)
        return session

    def select(session):
        command(
            "-C",
            options.client,
            "do",
            "session.select",
            "session_id=" + session,
            "--json",
        )

    def view(session):
        return api("session.view", session_id=session)

    def open_picker(session, action):
        result = command(
            "-C",
            options.client,
            "do",
            action,
            "-s",
            session,
            "client_id=" + options.client,
            "--json",
        )
        assert result and result.get("block_ids"), (
            "Picker did not return its terminal block"
        )
        return result["block_ids"][0]

    def screen(session, block):
        return command("capture", "-s", session, "-b", block, "--trim", text=True)

    def send(session, block, text):
        command("send", "-s", session, "-b", block, text, text=True)

    def key(session, block, name):
        command("send-key", "-s", session, "-b", block, name, text=True)

    def layers(session):
        return [
            layer
            for window in view(session).get("windows") or []
            for layer in window.get("layers") or []
        ]

    def floating(session):
        return [layer for layer in layers(session) if layer["kind"] == "floating"]

    def sized(session, block, fixed_card):
        size = api(
            "block.method", session_id=session, block_id=block, method="size", args={}
        )
        return (
            size
            if size.get("owner") == options.client
            and size["columns"] >= 60
            and size["rows"] >= 12
            and (not fixed_card or (size["columns"] <= 104 and size["rows"] <= 34))
            else None
        )

    def check_geometry(session, block, fixed_card=True):
        size = eventually(
            lambda: sized(session, block, fixed_card),
            "Picker did not become a readable, bounded card",
        )
        layer = next(
            layer
            for layer in floating(session)
            if any(item["block_id"] == block for item in layer["blocks"])
        )
        x, y, width, height = layer["bounds"]
        assert abs(x - (1 - width) / 2) < 0.02, layer["bounds"]
        assert abs(y - (1 - height) / 2) < 0.02, layer["bounds"]
        return size

    def app_presented(session):
        for layer in layers(session):
            if layer["kind"] == "tiled":
                for block in layer["blocks"]:
                    size = api(
                        "block.method",
                        session_id=session,
                        block_id=block["block_id"],
                        method="size",
                        args={},
                    )
                    if size.get("owner") == options.client:
                        return True
        return False

    def presented_at(session, block):
        size = api(
            "block.method", session_id=session, block_id=block, method="size", args={}
        )
        return next(
            (
                report["updated_at"]
                for report in size.get("desired") or []
                if report["client_id"] == options.client
            ),
            None,
        )

    def presented_after(session, block, previous):
        current = presented_at(session, block)
        return bool(current and current != previous)

    token = uuid.uuid4().hex[:10]
    for session in api("session.list").get("sessions") or []:
        for layer in layers(session["session_id"]):
            if layer["kind"] == "floating" and any(
                (block.get("label") or "").startswith("rex.picker.")
                for block in layer.get("blocks") or []
            ):
                raise AssertionError("Close existing pickers before running live tests")
    try:
        source_label = "picker-test-source-" + token
        source = create(source_label)
        target_label = "picker-test-target-" + token
        target = create(target_label)
        away = create("picker-test-away-" + token)
        away_window = api(
            "session.new_window",
            session_id=away,
            window_label="Away fixture",
            layout={
                "block": {
                    "flavor": "com.superlogical.terminal.shell",
                    "options": {"command": ["/bin/sleep", "300"]},
                }
            },
        )
        away_block = away_window["block_ids"][0]
        select(source)
        project = open_picker(source, "project_picker")
        first_bounds = floating(source)[0]["bounds"]
        eventually(
            lambda: ".dotfiles" in screen(source, project),
            "Repository list never appeared",
        )
        print("PASS project picker opens from an empty session")
        check_geometry(source, project, fixed_card=False)
        assert floating(source)[0]["bounds"] == first_bounds, (
            "Picker resized while appearing"
        )
        send(source, project, "picker-no-match-" + token)
        eventually(
            lambda: ".dotfiles" not in screen(source, project),
            "Typing did not filter repository rows",
        )
        previous = project
        project = open_picker(source, "project_picker")
        assert project != previous, "Opening the same picker did not replace it"
        assert len(floating(source)) == 1, "Duplicate project picker is open"
        eventually(
            lambda: ".dotfiles" in screen(source, project),
            "Replacement project picker did not start with a fresh query",
        )
        api(
            "session.set_layer_state",
            session_id=source,
            layer_id=floating(source)[0]["layer_id"],
            state="minimized",
        )
        sessions = open_picker(source, "session_picker")
        assert sessions != project, "Session picker reused the project block"
        assert len(floating(source)) == 1, "Minimized project picker was not closed"
        assert floating(source)[0]["blocks"][0]["block_id"] == sessions
        eventually(
            lambda: target_label in screen(source, sessions),
            "Session picker did not replace the minimized project picker",
        )
        project = open_picker(source, "project_picker")
        assert len(floating(source)) == 1, "Project picker did not replace sessions"
        assert floating(source)[0]["blocks"][0]["block_id"] == project
        command("config", "reload", "--json")
        previous_away = presented_at(away, away_block)
        select(away)
        eventually(
            lambda: presented_after(away, away_block, previous_away),
            "The app did not switch away from the picker",
        )
        for kind in ("projects", "sessions"):
            api(
                "session.new_layer",
                session_id=source,
                window_id=view(source)["active_window_id"],
                bounds=[0.2, 0.2, 0.6, 0.6],
                layout={
                    "block": {
                        "flavor": "com.superlogical.terminal.shell",
                        "label": "rex.picker." + kind + ":" + options.client,
                        "options": {
                            "shell": "none",
                            "login": False,
                            "command": ["/bin/sleep", "300"],
                        },
                    }
                },
            )
        assert len(floating(source)) == 3, "Legacy picker fixtures were not created"
        sessions = open_picker(away, "session_picker")
        assert not floating(source), "Reload left the old project picker open"
        assert len(floating(away)) == 1, "Replacement session got duplicate pickers"
        eventually(
            lambda: "session>" in screen(away, sessions),
            "Session picker did not open in the requesting session",
        )
        assert not floating(target), "Another session got a duplicate picker"
        assert not view(target).get("windows"), (
            "Replacement touched an unrelated session"
        )
        select(source)
        project = open_picker(source, "project_picker")
        assert not floating(away), (
            "Project picker left the session picker open elsewhere"
        )
        assert len(floating(source)) == 1, (
            "Replacement created duplicate project pickers"
        )
        first_bounds = floating(source)[0]["bounds"]
        eventually(
            lambda: ".dotfiles" in screen(source, project),
            "Project picker did not reopen in the requesting session",
        )
        print(
            "PASS either picker replaces the previous picker across sessions, minimized state, and config reload"
        )
        key(source, project, "ctrl+u")
        send(source, project, ".dotfiles")
        eventually(
            lambda: ".dotfiles" in screen(source, project),
            "Repository query did not find .dotfiles",
        )
        print("PASS real keyboard input filters repositories")
        assert floating(source)[0]["bounds"] == first_bounds, (
            "Picker resized after appearing"
        )
        print("PASS picker opens at final bounds without post-open resizing")
        key(source, project, "escape")
        eventually(lambda: not floating(source), "Escape left the project picker open")
        print("PASS project picker cancellation cleans up its layer")

        def concurrent_open(action):
            result = command(
                "-C",
                options.client,
                "do",
                action,
                "-s",
                source,
                "client_id=" + options.client,
                "--json",
            )
            assert len(floating(source)) <= 1, "Concurrent opens showed two pickers"
            return result

        with ThreadPoolExecutor(max_workers=6) as workers:
            opened = list(
                workers.map(concurrent_open, ["project_picker", "session_picker"] * 3)
            )
        blocks = {result["block_ids"][0] for result in opened if result}
        assert blocks, "Concurrent opens did not create a picker"
        assert len(floating(source)) == 1, "Concurrent opens created duplicate pickers"
        project = floating(source)[0]["blocks"][0]["block_id"]
        assert project in blocks, "Live picker was not returned by an opening action"
        eventually(
            lambda: any(
                prompt in screen(source, project) for prompt in ("project>", "session>")
            ),
            "Concurrent picker launch did not render",
        )
        key(source, project, "escape")
        eventually(lambda: not floating(source), "Concurrent picker did not close")
        print(
            "PASS concurrent mixed-type opens leave only one picker and cancellation permits reopening"
        )

        project = open_picker(source, "project_picker")
        eventually(
            lambda: "project>" in screen(source, project),
            "Project picker did not render before interrupt",
        )
        key(source, project, "ctrl+c")
        eventually(lambda: not floating(source), "Ctrl-C left the project picker open")
        print("PASS Ctrl-C cancels the direct picker process")

        project = open_picker(source, "project_picker")
        first_bounds = floating(source)[0]["bounds"]
        eventually(
            lambda: ".dotfiles" in screen(source, project),
            "Warm project picker did not render",
        )
        project_size = check_geometry(source, project)
        assert floating(source)[0]["bounds"] == first_bounds, (
            "Warm picker resized while appearing"
        )
        key(source, project, "escape")
        eventually(lambda: not floating(source), "Warm project picker did not close")

        host_window = view(source)["active_window_id"]
        repository = Path(
            tempfile.mkdtemp(
                prefix="picker-test-repository-" + token + "-",
                dir=Path.home() / "personal",
            )
        ).resolve()
        subprocess.run(["git", "init", "-q", str(repository)], check=True)
        repository_label = repository.name
        repo_window = api(
            "session.new_window",
            session_id=source,
            window_label="Repository fixture",
            focus=True,
            layout={
                "block": {
                    "flavor": "com.superlogical.terminal.shell",
                    "options": {
                        "cwd": str(repository),
                        "command": ["/bin/sleep", "300"],
                    },
                }
            },
        )
        repo_block = repo_window["block_ids"][0]
        eventually(
            lambda: (
                api(
                    "block.method",
                    session_id=source,
                    block_id=repo_block,
                    method="process",
                    args={},
                )
                .get("foreground", {})
                .get("cwd")
                == str(repository)
            ),
            "Repository fixture process did not report its working directory",
        )
        api("session.focus_window", session_id=source, window_id=host_window)
        select(source)
        project = open_picker(source, "project_picker")
        eventually(
            lambda: "project>" in screen(source, project),
            "Repository picker did not reopen",
        )
        api(
            "session.focus_window",
            session_id=source,
            window_id=repo_window["window_id"],
        )
        previous = project
        project = open_picker(source, "project_picker")
        assert project != previous, (
            "Opening from another tab did not replace the picker"
        )
        assert len(floating(source)) == 1, "Another tab got a duplicate picker"
        assert view(source)["active_window_id"] == repo_window["window_id"], (
            "Replacement did not stay in the requesting tab"
        )
        key(source, project, "escape")
        eventually(lambda: not floating(source), "Replacement picker did not close")
        api("session.focus_window", session_id=source, window_id=host_window)
        project = open_picker(source, "project_picker")
        eventually(
            lambda: "project>" in screen(source, project),
            "Repository picker did not reopen in the host tab",
        )
        key(source, project, "ctrl+r")
        send(source, project, repository_label)
        try:
            eventually(
                lambda: screen(source, project).count(repository_label) >= 2,
                "A newly created repository did not appear after refresh",
            )
        except AssertionError as error:
            raise AssertionError(
                str(error) + "\n" + "\n".join(screen(source, project).splitlines()[:8])
            ) from error
        key(source, project, "enter")
        eventually(
            lambda: not floating(source), "Repository selection left its picker open"
        )
        eventually(
            lambda: view(source)["active_window_id"] == repo_window["window_id"],
            "Repository reuse selected the session but not its matching tab",
        )
        print("PASS repository selection focuses an existing inactive matching tab")

        sessions = open_picker(source, "session_picker")
        first_bounds = floating(source)[0]["bounds"]
        eventually(
            lambda: target_label in screen(source, sessions),
            "Session list never appeared",
        )
        assert source_label not in screen(source, sessions), "Current session is listed"
        key(source, sessions, "ctrl+r")
        eventually(
            lambda: target_label in screen(source, sessions),
            "Refreshed session list never appeared",
        )
        assert source_label not in screen(source, sessions), (
            "Refresh listed the current session"
        )
        print(
            "PASS session picker excludes the current session before and after refresh"
        )
        session_size = check_geometry(source, sessions)
        assert floating(source)[0]["bounds"] == first_bounds, (
            "Session picker resized while appearing"
        )
        assert abs(project_size["columns"] - session_size["columns"]) <= 2
        assert abs(project_size["rows"] - session_size["rows"]) <= 2
        print(
            "PASS matching centered cards, projects {}x{} and sessions {}x{}".format(
                project_size["columns"],
                project_size["rows"],
                session_size["columns"],
                session_size["rows"],
            )
        )
        send(source, sessions, target_label)
        eventually(
            lambda: screen(source, sessions).count(target_label) >= 2,
            "Session query did not find its target",
        )
        key(source, sessions, "enter")
        eventually(
            lambda: not floating(source), "Session selection left its picker open"
        )
        eventually(
            lambda: bool(view(target).get("windows")),
            "Selecting an empty session did not open a terminal",
        )
        eventually(
            lambda: app_presented(target),
            "The app did not switch to the selected session",
        )
        print(
            "PASS choosing an empty session opens a terminal and switches the app there"
        )
        sessions = open_picker(target, "session_picker")
        eventually(
            lambda: source_label in screen(target, sessions),
            "Reopened session picker did not render",
        )
        assert target_label not in screen(target, sessions), (
            "Reopened picker lists its current session"
        )
        check_geometry(target, sessions)
        key(target, sessions, "escape")
        eventually(lambda: not floating(target), "Escape left the session picker open")
        print("PASS session picker reopens and cancels cleanly")
    finally:
        try:
            if repository is not None:
                for session in api("session.list").get("sessions") or []:
                    if (
                        session["label"] == repository.name
                        and session["session_id"] not in owned
                    ):
                        owned.append(session["session_id"])
            select(options.restore_session)
        finally:
            try:
                for session in reversed(owned):
                    api("session.destroy", session_id=session)
            finally:
                if repository is not None:
                    shutil.rmtree(repository)


if __name__ == "__main__":
    try:
        main()
    except (AssertionError, subprocess.TimeoutExpired) as error:
        raise SystemExit("FAIL " + str(error))
