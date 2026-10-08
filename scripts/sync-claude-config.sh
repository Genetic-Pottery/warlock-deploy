#!/usr/bin/env bash
# Copy your local Claude Code setup to the warlock box: CLAUDE.md, settings,
# skills, plugins, themes, and the status line script.
#
# It never copies login credentials, conversation history, or project memory.
#
# Usage: scripts/sync-claude-config.sh ubuntu@<box-ip>
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 user@host" >&2
  exit 2
fi

TARGET=$1
SRC="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
REMOTE_HOME=$(ssh "$TARGET" 'printf %s "$HOME"')

ITEMS=(CLAUDE.md settings.json skills plugins themes statusline-command.sh keybindings.json)

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

for item in "${ITEMS[@]}"; do
  if [[ -e "$SRC/$item" ]]; then
    cp -a "$SRC/$item" "$STAGE/"
  fi
done

# Settings and plugin manifests hold absolute paths. Point them at the remote
# home directory instead of yours.
grep -rlIF -- "$HOME" "$STAGE" 2>/dev/null | while read -r f; do
  sed -i "s#${HOME}#${REMOTE_HOME}#g" "$f"
done

echo "Copying to $TARGET:~/.claude:"
ls -1 "$STAGE"
ssh "$TARGET" 'mkdir -p ~/.claude'
rsync -a "$STAGE/" "$TARGET:.claude/"
echo "Done. Restart any running claude session on the box to pick it up."
