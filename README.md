# daily-notes

A Claude Code skill that turns your work into a living, interlinked Obsidian knowledge graph —
automatically.

Every Claude Code session you run gets quietly captured. Once a day you run `/daily-notes` and the
skill builds a structured daily note: your commits and PRs grouped by feature, your GitHub Project
board synced in, your decisions logged, and everything wikilinked into a graph of daily notes ↔
feature pages ↔ plans ↔ memories ↔ people. Over weeks, the graph becomes a searchable map of
everything you've built and decided — the thing you wish you had when someone asks "wait, why did we
do it that way?"

It's **config-driven**: nothing about it is hardcoded to one person or project. You run
`/daily-notes setup` once, answer a few questions, and it builds your vault, wires your GitHub board
(creating one if you don't have it), installs the capture hook, and writes your config. Everything
after that just works.

> Inspired by a personal daily-notes system, generalized and open-sourced so anyone can use it.

---

## What it does

- **Session auto-capture.** A lightweight Stop hook records which repo/branch/commit each Claude Code
  session touched, so `summarize` can reconstruct your day even across many sessions.
- **Daily notes.** `/daily-notes` creates today's note from a template with your work-area sections,
  a board-sync section, decisions log, manual follow-ups, and a personal section.
- **Work summaries.** `/daily-notes summarize` pulls your commits (since local midnight) and PRs,
  groups them by feature page, promotes decisions, and writes the Work Summary.
- **GitHub Project sync.** Pulls your assigned board items into the note, carries unfinished items
  forward day to day, and auto-enriches items that just hit "done" with a completion-summary comment.
  Don't have a project board? Setup creates one for you.
- **Reconciliation report.** After each update, a read-only "Things to Know" table flags work that
  shipped but whose board item is still open, manual follow-ups, unlinked PRs, and stale TODOs.
- **A clean knowledge graph.** Feature pages are hub nodes; daily notes are the time spine; plans and
  session memories are backlinked into their home feature page. The result is a graph that reads,
  not a hairball.
- **Weekly rollups.** `/daily-notes weekly` aggregates a week of daily notes into one summary.

---

## Requirements

| Tool | Needed for | Required? |
|---|---|---|
| [Claude Code](https://claude.com/claude-code) | Running the skill | Yes |
| `jq` | The capture hook and setup scripts | Yes |
| `git` | Summarizing commits | Recommended |
| [`gh`](https://cli.github.com/) (with `project`,`repo` scopes) | GitHub Project board sync | Optional |
| [Obsidian](https://obsidian.md) | Viewing the graph / backlinks (notes are plain markdown either way) | Recommended |

---

## Install

### Option A — as a Claude Code plugin (recommended)

```
/plugin marketplace add thedefaultman/daily-notes
/plugin install daily-notes@daily-notes-marketplace
```

Then run setup (as a plugin, the skill is namespaced):

```
/daily-notes:daily-notes setup
```

### Option B — as a plain skill folder

Copy the skill into your skills directory:

```bash
git clone https://github.com/thedefaultman/daily-notes
cp -r daily-notes/skills/daily-notes ~/.claude/skills/daily-notes
```

Then run:

```
/daily-notes setup
```

> Use it per-project instead of globally by copying into `<your-repo>/.claude/skills/daily-notes`.

---

## Quick start

```
/daily-notes setup     # one-time: interview + build vault + wire GitHub + install hook
/daily-notes           # create / open today's note (+ sync board, + Things to Know)
/daily-notes add fixed the flaky auth test, decided to drop the retry wrapper
/daily-notes summarize # pull commits + PRs into today's Work Summary
/daily-notes weekly    # roll up the current week
/daily-notes doctor    # verify the install is healthy
```

`/daily-notes setup` walks you through:

1. **You** — name, timezone.
2. **Vault** — where your Obsidian vault lives (it creates the folders).
3. **Project** — what you're tracking and the work-area "domains" it splits into.
4. **Repos** — local git repos to summarize.
5. **GitHub Project** — adopt an existing board or create a new one (it discovers/creates the status
   columns and maps them to roles automatically).
6. **Memory & plans** (optional) — wire your Claude Code session memory and plan docs into the graph.
7. **Hook** — installs the session-capture hook into your settings.

---

## Commands

| Command | What it does |
|---|---|
| `/daily-notes setup` | One-time configuration + vault scaffold + GitHub + hook install |
| `/daily-notes` | Create or show today's note; sync the board; emit Things to Know |
| `/daily-notes add <text>` | Append a timestamped, auto-linked entry to the right section |
| `/daily-notes summarize` | Build the Work Summary from commits + PRs + session captures |
| `/daily-notes weekly [Www]` | Roll up a week of daily notes |
| `/daily-notes sync-project` | Manually re-sync the GitHub Project board |
| `/daily-notes enrich-and-move <#N…>` | Comment on finished issues and move them to review |
| `/daily-notes config` | Print the current configuration |
| `/daily-notes doctor` | Health-check the install |

---

## How it's organized

```
<your vault>/
├── Daily/             # YYYY-MM-DD.md — the time spine
├── Weekly/            # YYYY-Www.md — weekly rollups
├── Projects/<name>/   # feature hub pages + Map-of-Content + Plan Status ledger
├── People/            # person notes
├── Reference/         # symlinks to repo docs / plans / session memory (graph nodes)
├── Templates/         # Obsidian Templates-plugin copies
└── .staging/          # sessions.jsonl (hook captures) + archive/
```

Your configuration lives at `~/.claude/daily-notes/config.json` (one file; the skill, the hook, and
the scripts all read it). Copy `config.example.json` if you'd rather hand-edit than run setup.

### The graph, briefly

- **Daily notes** chain via yesterday/tomorrow links — the time axis.
- **Feature pages** are high-degree hubs; daily notes link `[[Feature]]`, feature pages link back
  `[[YYYY-MM-DD]]`.
- **Plans and memories** are each *primary-assigned* to one home feature page (not copied everywhere)
  — cross-hub reach comes from `Related:` links and Obsidian's backlinks pane. That one rule is what
  keeps the graph readable as it grows.

---

## Privacy & safety

- Nothing leaves your machine except GitHub API calls you opt into (the board sync, via your own
  authenticated `gh`). The capture hook does no network calls.
- The hook only records sessions in the repos you list, and only metadata (repo, branch, commit
  subject) — never file contents.
- `enrich-and-move` (the only thing that writes to GitHub) is always gated on your confirmation.
- The hook installer merges into your `settings.json` non-destructively and writes a backup.

---

## Uninstall

```bash
# Unregister the capture hook. Use your skill path — for a plain skill folder it's the path below;
# plugin users: "$CLAUDE_PLUGIN_ROOT/skills/daily-notes/scripts/install-hook.sh".
bash ~/.claude/skills/daily-notes/scripts/install-hook.sh --remove
rm -rf ~/.claude/daily-notes   # remove config + the stable hook copy
```

Your vault and notes are plain markdown — they stay yours.

---

## Contributing

Issues and PRs welcome. The skill is plain markdown + a few bash scripts; see `skills/daily-notes/`.
If you change what the scripts read/write, update `references/config-schema.md` in the same change —
it's the contract every component depends on.

## License

MIT — see [LICENSE](LICENSE).
