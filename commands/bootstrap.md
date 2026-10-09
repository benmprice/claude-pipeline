# Bootstrap Claude Multi-Agent Pipeline

One-shot setup for the Claude Code multi-agent pipeline in the current project.
Run from the project root. Safe to re-run — existing files are merged, not overwritten.

---

## Step 1 — Pre-flight

```bash
git rev-parse --git-dir 2>/dev/null
```
If this fails: stop and say "Not a git repository. Run `git init` first or cd into your project root."

```bash
git remote -v 2>/dev/null | head -5
```
Detect backend:
- URL contains `github.com` → **GitHub mode**
- URL contains any other hostname → **Gitea mode** — extract base URL (with port) and owner/repo from the remote path
- No output → **Local mode**

Announce: `"Detected: [GitHub | Gitea at hostname | Local (no remote)]"`

---

## Step 2 — Inspect the project

Run all of these:

```bash
# Detect language/runtime
ls package.json pyproject.toml Cargo.toml go.mod pom.xml *.csproj 2>/dev/null

# Detect test and lint commands
cat package.json 2>/dev/null | python3 -I -c "
import sys, json
d = json.load(sys.stdin)
s = d.get('scripts', {})
print('test:', s.get('test', ''))
print('lint:', s.get('lint', ''))
" 2>/dev/null

grep -E "^(test|lint|check):" Makefile 2>/dev/null | head -5

# Find source directory
ls -d src/ lib/ app/ tests/ test/ spec/ __tests__/ 2>/dev/null

# Read existing CLAUDE.md if present
cat CLAUDE.md 2>/dev/null && echo "[[CLAUDE.MD EXISTS]]"
```

Determine:
- **Language**: node / python / rust / go / java / dotnet / unknown
- **Test command**: best guess (e.g. `npm test`, `pytest`, `cargo test ./...`) — or `# TODO: add test command`
- **Lint command**: best guess — or `# TODO: add lint command`
- **Src dir**: first match from ls above, or `.`
- **CLAUDE.md**: exists or not

---

## Step 3 — Check existing agent/command files

```bash
ls .claude/agents/planner.md .claude/agents/implementer.md .claude/agents/reviewer.md \
   .claude/commands/spec.md .claude/commands/build.md 2>/dev/null
```

If any exist: list them and ask "Overwrite, skip, or review each?" before proceeding.
Default: skip existing files unless the user says overwrite.

---

## Step 4 — Write agent files

Create `.claude/agents/` if it doesn't exist.

### `.claude/agents/planner.md`
```
---
name: planner
description: Analyzes issues and the codebase to produce a structured implementation plan. Use first on any new issue or feature.
tools: Read, Grep, Glob, Bash
model: haiku
effort: high
permissionMode: plan
color: blue
---

You are a senior software architect. You read and plan — you never implement.

Given an issue or task:
1. Read the issue or spec carefully
2. Explore the codebase — find the relevant files, understand patterns and conventions
3. Return a structured plan

Your output must include:
- **Summary**: One paragraph on what needs to be built and why
- **Files to modify**: Exact paths with a one-line description of each change
- **New files**: Any new files to create, with their purpose
- **Implementation steps**: Ordered steps an engineer could follow without guessing
- **Tests to write**: Specific test cases — not "add tests", name the actual scenarios
- **Risks**: What could go wrong; what not to touch

Name actual file paths and line numbers wherever possible.
Never write code. When done, hand your plan to the implementer.
```

### `.claude/agents/implementer.md`
```
---
name: implementer
description: Implements features and bug fixes from a plan. Runs in an isolated git worktree. Use after planner returns a plan.
tools: Read, Edit, Write, Bash, Grep, Glob
model: sonnet
effort: medium
permissionMode: acceptEdits
isolation: worktree
color: green
---

You are a senior engineer. You implement — you do not design or improvise.

You will receive a plan from the planner. Follow it.

Rules:
- Match existing code style exactly: indentation, naming, patterns, file structure
- Write the specific tests the plan named
- Commit with conventional commits: feat:, fix:, test:, refactor:
- Before finishing, run: [TEST_COMMAND]
- Before finishing, run: [LINT_COMMAND]
- If the plan is ambiguous or you hit something unexpected, stop and report it — do not make decisions the planner should have made

When done, report:
- Commit hash
- What you built (brief)
- Any deviations from the plan and the reason
- Test and lint results
```

