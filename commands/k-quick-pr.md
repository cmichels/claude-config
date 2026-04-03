---
description: "Fast PR review for routine/boilerplate PRs. Usage: /k-quick-pr <PR_NUMBER>. Single-pass checklist, approves or requests changes with inline comments. No agents, no ceremony."
allowed_tools: Read, Glob, Grep, Bash, AskUserQuestion
---

# /k-quick-pr — Fast PR Review

Single-pass review for routine PRs (image tag bumps, config restructuring, boilerplate migrations). Prioritizes speed over depth. Reviews locally, posts result to GitHub.

---

## Step 0: Parse Arguments

Extract `$PR_NUMBER` from `$ARGUMENTS` (first positional argument, numeric).

If missing or non-numeric: "Usage: `/k-quick-pr <PR_NUMBER>`" — STOP.

---

## Step 1: Save State & Checkout

Record current state and switch to the PR branch:

```bash
ORIGINAL_BRANCH=$(git branch --show-current)
```

Check if the working tree is dirty:
```bash
git status --porcelain
```

If dirty, stash:
```bash
git stash --include-untracked -m "k-quick-pr: auto-stash before reviewing PR #$PR_NUMBER"
```

Store `$ORIGINAL_BRANCH` and `$STASHED` (true/false).

Fetch and checkout the PR branch:
```bash
gh pr checkout $PR_NUMBER
```

---

## Step 2: Gather Context

Run these in parallel:

```bash
# PR metadata
gh pr view $PR_NUMBER --json title,body,baseRefName,headRefName,files,additions,deletions,changedFiles

# Diff against base
gh pr diff $PR_NUMBER

# Existing reviews and inline comments
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
gh api "repos/$REPO/pulls/$PR_NUMBER/comments" --paginate
```

Store:
- `$PR_TITLE`, `$PR_BODY`, `$BASE_BRANCH`, `$HEAD_BRANCH`
- `$FILES[]` — changed files with change types
- `$DIFF` — the full diff
- `$ADDITIONS`, `$DELETIONS`, `$CHANGED_FILES`
- `$EXISTING_COMMENTS[]` — inline review comments already posted (path, line, body)

### Complexity Gate

If the PR exceeds any of these thresholds, it's too complex for a quick review:
- More than 20 changed files
- More than 500 additions
- Touches CI/CD workflows AND application code in the same PR

If tripped: inform the user this PR needs `/review-pr-team` instead. Restore state (Step 5) and STOP.

---

## Step 3: Fast Checklist

Single pass over the diff. Check ONLY these items:

### Hard Blocks → REQUEST_CHANGES
1. **Secrets/credentials** — API keys, passwords, tokens, private keys, `.env` values
2. **Syntax errors** — malformed YAML, JSON, or shell that will fail at runtime
3. **Scope violation** — files changed that don't belong in this PR
4. **Destructive deletions** — entire files or large blocks removed without explanation in the PR body
5. **Wrong values** — image tags pointing to wrong registries, typos in service names, broken references

### Soft Flags → note in approval body, don't block
1. **Missing PR description** — changes are fine but PR body is empty/unhelpful
2. **Inconsistency** — pattern differs between files that should be identical
3. **Stale comments/TODOs** — leftover markers

### Ignore — do NOT check
- Code style, formatting, naming
- Test coverage
- Architecture, design patterns
- Performance
- Documentation

For each finding, record:
- `$FINDING.file` — file path
- `$FINDING.line` — line number in the **file** (not the diff)
- `$FINDING.body` — one-sentence description
- `$FINDING.blocking` — true/false

**Speed rule:** For a 1-file tag bump, the diff alone is sufficient context. Don't read surrounding files unless the diff is ambiguous. Read the minimum needed.

### Dedup Against Existing Comments

Before finalizing findings, compare each one against `$EXISTING_COMMENTS[]`:

- **Same file + line within 3 lines + same issue:** Drop the finding. It's already been said.
- **Same file + same issue but different line:** Drop it. The reviewer covered it.
- **Same general concern but different file:** Keep it — each file gets its own comment.

If a finding is dropped, do not mention it in the review body or as an inline comment. It doesn't exist as far as your review is concerned.

If ALL findings (blocking and soft) are already covered by existing comments, post a clean APPROVE with a summary only — no redundant notes.

---

## Step 4: Post Review

### Determine repo identity

```bash
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

### If no blocking findings → APPROVE

Write a review body (no boilerplate headers, no "automated" or "quick" language — write like a human reviewer):

```
<1-2 sentence summary of what the PR does based on the diff>

<if soft flags exist>
Notes:
- <flag 1>
- <flag 2>
</if>
```

Post:
```bash
gh pr review $PR_NUMBER --approve --body "$REVIEW_BODY"
```

### If blocking findings → REQUEST_CHANGES with inline comments

Build a JSON payload with inline comments. Write to a temp file to avoid shell escaping issues:

```bash
cat > /tmp/pr-review-$PR_NUMBER.json << 'REVIEW_EOF'
{
  "event": "REQUEST_CHANGES",
  "body": "<summary — same format as approve but listing the issues>",
  "comments": [
    {
      "path": "<file path>",
      "line": <line number>,
      "body": "<issue description>"
    }
  ]
}
REVIEW_EOF

gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" \
  --method POST \
  --input /tmp/pr-review-$PR_NUMBER.json

rm -f /tmp/pr-review-$PR_NUMBER.json
```

The summary body should list the issues plainly:
```
<1-2 sentence summary of PR intent>

Issues:
- path/to/file:L — description
```

**Never mention** "automated", "quick", "fast", "checklist", or "routine" in the review. Write as a normal reviewer would.

---

## Step 5: Restore State

Always run this, even on errors:

```bash
git checkout $ORIGINAL_BRANCH
```

If `$STASHED` is true:
```bash
git stash pop
```

If stash pop conflicts, inform the user their stash is saved as `k-quick-pr: auto-stash before reviewing PR #$PR_NUMBER` and they can resolve manually.

---

## Step 6: Report

Brief conversation summary:

**Approved:**
```
✅ PR #$PR_NUMBER — $PR_TITLE
   Approved. <what it does in one line>
```

**Changes requested:**
```
❌ PR #$PR_NUMBER — $PR_TITLE
   Requested changes:
   - <issue 1>
   - <issue 2>
```

**Redirected to /review-pr-team:**
```
⚠️  PR #$PR_NUMBER — $PR_TITLE
    Too complex for quick review (<reason>). Use /review-pr-team.
```

---

## Error Handling

- **PR not found:** Inform user, restore state. STOP.
- **Checkout fails:** Inform user, pop stash if needed. STOP.
- **Review post fails via `gh pr review`:** Fall back to `gh api`. If both fail, print the review in the conversation for manual posting.
- **Stash pop conflicts:** Inform user with the stash name so they can resolve.

## Rules

- Speed is everything. A 1-line tag bump should take under 30 seconds of analysis.
- Read the minimum context needed. If the diff tells the whole story, don't read files.
- Never expand scope. If something looks interesting but isn't on the checklist, ignore it.
- The review body should read like a human wrote it. Short, direct, no filler.
