---
description: "Quick sanity-check review of uncommitted or branch changes. Usage: /diff-review [base_branch]. Fast single-pass review — no agents, no reports, just tell me what's wrong."
allowed_tools: Bash, Read, Glob, Grep
---

# /diff-review — Quick Diff Sanity Check

Fast, single-pass review of current changes. No agents, no file output, no ceremony. Just read the diff and call out anything worth fixing before it gets committed.

**Base**: `$ARGUMENTS` (defaults to staged + unstaged changes if empty; if a branch name is provided, review all changes since diverging from that branch).

## Step 1: Get the Diff

**If `$ARGUMENTS` is empty:** Review working tree changes (staged + unstaged):
```bash
git diff HEAD
```

If that's empty, check for staged-only changes:
```bash
git diff --cached
```

If both are empty: "Nothing to review. Working tree is clean." STOP.

**If `$ARGUMENTS` is a branch name:** Review all changes on the current branch since diverging:
```bash
git diff $ARGUMENTS...HEAD
```

Also grab the file list for context:
```bash
git diff --stat $ARGUMENTS...HEAD
```

Store the diff as `$DIFF` and the changed file list as `$FILES`.

## Step 2: Read Changed Files

For each file in `$FILES` that is not deleted and not binary:
- Read the full current content using the Read tool
- This provides surrounding context that the diff alone may lack

Skip files over 500 lines — for those, rely on the diff only.

Cap at 15 files. If more than 15 files changed, note it and focus on the largest diffs first.

## Step 3: Review

Do a single pass over the diff and file contents. Look for — and ONLY for — things that actually matter:

### Blocking (would flag in a real PR review)
- Logic errors, off-by-one, wrong conditions
- Unhandled errors that will bite at runtime
- Security issues (injection, auth bypass, data exposure)
- Race conditions or concurrency bugs
- Resource leaks (unclosed connections, files, channels)
- Breaking API changes without migration

### Worth Mentioning (non-blocking but worth knowing)
- Dead code or unreachable branches introduced
- Inconsistency with patterns used elsewhere in the same file
- Missing nil/null/zero-value checks at boundaries
- Test gaps for new logic paths
- TODO/FIXME/HACK comments added without context

### Ignore (do NOT waste time on)
- Style, formatting, naming conventions — the linters handle that
- Missing comments or docs on internal code
- Import ordering
- "Could be cleaner" refactoring opinions
- Anything that was already there before these changes

## Step 4: Output

Respond directly in the conversation. No file output. No markdown report. Just talk.

**If nothing found:** "Diff looks clean. Ship it."

**If findings exist:** Group by file path. For each finding:
- File and line reference
- What the issue is (one sentence)
- What to do about it (one sentence)

Lead with blocking issues. Then non-blocking. Keep it tight.

**End with a one-line verdict:**
- "Clean — good to commit."
- "Minor stuff — commit if you want, or fix first."
- "Fix the blocking issues before committing."

## Rules

- This is a conversation, not a document. Write like you're pair programming.
- Be direct. "This will NPE" not "Consider adding a nil check to improve robustness."
- Don't pad with positives. If it's all good, say so and stop.
- Total response should be under 50 lines unless there are genuinely many issues.
- Never suggest running the full review pipeline — the user chose /diff-review for a reason.
