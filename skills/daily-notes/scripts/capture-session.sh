#!/usr/bin/env bash
# capture-session.sh — Claude Code "Stop" hook for the daily-notes skill.
#
# Captures lightweight session metadata (repo, branch, last commit) to a JSONL file
# so `/daily-notes summarize` can reconstruct the day's work even across many sessions.
# Designed to run in well under 100ms with no network calls.
#
# Everything is read from the daily-notes config — this script hardcodes no vault path
# and no repo. A hook must never break a session, so any missing prerequisite is a
# silent successful no-op (exit 0), never an error.

set -euo pipefail

CONFIG_BASE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CONFIG_FILE="$CONFIG_BASE/daily-notes/config.json"

# Prerequisites — bail silently if the user hasn't configured the skill or lacks jq.
command -v jq >/dev/null 2>&1 || exit 0
[ -f "$CONFIG_FILE" ] || exit 0

VAULT_ROOT=$(jq -r '.vault.root // empty' "$CONFIG_FILE" 2>/dev/null || true)
[ -n "$VAULT_ROOT" ] || exit 0
STAGING_REL=$(jq -r '.vault.staging_dir // ".staging"' "$CONFIG_FILE" 2>/dev/null || echo ".staging")
TZ_NAME=$(jq -r '.user.timezone // "UTC"' "$CONFIG_FILE" 2>/dev/null || echo "UTC")

STAGING_DIR="$VAULT_ROOT/$STAGING_REL"
SESSIONS_FILE="$STAGING_DIR/sessions.jsonl"
LAST_CAPTURE="$STAGING_DIR/.last_capture"
COOLDOWN=300  # seconds — skip a re-capture of the same commit within 5 minutes

# The Stop hook receives JSON on stdin; prefer its cwd, then env, then pwd.
INPUT=$(cat 2>/dev/null || echo '{}')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
[ -n "$CWD" ] || CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Must be inside a git repo.
REPO_ROOT=$(cd "$CWD" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "")
[ -n "$REPO_ROOT" ] || exit 0
REPO_NAME=$(basename "$REPO_ROOT")

# Only capture for repos the user listed in config (match on the git root basename).
MATCH=$(jq -r --arg n "$REPO_NAME" '.repos[]?.name | select(. == $n)' "$CONFIG_FILE" 2>/dev/null | head -1 || true)
[ -n "$MATCH" ] || exit 0

cd "$REPO_ROOT"
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "none")
LAST_COMMIT=$(git log -1 --format="%h %s" 2>/dev/null || echo "none")

# Dedup: skip if same commit and within cooldown.
NOW=$(date +%s)
if [ -f "$LAST_CAPTURE" ]; then
  read -r PREV_HASH PREV_TS < "$LAST_CAPTURE" 2>/dev/null || true
  if [ "${PREV_HASH:-}" = "$COMMIT_HASH" ] && [ $(( NOW - ${PREV_TS:-0} )) -lt $COOLDOWN ]; then
    exit 0
  fi
fi

mkdir -p "$STAGING_DIR"

# `day` is the date in the user's timezone — summarize filters on it so the day boundary
# matches the user's wall clock, not the machine's UTC clock. `ts` keeps the offset.
DAY=$(TZ="$TZ_NAME" date +%Y-%m-%d)
TS=$(TZ="$TZ_NAME" date +"%Y-%m-%dT%H:%M:%S%z")
RELATIVE_CWD="${CWD#"$REPO_ROOT"}"
RELATIVE_CWD="${RELATIVE_CWD#/}"
[ -z "$RELATIVE_CWD" ] && RELATIVE_CWD="."

echo '{}' | jq -c \
  --arg ts "$TS" \
  --arg day "$DAY" \
  --arg repo "$REPO_NAME" \
  --arg branch "$BRANCH" \
  --arg commit "$LAST_COMMIT" \
  --arg cwd "$RELATIVE_CWD" \
  '{ts: $ts, day: $day, repo: $repo, branch: $branch, last_commit: $commit, cwd: $cwd}' \
  >> "$SESSIONS_FILE"

echo "$COMMIT_HASH $NOW" > "$LAST_CAPTURE"
