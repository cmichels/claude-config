#!/usr/bin/env bash
# Detect and optionally copy config files from source repo to worktree.
# Usage:
#   worktree-check-configs.sh <SOURCE_DIR> <DEST_DIR>          # check only
#   worktree-check-configs.sh <SOURCE_DIR> <DEST_DIR> --copy   # check and copy

set -euo pipefail

SOURCE="${1:?Usage: worktree-check-configs.sh <SOURCE_DIR> <DEST_DIR> [--copy]}"
DEST="${2:?Usage: worktree-check-configs.sh <SOURCE_DIR> <DEST_DIR> [--copy]}"
COPY="${3:-}"

copy_dir() {
  local name="$1"
  if [ -d "$SOURCE/$name" ]; then
    echo "$name: EXISTS"
    if [ "$COPY" = "--copy" ]; then
      mkdir -p "$(dirname "$DEST/$name")"
      command cp -r "$SOURCE/$name" "$DEST/$name"
      echo "  copied: $name"
    fi
  else
    echo "$name: MISSING"
  fi
}

copy_file() {
  local name="$1"
  if [ -f "$SOURCE/$name" ]; then
    echo "$name: EXISTS"
    if [ "$COPY" = "--copy" ]; then
      mkdir -p "$(dirname "$DEST/$name")"
      command cp "$SOURCE/$name" "$DEST/$name"
      echo "  copied: $name"
    fi
  else
    echo "$name: MISSING"
  fi
}

echo "=== Config files ==="
copy_dir ".claude"
copy_file ".local"
copy_file ".env"
copy_file ".env.local"
copy_file ".env.development"
copy_file "docker-compose.yml"
copy_file "docker-compose.override.yml"
copy_dir ".ralph"
copy_dir "ClientApp/src/environments"
echo "=== Done ==="
