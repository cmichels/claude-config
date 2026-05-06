---
description: "Commit, push, create Jira ticket (if needed), and open a PR with proper labels/reviewers. Usage: /ship-it. Auto-generates commit messages and PR descriptions from code changes and Jira context. Validates branch naming (feature/* or bug/*), auto-detects dependency changes, assigns reviewers. Uses acli for all Jira operations."
allowed_tools: Read, Glob, Grep, Bash, AskUserQuestion
---

# Ship-It Command

Automates the full shipping workflow: validate branch -> analyze changes -> preview & confirm commit -> push -> create Jira ticket (if needed) -> auto-generate PR description -> create PR targeting `dev` with proper configuration.

All commit messages and PR descriptions are **automatically generated** based on:
- Analysis of actual code changes (git diff)
- Jira ticket context (summary, description, type)
- Branch type (feature/bug)

---

## Step 1: Environment Validation

### 1.1 Check Git Repository

```bash
git rev-parse --is-inside-work-tree 2>/dev/null && git remote get-url origin 2>/dev/null
```

**If not a git repo:** STOP and inform user: "Not inside a git repository. Please navigate to a git project."

### 1.2 Parse Repository Info

Extract owner and repo from the remote URL:
- SSH: `git@github.com:owner/repo.git` -> extract owner, repo
- HTTPS: `https://github.com/owner/repo.git` -> extract owner, repo

Store as `$OWNER` and `$REPO`.

### 1.3 Check Jira Connectivity

```bash
acli jira auth status 2>&1
```

**If acli auth check fails:** STOP and inform user:
```
Jira connectivity failed.

acli setup:
  ~/projects/personal/claude-config/install-acli.sh
  acli jira auth login --site starktechgroup.atlassian.net
```

---

## Step 2: Branch Validation

### 2.1 Get Current Branch

```bash
git branch --show-current
```

Store as `$BRANCH`.

### 2.2 Validate Branch Pattern

The branch MUST match one of these patterns:
- `feature/*` - for new features
- `bug/*` - for bug fixes

**Regex check:** `^(feature|bug)/`

**If branch doesn't match pattern:** STOP and ask user:
```
Current branch '$BRANCH' does not follow the required naming convention.

Branches must be named:
- feature/PROJ-XXX-description (for features)
- bug/PROJ-XXX-description (for bugs)

Would you like to:
1. Create a new branch with the correct naming?
2. Rename the current branch?
3. Abort the operation?
```

If user chooses to create/rename, prompt for:
- Branch type (feature/bug)
- Jira ticket (or create new)
- Description

### 2.3 Determine Branch Type

Extract branch type from prefix:
- `feature/*` -> `$BRANCH_TYPE = "feature"`, `$LABEL = "enhancement"`
- `bug/*` -> `$BRANCH_TYPE = "bug"`, `$LABEL = "bug"`

---

## Step 3: Jira Ticket Handling

### 3.1 Extract Ticket and Project Key from Branch Name

Parse branch for Jira ticket pattern: `(feature|bug)/([A-Z]+-\d+)`

**Examples:**
- `feature/OP-123-add-user-auth` -> `$JIRA_TICKET = "OP-123"`, `$PROJECT_KEY = "OP"`
- `bug/TSP-456-fix-login` -> `$JIRA_TICKET = "TSP-456"`, `$PROJECT_KEY = "TSP"`
- `feature/DEVOPS-99-infra` -> `$JIRA_TICKET = "DEVOPS-99"`, `$PROJECT_KEY = "DEVOPS"`
- `feature/add-new-thing` -> `$JIRA_TICKET = null`, `$PROJECT_KEY = null`

The project key is always derived from the ticket prefix (the letters before the dash-number). **Never hardcode a project key.**

### 3.2 If Ticket Found: Verify It Exists

```bash
acli jira workitem view "$JIRA_TICKET" --json --fields "summary,description,issuetype"
```

Parse with jq:
```bash
JIRA_SUMMARY=$(echo "$JSON" | jq -r '.fields.summary')
JIRA_DESCRIPTION=$(echo "$JSON" | jq -r '.fields.description // ""')
```

