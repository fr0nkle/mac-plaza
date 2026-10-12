#!/bin/zsh
set -u
cd "${0:A:h:h}"
while true; do
  python3 scripts/sync-private-release.py || echo 'Private release sync failed; keeping the previous complete update.' >&2
  sleep 60
done
