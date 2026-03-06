---
description: "Review a pull request comprehensively. Usage: /review-pr <PR_NUMBER>. Performs code quality, security, style, and architecture reviews, then posts a GitHub review with inline comments. Assumes the PR is in the current repository."
allowed_tools: Read, Glob, Grep, Bash, Task, WebFetch, AskUserQuestion, mcp__github-cli__get_pull_request, mcp__github-cli__get_pull_request_files, mcp__github-cli__get_pull_request_status, mcp__github-cli__get_pull_request_reviews, mcp__github-cli__get_pull_request_comments, mcp__github-cli__get_file_contents, mcp__github-cli__create_pull_request_review
---

# PR Review Command

You are performing a comprehensive pull request review. The PR number is: **$ARGUMENTS**

## Step 1: Detect Repository

First, detect the current repository from git:

```bash
git remote get-url origin
```

Parse the output to extract `owner` and `repo`:
- SSH format: `git@github.com:owner/repo.git` -> owner, repo
- HTTPS format: `https://github.com/owner/repo.git` -> owner, repo

## Step 2: Gather PR Information

Use the GitHub MCP tools to collect PR data. Run these in parallel:

1. **Get PR details**: `mcp__github-cli__get_pull_request`
   - Extract: title, description, base branch, head branch, author

2. **Get changed files**: `mcp__github-cli__get_pull_request_files`
   - Extract: list of files with paths, status (added/modified/deleted), patch (diff)

3. **Get CI status**: `mcp__github-cli__get_pull_request_status`
   - Extract: overall status, individual check results

4. **Get existing reviews**: `mcp__github-cli__get_pull_request_reviews`
   - Extract: existing review summaries to avoid duplicate feedback

5. **Get existing comments**: `mcp__github-cli__get_pull_request_comments`
   - Extract: inline comments already posted

## Step 3: Detect & Analyze Screenshots

Scan the PR description for image URLs matching patterns like:
- `![alt text](url)`
- `<img src="url">`
- Raw image URLs ending in `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`
- GitHub user-attachment URLs: `https://github.com/user-attachments/assets/<uuid>`

For each screenshot found, download it using authenticated `curl` and analyze with the `Read` tool:

1. **Download** each image to a temp directory using GitHub auth:
   ```bash
   mkdir -p /tmp/pr-review-screenshots
   curl -sL -H "Authorization: token $(gh auth token)" "<image_url>" -o "/tmp/pr-review-screenshots/screenshot-<index>.png"
   ```
   Download all images in parallel when possible (multiple curl commands in one Bash call).

2. **Analyze** each downloaded image using the `Read` tool (which supports visual analysis of image files). When reading each screenshot, focus your analysis on:
   - What UI elements are visible
   - What state the application is in
   - Any errors, warnings, or notable visual elements
   - Whether this appears to be a before/after comparison

3. **Cleanup**: After analysis is complete, remove the temp directory:
   ```bash
   rm -rf /tmp/pr-review-screenshots
   ```

Collect results as `visual_analysis[]`. If no screenshots are found, set to empty array and move on.

## Step 3.5: Pre-flight Diff Size Check & File Filtering

### 3.5.1 Measure Diff Size

Get diff stats to assess PR size before loading content:

```bash
gh pr diff $PR_NUMBER --repo '<owner>/<repo>' --stat
```

Extract total files changed and total lines changed. Store as `$DIFF_FILE_COUNT` and `$DIFF_LINE_COUNT`.

### 3.5.2 Large PR Warning

If `$DIFF_FILE_COUNT > 200` OR `$DIFF_LINE_COUNT > 3000`:
- Warn the user:
  ```
  This PR is large ($DIFF_FILE_COUNT files, $DIFF_LINE_COUNT lines changed).
  Generated/vendor files will be auto-filtered. Review may be less thorough on remaining files.
  ```
- Use `AskUserQuestion` with options:
  - **Continue** — proceed with auto-filtering applied
  - **Abort** — stop the review

### 3.5.3 Auto-Exclude Generated & Vendor Files

Filter out files matching these patterns from the changed files list. These files add noise and waste agent context:

