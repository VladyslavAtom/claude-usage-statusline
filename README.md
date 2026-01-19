# Claude Code Statusline - Usage Tracker (Linux)

[![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black)](https://www.linux.org/)
[![Python 3.6+](https://img.shields.io/badge/Python-3.6+-3776AB?logo=python&logoColor=white)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Real-time Claude API usage tracking for Claude Code's statusline with visual progress bars and color-coded gradients.

## Preview

![Statusline Preview](assets/preview.png)

## Features

- **Real-time Usage Tracking** - 10-block visual progress bar for API usage
- **Context Window Monitor** - Track how much context you've consumed
- **Reset Countdown** - Know exactly when your usage window resets
- **Color Gradients** - Visual feedback from green (low) to red (high)
- **60-second Cache** - Minimizes API calls while staying current
- **Local Processing** - All data stays on your machine

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/VladyslavAtom/ClaudeUsageStatusLine/main/install.sh | bash
```

This will:
- Download scripts to `~/.claude/`
- Prompt for your session key
- Configure `~/.claude/settings.json`

## Requirements

- Linux (tested on Arch, Ubuntu, Debian)
- `jq` - JSON processor
- `python3` with `requests` library
- Claude Pro or Max subscription

## Manual Installation

### 1. Clone the repository

```bash
git clone https://github.com/VladyslavAtom/ClaudeUsageStatusLine.git
cd ClaudeUsageStatusLine
```

### 2. Install dependencies

```bash
# Arch Linux
sudo pacman -S jq python-requests

# Ubuntu/Debian
sudo apt install jq python3-requests

# Fedora
sudo dnf install jq python3-requests

# Or via pip
pip install requests
```

### 3. Get your Claude session key

1. Open https://claude.ai in your browser
2. Log in to your account
3. Open Developer Tools (F12)
4. Go to **Application** → **Cookies** → `claude.ai`
5. Find and copy the `sessionKey` value

```bash
# Save the session key (replace with your actual key)
echo "sk-ant-sid01-xxxxx..." > ~/.claude-session-key
chmod 600 ~/.claude-session-key
```

> **Note**: Session keys expire periodically. If the statusline shows `--` for the timer, refresh your session key.

### 4. Install scripts

Copy scripts to your Claude config directory:

```bash
cp statusline.sh fetch-usage.py ~/.claude/
chmod +x ~/.claude/statusline.sh ~/.claude/fetch-usage.py
```

### 5. Configure Claude Code

Add to `~/.claude/settings.json`:

```json
{
  "statusline": {
    "script": "~/.claude/statusline.sh"
  }
}
```

## Display Format

| Component | Description |
|-----------|-------------|
| Model | Current Claude model (Opus 4.5, Sonnet 4, etc.) |
| U: | API usage percentage (5-hour rolling window) |
| C: | Context window consumption |
| Timer | Time until usage limit resets |

## Color Coding

### API Usage (U:)

| Usage | Color |
|-------|-------|
| 0-10% | Dark green |
| 11-30% | Green |
| 31-50% | Yellow-green |
| 51-70% | Orange |
| 71-100% | Red |

### Context Window (C:)

Cyan → Blue → Purple gradient as context fills up.

### Reset Timer

| Time Remaining | Color | Meaning |
|----------------|-------|---------|
| Unknown | Gray | Could not fetch reset time |
| < 30 min | Green | Reset coming soon! |
| 30min - 1h | Light green | Almost there |
| 1-2 hours | Olive | Moderate wait |
| 2-3 hours | Yellow | Significant wait |
| 3-4 hours | Orange | Long wait |
| 4+ hours | Red | Just reset, long wait ahead |

## How It Works

```
┌─────────────────┐     stdin      ┌──────────────┐
│  Claude Code    │ ─────────────► │ statusline.sh │
│  (session JSON) │                └──────┬───────┘
└─────────────────┘                       │
                                          │ calls
                                          ▼
                              ┌────────────────────┐
                              │  fetch-usage.py    │
                              │  (cached 60s)      │
                              └──────────┬─────────┘
                                         │
                                         ▼
                              ┌────────────────────┐
                              │  claude.ai API     │
                              │  /api/usage        │
                              └────────────────────┘
```

1. Claude Code sends session JSON to `statusline.sh` via stdin
2. Script extracts model name and context window stats
3. `fetch-usage.py` fetches API usage from claude.ai (cached for 60 seconds)
4. Renders colored progress bars with ANSI escape codes

## Troubleshooting

### Statusline shows `0%` or `--`

- **Expired session key**: Get a fresh `sessionKey` from claude.ai cookies
- **Network issues**: Check if you can reach claude.ai
- **File permissions**: Ensure `~/.claude-session-key` is readable

### Script not running

```bash
# Verify scripts are executable
chmod +x statusline.sh fetch-usage.py

# Test manually
echo '{"model":{"display_name":"Test"},"context_window":{}}' | ./statusline.sh
```

### Cache issues

```bash
# Clear the usage cache
rm /tmp/claude_usage_cache_$USER
```

## Why Python instead of Swift?

The [original macOS version](https://github.com/hamed-elfayome/Claude-Code-Statusline-Usage-Tracker-MacOS) uses Swift with native `URLSession` for browser-like TLS fingerprinting to bypass Cloudflare detection. On Linux, Python's `requests` library works reliably with the claude.ai API when using proper headers and session cookies.

## Credits

Inspired by [Claude-Code-Statusline-Usage-Tracker-MacOS](https://github.com/hamed-elfayome/Claude-Code-Statusline-Usage-Tracker-MacOS) by [@hamed-elfayome](https://github.com/hamed-elfayome).

## License

MIT License - See [LICENSE](LICENSE) for details.
