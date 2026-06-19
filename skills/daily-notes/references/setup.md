# Setup (`/daily-notes setup`)

This is the one command that runs **without** a config — it creates it. Work through these steps
in order. Be conversational: ask the questions, confirm sensible defaults, and explain what each
piece does. The goal is that a brand-new user with nothing but Claude Code and a desire to keep
daily notes ends with a working vault, a wired GitHub board, an installed capture hook, and their
first daily note — without having edited any JSON by hand.

**Idempotency:** if a config already exists at `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/daily-notes/config.json`,
do not start over. Summarize the current config and ask which part they want to change, then jump
to just that step. `scaffold-vault.sh` and `install-hook.sh` are safe to re-run.

---

## Step 0 — Pre-flight

Check the toolchain and tell the user what each gap costs (don't hard-fail on optional ones):

```bash
command -v jq   >/dev/null && echo "jq ok"   || echo "jq MISSING (required)"
command -v git  >/dev/null && echo "git ok"  || echo "git MISSING (needed to summarize commits)"
command -v gh   >/dev/null && echo "gh ok"   || echo "gh MISSING (needed for GitHub Project board)"
gh auth status 2>&1 | grep -i "Token scopes" || true
```

- `jq` is **required** (the hook and scripts use it). If missing, point to https://jqlang.github.io/jq/ and stop.
- `git` missing only disables commit summarization.
- `gh` missing or unauthenticated only disables the GitHub Project board — the rest works. If the
  board is wanted, `gh` needs the `project` and `repo` scopes. If `gh auth status` lacks `project`,
  the user runs: `gh auth refresh -s project,repo`.
- **Obsidian itself is not required for setup to succeed** — the vault is just markdown folders, and
  every command here works on plain files. But the graph view, backlinks pane, and templates are an
  Obsidian feature, so recommend the user install it from https://obsidian.md and "Open folder as
  vault" pointing at the vault root. Flag this as a manual follow-up at the end.

**Resolve the skill directory once.** The commands below run scripts from this skill. The scripts
live next to the `SKILL.md` you're reading — use that directory. As a plugin it is
`$CLAUDE_PLUGIN_ROOT/skills/daily-notes`; as a copied skill folder it's wherever it was installed
(e.g. `~/.claude/skills/daily-notes` or `<repo>/.claude/skills/daily-notes`). Below, `$SKILL_DIR`
stands for that resolved absolute path — substitute the real one.

---

## Step 1 — Interview

Ask these, offering the bracketed defaults. Keep it tight — most users will accept defaults.

1. **Your name** — for note authorship and people pages.
2. **Timezone** — IANA name (detect a default with `date +%Z` / `timedatectl` but confirm an IANA
   form like `America/New_York`; the config needs the IANA name, not an abbreviation).
3. **Vault location** — absolute path. Default `~/Obsidian/<ProjectName>-Vault`. If the user already
   has an Obsidian vault, offer to use it (the skill only adds its own folders).
4. **Project name** — the primary thing they're tracking (e.g. a product, a company, "Work"). This
   names the `## <project>` daily-note section and the feature-page folder.
5. **Tag root** — a short lowercase slug for nested tags (default = project name slugified). Tags
   render as `#<tag_root>/<domain>`.
6. **Work-area domains** — the 3–6 areas their work splits into. These become the daily-note
   subsections and route `add` entries. Offer a starter set and let them edit:
   - Product & Features · Infrastructure & DevOps · Bugs & Fixes · Growth & Sales · Admin & Ops
   For each, capture a short tag and a few keywords. (Keywords can grow later; seed a handful.)
7. **Repos** — local git repos to summarize. For each: a name (the git-root basename), its absolute
   `local_path`, and its `owner/repo` GitHub slug (optional; enables PR lookups). The hook only
   captures sessions whose repo basename matches one of these names.
8. **Standup?** — if they have a recurring standup, capture the day names; otherwise disable it.

Hold these answers in memory; you'll write them into `config.json` at Step 6.

---

## Step 2 — Scaffold the vault folders

Write a provisional `config.json` (Step 6 finalizes it) so the scripts can read paths. The
provisional config must contain the **full `vault` block** — `root` plus every `*_dir` with its
schema default (`Daily`, `Weekly`, `Projects`, `People`, `Templates`, `Reference`, `.staging`) — and
`project.name`. Don't write a `vault` block containing only `root`, or the scaffold would have no
directory names. Then:

```bash
bash "$SKILL_DIR/scripts/scaffold-vault.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/daily-notes/config.json"
```

This creates `Daily/`, `Weekly/`, `Projects/<project>/`, `People/`, `Templates/`, `Reference/`,
and `.staging/archive/` under the vault root (idempotent), plus any `reference_symlinks`. (The
script also falls back to the schema-default names for any missing `*_dir`, but write them
explicitly so the config file is self-consistent for later commands.)

---

## Step 3 — Write the starter graph pages

Create these so the graph has a spine on day one — but **only create each file if it doesn't already
exist**, so a re-run (e.g. config was deleted but the vault survived) never overwrites the user's
edited pages. Use the configured directory names and project name throughout. Copy the
Obsidian-Templates-plugin files from `$SKILL_DIR/assets/templates/` into the vault's `Templates/`
dir, then adapt the daily-note template's domain sections to match the user's configured domains
(the static copies carry example domains — replace them).

- **`Index.md`** (vault root) — links the top-level folders and the project Map-of-Content. Base it
  on `assets/templates/index.md`.
- **`Projects/<project>/<project>.md`** — the Map-of-Content (MOC) hub. Base it on
  `assets/templates/moc.md`: a short intro, a "Feature Pages" list (empty at first; it grows as
  features are linked), a "Conventions & gotchas" list, and links to the Plan Status ledger + Index.
- **`Projects/<project>/<project> Plan Status.md`** — the plan ledger (only meaningful if
  `plans.enabled`; create a stub otherwise). Base it on `assets/templates/plan-status.md`.
- **`People/` example** — one example person note from `assets/templates/person.md` so the folder
  isn't empty and the user sees the shape.
- **`Templates/Daily-Note.md`, `Weekly-Rollup.md`, `Feature-Page.md`** — the Obsidian Templates
  plugin versions (these use Obsidian's `{{date:...}}` tokens; the skill itself generates real notes
  from `config`, so these are for the user's manual "Insert template" workflow).

---

## Step 4 — GitHub Project board (optional)

Only if the user wants board integration and `gh` is authenticated. **If they decline (or `gh`
isn't available), still write `github_project: { "enabled": false }` into the config** — the object
must be present because every runtime guard reads `github_project.enabled` — then skip to Step 5.
Otherwise, two paths:

### 4a — Adopt an existing project

```bash
gh project list --owner <owner> --format json   # let the user pick; <owner> is a login or org, or "@me"
gh project view <number> --owner <owner> --format json     # -> .id (PVT_...), .url, .number
gh project field-list <number> --owner <owner> --format json
```

From `field-list`, find the single-select field that represents workflow status (its `type` is
`ProjectV2SingleSelectField`; usually named "Status"). Capture its `id` (`PVTSSF_...`) and its
`options` (each `{name, id}`). Then **role-map** the options by asking the user (or inferring):

- `done` — the option meaning finished.
- `review_target` — where completed items go for review (optional; may be null).
- `backlog` — where a brand-new ticket starts.
- `active` — every option that isn't `done` (and isn't a pure `review_target`), i.e. work in flight.

### 4b — Create a new project

First check for an existing board with the same title (so a re-run after a deleted config doesn't
spawn a duplicate) — adopt it via 4a if found:

```bash
gh project list --owner <owner> --format json --jq '.projects[] | select(.title=="<project> Todos")'
gh project create --owner <owner> --title "<project> Todos" --format json   # only if none found -> .id, .number, .url
```

A freshly created GitHub Project ships a default **Status** field with exactly **Todo /
In Progress / Done** — no "In review". Discover it with `field-list` (as in 4a) and map:
`backlog → Todo`, `active → [Todo, In Progress]`, `done → Done`, `review_target → null`.

If the user wants the richer "move finished work to a review column" flow, offer to add an
**In review** option. The robust automated path (read current options, append, write all back) is in
`references/github-project.md` → **Ensure a review option**. If that fails or the user prefers, add
the column manually in the Projects UI and re-run setup, or leave `review_target` null and set
`on_complete_move` to `done`.

### 4c — Resolve the assignee login

The board is filtered to the user's own items. Capture `config.github_project.login` as the
**concrete** login (not `@me`): `gh api user --jq .login` for a personal account, or the user's
login within an org. Store `owner`, `owner_type` (`user` or `org`), `number`, `id`, `url`, the
`status_field` block, **and `on_complete_move`** — set it from the role mapping: `review_target` if
a review column exists, else `done`, else `none`. (Sync auto-moves newly-done items to this target
during normal `/daily-notes` and `summarize`, so it must be set even on the adopt path.)

### 4d — Seed a few tickets (optional, new projects)

If the user has obvious first tasks, offer to create them so the board isn't empty. First list
existing item titles and skip any that already exist (so a re-run doesn't duplicate tickets):

```bash
gh project item-list <number> --owner <owner> --format json --jq '.items[].content.title'
gh project item-create <number> --owner <owner> --title "<task>" --body "<details>"   # only if not already present
```

You can also backfill from recent work — see **Step 7 (Backfill)**.

---

## Step 5 — Wire memory and plans (optional, the graph payoff)

These make the vault a real knowledge graph rather than a note pile. Detect, then offer:

- **Session memory:** Claude Code stores per-project memory at
  `~/.claude/projects/<slug>/memory/`, where `<slug>` is a repo's absolute path with every `/`
  replaced by `-`. For each configured repo, compute the slug and check whether that memory dir
  exists. If it does, offer to set `memory.enabled=true`, `memory.dir=<that path>`, and add a
  `reference_symlinks` entry (`{name:"<repo>-memory", target:<dir>}`) so memory files become
  wikilink-able nodes. If no memory dir exists yet, leave `memory.enabled=false` — it can be wired
  later once the user accumulates memories.
- **Plans:** ask whether the user keeps implementation-plan markdown anywhere (commonly
  `<repo>/docs/plans`). If yes, set `plans.enabled=true`, add the dir(s) to `plans.dirs`, and add a
  `reference_symlinks` entry so the plan files resolve as `[[plan-basename]]`.

Re-run `scaffold-vault.sh` after editing `reference_symlinks` so the new symlinks are created.

---

## Step 6 — Write the config and install the hook

1. Write the finalized `config.json` to `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/daily-notes/config.json`.
   Validate it: `jq empty <path>` must succeed. Match `references/config-schema.md` exactly. Every
   top-level object must be **present** even when a feature is off — write `github_project`,
   `memory`, and `plans` as `{ "enabled": false, ... }` stubs rather than omitting them, so runtime
   `*.enabled` guards always have something to read.
2. Install the session-capture hook:
   ```bash
   bash "$SKILL_DIR/scripts/install-hook.sh"
   ```
   This copies the hook to a stable location and registers it as a Stop hook (idempotently, merging
   into any existing `settings.json` without clobbering other hooks).

---

## Step 7 — Backfill (optional)

Give the user an immediately useful note instead of an empty one:

1. Create today's daily note (run the **Create** flow from `SKILL.md`).
2. Run **Summarize** — it will pick up today's commits/PRs from the configured repos even though the
   capture hook only starts recording from now on.
3. If they created a new board and want it populated from real work, surface recent unique
   work-streams (e.g. distinct branches from `git -C <repo> log --since="14 days ago" --format="%s"`
   grouped sensibly) and offer to create board items for the ones still in flight. Always confirm
   before creating issues/items — don't bulk-create silently.

---

## Step 8 — Report + manual follow-ups

Summarize what was created (vault path, project, domains, repos, board URL, hook status), then list
the manual follow-ups explicitly:

- **Obsidian:** install from https://obsidian.md and "Open folder as vault" → `<vault.root>`. For
  the colored graph, set graph groups by `tag:#<tag_root>/*` vs `tag:#personal/*`.
- **Hook activation:** restart Claude Code (or start a new session) so the Stop hook loads.
- **`gh` scopes (if the board is enabled but scopes were missing):** `gh auth refresh -s project,repo`.
- **Symlinks on Windows:** require Developer Mode or an elevated shell; note this if the user is on
  Windows and memory/plans wiring was requested.