**Lock files:**
- `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
- `go.sum`
- `Pipfile.lock`, `poetry.lock`
- `Gemfile.lock`
- `Cargo.lock`
- `composer.lock`

**Vendor/dependency directories:**
- `vendor/`
- `node_modules/`
- `third_party/`

**Generated/build artifacts:**
- `*.min.js`, `*.min.css`
- `*.generated.*`, `*.gen.*`
- `dist/`, `build/`, `out/`
- `*.pb.go` (protobuf generated Go)
- `*.swagger.json`, `*.openapi.json`

**IDE/OS artifacts:**
- `.DS_Store`, `Thumbs.db`
- `.idea/`, `.vscode/` (unless PR explicitly changes IDE config)

Store excluded files as `$FILTERED_FILES[]` for reporting in the terminal summary. Continue with remaining files only.

## Step 4: Read File Diffs

Apply the exclusion list from Step 3.5.3 — skip any file in `$FILTERED_FILES[]`.

For each remaining changed file:
- **Deleted files**: Include only the path and status. No content needed.
- **Modified files**: Include the diff/patch only. Do NOT fetch full file content — sub-agents have Read/Glob/Grep tools to fetch full context when they need it.
- **Added files under 30KB**: Fetch full content via `mcp__github-cli__get_file_contents` from the head branch. These are new files that sub-agents need to see in full.
- **Added files over 30KB**: Include path and status only, note the size.
- **Binary files**: Skip entirely (images, compiled assets, etc.)

## Step 5: Compile Context JSON

Assemble the following data package for the review agents:

```json
{
  "pr_number": "<number>",
  "owner": "<owner>",
  "repo": "<repo>",
  "title": "<PR title>",
  "description": "<PR description>",
  "base_branch": "<base>",
  "head_branch": "<head>",
  "author": "<author>",
  "ci_status": "<passing|failing|pending>",
  "visual_analysis": [
    {
      "url": "<screenshot URL>",
      "description": "<what the screenshot shows>"
    }
  ],
  "files": [
    {
      "path": "path/to/file.ext",
      "status": "modified|added|deleted",
      "diff": "<patch content>",
      "content": "<full content for new files only, null otherwise>"
    }
  ],
  "existing_reviews": ["<summary of existing reviews>"],
  "existing_comments": ["<summary of existing inline comments>"]
}
```

## Step 6: Spawn 5 Review Agents in Parallel

Use the `Task` tool to invoke all 5 specialized agents simultaneously. Each receives the same context JSON.

**IMPORTANT**: Launch all 5 Task calls in a single message for parallel execution.

### Agent 1: pr-code-review
```
Review this PR for code quality issues.

<pr_context>
[Insert compiled JSON from Step 5]
</pr_context>

Return your findings as JSON with: summary, severity (approve|request_changes|comment),
findings object, and comments array. Each comment needs path, line, and body.
```

### Agent 2: pr-security-scan
```
Review this PR for security vulnerabilities.

<pr_context>
[Insert compiled JSON from Step 5]
</pr_context>

Return your findings as JSON with: summary, severity, risk_level, findings object,
and comments array. Each comment needs path, line, and body.
```

### Agent 3: pr-style-check
```
Review this PR for style and convention issues.

<pr_context>
[Insert compiled JSON from Step 5]
</pr_context>

Return your findings as JSON with: summary, severity (approve|comment only),
consistency_score, findings object, and comments array.
```

### Agent 4: pr-architect-review
```
Review this PR for architectural concerns.

<pr_context>
[Insert compiled JSON from Step 5]
</pr_context>

Return your findings as JSON with: summary, severity, architecture_impact,
findings object, and comments array.
```

### Agent 5: pr-motivation-analysis
```
Analyze the motivations and design intent behind this PR.

<pr_context>
[Insert compiled JSON from Step 5]
</pr_context>

Extract any Jira ticket key from the PR title or branch name (e.g., "OP-3088" from
"feature/OP-3088_remove-double-scrollbars-platform-wide") and fetch the ticket for
additional context. Explore the codebase for plan files and related context.

