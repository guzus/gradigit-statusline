#!/bin/bash

# Ultimate Claude Code Statusline — Catppuccin Mocha palette, true color
# Designed for Ghostty with 24-bit color support
input=$(cat)

# ── Extract all variables (single jq call) ──
eval "$(echo "$input" | jq -r '
  @sh "model=\(.model.display_name // "—")",
  @sh "model_id=\(.model.id // "—")",
  @sh "style=\(.output_style.name // "—")",
  @sh "dir=\(.workspace.current_dir // "—")",
  @sh "used=\(.context_window.used_percentage // "")",
  @sh "ctx_size=\(.context_window.context_window_size // 200000)",
  @sh "tot_in=\(.context_window.total_input_tokens // 0)",
  @sh "tot_out=\(.context_window.total_output_tokens // 0)",
  @sh "sid=\(.session_id // "—")",
  @sh "ver=\(.version // "—")",
  @sh "cost=\(.cost.total_cost_usd // 0)",
  @sh "duration_ms=\(.cost.total_duration_ms // 0)",
  @sh "lines_add=\(.cost.total_lines_added // 0)",
  @sh "lines_rm=\(.cost.total_lines_removed // 0)",
  @sh "vim_mode=\(.vim.mode // "")",
  @sh "agent_name=\(.agent.name // "")",
  @sh "c_in=\(.context_window.current_usage.input_tokens // 0)",
  @sh "c_out=\(.context_window.current_usage.output_tokens // 0)",
  @sh "c_create=\(.context_window.current_usage.cache_creation_input_tokens // 0)",
  @sh "c_read=\(.context_window.current_usage.cache_read_input_tokens // 0)",
  @sh "thinking_enabled=\(.model.thinking_enabled // "")",
  @sh "reasoning_effort=\(.model.reasoning_effort // "")"
' 2>/dev/null)"

# Fallbacks
[ -z "$model" ] && model="—"
[ -z "$dir" ] && dir="$PWD"
[ -z "$cost" ] && cost=0
[ -z "$duration_ms" ] && duration_ms=0

now=$(date '+%H:%M:%S')

# ── Thinking level ──
thinking=""
if [ -n "$reasoning_effort" ]; then
  thinking="$reasoning_effort"
elif [ "$thinking_enabled" = "true" ]; then
  thinking="on"
else
  case "$model_id" in
    *think*|*extended*) thinking="extended" ;;
  esac
fi

# ── Session timestamps ──
now_epoch=$(date +%s)
if [ "$duration_ms" -gt 0 ]; then
  duration_s=$((duration_ms / 1000))
  start_epoch=$((now_epoch - duration_s))
  session_started=$(date -r "$start_epoch" '+%H:%M:%S')
  hrs=$((duration_s / 3600))
  mins=$(( (duration_s % 3600) / 60 ))
  secs=$((duration_s % 60))
  if [ "$hrs" -gt 0 ]; then
    duration_human="${hrs}h ${mins}m"
  elif [ "$mins" -gt 0 ]; then
    duration_human="${mins}m ${secs}s"
  else
    duration_human="${secs}s"
  fi
else
  session_started="—"
  duration_human="0s"
fi

# ── Rate limit / usage quota (cached 60s) ──
CACHE_FILE="/tmp/.claude-usage-cache"
CACHE_TTL=60
five_hr_used=""
five_hr_reset=""
seven_day_used=""
seven_day_reset=""

