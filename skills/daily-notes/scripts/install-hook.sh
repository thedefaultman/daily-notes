#!/usr/bin/env bash
# install-hook.sh — register the daily-notes session-capture Stop hook, idempotently.
#
# Copies capture-session.sh to a stable location (so a plugin reinstall or skill move
# doesn't break the registered hook) and patches Claude Code's settings.json by parsing
# and merging JSON — never a blind append. Re-running is safe: it detects an existing
# registration and does nothing. It only ever touches the current user's settings.
#
# Usage: bash install-hook.sh           # install/register
#        bash install-hook.sh --remove  # unregister + delete the stable copy

set -euo pipefail

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required. Install it: https://jqlang.github.io/jq/"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_BASE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
DN_DIR="$CONFIG_BASE/daily-notes"
SETTINGS="$CONFIG_BASE/settings.json"
STABLE_HOOK="$DN_DIR/capture-session.sh"
CMD="bash $STABLE_HOOK"

mkdir -p "$DN_DIR"

# Ensure settings.json exists and is valid JSON before we touch it.
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
jq empty "$SETTINGS" >/dev/null 2>&1 || { echo "ERROR: $SETTINGS is not valid JSON. Fix it first."; exit 1; }

remove_registration() {
  cp "$SETTINGS" "$SETTINGS.daily-notes.bak"
  local tmp; tmp=$(mktemp)
  jq --arg cmd "$CMD" '
    if .hooks.Stop then
      .hooks.Stop |= ( map( .hooks |= map(select(.command != $cmd)) ) | map(select((.hooks | length) > 0)) )
    else . end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
}

if [ "${1:-}" = "--remove" ]; then
  remove_registration
  rm -f "$STABLE_HOOK"
  echo "Removed daily-notes Stop hook and stable script copy."
  echo "Backup written to: $SETTINGS.daily-notes.bak"
  exit 0
fi

# Install the stable copy.
cp "$SCRIPT_DIR/capture-session.sh" "$STABLE_HOOK"
chmod +x "$STABLE_HOOK"

# Idempotency: do nothing if our exact command is already a Stop hook.
if jq -e --arg cmd "$CMD" '[.hooks.Stop[]?.hooks[]?.command] | index($cmd) != null' "$SETTINGS" >/dev/null 2>&1; then
  echo "Hook already registered — nothing to do."
  echo "Stable script: $STABLE_HOOK"
  exit 0
fi

cp "$SETTINGS" "$SETTINGS.daily-notes.bak"
tmp=$(mktemp)
jq --arg cmd "$CMD" '
  .hooks //= {} |
  .hooks.Stop //= [] |
  .hooks.Stop += [ { "matcher": "*", "hooks": [ { "type": "command", "command": $cmd } ] } ]
' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

echo "Registered Stop hook: $CMD"
echo "Stable script: $STABLE_HOOK"
echo "Backup written to: $SETTINGS.daily-notes.bak"
echo "Restart Claude Code (or start a new session) for the hook to take effect."
