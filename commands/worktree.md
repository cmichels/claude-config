---
description: "Set up a git worktree for a Jira ticket with full pipeline: worktree creation, config copy, Jira fetch, codebase analysis, and plan generation. Usage: /worktree <TICKET-ID>"
allowed_tools: Read, Glob, Grep, Bash, Task, AskUserQuestion, mcp__plugin_atlassian_atlassian__getJiraIssue, mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql, mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources, mcp__plugin_atlassian_atlassian__search
---

# Worktree Setup Command

You are setting up a fully-configured git worktree for Jira ticket implementation. The ticket ID is: **$ARGUMENTS**

---

## Step 1: Detect Repository Context

### 1.1 Validate Git Repository

```bash
git rev-parse --is-inside-work-tree 2>/dev/null
```

**If not a git repo:** STOP and inform user: "Not inside a git repository. Please navigate to the project you want to create a worktree from."

### 1.2 Detect Repo Name and Parent Directory

```bash
# Get the repo root directory name (this becomes the project prefix)
basename "$(git rev-parse --show-toplevel)"

# Get the parent directory (where the worktree will be created)
dirname "$(git rev-parse --show-toplevel)"
```

Store as `$REPO_NAME` and `$PARENT_DIR`.

**Example:** If in `/Volumes/data/projects/tsp/alarm-service`, then:
- `$REPO_NAME = "alarm-service"`
- `$PARENT_DIR = "/Volumes/data/projects/tsp"`
- Worktree will land at `/Volumes/data/projects/tsp/alarm-service-OP-3088`

### 1.3 Parse Ticket ID

The `$ARGUMENTS` should be a Jira ticket key like `OP-3088` or `TSP-456`.

**Validation:** Must match pattern `[A-Z]+-\d+`

**If no ticket ID provided:** Use `AskUserQuestion` to ask for it.

**If invalid format:** Inform user of the expected format and ask again.

Store as `$TICKET_ID`.

### 1.4 Compute Worktree Path

```
$WORKTREE_PATH = "$PARENT_DIR/$REPO_NAME-$TICKET_ID"
```

**Example:** `/Volumes/data/projects/tsp/alarm-service-OP-3088`

### 1.5 Check Worktree Doesn't Already Exist

```bash
git worktree list
```

Also check if the target directory already exists:
```bash
ls -d "$WORKTREE_PATH" 2>/dev/null
```

**If worktree or directory already exists:** Inform user and ask:
- **Use existing** — cd into it and skip to Step 5 (codebase analysis)
- **Remove and recreate** — `git worktree remove "$WORKTREE_PATH"` then continue
- **Abort** — stop the command

---

## Step 2: Fetch Jira Ticket (before worktree creation)

We fetch the Jira ticket **first** so we can derive a proper branch name from the issue type and summary.

### 2.1 Check Jira Connectivity

**Try MCP first:**
```
mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources()
```

Store the cloudId. Set `$JIRA_MODE = "mcp"`.

**If MCP fails:** Fall back to acli CLI.
```bash
acli jira --action getIssue --issue "$TICKET_ID" 2>/dev/null
```

**If acli succeeds:** Set `$JIRA_MODE = "acli"` and inform user.

**If both fail:** STOP and inform user:
```
Jira connectivity failed via both MCP and acli CLI.

MCP setup:
  claude mcp add --transport sse atlassian https://mcp.atlassian.com/v1/sse

acli setup:
  brew install atlassian-cli
  acli auth

Run `/mcp` to check your MCP server status.
```

### 2.2 Fetch Ticket Details

**If `$JIRA_MODE = "mcp"`:**
```
mcp__plugin_atlassian_atlassian__getJiraIssue(
  cloudId: "$CLOUD_ID",
  issueIdOrKey: "$TICKET_ID"
)
```

**If `$JIRA_MODE = "acli"`:**
```bash
acli jira --action getIssue --issue "$TICKET_ID"
```

Extract and store:
- `$JIRA_SUMMARY` — ticket title/summary
- `$JIRA_DESCRIPTION` — full description
- `$JIRA_TYPE` — issue type (Story, Bug, Task, etc.)
- `$JIRA_PRIORITY` — priority level
- `$JIRA_ACCEPTANCE` — acceptance criteria (if present)
- `$JIRA_LABELS` — any labels on the ticket
- `$JIRA_PARENT` — parent epic or story (if subtask)

### 2.3 Derive Branch Name

Build the branch name from the Jira issue type and summary:

