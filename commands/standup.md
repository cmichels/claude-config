---
description: "Generate a daily standup summary from git commits, Jira activity, and open PRs. Usage: /standup [days=1]"
allowed_tools: Bash, Read, Glob, Grep, mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql, mcp__plugin_atlassian_atlassian__getJiraIssue, mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources
---

# /standup — Daily Standup Summary

Generate a concise standup report by pulling from all available data sources in parallel.

**Lookback**: `$ARGUMENTS` days (default: 1). If `$ARGUMENTS` is empty or not a number, use 1.

Store as `$DAYS`.

## Step 1: Gather Data (Parallel)

Run ALL of the following in parallel. Do not wait for one to finish before starting another. Each source is independent.

### 1a. Git Commits

```bash
git log --all --author="$(git config user.name)" --since="$DAYS days ago" --format="%h %s (%ar)" --no-merges
```

If in a worktree, also check the main repo. Store as `$COMMITS`.

### 1b. Open PRs (authored)

```bash
gh pr list --author="starkmichelsc" --state=open --json number,title,baseRefName,headRefName,updatedAt,reviewDecision --limit 20
```

Also check for PRs that were merged in the lookback window:
```bash
gh pr list --author="starkmichelsc" --state=merged --json number,title,mergedAt --limit 10
```

Filter merged PRs to only those merged within `$DAYS` days. Store open as `$OPEN_PRS` and recently merged as `$MERGED_PRS`.

### 1c. PR Reviews Requested

```bash
gh pr list --search "review-requested:starkmichelsc" --state=open --json number,title,author,updatedAt --limit 10
```

Store as `$REVIEW_REQUESTS`.

### 1d. Jira Activity

**Try MCP first** using cloudId `7d1d0780-63ed-4375-90d5-5424cc8695a3`:

Search for issues assigned to the current user, updated in the lookback window:
```
searchJiraIssuesUsingJql(
  cloudId: "7d1d0780-63ed-4375-90d5-5424cc8695a3",
  jql: "assignee = currentUser() AND updated >= -${DAYS}d ORDER BY updated DESC"
)
```

**If MCP fails or hangs (>30s):** Fall back to CLI:
```bash
acli jira --action getIssueList --jql "assignee = currentUser() AND updated >= -${DAYS}d ORDER BY updated DESC" 2>/dev/null
```

**If both fail:** Skip Jira section entirely. Do not block the report.

Store as `$JIRA_ISSUES`. Extract key, summary, status, and priority for each.

## Step 2: Detect Current Context

```bash
git branch --show-current 2>/dev/null
```

Store as `$CURRENT_BRANCH`. If it matches a ticket pattern (`[A-Z]+-[0-9]+`), note the active ticket.

Also check for `.jira-context` in the repo root — if present, read it for additional context.

## Step 3: Format the Report

Output a clean, scannable standup report using this structure:

```
## Standup — {date} ({lookback} day window)

### Done
{List commits grouped by repo/branch. Each item: commit hash, message.}
{List merged PRs: #number — title}

### In Progress
{List open PRs: #number — title (review status: approved/changes_requested/pending)}
{List Jira tickets in "In Progress" status: KEY — summary}
{Note current branch if it maps to a ticket}

### Needs Attention
{PRs with changes requested}
{PRs awaiting your review (from $REVIEW_REQUESTS)}
{Jira tickets that are blocked or high priority}

### Up Next
{Jira tickets in "To Do" or "Selected for Development" status}
```

## Formatting Rules

- If a section has no items, omit it entirely — no "None" placeholders
- Keep it tight. One line per item. No descriptions unless critical.
- Group commits by branch/repo when there are more than 5
- For PRs, include the review decision status as a short tag: `[approved]`, `[changes requested]`, `[pending review]`
- Dates should be relative ("2 hours ago", "yesterday") not absolute
- If `$DAYS` > 1, label it as a multi-day summary
- Do NOT wrap the output in a code block — render it as markdown directly
