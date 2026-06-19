# Config Schema

`daily-notes` stores all user-specific settings in **one JSON file** so the skill, the
session-capture hook, and the helper scripts all read from the same place:

```
~/.claude/daily-notes/config.json
```

The skill never hardcodes a vault path, repo, GitHub org, or status-field ID. Everything
below is read from this file at runtime. `/daily-notes setup` writes it; you can also copy
`config.example.json` from the repo, edit it, and drop it at the path above.

If the file is missing or unreadable, every subcommand except `setup` should stop and tell
the user to run `/daily-notes setup` first. Do not invent defaults for a missing config.

## Top-level keys

| Key | Type | Purpose |
|---|---|---|
| `version` | number | Schema version. Currently `1`. Lets future skill versions migrate old configs. |
| `user` | object | Display name + timezone. |
| `vault` | object | Vault root and the subdirectory names inside it. |
| `project` | object | The primary project: its name, tag root, work-area domains, standup settings. |
| `repos` | array | Local git repos to summarize commits/PRs from. May be empty. |
| `github_project` | object | GitHub Project board integration. `enabled:false` turns the whole board feature off. |
| `memory` | object | Optional: Claude Code session-memory directory to backlink into the vault. |
| `plans` | object | Optional: `docs/plans`-style directories to backlink. |
| `reference_symlinks` | array | Optional: external dirs symlinked under `<vault>/<reference_dir>/` so their files become graph nodes. |

## `user`

```json
"user": { "name": "Your Name", "timezone": "America/Los_Angeles" }
```

- `timezone` is an IANA name (e.g. `America/New_York`, `Europe/London`, `UTC`). All dates,
  the daily-note filename, the `HH:MM` entry timestamps, and "since midnight" git windows are
  computed in this timezone. Resolve it with `TZ="<timezone>" date ...` in shell so the note's
  day boundary matches the user's wall clock, not the machine's UTC clock.

## `vault`

```json
"vault": {
  "root": "/abs/path/to/Vault",
  "daily_dir": "Daily", "weekly_dir": "Weekly", "projects_dir": "Projects",
  "people_dir": "People", "templates_dir": "Templates",
  "reference_dir": "Reference", "staging_dir": ".staging"
}
```

All `*_dir` values are **relative to `root`**. Resolve a daily note as
`<root>/<daily_dir>/<YYYY-MM-DD>.md`. Feature pages live in `<root>/<projects_dir>/<project.name>/`.

## `project`

```json
"project": {
  "name": "MyProject",
  "tag_root": "myproject",
  "standup": { "enabled": false, "days": ["Tuesday", "Friday"] },
  "domains": [ { "name": "Product & Features", "tag": "product", "keywords": ["feature","ui"] } ]
}
```

- `name` — used as the `## <name>` section in the daily note and the feature-page folder name.
- `tag_root` — the nested-tag prefix. A domain with `tag:"product"` renders as `#myproject/product`.
- `standup.enabled` — when true, daily notes include a **Next Standup** section; the reconciliation
  report nudges unchecked standup items. `standup.days` are day names the standup recurs on.
- `domains` — the work-area subsections under `## <name>`. Each `{name, tag, keywords}`:
  - `name` is the `### <name>` heading.
  - `tag` is the suffix after `tag_root` for the section's blockquote hint and `add` routing.
  - `keywords` route free-text `add` entries to this section and color the graph.

## `repos`

```json
"repos": [ { "name": "myrepo", "local_path": "/abs/path", "github": "owner/repo" } ]
```

Each repo is scanned by `summarize` (commits since midnight, PRs touched today) and by the
session-capture hook (which only records sessions whose git root basename matches a `name`).
`github` is `owner/repo` for `gh` calls; omit/empty to skip PR lookups for that repo.

## `github_project`

```json
"github_project": {
  "enabled": true,
  "owner": "owner-or-org", "owner_type": "user", "number": 1,
  "id": "PVT_xxx", "url": "https://github.com/users/owner/projects/1", "login": "owner",
  "status_field": {
    "id": "PVTSSF_xxx", "name": "Status",
    "roles": {
      "active": [ { "name": "Todo", "id": "..." }, { "name": "In Progress", "id": "..." } ],
      "backlog": { "name": "Todo", "id": "..." },
      "review_target": { "name": "In review", "id": "..." },
      "done": { "name": "Done", "id": "..." }
    }
  },
  "on_complete_move": "review_target"
}
```

- `owner_type` is `user` or `org`. It selects the GraphQL root (`user(login:)` vs
  `organization(login:)`) and the project URL form (`/users/<o>/projects/N` vs `/orgs/<o>/projects/N`).
- `id` is the ProjectV2 node id (`PVT_...`), needed for board mutations.
- `login` is the **concrete** assignee login the board is filtered to (the user's own work). It is
  compared against real `assignees.login` values during sync, so it must be the resolved login
  (e.g. `octocat`), not the `@me` shorthand. Setup resolves `@me` via `gh api user --jq .login`
  before storing it.
- `status_field.id` is the single-select field node id (`PVTSSF_...`).
- `status_field.roles` maps the four **roles** the skill needs onto whatever options the user's
  board actually has. This is the key abstraction: a brand-new GitHub Project ships only
  `Todo / In Progress / Done`, while a mature board may have `Backlog / In progress / In review / Done`.
  Setup discovers the real options and fills the roles:
  - `active` — array of options meaning "still being worked" (everything that isn't done/review).
  - `backlog` — the single option a brand-new ticket starts in.
  - `review_target` — where a completed item is moved by `enrich-and-move`. **May be `null`** if the
    board has no review column.
  - `done` — the terminal "finished" option.
- `on_complete_move` — `"review_target"`, `"done"`, or `"none"`. What `enrich-and-move` moves a
  finished item to. If `review_target` is null, fall back to `done` (or `none` to comment-only).

## `memory` (optional)

```json
"memory": { "enabled": true, "dir": "/home/you/.claude/projects/<slug>/memory" }
```

Claude Code stores per-project session memory at `~/.claude/projects/<slug>/memory/`, where
`<slug>` is the project's absolute path with every `/` replaced by `-` (e.g.
`/home/you/code/myrepo` → `-home-you-code-myrepo`). When `enabled`, the skill backlinks memory
files (`[[memory_slug]]`) into feature pages and can symlink the dir under `Reference/`. Leave
`enabled:false` if the user doesn't keep Claude memory — the rest of the skill works without it.

## `plans` (optional)

```json
"plans": { "enabled": true, "dirs": ["/abs/repo/docs/plans"] }
```

Directories of implementation-plan markdown to backlink (`[[plan-basename]]`) into feature pages
and a Plan Status ledger. Usually wired via a `reference_symlinks` entry so the files resolve.

## `reference_symlinks` (optional)

```json
"reference_symlinks": [ { "name": "myrepo-docs", "target": "/abs/repo/docs" } ]
```

Each entry creates `<vault>/<reference_dir>/<name>` → `target`. This pulls external markdown
(repo docs, plans, memory) into the vault so Obsidian indexes it and wikilinks resolve into a
single graph. Symlinks are POSIX-friendly; on Windows they require Developer Mode or admin.
