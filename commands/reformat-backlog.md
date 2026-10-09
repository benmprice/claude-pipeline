# Reformat Backlog

Normalize any existing backlog file into the canonical BACKLOG.md format.
Safe to run on messy, partially-formatted, or imported backlogs.
Preserves all content — only restructures and normalizes.

Usage:
  /reformat-backlog                  ← searches for BACKLOG.md in current tree
  /reformat-backlog path/to/file.md  ← use a specific file, any name

## Step 1 — Find the file

If $ARGUMENTS is a file path, use it directly.
Otherwise search: `find . -maxdepth 3 \( -name "BACKLOG.md" -o -name "backlog.md" -o -name "TODO.md" \) 2>/dev/null`
If multiple found, list them and ask which one.
If none found, ask: "What's the filename or path?"

Read the entire file.

## Step 2 — Analyze and report

Before touching anything, identify:
- How many items exist
- Which already have `ID:#NNN` format
- What section/status structure exists (headings, checkboxes, kanban columns, etc.)
- Priority markers (P1/High/Critical/etc. or none)
- Items with full specs vs. bare titles

Report: `"Found [N] items: [N] with IDs, [N] with specs. Sections: [list]"`
Ask: `"Ready to reformat? Content is preserved — only structure changes."`

## Step 3 — Assign missing IDs

Find the highest existing `ID:#NNN` in the file. Next = highest + 1, zero-padded to 3 digits.
Items that already have IDs keep them exactly — never renumber or reuse.

## Step 4 — Map sections to canonical structure

| Existing section name | Maps to |
|---|---|
| In Progress / Doing / Active / Current | Backlog with `in-progress` label |
| To Do / Todo / Next / Queue / Backlog | Backlog |
| Someday / Maybe / Ideas / Future / Wishlist | Icebox |
| Done / Completed / Closed / Merged | Done (flat list) |
| Named milestone / sprint / epic / feature group | Milestone section (preserve name) |

If any mapping is ambiguous, ask before proceeding.

## Step 5 — Normalize priority

| Existing | Canonical |
|---|---|
| Critical / Urgent / P0 / Blocker | P1 |
| High / Important | P1 |
| Medium / Normal | P2 |
| Low / Minor | P3 |
| Nice-to-have / Someday | P4 |
| None found | P3 for Backlog items, P4 for Icebox |

## Step 6 — Build canonical output

File header (add if missing):
```markdown
# [project-name] · Backlog
<!-- format: v1 | updated: [today] | reformatted-from: [original filename] -->
```

Section order: Milestone sections (if any) → Backlog → Icebox → Done

For each open item:
```markdown
### ID:#NNN · [Title]
`P[1-4]` `Seq:N` `[status]` `[other labels if any]`

[existing spec content preserved exactly — or empty if none was there]

---
```

Seq is assigned per-section starting at 1, preserving original item order within each section.

For Done items (flat, no spec):
```markdown
- [x] ID:#NNN [Title] — [date if found in original, otherwise omit]
```

## Step 7 — Confirm destination and write

Show a pre-write summary:
```
Ready to write:
  [N] items → Backlog, [N] → Icebox, [N] → Done, [N] milestones
  New IDs assigned: #NNN, #NNN, ...  (existing IDs unchanged)
  Source: [original path]
```

If the source file is not named `BACKLOG.md`, ask:
`"Save as BACKLOG.md in the same folder, overwrite the original, or specify a different path?"`

- **Save as BACKLOG.md**: Write canonical content to `BACKLOG.md` in the same directory. Leave the original file untouched. Report: `"✅ Written to BACKLOG.md. Original [filename] left in place — delete it when you're satisfied."`
- **Overwrite original**: Write canonical content back to the source file. Report: `"✅ [filename] reformatted in place."`
- **Specify path**: Write to the path they provide.

If the source is already named `BACKLOG.md`, ask: `"Overwrite in place? (yes / no)"`

Never delete any file automatically.
