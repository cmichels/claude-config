# Review PR Toolkit - Installation Guide

A comprehensive PR review command for Claude Code that performs code quality, security, style, and architecture reviews, then posts findings directly to GitHub.

## Contents

- `commands/review-pr.md` - Main command entry point
- `agents/pr-orchestrator.md` - Coordinates the 4 specialized reviewers
- `agents/pr-code-review.md` - Code quality analysis (logic, errors, tests)
- `agents/pr-security-scan.md` - Security vulnerability scanning (OWASP Top 10)
- `agents/pr-style-check.md` - Style and convention review
- `agents/pr-architect-review.md` - Architecture and design review

## Installation

### 1. Extract the zip to ~/.claude

```bash
# Navigate to your home directory
cd ~

# Extract the zip file (preserves folder structure)
unzip review-pr-toolkit.zip -d ~/.claude
```

This places:
- `review-pr.md` into `~/.claude/commands/`
- All agent files into `~/.claude/agents/`

### 2. Verify installation

```bash
# Check command exists
ls ~/.claude/commands/review-pr.md

# Check agents exist
ls ~/.claude/agents/pr-*.md
```

You should see:
```
/Users/<you>/.claude/commands/review-pr.md
/Users/<you>/.claude/agents/pr-architect-review.md
/Users/<you>/.claude/agents/pr-code-review.md
/Users/<you>/.claude/agents/pr-orchestrator.md
/Users/<you>/.claude/agents/pr-security-scan.md
/Users/<you>/.claude/agents/pr-style-check.md
```

### 3. Configure GitHub MCP Server (Required)

The toolkit uses GitHub MCP tools to fetch PR data and post reviews. Add the GitHub MCP server to your Claude settings:

**Option A: Via Claude Code CLI**
```bash
claude mcp add github-cli
```

**Option B: Manual configuration**

Add to `~/.claude/settings.json`:
```json
{
  "mcpServers": {
    "github-cli": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-server-github"]
    }
  }
}
```

**Option C: Using gh CLI wrapper**

If you have `gh` CLI installed and authenticated:
```json
{
  "mcpServers": {
    "github-cli": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_TOKEN": "<your-token>"
      }
    }
  }
}
```

### 4. Authenticate with GitHub

Ensure you have a GitHub token with repo access:
```bash
# Using gh CLI (recommended)
gh auth login

# Or set environment variable
export GITHUB_TOKEN=ghp_xxxxxxxxxxxx
```

## Usage

Navigate to any git repository with a GitHub remote, then:

```bash
# Review a specific PR
/review-pr 123

# Claude will:
# 1. Detect the repo from git remote
# 2. Fetch PR details, files, and existing reviews
# 3. Run 4 parallel review agents
# 4. Post a consolidated review to GitHub
```

## What Gets Reviewed

| Agent | Checks For |
|-------|------------|
| **Code Review** | Logic errors, error handling, resource leaks, test coverage |
| **Security Scan** | Injection, auth issues, data exposure, OWASP Top 10 |
| **Style Check** | Naming conventions, formatting, documentation |
| **Architecture** | Design patterns, modularity, scalability, tech debt |

## Output

The toolkit posts a GitHub review with:
- Summary verdict (Approve / Request Changes / Comment)
- Findings organized by category
- Inline comments on specific lines
- Severity ratings for issues

## Troubleshooting

**"MCP tool not found"**
- Ensure GitHub MCP server is configured in settings
- Restart Claude Code after adding MCP configuration

**"Could not detect repository"**
- Run from within a git repository
- Ensure remote is set: `git remote -v`

**"Permission denied"**
- Check GitHub token has `repo` scope
- Re-authenticate: `gh auth login`

**Review not posting**
- Verify you have write access to the repository
- Check PR number is correct

## Uninstall

```bash
rm ~/.claude/commands/review-pr.md
rm ~/.claude/agents/pr-orchestrator.md
rm ~/.claude/agents/pr-code-review.md
rm ~/.claude/agents/pr-security-scan.md
rm ~/.claude/agents/pr-style-check.md
rm ~/.claude/agents/pr-architect-review.md
```
