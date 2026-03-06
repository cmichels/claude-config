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
| `commands/` | Custom slash commands (/worktree, /ship-it, /review-pr, etc.) |
| `agents/` | Custom agent definitions (golang-expert, pr-review suite) |
| `hooks/` | Hook examples |
| `memories/` | Portable project memory (path-remappable) |
| `status-line.sh` | Custom status bar script |
| `.mcp.json.template` | MCP server config template (no secrets) |
| `setup.sh` | New machine bootstrap |

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
