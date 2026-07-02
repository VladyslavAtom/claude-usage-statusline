#!/bin/bash
# Claude Code Statusline Usage Tracker (Linux-adapted version)
# Original: https://github.com/hamed-elfayome/Claude-Code-Statusline-Usage-Tracker-MacOS

export LC_NUMERIC=C
input=$(cat)

# Parse JSON values (pipe-delimited to handle spaces in model name)
IFS='|' read -r MODEL CONTEXT_PCT <<< $(echo "$input" | jq -r '[.model.display_name, (.context_window.used_percentage // 0 | floor)] | join("|")')
CONTEXT_PCT=${CONTEXT_PCT:-0}

# Get config directory (from env or script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$SCRIPT_DIR}"
SETTINGS_FILE="${CLAUDE_CONFIG_DIR}/settings.json"
# Fall back to default ~/.claude/settings.json if profile dir has no settings
[ -f "$SETTINGS_FILE" ] || SETTINGS_FILE="$HOME/.claude/settings.json"

# Effort level indicator (5 levels: low/medium/high/xhigh/max)
EFFORT_LEVEL=$(jq -r '.effortLevel // "high"' "$SETTINGS_FILE" 2>/dev/null)
E_ON=$'\033[38;5;168m'
E_OFF=$'\033[38;5;239m'
E_ALL="▎▎▎▎▎"
case "$EFFORT_LEVEL" in
    low)    e_filled=1 ;;
    medium) e_filled=2 ;;
    high)   e_filled=3 ;;
    xhigh)  e_filled=4 ;;
    max)    e_filled=5 ;;
    *)      e_filled=3 ;;
esac
EFFORT_BARS="${E_ON}${E_ALL:0:$e_filled}${E_OFF}${E_ALL:$e_filled}"

# Fast mode indicator
FAST_ICON=""
FAST_MODE=$(jq -r '.fastMode // false' "$SETTINGS_FILE" 2>/dev/null)
if [ "$FAST_MODE" = "true" ]; then
    FAST_ICON=$'\033[38;5;208m⚡'
fi

# Fetch real usage from Claude API (cached for 60 seconds)

# Cache file includes config dir hash to avoid conflicts between profiles.
# Stored in a user-owned dir (not /tmp) to avoid predictable-name/symlink issues.
CONFIG_HASH=$(echo -n "$CLAUDE_CONFIG_DIR" | md5sum | cut -c1-8)
CACHE_DIR="${XDG_RUNTIME_DIR:-$HOME/.cache}"
mkdir -p "$CACHE_DIR" 2>/dev/null
CACHE_FILE="${CACHE_DIR}/claude_usage_cache_${CONFIG_HASH}"
CACHE_AGE=300

# Determine which executable to use (binary preferred over Python)
FETCH_CMD=""
if [ -x "${SCRIPT_DIR}/claude-usage" ]; then
    FETCH_CMD="${SCRIPT_DIR}/claude-usage"
elif [ -x "${SCRIPT_DIR}/fetch-usage.py" ]; then
    FETCH_CMD="${SCRIPT_DIR}/fetch-usage.py"
fi

# Check if cache exists and is fresh (Linux-compatible stat command)
if [ -f "$CACHE_FILE" ] && [ $(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0))) -lt $CACHE_AGE ]; then
    USAGE_DATA=$(cat "$CACHE_FILE")
else
    # Try to fetch fresh usage data
    if [ -n "$FETCH_CMD" ]; then
        USAGE_DATA=$(CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" "$FETCH_CMD" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$USAGE_DATA" ]; then
            echo "$USAGE_DATA" > "$CACHE_FILE"
        elif [ -f "$CACHE_FILE" ]; then
            # Fetch failed — use stale cache rather than showing nothing.
            # Touch it so we don't re-run the slow fetch on every render while the API is down.
            USAGE_DATA=$(cat "$CACHE_FILE")
            touch "$CACHE_FILE" 2>/dev/null
        else
            USAGE_DATA="0|-1"
        fi
    else
        # No executable found
        USAGE_DATA="0|-1"
    fi
fi

# Guard against corrupted cache / unexpected fetch output
# (old 2-field format from a pre-1.2 cache is still accepted)
[[ "$USAGE_DATA" =~ ^[0-9]+\|-?[0-9]+(\|[0-9]+\|[^|]+)?$ ]] || USAGE_DATA="0|-1"

USAGE_PCT=$(echo "$USAGE_DATA" | cut -d'|' -f1)
MINUTES_REMAINING=$(echo "$USAGE_DATA" | cut -d'|' -f2)
WEEK_PCT=$(echo "$USAGE_DATA" | cut -d'|' -f3)
WEEK_RESET=$(echo "$USAGE_DATA" | cut -d'|' -f4)
WEEK_PCT=${WEEK_PCT:-0}
[ -n "$WEEK_RESET" ] && [ "$WEEK_RESET" != "-" ] || WEEK_RESET="--"

# Format countdown timer
if [ "$MINUTES_REMAINING" -lt 0 ] 2>/dev/null; then
    COUNTDOWN="--"