### `.claude/agents/reviewer.md`
```
---
name: reviewer
description: Reviews code changes for correctness, quality, and test coverage. Runs tests and issues a verdict. Use after implementer completes work.
tools: Read, Bash, Grep, Glob
model: sonnet
effort: high
color: orange
---

You are a skeptical senior engineer. Your job is to catch what got missed, not to be harsh.

Steps:
1. Run `git diff main` (or the base branch) — read every line
2. Read every modified and new file in full
3. Run the test suite: [TEST_COMMAND]
4. Run the linter: [LINT_COMMAND]

Issue exactly ONE verdict:

**✅ APPROVE**
Code is correct, tests pass, nothing worth blocking. List minor nits as optional suggestions.

**⚠️ REQUEST CHANGES**
Something needs fixing before merge. For each issue: what's wrong, why it matters, what the fix is. Be specific — "this looks off" is not feedback.

**🚫 BLOCK**
A serious problem: security issue, data loss risk, broken interface contract, fundamentally wrong approach. Explain clearly. This stops the pipeline.

Do not soften verdicts. A wrong APPROVE is worse than a false REQUEST CHANGES.
```

Substitute `[TEST_COMMAND]` and `[LINT_COMMAND]` with detected values from Step 2.
If a command wasn't detected, use `# TODO: add your test/lint command`.

---

## Step 5 — Write command files

Create `.claude/commands/` if it doesn't exist.
Write the backend-appropriate variant of each command.

### `.claude/commands/spec.md` — GitHub variant
```
Refine issue #$ARGUMENTS into a spec an agent can implement without asking questions.

## Step 1 — Fetch the issue
Run: `gh issue view $ARGUMENTS --json title,body,labels,comments`
Read it carefully. Do not summarize it yet.

## Step 2 — Grill me
Your goal: reach a point where you could hand this issue to an engineer who has
never spoken to us, and they would know exactly what to build, what done looks
like, and what not to touch.

Ask ONE question at a time and wait for my answer before asking the next.
Follow threads — if my answer opens a new gap, chase it before moving on.

You're a senior engineer who has been burned by vague tickets. "Improve",
"better", "clean up", and "simple" are all hiding decisions someone has to make.

Probe as needed (not a checklist — a lens):
- What specifically is broken or missing today?
- What does a user do or see when this is done that they can't now?
- What is explicitly out of scope?
- What breaks if implementation goes slightly wrong?
- What must not change — existing APIs, patterns, files, behavior?
- What assumptions is the issue author making that aren't written down?

Keep asking until you're confident. There is no fixed number of questions.

## Step 3 — Write the spec
Format:
**Problem**: What's actually wrong or missing today
**Acceptance Criteria**: Bulleted, testable, specific — each one a pass/fail
**Out of Scope**: What this explicitly does not cover
**Edge Cases**: Inputs or states that need explicit handling
**Technical Notes**: Files to touch, patterns to follow, things to avoid

Show me the draft. Ask: "Does this capture it? Anything to change?"
Iterate until I confirm it's right. Then:

```bash
gh issue edit $ARGUMENTS --body "[final spec]"
gh issue edit $ARGUMENTS --add-label "agent-ready"
```
```

