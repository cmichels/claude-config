# Claude Code Config

Portable Claude Code environment — settings, custom commands, agents, hooks, and project memory.

## Why This Exists

I created this repository to build and version Claude skills, slash commands, and tool interoperability in one place while enforcing coding standards and guardrails.

As the Claude iteration cycle accelerated (tuning prompts, tightening constraints, automating workflows), I needed an environment that supports fast changes, durable history, and safe experimentation.

This repository provides a centralized, portable config system that persists across machines and can be symlinked like a dotfiles setup.

## Quick Setup (new machine)

```bash
# 1. Clone into ~/.claude
git clone git@github.com:cmichels/claude-config.git ~/.claude

# 2. Set your GitHub PAT
export GITHUB_PERSONAL_ACCESS_TOKEN="your-token-here"
# Add to ~/.zshrc or ~/.zshenv for persistence

# 3. (Optional) set local path variables for permission allowlists
export CLAUDE_PROJECTS_ROOT="$HOME/projects"
export CLAUDE_PRIMARY_PROJECT="work"

# 4. Run setup
cd ~/.claude && ./setup.sh
```

The setup script will:
- Generate `.mcp.json` from template with your PAT
- Generate machine-local `settings.json` from `settings.json.template`
- Apply `CLAUDE_PROJECTS_ROOT` and `CLAUDE_PRIMARY_PROJECT` values into path-specific permission rules
- Create required local directories (gitignored)
- Optionally restore project memory files with updated paths

### Required Local Settings

- `settings.json` is machine-local and intentionally gitignored.
- Tracked config lives in `settings.json.template` with placeholders.
- If `settings.json` already exists, setup preserves it.
- If `settings.json` is missing, setup generates it from the template.

## What's Tracked

| Path | Purpose |
|---|---|
| `CLAUDE.md` | Global instructions (personality, workflow, git conventions) |
| `settings.json.template` | Portable template for permissions, hooks, plugins, status line |
| `commands/` | Custom slash commands (/worktree, /ship-it, /review-pr-team, etc.) |
| `agents/` | Custom agent definitions (golang-expert, pr-review suite) |
| `hooks/` | Hook examples |
| `memories/` | Portable project memory (path-remappable) |
| `status-line.sh` | Custom status bar script |
| `.mcp.json.template` | MCP server config template (no secrets) |
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

## What's NOT Tracked

Session histories, debug logs, telemetry, caches, plugins (auto-reinstall), `.mcp.json` (contains PAT), `settings.json` (machine-local).

## Public vs Local Artifacts

| Type | Examples | Git status |
|---|---|---|
| Portable tracked config | `settings.json.template`, `commands/`, `agents/`, `bin/`, `CLAUDE.md` | Tracked |
| Machine-local generated config | `settings.json`, `.mcp.json` | Ignored |
| Local runtime state | `projects/`, `history.jsonl`, `cache/`, `tasks/`, `telemetry/` | Ignored |

## Updating Memory

Memory files in `memories/` are snapshots. As Claude learns new things per-project, run this to re-export:

```bash
cd ~/.claude
for memdir in projects/*/memory; do
  [ -d "$memdir" ] || continue
  project=$(echo "$memdir" | sed 's|projects/||;s|/memory||')
  mkdir -p "memories/$project"
  command cp -r "$memdir"/* "memories/$project/" 2>/dev/null || true
done
```
