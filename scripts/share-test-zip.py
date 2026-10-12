"""Create/revoke a private ZIP download link on the active hosting runtime."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys
from urllib.parse import urlsplit

root = Path(__file__).resolve().parent.parent
marker = root / "Server/.run/hosting-runtime.json"
if marker.exists():
    root = Path(json.loads(marker.read_text())["root"])
sys.path.insert(0, str(root / "Server"))
from downloads import DownloadStore
from run_local import settings

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("zip", nargs="?", type=Path)
parser.add_argument("--days", type=int, default=7)
parser.add_argument("--revoke", help="Previously created download URL")
args = parser.parse_args()
os.umask(0o077)
store = DownloadStore(root / "Server/.downloads")
try:
    if args.revoke:
        url = urlsplit(args.revoke)
        if not url.path.startswith("/download/"):
            raise ValueError("Choose a download URL.")
        store.revoke(url.path[len("/download/"):])
        print("Download link revoked.")
    else:
        if not args.zip:
            parser.error("Choose a ZIP to share.")
        origin = settings(root / "Server/.env")["PLAZA_PUBLIC_URL"].rstrip("/")
        url = urlsplit(origin)
        if url.scheme != "https" or not url.hostname or url.path or url.query or url.fragment or url.username or url.password:
            raise ValueError("Hosting needs an HTTPS origin.")
        token, data = store.create(args.zip, args.days)
        print(json.dumps(dict(url=origin + "/download/" + token,
                              expires=datetime.fromtimestamp(data["expires"], timezone.utc).isoformat(),
                              filename=data["filename"], sha256=data["sha256"])))
except (OSError, ValueError, KeyError):
    sys.exit("Could not update the private download. Check the ZIP, expiry and hosting settings.")