### `.claude/commands/spec.md` — Gitea variant
```
Refine backlog item $ARGUMENTS into a spec an agent can implement without asking questions.

## Step 1 — Fetch the issue
Detect Gitea config:
- Run: `git remote -v | head -3` to get base URL and owner/repo
- Token: check $GITEA_TOKEN, then ~/.config/gitea/token, then .gitea-token

Run:
```bash
curl -s -H "Authorization: token $GITEA_TOKEN" \
  "[BASE_URL]/api/v1/repos/[OWNER]/[REPO]/issues/$ARGUMENTS"
```
Read the title, body, and labels. Do not summarize yet.

## Step 2 — Grill me
[identical grill section as GitHub variant]

## Step 3 — Write the spec
[identical spec format]

Show me the draft. Iterate until confirmed. Then:
```bash
# Update body
curl -X PATCH "[BASE_URL]/api/v1/repos/[OWNER]/[REPO]/issues/$ARGUMENTS" \
  -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"body": "[final spec]"}'

# Get agent-ready label ID
LABEL_ID=$(curl -s "[BASE_URL]/api/v1/repos/[OWNER]/[REPO]/labels" \
  -H "Authorization: token $GITEA_TOKEN" \
  | python3 -I -c "import sys,json; labels=json.load(sys.stdin); print(next((l['id'] for l in labels if l['name']=='agent-ready'), ''))")

# Apply label
curl -X POST "[BASE_URL]/api/v1/repos/[OWNER]/[REPO]/issues/$ARGUMENTS/labels" \
  -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"labels\": [$LABEL_ID]}"
```
```

### `.claude/commands/spec.md` — Local variant
```
Refine backlog item $ARGUMENTS into a spec an agent can implement without asking questions.

## Step 1 — Find the item
Find BACKLOG.md: `find . -maxdepth 3 -name BACKLOG.md 2>/dev/null | head -1`
Read it. Find the item matching $ARGUMENTS (by ID like #003, or title keyword match).
Read the current title and any existing notes. Do not summarize yet.

## Step 2 — Grill me
[identical grill section]

## Step 3 — Write the spec and update BACKLOG.md
[identical spec format]

Show draft. Iterate until confirmed. Then edit the item's block in BACKLOG.md:
- Replace any placeholder spec with the final spec under the heading
- Add `agent-ready` to its label line if not already present
- Update `<!-- updated: [today] -->` at the top of the file
```

---

### `.claude/commands/build.md` — GitHub variant
```
Run the full AFK pipeline for issue #$ARGUMENTS.

## Pre-flight
```bash
gh issue view $ARGUMENTS --json labels --jq '.labels[].name'
```
If `agent-ready` is not in the label list: stop.
Say: "Issue #$ARGUMENTS is not labeled agent-ready. Run /spec $ARGUMENTS first."

## Step 1 — Plan
Invoke the planner agent with:
- The full issue body (fetch with `gh issue view $ARGUMENTS --json title,body`)
- The instruction to explore the codebase and return a structured plan

## Step 2 — Implement
Pass the planner's output to the implementer agent.
The implementer runs in an isolated worktree (`isolation: worktree`).
Wait for the implementer to report its commit hash and results.

## Step 3 — Review
Pass the implementer's commit hash and work summary to the reviewer agent.
Wait for the reviewer's verdict.

## Step 4 — Act on verdict

**✅ APPROVE**
```bash
gh pr create --fill --title "[issue title]" \
  --body "Closes #$ARGUMENTS\n\n[implementer summary]\n\n**Review**: ✅ Approved"
```
Report the PR URL.

**⚠️ REQUEST CHANGES**
Report the reviewer's feedback clearly. Ask: "Fix and re-run, or handle this manually?"
If fix: pass the feedback back to the implementer, then re-run Step 3.

**🚫 BLOCK**
Report the blocker clearly. Stop the pipeline. Do not create a PR.
Say what needs to be resolved before this can proceed.
```