fetch_usage() {
  local token
  token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
  [ -z "$token" ] && return 1
  local resp
  resp=$(curl -s --max-time 3 \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
  [ -z "$resp" ] && return 1
  echo "$resp" | jq -e '.five_hour' >/dev/null 2>&1 || return 1
  echo "$now_epoch $resp" > "$CACHE_FILE"
  echo "$resp"
}

get_usage() {
  if [ -f "$CACHE_FILE" ]; then
    local cached_epoch
    cached_epoch=$(cut -d' ' -f1 "$CACHE_FILE")
    if [ $((now_epoch - cached_epoch)) -lt $CACHE_TTL ]; then
      cut -d' ' -f2- "$CACHE_FILE"
      return 0
    fi
    # Stale cache — background refresh, serve stale
    ( fetch_usage >/dev/null 2>&1 & )
    cut -d' ' -f2- "$CACHE_FILE"
    return 0
  fi
  fetch_usage
}

usage_json=$(get_usage 2>/dev/null)
if [ -n "$usage_json" ]; then
  eval "$(echo "$usage_json" | jq -r '
    @sh "five_hr_used=\(if .five_hour.utilization then (.five_hour.utilization | floor) else "" end)",
    @sh "five_hr_reset=\(.five_hour.resets_at // "")",
    @sh "seven_day_used=\(if .seven_day.utilization then (.seven_day.utilization | floor) else "" end)",
    @sh "seven_day_reset=\(.seven_day.resets_at // "")"
  ' 2>/dev/null)"
fi

# ── Format helpers ──
fmt_reset() {
  local reset_iso="$1"
  [ -z "$reset_iso" ] && return
  local cleaned
  cleaned=$(echo "$reset_iso" | sed 's/\.[0-9]*//; s/:\([0-9][0-9]\)$/\1/')
  local reset_epoch
  reset_epoch=$(date -jf "%Y-%m-%dT%H:%M:%S%z" "$cleaned" "+%s" 2>/dev/null)
  [ -z "$reset_epoch" ] && return
  local diff=$(( reset_epoch - now_epoch ))
  [ "$diff" -le 0 ] && { printf "now"; return; }
  local h=$(( diff / 3600 ))
  local m=$(( (diff % 3600) / 60 ))
  if [ "$h" -gt 0 ]; then
    printf "%dh%dm" "$h" "$m"
  else
    printf "%dm" "$m"
  fi
}

fmt_reset_minutes() {
  local reset_iso="$1"
  [ -z "$reset_iso" ] && return
  local cleaned
  cleaned=$(echo "$reset_iso" | sed 's/\.[0-9]*//; s/:\([0-9][0-9]\)$/\1/')
  local reset_epoch
  reset_epoch=$(date -jf "%Y-%m-%dT%H:%M:%S%z" "$cleaned" "+%s" 2>/dev/null)
  [ -z "$reset_epoch" ] && return
  local diff=$(( reset_epoch - now_epoch ))
  [ "$diff" -le 0 ] && { printf "0m"; return; }
  local mins=$(( diff / 60 ))
  printf "%dm" "$mins"
}

fmt_reset_days() {
  local reset_iso="$1"
  [ -z "$reset_iso" ] && return
  local cleaned
  cleaned=$(echo "$reset_iso" | sed 's/\.[0-9]*//; s/:\([0-9][0-9]\)$/\1/')
  local reset_epoch
  reset_epoch=$(date -jf "%Y-%m-%dT%H:%M:%S%z" "$cleaned" "+%s" 2>/dev/null)
  [ -z "$reset_epoch" ] && return
  local diff=$(( reset_epoch - now_epoch ))
  [ "$diff" -le 0 ] && { printf "0d"; return; }
  local days=$(( diff / 86400 ))
  local hours=$(( (diff % 86400) / 3600 ))
  if [ "$days" -gt 0 ]; then
    printf "%dd%dh" "$days" "$hours"
  else
    printf "%dh" "$hours"
  fi
}

fmt_tokens() {
  local n=${1:-0}
  [ -z "$n" ] && n=0
  if [ "$n" -ge 1000000 ]; then
    printf "%.1fM" "$(echo "scale=1; $n / 1000000" | bc)"
  elif [ "$n" -ge 1000 ]; then
    printf "%.1fK" "$(echo "scale=1; $n / 1000" | bc)"
  else
    printf "%d" "$n"
  fi
}

# Pre-format values
f_tot_in=$(fmt_tokens "$tot_in")
f_tot_out=$(fmt_tokens "$tot_out")
f_c_in=$(fmt_tokens "$c_in")
f_c_out=$(fmt_tokens "$c_out")
f_c_create=$(fmt_tokens "$c_create")
f_c_read=$(fmt_tokens "$c_read")
f_cost=$(printf "\$%.2f" "$cost")

# Context window: derive actual current window tokens from percentage
if [ -n "$used" ] && [ "$used" -gt 0 ]; then
  ctx_tokens=$(( ctx_size * used / 100 ))
else
  ctx_tokens=0
fi
f_ctx_tokens=$(fmt_tokens "$ctx_tokens")
f_ctx_size=$(fmt_tokens "$ctx_size")

# ═══════════════════════════════════════════════════
# TRUE COLOR PALETTE — Catppuccin Mocha inspired
# ═══════════════════════════════════════════════════
RST='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
ITALIC='\033[3m'

# Structural / neutral layers
c_label='\033[38;2;108;112;134m'     # #6c7086 — Overlay0, muted labels
c_sep='\033[38;2;88;91;112m'         # #585b70 — Surface2, separators
c_text='\033[38;2;205;214;244m'      # #cdd6f4 — Text, primary values
c_subtext='\033[38;2;186;194;222m'   # #bac2de — Subtext1, secondary values
c_dim='\033[38;2;69;71;90m'          # #45475a — Surface1, very dim

# Accent colors
c_blue='\033[38;2;137;180;250m'      # #89b4fa — Blue, primary accent
c_sapphire='\033[38;2;116;199;236m'  # #74c7ec — Sapphire, clickable paths
c_teal='\033[38;2;148;226;213m'      # #94e2d5 — Teal, informational
c_lavender='\033[38;2;180;190;254m'  # #b4befe — Lavender, model identity
c_mauve='\033[38;2;203;166;247m'     # #cba6f7 — Mauve, thinking indicator
c_gold='\033[38;2;249;226;175m'      # #f9e2af — Yellow, cost/money

# Semantic status colors
c_green='\033[38;2;166;227;161m'     # #a6e3a1 — Green, healthy/added
c_peach='\033[38;2;250;179;135m'     # #fab387 — Peach, warning
c_red='\033[38;2;243;139;168m'       # #f38ba8 — Red, critical/removed

# ── Status color based on percentage used ──
status_color() {
  local pct=$1
  if [ "$pct" -lt 50 ]; then
    printf '%s' "$c_green"
  elif [ "$pct" -lt 75 ]; then
    printf '%s' "$c_peach"
  else
    printf '%s' "$c_red"
  fi
}

CTX_COLOR=$c_green
[ -n "$used" ] && CTX_COLOR=$(status_color "$used")

# ── OSC 8 clickable link for Ghostty ──
osc_link() {
  printf '\033]8;;file://%s\033\\%s\033]8;;\033\\' "$1" "$2"
}

# ── Git branch ──
git_branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null)

