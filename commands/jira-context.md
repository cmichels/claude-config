---
description: "Generate a .jira-context file for the current repo. Detects ticket ID from branch name or accepts it as an argument. Usage: /jira-context [TICKET-ID]"
allowed_tools: Bash, Read, Write
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

Use acli to fetch the ticket as JSON:

```bash
acli jira workitem view "$TICKET_ID" --json --fields "summary,issuetype,priority"
```

**If acli fails:** STOP and inform user about Jira connectivity. Suggest running `acli jira auth status` to verify auth.

Parse the JSON with jq:
```bash
JIRA_SUMMARY=$(echo "$JSON" | jq -r '.fields.summary // .summary')
JIRA_TYPE=$(echo "$JSON" | jq -r '.fields.issuetype.name // .issuetype.name')
JIRA_PRIORITY=$(echo "$JSON" | jq -r '.fields.priority.name // .priority.name // "None"')
```

The acli JSON wraps fields under `.fields.*`; the `// .X` fallbacks handle any future flattening.

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
