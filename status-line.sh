#!/bin/zsh
# Claude Code status line - runs periodically during sessions
# Uses Nerd Font icons (MesloLGS Nerd Font Mono) to match p10k prompt

# --- Colors ---
RED=$'\033[31m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
BLUE=$'\033[34m'
CYAN=$'\033[36m'
DIM=$'\033[2m'
RESET=$'\033[0m'

# --- Rainbow ---
# Strips existing ANSI colors and re-applies a per-character rainbow gradient
rainbow_text() {
  local plain
  plain=$(printf '%s' "$1" | sed $'s/\033\[[0-9;]*m//g')
  local -a colors=(196 208 220 46 51 39 105 165)
  local out="" ci=0 i c
  for (( i=1; i <= ${#plain}; i++ )); do
    c="${plain[$i]}"
    if [[ "$c" == " " ]]; then
      out+=" "
    else
      out+="\033[38;5;${colors[$(( (ci % ${#colors[@]}) + 1 ))]}m${c}"
      (( ci++ ))
    fi
  done
  out+="\033[0m"
  printf '%b' "$out"
}

# --- Nerd Font Icons ---
ICON_REVIEW=$'\uf06e'        # nf-fa-eye
ICON_ACTIVITY=$'\uf0f3'      # nf-fa-bell
ICON_BRANCH=$'\uf126'        # nf-fa-code_fork (matches p10k)
ICON_FOLDER=$'\uf07c'        # nf-fa-folder_open
ICON_WORKTREE=$'\uf0e8'      # nf-fa-sitemap
ICON_DIRTY=$'\uf06a'         # nf-fa-exclamation_circle
ICON_CLEAN=$'\uf00c'         # nf-fa-check
ICON_FIRE=$'\uf0fd'          # nf-fa-fire
ICON_AHEAD=$'\u21e1'         # ⇡ (matches p10k)
ICON_BEHIND=$'\u21e3'        # ⇣ (matches p10k)
ICON_JIRA=$'\uf7b1'          # nf-mdi-jira
SEP=$'\u2502'                # │ thin vertical line

parts=()

# --- PR Monitor ---
status_file="$HOME/.config/pr-monitor/status.json"
if [[ -f "$status_file" ]]; then
  pr_info=$(python3 -c "
import json
try:
    d = json.load(open('$status_file'))
    r = d.get('review_count', 0)
    a = d.get('authored_activity_count', 0)
    age = d.get('oldest_review_age_hours', 0)
    p = []
    if r:
        if age > 24:
            color = '\033[31m'
            icon = '$ICON_FIRE'
        else:
            color = '\033[33m'
            icon = '$ICON_REVIEW'
        p.append(f'{color}{icon} {r}\033[0m')
    if a:
        p.append(f'\033[34m$ICON_ACTIVITY {a}\033[0m')
    print(' '.join(p)) if p else None
except:
    pass
" 2>/dev/null)
  [[ -n "$pr_info" ]] && parts+=("$pr_info")
fi

# --- Git context (only if inside a repo) ---
if git rev-parse --is-inside-work-tree &>/dev/null; then

  # Current directory - repo-relative path
  repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  repo_name=${repo_root:t}
  rel_path=$(git rev-parse --show-prefix 2>/dev/null | sed 's:/$::')
  if [[ -n "$rel_path" ]]; then
    dir_display="${BLUE}${ICON_FOLDER} ${DIM}${repo_name}/${RESET}${rel_path}"
  else
    dir_display="${BLUE}${ICON_FOLDER} ${RESET}${repo_name}"
  fi
  parts+=("$dir_display")

  # Branch name
  branch=$(git branch --show-current 2>/dev/null)

  # Jira context - prefer .jira-context file, fallback to branch name
  ticket=""
  jira_summary=""
  jira_context_file="${repo_root}/.jira-context"
  if [[ -f "$jira_context_file" ]]; then
    jira_info=$(python3 -c "
import json
try:
    d = json.load(open('${jira_context_file}'))
    k = d.get('key', '')
    s = d.get('summary', '')
    if s and len(s) > 40:
        s = s[:37] + '...'
    print(f'{k}\t{s}')
except:
    pass
" 2>/dev/null)
    if [[ -n "$jira_info" ]]; then
      ticket="${jira_info%%$'\t'*}"
      jira_summary="${jira_info##*$'\t'}"
    fi
  fi
  if [[ -z "$ticket" && "$branch" =~ '([A-Z]+-[0-9]+)' ]]; then
    ticket="$match[1]"
  fi

  # Worktree detection
  git_dir=$(git rev-parse --git-dir 2>/dev/null)
  is_worktree=""
  if [[ -f "$git_dir" ]]; then
    is_worktree=1
  fi

  # Build git context string
  git_ctx=""
  if [[ -n "$ticket" && -z "$jira_summary" ]]; then
    # Ticket from branch name only - use as branch display
    git_ctx="${CYAN}${ICON_BRANCH} ${ticket}${RESET}"
  elif [[ -n "$branch" ]]; then
    git_ctx="${CYAN}${ICON_BRANCH} ${branch}${RESET}"
  fi
  [[ -n "$is_worktree" && -n "$git_ctx" ]] && git_ctx="${git_ctx} ${DIM}${ICON_WORKTREE}${RESET}"
  [[ -n "$git_ctx" ]] && parts+=("$git_ctx")

  # Jira context from .jira-context file
  if [[ -n "$ticket" && -n "$jira_summary" ]]; then
    parts+=("${CYAN}${ICON_JIRA} ${ticket}${DIM}: ${jira_summary}${RESET}")
  fi

  # Dirty indicator
  if [[ -n "$(git status --porcelain 2>/dev/null | head -1)" ]]; then
    parts+=("${YELLOW}${ICON_DIRTY}${RESET}")
  else
    parts+=("${GREEN}${ICON_CLEAN}${RESET}")
  fi

  # Ahead/behind remote (using p10k style arrows)
  upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null)
  if [[ -n "$upstream" ]]; then
    counts=$(git rev-list --left-right --count HEAD..."$upstream" 2>/dev/null)
    if [[ -n "$counts" ]]; then
      ahead=${counts%%$'\t'*}
      behind=${counts##*$'\t'}
      ab=""
      (( ahead > 0 )) && ab="${ab}${GREEN}${ICON_AHEAD}${ahead}${RESET}"
      (( behind > 0 )) && ab="${ab}${RED}${ICON_BEHIND}${behind}${RESET}"
      [[ -n "$ab" ]] && parts+=("$ab")
    fi
  fi

else
  # Not in a git repo - just show current dir name
  parts+=("${BLUE}${ICON_FOLDER} ${RESET}${PWD:t}")
fi

# --- Output ---
if (( ${#parts} > 0 )); then
  result=""
  for (( i = 1; i <= ${#parts}; i++ )); do
    (( i > 1 )) && result="${result} ${DIM}${SEP}${RESET} "
    result="${result}${parts[$i]}"
  done
  rainbow_text "$result"
fi