Store for later use.

**If ticket not found** (acli exits non-zero or returns null): Inform user and ask if they want to create it.

### 3.3 If No Ticket: Create New Jira Ticket

Prompt user for required information using AskUserQuestion:
- **Project Key:** Which Jira project? (required since it can't be auto-detected)
- **Summary:** Short description (or derive from branch name)
- **Issue Type:** Story (feature) or Bug (bug) - auto-select based on branch type
- **Description:** (optional) Detailed description

Store the chosen project key as `$PROJECT_KEY`.

Create the ticket:
```bash
acli jira workitem create --project "$PROJECT_KEY" --type "$ISSUE_TYPE" --summary "$SUMMARY" --description "$DESCRIPTION" --json
```

Parse the returned key:
```bash
JIRA_TICKET=$(echo "$JSON" | jq -r '.key')
```

Store as `$JIRA_TICKET`.

**If acli rejects the issue type** (e.g., "Story" not valid for the project): the available types vary per project. Try common alternatives — `Task`, `Story`, `Bug` — or ask the user.

### 3.4 Update Branch Name (if ticket was created)

If a new ticket was created, offer to rename the branch:
```bash
git branch -m "$BRANCH" "$BRANCH_TYPE/$JIRA_TICKET-$DESCRIPTION_SLUG"
```

Update `$BRANCH` variable.

---

## Step 4: Analyze Changes

### 4.1 Check for Uncommitted Changes

```bash
git status --porcelain
```

**If no changes:** Check if there are unpushed commits:
```bash
git log origin/$(git branch --show-current)..HEAD --oneline 2>/dev/null || git log --oneline -5
```

**If no changes and no unpushed commits:** STOP and inform user: "No changes to ship."

### 4.2 Get Changed Files

```bash
git diff --name-only HEAD
git diff --cached --name-only
git ls-files --others --exclude-standard
```

Store combined list as `$CHANGED_FILES`.

### 4.3 Detect Dependency Changes

Check if any dependency files were modified:

**Dependency file patterns:**
- `package.json`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
- `go.mod`, `go.sum`
- `requirements.txt`, `Pipfile`, `Pipfile.lock`, `pyproject.toml`, `poetry.lock`
- `Gemfile`, `Gemfile.lock`
- `Cargo.toml`, `Cargo.lock`
- `build.gradle`, `pom.xml`
- `*.csproj`, `packages.config`

```bash
git diff --name-only HEAD | grep -E "(package\.json|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|go\.(mod|sum)|requirements\.txt|Pipfile|pyproject\.toml|poetry\.lock|Gemfile|Cargo\.(toml|lock)|build\.gradle|pom\.xml|\.csproj|packages\.config)"
```

**If matches found:** Set `$HAS_DEPENDENCY_CHANGES = true`

---

## Step 5: Commit and Push

### 5.1 Analyze Code Changes

Get the full diff to understand what changed:
```bash
git diff HEAD
git diff --cached
```

Read the content of key changed files to understand the nature of the changes.

**Tool rules for code analysis:** Use `Read`, `Glob`, and `Grep` tools for examining file contents, finding files, and searching code. NEVER use Bash commands like `cat`, `grep`, `find`, `head`, `cd && ...`, or piped shell commands for codebase exploration — these trigger permission prompts. The dedicated tools are auto-approved.

### 5.2 Generate Commit Message

**Auto-generate** a commit message based on:
1. The code diff analysis
2. The Jira ticket summary and description (from Step 3.2)
3. The branch type (feature/bug)

**Commit message format:**
```
$JIRA_TICKET: <concise summary of what changed>

- Bullet points of specific changes if needed
```

**Guidelines for generating commit message:**
- Keep the first line under 72 characters
- Use imperative mood ("Add feature" not "Added feature")
- Reference the actual code changes, not just the Jira ticket description
- Be specific about what files/functions were modified

### 5.3 Preview Commit (Confirmation Gate)

**Before staging or committing**, display a preview to the user:

```
--- Ship-It Preview ---

Files to stage:
  M  src/api/handler.go
  M  src/api/handler_test.go
  A  src/models/user.go

Commit message:
  OP-123: Add user registration endpoint

  - Add POST /api/v1/users handler with validation
  - Add User model with email and role fields
  - Add unit tests for registration flow

Proceed?
```

Use **AskUserQuestion** with these options:
- **Ship it** - Stage, commit, push, and create PR
- **Edit commit message** - Let user modify the message before proceeding
- **Abort** - Cancel the operation

**If user chooses "Edit commit message":** Ask for their revised message, then re-display preview.

### 5.4 Stage Files (Explicit Staging)

**Do NOT use `git add -A`.** Instead, stage files explicitly by name:

```bash
git add src/api/handler.go src/api/handler_test.go src/models/user.go
```

**Rules for staging:**
- Stage only the files listed in `$CHANGED_FILES` from Step 4.2
- **NEVER stage** files matching these patterns (warn user if found):
  - `.env`, `.env.*` (environment/secrets)
  - `credentials.json`, `*-credentials.json`, `*.pem`, `*.key`
  - `*.secret`, `secrets.*`
  - `.DS_Store`, `Thumbs.db`
  - `node_modules/`, `vendor/` (should be gitignored, but check)
- If any suspicious files are in the changeset, warn the user and exclude them unless explicitly confirmed

### 5.5 Commit

```bash
git commit -m "$(cat <<'EOF'
$GENERATED_COMMIT_MESSAGE
EOF
)"
```

**If the commit fails** (e.g., pre-commit hook failure): STOP. Do NOT proceed to push. Inform the user of the failure and provide the hook output. Ask how they want to proceed.

### 5.6 Push to Remote

**Only push if the commit in Step 5.5 succeeded.**

Check if remote branch exists:
```bash
git ls-remote --heads origin $BRANCH
```

**If remote doesn't exist:** Push with upstream tracking:
```bash
git push -u origin $BRANCH
```

**If remote exists:** Regular push:
```bash
git push
```

---

## Step 6: Create Pull Request

### 6.1 Check for Existing PR

```bash
gh pr list --repo "$OWNER/$REPO" --head "$BRANCH" --state open --json number,url,title
```

**If PR already exists** (non-empty JSON array): Inform user and provide link. Ask if they want to update it or skip.

### 6.2 Set Base Branch

**Always target `dev`** as the base branch. Do NOT auto-detect from the remote default.

```
$BASE_BRANCH = "dev"
```

This is a hard rule per project convention. If the user explicitly specifies a different base, honor their request.

### 6.3 Generate PR Title and Body

**Auto-generate** the PR title and body based on:
1. The code diff analysis (from Step 5.1)
2. The Jira ticket summary and description (from Step 3.2)
3. The commit message generated in Step 5.2
4. The branch type (feature/bug)

**Title format:** `$JIRA_TICKET: <summary derived from changes and Jira ticket>`

**Body template:**
```markdown
## Summary

<Auto-generated description of what this PR accomplishes, based on the code changes and Jira ticket context. Write 2-4 sentences explaining the purpose and approach.>

## Changes

<Auto-generated bullet points of specific code changes:>
- File/module changes
- New functions or classes added
- Modified behavior
- Configuration changes

## Type

- [x] $TYPE (Feature or Bug fix - check the appropriate one)
- [$DEPENDENCY_CHECK] Dependency update

## Test Plan

<Auto-generated suggestions for how to test, based on what changed>

---

jira:$JIRA_TICKET
```

**Guidelines for generating PR description:**
- Analyze the actual code diff to describe what changed
- Cross-reference with Jira ticket for business context
- Be specific about files and functions modified
- The `jira:$JIRA_TICKET` line MUST be at the bottom (e.g., `jira:OP-123`)
- Check the appropriate type checkbox based on branch type
- If dependencies changed, check that box too
- Use actual newlines in the body string, never literal `\n` escape sequences

### 6.4 Determine Labels

Build labels array:
```
$LABELS = ["$LABEL"]  // "enhancement" or "bug"

if $HAS_DEPENDENCY_CHANGES:
  $LABELS.push("dependencies")
```

### 6.5 Create the PR

Write the PR body to a temp file (avoids escaping issues with multi-line content) and create with `gh pr create`:

```bash
cat > /tmp/pr-body.md <<'PR_BODY_EOF'
$PR_BODY
PR_BODY_EOF

gh pr create \
  --repo "$OWNER/$REPO" \
  --title "$PR_TITLE" \
  --body-file /tmp/pr-body.md \
  --head "$BRANCH" \
  --base dev \
  --draft

rm -f /tmp/pr-body.md
```

The PR URL is printed to stdout. Extract the PR number from the URL (last path segment) and store as `$PR_NUMBER`.

### 6.5.1 Link PR to Task

If the worktree has a `.jira-context` file (indicating it was set up via `/worktree`), link the PR to the tracked task:

```bash
task-ctl link-pr "$JIRA_TICKET" --pr $PR_NUMBER --url "https://github.com/$OWNER/$REPO/pull/$PR_NUMBER"
```

**If task-ctl is not installed or the task is not registered:** Log a warning but do NOT block PR creation. The PR is the priority.

```
Warning: task-ctl link-pr failed — PR not linked to task tracker.
```

### 6.6 Add Labels

```bash
gh pr edit $PR_NUMBER --add-label "$LABEL" --repo "$OWNER/$REPO"
```

If dependency changes detected:
```bash
gh pr edit $PR_NUMBER --add-label "dependencies" --repo "$OWNER/$REPO"
```

### 6.7 Set Assignee

Use the known GitHub username (do NOT call `gh api user`):
```
$GH_USER = "starkmichelsc"
```

Assign:
```bash
gh pr edit $PR_NUMBER --add-assignee "$GH_USER" --repo "$OWNER/$REPO"
```

### 6.8 Add Reviewers

```bash
gh pr edit $PR_NUMBER --add-reviewer "stark-tech-group/tsp-admin-contributors" --add-reviewer "stark-tech-group/tsp-contributors" --add-reviewer "copilot-pull-request-reviewer" --repo "$OWNER/$REPO"
```

**Note:** All three reviewers (tsp-admin-contributors, tsp-contributors, and copilot-pull-request-reviewer) are always requested.

---

## Step 7: Summary Output

After successful completion, display:

```
Ship-It Complete!

Repo:       $OWNER/$REPO
Branch:     $BRANCH
Base:       dev
Jira:       $JIRA_TICKET (https://starktechgroup.atlassian.net/browse/$JIRA_TICKET)
PR:         #$PR_NUMBER [DRAFT] (https://github.com/$OWNER/$REPO/pull/$PR_NUMBER)
Assignee:   $GH_USER
Reviewers:  tsp-admin-contributors, tsp-contributors, copilot-pull-request-reviewer
Labels:     $LABELS (comma-separated)

Commits pushed: [number]
Files changed:  [number]
```

---

## Error Handling

At any point if an error occurs:
1. Display clear error message
2. Show what succeeded before the failure
3. Provide remediation steps
4. Ask if user wants to retry or abort

**Common errors to handle:**
- Git authentication failure
- GitHub API rate limit
- Jira auth failure — run `acli jira auth login --site starktechgroup.atlassian.net`
- Pre-commit hook failure -> STOP, do not push, show hook output
- Branch protection rules preventing push
- PR already exists
- Required labels don't exist in repo
- Reviewer teams don't exist or user lacks permission to request

---

## Configuration Notes

This command requires:

1. **GitHub CLI (gh)** - For all PR operations:
```bash
brew install gh   # or: sudo apt install gh
gh auth login
```

2. **acli CLI** - For all Jira operations:
```bash
~/projects/personal/claude-config/install-acli.sh
acli jira auth login --site starktechgroup.atlassian.net
```

---

## Customization

To modify defaults, edit this file:
- **Base branch:** Change "dev" in Step 6.2 (default targets `dev`, not `main`)
- **Reviewers:** Change team names in Step 6.8
- **Branch patterns:** Modify regex in Step 2.2
- **Sensitive file patterns:** Add patterns to the exclusion list in Step 5.4
