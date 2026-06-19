---
name: daily-notes
description: Obsidian daily-notes system with session auto-capture, GitHub Project sync, and an interlinked knowledge graph. Create, append to, summarize, and roll up daily notes; sync a GitHub Project board into the note; backlink commits, PRs, memories, and plans to feature pages. Use when the user invokes /daily-notes, runs /daily-notes setup, or asks about daily notes, work logs, session summaries, or their work journal. First-time users run /daily-notes setup to configure everything.
---

# Daily Notes

A configurable, Obsidian-compatible daily-notes system. It captures what you work on across
Claude Code sessions, summarizes your commits and PRs into a daily log, syncs a GitHub Project
board into the note, and keeps a clean interlinked graph of daily notes ↔ feature pages ↔
plans ↔ memories ↔ people.

This skill is **config-driven**: it hardcodes no vault path, repo, or GitHub board. The first
time anyone uses it, they run `/daily-notes setup`, which interviews them, builds their vault,
wires up GitHub, installs the capture hook, and writes the config every other command reads.

## Load config first

Every command except `setup` reads the user's configuration from:

```
${CLAUDE_CONFIG_DIR:-$HOME/.claude}/daily-notes/config.json
```

Read that file before doing anything. If it is **missing or invalid JSON**, stop and tell the
user: _"daily-notes isn't configured yet — run `/daily-notes setup` and I'll walk you through
it."_ Do not invent defaults for a missing config. The full schema is documented in
`references/config-schema.md`; read it whenever you need a field's meaning.

Throughout this skill, `config.X` means "the value at key X in that config file." Resolve all
dates and times in `config.user.timezone` (use `TZ="<timezone>" date ...` in shell) so the
note's day boundary matches the user's wall clock.

## Subcommand routing

Parse the args passed to this skill and route to the matching section:

| Args | Route to |
|---|---|
| `setup` | **Setup** — read `references/setup.md` and run the interview + scaffold |
| (none) | **Create / Status** |
| `add <text>` | **Add Entry** |
| `summarize` | **Summarize** |
| `weekly` or `weekly <Www>` | **Weekly Rollup** |
| `sync-project` | **GitHub Project Sync** (manual trigger) |
| `enrich-and-move <issue-numbers>` | **Enrich and Move** |
| `config` | Print a human-readable summary of the current config (vault path, project, repos, board) |
| `doctor` | **Doctor** — verify the install (config valid, vault exists, hook registered, `gh` auth) |

Natural-language triggers that also route to **Enrich and Move**, but only when a **Things to
Know** report was just emitted in this conversation: `move the issues` (all flagged issues),
`move it` (only when the report flagged exactly one), `move #N` / `move issues #N #M`. If no
such report exists yet, ask the user to run `/daily-notes enrich-and-move <numbers>` explicitly.

---

## Setup (`/daily-notes setup`)

This is the one command that runs without a config — it *creates* the config. The full,
step-by-step interview, vault scaffold, GitHub Project create/adopt flow, and hook install live
in **`references/setup.md`**. Read that file and follow it. At a high level it:

1. Interviews the user (name, timezone, vault location, project name + work-area domains, repos).
2. Creates the Obsidian vault folder structure (`scripts/scaffold-vault.sh`) and writes the
   starter graph pages (Index, the project Map-of-Content, templates, a People example).
3. Offers GitHub Project integration — **adopts** an existing board (discovering its field/option
   IDs) or **creates** a new one and seeds it, then role-maps its Status options.
4. Optionally wires session **memory** and **plans** directories into the vault as backlinkable
   `Reference/` symlinks.
5. Installs the session-capture Stop hook (`scripts/install-hook.sh`).
6. Writes `config.json`, then creates today's first daily note so the user sees a result.

Setup is **idempotent**: the scaffold and hook-install scripts are safe to re-run, and the
graph-page and board-seed steps are exists-guarded (create a page only if it's missing; reuse an
existing same-named board rather than creating a duplicate). If a config already exists, offer to
edit specific sections rather than starting from scratch.

---

## Create / Status (`/daily-notes`)

