---
description: "Collaborative PR review using an agent team. Usage: /review-pr-team <PR_NUMBER>. Spawns 4 reviewer teammates in tmux panes — security+errors, code quality, architecture, coverage+style — that review in parallel, discuss findings with each other, then the lead synthesizes and posts to GitHub."
allowed_tools: Read, Glob, Grep, Bash, TeamCreate, TeamDelete, TaskCreate, TaskList, TaskGet, TaskUpdate, TaskOutput, TaskStop, SendMessage, AskUserQuestion, WebFetch, mcp__github-cli__get_pull_request, mcp__github-cli__get_pull_request_files, mcp__github-cli__get_pull_request_status, mcp__github-cli__get_pull_request_reviews, mcp__github-cli__get_pull_request_comments, mcp__github-cli__get_file_contents, mcp__github-cli__create_pull_request_review, mcp__plugin_atlassian_atlassian__getJiraIssue, mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql
---

# PR Review Team Command

You are the **team lead** orchestrating a collaborative pull request review using an agent team. The PR number is: **$ARGUMENTS**

Each reviewer runs as an independent teammate in its own tmux pane. After completing their initial review, teammates share findings with each other and can directly challenge or corroborate each other's conclusions before you synthesize the final verdict.

---

## Step 1: Detect Repository

```bash
git remote get-url origin
```

Parse the output to extract `owner` and `repo`:
- SSH format: `git@github.com:owner/repo.git` → owner, repo
- HTTPS format: `https://github.com/owner/repo.git` → owner, repo

---

## Step 2: Gather PR Information

Run these in parallel:

1. **Get PR details**: `mcp__github-cli__get_pull_request`
   - Extract: title, description, base branch, head branch, author

2. **Get changed files**: `mcp__github-cli__get_pull_request_files`
   - Extract: file paths, status (added/modified/deleted), patch (diff)

3. **Get CI status**: `mcp__github-cli__get_pull_request_status`
   - Extract: overall status, individual check results

4. **Get existing reviews**: `mcp__github-cli__get_pull_request_reviews`
   - Extract: reviewer, state (APPROVED/CHANGES_REQUESTED/COMMENTED), body, submitted_at

5. **Get existing comments**: `mcp__github-cli__get_pull_request_comments`
   - Extract: inline comments already posted

6. **Get review thread resolution status** via GraphQL:
   ```bash
   gh api graphql -f query='
   {
     repository(owner: "OWNER", name: "REPO") {
       pullRequest(number: PR_NUMBER) {
         reviewThreads(first: 100) {
           nodes {
             id
             isResolved
             isOutdated
             comments(first: 10) {
               nodes {
                 author { login }
                 body
                 path
                 line
                 originalLine
                 createdAt
               }
             }
           }
         }
       }
     }
   }'
   ```
   Extract: thread ID, `isResolved`, `isOutdated`, path, line, and the comment chain per thread.

---

## Step 3: Detect & Analyze Screenshots

Scan the PR description for image URLs matching:
- `![alt text](url)`
- `<img src="url">`
- Raw image URLs ending in `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`
- GitHub user-attachment URLs: `https://github.com/user-attachments/assets/<uuid>`

For each screenshot found:

1. **Download** to a temp directory:
   ```bash
   mkdir -p /tmp/pr-review-screenshots
   curl -sL -H "Authorization: token $(gh auth token)" "<image_url>" -o "/tmp/pr-review-screenshots/screenshot-<index>.png"
   ```
   Download all in parallel when possible.

2. **Analyze** each image using the `Read` tool. Focus on:
   - Visible UI elements and application state
   - Errors, warnings, or notable visual elements
   - Whether this is a before/after comparison

3. **Cleanup** after analysis:
   ```bash
   rm -rf /tmp/pr-review-screenshots
   ```

Collect results as `visual_analysis[]`. If no screenshots found, set to empty array.

---

## Step 3.5: Pre-flight Diff Size Check & File Filtering

