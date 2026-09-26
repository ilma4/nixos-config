"""Run the llama router only while its external model volume is mounted."""

from contextlib import closing
import os
import select
import signal
import subprocess
import sys
import time


def stop_server(process):
    # The router starts model workers; terminate the entire process group,
    # including any workers left behind if the router has crashed.
    try:
        os.killpg(process.pid, signal.SIGTERM)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            process.poll()  # Reap the router so it cannot keep the group alive.
            os.killpg(process.pid, 0)
            time.sleep(0.1)
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


def supervise(volume, models_directory, command):
    # StartOnMount fires for every volume. Exit successfully for unrelated mounts
    # so launchd waits for the next mount instead of restarting this job.
    if not os.path.ismount(volume) or not os.path.isdir(models_directory):
        return 0

    class Stopped(Exception):
        pass

    def stop(*_):
        raise Stopped

    for sig in (signal.SIGTERM, signal.SIGINT):
        signal.signal(sig, stop)

    process = None
    volume_fd = None
    try:
        # O_EVTONLY observes the volume without holding it busy for unmount.
        volume_fd = os.open(volume, os.O_EVTONLY)
        with closing(select.kqueue()) as events:
            events.control([select.kevent(
                volume_fd, filter=select.KQ_FILTER_VNODE,
                flags=select.KQ_EV_ADD | select.KQ_EV_CLEAR,
                fflags=select.KQ_NOTE_REVOKE,
            )], 0)
            # Close the race between the initial mount check and registration.
            if not os.path.ismount(volume) or events.control(None, 1, 0):
                return 0
            process = subprocess.Popen(command, start_new_session=True)
            print(f"llama-server started (pid {process.pid})", flush=True)
            events.control([select.kevent(
                process.pid, filter=select.KQ_FILTER_PROC,
                flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT,
                fflags=select.KQ_NOTE_EXIT,
            )], 0)
            # Block in the kernel until unmount or router exit: no timer/polling.
            notifications = events.control(None, 2)
            if any(event.filter == select.KQ_FILTER_VNODE for event in notifications):
                print("Model volume unmounted; stopping llama-server", flush=True)
                return 0
            return 1  # launchd throttles and retries an unexpected router exit.
    except Stopped:
        return 0
    except FileNotFoundError:
        if not os.path.ismount(volume):
            return 0
        raise
    finally:
        for sig in (signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, signal.SIG_IGN)
        if process is not None:
            stop_server(process)
        if volume_fd is not None:
            os.close(volume_fd)


if __name__ == "__main__":
    sys.exit(supervise(sys.argv[1], sys.argv[2], sys.argv[3:]))
