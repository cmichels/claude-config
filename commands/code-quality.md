---
description: "On-demand code quality and standards analysis for branch changes. Detects magic numbers, inline strings, duplicate code, naming issues, and structural smells. Usage: /code-quality [file_or_dir]"
allowed_tools: Bash, Read, Glob, Grep
---

# /code-quality — Code Standards & Smell Detection

Analyze code on the current branch for standards violations and code smells. Targets only files changed on this branch relative to the base branch.

**Scope**: `$ARGUMENTS` — optional file path or directory within the current project. If empty, analyze all changed files on the branch.

## Step 1: Determine Changed Files

Get the base branch and changed file list:

```bash
BASE=$(git merge-base HEAD dev)
git diff --name-only "$BASE"...HEAD
```

**If `$ARGUMENTS` is provided:** Filter the changed file list to only files matching the argument.
- If it's a file path: only analyze that file (confirm it's in the changed list; if not, analyze it anyway but note it has no branch diff)
- If it's a directory: only analyze changed files under that directory

**If no files match:** "No changed files in scope. Nothing to analyze." STOP.

Store the final file list as `$FILES`.

## Step 2: Read the Code

For each file in `$FILES`:
1. Read the full file content
2. Get the diff for context on what changed: `git diff $BASE...HEAD -- <file>`

Focus analysis on the **changed lines and their surrounding context** (functions/classes containing changes), but flag pre-existing issues in touched functions if they're egregious.

## Step 3: Analyze — Code Standards

Scan every file in `$FILES` for these categories. Be specific — cite the exact line and the offending code.

### Magic Numbers & Strings

- Unexplained numeric literals (outside 0, 1, -1, common HTTP status codes)
- Hardcoded string literals used for comparison, configuration, or display (not imports, not type annotations)
- Repeated literal values that should be constants
- Threshold/limit values without named constants

```typescript
// BAD
if (retryCount > 3) { ... }
if (status === 'ACTIVE') { ... }
setTimeout(callback, 86400000);

// GOOD
const MAX_RETRIES = 3;
const STATUS_ACTIVE = 'ACTIVE';
const ONE_DAY_MS = 86_400_000;
```

### Duplicate Code

- Identical or near-identical code blocks (3+ lines) appearing in multiple places
- Copy-paste patterns with minor variations (different variable names, same structure)
- Similar logic that could be unified into a shared function
- Repeated conditional chains with the same shape

### Naming Issues

- Single-letter variables outside of loop iterators or lambdas
- Generic names: `data`, `info`, `temp`, `result`, `item`, `val`, `obj`, `manager`, `handler`, `processor` — when a more specific name exists
- Misleading names that don't match what the code does
- Inconsistent naming within the same file (mixing conventions)
- Abbreviations when the full word is short enough (`btn` vs `button`, `msg` vs `message` — flag only when inconsistent with surrounding code)
- Boolean variables/functions that don't read as questions (`active` vs `isActive`)

### Structural Smells

- **Long functions**: 40+ lines — flag, suggest extraction points
- **Deep nesting**: 3+ levels of conditionals/loops — suggest early returns or extraction
- **Long parameter lists**: 4+ parameters — suggest grouping into an object/interface
- **God functions**: doing multiple unrelated things in sequence
- **Feature envy**: function mostly operating on another module's data

### Dead Code & Clutter

- Unreachable code after return/throw/break
- Unused variables, imports, or functions introduced in this branch
- Commented-out code blocks (not TODOs — actual dead code)
- Console.log / print statements that look like debug leftovers

### Type Safety (TypeScript/Angular specific)

- `any` type usage where a specific type is feasible
- Type assertions (`as`) that bypass safety without justification
- Missing null/undefined checks at boundaries
- Loose equality (`==`) instead of strict (`===`)

### Language-Specific

**TypeScript/Angular:**
- Missing `trackBy` on `*ngFor`
- Manual `.subscribe()` without cleanup (should use `this.subscription.add()` or async pipe)
- Hardcoded display strings that should use `gT()` for i18n
- Nested subscribes (subscribe inside subscribe)

**Go:**
- Ignored errors (`_ = someFunc()`)
- Error strings starting with uppercase
- Naked returns in functions longer than 10 lines
- `context.Background()` in request handlers

**Python:**
- Mutable default arguments
- Star imports
- Bare `except:` without exception type

## Step 4: Output

Respond directly in the conversation. No file output.

**If nothing found:** "Code looks clean. No standards issues detected." STOP.

**If findings exist:**

Group by file. Within each file, order by line number. For each finding:

```
**file/path.ts:42** — [Category] Brief description
  `offending code snippet`
  Fix: What to do about it (one sentence)
```

### Summary Table

End with a count table:

| Category | Count |
|---|---|
| Magic numbers/strings | N |
| Duplicate code | N |
| Naming issues | N |
| Structural smells | N |
| Dead code/clutter | N |
| Type safety | N |
| Language-specific | N |
| **Total** | **N** |

### Verdict

End with one line:
- "Clean — standards look solid."
- "Minor stuff — nothing blocking, tidy up when convenient."
- "Several issues worth addressing before this ships."
- "This needs work — fix the structural issues before review."

## Rules

- This is a conversation, not a document. Write like you're pair programming.
- Be direct. "`retryCount > 3` is a magic number" not "Consider extracting the numeric literal to improve maintainability."
- Only flag things that genuinely hurt readability, maintainability, or correctness. Not every literal needs a constant.
- Don't pad with positives. If it's clean, say so and stop.
- Don't suggest refactors beyond the scope of what's changed.
- Never suggest running the full review pipeline — the user chose /code-quality for a reason.
- Total response should be under 80 lines unless there are genuinely many issues.
