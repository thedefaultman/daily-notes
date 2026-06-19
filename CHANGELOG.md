# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] — 2026-06-19

Initial open-source release. A configurable, single-user generalization of a personal Obsidian
daily-notes system.

### Added
- `/daily-notes setup` — interactive configuration: interview, vault scaffold, GitHub Project
  create-or-adopt with automatic status-option role mapping, optional memory/plan wiring, and
  idempotent session-capture hook install.
- Core commands: create/status, `add`, `summarize`, `weekly`, `sync-project`, `enrich-and-move`,
  `config`, `doctor`.
- Config-driven design — all user specifics live in `~/.claude/daily-notes/config.json`; nothing is
  hardcoded. Schema documented in `references/config-schema.md`.
- Session-capture Stop hook (`scripts/capture-session.sh`) + idempotent installer
  (`scripts/install-hook.sh`) that merges into `settings.json` non-destructively.
- Vault scaffolder (`scripts/scaffold-vault.sh`) and Obsidian Templates-plugin asset files.
- GitHub Project integration (`references/github-project.md`): sync, dedup/carry, auto-enrich on
  done, and a safe "ensure a review option" helper for freshly created boards.
- Knowledge-graph backlinking of feature pages, plans, and Claude Code session memories, with
  collision rules that keep the graph readable.
- Distribution as both a Claude Code plugin (marketplace) and a copyable skill folder.