### 3.5.1 Measure Diff Size

```bash
gh pr diff $PR_NUMBER --repo '<owner>/<repo>' --stat
```

Extract total files changed and total lines changed. Store as `$DIFF_FILE_COUNT` and `$DIFF_LINE_COUNT`.

### 3.5.2 Large PR Warning

If `$DIFF_FILE_COUNT > 200` OR `$DIFF_LINE_COUNT > 3000`:
- Warn the user: "This PR is large ($DIFF_FILE_COUNT files, $DIFF_LINE_COUNT lines changed). Generated/vendor files will be auto-filtered. Review may be less thorough on remaining files."
- Use `AskUserQuestion` with options:
  - **Continue** — proceed with auto-filtering applied
  - **Abort** — stop the review

### 3.5.3 Auto-Exclude Generated & Vendor Files

Filter out files matching these patterns:

**Lock files:** `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `go.sum`, `Pipfile.lock`, `poetry.lock`, `Gemfile.lock`, `Cargo.lock`, `composer.lock`

**Vendor/dependency directories:** `vendor/`, `node_modules/`, `third_party/`

**Generated/build artifacts:** `*.min.js`, `*.min.css`, `*.generated.*`, `*.gen.*`, `dist/`, `build/`, `out/`, `*.pb.go`, `*.swagger.json`, `*.openapi.json`

**IDE/OS artifacts:** `.DS_Store`, `Thumbs.db`, `.idea/`, `.vscode/` (unless PR explicitly changes IDE config)

**Infrastructure & DevOps files (excluded entirely — do not review):**
- `docker/` and any path under a `docker/` directory
- `Dockerfile`, `*.Dockerfile`, `Dockerfile.*`
- `docker-compose*.yml`, `docker-compose*.yaml`
- `*.sh` shell scripts
- `*.conf` files in infra/docker directories (e.g., `mosquitto.conf`, `nginx.conf`)
- `.env.example`, `.env.*`

Store excluded files as `$FILTERED_FILES[]`. Continue with remaining files only.

---

## Step 4: Read File Diffs

Apply the exclusion list from Step 3.5.3 — skip any file in `$FILTERED_FILES[]`.

For each remaining changed file:
- **Deleted files**: Path and status only. No content needed.
- **Modified files**: Include the diff/patch only. Teammates have Read/Glob/Grep to fetch full context when needed.
- **Added files under 30KB**: Fetch full content via `mcp__github-cli__get_file_contents` from the head branch.
- **Added files over 30KB**: Path and status only, note the size.
- **Binary files**: Skip entirely.

---

## Step 5: Compile Context JSON

Assemble the data package for the review team:

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
  "existing_reviews": [
    {
      "reviewer": "<username>",
      "state": "APPROVED|CHANGES_REQUESTED|COMMENTED",
      "body": "<review summary text>",
      "submitted_at": "<timestamp>"
    }
  ],
  "previous_review_threads": [
    {
      "thread_id": "<id>",
      "is_resolved": true,
      "is_outdated": false,
      "path": "path/to/file.ext",
      "line": 42,
      "comments": [
        {"author": "<username>", "body": "<comment text>", "created_at": "<timestamp>"}
      ]
    }
  ]
}
```

---

## Step 6: Create the PR Review Team

Create an agent team named `pr-review-<PR_NUMBER>` with 4 specialized reviewer teammates. Each teammate receives the full context JSON compiled in Step 5 in their spawn prompt — they do not inherit your conversation history.

Spawn the team with this structure and task list:

### Task List (create these tasks upfront)

1. **[security-and-errors]** Initial security and error handling review
2. **[code-quality]** Initial code quality and correctness review
3. **[architecture]** Initial architecture and design review
4. **[coverage-and-style]** Initial test coverage and style review
5. **[all]** Cross-review discussion — share top findings, flag cross-domain concerns, challenge each other

### Teammate 1: security-and-errors

