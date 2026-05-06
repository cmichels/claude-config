---
description: "Set up a git worktree for a Jira ticket with full pipeline: worktree creation, config copy, Jira fetch, codebase analysis, and plan generation. Usage: /worktree <TICKET-ID>"
allowed_tools: Read, Glob, Grep, Bash, Task, AskUserQuestion
---

# Worktree Setup Command

You are setting up a fully-configured git worktree for Jira ticket implementation. The ticket ID is: **$ARGUMENTS**

---

## Step 1: Detect Repository Context

### 1.1 Validate Git Repository and Detect Repo Info

Run the pre-built repo-info script (auto-approved via bin/ permission):

```bash
/home/kuda/.claude/bin/repo-info.sh
```

This outputs key-value pairs:
```
is_git_repo: true
repo_name: alarm-service
parent_dir: /home/kuda/projects/tsp
toplevel: /home/kuda/projects/tsp/alarm-service
branch: dev
```

**If `is_git_repo: false` or exit code 1:** STOP and inform user: "Not inside a git repository. Please navigate to the project you want to create a worktree from."

Parse the output and store as `$REPO_NAME`, `$PARENT_DIR`, `$TOPLEVEL`, and `$BRANCH`.

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

Also check if the target directory already exists using the pre-built bin script (auto-approved):
```bash
/home/kuda/.claude/bin/worktree-exists.sh "$WORKTREE_PATH"
```
Outputs `EXISTS` (exit 0) or `NOT_EXISTS` (exit 1).

**If worktree or directory already exists:** Inform user and ask:
- **Use existing** — cd into it and skip to Step 5 (codebase analysis)
- **Remove and recreate** — `git worktree remove "$WORKTREE_PATH"` then continue
- **Abort** — stop the command

---

## Step 2: Fetch Jira Ticket (before worktree creation)

We fetch the Jira ticket **first** so we can derive a proper branch name from the issue type and summary.

### 2.1 Check Jira Connectivity

```bash
acli jira auth status 2>&1
```

**If acli fails:** STOP and inform user:
```
Jira connectivity failed.

acli setup:
  ~/projects/personal/claude-config/install-acli.sh
  acli jira auth login --site starktechgroup.atlassian.net
```

### 2.2 Fetch Ticket Details

```bash
acli jira workitem view "$TICKET_ID" --json --fields "*all"
```

Extract and store via jq from the JSON output:
- `$JIRA_SUMMARY` — `.fields.summary`
- `$JIRA_DESCRIPTION` — `.fields.description`
- `$JIRA_TYPE` — `.fields.issuetype.name`
- `$JIRA_PRIORITY` — `.fields.priority.name`
- `$JIRA_ACCEPTANCE` — typically a custom field; try `.fields | to_entries[] | select(.key | test("acceptance"; "i"))`
- `$JIRA_LABELS` — `.fields.labels[]`
- `$JIRA_PARENT` — `.fields.parent.key` (if subtask)

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

Search Jira for related work items by keyword. Pull 2-3 high-signal terms from `$JIRA_SUMMARY` and search:
```bash
acli jira workitem search --jql "text ~ \"$KEYWORDS\" AND key != \"$TICKET_ID\"" --fields "key,summary,status" --json --limit 10
```

Store the related tickets as `$RELATED_CONTEXT`. Confluence search is unavailable via acli — if Confluence context is needed, the user must check manually at `https://starktechgroup.atlassian.net/wiki`.

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

Use `$TOPLEVEL` from Step 1.1 as `$SOURCE_ROOT`.

Run the pre-built config checker script (auto-approved via bin/ permission):

```bash
/home/kuda/.claude/bin/worktree-check-configs.sh "$SOURCE_ROOT" "$WORKTREE_PATH"
```

This outputs which files exist. **Only copy what exists:**

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

Run the same script with `--copy` to detect and copy in one pass (auto-approved via bin/ permission):

```bash
/home/kuda/.claude/bin/worktree-check-configs.sh "$SOURCE_ROOT" "$WORKTREE_PATH" --copy
```

This uses `command cp` internally to bypass shell aliases. It only copies files/directories that exist and reports what was copied.

### 4.4 Write .jira-context File

Use the **Write tool** (NOT Bash heredoc/cat) to create a JSON context file at `$WORKTREE_PATH/.jira-context`. This is auto-approved via Write permissions.

