#!/usr/bin/env bash
# Outputs git repo info needed by worktree/ship-it workflows.
# Exit 1 if not inside a git repo.
#
# Output (one value per line):
#   is_git_repo: true|false
#   repo_name:   <basename of toplevel>
#   parent_dir:  <dirname of toplevel>
#   toplevel:    <absolute path to repo root>
#   branch:      <current branch name>

toplevel=$(git rev-parse --show-toplevel 2>/dev/null)

if [ -z "$toplevel" ]; then
  echo "is_git_repo: false"
  exit 1
fi

echo "is_git_repo: true"
echo "repo_name: $(basename "$toplevel")"
echo "parent_dir: $(dirname "$toplevel")"
echo "toplevel: $toplevel"
echo "branch: $(git branch --show-current 2>/dev/null)"
