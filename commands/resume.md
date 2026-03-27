---
description: "Resume a suspended task with full context restoration. Reads the plan and context dump, then continues where you left off. Usage: /resume [JIRA-KEY]"
allowed_tools: Read, Glob, Grep, Bash
---

# Resume Command

Resume a previously suspended task by loading the plan and context dump, then continuing work from where it was left off.

---

## Step 1: Identify the Task

### 1.1 Determine Jira Key

Check sources in order:

1. **Argument provided** — if `$ARGUMENTS` is a valid Jira key (`[A-Z]+-\d+`), use it directly as `$JIRA_KEY`
2. **`.jira-context` file** — if already in a worktree, read `$REPO_ROOT/.jira-context` for the `key` field
3. **Branch name** — extract from pattern `(feature|bug)/([A-Z]+-\d+)`
4. **List available tasks** — run `task-ctl list` and show the user what's available to resume

### 1.2 Get Task Details

```bash
task-ctl show "$JIRA_KEY"
```

Extract:
- `$WORKTREE_PATH` — where the code lives
- `$PLAN_PATH` — path to the plan file
- `$STATUS` — should be "suspended" or "active"
- Context dump availability

**If task-ctl is not installed:** Fall back to reading files directly from the current directory.

**If task is not found:** Inform the user. If already in a worktree, proceed with file-based resume (read plan + context dump from disk).

---

## Step 2: Load Context

### 2.1 Read the Plan File

If `$PLAN_PATH` exists (or check `plans/$JIRA_KEY.md` by convention):

Use `Read` to load the plan. Identify:
- Checked items (completed work)
- Unchecked items (remaining work)
- Open questions
- Guardrails

### 2.2 Read the Context Dump

Check for `.context-dump.md` in the worktree root:

Use `Read` to load `$WORKTREE_PATH/.context-dump.md` (or `$REPO_ROOT/.context-dump.md` if already in the worktree).

Extract:
- Status at suspend (what was actively being worked on)
- Completed items
- Remaining items
- Key decisions
- Modified files
- Blockers

### 2.3 Check Git State

```bash
git status --porcelain
git log --oneline -5
git diff --stat
```

Understand what's on disk vs what the context dump says.

---

## Step 3: Mark Task Active

If task-ctl is available and the task was suspended:

```bash
task-ctl resume "$JIRA_KEY"
```

**Note:** If already in the worktree's tmux window (e.g., user manually opened it), task-ctl resume may fail because the task is already active. This is fine — proceed with context restoration.

---

## Step 4: Present Resumption Summary

Synthesize the plan and context dump into a clear status report:

```
Resuming: $JIRA_KEY — $JIRA_SUMMARY

Last active: <timestamp from context dump>

What was in progress:
  <status at suspend>

Completed so far:
  - <item 1>
  - <item 2>

Remaining work:
  - <item 1>
  - <item 2>

Key decisions from last session:
  - <decision 1>

Blockers: <blockers or "None">

Current git state: X dirty files, Y ahead, Z behind

Ready to continue. What would you like to pick up first?
```

If there are blockers, highlight them prominently and ask if they've been resolved.

If the context dump is missing (crash recovery scenario), say so clearly:

```
No context dump found — this task may have been interrupted without a graceful suspend.

Reading the plan at plans/$JIRA_KEY.md for context...

<plan summary with checked/unchecked items>

What was the last thing you were working on?
```

---

## Error Handling

- **No Jira key and not in a worktree:** List available tasks via `task-ctl list`
- **Task not found in task-ctl:** Try file-based resume from current directory
- **Plan file missing:** Inform user, ask for context
- **Context dump missing:** Normal for crash recovery — proceed with plan only
- **Worktree doesn't exist:** Inform user the worktree was deleted, show context dump from DB if available via `task-ctl show`
