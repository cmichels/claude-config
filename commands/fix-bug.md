---
description: "Fully autonomous bug-fix workflow: fetch Jira ticket, create worktree, write failing test, implement fix with iterative test loop (max 5 retries), lint, and ship PR. Usage: /fix-bug <TICKET-ID>. Stops only on retry limit — no user prompts during the loop."
allowed_tools: Read, Edit, Write, Glob, Grep, Bash, Agent, AskUserQuestion, Skill, mcp__plugin_atlassian_atlassian__getJiraIssue, mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql, mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources, mcp__plugin_atlassian_atlassian__search, mcp__github-cli__create_pull_request, mcp__github-cli__get_pull_request, mcp__github-cli__list_pull_requests, mcp__plugin_playwright_playwright__browser_navigate, mcp__plugin_playwright_playwright__browser_snapshot, mcp__plugin_playwright_playwright__browser_take_screenshot, mcp__plugin_playwright_playwright__browser_click, mcp__plugin_playwright_playwright__browser_fill_form, mcp__plugin_playwright_playwright__browser_run_code, mcp__plugin_playwright_playwright__browser_console_messages, mcp__plugin_playwright_playwright__browser_network_requests
---

# Fix-Bug Command

Fully autonomous bug-fix pipeline. Takes a Jira ticket ID, sets up a worktree, reproduces the bug with a failing test, iteratively implements a fix, lints, and ships a PR. **No user interaction during the loop** — only stops if the retry limit (5 iterations) is hit.

The ticket ID is: **$ARGUMENTS**

---

## Phase 0: Validate Input

### 0.1 Parse Ticket ID

`$ARGUMENTS` must be a Jira ticket key matching `[A-Z]+-\d+` (e.g., `OP-3088`, `TSP-456`).

**If no ticket ID or invalid format:** STOP and inform user of the expected format.

Store as `$TICKET_ID`.

---

## Phase 1: Fetch Jira Ticket Details

### 1.1 Get Ticket via CLI

Use the acli CLI as the primary path (faster and more reliable for autonomous workflows):

```bash
acli jira --action getIssue --issue "$TICKET_ID"
```

**If acli fails:** Try MCP:
```
mcp__plugin_atlassian_atlassian__getAccessibleAtlassianResources()
mcp__plugin_atlassian_atlassian__getJiraIssue(cloudId: "$CLOUD_ID", issueIdOrKey: "$TICKET_ID")
```

**If both fail:** STOP and inform user:
```
Jira connectivity failed. Cannot proceed without ticket details.

acli setup: brew install atlassian-cli && acli auth
MCP setup:  claude mcp add --transport sse atlassian https://mcp.atlassian.com/v1/sse
```

### 1.2 Extract Bug Details

Parse and store:
- `$JIRA_SUMMARY` — ticket title
- `$JIRA_DESCRIPTION` — full description (this is the bug report)
- `$JIRA_TYPE` — should be Bug (warn if not)
- `$JIRA_PRIORITY` — priority level
- `$JIRA_ACCEPTANCE` — acceptance criteria / expected behavior
- `$JIRA_STEPS_TO_REPRODUCE` — reproduction steps (if present in description)
- `$JIRA_ENVIRONMENT` — environment info (if present)
- `$JIRA_ATTACHMENTS` — any attachments or screenshots referenced

### 1.3 Summarize Bug Understanding

Before proceeding, write a brief internal summary:
```
Bug: $JIRA_SUMMARY
Symptom: <what's going wrong>
Expected: <what should happen>
Repro steps: <how to trigger it>
Likely area: <initial guess at affected code area based on description>
```

This summary drives the rest of the workflow. Be precise.

---

## Phase 2: Set Up Worktree

### 2.1 Invoke /worktree

Run the `/worktree` skill with the ticket ID:

```
Skill: worktree $TICKET_ID
```

This will:
- Create a git worktree branched from `origin/dev`
- Branch named `bug/$TICKET_ID_<slugified-summary>`
- Copy config files (`.claude/`, `.env`, `.local`, etc.)
- Fetch Jira context and write `.jira-context`
- Analyze the codebase and generate a plan at `plans/$TICKET_ID.md`

### 2.2 Navigate to Worktree

After `/worktree` completes, `cd` into the worktree directory:

```bash
cd "$WORKTREE_PATH"
```

Store `$WORKTREE_PATH` for all subsequent operations.

### 2.3 Verify Setup

