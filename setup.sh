#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
cd "$CLAUDE_DIR"

echo "=== Claude Code Environment Setup ==="
echo ""

# --- Step 1: .mcp.json from template ---
if [ -f "$CLAUDE_DIR/.mcp.json" ]; then
  echo "[skip] .mcp.json already exists"
else
  if [ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
    echo "GITHUB_PERSONAL_ACCESS_TOKEN is not set in your environment."
    echo "Generate one at: https://github.com/settings/tokens"
    read -rp "Paste your GitHub PAT: " pat
    export GITHUB_PERSONAL_ACCESS_TOKEN="$pat"
    echo ""
    echo "Add this to your shell profile (~/.zshrc or ~/.zshenv):"
    echo "  export GITHUB_PERSONAL_ACCESS_TOKEN=\"$pat\""
    echo ""
  fi
  sed "s|\${GITHUB_PERSONAL_ACCESS_TOKEN}|${GITHUB_PERSONAL_ACCESS_TOKEN}|g" \
    "$CLAUDE_DIR/.mcp.json.template" > "$CLAUDE_DIR/.mcp.json"
  echo "[done] Created .mcp.json with your PAT"
fi

# --- Step 2: Create gitignored directories ---
for dir in projects debug telemetry file-history backups cache paste-cache \
           session-env shell-snapshots tasks todos plugins plans reviews \
           usage-data statsig .claude; do
  mkdir -p "$CLAUDE_DIR/$dir"
done
echo "[done] Created local-only directories"

# --- Step 3: Restore memory files into projects ---
if [ -d "$CLAUDE_DIR/memories" ]; then
  echo ""
  echo "Found portable memory files from previous machine."
  echo "These contain learned context about your projects."
  echo ""
  echo "Current memory sources:"
  for d in "$CLAUDE_DIR/memories"/*/; do
    [ -d "$d" ] || continue
    encoded=$(basename "$d")
    # Decode: replace leading dash, then dashes with /
    decoded=$(echo "$encoded" | sed 's/^-/\//;s/-/\//g')
    echo "  $decoded"
  done
  echo ""
  read -rp "Enter your projects base path (e.g., /Users/you/projects or /Volumes/data/projects): " new_base
  read -rp "Enter the OLD base path to replace (e.g., /Volumes/data/projects): " old_base

  # Encode paths for directory naming (replace / with -)
  old_encoded=$(echo "$old_base" | sed 's|/|-|g')
  new_encoded=$(echo "$new_base" | sed 's|/|-|g')

  restored=0
  for memdir in "$CLAUDE_DIR/memories"/*/; do
    [ -d "$memdir" ] || continue
    encoded=$(basename "$memdir")
    new_project_encoded="${encoded/$old_encoded/$new_encoded}"
    target="$CLAUDE_DIR/projects/$new_project_encoded/memory"
    mkdir -p "$target"
    command cp -r "$memdir"* "$target/" 2>/dev/null && ((restored++)) || true
  done
  echo "[done] Restored $restored project memory sets"
fi

# --- Step 4: Symlink bin/ scripts ---
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -L "$CLAUDE_DIR/bin" ]; then
  echo "[skip] bin symlink already exists"
elif [ -d "$CLAUDE_DIR/bin" ]; then
  echo "[warn] $CLAUDE_DIR/bin is a real directory, replacing with symlink"
  rm -rf "$CLAUDE_DIR/bin"
  ln -s "$REPO_DIR/bin" "$CLAUDE_DIR/bin"
  echo "[done] Created bin symlink"
else
  ln -s "$REPO_DIR/bin" "$CLAUDE_DIR/bin"
  echo "[done] Created bin symlink"
fi

# --- Step 5: Ensure nested settings.local.json ---
mkdir -p "$CLAUDE_DIR/.claude"
if [ ! -f "$CLAUDE_DIR/.claude/settings.local.json" ]; then
  cat > "$CLAUDE_DIR/.claude/settings.local.json" << 'JSONEOF'
{
  "enabledMcpjsonServers": [
    "github-cli"
  ],
  "enableAllProjectMcpServers": true
}
JSONEOF
  echo "[done] Created .claude/settings.local.json"
fi

# --- Step 6: Symlink review-guidelines.md ---
if [ -L "$CLAUDE_DIR/review-guidelines.md" ]; then
  echo "[skip] review-guidelines.md symlink already exists"
elif [ -f "$CLAUDE_DIR/review-guidelines.md" ]; then
  echo "[warn] review-guidelines.md is a real file, replacing with symlink"
  rm -f "$CLAUDE_DIR/review-guidelines.md"
  ln -s "$REPO_DIR/review-guidelines.md" "$CLAUDE_DIR/review-guidelines.md"
  echo "[done] Created review-guidelines.md symlink"
else
  ln -s "$REPO_DIR/review-guidelines.md" "$CLAUDE_DIR/review-guidelines.md"
  echo "[done] Created review-guidelines.md symlink"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Add GITHUB_PERSONAL_ACCESS_TOKEN to your shell profile if you haven't"
echo "  2. Run 'claude' in any project directory to start using Claude Code"
echo "  3. Plugins (playwright, atlassian, gopls) will auto-install on first use"
echo ""
