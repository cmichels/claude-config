# Permission Audit System for Claude Code

## What it does

Logs every tool Claude invokes during a session, then generates a report showing exactly what `--allowedTools` flags you need for autonomous skill execution. Lets you iteratively build locked-down permission profiles without guessing.

## Setup

### 1. Add the audit hook to `~/.claude/settings.json`

Add this as the **first entry** in the `hooks.PreToolUse` array. It fires on every tool call but is gated on an env var — zero cost when not auditing.

```json
{
  "matcher": "",
  "hooks": [
    {
      "type": "command",
      "command": "[ -z \"$CLAUDE_AUDIT_PERMISSIONS\" ] && exit 0; tool=\"$CLAUDE_TOOL_NAME\"; detail=$(echo \"$CLAUDE_TOOL_INPUT\" | jq -r '.command // .file_path // .skill // .query // .issueIdOrKey // \"—\"' 2>/dev/null); echo \"${tool}\t${detail}\" >> /tmp/claude-permission-audit.log; exit 0",
      "statusMessage": "Auditing tool use"
    }
  ]
}
```

**Where it goes in settings.json:**

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "[ -z \"$CLAUDE_AUDIT_PERMISSIONS\" ] && exit 0; tool=\"$CLAUDE_TOOL_NAME\"; detail=$(echo \"$CLAUDE_TOOL_INPUT\" | jq -r '.command // .file_path // .skill // .query // .issueIdOrKey // \"—\"' 2>/dev/null); echo \"${tool}\t${detail}\" >> /tmp/claude-permission-audit.log; exit 0",
            "statusMessage": "Auditing tool use"
          }
        ]
      }
      // ... your other PreToolUse hooks go after this
    ]
  }
}
```

### 2. Save the report script

Save to `~/.claude/bin/permission-audit.sh` (or anywhere in `$PATH`), then `chmod +x` it.

**On WSL2:** Also run `sed -i 's/\r//' permission-audit.sh` to fix line endings if your editor writes CRLF.

```bash
#!/usr/bin/env bash
# Generates a permission profile from a Claude tool audit log.
#
# Usage:
#   permission-audit.sh [logfile]
#
# Default logfile: /tmp/claude-permission-audit.log
#
# Workflow:
#   1. Enable auditing:  export CLAUDE_AUDIT_PERMISSIONS=1
#   2. Run your skill:   claude '/review-pr 199'
#   3. Generate report:  permission-audit.sh
#   4. Copy the --allowedTools output into your launcher script
#   5. Clean up:         permission-audit.sh --clean
#
# Output sections:
#   - Raw log (what was called)
#   - Unique tool summary
#   - Suggested --allowedTools patterns
#   - Diff against global settings.json allowlist

set -euo pipefail

LOGFILE="${1:-/tmp/claude-permission-audit.log}"
SETTINGS="$HOME/.claude/settings.json"

# Handle --clean flag
if [ "${1:-}" = "--clean" ]; then
  rm -f /tmp/claude-permission-audit.log
  echo "Audit log cleaned."
  exit 0
fi

if [ ! -f "$LOGFILE" ]; then
  echo "No audit log found at: $LOGFILE"
  echo ""
  echo "To start auditing:"
  echo "  export CLAUDE_AUDIT_PERMISSIONS=1"
  echo "  claude '/your-skill args'"
  echo "  permission-audit.sh"
  exit 1
fi

total=$(wc -l < "$LOGFILE")
echo "=== PERMISSION AUDIT REPORT ==="
echo "Log: $LOGFILE ($total tool calls)"
echo ""

# --- Section 1: Unique tools summary ---
echo "--- TOOL USAGE SUMMARY ---"
echo ""

# Extract tool names and count occurrences
awk -F'\t' '{print $1}' "$LOGFILE" | sort | uniq -c | sort -rn | while read -r count name; do
  printf "  %4d  %s\n" "$count" "$name"
done
echo ""

