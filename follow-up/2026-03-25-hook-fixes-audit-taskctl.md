# Session: Hook Fixes, Audit Workflow, and task-ctl Phase 1
## Date: 2026-03-25

## What Was Done

### 1. Committed Previous Session's Changes (4 commits on claude-config/dev)

- `92f97ce` — Rewrite hooks to use stdin JSON, add ~15 permissions for reduced prompting
- `d55ae0f` — Improve skill prompts: --model flag on review-pr-team, tool discipline on ship-it/worktree
- `3e5a84f` — Add docs, follow-ups, and uv project scaffold
- `fc65372` — Add 2 Jira MCP permissions, fix audit script (empty names, quote matching)

### 2. Audit Workflow Verified (Thread #2)

- Confirmed hooks capture clean data (zero empty tool names with fixed stdin parsing)
- Ran full `permission-audit.sh` report against 239 fresh tool calls
- Coverage check correctly identifies gaps vs settings.json allowlist
- Fixed audit script: filters empty tool names, strips quotes for Bash prefix matching
- Added `getTransitionsForJiraIssue` and `lookupJiraAccountId` to permissions

### 3. Rainbow Status Line

- Added `rainbow_text()` function to `status-line.sh`
- Per-character rainbow gradient using 256-color ANSI palette (8 colors cycling)
- Strips existing semantic colors, re-applies rainbow on output
- Committed: `64f1b48`

### 4. task-ctl Phase 1 — COMPLETE

New project: `~/projects/personal/task-ctl/`

**Created:**
- Go project scaffold (go.mod, Makefile, CLAUDE.md, .gitignore)
- `internal/db/db.go` — shared SQLite connection (WAL, busy timeout, same DB as pr-monitor)
- `internal/db/tasks.go` — Task type + full CRUD (Register, List, Get, UpdateStatus, LinkPR, UpdateGitState, StoreContextDump)
- `internal/db/tasks_test.go` — 10 tests, all passing
- `cmd/task-ctl/main.go` — Cobra CLI with register, list, show, complete, link-pr commands
- `plans/task-ctl-plan.md` — Full 7-phase architecture plan

**Verified:**
- Build: `go build && go vet && go test` all clean
- Installed to `~/go/bin/task-ctl`
- Smoke tested: register → list → show → link-pr → complete against real shared DB
- Shared DB coexistence with pr-monitor confirmed

**Initial commit:** `fca6419` on `task-ctl/dev`

## What's NOT Done

### claude-config: 6 commits ahead of origin, not pushed
All changes on `dev` branch, ready to push when desired.

### task-ctl: Phases 2-7 remaining

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Scaffold + Core CRUD | COMPLETE |
| 2 | Git State + Complete | READY |
| 3 | Suspend/Resume + tmux | READY (depends on Phase 2) |
| 4 | Worktree Removal + Safety Gates | Depends on Phase 2 |
| 5 | PR Linkage + Auto-scan | Depends on Phase 1 (done) |
| 6 | Claude Code Skill Integration | Depends on Phases 3-5 |
| 7 | pr-monitor TUI Integration | Depends on Phase 5 |

### Recommended Pickup Order

**Phase 2** (git state capture) is the natural next step — it's small, self-contained, and unblocks Phases 3 and 4.

Then **Phase 3** (suspend/resume) is the high-value feature — the whole shutdown/startup workflow.

Phase 5 (auto-scan) can happen in parallel since it only depends on Phase 1.

## Key Decisions Made

- **task-ctl is a separate Go project** — not a pr-monitor subcommand
- **Shared DB** — `~/.local/share/pr-monitor/pr-monitor.db`, task-ctl owns `tasks` table
- **Cobra for CLI** — needed for multi-subcommand architecture
- **modernc.org/sqlite** — pure Go, no CGo (same driver as pr-monitor)
- **Context dump: dual storage** — file in worktree + TEXT blob in DB
- **Safety gates on removal** — block on uncommitted/unpushed, warn on open PR, `--force` to override
- **Resume uses `claude -c` first** — falls back to plan + context dump

## Files Changed This Session

### claude-config (6 commits)
- `settings.json` — hooks rewritten, ~17 new permissions
- `bin/worktree-check-configs.sh` — NEW
- `bin/permission-audit.sh` — bug fixes
- `commands/review-pr-team.md` — --model flag
- `commands/ship-it.md` — tool discipline, hardcoded username
- `commands/worktree.md` — bin script, Write tool, tool table
- `status-line.sh` — rainbow gradient
- `docs/permission-audit-setup.md` — NEW
- `follow-up/` — session dumps (4 files)
- `.python-version`, `pyproject.toml`, `uv.lock`, `main.py` — uv scaffold

### task-ctl (initial commit)
- Full Phase 1 implementation (10 files, 1455 LOC)
