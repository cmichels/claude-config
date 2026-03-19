#!/usr/bin/env bash
# Searches for a screenshot session.json in priority order.
# Usage: find-session.sh [dir]
#   If dir is provided, checks $dir/session.json first.
#   Then falls back to ./session.json and ./screenshots/session.json.
#
# Output: Prints the path and contents of the first session.json found.
#   FOUND: <path>
#   <contents>
# Or: NO_SESSION (exit 1)

set -euo pipefail

dir="${1:-}"
found=""

for p in ${dir:+"$dir/session.json"} "./session.json" "./screenshots/session.json"; do
  if [ -f "$p" ]; then
    found="$p"
    break
  fi
done

if [ -n "$found" ]; then
  echo "FOUND: $found"
  cat "$found"
else
  echo "NO_SESSION"
  exit 1
fi
