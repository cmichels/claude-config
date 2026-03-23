# Claude Code Config

Portable Claude Code environment — settings, custom commands, agents, hooks, and project memory.

## Quick Setup (new machine)

```bash
# 1. Clone into ~/.claude
git clone git@github.com:starkmichelsc/claude-config.git ~/.claude

# 2. Set your GitHub PAT
export GITHUB_PERSONAL_ACCESS_TOKEN="your-token-here"
# Add to ~/.zshrc or ~/.zshenv for persistence

# 3. Run setup
cd ~/.claude && ./setup.sh
```

The setup script will:
- Generate `.mcp.json` from template with your PAT
- Create required local directories (gitignored)
- Optionally restore project memory files with updated paths

## What's Tracked

| Path | Purpose |
|---|---|
| `CLAUDE.md` | Global instructions (personality, workflow, git conventions) |
| `settings.json` | Permissions, hooks, plugins, status line |
| `commands/` | Custom slash commands (/worktree, /ship-it, /review-pr-team, etc.) |
| `agents/` | Custom agent definitions (golang-expert, pr-review suite) |
| `hooks/` | Hook examples |
| `memories/` | Portable project memory (path-remappable) |
| `status-line.sh` | Custom status bar script |
| `.mcp.json.template` | MCP server config template (no secrets) |
| `setup.sh` | New machine bootstrap |
| `bin/` | CLI scripts (session management, repo helpers) |

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

Session histories, debug logs, telemetry, caches, plugins (auto-reinstall), `.mcp.json` (contains PAT).

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