elif [ "$MINUTES_REMAINING" -ge 60 ] 2>/dev/null; then
    hours=$((MINUTES_REMAINING / 60))
    mins=$((MINUTES_REMAINING % 60))
    COUNTDOWN="${hours}h${mins}m"
else
    COUNTDOWN="${MINUTES_REMAINING}m"
fi

# Color gradient for API usage (10 levels: green -> red)
get_api_color() {
    local pct=$1
    local level=$(( (pct + 9) / 10 ))
    [ $level -lt 1 ] && level=1
    [ $level -gt 10 ] && level=10

    # Bright enough to stay readable as text color on dark backgrounds
    case $level in
        1)  echo $'\033[38;5;34m' ;;  # Green
        2)  echo $'\033[38;5;40m' ;;  # Bright green
        3)  echo $'\033[38;5;76m' ;;  # Light green
        4)  echo $'\033[38;5;112m' ;; # Yellow-green
        5)  echo $'\033[38;5;148m' ;; # Lime
        6)  echo $'\033[38;5;184m' ;; # Yellow
        7)  echo $'\033[38;5;214m' ;; # Amber
        8)  echo $'\033[38;5;208m' ;; # Orange
        9)  echo $'\033[38;5;202m' ;; # Red-orange
        10) echo $'\033[38;5;196m' ;; # Red
    esac
}

# Color gradient for context usage (cyan/blue tones)
get_ctx_color() {
    local pct=$1
    local level=$(( (pct + 9) / 10 ))
    [ $level -lt 1 ] && level=1
    [ $level -gt 10 ] && level=10

    # Bright enough to stay readable as text color on dark backgrounds
    case $level in
        1)  echo $'\033[38;5;37m' ;;  # Teal
        2)  echo $'\033[38;5;44m' ;;  # Cyan
        3)  echo $'\033[38;5;45m' ;;  # Light cyan
        4)  echo $'\033[38;5;51m' ;;  # Bright cyan
        5)  echo $'\033[38;5;39m' ;;  # Sky blue
        6)  echo $'\033[38;5;33m' ;;  # Blue
        7)  echo $'\033[38;5;69m' ;;  # Medium blue
        8)  echo $'\033[38;5;63m' ;;  # Blue-violet
        9)  echo $'\033[38;5;99m' ;;  # Purple
        10) echo $'\033[38;5;135m' ;; # Bright purple
    esac
}

# Color for countdown timer based on minutes remaining
# Less time = greener (reset coming soon is good!)
get_timer_color() {
    local minutes=$1
    if [ "$minutes" -lt 0 ]; then
        echo $'\033[38;5;240m'  # Gray for unknown
    elif [ "$minutes" -lt 30 ]; then
        echo $'\033[38;5;34m'   # Green (<30m)
    elif [ "$minutes" -lt 60 ]; then
        echo $'\033[38;5;70m'   # Light green (30m-1h)
    elif [ "$minutes" -lt 120 ]; then
        echo $'\033[38;5;142m'  # Olive (1-2h)
    elif [ "$minutes" -lt 180 ]; then
        echo $'\033[38;5;220m'  # Yellow (2-3h)
    elif [ "$minutes" -lt 240 ]; then
        echo $'\033[38;5;208m'  # Orange (3-4h)
    else
        echo $'\033[38;5;196m'  # Red (4h+)
    fi
}

RESET=$'\033[0m'
DIM=$'\033[38;5;245m'

# Single-char mini gauge: height encodes fill level (8 steps)
GAUGE_CHARS="▁▂▃▄▅▆▇█"
gauge_char() {
    local pct=$1
    local idx=$(( pct * 8 / 100 ))
    [ $idx -gt 7 ] && idx=7
    [ $idx -lt 0 ] && idx=0
    echo "${GAUGE_CHARS:$idx:1}"
}

API_COLOR=$(get_api_color "$USAGE_PCT")
API_GAUGE=$(gauge_char "$USAGE_PCT")

WEEK_COLOR=$(get_api_color "$WEEK_PCT")
WEEK_GAUGE=$(gauge_char "$WEEK_PCT")

CTX_COLOR=$(get_ctx_color "$CONTEXT_PCT")
CTX_GAUGE=$(gauge_char "$CONTEXT_PCT")

# Timer color
TIMER_COLOR=$(get_timer_color "$MINUTES_REMAINING")

# Output: mini-gauge format — one block char per metric, counters attached to their sections
printf '%s\n' "${EFFORT_BARS:+${EFFORT_BARS}${RESET} }${MODEL}${FAST_ICON:+ ${FAST_ICON}}${RESET} │ ${DIM}5h${RESET} ${API_COLOR}${API_GAUGE} ${USAGE_PCT}%${RESET} ${TIMER_COLOR}·${COUNTDOWN}${RESET} │ ${DIM}7d${RESET} ${WEEK_COLOR}${WEEK_GAUGE} ${WEEK_PCT}%${RESET} ${DIM}·${WEEK_RESET}${RESET} │ ${DIM}C${RESET} ${CTX_COLOR}${CTX_GAUGE} ${CONTEXT_PCT}%${RESET}"
