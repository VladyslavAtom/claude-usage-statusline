# Claude Code Statusline - Usage Tracker (Linux)

[![Linux](https://img.shields.io/badge/Linux-FCC624?logo=linux&logoColor=black)](https://www.linux.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Real-time Claude API usage tracking for Claude Code's statusline with visual progress bars and color-coded gradients.

## Preview

![Statusline Preview](https://raw.githubusercontent.com/VladyslavAtom/claude-usage-statusline/refs/heads/main/assets/preview.png?v=2)

## Features

- **Real-time Usage Tracking** - 10-block visual progress bar for API usage
- **Context Window Monitor** - Track how much context you've consumed
- **Reset Countdown** - Know exactly when your usage window resets
- **Color Gradients** - Visual feedback from green (low) to red (high)
- **60-second Cache** - Minimizes API calls while staying current
- **Multiple Profiles** - Support for separate work/personal configurations
- **Team/Enterprise Support** - Auto-detects organization with Claude Code access
- **Local Processing** - All data stays on your machine

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/VladyslavAtom/ClaudeUsageStatusLine/main/install.sh | bash
```

The installer will prompt you to choose:

| Method | Dependencies | Description |
|--------|--------------|-------------|
| **Binary** (Recommended) | `jq` only | Standalone executable, no Python needed |
| **Python script** | `jq`, `python3`, `curl_cffi` | Smaller, easier to inspect/modify |

Both methods will:
- Install to `~/.claude/`
- Prompt for your session key
- Configure `~/.claude/settings.json`

## Multiple Profiles (Work/Personal)

You can run separate Claude profiles with different config directories:

```bash
# Install to work profile
CLAUDE_CONFIG_DIR=~/.claude-work ./install.sh

# Create wrapper script for work Claude
cat > ~/bin/claude-work << 'EOF'
#!/bin/bash
export CLAUDE_CONFIG_DIR="$HOME/.claude-work"
exec claude "$@"
EOF
chmod +x ~/bin/claude-work
```

Each profile has its own:
- Session key (`$CLAUDE_CONFIG_DIR/claude-session-key`)
- Settings (`$CLAUDE_CONFIG_DIR/settings.json`)
- Organization selection (`$CLAUDE_CONFIG_DIR/organization`)
- Usage cache (separate per profile)

## Team/Enterprise Accounts

For accounts with multiple organizations (personal + team), the tool automatically selects the organization with Claude Code access (`raven` capability).

To explicitly specify an organization, create an `organization` file:

```bash
# By name
echo "My Company" > ~/.claude-work/organization

# Or by UUID
echo "f8b24ba5-0135-4f37-9c14-06731ce25980" > ~/.claude-work/organization
```

Organization selection priority:
1. Explicit `organization` file (if exists)
2. Auto-select org with `raven` capability (Team/Enterprise with Claude Code)
3. First organization in the list

## Requirements

### Binary Installation (Recommended)
- Linux x86_64
- `jq` - JSON processor
- Claude Pro, Max, or Team subscription

### Python Installation
- Linux (tested on Arch, Ubuntu, Debian)
- `jq` - JSON processor
- `python3` with `curl_cffi` library
- Claude Pro, Max, or Team subscription

## Manual Installation

### 1. Clone the repository

```bash
git clone https://github.com/VladyslavAtom/ClaudeUsageStatusLine.git
cd ClaudeUsageStatusLine
```

### 2. Install dependencies

```bash
# Arch Linux
sudo pacman -S jq

# Ubuntu/Debian
sudo apt install jq

# Fedora
sudo dnf install jq
```

For Python method, also install:
```bash
pip install curl_cffi
```

### 3. Get your Claude session key

1. Open https://claude.ai in your browser
2. Log in to your account
3. Open Developer Tools (F12)
4. Go to **Application** → **Cookies** → `claude.ai`
5. Find and copy the `sessionKey` value

```bash
# Save the session key (replace with your actual key)
echo "sk-ant-sid01-xxxxx..." > ~/.claude/claude-session-key
chmod 600 ~/.claude/claude-session-key
```

> **Note**: Session keys expire periodically. If the statusline shows `--` for the timer, refresh your session key.

### 4. Install scripts

**Option A: Binary (download from releases)**
```bash
mkdir -p ~/.claude
curl -fsSL https://github.com/VladyslavAtom/ClaudeUsageStatusLine/releases/latest/download/claude-usage -o ~/.claude/claude-usage
chmod +x ~/.claude/claude-usage
cp statusline.sh ~/.claude/
chmod +x ~/.claude/statusline.sh
```

**Option B: Python script**
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
                          ┌───────────────────────────┐
                          │  claude-usage (binary)    │
                          │  or fetch-usage.py        │
                          │  (cached 60s)             │
                          └───────────┬───────────────┘
                                      │
                                      ▼
                          ┌───────────────────────────┐
                          │  claude.ai API            │
                          │  /api/usage               │
                          └───────────────────────────┘
```

1. Claude Code sends session JSON to `statusline.sh` via stdin
2. Script extracts model name and context window stats
3. `claude-usage` (or `fetch-usage.py`) fetches API usage from claude.ai (cached for 60 seconds)
4. Renders colored progress bars with ANSI escape codes

## Configuration Files

All configuration is stored in `$CLAUDE_CONFIG_DIR` (default: `~/.claude`):

| File | Description |
|------|-------------|
| `claude-session-key` | Your claude.ai session cookie (required) |
| `settings.json` | Claude Code settings including statusline config |
| `organization` | Explicit org selection by name or UUID (optional) |
| `statusline.sh` | The statusline script |
| `claude-usage` | Binary or `fetch-usage.py` script |

Environment variables:
- `CLAUDE_CONFIG_DIR` - Override config directory (default: `~/.claude`)

## Building from Source

To build the binary yourself:

```bash
# Install uv (if not already installed)
curl -LsSf https://astral.sh/uv/install.sh | sh

# Build
make build

# Binary will be at dist/claude-usage
```

## Troubleshooting

### Statusline shows `0%` or `--`

- **Expired session key**: Get a fresh `sessionKey` from claude.ai cookies
- **Network issues**: Check if you can reach claude.ai
- **File permissions**: Ensure `~/.claude/claude-session-key` is readable

### Script not running

```bash
# Verify scripts are executable
chmod +x ~/.claude/statusline.sh

# Test manually
echo '{"model":{"display_name":"Test"},"context_window":{}}' | ~/.claude/statusline.sh
```

### Cache issues

```bash
# Clear all usage caches
rm /tmp/claude_usage_cache_${USER}_*
```

## Credits

Inspired by [Claude-Code-Statusline-Usage-Tracker-MacOS](https://github.com/hamed-elfayome/Claude-Code-Statusline-Usage-Tracker-MacOS) by [@hamed-elfayome](https://github.com/hamed-elfayome).

## License

MIT License - See [LICENSE](LICENSE) for details.