### `.claude/commands/build.md` — Gitea variant
```
Run the full AFK pipeline for issue #$ARGUMENTS.

## Pre-flight
Detect Gitea config from git remote. Resolve token ($GITEA_TOKEN → ~/.config/gitea/token → .gitea-token).

```bash
curl -s "[BASE_URL]/api/v1/repos/[OWNER]/[REPO]/issues/$ARGUMENTS/labels" \
  -H "Authorization: token $GITEA_TOKEN" \
  | python3 -I -c "import sys,json; labels=json.load(sys.stdin); print([l['name'] for l in labels])"
```
If `agent-ready` not in labels: stop. Say "Run /spec $ARGUMENTS first."

## Step 1 — Fetch issue body
```bash
curl -s "[BASE_URL]/api/v1/repos/[OWNER]/[REPO]/issues/$ARGUMENTS" \
  -H "Authorization: token $GITEA_TOKEN"
```

## Steps 2–4 — Plan, Implement, Review
[identical to GitHub variant — agent invocations are the same]

## Step 4 — Act on verdict

**✅ APPROVE**
```bash
curl -X POST "[BASE_URL]/api/v1/repos/[OWNER]/[REPO]/pulls" \
  -H "Authorization: token $GITEA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "[issue title]",
    "body": "Closes #$ARGUMENTS\n\n[implementer summary]\n\n**Review**: ✅ Approved",
    "head": "[implementer branch]",
    "base": "main"
  }'
```

**⚠️ REQUEST CHANGES** / **🚫 BLOCK**
[identical handling as GitHub variant]
```

### `.claude/commands/build.md` — Local variant
```
Run the full AFK pipeline for backlog item $ARGUMENTS.

## Pre-flight
Find BACKLOG.md. Find item matching $ARGUMENTS.
Check its label line for `agent-ready`. If missing: stop.
Say "Run /spec $ARGUMENTS first to get this item to agent-ready."

## Step 1 — Extract spec
Read the item's full spec block from BACKLOG.md. Pass it to the planner agent.

## Steps 2–4 — Plan, Implement, Review
[identical agent flow — planner → implementer → reviewer]

## Step 4 — Act on verdict

**✅ APPROVE**
Mark the item in-progress in BACKLOG.md, then after merge mark it done:
`/backlog done $ARGUMENTS`
Report the commit hash. (No PR — local repo.)

**⚠️ REQUEST CHANGES** / **🚫 BLOCK**
[identical handling]
```

---

## Step 6 — Write or merge CLAUDE.md

Detect project name: `basename $(git rev-parse --show-toplevel)`.

**If CLAUDE.md does not exist**, create it:

```markdown
# [project-name] — Claude Instructions

## Project Overview
[Detected language] project.
<!-- TODO: add a one-paragraph description of what this project does -->

## Commands

| Command | Purpose |
|---|---|
| `/spec [id]` | Grill an issue into an unambiguous spec. Always run before /build. |
| `/build [id]` | Run the full pipeline: plan → implement → review → PR. agent-ready issues only. |
| `/backlog [instruction]` | Add, move, prioritize, or view backlog items in natural language. |

## Tech Stack
- **Language**: [detected]
- **Test command**: [detected or `# TODO`]
- **Lint command**: [detected or `# TODO`]
- **Source dir**: [detected]

## Agent Pipeline
Three agents run in sequence on every issue:
1. **planner** (haiku) — reads the issue, explores the codebase, writes an implementation plan. Never touches code.
2. **implementer** (sonnet) — builds in an isolated git worktree, commits all work.
3. **reviewer** (sonnet) — runs tests, reads the diff, issues APPROVE / REQUEST CHANGES / BLOCK.

Only run `/build` on items labeled `agent-ready`. Use `/spec` to get there.

