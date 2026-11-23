import fcntl
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time


SWAYMSG, DARKMAN = sys.argv[1:]
REDRAW_DELAY = 0.15  # Several frames at 60 Hz; apps don't acknowledge theme updates.


def ipc(*args):
    return json.loads(subprocess.check_output([SWAYMSG, "-r", *args], timeout=5))


def command(*commands):
    batch = "; ".join(commands)
    replies = ipc("--", batch)
    if not replies or not all(reply["success"] for reply in replies):
        raise RuntimeError(f"Sway rejected {batch!r}: {replies}")


def quote(name):
    return json.dumps(name, ensure_ascii=False)


def select_workspace(name):
    return f"workspace --no-auto-back-and-forth {quote(name)}"


def nodes(node):
    yield node
    for child in node["nodes"] + node["floating_nodes"]:
        yield from nodes(child)


def refresh():
    workspaces = ipc("-t", "get_workspaces")
    hidden = [w for w in workspaces if not w["visible"]]
    focused = next((w for w in workspaces if w["focused"]), None)
    if not hidden or focused is None:
        return

    outputs = {o["name"]: o for o in ipc("-t", "get_outputs")}
    right = max(o["rect"]["x"] + o["rect"]["width"] for o in outputs.values() if o["active"])
    restore_focus = (
        f'focus output {quote(focused["output"])}',
        select_workspace(focused["name"]),
    )
    warping = re.findall(
        r"(?m)^[ \t]*mouse_warping[ \t]+(output|container|none)\b",
        ipc("-t", "get_config")["config"],
    )

    def find_new_output():
        created = [
            o["name"] for o in ipc("-t", "get_outputs")
            if o["name"] not in outputs and re.fullmatch(r"HEADLESS-\d+", o["name"])
        ]
        return created[0] if len(created) == 1 else None

    virtual_name = None
    creating_output = False
    try:
        command("mouse_warping none")
        creating_output = True
        command("create_output")
        virtual_name = find_new_output()
        if virtual_name is None:
            raise RuntimeError("could not identify the new headless output")
        virtual = quote(virtual_name)

        # Refresh workspaces, not tabs hidden inside an otherwise visible workspace.
        for ws in hidden:
            live = next((w for w in ipc("-t", "get_workspaces") if w["id"] == ws["id"]), None)
            if not live or live["visible"] or live["output"] != ws["output"]:
                continue
            output = outputs[ws["output"]]
            if not output["active"] or not output["current_workspace"]:
                continue
            tree = next((n for n in nodes(ipc("-t", "get_tree")) if n["id"] == ws["id"]), None)
            view = tree and next((n for n in nodes(tree) if n.get("shell") and not n.get("sticky")), None)
            if not view:
                continue

            mode = output["current_mode"]
            command(
                f'output {virtual} mode {mode["width"]}x{mode["height"]} '
                f'scale {output["scale"]} transform {output["transform"]} position {right + 100} 0'
            )
            try:
                # Sway focuses the moved workspace. Undo that in the same IPC transaction;
                # the workspace remains visible (and can render) on the headless output.
                command(f'[con_id={view["id"]}] move workspace to output {virtual}', *restore_focus)
                time.sleep(REDRAW_DELAY)
            finally:
                location = next((w for w in ipc("-t", "get_workspaces") if w["id"] == ws["id"]), None)
                if location and location["output"] == virtual_name:
                    command(
                        select_workspace(ws["name"]),
                        f'move workspace to output {quote(ws["output"])}',
                        select_workspace(output["current_workspace"]),
                        *restore_focus,
                    )
    finally:
        try:
            # Recover the output if interrupted between creating and identifying it.
            if creating_output and virtual_name is None:
                virtual_name = find_new_output()
            if virtual_name:
                command(f"output {quote(virtual_name)} unplug", *restore_focus)
        finally:
            command(f'mouse_warping {warping[-1] if warping else "output"}')


def interrupted(_signum, _frame):
    raise KeyboardInterrupt


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, interrupted)
    try:
        lock_path = Path(os.environ["XDG_RUNTIME_DIR"]) / "msi-modern-theme-refresh.lock"
        with lock_path.open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            subprocess.run([DARKMAN, "toggle"], check=True, timeout=5)
            refresh()
    except KeyboardInterrupt:
        sys.exit("toggle-theme-refresh-workspaces: interrupted")
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        sys.exit(f"toggle-theme-refresh-workspaces: {error}")
