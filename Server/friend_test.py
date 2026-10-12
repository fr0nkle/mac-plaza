"""Start/stop the Mac-hosted pilot without touching the system Tailscale app."""
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent
SERVER = ROOT / "Server"
RUN = SERVER / ".run"
STATE = RUN / "tailscale"
RECORD = RUN / "processes.json"
CLI = "/opt/homebrew/bin/tailscale"
DAEMON = "/opt/homebrew/bin/tailscaled"
SOCKET = str(STATE / "tailscaled.sock")


def matches(item):
    try:
        command = subprocess.check_output(
            ["ps", "-wwp", str(item["pid"]), "-o", "command="], text=True).strip()
        cwd = subprocess.check_output(
            ["lsof", "-a", "-p", str(item["pid"]), "-d", "cwd", "-Fn"], text=True)
        return command == item["command"] and "n" + item["cwd"] in cwd.splitlines()
    except subprocess.CalledProcessError:
        return False


def save(items):
    temporary = RECORD.with_suffix(".tmp")
    temporary.write_text(json.dumps(items, indent=2) + "\n")
    temporary.replace(RECORD)


def tailscale(*args):
    return subprocess.run([CLI, "--socket=" + SOCKET, *args],
                          capture_output=True, text=True, timeout=30)


def start(items):
    from run_local import settings
    config = settings(SERVER / ".env")
    if config.get("PLAZA_BIND", "127.0.0.1") != "127.0.0.1" or config.get("PORT", "8787") != "8787":
        raise RuntimeError("This pilot requires localhost:8787 in Server/.env.")
    if not Path(CLI).is_file() or not Path(DAEMON).is_file():
        raise RuntimeError("Install the official Homebrew tailscale formula first.")

    def ensure(kind, command, cwd):
        if any(row["kind"] == kind and matches(row) for row in items):
            return next(row["pid"] for row in items if row["kind"] == kind and matches(row))
        with (RUN / (kind.replace(" ", "-") + ".log")).open("ab") as log:
            child = subprocess.Popen(command, cwd=cwd, stdin=subprocess.DEVNULL,
                                     stdout=log, stderr=log, start_new_session=True)
        time.sleep(0.3)
        if child.poll() is not None:
            raise RuntimeError("Could not start " + kind + "; inspect its private .run log.")
        actual = subprocess.check_output(["ps", "-wwp", str(child.pid), "-o", "command="], text=True).strip()
        items.append(dict(kind=kind, pid=child.pid, command=actual, cwd=str(cwd)))
        save(items)
        return child.pid

    ensure("Plaza Tailscale daemon", [DAEMON, "--tun=userspace-networking",
           "--statedir=" + str(STATE), "--socket=" + SOCKET], ROOT)
    deadline = time.monotonic() + 20
    while True:
        status = tailscale("status", "--json")
        if not status.returncode and json.loads(status.stdout).get("BackendState") == "Running":
            break
        if time.monotonic() >= deadline:
            break
        time.sleep(0.5)
    if status.returncode or json.loads(status.stdout).get("BackendState") != "Running":
        raise RuntimeError("Authorize the dedicated device first; see DISTRIBUTION.md. Its saved state must remain in Server/.run/tailscale.")
    host = json.loads(status.stdout)["Self"]["DNSName"].rstrip(".")
    if config.get("PLAZA_PUBLIC_URL") != "https://" + host:
        raise RuntimeError("The dedicated device hostname must match PLAZA_PUBLIC_URL and Discord's callback.")
    with socket.socket() as probe:
        occupied = probe.connect_ex(("127.0.0.1", 8787)) == 0
    if occupied and not any(row["kind"] == "service" and matches(row) for row in items):
        raise RuntimeError("Port 8787 is already occupied by an unrecorded process. Leave it running and inspect it first.")
    service = ensure("service", [str(SERVER / ".venv/bin/python"), "-B", "run_local.py"], SERVER)
    route = tailscale("funnel", "--bg", "--https=443", "http://127.0.0.1:8787")
    if route.returncode:
        raise RuntimeError("The dedicated device needs Funnel approval; see DISTRIBUTION.md.")
    ensure("release watcher", ["zsh", "scripts/watch-private-releases.sh"], ROOT)
    ensure("awake helper", ["caffeinate", "-i", "-w", str(service)], ROOT)
    print("Plaza test running at https://" + host)
    print("Keep this Mac powered on with its lid open. Use Stop Friend Test.command to stop hosting.")


def stop(items):
    # Only our explicit socket and HTTPS route; never reset system Tailscale.
    if any(row["kind"] == "Plaza Tailscale daemon" and matches(row) for row in items):
        tailscale("funnel", "--https=443", "off")
    for row in reversed(items):
        if matches(row):
            os.kill(row["pid"], signal.SIGTERM)
            print("Stopped Plaza test " + row["kind"] + ".")
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline and any(matches(row) for row in items):
        time.sleep(0.1)
    save([row for row in items if matches(row)])
    print("Your database, credentials and dedicated device identity are preserved.")


if __name__ == "__main__":
    os.umask(0o077)
    STATE.mkdir(parents=True, exist_ok=True)
    items = json.loads(RECORD.read_text()) if RECORD.exists() else []
    items = [row for row in items if matches(row)]
    try:
        if sys.argv[1:] == ["start"]:
            start(items)
        elif sys.argv[1:] == ["stop"]:
            stop(items)
        else:
            sys.exit("Usage: friend_test.py start|stop")
    except (OSError, ValueError, subprocess.SubprocessError):
        sys.exit("Pilot setup failed. Check private settings and .run logs; do not share their contents.")
    except RuntimeError as error:
        sys.exit(str(error))