## Conventions
<!-- TODO: add project-specific conventions agents must follow -->
<!-- Examples: -->
<!-- - Never modify the public API in src/api/routes.ts without a migration -->
<!-- - All new components go in src/components/, never in pages/ -->
<!-- - Branch names: feat/description or fix/description -->
```

**If CLAUDE.md already exists:**
1. Read it carefully
2. Identify what's already there
3. Add ONLY what's missing: the Commands table and Agent Pipeline section
4. Preserve everything else exactly as written
5. Show the user what you're adding before writing it:
   > "Adding these sections to your existing CLAUDE.md: [Commands table] [Agent Pipeline]. Your existing content is untouched. OK to write?"

---

## Step 7 — Labels and backlog

### GitHub
```bash
for name_color_desc in \
  "agent-ready|0075ca|Spec complete — ready for AFK pipeline" \
  "P1|d73a4a|Priority 1 — critical" \
  "P2|e4e669|Priority 2 — high" \
  "P3|0e8a16|Priority 3 — normal" \
  "P4|bfd4f2|Priority 4 — low"; do
  IFS="|" read name color desc <<< "$name_color_desc"
  gh label create "$name" --color "$color" --description "$desc" 2>/dev/null \
    || echo "  (label '$name' already exists, skipping)"
done
```

### Gitea
```bash
BASE="[detected]"
REPO="[owner/repo]"
for label in \
  '{"name":"agent-ready","color":"#0075ca","description":"Ready for AFK pipeline"}' \
  '{"name":"P1","color":"#d73a4a","description":"Priority 1"}' \
  '{"name":"P2","color":"#e4e669","description":"Priority 2"}' \
  '{"name":"P3","color":"#0e8a16","description":"Priority 3"}' \
  '{"name":"P4","color":"#bfd4f2","description":"Priority 4"}'; do
  curl -s -X POST "$BASE/api/v1/repos/$REPO/labels" \
    -H "Authorization: token $GITEA_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$label" > /dev/null
done
echo "Labels created (Gitea ignores duplicates)"
```

### Local
If `BACKLOG.md` doesn't exist, create it:
```markdown
# [project-name] · Backlog
<!-- format: v1 | updated: [today] -->

---

## Backlog
> Ungrouped work — no milestone assigned yet

## Icebox
> Low priority / no milestone

## Done
```

---

## Step 7a — Ensure global commands

These live in ~/.claude/commands/ and work across all repos. Check each; write if missing, skip if present.

```bash
mkdir -p ~/.claude/commands
ls ~/.claude/commands/backlog.md 2>/dev/null && echo "exists" || echo "missing"
ls ~/.claude/commands/reformat-backlog.md 2>/dev/null && echo "exists" || echo "missing"
```

### `~/.claude/commands/backlog.md` — if missing, write it
[full backlog command content — three-mode auto-detecting version,
 with Seq on label line and quick-capture as default for add]

### `~/.claude/commands/reformat-backlog.md` — if missing, write it
[full reformat-backlog content]

Add to final report:
  ~/.claude/commands/backlog.md          ← [created | already existed, skipped]
  ~/.claude/commands/reformat-backlog.md ← [created | already existed, skipped]

---

## Step 8 — Final report

```
✅ Bootstrap complete

Backend:  [GitHub | Gitea (hostname) | Local]
Language: [detected]

Files written:
  .claude/agents/planner.md
  .claude/agents/implementer.md
  .claude/agents/reviewer.md
  .claude/commands/spec.md       ← [GitHub | Gitea | local] variant
  .claude/commands/build.md      ← [GitHub | Gitea | local] variant
  CLAUDE.md                      ← [created fresh | merged with existing]
  BACKLOG.md                     ← [created | already existed]  (local only)

  ~/.claude/commands/backlog.md          ← [created | already existed, skipped]
  ~/.claude/commands/reformat-backlog.md ← [created | already existed, skipped]

Labels created: agent-ready P1 P2 P3 P4   (GitHub/Gitea only)

TODOs left for you:
  □ Fill in project description in CLAUDE.md
  □ Add project-specific conventions to CLAUDE.md
  [if test/lint not detected] □ Add test and lint commands to agent files

When you're ready:
  /spec [issue id or title]     ← spec out your first issue
  /build [id]                   ← run the pipeline
  /backlog add [idea]           ← capture something quickly
```
