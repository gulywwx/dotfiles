#!/bin/sh
# Adapted from https://github.com/danielmackay/claude-code-statusline
# (blog: https://www.dandoescode.com/blog/claude-code-custom-statusline)
#
# Local changes vs upstream:
#   - 7d rate limit enabled (upstream ships it commented out)
#   - " | " separator between the 5h and 7d segments
#   - git commands run with -C "$current_dir" --no-optional-locks so the branch
#     reflects the session's project, not the statusline process's cwd
#   - resets_at accepted as either epoch seconds or an ISO-8601 timestamp
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Unknown Model"')
effort=$(echo "$input" | jq -r '.effort.level // empty')
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
worktree=$(echo "$input" | jq -r '.worktree.name // empty')
total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
current_dir=$(echo "$input" | jq -r '.worktree.original_cwd // empty')
rl_5h_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rl_5h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
rl_7d_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
rl_7d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

[ -n "$rl_5h_pct" ] && rl_5h_pct=$(awk "BEGIN { printf \"%.0f\", $rl_5h_pct }")
[ -n "$rl_7d_pct" ] && rl_7d_pct=$(awk "BEGIN { printf \"%.0f\", $rl_7d_pct }")

if [ -n "$used" ]; then
  used_display=$(printf "%.0f" "$used")
  usage_str="${used_display}%"
else
  usage_str="0%"
fi

if [ -n "$worktree" ]; then
  worktree_str="${worktree}"
else
  worktree_str="no worktree"
fi

GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'

[ -z "$current_dir" ] && current_dir=$(pwd)

git_str=""
if git -C "$current_dir" rev-parse --git-dir > /dev/null 2>&1; then
  branch=$(git -C "$current_dir" --no-optional-locks branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch=$(git -C "$current_dir" --no-optional-locks rev-parse --abbrev-ref HEAD 2>/dev/null)
  staged=$(git -C "$current_dir" --no-optional-locks diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
  modified=$(git -C "$current_dir" --no-optional-locks diff --numstat 2>/dev/null | wc -l | tr -d ' ')

  git_str="$branch"
  [ "$staged" -gt 0 ] && git_str="${git_str} $(printf "${GREEN}+${staged}${RESET}")"
  [ "$modified" -gt 0 ] && git_str="${git_str} $(printf "${YELLOW}~${modified}${RESET}")"
else
  git_str="no branch"
fi

if [ -n "$total_cost" ]; then
  cost_display=$(awk "BEGIN { printf \"%.2f\", $total_cost }")
  block_str="\$${cost_display}"
else
  block_str="\$0.00"
fi

make_bar() {
  pct="$1"
  width=10
  filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled="$width"
  [ "$filled" -lt 0 ] && filled=0
  empty=$(( width - filled ))
  bar=""
  i=0
  while [ $i -lt $filled ]; do bar="${bar}█"; i=$(( i + 1 )); done
  while [ $i -lt $width ];  do bar="${bar}░"; i=$(( i + 1 )); done
  printf "%s" "$bar"
}

fmt_reset() {
  ts="$1"
  [ -z "$ts" ] && return
  case "$ts" in
    *[!0-9]*) base="${ts%%.*}"; base="${base%Z}"
              epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$base" "+%s" 2>/dev/null)
              if [ -n "$epoch" ]; then date -r "$epoch" "+%-I:%M%p" 2>/dev/null
              else date -d "$ts" "+%-I:%M%p" 2>/dev/null; fi ;;
    *)        date -r "$ts" "+%-I:%M%p" 2>/dev/null \
              || date -d "@$ts" "+%-I:%M%p" 2>/dev/null ;;
  esac
}

format_rl() {
  pct="$1"
  reset_ts="$2"
  label="$3"
  [ -z "$pct" ] && return
  if [ "$pct" -ge 90 ]; then color="$RED"
  elif [ "$pct" -ge 70 ]; then color="$YELLOW"
  else color="$GREEN"
  fi
  bar=$(make_bar "$pct")
  reset_time=$(fmt_reset "$reset_ts")
  if [ -n "$reset_time" ]; then
    printf "${color}${label} ${bar} ${pct}%% resets ${reset_time}${RESET}"
  else
    printf "${color}${label} ${bar} ${pct}%%${RESET}"
  fi
}

rl_5h_str=$(format_rl "$rl_5h_pct" "$rl_5h_reset" "5h")
rl_7d_str=$(format_rl "$rl_7d_pct" "$rl_7d_reset" "7d")

rate_limit_str="$rl_5h_str"
if [ -n "$rl_5h_str" ] && [ -n "$rl_7d_str" ]; then
  rate_limit_str="${rl_5h_str} | ${rl_7d_str}"
elif [ -n "$rl_7d_str" ]; then
  rate_limit_str="$rl_7d_str"
fi

repo_root=$(cd "$current_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$current_dir")
dir_display=$(basename "$repo_root")

if [ -n "$effort" ]; then
  printf "🤖 %s | 💪 %s | 🧠 %s | 💰 %s | ⏱️ %s\n📁 %s | 🌳 %s | 🌿 %s" "$model" "$effort" "$usage_str" "$block_str" "$rate_limit_str" "$dir_display" "$worktree_str" "$git_str"
else
  printf "🤖 %s | 🧠 %s | 💰 %s | ⏱️ %s\n📁 %s | 🌳 %s | 🌿 %s" "$model" "$usage_str" "$block_str" "$rate_limit_str" "$dir_display" "$worktree_str" "$git_str"
fi
