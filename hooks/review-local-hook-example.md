# Review Local Hook Examples

This document shows example hook configurations for integrating `/review-local` into your workflow.

## Git Pre-Push Hook (Recommended)

Create `.git/hooks/pre-push`:

```bash
#!/bin/bash
# Pre-push hook to run code review before pushing

# Get the current branch
BRANCH=$(git branch --show-current)

# Skip for main/master branches
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
    exit 0
fi

# Check if review already exists and is recent (within 1 hour)
REVIEW_FILE="./reviews/${BRANCH//\//-}-review.md"
if [ -f "$REVIEW_FILE" ]; then
    REVIEW_AGE=$(($(date +%s) - $(stat -f %m "$REVIEW_FILE")))
    if [ $REVIEW_AGE -lt 3600 ]; then
        echo "Recent review exists: $REVIEW_FILE"
        exit 0
    fi
fi

echo "Running code review for branch: $BRANCH"
echo "Run '/review-local' in Claude Code to generate review before pushing."

# Optional: Prompt to continue without review
read -p "Continue without review? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi
```

## Claude Code Settings Hook

Add to `~/.claude/settings.json` (or project `.claude/settings.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "command": "if echo \"$TOOL_INPUT\" | grep -q 'git push'; then echo 'Consider running /review-local first'; fi"
      }
    ]
  }
}
```

## Automatic Review on Branch Switch

For `.claude/settings.json` in your project:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "if echo \"$TOOL_INPUT\" | grep -qE 'git (checkout|switch)'; then echo 'HINT: Run /review-local to review changes on this branch'; fi"
          }
        ]
      }
    ]
  }
}
```

## Integration with /ship-it

The `/review-local` command can be used as a pre-step before `/ship-it`:

1. Run `/review-local` to generate comprehensive review
2. Address any blocking issues
3. Run `/ship-it` to commit, push, and create PR
4. The review file can inform your PR description

## Keyboard Shortcuts (nvim integration)

Add to your nvim config to quickly trigger review:

```lua
-- Map <leader>cr to run claude code review
vim.keymap.set('n', '<leader>cr', function()
  vim.cmd('terminal claude /review-local')
end, { desc = 'Claude Code Review' })
```

## Review File Locations

By default, reviews are saved to:
- `./reviews/<branch-name>-review.md` (project-local)

You can also configure a global reviews directory:
- `~/.claude/reviews/<repo>-<branch>-review.md`
