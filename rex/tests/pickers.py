import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import uuid


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

    def sized(session, block):
        size = api(
            "block.method", session_id=session, block_id=block, method="size", args={}
        )
        return (
            size
            if size.get("owner") == options.client
            and 60 <= size["columns"] <= 104
            and 12 <= size["rows"] <= 34
            else None
        )

    def check_geometry(session, block):
        size = eventually(
            lambda: sized(session, block),
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

    token = uuid.uuid4().hex[:10]
    try:
        source = create("picker-test-source-" + token)
        target_label = "picker-test-target-" + token
        target = create(target_label)
        select(source)
        project = open_picker(source, "project_picker")
        eventually(
            lambda: ".dotfiles" in screen(source, project),
            "Repository list never appeared",
        )
        print("PASS project picker opens from an empty session")
        project_size = check_geometry(source, project)
        original_layer = floating(source)[0]
        original_width, original_height = original_layer["bounds"][2:]
        for scale in (1.25, 0.75):
            width = min(0.9, original_width * scale)
            height = min(0.85, original_height * scale)
            api(
                "session.resize_layer",
                session_id=source,
                layer_id=original_layer["layer_id"],
                bounds=[(1 - width) / 2, (1 - height) / 2, width, height],
            )
            eventually(
                lambda: abs(floating(source)[0]["bounds"][2] - original_width) < 0.015,
                "Picker did not refit after its terminal grid changed",
            )
            check_geometry(source, project)
        print(
            "PASS picker refits and recenters after both larger and smaller app size reports"
        )
        send(source, project, "picker-no-match-" + token)
        eventually(
            lambda: ".dotfiles" not in screen(source, project),
            "Typing did not filter repository rows",
        )
        key(source, project, "ctrl+u")
        send(source, project, ".dotfiles")
        eventually(
            lambda: ".dotfiles" in screen(source, project),
            "Repository query did not find .dotfiles",
        )
        print("PASS real keyboard input filters repositories")
        key(source, project, "escape")
        eventually(lambda: not floating(source), "Escape left the project picker open")
        print("PASS project picker cancellation cleans up its layer")

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
        eventually(
            lambda: target_label in screen(source, sessions),
            "Session list never appeared",
        )
        session_size = check_geometry(source, sessions)
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
            lambda: target_label in screen(target, sessions),
            "Reopened session picker did not render",
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