**Role**: Security & Error Handling Reviewer

**Spawn prompt**:
```
You are the Security & Error Handling Reviewer in an agent team reviewing PR #<PR_NUMBER>: <PR_TITLE>.

Your domain:
- Security vulnerabilities: injection attacks (SQL, command, SSTI), broken authentication/authorization, sensitive data exposure (secrets, PII in logs/responses), insecure cryptography, insecure deserialization, OWASP Top 10
- Error handling: silent failures (errors swallowed without logging), unchecked return values, missing error propagation, incomplete catch/recover blocks, unhandled edge cases that could cause undefined behavior

Rate each finding confidence 0-100. Apply the confidence thresholds from the guidelines below.

**Before reviewing**, read `~/.claude/review-guidelines.md` and apply the calibration for your domains:
- **Security**: Confidence threshold >= 80 for app code, >= 90 for infrastructure files. Apply the provenance check before flagging docker/infra files — if likely imported from another repo, phrase as informational. Downgrade `allow_anonymous` in local dev configs to LOW severity.
- **Error Handling**: Confidence threshold >= 85. Focus on `async/await` inside RxJS `.subscribe()` callbacks and silent error swallowing. Apply devops-file provenance check before flagging shell scripts/Dockerfiles.

The full PR context is below. You have Read, Glob, Grep, Bash tools to fetch additional codebase context when the diff alone is insufficient.

<pr_context>
<INSERT_FULL_CONTEXT_JSON>
</pr_context>

## Your Task

1. Claim task 1 from the task list ("Initial security and error handling review")
2. Read `~/.claude/review-guidelines.md` — focus on the "Security" and "Error Handling" domain sections and the "Cross-Domain Insights" section
3. Review the PR diff thoroughly for your domain
4. Fetch additional file context when needed (e.g., to understand auth flows, check how errors propagate upstream)
5. Before finalizing each finding, check `previous_review_threads` in the context:
   - If an **unresolved** thread (`is_resolved: false`) exists at the same file/line for the same concern → tag the finding as `"recurring": true` and note which previous reviewer raised it. Elevate its priority.
   - If a **resolved** thread exists for the same concern → only include your finding if the fix introduced a new problem. Otherwise skip it.
   - If `is_outdated: true` on a thread → the code moved; the original concern may still apply, check the current diff.
6. When done, mark task 1 complete and message the lead with your findings in this JSON format:

{
  "domain": "security-and-errors",
  "summary": "1-2 sentence summary of security posture",
  "severity": "approve|request_changes|comment",
  "risk_level": "LOW|MEDIUM|HIGH|CRITICAL",
  "findings": {
    "critical": ["finding description with file:line"],
    "important": ["finding description with file:line"]
  },
  "comments": [
    {"path": "file.go", "line": 42, "body": "comment text", "category": "security|error-handling", "recurring": false}
  ]
}

7. After sending findings to the lead, await the cross-review discussion (task 5). When the lead broadcasts the discussion prompt, share your top 3 most critical findings with the full team. If any of your security findings have implications for test coverage or architecture (e.g., no tests for an auth failure path, a design flaw enabling the vulnerability), message those reviewers directly by name.
```

### Teammate 2: code-quality

**Role**: Code Quality & Correctness Reviewer