Confirm the worktree is ready:
```bash
git branch --show-current && pwd && ls -la
```

---

## Phase 3: Analyze Code and Write Failing Test

### 3.1 Deep-Dive into Bug Area

Using the bug summary from Phase 1.3 and the plan from Phase 2, perform targeted codebase analysis:

1. **Search for keywords** from the bug description in the codebase:
   ```
   Grep: <key terms from bug report>
   Glob: <file patterns likely related>
   ```

2. **Read the affected files** — understand the current logic, data flow, and edge cases.

3. **Read existing tests** for the affected module to understand test conventions:
   - Test file locations and naming patterns
   - Test framework used (Go testing, Jest, Jasmine, etc.)
   - Helper functions, fixtures, and mocking patterns
   - How similar edge cases are already tested

4. **If the bug involves UI/browser behavior**, use Playwright to reproduce:
   ```
   browser_navigate -> browser_snapshot -> browser_console_messages
   ```
   Capture screenshots to `plans/screenshots/` for reference.

### 3.2 Identify Root Cause Hypothesis

Before writing the test, form a clear hypothesis:
```
Root cause: <specific code path / condition that causes the bug>
File(s):    <exact file paths>
Function:   <exact function/method names>
Trigger:    <what input/state triggers the bug>
```

### 3.3 Write a Failing Test

Create or modify a test file that **reproduces the bug**. The test must:

- Follow the project's existing test conventions (naming, location, framework)
- Set up the exact conditions described in the bug report
- Assert the **expected (correct) behavior**, so it FAILS against the current buggy code
- Be focused — test only the specific bug, not unrelated behavior
- Include a descriptive test name referencing the ticket (e.g., `TestAlarmHandler_NilPointer_OP3088`)

**For Go projects:**
```go
func TestXxx_BugDescription_TICKETID(t *testing.T) {
    // Setup: reproduce the conditions from the bug report
    // Act: trigger the buggy code path
    // Assert: verify the EXPECTED (correct) behavior
}
```

**For TypeScript/Angular projects:**
```typescript
it('should <expected behavior> (TICKET-ID)', () => {
    // Setup: reproduce the conditions from the bug report
    // Act: trigger the buggy code path
    // Assert: verify the EXPECTED (correct) behavior
});
```

### 3.4 Run Test to Confirm Failure

Run the test suite for the affected module:

**Go:**
```bash
cd "$WORKTREE_PATH" && go test ./path/to/package/... -run "TestName" -v -count=1 2>&1
```

**TypeScript/Angular:**
```bash
cd "$WORKTREE_PATH" && npx ng test --include='**/affected.spec.ts' --watch=false 2>&1
# or
cd "$WORKTREE_PATH" && npx jest path/to/test --no-coverage 2>&1
```

**Expected outcome:** The test MUST FAIL. This confirms the test correctly reproduces the bug.

**If the test passes:** The test does not reproduce the bug. Revisit the hypothesis (Phase 3.2), adjust the test, and re-run. Spend up to 3 attempts refining the reproduction test.

**If you still cannot reproduce after 3 attempts:** STOP. Do not proceed with a best-effort fix. A fix without a verifiable reproduction test cannot be trusted. Jump to Phase 7c: Reproduction Failure Report.

**If the test errors (compilation/syntax):** Fix the test code and re-run. This does not count against the 5-iteration limit.

---

## Phase 4: Implement Fix (Iterative Loop)

### 4.0 Initialize Loop State

```
$ITERATION = 0
$MAX_ITERATIONS = 5
$STATUS = "in_progress"
$ATTEMPTS_LOG = []
```

### 4.1 Fix Loop

**WHILE `$ITERATION < $MAX_ITERATIONS` AND `$STATUS == "in_progress"`:**

#### 4.1.1 Increment Counter

```
$ITERATION = $ITERATION + 1
```

#### 4.1.2 Implement / Refine the Fix

**On iteration 1:** Implement the initial fix based on the root cause hypothesis from Phase 3.2.

**On iterations 2+:** Analyze the test failure output from the previous iteration and adjust the fix. Consider:
- Did the original test start passing but a different test broke? (regression)
- Is the fix incomplete — does it only handle part of the edge case?
- Is there a deeper issue than the initial hypothesis suggested?
- Are there related code paths that also need the fix?

**Edit the source code** using the Edit tool. Make minimal, focused changes — fix the bug, nothing else.

#### 4.1.3 Run Tests (Two-Stage)

**Stage 1: Run the reproduction test only.**

