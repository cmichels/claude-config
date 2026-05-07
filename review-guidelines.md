# PR Review Team — Adaptive Guidelines
Generated: 2026-03-13
Based on: 5 merged PRs analyzed (16 inline comments, 43.75% overall adoption)

## Overall Signal Quality: MEDIUM

PRs analyzed: #1418, #1415, #1413, #1410, #1409
Date range: 2026-03-06 → 2026-03-13

---

## Critical Reliability Issues (Fix These First)

### 1. Inline comment posting failure — PR #1418
The agent composed 5 detailed inline comments and embedded them in the **review body text** under
an "Inline Comments (posted below)" header, but never actually posted them as GitHub inline
review comments. Authors saw them only as a wall of text, with no line-specific threading.
**Result**: 0 of 5 inline items were acted on. 0 post-review commits after agent review.

**Fix**: After composing inline comment content, verify each was posted via the PR comments API
(`GET /pulls/{PR}/comments`) and confirm the `pull_request_review_id` matches. If posting failed,
retry before submitting the summary review body. Never embed inline comment content in the body
as a fallback — it is invisible and non-actionable.

### 2. Duplicate inline comment posting — PR #1410
The same 4 inline comments were posted under 5 different review IDs
(3905910211, 3905927917, 3905930476, 3905940333, 3905942245) by the same reviewer.
**Result**: Comment spam, author confusion, and noise in the thread.

**Fix**: Before posting inline comments, check if a comment from the same reviewer already exists
on that file+line (±5 lines). If a duplicate is detected, skip posting. The orchestrator should
track which comments it has already posted within a session.

---

## Domain Breakdown

### Bug Detection & Code Quality

**Adoption rate**: 100% (3/3 acted on)
**Confidence threshold**: >= 75 (current level is well-calibrated)

PRs: #1413 (save() discards stacking toggle — fixed), #1410 (renderChart() no-op — fixed),
#1410 (title: null as any — fixed)

**Keep emphasizing:**
- Confirmed bugs where a setter/method silently discards state
- No-op method overrides that satisfy abstract contracts without functional purpose
- Type hacks (`as any`, `null as any`) that hide legitimate type errors
- Logic that produces wrong output under specific conditions (off-by-one, edge cases)

**Recalibrate:**
- None needed — this domain is performing at maximum signal.

---

### Test Coverage

**Adoption rate**: 100% (2/2 acted on)
**Confidence threshold**: >= 75

PRs: #1415 (showAllWidgets() tests added to both template.service and DA component)

**Keep emphasizing:**
- New public methods with zero test coverage when sibling methods are tested
- Explicit patterns: "the pattern for testing X is already established at spec line Y — follow it"
- Include the existing spec file location and test structure in the comment to reduce friction

**Recalibrate:**
- None needed.

---

### Security

**Adoption rate**: 33% (1/3)
**Confidence threshold**: >= 85 (raise from 80 for non-app-code files)

PRs: #1410 (color XSS in HTML legend — acted on), #1415 (allow_anonymous MQTT — ignored/out of
scope), #1415 (USER variable in Dockerfile — ignored/out of scope)

**Keep emphasizing:**
- HTML injection via unescaped user-controlled data in Highcharts label formatters (acted on 100%
  when scoped to app code)
- Cryptographically insecure random (Math.random() for IDs) — this was also caught by Copilot on
  #1418 and fixed
- Prototype mutation with global side effects (PR #1418 — described in body but never posted inline)

**Recalibrate:**
- Docker/infrastructure files imported verbatim from other repositories (devops-compose project):
  author response was "pulled from devops project, not an issue here." Add provenance check:
  before flagging infrastructure files, check if the file appears to be a template copy (no
  project-specific values, comments reference another project, etc.). If likely imported, flag
  as informational only with: "If this file was authored for this PR, address X. If copied from
  devops-compose, track as a separate devops ticket."
- `allow_anonymous true` in MQTT configs: likely intentional for local dev. Downgrade to LOW
  severity with explicit caveat about dev-vs-prod context.

---

### Architecture & Design

**Adoption rate**: 20% (1/5)
**Confidence threshold**: >= 90 (raise — currently generating low-value noise)

PRs: #1413 (enum renamed — acted on), #1413 (oneToOne=true — rejected, intentional design),
#1413 (height: 100% — rejected, no impact verified), #1415 (hardcoded hostname — ignored/devops
scope), #1410 (settings schema migration — deferred to tech debt)

**Keep emphasizing:**
- Naming/enum consistency where a rename is low-risk and clearly better (acted on 100%)
- Breaking API changes where no migration path exists and existing data will silently break

**Recalibrate:**
- Design decisions that involve tradeoffs the PR author has clearly already evaluated
  (oneToOne, height overrides): raise confidence threshold to >= 90, and phrase as
  "Confirm this is intentional: [explain the tradeoff]" rather than "This should be changed."
  If the author responds "yes, intentional," do not re-flag on subsequent PRs.
- Infrastructure-scope architecture (hardcoded hostnames in docker scripts): apply same
  provenance check as Security above.
