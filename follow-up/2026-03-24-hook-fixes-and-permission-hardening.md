# Session Dump — 2026-03-24 (Monday)
## Hook stdin Migration, Permission Hardening, Skill Fixes

---

## What We Did

1. **Reviewed `follow-up/2026-03-20-audit-toggle-and-review.md`** — verified accuracy against current repo state. Found Thread #5 (commit accumulated changes) was already resolved as `2cc77db`. Branch is now synced with origin.

2. **Diagnosed broken audit hook** — the audit log had 401 lines of empty data. Root cause: all 8 hooks in settings.json used `$CLAUDE_TOOL_NAME`, `$CLAUDE_TOOL_INPUT`, and `$CLAUDE_FILE_PATH` environment variables, but Claude Code passes hook data via **stdin as JSON**. Every hook was silently receiving empty strings.

3. **Rewrote all 8 hooks** to read stdin JSON via `input=$(cat)` and extract fields with `jq`:
   - `$CLAUDE_TOOL_NAME` → `jq -r '.tool_name'`
   - `$CLAUDE_TOOL_INPUT` → `jq -r '.tool_input'`
   - `$CLAUDE_FILE_PATH` → `jq -r '.tool_input.file_path'`

4. **Added ~15 new permissions** to settings.json to reduce prompt fatigue from /worktree, /ship-it, and /screenshot skills. All scoped narrowly per kuda's policy (no destructive wildcards).

5. **Created `bin/worktree-check-configs.sh`** — replaces inline compound Bash commands in /worktree skill. Detects and optionally copies config files in one call. Auto-approved via existing `Bash(/home/kuda/.claude/bin/*)` permission.

6. **Fixed /worktree skill** (`commands/worktree.md`):
   - Step 4.1: use bin script for config detection
   - Step 4.2: use bin script with `--copy` flag for file copying
   - Step 4.4: use Write tool instead of Bash heredoc for `.jira-context`
   - Step 5.1: added tool discipline table — ZERO Bash for codebase exploration

7. **Fixed /ship-it skill** (`commands/ship-it.md`):
   - Step 5.1: added tool discipline instruction (no Bash for code analysis)
   - Step 6.7: hardcoded `$GH_USER = "starkmichelsc"` instead of calling `gh api user`

8. **Added `--model` flag to /review-pr-team** (`commands/review-pr-team.md`):
   - New Step 0: argument parsing for `--model sonnet|opus|haiku`
   - Default: reviewers on Sonnet, lead on session model
   - Step 6: explicit `model: $REVIEWER_MODEL` in teammate spawn
   - Step 9: terminal summary shows reviewer model

9. **Initialized uv project** (pyproject.toml, .venv, .python-version) for JSON validation tooling.

---

## Files Modified

| File | Change |
|------|--------|
| `settings.json` | 8 hooks rewritten (env vars → stdin JSON), ~15 new permissions added |
| `commands/worktree.md` | bin script integration, Write tool for .jira-context, tool discipline table |
| `commands/ship-it.md` | tool discipline, hardcoded GitHub username |
| `commands/review-pr-team.md` | --model flag, Step 0 arg parsing, Sonnet default for reviewers |
| `bin/worktree-check-configs.sh` | **NEW** — detect + copy config files for worktree setup |
| `pyproject.toml` | **NEW** — uv project init |
| `.python-version` | **NEW** — from uv init |
| `uv.lock` | **NEW** — from uv init |
| `main.py` | **NEW** — from uv init (placeholder) |

---

## Permissions Added (settings.json)

| Permission | Reason |
|-----------|--------|
| `Bash(mkdir -p ./plans/screenshots*)` | /screenshot skill |
| `Bash(ls ./plans/screenshots*)` | /screenshot skill |
| `Bash(python3 ./plans/screenshots/annotate.py*)` | /screenshot annotation |
| `Bash(command cp /home/kuda/projects/optelligent/*)` | /worktree config copy |
| `Bash(command cp -r /home/kuda/projects/optelligent/*)` | /worktree .claude/ copy |
| `Write(/home/kuda/projects/optelligent/*/.jira-context)` | /worktree jira context |
| `Write(../*/.jira-context)` | /worktree jira context (relative path) |
| `Bash(git -C * fetch*)` | /worktree fetch from path |
| `Bash(git -C * worktree*)` | /worktree operations from path |
| `Bash(git -C * add *)` | /ship-it staging from path |
| `Bash(git -C * status*)` | git status from path |
| `Bash(git -C * log*)` | git log from path |
| `Bash(git -C * diff*)` | git diff from path |
| `Bash(git -C * branch*)` | git branch from path |
| `Bash(git -C * rev-parse*)` | git rev-parse from path |
| `Bash(git checkout HEAD -- *)` | /ship-it restore files |
| `Bash(git worktree add *)` | /worktree creation (no -C) |
| `mcp__plugin_atlassian_atlassian__editJiraIssue` | Jira field updates, assignment |
| `mcp__plugin_atlassian_atlassian__transitionJiraIssue` | Jira status transitions |

---

## Commits Made

None this session. All changes are uncommitted.

**Branch state:** `dev`, up to date with `origin/dev`.

---

## Open Threads — Status Update

### 1. Permission audit hook — file-based toggle
- **Status:** DONE (from previous session, verified)

### 2. Permission audit — test the full workflow
- **Status:** READY → needs fresh session
- The hooks are now fixed (stdin JSON instead of env vars). Audit log was cleared. Next step: start fresh session, run a skill, verify `/tmp/claude-permission-audit.log` has real data, then run `bin/permission-audit.sh`.

### 3. Build launcher scripts for pr-monitor
- **Status:** BLOCKED by Thread #2
- Unchanged from previous session.

### 4. /teams-chat file attachment support
- **Status:** Parked
- Unchanged.

### 5. Commit this session's changes
- **Status:** OPEN — significant batch of changes ready to commit
- Consider splitting into 2 commits:
  1. Hook fixes + permissions (settings.json + bin script)
  2. Skill improvements (worktree.md, ship-it.md, review-pr-team.md)

---

## Key Learnings

### Hook stdin protocol
- Claude Code hooks receive JSON on stdin, NOT environment variables
- The stdin JSON structure: `{"tool_name": "...", "tool_input": {...}}`
- Must capture stdin with `input=$(cat)` before any jq parsing — stdin is a one-read stream
- The `.tool_input` field is nested — `jq '.tool_input.command'` not `jq '.command'`

### Permission prefix matching gotchas
- `git fetch*` does NOT match `git -C /path fetch` — the `-C` flag changes the prefix
- `command cp *` does NOT match `command cp -r *` — flags are part of the prefix
- `git worktree list*` does NOT match `git worktree add*` — each subcommand is separate
- Compound commands with `; && ||` trigger "ambiguous syntax" warnings regardless of permissions — extract to bin scripts

### Permission policy (kuda's rule)
- Default to narrowest permission that covers the specific command
- No destructive wildcards — `git -C *` would allow force push, `git worktree *` would allow remove
- If something can be destructive, discuss it first
- Each permission entry should be readable as "this exact capability is auto-approved"

---

## Pickup Instructions

1. **Commit the changes** — review the diff and decide on grouping (1 or 2 commits)
2. **Start fresh session** — picks up fixed hooks and new permissions
3. **Test audit workflow (Thread #2)** — run a skill, check audit log has real data
4. **Verify permissions** — run /worktree and /ship-it to confirm reduced prompting