**When no args are provided:**

1. Compute today's `date` (`YYYY-MM-DD`), `day` (e.g. `Friday`), `week` (`YYYY-Www`),
   `yesterday`, and `tomorrow` — all in `config.user.timezone`.
2. Check if `<vault.root>/<vault.daily_dir>/<date>.md` exists.

**If it does not exist — create it** using the template below, substituting placeholders and
expanding the project domain sections from `config.project.domains`. Then:

- Run **GitHub Project Sync** (if `config.github_project.enabled`) to populate the board section.
- Run the **Reconciliation Report** and emit the **Things to Know** table.

**If it exists — show status:** report which sections have content, the session-log entry count,
whether Work Summary has run, and the synced-task count; then run **GitHub Project Sync** (if the
board section is empty/stale) and the **Reconciliation Report**.

### Daily note template

Replace `{{PLACEHOLDER}}` tokens. Build the `## {{PROJECT_NAME}}` block by emitting one
`### <domain.name>` subsection per entry in `config.project.domains`, each with a
`> #{{TAG_ROOT}}/<domain.tag>` blockquote hint. Include the **GitHub Project Tasks** section only
if `config.github_project.enabled`, and the **Next Standup** section only if
`config.project.standup.enabled`.

```markdown
---
date: "{{DATE}}"
day: "{{DAY}}"
week: "{{WEEK}}"
type: daily-note
tags:
  - daily
  - {{TAG_ROOT}}
---

# {{DATE}} -- {{DAY}}

> [[{{YESTERDAY}}|<- Yesterday]] | [[{{TOMORROW}}|Tomorrow ->]]

## Schedule
- [ ] 

## Top Priorities
- [ ] 
- [ ] 
- [ ] 

## GitHub Project Tasks
> Synced from {{PROJECT_URL}} — @{{GH_LOGIN}}
> Source of truth: the project board status. Items here are an auto-synced reflection; check off on the board, not the note.


---

## {{PROJECT_NAME}}

### {{DOMAIN_NAME}}
> #{{TAG_ROOT}}/{{DOMAIN_TAG}}

(... one subsection per configured domain ...)

---

## Next Standup ({{NEXT_STANDUP_DATE}})
> Topics for the next standup ({{STANDUP_DAYS}}).

- [ ] 

---

## Decisions Log
> Key decisions made today -- auto-captured from sessions + manual entries


---

## Work Summary
> Auto-generated by `/daily-notes summarize`

### Commits

### Pull Requests

### Documentation

---

## Next Week TODOs ({{WEEK}})
> Planned work for the upcoming week

- [ ] 

---

## Manual Follow-Up
> Concrete actions you need to perform in external systems (cloud consoles, dashboards, secrets, DNS, etc.).
> _None — remove this line and add entries below as they arise._

---

## Personal

### Health & Energy
> Energy: /5 | Sleep: | Exercise: 


### Learning
> Articles, videos, things learned


### Personal TODOs
- [ ] 

### Reflections
> End-of-day thoughts


---

## Session Log
> Auto-appended by the capture hook -- raw session metadata
```

Report the created path and a one-line status.

---

## Add Entry (`/daily-notes add <text>`)

1. Ensure today's note exists (run Create if needed).
2. Read `references/linking-conventions.md` (section-detection keywords) and
   `references/feature-map.md` (keyword → feature-page mapping).
3. Detect the target section by matching the text against the configured domains'
   `keywords` and the universal section keywords. Prefer the most specific match; default to
   **Decisions Log** when ambiguous.
4. Detect feature-page links by matching the text against the feature map.
5. Format as a timestamped bullet (time in `config.user.timezone`):
   `- **HH:MM** — <text with [[Feature Page]] wikilinks and #{{tag_root}}/<tag> inserted>`
6. Insert it under the target section's blockquote hint, above existing entries; write the file.
7. Report what was added, to which section, with which links.
8. Run **Feature Page Maintenance** for any feature pages the entry linked.

---

## Summarize (`/daily-notes summarize`)

Reconstructs the day's work from session captures + git and writes the Work Summary.