Return your analysis as a structured markdown narrative with sections for:
why the PR exists, what it solves for users, design philosophy, trade-offs,
strategic context, and confidence level.
```

## Step 7: Merge Results & Determine Verdict

### Parse Results
Extract the JSON response from each review agent. If an agent's response isn't valid JSON, extract what you can and note the parsing issue. The motivation analysis agent returns markdown prose (not JSON) — store it verbatim for inclusion in the terminal summary.

### Merge Inline Comments
Combine all comments from all 4 agents into a single array. Deduplicate comments that target the same file+line and address the same issue (keep the more detailed one).

Cap total inline comments at 20. If more than 20, prioritize:
1. Security findings (highest priority)
2. Code quality blocking issues
3. Architecture concerns
4. Code quality suggestions
5. Style comments (lowest priority)

### Determine Verdict

**IMPORTANT: Style agent findings do NOT affect the verdict.** Only code, security, and architecture agents determine the final event.

Apply this logic using only pr-code-review, pr-security-scan, and pr-architect-review:

1. If ANY of these 3 agents returns `request_changes` -> final event is `REQUEST_CHANGES`
2. If ALL 3 agents return `approve` -> final event is `APPROVE`
3. Otherwise -> final event is `COMMENT`

### Compile Review Body

```markdown
## PR Review Summary

**Verdict**: [Approved | Changes Requested | Reviewed with Comments]

### Code Quality
[Summary from pr-code-review]

### Security
[Summary from pr-security-scan - include risk level]

### Architecture
[Summary from pr-architect-review - include impact level]

### Style & Conventions
[Summary from pr-style-check - note: style findings do not affect verdict]

---
*Automated review by Claude Code*
```

## Step 8: Post to GitHub with Fallback

### Attempt 1: Direct MCP Post

Use `mcp__github-cli__create_pull_request_review` directly:

```json
{
  "owner": "<owner>",
  "repo": "<repo>",
  "pull_number": "<pr_number>",
  "body": "<compiled review body>",
  "event": "APPROVE|REQUEST_CHANGES|COMMENT",
  "comments": [<merged inline comments>]
}
```

If this succeeds, record: `post_method = "MCP"`, `post_success = true`.

### Attempt 1b: MCP Retry Without Inline Comments (Line Resolution Fallback)

If Attempt 1 fails with an error mentioning invalid line, position, or diff — this means one or more inline comments couldn't be mapped to the diff. Do NOT fall through to CLI yet. Instead:

1. Remove ALL inline comments from the request
2. Append them to the review body as a consolidated list:
   ```markdown
   ---
   ### Inline Comments (line resolution failed)
   - **path/to/file.ext:42** — [Category] Comment body
   - **path/to/file.ext:87** — [Category] Comment body
   ```
3. Retry `mcp__github-cli__create_pull_request_review` with just the body (no `comments` array)

If this succeeds, record: `post_method = "MCP (comments inlined)"`, `post_success = true`.

### Attempt 2: gh CLI Fallback

If MCP fails, fall back to `gh pr review` via Bash. Since the CLI doesn't support inline comments, append them to the body:

```bash
# Write body to temp file to handle multiline + special chars
cat > /tmp/pr-review-body.md <<'REVIEW_EOF'
<review body>

---
### Inline Comments (could not post individually)

- **path/to/file.ext:42** — [Category] Brief description
REVIEW_EOF

