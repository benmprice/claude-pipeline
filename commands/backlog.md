# Backlog Manager

Manage the project backlog regardless of whether this repo uses GitHub Issues,
Gitea Issues, or a local BACKLOG.md file. This command is the only interface
to the backlog — never ask the user to edit markdown directly.

## Step 1 — Detect backend

Run: `git remote -v 2>/dev/null | head -5`

Parse the remote URL:
- Contains `github.com` → **GitHub mode**
- Contains any other hostname → **Gitea mode** — extract base URL and owner/repo
- No remote output → **Local mode**

Announce the detected mode before doing anything else.
Example: `"Detected: Gitea mode (macmini-server.tail62ac67.ts.net / benprice/myapp)"`

## Step 2 — Parse the request

The user's instruction is: $ARGUMENTS

If $ARGUMENTS is empty → run **show** (summary of current backlog state).

Interpret the instruction into one of these operations:
- **add** — create a new backlog item
- **show** — display backlog summary grouped by milestone
- **move** — change sequence position or milestone of an item
- **priority** — change P1/P2/P3/P4 label
- **label** — toggle a label (agent-ready, blocked, in-progress, etc.)
- **done** — close/complete an item
- **promote** — move an item from Icebox or Backlog into a named milestone
- **new-milestone** — scaffold a new milestone

---

## GITHUB MODE

Prerequisite: run `gh auth status` — if it fails, tell the user to run `gh auth login`.

**add**
```bash
gh issue create --title "[title]" --body "[spec]" --label "P[1-4]"
# If milestone provided:
gh issue create ... --milestone "[name]"
```
Quick capture: title is the only required field. Do not prompt for a spec on add.
Confirm: "Added #[number] · [title]. Run /spec [number] to flesh it out."

**show**
```bash
gh issue list --state open --json number,title,labels,milestone \
  | jq 'group_by(.milestone.title)'
```
Format as grouped summary: milestone header, then ID / title / priority / labels per item.

**move** (change milestone)
```bash
gh issue edit [ID] --milestone "[milestone name]"
```

**priority**
```bash
gh issue edit [ID] --remove-label "P1,P2,P3,P4" --add-label "P[new]"
```

**label**
```bash
gh issue edit [ID] --add-label "[label]"
# or: --remove-label "[label]"
```

**done**
```bash
gh issue close [ID] --comment "Completed."
```

**new-milestone**
```bash
gh api repos/:owner/:repo/milestones --method POST \
  --field title="[name]" \
  --field description="Goal: [goal]" \
  --field due_on="[YYYY-MM-DD]T00:00:00Z"
```

---

## GITEA MODE

Extract from remote URL:
- Base URL: `https://[hostname]` (include port if present, e.g. `:8443`)
- Owner/repo: last two path segments (strip `.git`)

Token resolution — check in order:
1. `$GITEA_TOKEN` environment variable
2. `~/.config/gitea/token`
3. `.gitea-token` file in repo root

If none found, stop and tell the user:
> "Add `export GITEA_TOKEN=your_token` to your shell profile, or create
> a `.gitea-token` file in the repo root and add `.gitea-token` to `.gitignore`."

All requests: `curl -s -H "Authorization: token $GITEA_TOKEN" -H "Content-Type: application/json"`

**add**
```bash
# Get label IDs first
curl "[base]/api/v1/repos/[owner]/[repo]/labels"
# Create issue
curl -X POST "[base]/api/v1/repos/[owner]/[repo]/issues" \
  -d '{"title":"[title]","body":"[spec]","labels":[[label_id]]}'
```
Quick capture: title only required. Do not prompt for spec on add.
Confirm: "Added #[number] · [title]. Run /spec [number] to flesh it out."

**show**
```bash
curl "[base]/api/v1/repos/[owner]/[repo]/issues?type=issues&state=open&limit=50"
```
Format grouped by milestone field.

**move** (milestone)
```bash
# Get milestone ID first
curl "[base]/api/v1/repos/[owner]/[repo]/milestones"
# Update issue
curl -X PATCH "[base]/api/v1/repos/[owner]/[repo]/issues/[id]" \
  -d '{"milestone":[milestone_id]}'
```