1. Ensure today's note exists. Read `references/feature-map.md` and `references/linking-conventions.md`.
2. **Session captures:** if `<vault.root>/<vault.staging_dir>/sessions.jsonl` exists, read it and
   keep entries whose `day` equals today (in `config.user.timezone`). These tell you which repos
   and branches saw work even if you weren't present for those sessions.
3. **Commits:** for each repo in `config.repos`, at its `local_path`, bake the timezone into the
   command so "midnight" is the user's local midnight (matching the `.day` the hook writes):
   `TZ="<config.user.timezone>" git -C <local_path> log --since="midnight" --oneline --no-merges`.
   Apply the same `TZ=` prefix to any other date-relative git command here. Handle repos with no
   commits gracefully.
4. **PRs:** for each repo with a `github` slug and commits today:
   `gh pr list --repo <github> --author=@me --state=all --json number,title,state,url,createdAt,mergedAt`
   then keep PRs created or merged today.
5. **Map to features:** for each commit, `git -C <repo> show --stat --format="" <hash>` to list
   changed files, match them against the path patterns in `feature-map.md`, and group by feature.
6. **Write Work Summary** — replace the section body with `### Commits` (grouped by feature, with
   `[[Feature]]` wikilinks and `#tag`), `### Pull Requests` (with status + external link), and
   `### Documentation` (any `.md` created/modified). See `references/linking-conventions.md` for
   exact link formats.
7. **Promote decisions:** scan the Session Log for decision-like content; promote key ones to the
   Decisions Log as formatted entries.
8. **Archive consumed captures:** move today's consumed `sessions.jsonl` lines to
   `<staging_dir>/archive/<date>.jsonl` and remove them from `sessions.jsonl`.
9. Run **Feature Page Maintenance** for every feature touched.
10. Run **GitHub Project Sync** (if stale) and the **Reconciliation Report** — summarize is when
    the report has the most signal, because Work Summary is now fresh.
11. Report: commit count, PR count, features touched, and the count of Things-to-Know items.

---

## GitHub Project Sync (`/daily-notes sync-project`, or auto during Create/Summarize)

Only runs when `config.github_project.enabled`. Syncs the user's board items into the note's
**GitHub Project Tasks** section, and auto-enriches items that just reached "done". The full
GraphQL queries, the dedup/carry logic, and the role-mapped status handling live in
**`references/github-project.md`** — read that file and follow its **Sync** section. It uses the
IDs in `config.github_project` (project id, status-field id, role→option-id map); never hardcode
board IDs.

Source-of-truth rule: the **board status** decides whether a task is active or done — the note
checkboxes are a read-only reflection. After syncing, run the **Reconciliation Report**.

---

## Reconciliation Report — "Things to Know"

After any flow that touches Work Summary or the board, surface gaps between what shipped and what
the board reflects, plus anything else worth actioning. **This step is read-only — it never
mutates GitHub.** Run it after **Create/Status**, **Summarize**, and **GitHub Project Sync**.

Detection categories (skip a category with zero rows):

1. **Effectively-done board items** (most valuable): for each PR/commit in today's Work Summary,
   find a board item assigned to `config.github_project.login` that is still in an `active`/`backlog`
   role. Match by (a) explicit `#N` / `Closes #N` reference, (b) ≥3 shared meaningful title tokens
   (drop stop-words), or (c) shared feature page via `feature-map.md`. Skip items already in the
   `review_target` or `done` role.
2. **Manual follow-ups:** distill each entry in the note's `## Manual Follow-Up` section to one
   line. Skip if only the placeholder remains.
3. **Unchecked standup items** (only if `config.project.standup.enabled`): if today/yesterday is a
   standup day and the Next Standup section has unchecked items, surface them.
4. **Unlinked PRs (judgment):** a PR in Work Summary that references no issue and matches no active
   item — flag only if it added meaningful behavior (roughly ≥50 changed lines and touches a non-doc
   source/service file), not a typo or doc chore. The concrete bar keeps the call reproducible.