gh pr review <pr_number> --repo '<owner>/<repo>' --<event_flag> --body-file /tmp/pr-review-body.md
rm -f /tmp/pr-review-body.md
```

Where `<event_flag>` is: `APPROVE` -> `--approve`, `REQUEST_CHANGES` -> `--request-changes`, `COMMENT` -> `--comment`.

If CLI succeeds, record: `post_method = "CLI fallback (gh)"`, `post_success = true`.

### Attempt 3: Ask User to Intervene

**Never silently fail.** If both MCP and CLI fail, use `AskUserQuestion` to surface the failure and let the user decide:

Tell the user:
- Which methods failed (MCP, gh CLI) and the error messages for each
- The review is ready but could not be posted

Offer these options:
- **"Retry after I fix auth"** — user fixes credentials/tokens/auth, then retry the MCP → CLI sequence from the top
- **"Post manually"** — output the full review body and all inline comments to the terminal in copy-pasteable format
- **"Skip posting"** — continue to terminal summary without posting (record `post_method = "none"`)

If the user chooses to retry, go back to Attempt 1 and try the full sequence again. Only record `post_success = false` if the user explicitly chooses to skip.

## Step 8b: Atlassian MCP Fallback Pattern

If any step in this command uses Atlassian MCP tools (e.g., `mcp__plugin_atlassian_atlassian__getJiraIssue`, `mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql`, or any `mcp__plugin_atlassian_*` tool) and the MCP call fails:

### Atlassian Fallback Sequence

1. **Attempt acli CLI**: Fall back to the Atlassian CLI (`acli`) via Bash. Common equivalents:
   - Jira issue fetch: `acli jira --action getIssue --issue <KEY>`
   - Jira search: `acli jira --action getIssueList --jql '<JQL>'`
   - Jira add comment: `acli jira --action addComment --issue <KEY> --comment '<text>'`
   - Jira transition: `acli jira --action transitionIssue --issue <KEY> --transition '<name>'`
   - Confluence page: `acli confluence --action getPageSource --space <SPACE> --title '<title>'`

2. **Ask user to intervene**: If acli also fails, use `AskUserQuestion`:
   - Tell the user which Atlassian operation failed and the errors from both MCP and acli
   - Offer options:
     - **"Retry after I fix auth"** — user re-authenticates, then retry MCP → acli
     - **"Skip this step"** — continue without the Atlassian data
     - **"Provide data manually"** — user pastes the needed information directly

## Step 9: Rich Terminal Summary

Output a detailed summary to the terminal:

```markdown
## PR Review Complete: #<number> - <title>

**Verdict**: APPROVED / CHANGES REQUESTED / COMMENTED
**Posted to GitHub**: Yes (MCP) | Yes (CLI fallback) | Skipped (user choice) | Failed

### Files Changed (<n> files)
- [A] path/to/new-file.ts — <brief description of what this file adds>
- [M] path/to/changed-file.ts — <brief description of what changed>
- [D] path/to/removed-file.ts — Deleted

### Review Findings
| Category     | Verdict  | Blocking | Comments |
|--------------|----------|----------|----------|
| Code Quality | APPROVE  | 0        | 2        |
| Security     | COMMENT  | 0        | 1        |
| Architecture | APPROVE  | 0        | 0        |
| Style        | COMMENT  | n/a      | 3        |

### Key Findings
**Code**: <1-2 sentence summary>
**Security**: <1-2 sentence summary> [risk: LOW/MEDIUM/HIGH/CRITICAL]
**Architecture**: <1-2 sentence summary> [impact: NONE/LOW/MEDIUM/HIGH]
**Style**: <1-2 sentence summary>

### Motivation & Intent Analysis
[Insert the full narrative from the pr-motivation-analysis agent verbatim.
This section is subjective — an educated guess at the motivations, design rationale,
and strategic context behind the changes, informed by ticket context, code patterns,
and project knowledge.]

### Filtered Files: <n>
- <list of auto-excluded files (lock files, vendor, generated, etc.)>
(omit this section if no files were filtered)

### Screenshots Analyzed: <n>
- Screenshot 1: <description of what it shows>
(omit this section if no screenshots)

### Inline Comments Posted: <n>
- path/to/file.ts:42 — [Code] Brief description
- path/to/file.ts:87 — [Security] Brief description
(list all posted inline comments)
```

If posting failed (Step 8 Attempt 3), also output the full review body so it can be manually posted or referenced.

## Important Notes

- If no PR number is provided, ask the user for it
- If the repository cannot be detected, ask the user for owner/repo
- Skip binary files (images, compiled assets) when reading content
- Report any errors clearly (PR not found, permission denied, etc.)
- If a review agent fails or returns garbage, note it in the summary but continue with the other agents' results
- Never block a PR solely based on style findings
- The **Motivation & Intent Analysis** is terminal-only — it is NOT included in the GitHub review body (it's subjective and for the reviewer's benefit, not the PR author's)
- **Never silently fail on posting** — if MCP and CLI both fail for GitHub or Atlassian, always ask the user to intervene via `AskUserQuestion`
- For Atlassian MCP failures, always try `acli` CLI before asking the user (see Step 8b)
