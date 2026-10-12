"""Install/remove the hosting Mac's per-user login agent (no root daemon)."""
import os
from pathlib import Path
import plistlib
import json
import shutil
import sqlite3
import subprocess
import sys

LABEL = "org.squidproductions.macplaza.host"
SERVER = Path(__file__).resolve().parent
AGENT = Path.home() / "Library/LaunchAgents" / (LABEL + ".plist")
HOST = Path.home() / "Library/Application Support/Mac Plaza Host"


def unload():
    # Only our named agent in the current user's GUI session.
    subprocess.run(["/bin/launchctl", "bootout", "gui/" + str(os.getuid()) + "/" + LABEL],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def configuration(server=None):
    server = server or HOST / "Server"
    return {
        "Label": LABEL,
        "ProgramArguments": [str(server / ".venv/bin/python"), "-B", "-u",
                             str(server / "friend_test.py"), "start"],
        "WorkingDirectory": str(server),
        "RunAtLoad": True,
        # Retry if networking is still starting at login; stop retrying on success.
        "KeepAlive": {"SuccessfulExit": False},
        "ThrottleInterval": 30,
        "AbandonProcessGroup": True,
        "ProcessType": "Background",
        "Umask": 0o077,
        "EnvironmentVariables": {"PATH": "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"},
        "StandardOutPath": str(server / ".run/login-start.log"),
        "StandardErrorPath": str(server / ".run/login-start-error.log"),
    }


def prepare_runtime():
    """Desktop is privacy protected; run hosting from Application Support instead."""
    server = HOST / "Server"
    first_install = not (HOST / ".configured").exists()
    HOST.mkdir(mode=0o700, parents=True, exist_ok=True)
    HOST.chmod(0o700)
    server.mkdir(mode=0o700, exist_ok=True)
    (server / ".run").mkdir(mode=0o700, exist_ok=True)
    for name in ("server.py", "updates.py", "presence_bot.py", "run_local.py",
                 "friend_test.py", "login_start.py", "Start Friend Test.command",
                 "Stop Friend Test.command"):
        shutil.copy2(SERVER / name, server / name)
    shutil.copytree(SERVER / ".venv", server / ".venv", symlinks=True, dirs_exist_ok=True)
    (server / ".tools").mkdir(mode=0o700, exist_ok=True)
    shutil.copy2(SERVER / ".tools/gh", server / ".tools/gh")
    (HOST / "scripts").mkdir(exist_ok=True)
    for name in ("watch-private-releases.sh", "sync-private-release.py"):
        shutil.copy2(SERVER.parent / "scripts" / name, HOST / "scripts" / name)
    (HOST / "ThirdParty/Sparkle/bin").mkdir(parents=True, exist_ok=True)
    shutil.copy2(SERVER.parent / "ThirdParty/Sparkle/bin/sign_update",
                 HOST / "ThirdParty/Sparkle/bin/sign_update")
    config = None
    if first_install:
        from run_local import settings
        config = settings(SERVER / ".env")
        database = Path(config.get("PLAZA_DATABASE", "plaza.sqlite3"))
        if database.is_absolute() or database.parent != Path(".") or not (SERVER / database).is_file():
            raise ValueError("Migrate a custom database location explicitly before enabling login hosting.")
    # Stop only our recorded components before taking over their database/identity.
    subprocess.run([str(SERVER / ".venv/bin/python"), "-B",
                    str(SERVER / "friend_test.py"), "stop"], check=True)
    if first_install:
        shutil.copy2(SERVER / ".env", server / ".env")
        (server / ".env").chmod(0o600)
        with sqlite3.connect(str(SERVER / database)) as source:
            with sqlite3.connect(str(server / database)) as destination:
                source.backup(destination)
        (server / database).chmod(0o600)
        shutil.copytree(SERVER / ".run/tailscale", server / ".run/tailscale",
                        ignore=shutil.ignore_patterns("*.sock", "*.log"), dirs_exist_ok=True)
        (server / ".updates").mkdir(mode=0o700, exist_ok=True)
        manifest = json.loads((SERVER / ".updates/release.json").read_text())
        from updates import ReleaseStore
        store = ReleaseStore(SERVER / ".updates")
        for key in ("archive", "source"):
            asset = store.asset(manifest[key])
            shutil.copy2(asset, server / ".updates" / asset.name)
        shutil.copy2(SERVER / ".updates/release.json", server / ".updates/release.json")
        (HOST / ".configured").write_text("Private Plaza hosting runtime\n")
    marker = SERVER / ".run/hosting-runtime.json"
    marker.write_text(json.dumps({"root": str(HOST)}) + "\n")
    marker.chmod(0o600)


def install():
    if not (SERVER / ".venv/bin/python").is_file() or not (SERVER / ".env").is_file():
        sys.exit("Prepare this hosting Mac's private environment first; see DISTRIBUTION.md.")
    os.umask(0o077)
    (SERVER / ".run").mkdir(exist_ok=True)
    unload()
    prepare_runtime()
    AGENT.parent.mkdir(parents=True, exist_ok=True)
    temporary = AGENT.with_suffix(".tmp")
    temporary.write_bytes(plistlib.dumps(configuration()))
    temporary.chmod(0o600)
    temporary.replace(AGENT)
    domain = "gui/" + str(os.getuid())
    subprocess.run(["/bin/launchctl", "enable", domain + "/" + LABEL], check=True)
    subprocess.run(["/bin/launchctl", "bootstrap", domain, str(AGENT)], check=True)
    print("Plaza hosting will start at login. Startup has also been requested now.")
    print("Runtime, database, tunnel identity and private logs: " + str(HOST))


def remove():
    unload()
    AGENT.unlink(missing_ok=True)
    print("Automatic hosting at login is disabled. Already running hosting processes are unchanged.")
    print("Use Stop Friend Test.command if you also want to stop hosting now.")


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["install"]:
            install()
        elif sys.argv[1:] == ["remove"]:
            remove()
        else:
            sys.exit("Usage: login_start.py install|remove")
    except (OSError, ValueError, subprocess.CalledProcessError):
        sys.exit("Could not update the Plaza login agent. Check this Mac's Background Items settings.")
