# Path / Branch / Keyword → Feature Page Mapping

This file maps repository paths, branch patterns, and free-text keywords to Obsidian **feature
pages** (the hub nodes under `<projects_dir>/<project>/`). `/daily-notes summarize` uses it to
auto-link commits to features; `/daily-notes add` uses it to auto-link free-text entries.

**It starts almost empty on purpose.** Your codebase's paths and your project's feature names are
unique to you — a shipped list would be wrong for everyone. Grow it as you work: when `summarize` or
`add` encounters a path or topic with no mapping, it should **propose** a new row here (and create
the feature page if it doesn't exist), then ask before committing the mapping. Over a week or two
this file becomes an accurate index of your project.

The examples below are illustrative placeholders — replace them with your own.

## Path Mapping

Match a commit's changed file paths (from `git show --stat`) against these glob-ish patterns; the
most specific match wins.

| Path pattern | Feature page |
|---|---|
| `src/**/auth*` | `[[Auth]]` |
| `src/**/billing*` | `[[Billing]]` |
| `infra/**` or `terraform/**` | `[[Infrastructure]]` |
| `docs/**` | `[[Documentation]]` |

## Branch Pattern Mapping

Match the working branch name (from session captures or `git branch --show-current`).

| Branch pattern | Feature page |
|---|---|
| `*auth*` | `[[Auth]]` |
| `*billing*` | `[[Billing]]` |
| `*infra*` | `[[Infrastructure]]` |

## Keyword Mapping (for `/daily-notes add`)

Match free-text entry content (case-insensitive). These are in addition to the per-domain keywords
in `config.project.domains` — domain keywords route an entry to a *section*; these route it to a
*feature page* wikilink.

| Keywords | Feature page |
|---|---|
| auth, login, oauth, session, token | `[[Auth]]` |
| billing, subscription, invoice, payment, stripe | `[[Billing]]` |
| deploy, infra, terraform, pipeline, ci, cd | `[[Infrastructure]]` |
