# Claude Code Config

Portable Claude Code environment — settings, custom commands, agents, hooks, and project memory.

## Why This Exists

I created this repository to build and version Claude skills, slash commands, and tool interoperability in one place while enforcing coding standards and guardrails.

As the Claude iteration cycle accelerated (tuning prompts, tightening constraints, automating workflows), I needed an environment that supports fast changes, durable history, and safe experimentation.

This repository provides a centralized, portable config system that persists across machines and can be symlinked like a dotfiles setup.

## Prerequisites

Required before setup — the config assumes these exist:

- `git`, `gh` (authenticated: `gh auth login`), `jq`, `zsh`, and `python3` — hooks depend on `jq`; the status line runs under `zsh` and uses `jq` and `python3`
- GPG signing configured: key imported, `commit.gpgsign true`, `user.signingkey` set, and on WSL2 `pinentry-mode loopback` in `~/.gnupg/gpg.conf` — all commits are signed, and a hook warns on unsigned ones
- WSL2 only: `win32yank` on `$PATH` for clipboard bridging

Optional, degrade gracefully if absent:

- `yq` — enables the preflight script's friction-registry checks
- `acli` for Jira workflows — install with `./install-acli.sh`
- Go toolchain — enables the auto-`gofmt`/`go vet` hook on Go file edits
- `task-ctl` on `$PATH` — companion CLI from the private `starkmichelsc/task-ctl` repo; required only by `/k-suspend` and `/k-resume`
- A Nerd Font in the terminal — the status line renders Nerd Font glyphs (built against MesloLGS NF)

## Quick Setup (new machine)

```bash
# 1. Clone the repo (NOT into ~/.claude — the script refuses that)
git clone https://github.com/cmichels-engineering/claude-config ~/projects/personal/claude-config

# 2. (Optional) set local path variables for permission allowlists
export CLAUDE_PROJECTS_ROOT="$HOME/projects"
export CLAUDE_PRIMARY_PROJECT="work"

# 3. Run setup
~/projects/personal/claude-config/setup.sh
```

The setup script will:
- Generate `settings.json` from `settings.json.template` into the repo working tree (gitignored)
- Apply `CLAUDE_PROJECTS_ROOT` and `CLAUDE_PRIMARY_PROJECT` values into path-specific permission rules
- Symlink `settings.json`, `CLAUDE.md`, `review-guidelines.md`, `status-line.sh`, `agents/`, `commands/`, and `bin/` into `~/.claude/`
- Create required local runtime directories in `~/.claude/`

The script is idempotent — re-running skips anything already in place, and pre-existing real files in `~/.claude/` are backed up to `*.pre-setup.bak` before being replaced with symlinks.

### Required Local Settings

- `settings.json` lives in the repo working tree but is intentionally gitignored (machine-local).
- Tracked config lives in `settings.json.template` with placeholders.
- If `settings.json` already exists, setup preserves it.
- If `settings.json` is missing, setup generates it from the template.

## What's Tracked

| Path | Purpose |
|---|---|
| `CLAUDE.md` | Global instructions (personality, workflow, git conventions) |
| `settings.json.template` | Portable template for permissions, hooks, plugins, status line |
| `commands/` | Custom slash commands (/worktree, /ship-it, /review-pr-team, etc.) |
| `agents/` | Custom agent definitions (pr-review suite: security, code quality, architecture, style) |
| `hooks/` | Hook examples |
| `status-line.sh` | Custom status bar script |
| `setup.sh` | New machine bootstrap |
| `bin/` | CLI scripts (session management, repo helpers) |

## Works with pr-monitor

This repository pairs with `pr-monitor` in a terminal-first workflow:

- `claude-config` defines the environment, guardrails, and command automation.
- `pr-monitor` provides PR monitoring and review context in the terminal.
- Together they reduce context switching and improve execution flow.

## bin/ — CLI Scripts

Session management tools for running multiple Claude sessions across tmux windows.

| Script | Usage | Description |
|---|---|---|
| `ccs` | `ccs [args...]` | Start a new Claude session. Generates a session ID, saves it keyed to the current tmux pane, and launches `claude --session-id <id> --name <window>`. All args passed through. |
| `cr` | `cr [args...]` | Resume the saved session for the current tmux pane. Falls back to cwd-based lookup if pane ID isn't found. |
| `cls` | `cls` | List all saved pane-session mappings (pane, window name, cwd, session ID, timestamp). |
| `ccc` | `ccc [-a]` | Clean stale pane-session mappings for panes no longer in tmux; `-a` removes all saved sessions. |

Session state is stored in `~/.claude/pane-sessions/<pane-id>.json`.

### Setup

Scripts are symlinked to `~/.local/bin/` (must be in `$PATH`):

```bash
ln -sf ~/projects/personal/claude-config/bin/ccs ~/.local/bin/ccs
ln -sf ~/projects/personal/claude-config/bin/cr ~/.local/bin/cr
ln -sf ~/projects/personal/claude-config/bin/cls ~/.local/bin/cls
```

Optional alias in your shell config:

```bash
alias claude=ccs
```

Also includes utility scripts used by Claude Code skills:

| Script | Description |
|---|---|
| `repo-info.sh` | Outputs git repo metadata (name, branch, toplevel path) |
| `worktree-exists.sh` | Checks if a directory exists (exit 0/1) |
| `worktree-check-configs.sh` | Detects (and with `--copy`, copies) local config files from a source repo into a worktree |
| `pr-review-threads.sh` | Fetches PR review threads with resolution status via GitHub GraphQL (read-only) |
| `find-session.sh` | Locates a screenshot `session.json` in priority order (used by /screenshot) |
| `permission-audit.sh` | Generates a permission profile from a Claude tool audit log |
| `claude-preflight.sh` | WSL2 environment preflight (gpg-agent, pinentry, clipboard, PATH); `--once` mode runs from a PreToolUse hook |

## What's NOT Tracked

Session histories, debug logs, telemetry, caches, plugins (auto-reinstall), `settings.json` (machine-local).

## Public vs Local Artifacts

| Type | Examples | Git status |
|---|---|---|
| Portable tracked config | `settings.json.template`, `commands/`, `agents/`, `bin/`, `CLAUDE.md` | Tracked |
| Machine-local generated config | `settings.json` | Ignored |
| Local runtime state | `projects/`, `history.jsonl`, `cache/`, `tasks/`, `telemetry/` | Ignored |

## Moving Memory to a New Machine

Per-project auto-memory lives in `~/.claude/projects/<encoded-path>/memory/` and is not tracked in this repo. To carry it to a new machine, copy each project's `memory/` directory to the same encoded path under the new machine's `~/.claude/projects/`. Directory names encode the project's absolute path — if project paths are identical across machines, no renaming is needed.
