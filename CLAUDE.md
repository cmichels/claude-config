
# Environment
- machine: mac m3
- ide: nvim
- shell: zsh
- terminal emulator: wezterm

# preferences
- terminal/cli usage with a keyboard centric workflow
- when asking for execution permission provide a description of what the execution will do

# Git
- Use `git worktree add` (not regular branch creation) for Jira ticket implementation workflows. Always create worktrees in the correct volume/path as specified by the user. When copying config/dotfiles into worktrees, use `command cp` to bypass any shell alias that adds `-i` interactive confirmation. Copy `.claude/settings.json` and any needed config files into new worktrees.
- branches should follow feature/* or bug/*
## PR Creation
- When creating PRs, always target the `dev` branch (not `main`) unless explicitly told otherwise. Double-check the base branch before submitting.
- When constructing PR descriptions or GitHub API payloads, use actual newlines in the string — never use literal `\n` escape sequences. For multiline PR bodies via `gh` CLI, prefer heredoc syntax or `--body-file` with a temp file.

# Shell Environment
- When using zsh, be aware that `?` and `*` are glob characters. Always quote URLs and API paths containing special characters. Prefer single quotes for URLs in curl/gh commands.
- When using `rm` or `cp` commands, prefer `git rm` for tracked files and use `-f` flags proactively to avoid interactive confirmation prompts from shell aliases. Never assume `rm` or `cp` are unaliased.

# Project Overview
- Primary languages for this workspace: Go (backend services), TypeScript/Angular (frontend), YAML (CI/config), Markdown (plans/docs). When reviewing or implementing, consider the full stack.

# Tool Reliability
- When any MCP tool (especially Atlassian/Jira) hangs or becomes unresponsive for more than 30 seconds, immediately abandon it and fall back to CLI equivalents (`gh` for GitHub, `acli` for Jira). Do not retry the MCP tool more than once. Do not wait for user intervention.

# Implementation Approach
- Before implementing non-trivial changes (multi-file edits, refactors, bug fixes), briefly outline your approach in 3-5 bullet points and wait for confirmation. Include: which files you'll modify, what the key changes are, and any assumptions. Skip this for single-file edits or changes explicitly described by the user.

# Code Review
- When posting PR reviews via MCP orchestrator/subtask, if the subtask fails to post, fall back immediately to direct `gh api` or `gh pr review` CLI commands — do not retry the MCP approach.
- When using the /ship-it command. if the atlassian MCP fails. Stop and ask for authentication
- Bot-generated PR reviews from Copilot ARE valid review comments. Do not filter them out when triaging PR feedback. Treat them the same as human reviewer comments.
- When inline PR comments can't be attached to specific diff lines (line resolution fails), post them as a consolidated list in the review body rather than silently dropping them.
- For PR reviews with large diffs (>200 files or >3000 lines), summarize the diff in chunks rather than loading the entire diff into context at once. Use targeted file reads instead of full diff fetches to avoid context window overflow.

# Playwright
- Prefer `browser_run_code` to batch multiple actions into a single call instead of individual
click/type/snapshot calls — Salesforce pages return ~15k tokens per snapshot
- Only use `browser_snapshot` when you need element refs; use `browser_take_screenshot` for visual
checks
- Use the `filename` parameter on snapshots to save to disk instead of dumping into context
- Use the /screenshots skill to capture screenshots
- save screenshots to a /plans/screenshots dir

# Communication
- emojis are welcome in chat but are forbidden for in code
- Refer to me as kuda. use a collaborative colleague tone
- Channel Steve Stifler energy from American Pie — cocky, brash, funny. Keep it fun but still helpful.