# --- Section 2: Bash commands (the interesting part) ---
echo "--- BASH COMMANDS USED ---"
echo ""

grep '^Bash' "$LOGFILE" | awk -F'\t' '{print $2}' | sort -u | while read -r cmd; do
  prefix=$(echo "$cmd" | awk '{print $1, $2}')
  echo "  $cmd"
done
echo ""

# --- Section 3: Non-Bash tools ---
echo "--- NON-BASH TOOLS USED ---"
echo ""

grep -v '^Bash' "$LOGFILE" | awk -F'\t' '{print $1}' | sort -u | while read -r tool; do
  echo "  $tool"
done
echo ""

# --- Section 4: Suggested --allowedTools patterns ---
echo "--- SUGGESTED --allowedTools ---"
echo ""

# Bash patterns: group by first two words, add wildcard
bash_patterns=$(grep '^Bash' "$LOGFILE" | awk -F'\t' '{print $2}' | \
  awk '{
    # For git/gh commands, use first 2-3 words as pattern
    if ($1 == "git" || $1 == "gh") {
      print $1 " " $2 "*"
    }
    # For absolute paths (bin scripts), use as-is with wildcard
    else if (substr($1, 1, 1) == "/") {
      print $1 "*"
    }
    # For everything else, first word + wildcard
    else {
      print $1 "*"
    }
  }' | sort -u)

non_bash=$(grep -v '^Bash' "$LOGFILE" | awk -F'\t' '{print $1}' | sort -u)

echo "# Paste into your launcher script's --allowedTools:"
echo "claude --allowedTools \\"

# Non-bash tools first
while IFS= read -r tool; do
  [ -n "$tool" ] && echo "  \"$tool\" \\"
done <<< "$non_bash"

# Bash patterns
while IFS= read -r pattern; do
  [ -n "$pattern" ] && echo "  \"Bash($pattern)\" \\"
done <<< "$bash_patterns"

echo '  "Read" "Glob" "Grep"'
echo ""

# --- Section 5: Coverage check against global settings ---
if [ -f "$SETTINGS" ]; then
  echo "--- COVERAGE CHECK (vs global settings.json) ---"
  echo ""

  # Extract current allow list
  allowed=$(jq -r '.permissions.allow[]' "$SETTINGS" 2>/dev/null)

  echo "Already covered by global settings:"
  already_covered=0
  not_covered=0

  while IFS= read -r tool; do
    [ -z "$tool" ] && continue
    covered=false
    while IFS= read -r rule; do
      # Simple prefix match (not full glob, but good enough for reporting)
      rule_prefix="${rule%\*}"
      if [ "$tool" = "$rule" ] || [[ "$tool" == "$rule_prefix"* ]]; then
        covered=true
        break
      fi
    done <<< "$allowed"

    if $covered; then
      echo "  [COVERED]  $tool"
      already_covered=$((already_covered + 1))
    else
      echo "  [MISSING]  $tool  <-- add to --allowedTools"
      not_covered=$((not_covered + 1))
    fi
  done <<< "$non_bash"

  # Check bash patterns
  grep '^Bash' "$LOGFILE" | awk -F'\t' '{print $2}' | sort -u | while read -r cmd; do
    covered=false
    while IFS= read -r rule; do
      case "$rule" in
        Bash\(*)
          # Extract the pattern inside Bash(...)
          pattern="${rule#Bash(}"
          pattern="${pattern%)}"
          pattern_prefix="${pattern%\*}"
          if [[ "$cmd" == "$pattern_prefix"* ]]; then
            covered=true
            break
          fi
          ;;
      esac
    done <<< "$allowed"

    if $covered; then
      echo "  [COVERED]  Bash: $cmd"
    else
      echo "  [MISSING]  Bash: $cmd  <-- add to --allowedTools"
    fi
  done

  echo ""
  echo "Summary: $already_covered covered, $not_covered missing (non-Bash tools)"
fi