1. **Determine prefix:**
   - If `$JIRA_TYPE` is `Bug` → prefix = `bug`
   - For all other types (Story, Task, Subtask, etc.) → prefix = `feature`

2. **Slugify the summary** to create a short descriptor:
   - Lowercase `$JIRA_SUMMARY`
   - Replace spaces and special characters with hyphens
   - Remove consecutive hyphens
   - Truncate to ~50 characters max (break at word boundary)
   - Remove trailing hyphens

3. **Compose branch name:**
   ```
   $BRANCH_NAME = "<prefix>/${TICKET_ID}_<slugified-summary>"
   ```

   **Examples:**
   - Bug ticket `OP-3088` with summary "Fix null pointer in alarm handler"
     → `bug/OP-3088_fix-null-pointer-in-alarm-handler`
   - Story ticket `OP-4001` with summary "Add webhook retry logic for failed deliveries"
     → `feature/OP-4001_add-webhook-retry-logic-for-failed-deliveries`

### 2.4 Search for Related Context

Use Rovo search to find related tickets, docs, or context:
```
mcp__plugin_atlassian_atlassian__search(
  query: "$JIRA_SUMMARY"
)
```

Store any relevant related items (linked tickets, Confluence docs) as `$RELATED_CONTEXT`.

### 2.5 Write .jira-context File (deferred to after worktree creation)

Store the Jira data for writing in Step 4.

---

## Step 3: Create Worktree

### 3.1 Ensure Dev Branch Is Up to Date

```bash
git fetch origin dev
```

### 3.2 Create the Worktree

```bash
git worktree add "$WORKTREE_PATH" -b "$BRANCH_NAME" origin/dev
```

This creates:
- A new worktree at `$WORKTREE_PATH`
- A new branch named `$BRANCH_NAME` (e.g. `feature/OP-3088_add-webhook-retry`) based on `origin/dev`

**If the branch already exists** (e.g., from a previous attempt):
```bash
git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
```

**If this also fails:** Inform user with the error and ask how to proceed.

---

## Step 4: Copy Config Files & Write Context

### 4.1 Detect Config Files in Source Repo

Get the source repo root:
```bash
git rev-parse --show-toplevel
```

Store as `$SOURCE_ROOT`.

Scan for these config files/directories in the source repo. **Only copy what exists:**

| Priority | Path | Description |
|----------|------|-------------|
| Always | `.claude/` | Claude Code settings and config |
| Always | `.local` | Local environment config |
| Always | `.env` | Environment variables |
| If exists | `.env.local` | Local env overrides |
| If exists | `.env.development` | Dev environment config |
| If exists | `docker-compose.yml` | Docker config |
| If exists | `docker-compose.override.yml` | Docker overrides |
| If exists | `.ralph/` | Ralph loop state |
| If exists | `ClientApp/src/environments/` | Angular environment configs (gitignored) |

### 4.2 Copy Files

**IMPORTANT:** Use `command cp` to bypass shell aliases that add `-i` (interactive confirmation).

For directories:
```bash
command cp -r "$SOURCE_ROOT/.claude" "$WORKTREE_PATH/.claude"
```

For files:
```bash
command cp "$SOURCE_ROOT/.env" "$WORKTREE_PATH/.env"
```

For nested gitignored directories (e.g., Angular environments):
```bash
mkdir -p "$WORKTREE_PATH/ClientApp/src/environments"
command cp "$SOURCE_ROOT/ClientApp/src/environments/"*.ts "$WORKTREE_PATH/ClientApp/src/environments/"
```

Only copy files that exist. Do not error on missing optional files.

### 4.3 Report What Was Copied

List all files/directories that were successfully copied so the user knows what's in the worktree.

### 4.4 Write .jira-context File

Write a JSON context file to the worktree root so other tools (Claude Code status line, shell functions) can display ticket context:

```bash
cat > "$WORKTREE_PATH/.jira-context" << 'CTXEOF'
{
  "key": "$TICKET_ID",
  "type": "$JIRA_TYPE",
  "priority": "$JIRA_PRIORITY",
  "summary": "$JIRA_SUMMARY"
}
CTXEOF
```

Replace the `$VARIABLES` with actual values. Ensure valid JSON (escape any quotes in the summary).

**If the write fails:** Log a warning but do not abort — this file is informational, not critical.

---

## Step 5: Analyze Codebase

### 5.1 Identify Affected Modules

Based on the Jira ticket description and summary, analyze the worktree codebase to identify:
- Which packages/modules are likely affected
- Key files that will need modification
- Existing patterns and conventions in the affected areas
- Test files that exist for the affected modules
- Any relevant interfaces, types, or models

