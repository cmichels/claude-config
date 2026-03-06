---
description: "Generate a .jira-context file for the current repo. Detects ticket ID from branch name or accepts it as an argument. Usage: /jira-context [TICKET-ID]"
allowed_tools: Bash, Read, Write, mcp__plugin_atlassian_atlassian__getJiraIssue, mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources
---

# Generate .jira-context

Create a `.jira-context` JSON file in the current repo root so the Claude Code status line and shell tools can display ticket context.

## Step 1: Determine Ticket ID

**If `$ARGUMENTS` is provided and matches `[A-Z]+-\d+`:** Use it as `$TICKET_ID`.

**Otherwise:** Detect from the current git branch:
```bash
git branch --show-current 2>/dev/null
```

Extract ticket ID matching pattern `[A-Z]+-[0-9]+` from the branch name (e.g., `feature/OP-3088-fix-thing` -> `OP-3088`, or just `OP-3088` if the branch is the ticket ID).

**If no ticket ID found:** Inform user: "Could not detect a Jira ticket ID from branch name. Usage: `/jira-context OP-1234`"

## Step 2: Find Repo Root

```bash
git rev-parse --show-toplevel 2>/dev/null
```

Store as `$REPO_ROOT`. If not in a git repo, use the current working directory.

## Step 3: Check for Existing .jira-context

```bash
ls "$REPO_ROOT/.jira-context" 2>/dev/null
```

**If it already exists:** Read and display it, then ask user if they want to overwrite or keep existing.

## Step 4: Fetch Jira Ticket

**Try MCP first:**
```
mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources()
```

Store the cloudId. Then:
```
mcp__plugin_atlassian_atlassian__getJiraIssue(
  cloudId: "$CLOUD_ID",
  issueIdOrKey: "$TICKET_ID"
)
```

**If MCP fails:** Fall back to acli CLI:
```bash
acli jira --action getIssue --issue "$TICKET_ID" 2>/dev/null
```

**If both fail:** STOP and inform user about Jira connectivity.

Extract:
- `$JIRA_SUMMARY` — ticket title
- `$JIRA_TYPE` — issue type (Story, Bug, Task, etc.)
- `$JIRA_PRIORITY` — priority level

## Step 5: Write .jira-context

Write the JSON file to `$REPO_ROOT/.jira-context`:

```json
{
  "key": "$TICKET_ID",
  "type": "$JIRA_TYPE",
  "priority": "$JIRA_PRIORITY",
  "summary": "$JIRA_SUMMARY"
}
```

Replace variables with actual values. Ensure valid JSON (escape quotes in summary).

## Step 6: Confirm

Display the written context:
```
.jira-context written to $REPO_ROOT/.jira-context

  $TICKET_ID | $JIRA_TYPE | $JIRA_PRIORITY | $JIRA_SUMMARY
```