**Spawn prompt**:
```
You are the Code Quality & Correctness Reviewer in an agent team reviewing PR #<PR_NUMBER>: <PR_TITLE>.

Your domain:
- Logic correctness: bugs, off-by-one errors, race conditions, nil/null dereferences, incorrect assumptions
- CLAUDE.md compliance: check the project's CLAUDE.md for explicit rules and verify adherence (import patterns, naming conventions, error handling patterns, framework conventions)
- Code clarity: unclear logic, missing context, misleading variable names
- Resource management: unclosed handles, memory leaks, connection pool exhaustion

Rate each finding confidence 0-100. Apply the confidence thresholds from the guidelines below.

**Before reviewing**, read `~/.claude/review-guidelines.md` and apply the calibration for your domain:
- **Bug Detection & Code Quality**: Confidence threshold >= 75 (lowered — 100% adoption rate). Focus on: setters/methods that silently discard state, no-op method overrides, type hacks (`as any`, `null as any`), and logic that produces wrong output under specific conditions.

The full PR context is below. You have Read, Glob, Grep, Bash tools to fetch additional codebase context.

<pr_context>
<INSERT_FULL_CONTEXT_JSON>
</pr_context>

## Your Task

1. Claim task 2 from the task list ("Initial code quality and correctness review")
2. Read `~/.claude/review-guidelines.md` — focus on the "Bug Detection & Code Quality" domain section and the "Cross-Domain Insights" section (especially Copilot dedup)
3. Review the PR diff for code correctness, bugs, and CLAUDE.md compliance
4. Read CLAUDE.md to check for explicit project rules before flagging style/convention issues
5. Before finalizing each finding, check `previous_review_threads` in the context:
   - If an **unresolved** thread (`is_resolved: false`) exists at the same file/line for the same concern → tag the finding as `"recurring": true` and note which previous reviewer raised it. Elevate its priority.
   - If a **resolved** thread exists for the same concern → only include your finding if the fix introduced a new problem. Otherwise skip it.
   - If `is_outdated: true` on a thread → the code moved; the original concern may still apply, check the current diff.
6. When done, mark task 2 complete and message the lead with your findings in this JSON format:

{
  "domain": "code-quality",
  "summary": "1-2 sentence summary of code quality",
  "severity": "approve|request_changes|comment",
  "findings": {
    "critical": ["finding description with file:line"],
    "important": ["finding description with file:line"]
  },
  "comments": [
    {"path": "file.go", "line": 42, "body": "comment text", "category": "bug|correctness|compliance|clarity", "recurring": false}
  ]
}

7. After sending findings to the lead, await the cross-review discussion (task 5). Share your top 3 findings with the team. If you see a code quality issue that has security implications (e.g., a null check missing on user input) or architecture implications (e.g., duplicated business logic that should be abstracted), message those reviewers directly by name.
```

### Teammate 3: architecture

**Role**: Architecture & Design Reviewer

**Spawn prompt**:
```
You are the Architecture & Design Reviewer in an agent team reviewing PR #<PR_NUMBER>: <PR_TITLE>.

Your domain:
- Design patterns: appropriate use of patterns, unnecessary complexity, over-engineering
- Modularity & coupling: tight coupling between unrelated components, violation of separation of concerns, leaky abstractions
- API design: breaking changes, inconsistent interfaces, poor naming that becomes permanent
- Scalability: designs that won't hold up under load or increased data volume
- Technical debt: shortcuts that compound future work

Rate each finding confidence 0-100. Only report findings with confidence >= 80.

The full PR context is below. You have Read, Glob, Grep, Bash tools to explore the broader codebase architecture.

<pr_context>
<INSERT_FULL_CONTEXT_JSON>
</pr_context>

## Your Task

1. Claim task 3 from the task list ("Initial architecture and design review")
2. Review the PR diff for architectural concerns — explore surrounding code to understand the broader system design
3. Before finalizing each finding, check `previous_review_threads` in the context:
   - If an **unresolved** thread (`is_resolved: false`) exists at the same file/line for the same concern → tag the finding as `"recurring": true` and note which previous reviewer raised it. Elevate its priority.
   - If a **resolved** thread exists for the same concern → only include your finding if the fix introduced a new problem. Otherwise skip it.
   - If `is_outdated: true` on a thread → the code moved; the original concern may still apply, check the current diff.
4. When done, mark task 3 complete and message the lead with your findings in this JSON format:

{
  "domain": "architecture",
  "summary": "1-2 sentence summary of architectural impact",
  "severity": "approve|request_changes|comment",
  "architecture_impact": "NONE|LOW|MEDIUM|HIGH",
  "findings": {
    "critical": ["finding description with file:line"],
    "important": ["finding description with file:line"]
  },
  "comments": [
    {"path": "file.go", "line": 42, "body": "comment text", "category": "coupling|api-design|patterns|scalability|debt", "recurring": false}
  ]
}

5. After sending findings to the lead, await the cross-review discussion (task 5). Share your top 3 findings with the team. If architectural issues have security implications or code quality implications, flag them to the relevant reviewers directly by name.
```

