#!/usr/bin/env bash
# Checks whether a worktree path already exists.
# Usage: worktree-exists.sh <path>
# Exits 0 and prints EXISTS if found, exits 1 and prints NOT_EXISTS if not.

if [ -z "$1" ]; then
  echo "Usage: worktree-exists.sh <path>" >&2
  exit 2
fi

if [ -d "$1" ]; then
  echo "EXISTS"
  exit 0
else
  echo "NOT_EXISTS"
  exit 1
fi
