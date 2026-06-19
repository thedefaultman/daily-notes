# GitHub Project Integration

All board work reads its IDs from `config.github_project` — never hardcode a project, field, or
option ID. The relevant config shape (see `references/config-schema.md`):

```
github_project: { enabled, owner, owner_type, number, id, url, login,
                  status_field: { id, name, roles: { active[], backlog, review_target, done } },
                  on_complete_move }
```

`owner_type` selects the GraphQL root: `organization(login: $owner)` for an org, `user(login: $owner)`
for a personal account. The examples below show the `organization` form — swap the root field when
`owner_type == "user"`. Required `gh` scopes: `project`, `repo`.

---

## Sync — pull board items into today's note

### Step 1 — Fetch the user's items

```bash
gh api graphql -f query='
query($login: String!, $number: Int!) {
  organization(login: $login) {            # or: user(login: $login)
    projectV2(number: $number) {
      items(first: 100) {
        nodes {
          id
          fieldValues(first: 20) {
            nodes {
              ... on ProjectV2ItemFieldSingleSelectValue {
                name optionId
                field { ... on ProjectV2SingleSelectField { name } }
              }
            }
          }
          content {
            ... on Issue        { number title url state repository { nameWithOwner } assignees(first: 5) { nodes { login } } }
            ... on DraftIssue   { title assignees(first: 5) { nodes { login } } }
            ... on PullRequest  { number title url state repository { nameWithOwner } assignees(first: 5) { nodes { login } } }
          }
        }
      }
    }
  }
}' -f login="<config.github_project.owner>" -F number=<config.github_project.number>
```

### Step 2 — Filter and classify

Keep items where `config.github_project.login` appears in `assignees` (case-insensitive). Read each
item's Status `optionId` and classify by role using `config.github_project.status_field.roles`:

- **Active** — `optionId` is in `roles.active` (or `roles.backlog`). These render in the note.
- **Newly done** — `optionId` equals `roles.done`. Candidates for auto-enrichment.
- **In review** — `optionId` equals `roles.review_target`. Already processed; skip.

### Step 3 — Dedup against the most recent prior note

Walk back up to 7 days through `<daily_dir>/<YYYY-MM-DD>.md` for the most recent note containing a
`## GitHub Project Tasks` section. Record its date as `PREV_DATE` and extract dedup markers
`<!-- gh-project:(\d+) -->` plus whether each was `[x]` or `[ ]`. If none found, treat the carried
set as empty (handles first run and gaps).

### Step 4 — Build today's task list

For each active item, format:

```
- [ ] [#NUMBER — TITLE](URL) `STATUS` <!-- gh-project:NUMBER -->
```

If the issue was `[ ]` in the prior note, append `*(carried from PREV_DATE)*` before the marker.
DraftIssues (no number/URL): `- [ ] TITLE \`STATUS\` <!-- gh-project-draft:TITLE_SLUG -->`. Sort by
status priority: active-in-progress first, then backlog-ish, using the option order in `roles.active`.

### Step 5 — Auto-enrich newly-done items

For each item now in the `done` role that was `[ ]` in the prior note (i.e. it just completed), run
the **Enrich and Move** flow below (gather context → inspect diff → post comment → move to
`on_complete_move` target). Skip DraftIssues (no issue number). Do **not** skip the Step 2 diff
inspection just because the item already shows "done" — it's still worth reading the change to write
a useful comment, including the Scope note if the issue asked for more than the PR delivered.

### Step 6 — Write + report

Replace the body of the note's `## GitHub Project Tasks` section (between the blockquote hints and
the next `---`/`##`) with the Step 4 list. If the section is missing, insert it after
`## Top Priorities`. Report active/carried/enriched counts and any GraphQL errors. Then run the
**Reconciliation Report** (in `SKILL.md`).

---

## Enrich and Move

Posts a completion-summary comment on an issue and moves its board item to the configured target.
Always gated on user confirmation. For each issue number:

### Step 1 — Gather live context (read fresh)

```bash
gh issue view <N> --repo <owner/repo> --json title,body,comments \
  --jq '{title, body, recent_comments: [.comments[-3:][] | {author: .author.login, createdAt, body}]}'
gh pr list --repo <owner/repo> --search "#<N>" --state all --json number,title,url,state,mergedAt
git -C <repo.local_path> log --all --oneline --grep="#<N>" --since="60 days ago"
```

If both the PR search and the git grep are empty, fall back to the PR/commit named in the **Things
to Know** report (the work landed without an explicit reference) and cite it so the issue gains a
permanent back-link.

### Step 2 — Inspect the change for an honest summary

```bash
gh pr view <PR> --repo <owner/repo> --json title,body,mergedAt,additions,deletions
git -C <repo.local_path> show <commit> -- <key-files>
```

