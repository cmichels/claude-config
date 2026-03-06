---
description: "Comprehensive code review for local branch changes. Usage: /review-local [base_branch]. Reviews code quality, security, architecture, tests, smells, and validates against Jira requirements. Outputs to ./reviews/<branch>-review.md"
allowed_tools: Read, Glob, Grep, Bash, Task, Write, AskUserQuestion, mcp__atlassian__getJiraIssue, mcp__atlassian__search, mcp__atlassian__fetch
---

# Local Branch Code Review

You are performing a comprehensive code review on local branch changes. Base branch: **$ARGUMENTS** (defaults to `main` if not specified).

## Overview

This review will:
1. Analyze all changes against the base branch
2. Fetch related Jira ticket context
3. Check for relevant implementation plans
4. Run 6 specialized review agents in parallel
5. Execute static analysis tools
6. Compile findings into a detailed markdown report
7. Output to `./reviews/<branch_name>-review.md`

---

## Step 1: Detect Branch and Changes

Run these git commands to gather context:

```bash
# Get current branch name
git branch --show-current

# Get the base branch (use argument or default to main)
BASE_BRANCH="${ARGUMENTS:-main}"

# Verify base branch exists
git rev-parse --verify $BASE_BRANCH 2>/dev/null || git rev-parse --verify master 2>/dev/null

# Get list of changed files
git diff --name-status $BASE_BRANCH...HEAD

# Get full diff for review
git diff $BASE_BRANCH...HEAD

# Get commit history on this branch
git log --oneline $BASE_BRANCH..HEAD
```

Store:
- `branch_name`: Current branch
- `base_branch`: Target base branch
- `changed_files`: List of added/modified/deleted files
- `diff_content`: Full diff
- `commits`: List of commits on this branch

---

## Step 2: Extract Jira Ticket

Parse the branch name for Jira ticket patterns:

**Pattern matching (regex):**
- `^(?:feature|bug|fix|hotfix|chore)?/?([A-Z]+-\d+)`
- `([A-Z]+-\d+)` anywhere in branch name

**Examples:**
- `feature/PROJ-123-add-login` -> `PROJ-123`
- `PROJ-456/fix-bug` -> `PROJ-456`
- `bug/PROJ-789-fix-crash` -> `PROJ-789`

Also check commit messages for Jira references:
```bash
git log --oneline $BASE_BRANCH..HEAD | grep -oE '[A-Z]+-[0-9]+'
```

If ticket found, fetch details using `mcp__atlassian__search` or `mcp__atlassian__getJiraIssue`:
- Summary
- Description
- Acceptance criteria
- Status
- Priority
- Linked issues

If no ticket found, note this in the review and continue.

---

## Step 3: Find Relevant Plans

Search for implementation plans in `~/.claude/plans/`:

```bash
# List recent plans
ls -lt ~/.claude/plans/*.md | head -10
```

Then use Grep to search plan contents for:
- Branch name references
- Jira ticket references
- File paths that match changed files
- Related feature/component names

Read the most relevant plan(s) and extract:
- Intended implementation approach
- Acceptance criteria from planning
- Design decisions made

---

## Step 4: Read Changed Files

For each changed file (not deleted):

1. Read the full current content using the Read tool
2. Store file content with its diff for context

Skip binary files (images, compiled assets).
Note files that are too large (>100KB).

Build a files array:
```json
{
  "files": [
    {
      "path": "path/to/file.go",
      "status": "modified|added|deleted",
      "diff": "<patch content>",
      "content": "<full file content>",
      "is_test": true|false
    }
  ]
}
```

---

## Step 5: Launch Review Agents in Parallel

Use the Task tool to invoke these 6 agents simultaneously:

### Agent 1: pr-code-review
```
Review this code for quality issues.

Branch: <branch_name>
Jira: <ticket_key> - <summary>
Acceptance Criteria: <criteria>

Files:
<for each file: path, status, diff, content>

Return JSON with: summary, severity, findings (blocking, suggestions, positives), comments
```

### Agent 2: pr-security-scan
```
Perform security analysis on these changes.

Branch: <branch_name>

Files:
<for each file: path, diff, content>

Return JSON with: summary, severity, risk_level, findings, comments
```

### Agent 3: pr-architect-review
```
Review architectural implications of these changes.

Branch: <branch_name>
Jira Context: <ticket summary>

Files:
<for each file: path, diff, content>

Return JSON with: summary, severity, architecture_impact, findings, comments
```

