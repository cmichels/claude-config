---
description: "PR review retrospective: analyzes last N merged PRs reviewed by the agent team, scores comment adoption rates by domain, and generates updated reviewer guidelines. Usage: /review-retro [N=5]"
allowed_tools: Read, Glob, Grep, Bash, Write, AskUserQuestion
---

# Review Retrospective Command

Analyze the last N merged PRs that received an agent team review. Score how many comments were acted on vs ignored. Generate updated reviewer guidelines that amplify signal and reduce noise.

The argument is: **$ARGUMENTS** (default: 5 if empty)

---

## Phase 0: Setup

### 0.1 Parse Arguments

Parse `$ARGUMENTS`:
- If empty or not a number → use `N = 5`
- If a positive integer → use that as N
- If invalid → inform user and use default

Store as `$N`.

### 0.2 Detect Repository

```bash
git remote get-url origin
```

Parse `owner` and `repo` from output (SSH or HTTPS format). Store as `$OWNER` and `$REPO`.

### 0.3 Check for Existing Guidelines

```bash
cat /home/kuda/.claude/review-guidelines.md 2>/dev/null || echo "NO_EXISTING_GUIDELINES"
```

If guidelines exist, store as `$EXISTING_GUIDELINES` — they will inform the update rather than being replaced wholesale.

---

## Phase 1: Discover Agent-Reviewed Merged PRs

### 1.1 Fetch Recent Merged PRs

Fetch a candidate pool — more than N to account for filtering:

```bash
gh pr list \
  --repo "$OWNER/$REPO" \
  --state merged \
  --limit $((N * 5)) \
  --json number,title,mergedAt,headRefName \
  --jq '.[] | "\(.number) \(.mergedAt) \(.title)"'
```

### 1.2 Filter for Agent-Reviewed PRs

For each PR in the candidate pool, check if an agent team review exists. An agent team review is identified by its body containing:
```
*Automated review by Claude Code (agent team)*
```

Use this command per PR (run up to 10 in small parallel batches):

```bash
gh api "repos/$OWNER/$REPO/pulls/<PR_NUMBER>/reviews" \
  --jq '.[] | select(.body | contains("Automated review by Claude Code (agent team)")) | {id: .id, submitted_at: .submitted_at, body: .body, state: .state}'
```

Collect PRs that have at least one matching review. Stop once you have `$N` qualifying PRs.

If fewer than `$N` agent-reviewed PRs exist, proceed with however many are found and note the shortfall in the final report.

Store as `$REVIEWED_PRS[]` — array of `{number, title, mergedAt, review_id, review_body, review_submitted_at}`.

---

## Phase 2: Extract Data Per PR

For each PR in `$REVIEWED_PRS[]`, collect:

### 2.1 Inline Review Comments

```bash
gh api "repos/$OWNER/$REPO/pulls/<PR_NUMBER>/comments" \
  --jq '.[] | select(.pull_request_review_id == <REVIEW_ID>) | {
    id: .id,
    path: .path,
    line: (.line // .original_line),
    body: .body,
    created_at: .created_at
  }'
```

For each comment, extract:
- `path` — file path
- `line` — line number (use `line` first, fall back to `original_line`)
- `body` — full comment text
- `domain` — extract from bracket prefix if present: `[Security]`, `[Code]`, `[Architecture]`, `[Coverage]`, `[Style]`. If no bracket prefix, infer from content keywords.
- `category` — sub-category if present (e.g., `security`, `bug`, `coverage`, `style`)
- `is_recurring` — true if body contains `⚠️ Recurring`

### 2.2 Final Merged Diff

```bash
gh pr diff <PR_NUMBER> --repo "$OWNER/$REPO"
```

Parse the diff to extract:
- Changed file paths
- For each changed file: the line ranges that were added/modified (`+` lines) and removed (`-` lines)
- Store as `$DIFF_MAP[path] = {added_lines: [], removed_lines: [], changed_range_start, changed_range_end}`

### 2.3 Post-Review Commits

```bash
gh api "repos/$OWNER/$REPO/pulls/<PR_NUMBER>/commits" \
  --jq '.[] | {sha: .sha, message: .commit.message, date: .commit.author.date}'
```

Filter for commits with date AFTER `review_submitted_at`. These are the commits made in response to the review. Store count as `$POST_REVIEW_COMMITS`.

---

## Phase 3: Score Each Comment

For each inline comment, determine its adoption status.

### 3.1 Scoring Logic

**acted_on**: The comment pointed to a file+line area that was subsequently modified.
- The file appears in the diff AND
- At least one changed line (added or removed) falls within ±15 lines of the comment's `line`

