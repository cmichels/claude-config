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
  # Extract the first two words to suggest a pattern
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