### Agent 4: pr-style-check
```
Check style and convention adherence.

Files:
<for each file: path, diff, content>

Return JSON with: summary, severity, consistency_score, findings, comments
```

### Agent 5: test-coverage-review
```
Analyze test coverage for these changes.

Files:
<for each file: path, is_test, diff, content>

Focus on missing tests, edge cases, test quality.

Return JSON with: summary, severity, coverage_assessment, missing_tests, suggested_tests, comments
```

### Agent 6: code-smell-detector
```
Detect code smells and anti-patterns.

Files:
<for each file: path, diff, content>

Return JSON with: summary, smell_count, smells_found, refactoring_suggestions, comments
```

---

## Step 6: Run Static Analysis

Execute language-appropriate linters based on files changed:

### For Go files (.go):
```bash
# Check if golangci-lint is available
which golangci-lint && golangci-lint run --new-from-rev=$BASE_BRANCH --out-format=line-number 2>&1 | head -50

# Run go vet
go vet ./... 2>&1 | head -20

# Check gopls diagnostics if LSP available
```

### For TypeScript/JavaScript files (.ts, .tsx, .js, .jsx):
```bash
# Check if eslint config exists and run
[ -f .eslintrc* ] || [ -f eslint.config.* ] && npx eslint --format=stylish <changed_files> 2>&1 | head -50

# TypeScript compiler check
[ -f tsconfig.json ] && npx tsc --noEmit 2>&1 | head -30
```

### For Python files (.py):
```bash
# Try ruff first (fast), fall back to flake8
which ruff && ruff check <changed_files> 2>&1 | head -50 || \
which flake8 && flake8 <changed_files> 2>&1 | head -50

# Type checking
[ -f pyproject.toml ] && which mypy && mypy <changed_files> 2>&1 | head -30
```

### For Java files (.java):
```bash
# Maven check
[ -f pom.xml ] && mvn compile -q 2>&1 | head -30
```

---

## Step 7: Validate Against Requirements

If Jira ticket was found:

1. **Extract acceptance criteria** from ticket description
2. **Map criteria to code changes** - does each criterion have corresponding implementation?
3. **Identify gaps** - requirements not addressed
4. **Flag scope creep** - changes beyond ticket scope
5. **Note completeness** - is this ready for the ticket to be marked done?

Use this analysis to inform the "Jira Alignment" section.

---

## Step 8: User Feedback (Conditional)

If any of these conditions exist, use AskUserQuestion:

1. **Critical security issues** - Confirm intent before proceeding
2. **Ambiguous requirements** - Clarify what was intended
3. **Missing context** - Ask about business logic
4. **Conflicting patterns** - Which approach is preferred?

Example questions:
- "The authentication flow differs from the ticket description. Is this intentional?"
- "There are 3 critical security findings. Should I proceed with the full review?"

---

## Step 9: Determine Verdict

Based on all agent results:

**Ready for PR** if:
- No blocking issues from any agent
- Security risk level is LOW or NONE
- Test coverage is ADEQUATE
- No critical code smells

**Needs Changes** if:
- Any blocking issues exist
- Security risk is MEDIUM or higher
- Test coverage is INSUFFICIENT
- Major code smells detected
- Jira requirements not met

**Requires Discussion** if:
- Architectural decisions need team input
- Significant scope changes from requirements
- Trade-offs that need product decision
- Questions unanswered by agents

---

## Step 10: Compile Review Document

Create the review markdown document:

```markdown
# Code Review: <branch_name>

**Date:** <current_date>
**Reviewer:** Claude Code
**Base Branch:** <base_branch>
**Jira Ticket:** <PROJ-123> - <Summary> | _No ticket detected_

## Executive Summary

<2-3 sentence overall assessment combining all agent findings>

**Verdict:** <Ready for PR | Needs Changes | Requires Discussion>

**Stats:**
- Files Changed: <count>
- Lines Added: <count>
- Lines Removed: <count>
- Blocking Issues: <count>
- Total Findings: <count>

---

## Jira Alignment

<If ticket found, show requirements coverage>

### Requirements Coverage
| Requirement | Status | Evidence |
|-------------|--------|----------|
| AC 1 | ✅ Implemented | `file.go:45` |
| AC 2 | ⚠️ Partial | Missing error case |
| AC 3 | ❌ Not found | No implementation |

### Gaps Identified
<List any missing requirements>

### Scope Notes
<Any out-of-scope changes>

---

## Code Quality

### Summary
<From pr-code-review agent>

### Blocking Issues
<list with file:line references>

### Suggestions
<non-blocking improvements>

### Positive Observations
<good practices noted>

---

## Security Analysis

### Risk Level: <CRITICAL|HIGH|MEDIUM|LOW|NONE>

### Summary
<From pr-security-scan agent>

### Findings by Severity

#### Critical
<list>

#### High
<list>

#### Medium/Low
<list>

### Recommendations
<security improvements>

---

## Architecture & Design

### Impact Level: <HIGH|MEDIUM|LOW|NONE>

### Summary
<From pr-architect-review agent>

### Concerns
<architectural issues>

### Suggestions
<design improvements>

### Questions for Author
<points needing clarification>

---

## Code Smells & Anti-Patterns

### Summary
<From code-smell-detector agent>

**Smell Count:** Critical: X | Major: Y | Minor: Z

### Smells Detected
| Type | Severity | Location | Description |
|------|----------|----------|-------------|
| Long Method | Major | `file.go:45-120` | 75 lines with 4 nesting levels |

### Refactoring Opportunities
<suggested improvements with techniques>

### Technical Debt
<accumulated debt observations>

---

## Test Coverage

### Assessment: <ADEQUATE|NEEDS_IMPROVEMENT|INSUFFICIENT>

### Summary
<From test-coverage-review agent>

### Missing Tests
| Source File | Missing Coverage | Priority |
|-------------|-----------------|----------|
| `user.go` | No test file | High |

### Missing Edge Cases
<specific scenarios not tested>

### Suggested Test Cases
<concrete tests to add>

---

## Style & Conventions

### Consistency: <HIGH|MEDIUM|LOW>

### Summary
<From pr-style-check agent>

### Notes
<style observations - never blocking>

---

## Static Analysis Results

### Linter Findings

#### <tool_name>
```
<linter output>
```

### Summary
- Errors: <count>
- Warnings: <count>
- Info: <count>

---

## Detailed Findings by File

<For each file with findings>

### `<file_path>`

| Line | Category | Severity | Issue | Suggestion |
|------|----------|----------|-------|------------|
| 42 | Security | High | SQL injection risk | Use parameterized query |
| 67 | Code | Medium | Unhandled error | Add error check |

---

## Action Items

### 🚫 Must Fix (Blocking)
- [ ] <Issue 1> - `file.go:42`
- [ ] <Issue 2> - `file.go:67`

### ⚠️ Should Fix (Recommended)
- [ ] <Suggestion 1>
- [ ] <Suggestion 2>

### 💡 Consider (Optional)
- [ ] <Enhancement 1>
- [ ] <Enhancement 2>

---

## Plan Reference

<If relevant plan found>

### Related Plan
**File:** `~/.claude/plans/<plan_name>.md`

<Relevant excerpts>

---

## Commits Reviewed

```
<commit_log>
```

---

*Generated by Claude Code Local Review*
*Command: /review-local*
*Timestamp: <ISO_timestamp>*
```

---

## Step 11: Create Output Directory and Write Review

```bash
# Create reviews directory if it doesn't exist
mkdir -p ./reviews

# Sanitize branch name for filename (replace / with -)
SAFE_BRANCH=$(echo "<branch_name>" | tr '/' '-')
```

Use the Write tool to save the review to:
`./reviews/<SAFE_BRANCH>-review.md`

---

## Step 12: Summary Output

After writing the review file, output to the user:

```
✅ Code Review Complete

📄 Review saved to: ./reviews/<branch>-review.md

📊 Summary:
   Verdict: <Ready for PR | Needs Changes | Requires Discussion>
   Files Reviewed: <count>
   Blocking Issues: <count>
   Total Findings: <count>

🔍 Key Highlights:
   - <Most important finding 1>
   - <Most important finding 2>
   - <Most important finding 3>

📋 Next Steps:
   <Based on verdict, suggest next actions>

To view the full review:
   cat ./reviews/<branch>-review.md

   # Or open in your editor:
   nvim ./reviews/<branch>-review.md
```

---

## Error Handling

- If not in a git repository, inform user and exit
- If no changes detected, inform user and exit
- If base branch doesn't exist, try `master`, then ask user
- If Jira MCP unavailable, continue without ticket context
- If any agent fails, note in review and continue with others
- If static analysis tools not installed, skip with note

---

## Important Notes

- This review is for local pre-PR quality assurance
- The review file can be used as PR description basis
- All findings should be actionable with specific locations
- Be constructive - every issue should have a suggestion
- Acknowledge good code and patterns
- Consider context - internal tools vs public APIs have different standards
