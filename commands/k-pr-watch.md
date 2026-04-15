---
description: "Watch a PR for CI failures, review comments, and approvals. Polls and surfaces actionable items interactively. Usage: /k-pr-watch <PR_NUMBER>"
allowed_tools: Read, Glob, Grep, Bash, Edit, Write, AskUserQuestion
---

# /k-pr-watch — PR Watch & Respond

Monitor an open PR for CI status changes, review comments, and approvals. Surfaces actionable items interactively and implements fixes with user approval.

---

## Step 0: Parse Arguments

Extract `$PR_NUMBER` from `$ARGUMENTS` (first positional argument, numeric).

If missing or non-numeric: "Usage: `/k-pr-watch <PR_NUMBER>`" — STOP.

---

## Step 1: Initial PR State

Gather the current state of the PR:

```bash
# PR metadata
gh pr view $PR_NUMBER --json title,body,baseRefName,headRefName,state,reviewDecision,statusCheckRollup,reviews,comments,labels,author

# Repo context
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

Store:
- `$PR_TITLE`, `$HEAD_BRANCH`, `$BASE_BRANCH`, `$AUTHOR`
- `$CI_STATUS` — overall check status (pending/success/failure)
- `$REVIEW_DECISION` — review state (approved/changes_requested/review_required)
- `$EXISTING_COMMENTS` — snapshot of current comments (to detect new ones)
- `$EXISTING_REVIEWS` — snapshot of current reviews

Report the initial state to the user:
```
Watching PR #$PR_NUMBER — $PR_TITLE
CI: $CI_STATUS | Reviews: $REVIEW_DECISION
Polling every 90 seconds. I'll surface anything that needs your attention.
```

---

## Step 2: Poll Loop

Use `/loop` to poll the PR on a self-paced interval. Each iteration:

### 2a: Check CI Status

```bash
gh pr checks $PR_NUMBER --json name,state,conclusion
```

Compare against previous state:
- **New failure:** → Go to Step 3 (CI Diagnosis)
- **All passing (was failing):** → Notify: "CI is green now."
- **Still pending:** → No action
- **Still passing:** → No action

### 2b: Check for New Comments

```bash
gh pr view $PR_NUMBER --json reviews,comments
gh api "repos/$REPO/pulls/$PR_NUMBER/comments" --paginate
```

Compare against previous snapshot:
- **New review comments:** → Go to Step 4 (Review Triage)
- **New general comments:** → Surface them: "New comment from @author: ..."
- **No new comments:** → No action

### 2c: Check Review Decision

```bash
gh pr view $PR_NUMBER --json reviewDecision
```

- **Approved (was not):** → Go to Step 5 (Approval Notification)
- **Changes requested (new):** → Go to Step 4 (Review Triage)
- **No change:** → No action

### 2d: Check PR State

- **Merged:** → Notify "PR #$PR_NUMBER has been merged." — STOP loop.
- **Closed:** → Notify "PR #$PR_NUMBER was closed without merging." — STOP loop.

Update all snapshots for next iteration.

---

## Step 3: CI Diagnosis

When a CI check fails:

1. Identify the failed check(s):
```bash
gh pr checks $PR_NUMBER --json name,state,conclusion,detailsUrl
```

2. Fetch the failure logs:
```bash
# Get the run ID for the failed check
gh run list --branch $HEAD_BRANCH --json databaseId,conclusion,name --limit 5
gh run view $RUN_ID --log-failed 2>&1 | tail -100
```

3. Categorize the failure:
   - **Test regression** from PR changes
   - **Flaky test / environment issue**
   - **Lint or formatting violation**
   - **Build / dependency issue**
   - **Infrastructure / CI config issue**

4. Propose a fix:
```
CI check "$CHECK_NAME" failed.

Category: $CATEGORY
Root cause: $DIAGNOSIS

Proposed fix:
$FIX_DESCRIPTION

Apply this fix? [y/n]
```

5. Wait for user response:
   - **Yes:** Implement the fix, commit with message `fix(ci): $description`, push.
   - **No:** Acknowledge, continue watching.

### Auto-Fix Patterns (placeholder)

The following patterns are approved for automatic fix without asking. This list is currently empty — all fixes require user approval.

```yaml
auto_fix_patterns: []
# Future examples:
# - pattern: "gofmt"
#   action: "Run gofmt -w on affected files"
# - pattern: "eslint"
#   action: "Run npx eslint --fix on affected files"
# - pattern: "go vet"
#   action: "Fix go vet findings"
```

When an auto-fix pattern matches, apply the fix, commit, push, and notify the user what was done.

---

## Step 4: Review Triage

When new review comments arrive:

1. Fetch all comments:
```bash
gh pr view $PR_NUMBER --json reviews,comments
gh api "repos/$REPO/pulls/$PR_NUMBER/comments" --paginate
```

2. Filter:
   - Remove bot comments (Copilot, github-actions, dependabot) — BUT keep them visible (do not silently drop). List them separately: "Bot feedback: ..."
   - Remove dismissed reviews
   - Remove comments already seen in previous snapshot

3. Group remaining feedback by file, then by reviewer.

4. For each actionable comment, present interactively:
```
Review feedback from @$REVIEWER
File: $FILE_PATH:$LINE
---
$COMMENT_BODY
---
Code context:
$CODE_SNIPPET

How should I address this? (Options: fix it, skip, reply, discuss)
```

5. Wait for user response before proceeding to the next comment:
   - **fix it:** Implement the change, show the diff, confirm before committing
   - **skip:** Move to next comment
   - **reply:** Ask user what to reply, post it via `gh api`
   - **discuss:** Open discussion — user explains their thinking, help craft a response

6. After all comments are addressed, ask:
```
All review feedback addressed. Push changes? [y/n]
```

If yes, commit with descriptive message and push.

---

## Step 5: Approval Notification

When the PR is approved:

```
PR #$PR_NUMBER approved by @$APPROVER.
CI: $CI_STATUS
Ready to merge: $MERGE_READY

Note: Auto-merge is disabled. Merge manually when ready.
```

Continue watching unless the user says to stop.

---

## Polling Behavior

- Self-pace the loop interval based on activity:
  - **Active (CI running, recent comments):** Poll every 60-90 seconds
  - **Quiet (CI passed, no new comments):** Poll every 3-5 minutes
  - **Very quiet (>30 min no changes):** Poll every 10 minutes
- On any state change, report immediately and reset to active polling
- User can stop the watch at any time

---

## Error Handling

- If `gh` commands fail (auth, rate limit), report the error and suggest re-auth
- If the PR is not found (deleted, wrong repo), stop with clear error
- If the branch has diverged (force push detected), warn and refresh state