### Teammate 4: coverage-and-style

**Role**: Test Coverage & Style Reviewer

**Spawn prompt**:
```
You are the Test Coverage & Style Reviewer in an agent team reviewing PR #<PR_NUMBER>: <PR_TITLE>.

Your domain:
- Test coverage: untested new code paths, missing edge case tests, tests that only test the happy path, inadequate assertions (testing too little per test)
- Test quality: brittle tests, tests that don't actually verify behavior, missing integration test coverage for cross-component changes
- Style & conventions: naming conventions, formatting consistency, documentation completeness, consistency with existing codebase patterns

Style findings do NOT affect the final verdict (approve/request_changes/comment) — flag them but do not block.

Rate each finding confidence 0-100. Only report findings with confidence >= 80.

The full PR context is below. You have Read, Glob, Grep, Bash tools to explore existing tests for context.

<pr_context>
<INSERT_FULL_CONTEXT_JSON>
</pr_context>

## Your Task

1. Claim task 4 from the task list ("Initial test coverage and style review")
2. Review the PR diff — check test files for coverage gaps and non-test files for untested paths
3. Before finalizing each finding, check `previous_review_threads` in the context:
   - If an **unresolved** thread (`is_resolved: false`) exists at the same file/line for the same concern → tag the finding as `"recurring": true` and note which previous reviewer raised it. Elevate its priority.
   - If a **resolved** thread exists for the same concern → only include your finding if the fix introduced a new problem. Otherwise skip it.
   - If `is_outdated: true` on a thread → the code moved; the original concern may still apply, check the current diff.
4. When done, mark task 4 complete and message the lead with your findings in this JSON format:

{
  "domain": "coverage-and-style",
  "summary": "1-2 sentence summary of test coverage and style",
  "severity": "approve|comment",
  "coverage_assessment": "ADEQUATE|GAPS|INSUFFICIENT",
  "findings": {
    "coverage_gaps": ["untested path description with file:line"],
    "style": ["style issue with file:line"]
  },
  "comments": [
    {"path": "file.go", "line": 42, "body": "comment text", "category": "coverage|style", "recurring": false}
  ]
}

5. After sending findings to the lead, await the cross-review discussion (task 5). Share your top 3 coverage gaps with the team. If the security reviewer flagged a vulnerability, proactively check whether there are tests covering that failure path and report back to them directly.
```

---

## Step 6b: Monitor Initial Reviews

After spawning the team, monitor progress:

1. Periodically check task status with `TaskList` to see which initial reviews are complete
2. If a reviewer appears stuck (task in-progress for an unusually long time), send them a nudge via `SendMessage`: "Check in — how is your review progressing? Let me know if you're blocked."
3. As findings arrive in your mailbox from teammates, acknowledge receipt and note any findings that seem cross-domain

Wait until all 4 initial review tasks are marked complete before proceeding to the discussion phase.

---

## Step 6c: Cross-Review Discussion Phase

Once all initial reviews are complete, create task 5 and broadcast the discussion prompt to all teammates:

```
All initial reviews are complete. This is the cross-review discussion phase.

1. Each of you: share your TOP 3 most critical findings with the team now.
2. If any of your findings have cross-domain implications, message the relevant reviewer directly:
   - Security finding with no test coverage → message coverage-and-style
   - Architecture flaw that enables a bug → message code-quality
   - Code quality issue with security implications → message security-and-errors
3. If you disagree with a finding from another reviewer (e.g., they flagged something as a bug but you recognize it as an intentional project pattern per CLAUDE.md), say so and explain why.
4. Challenge findings you believe are false positives. The goal is accurate findings, not maximum findings.

Reply with your top 3 findings and any cross-domain flags. Then go idle.
```