Use `Glob`, `Grep`, and `Read` tools to explore the codebase. Focus on:
1. The ticket description keywords — search for relevant terms in the code
2. Package structure — understand the project layout
3. Related tests — identify existing test patterns
4. Configuration — any config files relevant to the feature/fix

### 5.2 Check for Existing Plans

Look for any existing plan files that might provide context:
```
Glob: plans/*.md in $WORKTREE_PATH
```

Also check for a CLAUDE.md in the project root for project-specific conventions.

---

## Step 6: Generate Plan

### 6.1 Create Plans Directory

```bash
mkdir -p "$WORKTREE_PATH/plans"
```

### 6.2 Write Plan File

Create the plan at `$WORKTREE_PATH/plans/$TICKET_ID.md`.

**Plan template:**

```markdown
# $TICKET_ID: $JIRA_SUMMARY

## Ticket Context

- **Type:** $JIRA_TYPE
- **Priority:** $JIRA_PRIORITY
- **Jira:** https://starktechgroup.atlassian.net/browse/$TICKET_ID

### Description
$JIRA_DESCRIPTION

### Acceptance Criteria
$JIRA_ACCEPTANCE (or "Not specified" if absent)

### Related Context
$RELATED_CONTEXT (or "None found" if absent)

## Codebase Analysis

### Affected Modules
<List the packages/modules identified in Step 5.1>

### Key Files
<List specific files that will need modification with brief descriptions>

### Existing Patterns
<Describe relevant patterns, conventions, and architectural decisions
observed in the affected areas of the codebase>

### Test Coverage
<Describe existing test files and patterns for the affected modules>

## Implementation Plan

### Phase 1: <descriptive name>
- [ ] Step description
  - Details about what this step involves
  - Files affected: `path/to/file`

### Phase 2: <descriptive name>
- [ ] Step description
  - Details about what this step involves
  - Files affected: `path/to/file`

### Phase N: Testing & Verification
- [ ] Run existing tests to confirm no regressions
- [ ] Add/update tests for new functionality
- [ ] Verification command: `<appropriate test command>`

## Open Questions

<List any ambiguities or decisions that need user input before implementation>

## Guardrails

<Project-specific constraints discovered during codebase analysis:
module paths, import rules, testing conventions, etc.>
```

**Guidelines for generating the plan:**
- Be specific about file paths and function names
- Reference actual code patterns found during analysis
- Break implementation into logical phases that can be approved step-by-step
- Include a testing phase with the project's actual test commands
- Surface any ambiguities as open questions rather than making assumptions
- Include guardrails based on project conventions found in CLAUDE.md or .ralph/

---

## Step 7: Summary Output

Display the completed setup:

```
Worktree Ready

Ticket:     $TICKET_ID - $JIRA_SUMMARY
Type:       $JIRA_TYPE
Worktree:   $WORKTREE_PATH
Branch:     $BRANCH_NAME (from origin/dev)
Plan:       $WORKTREE_PATH/plans/$TICKET_ID.md
Jira Mode:  $JIRA_MODE

Config copied:
  - .claude/
  - .env
  - .local
  (list what was actually copied)

Affected modules:
  - <module 1>
  - <module 2>

Open questions: <n> (see plan file)

To start working:
  cd $WORKTREE_PATH
```

If there are open questions in the plan, highlight them and ask the user if they want to resolve them now before starting implementation.

---

## Error Handling

At any point if an error occurs:
1. Display clear error message
2. Show what succeeded before the failure
3. Provide remediation steps
4. Ask if user wants to retry or abort

**Common errors to handle:**
- Worktree path already exists (directory conflict)
- Branch already exists (from previous attempt)
- Jira ticket not found (typo in ticket ID)
- Jira auth failure -> fall back to acli if in MCP mode
- Git fetch failure (network, auth)
- Insufficient disk space
- Source config files with restricted permissions

**Jira Fallback Rules:**
- If any MCP Jira call fails mid-workflow, automatically retry using acli CLI
- Switch `$JIRA_MODE` to "acli" and continue
- Inform user: "Jira MCP call failed - switched to acli CLI fallback"

**Cleanup on Failure:**
- If the worktree was created but a later step fails, do NOT automatically remove it
- Inform the user the worktree exists at `$WORKTREE_PATH` and let them decide
- The user can always re-run `/worktree $TICKET_ID` and choose "Use existing" to resume