Contents (replace variables with actual values, ensure valid JSON — escape any quotes in the summary):

```json
{
  "key": "$TICKET_ID",
  "type": "$JIRA_TYPE",
  "priority": "$JIRA_PRIORITY",
  "summary": "$JIRA_SUMMARY"
}
```

**NEVER use `cat >` or Bash heredocs for this** — it triggers security warnings. The Write tool is pre-approved and silent.

**If the write fails:** Log a warning but do not abort — this file is informational, not critical.

### 4.5 Symlink Project Memory

Claude Code stores per-project memory at `~/.claude/projects/<path-key>/memory/`, where `<path-key>` is the absolute project path with `/` replaced by `-` (e.g., `/home/kuda/projects/tsp/alarm-service` → `-home-kuda-projects-tsp-alarm-service`).

Worktrees get a different path key than the source repo, so they start with an empty memory store. Fix this by symlinking the worktree's memory directory to the source repo's memory.

1. **Compute path keys:**
   ```bash
   SOURCE_PROJECT_KEY=$(echo "$TOPLEVEL" | sed 's|/|-|g')
   WORKTREE_PROJECT_KEY=$(echo "$WORKTREE_PATH" | sed 's|/|-|g')
   ```

2. **Check source memory exists:**
   ```bash
   SOURCE_MEMORY="$HOME/.claude/projects/${SOURCE_PROJECT_KEY}/memory"
   ```
   If `$SOURCE_MEMORY` does not exist, skip this step — no memory to share yet.

3. **Create worktree project directory and symlink:**
   ```bash
   WORKTREE_PROJECT_DIR="$HOME/.claude/projects/${WORKTREE_PROJECT_KEY}"
   mkdir -p "$WORKTREE_PROJECT_DIR"
   ln -s "$SOURCE_MEMORY" "$WORKTREE_PROJECT_DIR/memory"
   ```

4. **Verify:**
   ```bash
   ls -la "$WORKTREE_PROJECT_DIR/memory"
   ```
   Confirm it's a symlink pointing to the source repo's memory directory.

**If the source repo has no memory directory yet:** Skip silently — memory will be created naturally when the user starts building memories for that repo. Future worktrees will pick it up.

**If the symlink already exists:** Skip — this handles the "Use existing" worktree flow from Step 1.5.

---

## Step 4.6: Register Task with task-ctl

Register this worktree as a tracked task so it survives session crashes and can be resumed later.

```bash
task-ctl register \
  --jira "$TICKET_ID" \
  --repo "$OWNER/$REPO_NAME" \
  --branch "$BRANCH_NAME" \
  --worktree "$WORKTREE_PATH" \
  --summary "$JIRA_SUMMARY" \
  --type "$JIRA_TYPE" \
  --priority "$JIRA_PRIORITY"
```

Where `$OWNER/$REPO_NAME` is the GitHub org/repo (e.g., `Stark-Tech-Group/stark-web`). Extract from `git -C "$WORKTREE_PATH" remote get-url origin`.

**Note:** The `--plan` flag is omitted here because the plan file hasn't been generated yet. It will be linked after Step 6.

**If task-ctl is not installed** (command not found): Log a warning but do NOT block the worktree setup. The worktree is still usable without task tracking.

```
Warning: task-ctl not found — task not registered. Install with:
  cd ~/projects/personal/task-ctl && make install
```

---

## Step 5: Analyze Codebase

### 5.1 Identify Affected Modules

Based on the Jira ticket description and summary, analyze the worktree codebase to identify:
- Which packages/modules are likely affected
- Key files that will need modification
- Existing patterns and conventions in the affected areas
- Test files that exist for the affected modules
- Any relevant interfaces, types, or models

### ⛔ TOOL RULES FOR STEP 5 — READ BEFORE PROCEEDING

| Task | CORRECT tool | FORBIDDEN (triggers permission prompts) |
|------|-------------|----------------------------------------|
| Find files by pattern | `Glob` (`**/*.scss`, `**/routes.*`) | `find`, `ls`, `tree` |
| Search file contents | `Grep` (supports regex, glob filters) | `grep`, `rg`, `ack`, `xargs grep` |
| Read file contents | `Read` | `cat`, `head`, `tail`, `less` |
| Any combination | Use multiple tool calls in parallel | Piped shell commands (`find | xargs`, `grep -r | head`) |

