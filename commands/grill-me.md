---
description: "Walk through AI-generated changes on the current branch (vs dev) and grill the user on the patterns, tech, and decisions involved before /ship-it. Hybrid format: state the change, then ask one pointed comprehension question. Top-down progression. Stops on 'uncle' and writes a summary file. Use when user wants to gain understanding of branch changes before shipping, or mentions 'grill me'."
allowed_tools: Read, Glob, Grep, Bash, AskUserQuestion, Write
---

Walk me through the AI-generated changes on this branch so I can ship them with confidence. Start with the big picture, drill down progressively, stop when I say "uncle".

## How

1. **Identify the diff.** Run `git diff --stat dev...HEAD` for scope, then `git diff dev...HEAD` for the full picture. If there are uncommitted changes, fold them in via `git diff HEAD` and `git diff --cached`.
2. **Read the surrounding code.** Use Read/Glob/Grep on touched files and their neighbors. Questions about "why this approach" require knowing what alternatives already exist in the codebase.
3. **Walk top-down.** Big picture first ("this change introduces X to solve Y"), then per-module, then specific decisions. Do not open with line-level pedantry.

## Format for each topic

1. **Set the frame.** State the change or pattern in one or two sentences. Name the tech or pattern in play.
2. **Ask one pointed question.** Pick the question that exposes whether the user understands the *implications*, not whether they can repeat the description.
   - Strong: "If we changed this channel to buffered size 1, what would break?"
   - Strong: "What happens to in-flight requests if this context cancels mid-write?"
   - Weak: "What does this function do?"
3. **React to the answer.** Solid → move on. Hand-wavy → drill once with a follow-up, then mark it as a gap and move on. Don't grind.

## Topic priority

Cover in this order; skip the rest:

- Architectural decisions (new modules, new patterns, dependency direction)
- Non-obvious choices (where another reasonable approach exists)
- Risky bits (concurrency, error handling, security boundaries, external API contracts, data integrity)
- New dependencies and why they were chosen over the existing toolkit
- Skip: formatting, renames, obvious refactors, boilerplate

## Rules

- **One question at a time.** No batches.
- **Codebase over speculation.** If reading the code answers a question, read it instead of asking.
- **Don't restate; test.** Your job is to surface gaps, not narrate the diff.
- **"uncle" stops the grilling.** When the user says it, stop asking and write the summary.

## End with a summary

When the user says "uncle" or you've covered the meaningful surface area, write a summary to `.grill-summary.md` in the repo root using the Write tool:

```markdown
# Grill Summary — <branch name>

## Patterns and tech you now understand
- <topic>: <one-line description of what they answered well>

## Things you hand-waved past
- <topic>: <what was missing from the answer>

## Worth a second look before /ship-it
- <file:line>: <specific concern and why it matters>
```

Do not soften concerns. If something is risky and the user did not have a confident answer, flag it. The summary is a confidence check before shipping, not a participation trophy.
