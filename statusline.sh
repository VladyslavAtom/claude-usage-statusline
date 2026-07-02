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
# (older 2- and 4-field formats from pre-1.4 caches are still accepted;
#  "E|..." is the spend-based Enterprise format from fetcher v1.5+,
#  with 6 numeric fields in its first revision and 7 in the current one)
[[ "$USAGE_DATA" =~ ^([0-9]+\|-?[0-9]+(\|[0-9]+\|[^|]+(\|-?[0-9]+)?)?|E(\|-?[0-9]+){6,7}\|[^|]+)$ ]] || USAGE_DATA="0|-1"
ENTERPRISE=false
[[ "$USAGE_DATA" == E\|* ]] && ENTERPRISE=true

USAGE_PCT=$(echo "$USAGE_DATA" | cut -d'|' -f1)
MINUTES_REMAINING=$(echo "$USAGE_DATA" | cut -d'|' -f2)
WEEK_PCT=$(echo "$USAGE_DATA" | cut -d'|' -f3)
WEEK_RESET=$(echo "$USAGE_DATA" | cut -d'|' -f4)
WEEK_MINUTES_REMAINING=$(echo "$USAGE_DATA" | cut -d'|' -f5)
WEEK_PCT=${WEEK_PCT:-0}
WEEK_MINUTES_REMAINING=${WEEK_MINUTES_REMAINING:--1}
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

# Color gradient for remaining charge (10 levels: red -> green)
get_charge_color() {
    local pct=$1
    local level=$(( (pct + 9) / 10 ))
    [ $level -lt 1 ] && level=1
    [ $level -gt 10 ] && level=10

    # Bright enough to stay readable as text color on dark backgrounds
    case $level in
        1)  echo $'\033[38;5;196m' ;; # Red (almost empty)
        2)  echo $'\033[38;5;202m' ;; # Red-orange
        3)  echo $'\033[38;5;208m' ;; # Orange
        4)  echo $'\033[38;5;214m' ;; # Amber
        5)  echo $'\033[38;5;184m' ;; # Yellow
        6)  echo $'\033[38;5;148m' ;; # Lime
        7)  echo $'\033[38;5;112m' ;; # Yellow-green
        8)  echo $'\033[38;5;76m' ;;  # Light green
        9)  echo $'\033[38;5;40m' ;;  # Bright green
        10) echo $'\033[38;5;34m' ;;  # Green (full charge)
    esac
}

# Color gradient for free context (10 levels: purple -> teal)
get_ctx_charge_color() {
    local pct=$1
    local level=$(( (pct + 9) / 10 ))
    [ $level -lt 1 ] && level=1
    [ $level -gt 10 ] && level=10

    # Bright enough to stay readable as text color on dark backgrounds
    case $level in
        1)  echo $'\033[38;5;135m' ;; # Bright purple (context almost gone)
        2)  echo $'\033[38;5;99m' ;;  # Purple
        3)  echo $'\033[38;5;63m' ;;  # Blue-violet
        4)  echo $'\033[38;5;69m' ;;  # Medium blue
        5)  echo $'\033[38;5;33m' ;;  # Blue
        6)  echo $'\033[38;5;39m' ;;  # Sky blue
        7)  echo $'\033[38;5;51m' ;;  # Bright cyan
        8)  echo $'\033[38;5;45m' ;;  # Light cyan
        9)  echo $'\033[38;5;44m' ;;  # Cyan
        10) echo $'\033[38;5;37m' ;;  # Teal (context free)
    esac
}

