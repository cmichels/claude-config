---
description: "Analyze a codebase, propose per-repo domain expert agents, and generate them in .claude/agents/. Usage: /project-agents"
allowed_tools: Bash, Read, Write, Edit, Glob, Grep
---

# /project-agents

Generate per-repo domain expert sub-agents tailored to this specific codebase. Agents are written to the project's `.claude/agents/` directory and are **local-only** — they are not committed to the repo and are not shared with other team members.

---

## Step 1: Find Repo Root

```bash
git rev-parse --show-toplevel 2>/dev/null
```

Store as `$REPO_ROOT`. If not in a git repo, use the current working directory.

---

## Step 2: Check for Existing Project-Level Agents

Check for existing agents at `$REPO_ROOT/.claude/agents/`:

```bash
ls "$REPO_ROOT/.claude/agents/" 2>/dev/null
```

**If agents already exist:** List them with their names and one-line descriptions (read the `name` and first line of `description` from each file's frontmatter). Then ask:

> "Found existing project agents: [list]. How do you want to proceed?
> 1. Review each and decide individually (keep / overwrite / skip)
> 2. Overwrite all
> 3. Keep all existing, only add missing domains"

Wait for the user's choice before proceeding.

**If no agents exist:** Continue to Step 3.

---

## Step 3: Deep Codebase Analysis

Perform a thorough analysis before proposing anything. Do NOT rush to propose — read first.

### 3a. Directory Structure

```bash
find "$REPO_ROOT" -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' -not -path '*/.venv/*' -not -path '*/dist/*' -not -path '*/build/*' | sort
```

### 3b. Detect Languages and Stack

Look for these files to identify the stack:
- `go.mod` → Go project
- `package.json` → Node/TypeScript/JavaScript
- `pyproject.toml` / `requirements.txt` / `setup.py` → Python
- `Cargo.toml` → Rust
- `pom.xml` / `build.gradle` → Java/Kotlin
- `*.tf` files → Terraform/infrastructure
- `Dockerfile` / `docker-compose.yml` → containerisation layer
- `Makefile` → build tooling

Read any found config files to understand:
- Dependencies and libraries in use
- Build commands
- Test commands

### 3c. Read Existing Architecture Documentation

If `$REPO_ROOT/CLAUDE.md` exists, read it — it contains architectural decisions and package maps that should be encoded in the agents.

Also check for: `README.md`, `ARCHITECTURE.md`, `docs/` directory.

### 3d. Read Entry Points and Package Structure

**Go**: Read `go.mod`, all files in `cmd/`, and all `**/doc.go` files if present.

**TypeScript/Node**: Read `package.json`, `tsconfig.json`, and the top-level `src/` or `app/` structure. Read `src/index.ts`, `src/app.ts`, or equivalent entry points.

**Python**: Read `pyproject.toml` or `setup.py`, and `__init__.py` files at the top level of each package.

**All**: Read the top-level directory structure to understand package/module layout.

### 3e. Read Key Source Files Per Domain

For each top-level package or module directory, read:
- The main/index/entry file
- Any types or interface definition files
- One representative file that shows the patterns used

The goal is to understand:
- What each package/module is responsible for
- What libraries/patterns it uses
- What constraints or conventions exist (e.g. "never import X from Y", "always use interface Z")
- What the testing approach is

### 3f. Identify Cross-Cutting Concerns

Look for:
- Shared data models or types used across packages
- Interfaces that decouple layers
- Communication patterns between packages (channels, events, shared state, message passing)
- Architectural rules or invariants (e.g. "poller and TUI do not import each other")
- Database/storage layer and how it's accessed
- External API integrations

---

## Step 4: Propose Agent Breakdown

Based on your analysis, identify 3–5 natural domain boundaries. More than 5 is usually a sign of over-segmentation. Fewer than 3 may mean the codebase is simple enough that per-repo agents aren't necessary (say so if that's the case).

For each proposed agent, present:

```
## [agent-name]
**Owns:** [list of files/packages/directories]
**Responsibilities:** [1-2 sentence description of what this domain does]
**Key constraints to encode:**
- [specific technical rule or constraint #1]
- [specific technical rule or constraint #2]
- ...
**Suggested tools:** [Read, Glob, Grep, Bash, Edit, Write, ...]
```

Then ask:

> "Here's my proposed agent breakdown for [repo name]. Does this look right?
> You can approve as-is, rename agents, adjust domain boundaries, add or remove agents, or add constraints I missed.
> Once you confirm, I'll generate the agent files."

**Wait for explicit confirmation before proceeding to Step 5.**

---

## Step 5: Generate Agent Files

Once confirmed, create `$REPO_ROOT/.claude/agents/` if it doesn't exist:

```bash
mkdir -p "$REPO_ROOT/.claude/agents/"
```

For each approved agent, write `$REPO_ROOT/.claude/agents/<agent-name>.md` using this format:

```
---
name: <agent-name>
description: Use this agent when working on [repo name]'s [domain] layer. Invoke when: [specific triggers based on the domain]. [2-3 concrete example scenarios].
tools: <comma-separated tool list>
model: sonnet
color: <pick a distinct color: cyan, green, yellow, purple, pink, orange, red, blue>
---

You are the [domain] domain expert for [repo name]. [One sentence describing what the repo does and what this agent's role is.]

## Your Domain

You own [describe files/packages/directories with specific paths].

## Architecture Rules

[Document the architectural invariants for this domain. What does this package communicate with? What does it NOT import? What is the data flow?]

## Critical Technical Constraints

[Enumerate the hard rules with examples:
- Which libraries to use and which to avoid (and why)
- Patterns that must be followed
- Things that must never be done
- Configuration or setup requirements]

## Key Patterns

[Document the main patterns used in this domain:
- Data models and their conventions
- Error handling approach
- Testing approach specific to this domain]

## Testing

[Specific testing conventions for this domain:
- What to mock
- What test helpers exist
- In-memory vs real dependencies
- Table-driven, BDD, etc.]

## Verification

Always run before considering work done:
[project-specific build/test/lint command]
```

Use distinct colors across agents so they're visually distinguishable in split-pane mode.

For each file written, encode the **actual** constraints discovered during analysis — not generic advice. If a specific library must be used instead of another, name both. If a specific interface must be used, show it. If an architectural rule exists, state it precisely.

---

## Step 6: Summary

After generating all files, output:

```
## Project Agents Created

$REPO_ROOT/.claude/agents/
  ✓ <agent-name>.md — [one-line domain description]
  ✓ <agent-name>.md — [one-line domain description]
  ...

These agents are local-only. They will not be committed or shared with other team members.

To use them:
- Reference by name in prompts: "use the <name> agent to..."
- Or spin up an agent team: "create an agent team using my domain experts to implement [feature]"
```
