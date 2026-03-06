---
description: "Understand code before you ship it. Usage: /explain <file_path> or /explain <file_path:function_name>. Explains purpose, logic, dependencies, and edge cases so you can confidently own it in a PR review."
allowed_tools: Read, Glob, Grep, Bash
---

# /explain — Understand Code Before You Ship It

Explain the code at the specified path so the user fully understands it before owning it in a PR.

**Target**: `$ARGUMENTS`

## Step 1: Resolve the Target

- If `$ARGUMENTS` contains a `:` separator (e.g., `path/to/file.go:FunctionName`), split into file path and function/method name. Read the file and locate that specific function or method.
- If `$ARGUMENTS` is a file path with no `:`, read the full file.
- If `$ARGUMENTS` is empty or missing, find the most recently modified file in the current working directory:
  ```bash
  ls -t | head -1
  ```
  Then read that file.
- If the path doesn't exist, try common resolutions (relative to cwd, glob for partial matches) before giving up.

## Step 2: Analyze and Explain

Provide a clear, concise explanation covering these sections:

### Purpose
What does this code do and why does it exist? Frame it in terms of the system it belongs to — not just "this function returns X" but "this handles Y in the context of Z."

### Inputs / Outputs
- What parameters, configs, or data does it consume?
- What does it return, write, emit, or mutate?
- What side effects does it have (HTTP calls, DB writes, file I/O, channel sends, etc.)?

### Key Logic
Walk through the important decisions and control flow. Focus on:
- Branching logic and why each branch exists
- Loops and what drives their iteration
- State transitions or mutations
- Any non-obvious algorithms or patterns used

Do NOT do a line-by-line walkthrough. Summarize the logic at a level where someone can confidently say "I understand what this does."

### Dependencies
What does this code rely on?
- Imported packages or modules (highlight non-standard ones)
- Other files, services, or functions it calls
- Environment variables, config values, or feature flags
- Database tables, API endpoints, or external systems

Use Grep or Glob to trace key dependencies if the imports aren't self-explanatory.

### Edge Cases & Assumptions
- What inputs could cause unexpected behavior?
- What assumptions does the code make about its environment?
- Are there implicit contracts (e.g., "caller must hold the lock", "slice must be non-empty")?
- What happens on nil/null/zero-value inputs?

## Step 3: Watch Out (Conditional)

If you spot potential issues during analysis, add a **Watch Out** section flagging:
- Race conditions or concurrency issues
- Missing error handling or swallowed errors
- Security concerns (injection, auth bypass, data exposure)
- Performance traps (N+1 queries, unbounded allocations, blocking calls)
- Silent failures or misleading behavior
- Dead code or unreachable branches

Only include this section if there are genuine concerns — do not pad it with hypotheticals.

## Formatting Rules

- Keep the explanation focused and practical — no filler
- Use code snippets sparingly: only when referencing a specific non-obvious line
- Target someone who needs to confidently say "I understand this code" in a PR review
- If the file is large (>300 lines), focus the Key Logic section on the most important ~30% and note what was skimmed
- For Go code, mention receiver types and interface satisfaction if relevant
- For TypeScript/Angular code, mention component lifecycle hooks and DI if relevant