**priority / label**
```bash
# Remove old label
curl -X DELETE "[base]/api/v1/repos/[owner]/[repo]/issues/[id]/labels/[old_id]"
# Add new label
curl -X POST "[base]/api/v1/repos/[owner]/[repo]/issues/[id]/labels" \
  -d '{"labels":[[new_id]]}'
```

**done**
```bash
curl -X PATCH "[base]/api/v1/repos/[owner]/[repo]/issues/[id]" \
  -d '{"state":"closed"}'
```

**new-milestone**
```bash
curl -X POST "[base]/api/v1/repos/[owner]/[repo]/milestones" \
  -d '{"title":"[name]","description":"Goal: [goal]","due_on":"[YYYY-MM-DD]T00:00:00Z"}'
```

---

## LOCAL MODE

Find `BACKLOG.md`: search upward from CWD (`find . -maxdepth 3 -name BACKLOG.md 2>/dev/null | head -1`).

If not found: "No BACKLOG.md found. Create one? (yes/no)"
If yes, scaffold:
```markdown
# [Project Name] · Backlog
<!-- format: v1 | updated: [today] -->

---

## Backlog
> Ungrouped work — no milestone assigned yet

## Icebox
> Low priority / no milestone

## Done
```

### Format rules (enforce on every write)

Issue heading: `### ID:#NNN · [Title]`
Labels line (immediately after heading): `` `P[1-4]` `Seq:N` `[status]` `[other labels]...` ``
Valid status labels: `todo` `in-progress` `blocked` `someday`
Valid other labels: `agent-ready` and any freeform tag

Full issue block with spec:
```markdown
### ID:#001 · Implement JWT refresh tokens
`P1` `Seq:1` `in-progress` `agent-ready`

**Problem**: ...

**Acceptance Criteria**
- [ ] ...

**Out of Scope**: ...

**Edge Cases**: ...

**Technical Notes**: ...

**Depends on**: none

---
```

Done entry (flat, no spec):
```markdown
- [x] ID:#001 Implement JWT refresh tokens — 2026-10-09
```

### ID assignment
- Scan entire file for all `ID:#NNN` patterns
- Next ID = highest found + 1, zero-padded to 3 digits
- IDs are permanent — never renumber or reuse

### Seq assignment
- Seq is per-section (each milestone and the Backlog/Icebox sections have independent sequences starting at 1)
- When adding or moving items, renumber all Seq values in every affected section

### Operations

**add**
1. Determine next ID
2. If section not specified, ask: milestone name, Backlog, or Icebox
3. If Seq not specified, default to end of section
4. Insert the H3 block — title + label line only (no spec scaffolding unless user provides spec)
5. Renumber Seq in the target section
6. Update `<!-- updated: [today] -->`
7. Confirm: `"Added ID:#NNN · Seq:N in [section]. Run /spec [title] to flesh out the spec."`

**show**
Read BACKLOG.md and print a compact summary — one line per item: `ID:#NNN Seq:N P[1] [labels] [Title]`. Group by section. Don't print specs.

**move**
1. Find item by ID or title match
2. Remove H3 block from source section
3. Insert at target section + Seq position
4. Renumber source and target sections
5. Confirm move

**priority**
Find item, update `P[1-4]` in its label line.

**label**
Add or remove a backtick label from the item's label line. Preserve order: P-label first, Seq second, status third, others after.

**done**
1. Find item by ID
2. Add `- [x] ID:#NNN [Title] — [today]` to Done section
3. Remove the full H3 block from its source section
4. Renumber source section
5. Update `<!-- updated -->` date

**promote**
Move from Icebox or Backlog into a named milestone section at specified Seq (default: end).

**new-milestone**
Prompt for: name, goal, target date (optional).
Scaffold H2 block above the Backlog section:
```markdown
## Milestone M[N] — [Name]
> **Goal**: [goal]
> **Target**: [date or TBD]
> **Status**: planned
```

### Validation (run after every write)
- No duplicate IDs anywhere in the file
- Every `Depends on: ID:#NNN` references an ID that exists in the file
- Seq values in each section are 1..N with no gaps
- Report any violations before confirming success
