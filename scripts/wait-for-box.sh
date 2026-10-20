#!/usr/bin/env bash
# Wait until first boot finishes and the box joins your tailnet.
#
# The box joins the tailnet at the end of its first NixOS build, so once it
# answers a ping, you can log in. Run this from a device on your tailnet.
#
# Usage: scripts/wait-for-box.sh <tailnet-hostname>
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 hostname" >&2
  exit 2
fi

HOST=$1
START=$(date +%s)

echo "Waiting for $HOST to join your tailnet. First boot builds the NixOS system and can take several minutes."

until tailscale ping -c 1 --timeout 5s "$HOST" >/dev/null 2>&1; do
  printf '\r%d minutes elapsed' $((($(date +%s) - START) / 60))
  sleep 20
done

printf '\rReady after %d minutes. Log in with: ssh <user>@%s\n' $((($(date +%s) - START) / 60)) "$HOST"
