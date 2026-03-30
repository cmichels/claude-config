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

# --- Rainbow palette (ROYGBIV) + animation offset ---
RAINBOW=(196 208 220 46 51 39 105 165)
rainbow_offset=$(( $(date +%s) % ${#RAINBOW} ))

# Pre-compute rainbow separator colors (avoids subshells in loops)
typeset -a SEP_COLORS
for (( _i=1; _i<=${#RAINBOW}; _i++ )); do
  SEP_COLORS[$_i]=$(printf '\033[38;5;%dm' "${RAINBOW[$_i]}")
done

# --- Rainbow text ---
# Strips existing ANSI colors and re-applies an animated per-character rainbow gradient
rainbow_text() {
  local plain
  plain=$(printf '%s' "$1" | sed $'s/\033\[[0-9;]*m//g')
  local rlen=${#RAINBOW}
  local out="" ci=0 i c
  for (( i=1; i <= ${#plain}; i++ )); do
    c="${plain[$i]}"
    if [[ "$c" == " " ]]; then
      out+=" "
    else
      out+="\033[38;5;${RAINBOW[$(( ((ci + rainbow_offset) % rlen) + 1 ))]}m${c}"
      (( ci++ ))
    fi
  done
  out+="\033[0m"
  printf '%b' "$out"
}

# --- Stdin JSON (piped by Claude Code) ---
stdin_json=""
if [[ ! -t 0 ]]; then
  stdin_json=$(command cat)
fi

model_name=""
ctx_percent=-1
five_hour_pct=-1
transcript_path=""
ctx_size=0
input_tokens=0
cache_tokens=0

if [[ -n "$stdin_json" ]]; then
  IFS=$'\t' read -r model_name ctx_percent five_hour_pct <<< "$(
    printf '%s' "$stdin_json" | jq -r '[
      (.model.display_name // .model.id // ""),
      (.context_window.used_percentage // -1 | floor),
      (.rate_limits.five_hour.used_percentage // -1 | floor)
    ] | @tsv' 2>/dev/null
  )"

  IFS=$'\t' read -r transcript_path ctx_size input_tokens cache_tokens <<< "$(
    printf '%s' "$stdin_json" | jq -r '[
      (.transcript_path // ""),
      (.context_window.context_window_size // 0),
      (.context_window.current_usage.input_tokens // 0),
      ((.context_window.current_usage.cache_creation_input_tokens // 0) + (.context_window.current_usage.cache_read_input_tokens // 0))
    ] | @tsv' 2>/dev/null
  )"
fi

# Shorten model name: "Claude Opus 4.6" → "Opus 4.6"
model_name="${model_name#Claude }"

# --- Helpers ---
format_tokens() {
  local n=$1
  if (( n >= 1000000 )); then
    printf '%s' "$(( n / 1000000 )).$(( (n % 1000000) / 100000 ))M"
  elif (( n >= 1000 )); then
    printf '%s' "$(( n / 1000 ))k"
  else
    printf '%s' "$n"
  fi
}

gradient_bar() {
  local pct=$1 width=$2
  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))
  local rlen=${#RAINBOW}
  local out="" ci
  # Filled hearts: vivid scrolling rainbow
  for (( i=0; i<filled; i++ )); do
    ci=$(( (i + rainbow_offset) % rlen + 1 ))
    out+="\033[38;5;${RAINBOW[$ci]}m♥"
  done
  # Empty hearts: ghost scrolling rainbow (dim)
  for (( i=0; i<empty; i++ )); do
    ci=$(( (filled + i + rainbow_offset) % rlen + 1 ))
    out+="\033[2;38;5;${RAINBOW[$ci]}m♡"
  done
  out+="\033[0m"
  printf '%b' "$out"
}

# --- Session Duration ---
session_dur=""
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
  birth=$(stat -c '%W' "$transcript_path" 2>/dev/null)
  [[ "$birth" == "0" || -z "$birth" ]] && birth=$(stat -c '%Z' "$transcript_path" 2>/dev/null)
  if [[ -n "$birth" && "$birth" != "0" ]]; then
    now_epoch=$(date +%s)
    elapsed=$(( now_epoch - birth ))
    mins=$(( elapsed / 60 ))
    if (( mins < 1 )); then session_dur="<1m"
    elif (( mins < 60 )); then session_dur="${mins}m"
    else
      hours=$(( mins / 60 ))
      rem=$(( mins % 60 ))
      session_dur="${hours}h ${rem}m"
    fi
  fi
fi

# --- Health Emoji (context-based) ---
health=""
if (( ctx_percent >= 95 )); then   health=$'\U0001F480'     # skull
elif (( ctx_percent >= 85 )); then health=$'\u2764'          # red heart
elif (( ctx_percent >= 75 )); then health=$'\U0001F9E1'     # orange heart
elif (( ctx_percent >= 50 )); then health=$'\U0001F49B'     # yellow heart
elif (( ctx_percent >= 0 )); then  health=$'\U0001F49A'     # green heart
fi

# --- Nerd Font Icons ---
ICON_REVIEW=$'\uf06e'        # nf-fa-eye
ICON_ACTIVITY=$'\uf0f3'      # nf-fa-bell
ICON_BRANCH=$'\uf126'        # nf-fa-code_fork (matches p10k)
ICON_FOLDER=$'\uf07c'        # nf-fa-folder_open
ICON_WORKTREE=$'\uf0e8'      # nf-fa-sitemap
ICON_DIRTY=$'\uf06a'         # nf-fa-exclamation_circle
ICON_CLEAN=$'\uf00c'         # nf-fa-check
ICON_FIRE=$'\uf0fd'          # nf-fa-fire
ICON_AHEAD=$'\u21e1'         # upwards arrow (matches p10k)
ICON_BEHIND=$'\u21e3'        # downwards arrow (matches p10k)
ICON_JIRA=$'\uf7b1'          # nf-mdi-jira
ICON_CLOCK=$'\uf017'         # nf-fa-clock_o
SEP=$'\u2502'                # thin vertical line

rainbow_parts=()
solid_parts=()

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
  [[ -n "$pr_info" ]] && rainbow_parts+=("$pr_info")
fi

# --- Model & Context Window (from stdin) ---
if [[ -n "$model_name" ]]; then
  term_width=$(tput cols 2>/dev/null || echo 120)
  bar_width=$(( term_width / 8 ))
  (( bar_width < 5 )) && bar_width=5
  (( bar_width > 20 )) && bar_width=20

  if (( ctx_percent >= 0 )); then
    # Context color for percentage text
    if (( ctx_percent >= 85 )); then ctx_color=$RED
    elif (( ctx_percent >= 70 )); then ctx_color=$YELLOW
    else ctx_color=$GREEN
    fi

    # Autocompact warning + token breakdown at high usage
    if (( ctx_percent >= 85 )); then
      total_tokens=$(( input_tokens + cache_tokens ))
      if (( ctx_size > 0 && total_tokens > 0 )); then
        ctx_display="\u26a0 ${ctx_percent}% ($(format_tokens $total_tokens)/$(format_tokens $ctx_size))"
      else
        ctx_display="\u26a0 ${ctx_percent}%"
      fi
    elif (( ctx_percent >= 80 )); then
      ctx_display="\u26a0 ${ctx_percent}%"
    else
      ctx_display="${ctx_percent}%"
    fi

    solid_parts+=("${health} ${CYAN}[${model_name}]${RESET} $(gradient_bar $ctx_percent $bar_width) ${ctx_color}${ctx_display}${RESET}")
  else
    solid_parts+=("${CYAN}[${model_name}]${RESET}")
  fi
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
  rainbow_parts+=("$dir_display")

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
    git_ctx="${CYAN}${ICON_BRANCH} ${ticket}${RESET}"
  elif [[ -n "$branch" ]]; then
    git_ctx="${CYAN}${ICON_BRANCH} ${branch}${RESET}"
  fi
  [[ -n "$is_worktree" && -n "$git_ctx" ]] && git_ctx="${git_ctx} ${DIM}${ICON_WORKTREE}${RESET}"
  [[ -n "$git_ctx" ]] && solid_parts+=("$git_ctx")

  # Jira context from .jira-context file
  if [[ -n "$ticket" && -n "$jira_summary" ]]; then
    solid_parts+=("${CYAN}${ICON_JIRA} ${ticket}${DIM}: ${jira_summary}${RESET}")
  fi

  # Dirty indicator
  if [[ -n "$(git status --porcelain 2>/dev/null | head -1)" ]]; then
    solid_parts+=("${YELLOW}${ICON_DIRTY}${RESET}")
  else
    solid_parts+=("${GREEN}${ICON_CLEAN}${RESET}")
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
      [[ -n "$ab" ]] && solid_parts+=("$ab")
    fi
  fi

else
  # Not in a git repo - just show current dir name
  rainbow_parts+=("${BLUE}${ICON_FOLDER} ${RESET}${PWD:t}")
fi

# --- Rate Limit (5h, shown when > 50%) ---
if (( five_hour_pct >= 0 )); then
  if (( five_hour_pct >= 90 )); then rl_color=$RED
  elif (( five_hour_pct >= 75 )); then rl_color=$YELLOW
  else rl_color=$CYAN
  fi
  rl_bar_width=$(( bar_width > 0 ? bar_width / 2 : 5 ))
  (( rl_bar_width < 3 )) && rl_bar_width=3
  solid_parts+=("${rl_color}5h${RESET} $(gradient_bar $five_hour_pct $rl_bar_width) ${rl_color}${five_hour_pct}%${RESET}")
fi

# --- Session Duration ---
if [[ -n "$session_dur" ]]; then
  solid_parts+=("${CYAN}${ICON_CLOCK} ${session_dur}${RESET}")
fi

# --- Output ---
# Rainbow gradient for PR monitor + directory, rainbow separators, solid semantic colors
output=""

if (( ${#rainbow_parts} > 0 )); then
  rbow=""
  for (( i = 1; i <= ${#rainbow_parts}; i++ )); do
    (( i > 1 )) && rbow="${rbow} ${DIM}${SEP}${RESET} "
    rbow="${rbow}${rainbow_parts[$i]}"
  done
  output+="$(rainbow_text "$rbow")"
fi

if (( ${#solid_parts} > 0 )); then
  solid=""
  sep_ci=0
  for (( i = 1; i <= ${#solid_parts}; i++ )); do
    ci=$(( (sep_ci + rainbow_offset) % ${#RAINBOW} + 1 ))
    solid="${solid} ${SEP_COLORS[$ci]}${SEP}${RESET} "
    (( sep_ci++ ))
    solid="${solid}${solid_parts[$i]}"
  done
  output+="$solid"
fi

[[ -n "$output" ]] && printf '%b' "$output"
