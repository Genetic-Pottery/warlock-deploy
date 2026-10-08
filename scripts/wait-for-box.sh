#!/usr/bin/env bash
# Wait until first boot finishes and you can log in as your user.
#
# Usage: scripts/wait-for-box.sh <user>@<box-ip>
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 user@host" >&2
  exit 2
fi

TARGET=$1
HOST=${TARGET#*@}
START=$(date +%s)

echo "Waiting for $TARGET. First boot builds warlock from source and can take 20 minutes or more."
echo "To watch the build while you wait, run: ssh root@$HOST journalctl -fu amazon-init"

until ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
  "$TARGET" true 2>/dev/null; do
  printf '\r%d minutes elapsed' $((($(date +%s) - START) / 60))
  sleep 20
done

printf '\rReady after %d minutes. Log in with: ssh %s\n' $((($(date +%s) - START) / 60)) "$TARGET"
