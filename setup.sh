#!/usr/bin/env bash
set -euo pipefail

# Bootstrap a new machine: symlink this repo's config into ~/.claude.
#
# Topology: the repo lives OUTSIDE ~/.claude (e.g. ~/projects/personal/claude-config).
# ~/.claude holds symlinks into the repo plus machine-local runtime files.
# settings.json is generated into the repo working tree (gitignored) so the
# symlink target is owned by this machine but versioned alongside its template.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

if [ "$REPO_DIR" = "$CLAUDE_DIR" ]; then
  echo "error: this repo is cloned at ~/.claude itself." >&2
  echo "Clone it elsewhere and re-run, e.g.:" >&2
  echo "  git clone https://github.com/cmichels-engineering/claude-config ~/projects/personal/claude-config" >&2
  echo "  ~/projects/personal/claude-config/setup.sh" >&2
  exit 1
fi

echo "=== Claude Code Environment Setup ==="
echo "repo:   $REPO_DIR"
echo "target: $CLAUDE_DIR"
echo ""

mkdir -p "$CLAUDE_DIR"

# --- Step 1: settings.json from template (gitignored, machine-owned) ---
PROJECTS_ROOT_DEFAULT="$HOME/projects"
PRIMARY_PROJECT_DEFAULT="work"

if [ -f "$REPO_DIR/settings.json" ]; then
  echo "[skip] settings.json already exists in repo"
else
  project_root="${CLAUDE_PROJECTS_ROOT:-$PROJECTS_ROOT_DEFAULT}"
  primary_project="${CLAUDE_PRIMARY_PROJECT:-$PRIMARY_PROJECT_DEFAULT}"
  sed -e "s|__CLAUDE_PROJECTS_ROOT__|${project_root}|g" \
      -e "s|__CLAUDE_PRIMARY_PROJECT__|${primary_project}|g" \
      -e "s|__CLAUDE_HOME__|${HOME}|g" \
    "$REPO_DIR/settings.json.template" > "$REPO_DIR/settings.json"
  echo "[done] Generated settings.json from template"
  echo "       root=$project_root primary_project=$primary_project"
fi

# --- Step 2: symlink repo config into ~/.claude ---
LINKS=(settings.json CLAUDE.md review-guidelines.md status-line.sh friction-registry.yaml agents commands bin)

for name in "${LINKS[@]}"; do
  src="$REPO_DIR/$name"
  dst="$CLAUDE_DIR/$name"
  if [ ! -e "$src" ]; then
    echo "[warn] $name missing from repo; skipping"
    continue
  fi
  if [ -L "$dst" ]; then
    if [ "$(readlink "$dst")" = "$src" ]; then
      echo "[skip] $name already linked"
      continue
    fi
    echo "[warn] $name linked elsewhere ($(readlink "$dst")); relinking to repo"
    rm "$dst"
  elif [ -e "$dst" ]; then
    echo "[warn] $name exists as a real file/dir; backing up to $name.pre-setup.bak"
    mv "$dst" "$dst.pre-setup.bak"
  fi
  ln -s "$src" "$dst"
  echo "[done] Linked $name"
done

# --- Step 3: machine-local runtime directories ---
for dir in projects debug telemetry file-history backups cache paste-cache \
           session-env shell-snapshots tasks todos plugins plans reviews \
           usage-data statsig; do
  mkdir -p "$CLAUDE_DIR/$dir"
done
echo "[done] Created local runtime directories"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Next steps:"
echo "  1. Review the generated settings.json in the repo (gitignored, machine-owned)"
echo "  2. To carry auto-memory from an old machine, copy per-project memory dirs:"
echo "       old:~/.claude/projects/<encoded-path>/memory/ -> same path on this machine"
echo "     (dir names encode the project path; identical paths need no renaming)"
echo "  3. Run 'claude' in any project directory to start"
echo "  4. Plugins (playwright, context7, etc.) auto-install on first use"