# Pace arrow: used% vs elapsed% of the window.
# Double arrow = strong signal, single = mild.
#   ⇈  ratio < 0.5   way under pace (limit will go unused)
#   ↑  0.5 - 0.8     a bit under pace
#   −  0.8 - 1.2     on pace
#   ↓  1.2 - 1.5     a bit over pace
#   ⇊  ratio > 1.5   slow down
get_pace_arrow() {
    local used_pct=$1 elapsed_pct=$2
    # Unknown window position, or too early in the window for a stable ratio
    if [ "$elapsed_pct" -lt 5 ]; then
        echo $'\033[38;5;245m−'
        return
    fi
    local ratio=$(( used_pct * 100 / elapsed_pct ))
    if [ $ratio -lt 50 ]; then
        echo $'\033[38;5;40m⇈'
    elif [ $ratio -lt 80 ]; then
        echo $'\033[38;5;76m↑'
    elif [ $ratio -le 120 ]; then
        echo $'\033[38;5;245m−'
    elif [ $ratio -le 150 ]; then
        echo $'\033[38;5;208m↓'
    else
        echo $'\033[38;5;196m⇊'
    fi
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

# Enterprise (spend-based) view: no 5h/7d windows — personal extra-usage
# credits as the main battery, org-wide budget dimmed for reference
if $ENTERPRISE; then
    IFS='|' read -r -a EF <<< "$USAGE_DATA"
    SPEND_PCT=${EF[1]}; SPEND_USED=${EF[2]}; SPEND_LIMIT=${EF[3]}
    if [ ${#EF[@]} -ge 9 ]; then
        OV_USED=${EF[4]}; OV_LIMIT=${EF[5]}
        AMBER_USED=${EF[6]}; AMBER_LIMIT=${EF[7]}; AMBER_RESET=${EF[8]}
    else
        # First-revision E format (no overage fields): E|pct|used|limit|org_pct|org_used|org_limit|reset
        OV_USED=-1; OV_LIMIT=0
        AMBER_USED=${EF[5]}; AMBER_LIMIT=${EF[6]}; AMBER_RESET=${EF[7]}
    fi

    SPEND_LEFT=$(( 100 - SPEND_PCT ))
    SPEND_COLOR=$(get_charge_color "$SPEND_LEFT")
    SPEND_GAUGE=$(gauge_char "$SPEND_LEFT")
    # spend amounts come in minor units (cents)
    SPEND_USED_USD=$(( SPEND_USED / 100 ))
    SPEND_LIMIT_USD=$(( SPEND_LIMIT / 100 ))

    fmt_k() { if [ "$1" -ge 1000 ]; then echo "$(( $1 / 1000 ))k"; else echo "$1"; fi; }

    # Org block: live monthly overage spend first, contract credit pool as reference
    ORG_INFO=""
    if [ "$OV_USED" -ge 0 ]; then
        if [ "$OV_LIMIT" -gt 0 ]; then
            ORG_INFO="\$$(( OV_USED / 100 ))/\$$(( OV_LIMIT / 100 ))·mo"
        else
            ORG_INFO="\$$(( OV_USED / 100 ))/mo"
        fi
        ORG_INFO+=" · "
    fi
    ORG_INFO+="\$$(fmt_k "$AMBER_USED")/\$$(fmt_k "$AMBER_LIMIT") ${AMBER_RESET}"

    CTX_FREE=$(( 100 - CONTEXT_PCT ))
    CTX_COLOR=$(get_ctx_charge_color "$CTX_FREE")
    CTX_GAUGE=$(gauge_char "$CTX_FREE")

    printf '%s\n' "${EFFORT_BARS:+${EFFORT_BARS}${RESET} }${MODEL}${FAST_ICON:+ ${FAST_ICON}}${RESET} │ ${DIM}\$${RESET} ${SPEND_COLOR}${SPEND_GAUGE} ${SPEND_LEFT}%${RESET} ${DIM}·\$${SPEND_USED_USD}/\$${SPEND_LIMIT_USD}${RESET} │ ${DIM}org ${ORG_INFO}${RESET} │ ${DIM}C${RESET} ${CTX_COLOR}${CTX_GAUGE} ${CTX_FREE}%${RESET}"
    exit 0
fi

# Battery view: gauges show what's LEFT, draining from full/green to empty/red
API_LEFT=$(( 100 - USAGE_PCT ))
WEEK_LEFT=$(( 100 - WEEK_PCT ))
CTX_FREE=$(( 100 - CONTEXT_PCT ))

# Elapsed share of each rate window (5h = 300 min, 7d = 10080 min); -1 = unknown
API_ELAPSED=-1
[ "$MINUTES_REMAINING" -ge 0 ] && API_ELAPSED=$(( (300 - MINUTES_REMAINING) * 100 / 300 ))
WEEK_ELAPSED=-1
[ "$WEEK_MINUTES_REMAINING" -ge 0 ] && WEEK_ELAPSED=$(( (10080 - WEEK_MINUTES_REMAINING) * 100 / 10080 ))

API_COLOR=$(get_charge_color "$API_LEFT")
API_GAUGE=$(gauge_char "$API_LEFT")
API_PACE=$(get_pace_arrow "$USAGE_PCT" "$API_ELAPSED")

WEEK_COLOR=$(get_charge_color "$WEEK_LEFT")
WEEK_GAUGE=$(gauge_char "$WEEK_LEFT")
WEEK_PACE=$(get_pace_arrow "$WEEK_PCT" "$WEEK_ELAPSED")

CTX_COLOR=$(get_ctx_charge_color "$CTX_FREE")
CTX_GAUGE=$(gauge_char "$CTX_FREE")

# Timer color
TIMER_COLOR=$(get_timer_color "$MINUTES_REMAINING")

# Output: battery format — gauge and % show remaining charge, arrow shows pace vs the window
printf '%s\n' "${EFFORT_BARS:+${EFFORT_BARS}${RESET} }${MODEL}${FAST_ICON:+ ${FAST_ICON}}${RESET} │ ${DIM}5h${RESET} ${API_COLOR}${API_GAUGE} ${API_LEFT}%${RESET} ${API_PACE}${RESET} ${TIMER_COLOR}·${COUNTDOWN}${RESET} │ ${DIM}7d${RESET} ${WEEK_COLOR}${WEEK_GAUGE} ${WEEK_LEFT}%${RESET} ${WEEK_PACE}${RESET} ${DIM}·${WEEK_RESET}${RESET} │ ${DIM}C${RESET} ${CTX_COLOR}${CTX_GAUGE} ${CTX_FREE}%${RESET}"