echo ""
echo "=== END REPORT ==="
```

## Usage

```bash
# 1. Enable auditing in your shell
export CLAUDE_AUDIT_PERMISSIONS=1

# 2. Run any skill normally (approve everything as prompted)
claude '/review-pr 199'

# 3. After the session, generate the report
~/.claude/bin/permission-audit.sh

# 4. Clean up when done
~/.claude/bin/permission-audit.sh --clean
```

## Example output

```
=== PERMISSION AUDIT REPORT ===
Log: /tmp/claude-permission-audit.log (47 tool calls)

--- TOOL USAGE SUMMARY ---

    22  Bash
     9  Read
     5  Grep
     4  Task
     3  Write
     2  Glob
     2  AskUserQuestion

--- BASH COMMANDS USED ---

  curl -sL -H "Authorization: token ..." -o /tmp/pr-review-screenshots/screenshot-0.png
  gh api repos/owner/repo/pulls/199/files --paginate
  gh api -X POST repos/owner/repo/pulls/199/reviews --input /tmp/pr-review-payload.json
  gh pr diff 199 --stat
  gh pr view 199 --json title,body,headRefName
  git remote get-url origin
  mkdir -p /tmp/pr-review-screenshots
  rm -rf /tmp/pr-review-screenshots

--- NON-BASH TOOLS USED ---

  AskUserQuestion
  Glob
  Grep
  Read
  Task
  Write

--- SUGGESTED --allowedTools ---

# Paste into your launcher script's --allowedTools:
claude --allowedTools \
  "AskUserQuestion" \
  "Glob" \
  "Grep" \
  "Read" \
  "Task" \
  "Write" \
  "Bash(curl*)" \
  "Bash(gh api*)" \
  "Bash(gh pr*)" \
  "Bash(git remote*)" \
  "Bash(mkdir*)" \
  "Bash(rm*)" \
  "Read" "Glob" "Grep"

--- COVERAGE CHECK (vs global settings.json) ---

  [COVERED]  Read
  [COVERED]  Glob
  [COVERED]  Grep
  [COVERED]  AskUserQuestion
  [MISSING]  Task  <-- add to --allowedTools
  [MISSING]  Write  <-- add to --allowedTools
  [COVERED]  Bash: git remote get-url origin
  [COVERED]  Bash: gh pr diff 199 --stat
  [COVERED]  Bash: gh pr view 199 --json title,body,headRefName
  [COVERED]  Bash: gh api repos/owner/repo/pulls/199/files --paginate
  [MISSING]  Bash: mkdir -p /tmp/pr-review-screenshots  <-- add to --allowedTools
  [MISSING]  Bash: rm -rf /tmp/pr-review-screenshots  <-- add to --allowedTools

Summary: 4 covered, 2 missing (non-Bash tools)

=== END REPORT ===
```

## How it fits into automation

Once you have the `--allowedTools` list from the report, use it in launcher scripts or automation tools:

```bash
# Autonomous but locked down:
# --permission-mode dontAsk = auto-DENY anything not listed
# --allowedTools = auto-APPROVE these specific tools
claude --permission-mode dontAsk \
  --allowedTools \
    "Write" \
    "Task" \
    "Bash(gh pr*)" \
    "Bash(git remote*)" \
    "Bash(mkdir -p /tmp/*)" \
  '/review-pr 199'
```

## Key concepts

- **`--allowedTools`** accepts the same pattern syntax as `settings.json` permissions (e.g., `Bash(git worktree*)`, `Bash(gh pr diff*)`)
- **`--permission-mode dontAsk`** combined with `--allowedTools` gives you a closed permission set — listed tools are approved, everything else is silently denied
- **CLI flags are additive** to your global `~/.claude/settings.json` — they augment, not replace
- **The audit hook has zero cost when not active** — it checks `$CLAUDE_AUDIT_PERMISSIONS` first and exits immediately if unset

## Prerequisites

- `jq` (for parsing settings.json and tool input in the hook)
- Claude Code CLI (`claude`)
- Bash 4+
