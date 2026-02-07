#!/bin/bash
# Claude Code Statusline Usage Tracker (Linux-adapted version)
# Original: https://github.com/hamed-elfayome/Claude-Code-Statusline-Usage-Tracker-MacOS

export LC_NUMERIC=C
input=$(cat)

# Parse JSON values (pipe-delimited to handle spaces in model name)
IFS='|' read -r MODEL CONTEXT_PCT <<< $(echo "$input" | jq -r '[.model.display_name, (.context_window.used_percentage // 0 | floor)] | join("|")')
CONTEXT_PCT=${CONTEXT_PCT:-0}

# Effort level and fast mode only apply to 4.6+ models
EFFORT_BARS=""
FAST_ICON=""
if echo "$MODEL" | grep -qE '4\.6|4\.[7-9]|[5-9]\.[0-9]'; then
    # Read effort level from Claude settings
    EFFORT_LEVEL=$(jq -r '.effortLevel // "medium"' ~/.claude/settings.json 2>/dev/null)
    E_ON=$'\033[38;5;168m'
    E_OFF=$'\033[38;5;239m'
    B="▎"
    case "$EFFORT_LEVEL" in
        low)    EFFORT_BARS="${E_ON}${B}${E_OFF}${B}${B}" ;;
        high)   EFFORT_BARS="${E_ON}${B}${B}${B}" ;;
        *)      EFFORT_BARS="${E_ON}${B}${B}${E_OFF}${B}" ;;
    esac

    # Fast mode indicator
    FAST_MODE=$(jq -r '.fastMode // false' ~/.claude/settings.json 2>/dev/null)
    if [ "$FAST_MODE" = "true" ]; then
        FAST_ICON=$'\033[38;5;208m⚡'
    fi
fi

# Fetch real usage from Claude API (cached for 60 seconds)
# Get config directory (from env or script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$SCRIPT_DIR}"

# Cache file includes config dir hash to avoid conflicts between profiles
CONFIG_HASH=$(echo -n "$CLAUDE_CONFIG_DIR" | md5sum | cut -c1-8)
CACHE_FILE="/tmp/claude_usage_cache_${USER}_${CONFIG_HASH}"
CACHE_AGE=60

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
        else
            USAGE_DATA="0|-1"
        fi
    else
        # No executable found
        USAGE_DATA="0|-1"
    fi
fi

USAGE_PCT=$(echo "$USAGE_DATA" | cut -d'|' -f1)
MINUTES_REMAINING=$(echo "$USAGE_DATA" | cut -d'|' -f2)

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

    case $level in
        1)  echo $'\033[38;5;22m' ;;  # Dark green
        2)  echo $'\033[38;5;28m' ;;  # Green
        3)  echo $'\033[38;5;34m' ;;  # Light green
        4)  echo $'\033[38;5;64m' ;;  # Olive
        5)  echo $'\033[38;5;100m' ;; # Yellow-green
        6)  echo $'\033[38;5;136m' ;; # Dark yellow
        7)  echo $'\033[38;5;172m' ;; # Orange
        8)  echo $'\033[38;5;208m' ;; # Light orange
        9)  echo $'\033[38;5;196m' ;; # Red
        10) echo $'\033[38;5;124m' ;; # Dark red
    esac
}

# Color gradient for context usage (cyan/blue tones)
get_ctx_color() {
    local pct=$1
    local level=$(( (pct + 9) / 10 ))
    [ $level -lt 1 ] && level=1
    [ $level -gt 10 ] && level=10

    case $level in
        1)  echo $'\033[38;5;23m' ;;  # Dark cyan
        2)  echo $'\033[38;5;30m' ;;  # Teal
        3)  echo $'\033[38;5;37m' ;;  # Cyan
        4)  echo $'\033[38;5;44m' ;;  # Light cyan
        5)  echo $'\033[38;5;45m' ;;  # Sky blue
        6)  echo $'\033[38;5;39m' ;;  # Blue
        7)  echo $'\033[38;5;33m' ;;  # Medium blue
        8)  echo $'\033[38;5;27m' ;;  # Dark blue
        9)  echo $'\033[38;5;57m' ;;  # Purple-blue
        10) echo $'\033[38;5;93m' ;; # Purple
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

# Build progress bars (10 characters, no loops)
FULL="██████████"
EMPTY="░░░░░░░░░░"
bar_width=10

api_filled=$(( (USAGE_PCT * bar_width + 50) / 100 ))
[ $api_filled -gt $bar_width ] && api_filled=$bar_width
API_BAR_COLOR=$(get_api_color "$USAGE_PCT")
API_BAR="${API_BAR_COLOR}${FULL:0:$api_filled}${EMPTY:0:$((bar_width - api_filled))}${RESET}"

ctx_filled=$(( (CONTEXT_PCT * bar_width + 50) / 100 ))
[ $ctx_filled -gt $bar_width ] && ctx_filled=$bar_width
CTX_BAR_COLOR=$(get_ctx_color "$CONTEXT_PCT")
CTX_BAR="${CTX_BAR_COLOR}${FULL:0:$ctx_filled}${EMPTY:0:$((bar_width - ctx_filled))}${RESET}"

# Timer color
TIMER_COLOR=$(get_timer_color "$MINUTES_REMAINING")

# Fixed-width formatting
USAGE_FMT=$(printf "%3d" "$USAGE_PCT")
CTX_FMT=$(printf "%3d" "$CONTEXT_PCT")

# Output: compact format with thin separators
printf '%s\n' "${EFFORT_BARS:+${EFFORT_BARS}${RESET} }${MODEL}${FAST_ICON:+ ${FAST_ICON}}${RESET} │ ${API_BAR_COLOR}U:${API_BAR} ${USAGE_FMT}%${RESET} │ ${CTX_BAR_COLOR}C:${CTX_BAR} ${CTX_FMT}%${RESET} │ ${TIMER_COLOR}${COUNTDOWN}${RESET}"