- Tech debt that requires a separate migration: flag once, mark with "[Deferred OK — track
  separately]" label so it doesn't re-appear in subsequent PR reviews on the same file.

---

### Error Handling

**Adoption rate**: 0% (0/2)
**Confidence threshold**: >= 90 (raise significantly)

PRs: #1415 (infinite retry loop — ignored/devops scope), #1415 (swallowed failure — ignored/devops scope)

**Note**: Both findings were in devops-imported files and appropriately dismissed. The 0% rate
reflects scope mismatch, not poor finding quality. The async/await-inside-subscribe finding on
PR #1418 was identified but never posted as an inline comment (reliability failure).

**Keep emphasizing:**
- `async/await` inside RxJS `.subscribe()` callbacks that swallow errors post-await — this is a
  real pattern in this codebase (seen in #1418) and genuinely risky
- Error paths that silently succeed (`|| echo 'failed'`) where non-zero exit matters

**Recalibrate:**
- Apply same devops-file provenance check before flagging shell scripts / Dockerfiles.

---

### Style & Conventions

**Adoption rate**: 0% (0/1)
**Confidence threshold**: >= 95 (near-maximum — treat as advisory only)

PRs: #1415 (event suffix naming — dismissed as out of scope)

**Guidance**: Style comments are low-adoption and generate friction when the fix requires
touching files outside the PR's intended scope. Mark all style comments as `[Style — non-blocking]`
(already doing this), and reduce volume. Only post style comments when:
1. The violation is in a file already being modified for functional reasons
2. The inconsistency would cause a lint error in CI
Otherwise suppress entirely.

---

## Cross-Domain Insights

### Devops-file scope mismatch (5 comments, 0% adoption)
The #1415 PR included docker/infrastructure files copied from a separate devops-compose
repository. The agent flagged 5 security+error+architecture issues in those files. All 5 were
dismissed with "pulled from devops project." The agent has no file-provenance awareness.

**Recommendation**: Before generating comments for docker/, .Dockerfile, *.sh, docker-compose*,
or mosquitto.conf files, include this preamble in the finding: "If this file was written for this
PR (not copied from another repo), address the following. If it was imported verbatim, please
track this in the devops project instead." This converts a hard-dismissed comment into an
appropriately scoped one.

### Copilot + Agent review redundancy (PR #1418, #1410, #1409)
Copilot's review runs before the agent team. On PR #1418, Copilot caught and got fixed:
hardcoded strings, Date.now() IDs, dead private fields, missing event listener cleanup, type
annotations. The agent's review body then re-identified issues that were *already fixed* by
Copilot responses, plus added new ones. The agent should check Copilot's existing review to
avoid re-flagging already-acknowledged issues and focus on what Copilot missed.

### Body-described vs. actually-posted inline comments
PR #1418 had the agent write 5 detailed inline comments in the review body text but post 0
actual inline comments. This is the single highest-priority reliability bug. The author approved
and merged the PR without addressing any of the agent's substantive concerns (global prototype
mutation, async/subscribe error swallowing, getter mutation side effect, OnPush strategy, chart
flicker). These were all real findings and all were lost.

---

## Suggested Confidence Threshold Adjustments

| Domain              | Previous | Suggested | Rationale                                          |
|---------------------|----------|-----------|----------------------------------------------------|
| Bug / Code Quality  | 80       | 75        | 100% adoption — can lower bar safely               |
| Coverage            | 80       | 75        | 100% adoption — lower bar to catch more gaps       |
| Security (app code) | 80       | 80        | Keep — good signal when scoped to app files        |
| Security (infra)    | 80       | 90        | Devops files: needs provenance check first         |
| Architecture        | 80       | 90        | Low adoption — raise bar, rephrase as questions    |
| Error Handling      | 80       | 85        | Mixed — infra scope mismatch inflated ignore rate  |
| Style               | 80       | 95        | Near-zero adoption — advisory only                 |

---

## Per-PR Summary

| PR    | Title                              | Verdict            | Comments | Acted On | Rate  |
|-------|------------------------------------|--------------------|----------|----------|-------|
| #1418 | Synchronized charts integration    | Reviewed w/Comments| 0 inline*| 0        | N/A   |
| #1415 | Show all / GitHub env secrets      | Changes Requested  | 8        | 2        | 25%   |
| #1413 | Stacked bar chart integration      | Changes Requested  | 4        | 2        | 50%   |
| #1410 | Gauge integration                  | Reviewed w/Comments| 4        | 3        | 75%   |
| #1409 | Pie chart dashboard v2             | Reviewed w/Comments| 0 inline*| 0        | N/A   |

*Agent composed inline comments but failed to post them as GitHub inline review comments.

---

## Wiring Guidelines Into Reviews

Add the following to Step 6 of each sub-reviewer's spawn prompt:

```
Load ~/.claude/review-guidelines.md and apply the confidence thresholds and recalibration
notes for your domain before finalizing findings. Pay special attention to:
- File provenance check before flagging docker/infra files
- Duplicate comment guard: verify no existing comment at ±5 lines before posting
- Inline comment posting verification: confirm each was posted via API before writing summary
```

---
*Maintained manually. Review before applying to production reviews.*
