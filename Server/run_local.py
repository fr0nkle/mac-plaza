"""Load the private local settings without executing shell code, then run Plaza."""
import os
from pathlib import Path
import shlex
import sys


def settings(path):
    allowed = {"PLAZA_PUBLIC_URL", "PLAZA_BIND", "PORT", "PLAZA_DATABASE",
               "DISCORD_CLIENT_ID", "DISCORD_CLIENT_SECRET", "DISCORD_BOT_TOKEN"}
    result = {}
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        key, separator, value = line.partition("=")
        if not separator or key.strip() not in allowed:
            raise ValueError("Unsupported setting on line " + str(number))
        parts = shlex.split(value, comments=True)
        if len(parts) != 1:
            raise ValueError("Quote the setting value on line " + str(number))
        result[key.strip()] = parts[0]
    return result


if __name__ == "__main__":
    root = Path(__file__).resolve().parent
    try:
        config = settings(root / ".env")
        if not config.get("DISCORD_CLIENT_ID") or not config.get("DISCORD_CLIENT_SECRET"):
            raise ValueError("Fill DISCORD_CLIENT_ID and DISCORD_CLIENT_SECRET in Server/.env first.")
    except (OSError, ValueError):
        # Never print the input, parsed values, or exception text: it may contain a secret.
        sys.exit("Local settings are missing, incomplete, or invalid. Check Server/.env and quote each value.")
    os.chdir(root)
    os.execve(sys.executable, [sys.executable, "server.py"], dict(os.environ, **config))