# Separator character
S="${c_sep} │ ${RST}"

# Suppress all stderr from output section so bash errors never leak into display
exec 2>/dev/null

# ═══════════════════════════════════════════════════
# LINE 1 — Directory + Git Branch + Duration + Vim + Agent
# ═══════════════════════════════════════════════════
printf "${c_sapphire}"
osc_link "$dir" "$dir"
[ -n "$git_branch" ] && printf "${RST}${S}${c_green}%s${RST}" "$git_branch"
printf "${RST}${S}${c_subtext}%s${RST}" "$duration_human"
[ -n "$vim_mode" ] && printf "${S}${c_mauve}VIM ${BOLD}%s${RST}" "$vim_mode"
[ -n "$agent_name" ] && printf "${S}${c_lavender}%s${RST}" "$agent_name"
printf '\n'

# ═══════════════════════════════════════════════════
# LINE 2 — Model + Thinking + Version + Cost + Quota
# ═══════════════════════════════════════════════════
printf "${c_lavender}${BOLD}%s${RST}" "$model"
[ -n "$thinking" ] && printf " ${c_mauve}${ITALIC}%s${RST}" "$thinking"
printf "${S}${c_label}v%s${RST}" "$ver"
printf "${S}${c_gold}${BOLD}%s${RST}" "$f_cost"
printf "${S}"
if [ -n "$five_hr_used" ] && [ -n "$seven_day_used" ]; then
  # Sanitize to integers (strip decimals, default to 0)
  five_hr_used=${five_hr_used%%.*}
  seven_day_used=${seven_day_used%%.*}
  [ -z "$five_hr_used" ] && five_hr_used=0
  [ -z "$seven_day_used" ] && seven_day_used=0
  five_left=$((100 - five_hr_used))
  seven_left=$((100 - seven_day_used))
  FIVE_C=$(status_color "$five_hr_used")
  SEVEN_C=$(status_color "$seven_day_used")
  f_five_r=$(fmt_reset "$five_hr_reset")
  f_seven_r=$(fmt_reset_days "$seven_day_reset")
  printf "${FIVE_C}${BOLD}%s%%${RST}${c_label} left${RST}" "$five_left"
  [ -n "$f_five_r" ] && printf " ${c_dim}%s${RST}" "$f_five_r"
  printf "${S}"
  printf "${SEVEN_C}${BOLD}%s%%${RST}${c_label} left${RST}" "$seven_left"
  [ -n "$f_seven_r" ] && printf " ${c_dim}%s${RST}" "$f_seven_r"
else
  printf "${c_label}Quota  —${RST}"
fi
printf '\n'

# ═══════════════════════════════════════════════════
# LINE 3 — Context
# ═══════════════════════════════════════════════════
if [ -n "$used" ]; then
  ctx_warn=""
  if [ "$used" -ge 80 ]; then
    ctx_warn=" 🚨"
  elif [ "$used" -ge 60 ]; then
    ctx_warn=" ⚠️"
  fi
  printf "${c_label}ctx ${CTX_COLOR}${BOLD}%s%%%s${RST} ${c_dim}%s/%s${RST}" "$used" "$ctx_warn" "$f_ctx_tokens" "$f_ctx_size"
else
  printf "${c_dim}ctx  —${RST}"
fi
printf '\n'