Identify **what shipped** (concrete — files, identifiers), any **cost/behavior expectations** from
the PR body, and **scope discrepancies** (did the issue ask for more than the PR delivered?). The
scope note is the most valuable part when it applies — don't omit it to look cleaner.

### Step 3 — Post the comment

```bash
gh issue comment <N> --repo <owner/repo> --body "$(cat <<'EOF'
## Completion Summary (auto-generated)

**Status**: <one-line, e.g. "Shipped via PR #M (merged YYYY-MM-DD).">

### Linked Pull Requests
- [PR #M — title](url) — merged YYYY-MM-DD
(or "None directly referencing this issue. Implementing PR identified by feature/title match: PR #M.")

### Related Commits
- `abc1234` commit subject
(or "None found via grep — PR commits listed above.")

### What shipped
- <concrete bullet: file/component, what changed>
- <test count if known>

### Cost / behavior expectations  *(optional — include if the PR body or change implies it)*
- <e.g. ~$X/month for component, a new alert/budget, a performance number from the PR body>

### Recent Discussion  *(optional — include if the issue already had comments)*
> Summary of the last ~3 comments (from Step 1's recent_comments) so the close has context.

### Scope note  *(optional — only if the issue asked for more than the PR delivered)*
The issue asked for X; the PR delivered only Y. <Recommendation: keep open with follow-up / file new issue / close.>

---
*Auto-generated by the daily-notes skill on YYYY-MM-DD.*
EOF
)"
```

Omit any optional section entirely when it has nothing to say — don't emit an empty heading. Tone:
factual, not promotional. Cite files and identifiers a future reader can navigate to. You already
gathered the data for Related Commits (Step 1 grep), Cost/behavior (Step 2 PR body), and Recent
Discussion (Step 1 recent_comments) — don't discard it.

### Step 4 — Move the board item

Resolve the move target from `config.github_project.on_complete_move`
(`review_target` → `roles.review_target.id`; `done` → `roles.done.id`; `none` → skip the move). If
the target is `review_target` but it's null, fall back to `done`. Then:

```bash
gh api graphql -f query='
mutation($project: ID!, $item: ID!, $field: ID!, $option: String!) {
  updateProjectV2ItemFieldValue(input: {
    projectId: $project, itemId: $item, fieldId: $field,
    value: { singleSelectOptionId: $option }
  }) { projectV2Item { id } }
}' -f project="<config.github_project.id>" -f item="<ITEM_ID>" \
   -f field="<config.github_project.status_field.id>" -f option="<TARGET_OPTION_ID>"
```

`ITEM_ID` is the project item id from the Sync query (re-fetch if not cached). Report the comment
URL, the new status, and whether a scope note was included. Surface any failure with the issue
number and exact error — never swallow it.

---

## Ensure a review option (setup helper)

Used by `/daily-notes setup` when a user wants the review-column flow on a board that lacks one
(notably a freshly created project, which only has Todo/In Progress/Done). GitHub has no
"append one option" mutation — `updateProjectV2Field` **replaces** the whole option list, rewriting
options by name with no per-option id, so it **regenerates every option ID**. On a board that
already has items, that unsets the Status of every assigned item (their stored option IDs no longer
exist) — not merely "drops an option." **Run this only on a board with no items yet** (e.g. a
freshly created project). Read the current options, append the new one, write them all back, then
verify.

```bash
# 1. Read current options of the status field (from gh project field-list JSON).
gh project field-list <number> --owner <owner> --format json \
  --jq '.fields[] | select(.id=="<status_field.id>") | .options'

# 2. Write back all existing options PLUS "In review". colors/descriptions are required by the API.
gh api graphql -f query='
mutation($field: ID!) {
  updateProjectV2Field(input: {
    fieldId: $field,
    singleSelectOptions: [
      { name: "Todo",        color: GRAY,   description: "" },
      { name: "In Progress", color: YELLOW, description: "" },
      { name: "In review",   color: BLUE,   description: "" },
      { name: "Done",        color: GREEN,  description: "" }
    ]
  }) { projectV2Field { ... on ProjectV2SingleSelectField { id options { id name } } } }
}' -f field="<status_field.id>"
```

Build the `singleSelectOptions` array dynamically from the options you read in step 1 (preserving
their names) plus the new `In review`. After the mutation, re-run `field-list` and confirm every
prior option still exists and now `In review` is present, then capture the refreshed option IDs into
`config.github_project.status_field.roles`. If the mutation errors (permissions, schema), do not
retry blindly — fall back to: tell the user to add an "In review" column in the Projects UI and
re-run setup, or leave `review_target` null and set `on_complete_move` to `done`.