This gives fast, focused feedback on whether the fix logic is correct before checking for regressions.

**Go:**
```bash
cd "$WORKTREE_PATH" && go test ./path/to/package/... -run "TestSpecificName" -v -count=1 2>&1
```

**TypeScript/Angular:**
```bash
cd "$WORKTREE_PATH" && npx jest path/to/test --testNamePattern="specific test name" --no-coverage 2>&1
```

**If the reproduction test fails:** Skip Stage 2. The fix isn't right yet — log the attempt and continue the loop (jump to 4.1.4).

**Stage 2: Run the full module test suite.**

Only reached if the reproduction test passes. This catches regressions.

**Go:**
```bash
cd "$WORKTREE_PATH" && go test ./path/to/package/... -v -count=1 2>&1
```

**TypeScript/Angular:**
```bash
cd "$WORKTREE_PATH" && npx ng test --include='**/affected*.spec.ts' --watch=false 2>&1
# or
cd "$WORKTREE_PATH" && npx jest path/to/tests/ --no-coverage 2>&1
```

#### 4.1.4 Evaluate Results

**If ALL tests pass (Stage 1 + Stage 2):**
```
$STATUS = "tests_passing"
```
Break the loop and proceed to Phase 5.

**If the reproduction test fails (Stage 1):** The fix logic is wrong. Log and iterate.

**If the reproduction test passes but other tests fail (Stage 2):** The fix introduced a regression. Log which tests broke and iterate.

**On failure:**

Log the attempt:
```
$ATTEMPTS_LOG.append({
  iteration: $ITERATION,
  changes_made: "<description of what was changed>",
  test_output: "<relevant failure output — truncated to key lines>",
  diagnosis: "<why it failed and what to try next>"
})
```

Continue the loop (back to 4.1.1).

#### 4.1.5 Retry Limit Reached

**If `$ITERATION >= $MAX_ITERATIONS` AND `$STATUS == "in_progress"`:**

```
$STATUS = "stuck"
```

**STOP** and present the failure summary (jump to Phase 7: Failure Report).

---

## Phase 5: Lint and Format

Only reach this phase if `$STATUS == "tests_passing"`.

### 5.1 Detect Project Type and Run Formatters

**Go projects:**
```bash
cd "$WORKTREE_PATH" && gofmt -w $(git diff --name-only --diff-filter=AM HEAD | grep '\.go$') 2>&1
cd "$WORKTREE_PATH" && go vet ./path/to/package/... 2>&1
```

If `golangci-lint` is available:
```bash
cd "$WORKTREE_PATH" && which golangci-lint && golangci-lint run ./path/to/package/... 2>&1
```

**TypeScript/Angular projects:**
```bash
cd "$WORKTREE_PATH" && npx eslint --fix $(git diff --name-only --diff-filter=AM HEAD | grep -E '\.(ts|js)$') 2>&1
cd "$WORKTREE_PATH" && npx prettier --write $(git diff --name-only --diff-filter=AM HEAD | grep -E '\.(ts|js|html|css|scss)$') 2>&1
```

### 5.2 Re-run Tests After Formatting

Formatting changes can occasionally break things. Verify:

```bash
cd "$WORKTREE_PATH" && <same test command from Phase 4.1.3>
```

**If tests fail after formatting:** Undo formatting changes on the offending file and re-run. Do not count this against the iteration limit.

### 5.3 Lint Evaluation

**If lint passes:** Set `$STATUS = "ready_to_ship"` and proceed to Phase 6.

**If lint has errors that cannot be auto-fixed:** Log them but proceed — lint warnings should not block the bug fix. Only true errors (syntax-breaking) should block.

---

## Phase 6: Ship It

Only reach this phase if `$STATUS == "ready_to_ship"`.

### 6.1 Invoke /ship-it

Run the `/ship-it` skill:

```
Skill: ship-it
```

This will:
- Analyze changes and generate commit message
- Stage, commit, and push
- Create a draft PR targeting `dev`
- Link the Jira ticket
- Assign reviewers

**IMPORTANT OVERRIDE for autonomous mode:** The `/ship-it` skill normally asks for commit message confirmation. In this autonomous workflow, accept the auto-generated commit message without modification. If `/ship-it` asks a question, answer with the default / "Ship it" option.

### 6.2 Update Plan File

After shipping, update the plan file to reflect completion:

```bash
echo -e "\n## Resolution\n\n- **Status:** Fixed and PR created\n- **Root Cause:** <root cause summary>\n- **Fix:** <brief description of the fix>\n- **Tests Added:** <test names>\n- **Iterations:** $ITERATION\n- **PR:** <PR link>" >> "$WORKTREE_PATH/plans/$TICKET_ID.md"
```

---

## Phase 7: Output

### 7a: Success Report (if `$STATUS == "ready_to_ship"`)

```
Fix-Bug Complete

Ticket:      $TICKET_ID - $JIRA_SUMMARY
Worktree:    $WORKTREE_PATH
Branch:      $BRANCH_NAME
Iterations:  $ITERATION of $MAX_ITERATIONS

Root Cause:
  <concise root cause explanation>

Fix Applied:
  <concise description of what was changed>

Files Modified:
  - <file1>: <what changed>
  - <file2>: <what changed>

Tests:
  - Added: <test name(s)>
  - All passing (including existing suite)

Lint: Clean
PR:   <PR link>
```

### 7b: Failure Report (if `$STATUS == "stuck"`)

### 7c: Reproduction Failure Report (if bug could not be reproduced)

```
Fix-Bug STOPPED — Could not reproduce bug

Ticket:      $TICKET_ID - $JIRA_SUMMARY
Worktree:    $WORKTREE_PATH
Branch:      $BRANCH_NAME

Bug Hypothesis:
  <root cause hypothesis from Phase 3.2>

Reproduction Attempts (3):
  Attempt 1:
    Test: <what was tested and how>
    Result: <test passed — bug not triggered because...>

  Attempt 2:
    Test: <adjusted approach>
    Result: <test passed — still not triggered because...>

  Attempt 3:
    Test: <final approach>
    Result: <test passed — still not triggered because...>

Analysis:
  <why the bug could not be reproduced — possible causes:>
  - Environment-specific issue (data, config, timing)?
  - Bug only manifests in integration, not unit context?
  - Bug description incomplete or misleading?
  - Already fixed by another change?

Suggested Next Steps:
  1. <manual reproduction approach to try>
  2. <additional context needed from reporter>
  3. <alternative test strategy (integration, E2E, Playwright)>

The worktree is intact at $WORKTREE_PATH with test attempts preserved.
```

```
Fix-Bug STUCK after $MAX_ITERATIONS iterations

Ticket:      $TICKET_ID - $JIRA_SUMMARY
Worktree:    $WORKTREE_PATH
Branch:      $BRANCH_NAME

Bug Hypothesis:
  <root cause hypothesis>

Attempts:
  Iteration 1:
    Changes: <what was tried>
    Result:  <what failed and why>

  Iteration 2:
    Changes: <what was adjusted>
    Result:  <what failed and why>

  ... (all iterations)

  Iteration 5:
    Changes: <last attempt>
    Result:  <current failure state>

Current State:
  - Failing tests: <list>
  - Error output: <key error lines>

Suggested Next Steps:
  1. <suggestion based on pattern of failures>
  2. <alternative approach not yet tried>
  3. <information that might be missing>

The worktree is intact at $WORKTREE_PATH with all changes preserved.
You can continue manually or re-run /fix-bug after adjusting the approach.
```

---

## Error Handling

### General Rules

- **No user prompts during the loop.** The only reason to stop is hitting the 5-iteration limit or a fatal infrastructure error (git broken, filesystem full, etc.).
- **Compilation errors in the fix** count as a failed iteration (the test suite will fail).
- **Compilation errors in the test** (Phase 3.4) do NOT count against iterations — fix them inline.
- **Jira fetch failure** is fatal — cannot proceed without understanding the bug.
- **Worktree creation failure** is fatal — cannot proceed without a clean workspace.
- **Test command not found** — detect the project type and adjust. Try `go test`, `npm test`, `npx jest`, `npx ng test` in order.

### Jira Fallback

If acli fails, try MCP. If MCP also fails, STOP. Do not guess at bug details.

### Playwright Fallback

If the bug involves UI behavior and Playwright is available, use it to visually verify the reproduction and fix. If Playwright is not available or fails, rely on unit/integration tests only.

### Recovery

If the process is interrupted or fails partway:
- The worktree remains intact at `$WORKTREE_PATH`
- All code changes are preserved (uncommitted)
- The plan file documents progress
- User can `cd $WORKTREE_PATH` and continue manually
- User can re-run `/fix-bug $TICKET_ID` — the `/worktree` step will detect the existing worktree and offer to reuse it