**inconclusive**: Cannot determine with confidence.
- File was deleted in the final diff (can't compare)
- Comment line is 0 or null
- File doesn't appear in diff but PR had 0 post-review commits (maybe merged without addressing anything)
- Comment was marked `⚠️ Recurring` — these are always escalated regardless of outcome

**ignored**: Comment was not addressed.
- File appears in diff but no changes within ±15 lines of comment line
- File does NOT appear in diff at all AND there were post-review commits

### 3.2 Record Each Score

For each comment, store:
```json
{
  "pr_number": 123,
  "path": "path/to/file.go",
  "line": 42,
  "body_preview": "first 80 chars of body",
  "domain": "security",
  "category": "error-handling",
  "is_recurring": false,
  "status": "acted_on|ignored|inconclusive",
  "score_rationale": "brief explanation of why this score was assigned"
}
```

---

## Phase 4: Aggregate Patterns

### 4.1 Per-Domain Stats

Group scored comments by domain. For each domain calculate:

```
domain_stats[domain] = {
  total_comments: N,
  acted_on: N,
  ignored: N,
  inconclusive: N,
  adoption_rate: acted_on / (total - inconclusive),  // exclude inconclusive from denominator
  recurring_count: N,  // comments marked ⚠️ Recurring
  top_ignored_categories: [],  // sub-categories most frequently ignored
  top_acted_categories: []   // sub-categories most frequently acted on
}
```

### 4.2 Cross-PR Patterns

Identify:
- **High-signal categories**: categories with adoption rate > 70% — reviewers should emphasize these
- **Low-signal categories**: categories with adoption rate < 30% — reviewers should recalibrate or drop
- **Recurring issues**: findings marked `⚠️ Recurring` that were STILL ignored — systemic problem, may need escalation guidance
- **Cross-domain correlations**: did security findings with coverage gaps get acted on more than solo security findings?

### 4.3 Overall Health Score

```
overall_adoption_rate = total_acted_on / (total_comments - total_inconclusive)
signal_quality = "HIGH" if > 70%, "MEDIUM" if 40-70%, "LOW" if < 40%
```

---

## Phase 5: Generate Updated Guidelines

Based on the aggregate patterns, generate domain-specific guideline updates.

### 5.1 Guideline Generation Logic

For each domain, generate guidance covering:

**If adoption_rate > 70%:**
> This domain's findings are being acted on at a high rate. Current guidance is calibrated well. Continue emphasizing [top acted-on categories]. Consider raising the confidence threshold slightly to reduce total comment volume while maintaining signal quality.

**If adoption_rate 40-70%:**
> Mixed signal. [Top acted-on categories] are valued — keep these. [Top ignored categories] are being consistently skipped — either recalibrate expectations or add explicit "why this matters" context to make them harder to dismiss.

**If adoption_rate < 30%:**
> Low adoption. This domain may be generating noise. Recommendation: raise the confidence threshold to >= 90 for this domain, narrow scope to [high-value subcategories only], and consider whether some [ignored categories] should be downgraded to informational-only.

**If recurring_count > 2:**
> Multiple recurring issues were still ignored after being flagged repeatedly. For findings with `⚠️ Recurring`, recommend: include the specific PR number where it was first raised, reference the exact code pattern that was not addressed, and escalate to REQUEST_CHANGES automatically rather than COMMENT.

### 5.2 Write Guidelines File

Write the generated guidelines to `/home/kuda/.claude/review-guidelines.md`:

```markdown
# PR Review Team — Adaptive Guidelines
Generated: <date>
Based on: <N> merged PRs analyzed (<total_comments> comments, <adoption_rate>% overall adoption)

## Overall Signal Quality: HIGH|MEDIUM|LOW

---

## Security & Error Handling

**Adoption rate**: X% (N acted on / M total)
**Confidence threshold**: >= 80 (raise to >= 90 if LOW signal)

### Keep emphasizing:
- [categories with high adoption]

### Recalibrate:
- [categories with low adoption — add "why this matters" context or raise threshold]

### Recurring issue guidance:
[if recurring_count > 2: specific escalation guidance]

---

## Code Quality & Correctness

**Adoption rate**: X%
**Confidence threshold**: >= 80

### Keep emphasizing:
- [high adoption categories]

### Recalibrate:
- [low adoption categories]

---

## Architecture & Design

**Adoption rate**: X%
**Confidence threshold**: >= 80

### Keep emphasizing:
- [high adoption categories]

### Recalibrate:
- [low adoption categories]

---

## Test Coverage & Style

**Adoption rate**: X%
**Note**: Style findings do not affect verdict. Coverage findings do.

### Keep emphasizing (coverage):
- [high adoption coverage categories]

### Recalibrate (coverage):
- [low adoption coverage categories]

### Style findings:
[If style adoption rate < 20%: "Consider reducing style comment volume — authors are not acting on them."]

---

## Cross-Domain Insights

[High-signal patterns that span domains]
[Recurring issue systemic patterns]
[Cross-domain correlations]

---

## Suggested Confidence Threshold Adjustments

| Domain             | Current | Suggested | Rationale                     |
|--------------------|---------|-----------|-------------------------------|
| security-errors    | 80      | X         | [rationale]                   |
| code-quality       | 80      | X         | [rationale]                   |
| architecture       | 80      | X         | [rationale]                   |
| coverage-style     | 80      | X         | [rationale]                   |

---
*Auto-generated by /review-retro. Review before applying to production reviews.*
```

If `$EXISTING_GUIDELINES` was found in Phase 0.3, **merge** rather than replace:
- Keep any manual annotations (lines starting with `> Note:`)
- Update stats sections with new data
- Add a `## History` section showing previous adoption rates over time

---

## Phase 6: Terminal Report

Output a rich terminal summary:

```
╔══════════════════════════════════════════════════════════╗
║           PR Review Retrospective                        ║
║           $N PRs analyzed · $TOTAL_COMMENTS comments     ║
╚══════════════════════════════════════════════════════════╝

Overall Adoption Rate: XX%  [Signal Quality: HIGH|MEDIUM|LOW]
PRs Analyzed: $N (of $CANDIDATE_COUNT candidates scanned)
Date Range: <oldest mergedAt> → <newest mergedAt>

┌─────────────────────────────────────────────────────────┐
│ Domain Breakdown                                        │
├──────────────────────┬────────┬──────┬────────┬─────────┤
│ Domain               │ Total  │ Done │ Missed │ Rate    │
├──────────────────────┼────────┼──────┼────────┼─────────┤
│ Security & Errors    │   N    │  N   │   N    │  XX%    │
│ Code Quality         │   N    │  N   │   N    │  XX%    │
│ Architecture         │   N    │  N   │   N    │  XX%    │
│ Coverage & Style     │   N    │  N   │   N    │  XX%    │
│ ─────────────────────┼────────┼──────┼────────┼─────────│
│ TOTAL                │   N    │  N   │   N    │  XX%    │
└──────────────────────┴────────┴──────┴────────┴─────────┘

High-Signal Findings (acted on > 70%)
  ✓ [Security] injection/auth findings
  ✓ [Code] nil dereference / off-by-one
  ✓ [Architecture] breaking API changes

Low-Signal Findings (acted on < 30%)
  ✗ [Style] naming conventions
  ✗ [Coverage] trivial getter tests
  ✗ [Architecture] debt warnings without concrete impact

⚠️  Recurring Issues ($RECURRING_IGNORED still unresolved across PRs)
  [list recurring findings that were ignored]

Per-PR Summary
  PR #NNN — "<title>" — XX% adoption ($N/$M comments addressed)
  PR #NNN — "<title>" — XX% adoption ($N/$M comments addressed)
  ...

Guidelines written to: ~/.claude/review-guidelines.md

Next Step (optional):
  Wire guidelines into /review-pr-team by adding this to
  Step 6 of the spawn prompts:
    "Load ~/.claude/review-guidelines.md and apply the
     confidence thresholds and recalibration notes for
     your domain before finalizing findings."
```

---

## Phase 7: Error Handling

**Fewer than N agent-reviewed PRs found:**
Proceed with what's available. Note in report: "Only X of $N requested PRs found with agent reviews. Widen the search window or run more reviews first."

**PR diff fetch fails:**
Skip that PR's comment scoring. Mark all its comments as `inconclusive`. Note in report.

**API rate limit:**
If `gh api` returns 403/429, pause 10 seconds and retry once. If still failing, note in report and continue with data collected so far.

**Zero comments found for a review:**
Some PRs may have been reviewed with body-only (no inline comments). These still count toward "PRs reviewed" but contribute no scoring data. Note them separately.

**Guidelines file write fails:**
Print the guidelines content to terminal instead. Inform user of the write failure and the path.

---

## Important Notes

- This command is read-only — it does NOT post anything to GitHub, create PRs, or modify code
- The guidelines file is a recommendation — review it before wiring it into active reviews
- `inconclusive` results are excluded from adoption rate calculations to avoid penalizing ambiguous cases
- Recurring findings (⚠️) are always flagged regardless of adoption score — they represent systemic issues
- The ±15 line window for "acted on" detection is a heuristic — some false positives and negatives are expected
- First run may return limited data if few PRs have been reviewed with the agent team