Allow teammates to exchange messages. Read the discussion thread as it develops. After all teammates have responded and gone idle, mark task 5 complete.

Key things to watch for in the discussion:
- **Corroboration**: multiple reviewers flagging the same file/module independently — escalate priority
- **Contradiction**: one reviewer flags a pattern another recognizes as intentional — investigate and resolve
- **Escalation**: a security finding that now has a confirmed test coverage gap — these become higher priority in synthesis

---

## Step 7: Lead Motivation Analysis + Result Synthesis

### 7a: Motivation Analysis (Lead)

Extract any Jira ticket key from the PR title or branch name (e.g., `OP-3088` from `feature/OP-3088_remove-double-scrollbars`). If found:
- Fetch the ticket via `mcp__plugin_atlassian_atlassian__getJiraIssue`
- If Atlassian MCP fails, fall back to `acli jira --action getIssue --issue <KEY>`

Explore the codebase for plan files: `~/.claude/plans/`, `./plans/`, `./docs/`.

Produce a motivation narrative covering: why the PR exists, what it solves for users, design philosophy, trade-offs, and strategic context.

This analysis is terminal-only — it is NOT included in the GitHub review body.

### 7b: Merge Inline Comments

Combine all comments from all 4 reviewers into a single array. Apply these rules in order:

- **Drop infra-file comments**: Any comment targeting a file in `$FILTERED_FILES[]` must be removed — infra files are excluded from review entirely.
- **Deduplicate within session**: same file+line addressing the same issue from multiple teammates → keep the more detailed one.
- **Deduplicate against existing comments**: Before including any comment, check `existing_comments` loaded in Step 2. If a comment from ANY previous reviewer (including Copilot, other agents, or human reviewers) already exists within ±5 lines of the same file AND addresses the same concern:
  - If it has been replied to with "fixed" / "addressed" / "done" → drop it entirely.
  - If it is unresolved and still present in the diff → tag as `recurring: true` (don't re-describe it; reference the existing thread instead).
  - If the author replied explaining the decision (not fixing it) → drop it; the decision was made.
- **Elevate**: findings corroborated by multiple reviewers → mark as higher priority.
- **Resolve contradictions**: if a finding was challenged and the challenge was valid, drop it.
- **Recurring issues**: comments with `recurring: true` → prepend body with `⚠️ Recurring: previously raised and not yet addressed.` and treat as highest priority within their severity tier.
- **Cap at 20 inline comments**, prioritizing: recurring issues > security > code quality blocking > architecture > coverage gaps > style.

Track for the review body:
- `$UNRESOLVED_COUNT` = number of threads from `previous_review_threads` where `is_resolved: false`
- `$RESOLVED_COUNT` = number of threads where `is_resolved: true`
- `$RECURRING_COUNT` = number of comments with `recurring: true` in the final merged set

### 7c: Determine Verdict

**Style and coverage reviewers do NOT affect the verdict.** Only `security-and-errors`, `code-quality`, and `architecture` determine the final event:

1. If ANY of these 3 returns `request_changes` → final event is `REQUEST_CHANGES`
2. If ALL 3 return `approve` → final event is `APPROVE`
3. Otherwise → final event is `COMMENT`

### 7d: Compile Review Body

```markdown
## PR Review Summary

**Verdict**: [Approved | Changes Requested | Reviewed with Comments]

### Code Quality
[Summary from code-quality reviewer]

### Security & Error Handling
[Summary from security-and-errors reviewer — include risk level]

### Architecture
[Summary from architecture reviewer — include impact level]

### Test Coverage & Style
[Summary from coverage-and-style reviewer — note: does not affect verdict]

### Cross-Review Insights
[Summarize any significant findings from the discussion phase:
corroborations, resolved contradictions, escalated issues]

### Previous Review Follow-up
**Unresolved threads**: $UNRESOLVED_COUNT
**Resolved threads**: $RESOLVED_COUNT
[If $UNRESOLVED_COUNT > 0, list each unresolved thread: `- path/to/file.ext:line — original concern summary`]
[If $RECURRING_COUNT > 0: "**⚠️ $RECURRING_COUNT finding(s) are recurring** — previously raised and still not addressed."]

---
*Automated review by Claude Code (agent team)*
```

---

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

If successful, record: `post_method = "MCP"`, `post_success = true`.

### Attempt 1 Verification

After a successful MCP post, verify the inline comments were actually stored on GitHub — **do not skip this step**:

```bash
gh api "repos/<owner>/<repo>/pulls/<pr_number>/comments" \
  --jq '[.[] | select(.pull_request_review_id == <REVIEW_ID>)] | length'
```

- If the returned count equals `len(merged_inline_comments)` → verification passed.
- If the count is **less than expected**:
  1. Identify which comments are missing (compare paths/lines against the returned list).
  2. Append the missing ones to the review body as a follow-up body comment via:
     ```bash
     gh pr comment <pr_number> --repo '<owner>/<repo>' --body "$(cat <<'EOF'
     **Inline comments that failed to attach (line resolution):**
     - **path/to/file.ext:42** — [Category] Comment body
     EOF
     )"
     ```
  3. Record: `post_method = "MCP (partial — N comments inlined in body)"`.
- **NEVER write inline comment content directly in the review body text** as a workaround for posting failures. All inline content must go through the `comments` array or the explicit fallback formats below.

### Attempt 1b: MCP Retry Without Inline Comments (Line Resolution Fallback)

If Attempt 1 fails with an error about invalid line, position, or diff:

1. Remove ALL inline comments from the request
2. Append them to the review body as a consolidated list:
   ```markdown
   ---
   ### Inline Comments (line resolution failed)
   - **path/to/file.ext:42** — [Category] Comment body
   ```
3. Retry `mcp__github-cli__create_pull_request_review` with just the body (no `comments` array)

If successful, record: `post_method = "MCP (comments inlined)"`, `post_success = true`.

### Attempt 2: gh CLI Fallback

If MCP fails, fall back to `gh pr review` via Bash:

```bash
cat > /tmp/pr-review-body.md <<'REVIEW_EOF'
<review body>

---
### Inline Comments (could not post individually)

- **path/to/file.ext:42** — [Category] Brief description
REVIEW_EOF

gh pr review <pr_number> --repo '<owner>/<repo>' --<event_flag> --body-file /tmp/pr-review-body.md
rm -f /tmp/pr-review-body.md
```

Where `<event_flag>` is: `APPROVE` → `--approve`, `REQUEST_CHANGES` → `--request-changes`, `COMMENT` → `--comment`.

If successful, record: `post_method = "CLI fallback (gh)"`, `post_success = true`.

### Attempt 3: Ask User to Intervene

**Never silently fail.** If both MCP and CLI fail, use `AskUserQuestion`:
- Which methods failed and their error messages
- Options: **Retry after I fix auth** | **Post manually** | **Skip posting**

---

## Step 8b: Atlassian MCP Fallback Pattern

If any Atlassian MCP call fails (`mcp__plugin_atlassian_*`):

1. Fall back to `acli` CLI:
   - Jira issue fetch: `acli jira --action getIssue --issue <KEY>`
   - Jira search: `acli jira --action getIssueList --jql '<JQL>'`
2. If acli also fails, use `AskUserQuestion`:
   - Report both failures and offer: **Retry after I fix auth** | **Skip this step** | **Provide data manually**

---

## Step 9: Rich Terminal Summary

```markdown
## PR Review Complete: #<number> - <title>

**Verdict**: APPROVED / CHANGES REQUESTED / COMMENTED
**Posted to GitHub**: Yes (MCP) | Yes (CLI fallback) | Skipped (user choice) | Failed
**Review method**: Agent team (4 reviewers + lead)

### Files Changed (<n> files)
- [A] path/to/new-file.ts — <brief description>
- [M] path/to/changed-file.ts — <brief description>
- [D] path/to/removed-file.ts — Deleted

### Team Review Findings
| Reviewer          | Verdict          | Risk/Impact | Comments |
|-------------------|------------------|-------------|----------|
| Security & Errors | APPROVE/REQ/CMT  | LOW/MED/HI  | n        |
| Code Quality      | APPROVE/REQ/CMT  | —           | n        |
| Architecture      | APPROVE/REQ/CMT  | NONE/LOW/HI | n        |
| Coverage & Style  | APPROVE/CMT      | ADEQUATE/.. | n        |

### Cross-Review Insights
[Notable findings from the discussion phase — corroborations, escalations,
resolved contradictions]

### Key Findings
**Security**: <1-2 sentences> [risk: LOW/MEDIUM/HIGH/CRITICAL]
**Code Quality**: <1-2 sentences>
**Architecture**: <1-2 sentences> [impact: NONE/LOW/MEDIUM/HIGH]
**Coverage**: <1-2 sentences>

### Motivation & Intent Analysis
[Full narrative from lead's motivation analysis — subjective, for reviewer's
benefit only, not posted to GitHub]

### Filtered Files: <n>
- <list of auto-excluded files>
(omit if none)

### Screenshots Analyzed: <n>
- Screenshot 1: <description>
(omit if none)

### Previous Review Status
- Unresolved threads: $UNRESOLVED_COUNT
- Resolved threads: $RESOLVED_COUNT
- Recurring issues: $RECURRING_COUNT (previously flagged, still present)

### Inline Comments Posted: <n>
- path/to/file.ts:42 — [Security] ⚠️ Recurring | Brief description
- path/to/file.ts:87 — [Code] Brief description
```

---

## Step 10: Clean Up the Team

After posting and printing the terminal summary, clean up the team:

1. Ensure all teammates are idle (they should be after the discussion phase)
2. Ask the lead to clean up: shut down any active teammates first, then delete the team
3. Remove temp files if any remain

If teammates are still active, send them a shutdown request. Wait for confirmation before cleaning up.

---

## Important Notes

- If no PR number is provided, ask the user for it
- If the repository cannot be detected, ask the user for owner/repo
- Skip binary files when reading content
- If a reviewer agent fails or goes unresponsive, note it in the summary and continue with remaining results — a 3-reviewer synthesis is still valuable
- **Never block a PR solely on style or coverage findings**
- **Motivation & Intent Analysis** is terminal-only — not in the GitHub review body
- **Never silently fail on posting** — MCP and CLI both fail → ask the user to intervene
- **Never embed inline comment content in the review body text** — all inline content must go through the `comments` array (Attempt 1), the body fallback list (Attempt 1b), or the verification follow-up comment (Attempt 1 Verification). Writing "### Inline Comments (posted below)" and embedding content in the body without actually posting inline comments is a known failure mode — do not do this.
- **Post exactly one review** — do not retry `create_pull_request_review` with the same inline comments if the call appears to succeed. Check `post_success` before retrying. Duplicate posts from the same session are a known issue (multiple review IDs with identical content).
- **Do not re-raise findings already present in `existing_comments`** — if a previous reviewer (including Copilot) raised the same concern and the author responded, the decision was made. The dedup check in Step 7b handles this, but teammates should also apply it before submitting their findings to you.
- For the cross-review discussion, give teammates reasonable time to respond before synthesizing — don't rush to Step 7 before the discussion produces value
- The discussion phase is the primary advantage over the single-session review approach — treat it as a first-class step, not an optional one
