---
description: "Suspend the current task with a context dump for later resumption. Generates a summary of work state, writes .context-dump.md, and calls task-ctl suspend. Usage: /k-suspend"
allowed_tools: Read, Glob, Grep, Bash, Write
---

# Suspend Command

Gracefully suspend the current task by generating a context dump and calling task-ctl to track the suspension. This preserves work state so the task can be resumed in a new session with full context.

---

## Step 1: Detect Current Task Context

### 1.1 Find Task Key

Try these sources in order:
1. **`.jira-context` file** in the repo root — parse JSON for `key` field
2. **`.task-context` file** in the repo root — parse JSON for `name` field (non-Jira projects)
3. **Branch name** — extract from pattern `(feature|bug)/([A-Z]+-\d+)`
4. **Ask the user** — if no source works, use output text to ask for the task key

```bash
git rev-parse --show-toplevel
```

Store as `$REPO_ROOT`.

Check for `.jira-context`:
- Use `Read` to read `$REPO_ROOT/.jira-context`
- Parse JSON to extract `$TASK_KEY` from `key` field

If not found, check for `.task-context`:
- Use `Read` to read `$REPO_ROOT/.task-context`
- Parse JSON to extract `$TASK_KEY` from `name` field

If neither found, parse branch:
```bash
git branch --show-current
```

Extract `$TASK_KEY` from branch name pattern.

### 1.2 Verify Task is Registered

```bash
task-ctl show "$TASK_KEY"
```

**If task-ctl is not installed:** Warn the user but continue — the context dump file is still valuable on its own.

**If task is not registered:** Warn the user. Offer to register it:
```bash
task-ctl register \
  --jira "$TASK_KEY" \
  --repo "$(git remote get-url origin | sed 's/.*github.com[:/]\(.*\)\.git/\1/')" \
  --branch "$(git branch --show-current)" \
  --worktree "$REPO_ROOT"
```

### 1.3 Gather Current State

Collect information needed for the context dump:

```bash
git status --porcelain
git diff --name-only HEAD
git diff --cached --name-only
```

Also check for a plan file:
- Use `Glob` to find `$REPO_ROOT/plans/$TASK_KEY.md`

If found, use `Read` to read the plan and identify:
- Which items are checked (completed)
- Which items are unchecked (remaining)

---

## Step 2: Generate Context Dump

This is the critical step. You (Claude) must self-reflect on the current conversation and work state to produce an accurate summary.

### 2.1 Analyze Current State

Review:
1. **What was actively being worked on** — the current task or subtask in progress
2. **What's completed** — cross-reference with the plan file checkboxes and your conversation history
3. **What's remaining** — unchecked plan items plus any discovered work not in the plan
4. **Key decisions made** — any non-obvious choices, tradeoffs, or architectural decisions during this session
5. **Modified files** — from git diff
6. **Blockers** — anything that was blocking progress or needs external input

### 2.2 Write Context Dump

Use the **Write tool** (NOT Bash heredoc) to create `$REPO_ROOT/.context-dump.md`:

```markdown
# Context Dump: $TASK_KEY
## Generated: <current ISO 8601 timestamp>
## Plan: plans/$TASK_KEY.md

## Status at Suspend
<1-2 sentences: what was actively being worked on when suspend was called>

## Completed
- <bulleted list of done items, derived from plan checkboxes and conversation>

## Remaining
- <bulleted list of remaining work, with brief notes on approach if relevant>

## Key Decisions
- <non-obvious decisions made during this session, with rationale>
- <if none, write "None — straightforward implementation">

## Modified Files
<list of files from git diff --name-only, one per line>

## Blockers
- <anything blocking progress, or "None">
```

**Guidelines for generating the context dump:**
- Be specific and actionable — a new Claude session will read this cold
- Reference actual file paths and function names
- For key decisions, include the "why" not just the "what"
- For remaining items, include enough context that someone can pick up without re-reading the whole plan
- Don't pad — if there are no blockers, say "None"
- Keep it concise but complete — aim for 20-50 lines

---

## Step 3: Call task-ctl suspend

```bash
task-ctl suspend "$TASK_KEY" --context-file "$REPO_ROOT/.context-dump.md"
```

This will:
1. Capture git state (dirty count, ahead/behind)
2. Read the context dump file and store it in the DB
3. Mark the task as "suspended" with a timestamp
4. Close the tmux window for this task (if in tmux)

**If task-ctl is not installed:** Skip this step. The `.context-dump.md` file is still on disk and can be read manually on resume.

**If suspend fails:** Show the error. The context dump file still exists — the user can manually resume later.

---

## Step 4: Confirmation Output

Display the suspension summary:

```
Task Suspended: $TASK_KEY

Context dump:  $REPO_ROOT/.context-dump.md
Plan:          $REPO_ROOT/plans/$TASK_KEY.md (if exists)
Git state:     X dirty, Y ahead, Z behind
Status:        suspended

To resume later:
  task-ctl resume $TASK_KEY

Or from pr-monitor: select task and press Enter
```

---

## Error Handling

- **No .jira-context/.task-context and can't parse branch:** Ask user for the task key
- **task-ctl not installed:** Generate context dump anyway, warn about manual tracking
- **Not in a git repo:** STOP — nothing to suspend
- **Task not registered:** Offer to register, then suspend
- **Context dump write fails:** Report error, still attempt task-ctl suspend without --context-file
