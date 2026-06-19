# Linking Conventions

Rules for creating Obsidian-compatible links and tags. The specific tag names come from the user's
`config.project` (its `tag_root` and `domains`); the formats and structural rules below are universal.

## Tags (nested, Obsidian-compatible)

### Project tags
One per configured domain, as `#<tag_root>/<domain.tag>`. For example, with `tag_root: "acme"` and a
domain tagged `product`, the section hint and routed entries use `#acme/product`. Keep them nested
under the single `tag_root` so the graph can color the whole project tree at once.

### Personal tags (universal)
- `#personal/health` — energy, sleep, exercise
- `#personal/learning` — articles, videos, TIL
- `#personal/todos` — non-work tasks
- `#personal/journal` — reflections, thoughts

### Note-type tags
- `#daily` — on all daily notes
- `#weekly` — on all weekly rollups

## Wikilink formats

| Link type | Format | Example |
|---|---|---|
| Daily → Daily | `[[YYYY-MM-DD]]` | `[[2026-06-19]]` |
| Daily → Feature | `[[Feature Name]]` | `[[Billing]]` |
| Daily → Weekly | `[[YYYY-Www]]` | `[[2026-W25]]` |
| Weekly → Dailies | `[[YYYY-MM-DD]]` | listed in the rollup body |
| Feature → Feature | `[[Other Feature]]` | `[[Auth]]` |
| PRs and commits | External markdown | `[PR #42](https://github.com/owner/repo/pull/42)` |
| Repo docs / plans (`.md`) | Wikilink | `[[some-design-doc]]` or `[[some-design-doc\|Display Text]]` |
| Memory entries | Wikilink | `[[project_some_finding]]` |
| Non-md files | Wikilink with extension | `[[diagram.html\|Architecture Diagram]]` |

Prefer wikilinks over `file:///` URLs — only wikilinks create backlinks in Obsidian's graph.

## Section detection keywords (`/daily-notes add`)

Universal sections route on these. Domain sections route on the `keywords` configured for each
domain in `config.project.domains` — check those first, then fall back to the universal list.

| Target section | Keywords |
|---|---|
| Decisions Log | decided, decision, chose, picked, switched, changed approach |
| Manual Follow-Up | need to, must, remember to, follow up, action item, todo (external system) |
| Health & Energy | energy, sleep, exercise, health, mood |
| Learning | learned, article, read, watched, TIL |
| Personal TODOs | errand, appointment, personal task, chore |
| Reflections | reflect, thinking about, journal, feeling |

Default when ambiguous: **Decisions Log**.

## Symlinked reference directories

`config.reference_symlinks` creates `<vault>/<reference_dir>/<name>` → an external dir, making that
dir's files wikilink-able graph nodes. Common targets: a repo's `docs/`, a `docs/plans/` dir, and
the Claude Code session-memory dir. For `.md` files use `[[filename]]`; for non-md use
`[[file.ext|Display Text]]`.

## File naming

- Daily notes: `<daily_dir>/YYYY-MM-DD.md`
- Weekly rollups: `<weekly_dir>/YYYY-Www.md`
- Feature pages: `<projects_dir>/<project>/Feature Name.md`

## Collision rules (keep the graph clean)

These prevent the graph from tangling as it grows:

- **Duplicate basenames must be path-qualified.** If two files share a basename (e.g. several
  `README.md`), a bare `[[README]]` is ambiguous — link the full vault-relative path,
  `[[Reference/repo-docs/product/README|Product README]]`.
- **Memory slugs use underscores; plan basenames use hyphens.** `[[project_some_finding]]` is a
  memory; `[[some-feature-plan]]` is a plan. Don't confuse a plan with its same-topic memory.
- **Primary-assign each plan/memory to one home feature page.** Don't duplicate it across every
  related hub — cross-hub reach comes from `Related:` links plus the backlinks pane. This is the
  single most important rule for a readable graph.
- **Skills aren't wikilink-able by name** (`SKILL.md` files) — reference them as inline code.
- **Daily-note date links are the spine.** The `[[YYYY-MM-DD]]` form is how the time axis threads
  together; unresolved future-date placeholders are normal and harmless.

## Graph structure goals

- **Time spine** — daily notes chain via yesterday/tomorrow links.
- **Weekly clusters** — each weekly rollup links its 5–7 daily nodes.
- **Feature hubs** — feature pages are high-degree nodes with many daily-note backlinks.
- **Tag coloring** — color `#<tag_root>/*` distinctly from `#personal/*` in Obsidian's graph settings.