**There are ZERO exceptions. Every Bash call in Step 5 is a bug.**

Focus on:
1. The ticket description keywords — use `Grep` to search for relevant terms in the code
2. Package structure — use `Glob` with patterns like `**/*.ts`, `**/routes.*` to understand the project layout
3. Related tests — use `Glob` with patterns like `**/*.spec.ts`, `**/*.test.ts` to identify existing test patterns
4. Search for CSS/style patterns — use `Grep` with regex and glob filters (e.g., `pattern: "\.card|card-block"`, `glob: "*.scss"`)
5. Configuration — use `Glob` and `Read` for any config files relevant to the feature/fix

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

### 6.3 Link Plan to Task

If task-ctl registration succeeded in Step 4.6, update the task with the plan path:

```bash
task-ctl link-plan "$TICKET_ID" --plan "$WORKTREE_PATH/plans/$TICKET_ID.md"
```

**If task-ctl is not installed or the task wasn't registered:** Skip silently.

**Note:** If `link-plan` is not a recognized command (task-ctl may not have it yet), this is non-blocking. The plan file path can be discovered later via convention (`plans/<KEY>.md`).

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

Config copied:
  - .claude/
  - .env
  - .local
  (list what was actually copied)

Memory:    linked → $SOURCE_MEMORY (or "no source memory found — skipped")

Affected modules:
  - <module 1>
  - <module 2>

Open questions: <n> (see plan file)

To start working:
  cd $WORKTREE_PATH
```

If there are open questions in the plan, highlight them and ask the user if they want to resolve them now before starting implementation.

---

## Step 8: Generate Starter Prompt

After displaying the summary, synthesize a ready-to-paste prompt for the new Claude session the user will open in the worktree.

### 8.1 Identify Insights Not Fully Captured in the Plan

Review everything gathered during Steps 2 and 5 and identify 2–5 things worth surfacing to the new session that the plan does not deeply address. These are not problems with the plan — they are observations, risks, or open threads that are worth discussing before diving in. Examples:

- A pattern in the codebase that conflicts with or complicates the planned approach
- A dependency or shared component that the plan touches but doesn't explain (e.g., a base class, shared service, or model used by many widgets)
- A security or data-integrity concern implied by the ticket that isn't called out
- An alternative approach that was considered but not chosen — worth flagging so the new session can evaluate the tradeoff
- A test gap: existing tests that will break or an area with no test coverage that the work will touch
- A scope ambiguity in the Jira ticket or acceptance criteria that could lead to over- or under-building

Keep each insight to one concise sentence. Only include ones that are genuinely informative — don't pad.

### 8.2 Output the Starter Prompt

Print the following block verbatim, with a clear "copy this" visual separator. Substitute all `$VARIABLES` with real values:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  STARTER PROMPT — paste into new session
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

I'm working on $TICKET_ID: $JIRA_SUMMARY ($JIRA_TYPE).

The implementation plan is at: plans/$TICKET_ID.md
Worktree: $WORKTREE_PATH

Before we start — a few things from the codebase analysis worth discussing:
- <insight 1>
- <insight 2>
- <insight 3 if applicable>
<open questions from the plan, formatted as: - Open question: <question text>>

Let's walk through the plan iteratively and interactively. For each item provide:
details, files to be changed, security concerns, design issues, refactoring
opportunities, pros, cons, tradeoffs, off suggestions, and ask clarifying
questions. I'll provide feedback and direction. After each item, update the
plan and commit changes.

Any questions?

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Notes for generating the starter prompt:**
- If there are no open questions in the plan, omit the open-question lines entirely.
- If there are no standout insights from analysis, use 1–2 generic but accurate observations rather than fabricating specifics (e.g., "The affected module has no existing unit tests — coverage will need to be added.").
- The insights section is the high-value part of this prompt. Spend the most care here — this is what distinguishes a useful handoff from a generic one.

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
- Jira auth failure — run `acli jira auth login --site starktechgroup.atlassian.net`
- Git fetch failure (network, auth)
- Insufficient disk space
- Source config files with restricted permissions

**Cleanup on Failure:**
- If the worktree was created but a later step fails, do NOT automatically remove it
- Inform the user the worktree exists at `$WORKTREE_PATH` and let them decide
- The user can always re-run `/worktree $TICKET_ID` and choose "Use existing" to resume