5. **Stale carried items:** a Personal TODO carried ≥7 days (via its `*(carried from YYYY-MM-DD)*`
   marker) — gentle nudge.

Render as a markdown table titled `## Things to Know`. If every category is empty, emit
`## Things to Know` then `_Nothing flagged._`. Each row must be specific — name issue numbers, PR
numbers, dates, exact statuses, file paths. Vague rows ("some issues might be done") are useless.
Use these row shapes (advertise the move triggers on effectively-done rows so the user knows the
reply):

```
## Things to Know

| Item | Note |
|---|---|
| Project board issue #N ("title") | Effectively done by PR #M (merged YYYY-MM-DD) — board still says <status>. Reply "move it" / "move the issues" to enrich + move to <review_target name>. |
| Project board issue #N ("title") | Already shipped (PR #M on YYYY-MM-DD via title-token match) — board still says <status>. Reply "move it" to enrich + move. |
| Manual follow-up: <System> | <exact action> — <why>. |
| Standup items (YYYY-MM-DD) | Left unchecked — the model can't know what was decided. |
| PR #M ("title") not linked to any issue | Touches <files> — consider tracking the scope as an issue. |
| Personal TODO: <title> | Carried for N days (since YYYY-MM-DD). |
```

After the report, **wait for user confirmation** before any mutating action, and remember which
issues were flagged so the `move it` / `move the issues` triggers map to the right list.

---

## Enrich and Move (`/daily-notes enrich-and-move <issue-numbers>`)

Posts a completion-summary comment on each issue and moves the board item to the configured
`on_complete_move` target. Always gated on user confirmation — never auto-fire. The comment
template, the live-context gathering, the honest-summary diff inspection (including the valuable
**Scope note** when the issue asked for more than the PR delivered), and the board mutation all
live in **`references/github-project.md`** — read its **Enrich and Move** section. Move target and
status-option IDs come from `config.github_project`.

---

## Weekly Rollup (`/daily-notes weekly [Www]`)

1. Use the provided week arg or the current ISO week (in `config.user.timezone`).
2. Compute the Monday–Sunday range; read each existing `<weekly_dir>`-adjacent daily note in range.
3. Write `<vault.root>/<vault.weekly_dir>/<YYYY-Www>.md` aggregating: a Daily Notes list (one
   `[[YYYY-MM-DD]]` per day with a note), Highlights grouped by the configured domains, Key
   Decisions (from each day's Decisions Log), Work Stats (commit/PR/doc totals), and Personal
   Reflections (if non-empty). Tag it `weekly` + `{{tag_root}}`, frontmatter `type: weekly-rollup`.
4. Add `weekly: "[[YYYY-Www]]"` to each in-range daily note's frontmatter if absent.
5. Report the path, days covered, and key stats.

---

## Feature Page Maintenance (automatic, on every note update that references features)

Feature pages live in `<vault.root>/<vault.projects_dir>/<config.project.name>/` and are the
high-degree hub nodes of the graph. Keep them current whenever a note links one. This is not a
subcommand — it runs as part of `add`, `summarize`, and Create.

For each `[[Feature Name]]` referenced:

1. If `<projects_dir>/<project.name>/<Feature Name>.md` doesn't exist, create it from the feature
   template (below). If it exists, append a `- [[YYYY-MM-DD]] — <brief summary>` line to its
   `## Recent Activity` section.
2. Ensure bidirectional links: daily notes use `[[Feature Name]]`; feature pages link back with
   `[[YYYY-MM-DD]]`.
3. **Documentation auto-scan:** scan the `config.reference_symlinks` targets (the `Reference/` dirs)
   for docs whose name or topic matches this feature, and add any new `[[doc]]` wikilinks under the
   page's `## Documentation` section if not already present. (Generalizes over whatever the user
   symlinked — repo docs, design specs — rather than any fixed dir.)
4. If `config.plans.enabled`, link any matching plan files (`[[plan-basename]]`) under the page's
   `## Plans` section. If `config.memory.enabled`, link matching memory files (`[[memory_slug]]`)
   under `## Memory / Operational Notes`. See **Backlinking memories & plans** below.

