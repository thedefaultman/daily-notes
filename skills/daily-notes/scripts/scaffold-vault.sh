#!/usr/bin/env bash
# scaffold-vault.sh — create the daily-notes vault folder structure and Reference symlinks.
#
# Idempotent: `mkdir -p` and `ln -sfn` are safe to re-run. Reads every path from config,
# so it never assumes a vault location. This handles only the deterministic filesystem
# scaffold (folders + symlinks); the skill writes the content pages (Index, MOC, feature
# pages, templates) because those depend on the setup interview.
#
# Usage: bash scaffold-vault.sh [path-to-config.json]

set -euo pipefail
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required."; exit 1; }

CONFIG_BASE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CONFIG_FILE="${1:-$CONFIG_BASE/daily-notes/config.json}"
[ -f "$CONFIG_FILE" ] || { echo "ERROR: config not found at $CONFIG_FILE. Run /daily-notes setup first."; exit 1; }
jq empty "$CONFIG_FILE" >/dev/null 2>&1 || { echo "ERROR: $CONFIG_FILE is not valid JSON."; exit 1; }

# get() returns "" (not the string "null") for a missing key, so a hand-edited config that
# omits a directory name fails fast instead of creating a folder literally named "null".
get() { jq -r "$1 // empty" "$CONFIG_FILE"; }

ROOT=$(get '.vault.root')
[ -n "$ROOT" ] || { echo "ERROR: vault.root is empty in config."; exit 1; }

# Subdirectory names fall back to the schema defaults if absent.
PROJECT=$(get '.project.name'); [ -n "$PROJECT" ] || PROJECT="Project"
DAILY=$(get '.vault.daily_dir');       [ -n "$DAILY" ]     || DAILY="Daily"
WEEKLY=$(get '.vault.weekly_dir');      [ -n "$WEEKLY" ]    || WEEKLY="Weekly"
PROJECTS=$(get '.vault.projects_dir');  [ -n "$PROJECTS" ]  || PROJECTS="Projects"
PEOPLE=$(get '.vault.people_dir');      [ -n "$PEOPLE" ]    || PEOPLE="People"
TEMPLATES=$(get '.vault.templates_dir');[ -n "$TEMPLATES" ] || TEMPLATES="Templates"
REFERENCE=$(get '.vault.reference_dir');[ -n "$REFERENCE" ] || REFERENCE="Reference"
STAGING=$(get '.vault.staging_dir');    [ -n "$STAGING" ]   || STAGING=".staging"

mkdir -p \
  "$ROOT/$DAILY" \
  "$ROOT/$WEEKLY" \
  "$ROOT/$PROJECTS/$PROJECT" \
  "$ROOT/$PEOPLE" \
  "$ROOT/$TEMPLATES" \
  "$ROOT/$REFERENCE" \
  "$ROOT/$STAGING/archive"

echo "Vault folders ready under: $ROOT"

# Reference symlinks: external dirs -> <vault>/<reference_dir>/<name>
REFDIR="$ROOT/$REFERENCE"
jq -c '.reference_symlinks[]?' "$CONFIG_FILE" | while read -r entry; do
  name=$(echo "$entry" | jq -r '.name // empty')
  target=$(echo "$entry" | jq -r '.target // empty')
  if [ -n "$target" ] && [ -e "$target" ]; then
    ln -sfn "$target" "$REFDIR/$name"
    echo "  linked $REFERENCE/$name -> $target"
  else
    echo "  SKIP $REFERENCE/$name (target missing or empty: $target)"
  fi
done

echo "Done."