### Feature page template

```markdown
---
type: feature-page
project: {{TAG_ROOT}}
status: active
tags:
  - {{TAG_ROOT}}
  - feature
created: "{{DATE}}"
---

# {{FEATURE_NAME}}

## Overview
<one-line description>

## Key Links
- **Repo path**: `<relevant source paths>`
- **Related**: [[Other Feature]]

## Documentation
<wikilinks to design docs / specs in Reference/ symlinked dirs>

## Plans
> Implementation plans, linked via Reference symlinks (auto-backlink into the graph).

## Key Decisions

## Memory / Operational Notes
> Session memory entries (incidents, fixes, findings). Also check the backlinks pane.

## Recent Activity
> Explicit activity log. Also check the backlinks pane for additional daily-note references.

## Notes
```

Status values: `research` (not yet built), `active` (in development / recently shipped),
`stable` (shipped, low-churn), `planned` (defined, not started).

---

## Backlinking memories & plans (the clean-graph payoff)

This is what makes the vault a *graph* instead of a pile of notes. It is **optional** and degrades
gracefully — it only runs for the pieces the user actually has.

- **Memories** (`config.memory.enabled`): Claude Code keeps per-project session memory at
  `config.memory.dir` (a `~/.claude/projects/<slug>/memory/` directory; `<slug>` is the project's
  absolute path with `/` → `-`). Setup symlinks it under `Reference/` so each memory file becomes a
  wikilink-able node. When a daily note or feature page concerns a topic a memory covers, link it as
  `[[memory_slug]]` (memory slugs use underscores). Add the link under the feature page's
  `## Memory / Operational Notes` section.
- **Plans** (`config.plans.enabled`): implementation-plan markdown in `config.plans.dirs`
  (symlinked under `Reference/`). Link as `[[plan-basename]]` (plan basenames use hyphens — don't
  confuse a plan with its same-topic memory) under the feature page's `## Plans` section, and track
  them in the project's Plan Status ledger page.

The rule that keeps the graph clean: **primary-assign** each plan and memory to one home feature
page (don't duplicate it across every related hub); cross-hub reach comes from `Related:` hub links
plus Obsidian's automatic backlinks pane. See `references/linking-conventions.md` for the collision
rules (duplicate basenames, underscores vs hyphens, daily-note date links).

---

## Config (`/daily-notes config`)

Print a human-readable summary of the current configuration — don't dump raw JSON. Read the config
and report: vault root, project name + tag root, the configured domains, the repos (name → path →
github), and the board status (enabled? which project URL, which status-field roles map to which
option names). End with the config file path so the user can hand-edit if they want. If no config
exists, tell them to run `/daily-notes setup`.

---

## Doctor (`/daily-notes doctor`)

A read-only health check. Verify and report, one line each: config exists and is valid JSON; the
vault root and its subdirectories exist; the capture hook is registered in settings.json and the
stable script is present; `gh auth status` succeeds with `project` + `repo` scopes (only if the
board is enabled); each `config.repos[].local_path` is a git repo. For any failure, give the exact
fix (usually "re-run `/daily-notes setup`" or a specific `gh auth refresh -s project` command).

---

## Key files

| File | Purpose |
|---|---|
| `references/setup.md` | The full setup interview, vault scaffold, GitHub create/adopt, hook install |
| `references/github-project.md` | GraphQL queries + mutations for sync and enrich-and-move |
| `references/config-schema.md` | The config.json schema, field by field |
| `references/linking-conventions.md` | Tags, wikilink formats, section keywords, collision rules |
| `references/feature-map.md` | Path / branch / keyword → feature-page mapping (user-grown) |
| `scripts/capture-session.sh` | The Stop hook that records session metadata to `sessions.jsonl` |
| `scripts/install-hook.sh` | Idempotent installer that registers the hook in settings.json |
| `scripts/scaffold-vault.sh` | Creates the vault folders + Reference symlinks from config |
| `assets/templates/` | Obsidian-Templates-plugin copies of the note templates (copied into the vault) |
