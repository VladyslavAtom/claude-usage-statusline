#!/bin/bash
# Claude Usage Statusline Installer

set -e

CLAUDE_DIR="$HOME/.claude"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_URL_BASE="https://raw.githubusercontent.com/VladyslavAtom/ClaudeUsageStatusLine/main"
RELEASE_URL="https://github.com/VladyslavAtom/ClaudeUsageStatusLine/releases/latest/download"

# Check if running from cloned repo
LOCAL_MODE=false
if [ -f "$SCRIPT_DIR/statusline.sh" ] && [ -f "$SCRIPT_DIR/fetch-usage.py" ]; then
    LOCAL_MODE=true
fi

# Installation method: binary or python
INSTALL_METHOD=""

echo "=== Claude Usage Statusline Installer ==="
if $LOCAL_MODE; then
    echo "    (local mode - using cloned files)"
fi
echo

# Ask for installation method
choose_install_method() {
    echo "Choose installation method:"
    echo
    echo "  [1] Binary (Recommended)"
    echo "      - Standalone executable, no dependencies needed"
    echo "      - Downloads pre-built binary from GitHub releases"
    echo
    echo "  [2] Python script"
    echo "      - Requires Python 3 and curl_cffi package"
    echo "      - Smaller download, easier to inspect/modify"
    echo
    read -p "Enter choice [1/2] (default: 1): " choice
    case "$choice" in
        2) INSTALL_METHOD="python" ;;
        *) INSTALL_METHOD="binary" ;;
    esac
    echo
    echo "Selected: $INSTALL_METHOD"
}

# Check dependencies for Python method
check_python_deps() {
    local missing_pip=false

    if ! command -v python3 &>/dev/null; then
        echo "ERROR: Python 3 is required for Python installation method"
        echo "Please install Python 3 or choose binary installation"
        exit 1
    fi

    if ! python3 -c "from curl_cffi import requests" &>/dev/null 2>&1; then
        missing_pip=true
    fi

    if $missing_pip; then
        echo "Missing Python dependency: curl_cffi"
        echo
        echo "Install with:"
        if $LOCAL_MODE && [ -f "$SCRIPT_DIR/requirements.txt" ]; then
            echo "  pip install -r $SCRIPT_DIR/requirements.txt"
        else
            echo "  pip install curl_cffi"
        fi
        echo
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "All Python dependencies installed"
    fi
}

# Check dependencies for both methods (jq is always needed)
check_common_deps() {
    if ! command -v jq &>/dev/null; then
        echo "Missing dependency: jq"
        echo
        echo "Install jq:"
        echo "  Arch:   sudo pacman -S jq"
        echo "  Ubuntu: sudo apt install jq"
        echo "  Fedora: sudo dnf install jq"
        echo
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Install binary method
install_binary() {
    mkdir -p "$CLAUDE_DIR"

    local binary_path="$CLAUDE_DIR/claude-usage"

    if $LOCAL_MODE && [ -f "$SCRIPT_DIR/dist/claude-usage" ]; then
        echo "Copying binary from local build..."
        cp "$SCRIPT_DIR/dist/claude-usage" "$binary_path"
    else
        echo "Downloading binary from GitHub releases..."
        if ! curl -fsSL "$RELEASE_URL/claude-usage" -o "$binary_path"; then
            echo "ERROR: Failed to download binary"
            echo "The binary may not be available yet. Try Python method instead."
            exit 1
        fi
    fi

    chmod +x "$binary_path"

    # Copy statusline.sh
    if $LOCAL_MODE; then
        cp "$SCRIPT_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh"
    else
        curl -fsSL "$SCRIPT_URL_BASE/statusline.sh" -o "$CLAUDE_DIR/statusline.sh"
    fi
    chmod +x "$CLAUDE_DIR/statusline.sh"

    # Create marker file to indicate binary mode
    echo "binary" > "$CLAUDE_DIR/.install-method"

    echo "Binary installed to $binary_path"
}

# Install Python method
install_python() {
    mkdir -p "$CLAUDE_DIR"

    if $LOCAL_MODE; then
        echo "Copying scripts to $CLAUDE_DIR..."
        cp "$SCRIPT_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh"
        cp "$SCRIPT_DIR/fetch-usage.py" "$CLAUDE_DIR/fetch-usage.py"
    else
        echo "Downloading scripts to $CLAUDE_DIR..."
        curl -fsSL "$SCRIPT_URL_BASE/statusline.sh" -o "$CLAUDE_DIR/statusline.sh"
        curl -fsSL "$SCRIPT_URL_BASE/fetch-usage.py" -o "$CLAUDE_DIR/fetch-usage.py"
    fi

    chmod +x "$CLAUDE_DIR/statusline.sh" "$CLAUDE_DIR/fetch-usage.py"

    # Create marker file to indicate python mode
    echo "python" > "$CLAUDE_DIR/.install-method"

    echo "Scripts installed"
}

# Configure session key
setup_session_key() {
    local key_file="$HOME/.claude-session-key"

    if [ -f "$key_file" ]; then
        echo "Session key already exists at $key_file"
        return
    fi

    echo
    echo "Session key setup:"
    echo "  1. Open https://claude.ai in your browser"
    echo "  2. Open Developer Tools (F12) -> Application -> Cookies"
    echo "  3. Copy the 'sessionKey' value"
    echo
    read -p "Paste your session key (or press Enter to skip): " session_key

    if [ -n "$session_key" ]; then
        echo "$session_key" > "$key_file"
        chmod 600 "$key_file"
        echo "Session key saved to $key_file"
    else
        echo "Skipped. Create $key_file manually later."
    fi
}

# Update settings.json
update_settings() {
    local settings_file="$CLAUDE_DIR/settings.json"
    local script_path="$CLAUDE_DIR/statusline.sh"

    if [ -f "$settings_file" ]; then
        if grep -q '"statusline"' "$settings_file"; then
            echo "statusline already configured in $settings_file"
            echo "  Verify it points to: $script_path"
            return
        fi

        # Add statusline to existing settings
        if command -v jq &>/dev/null; then
            local tmp=$(mktemp)
            jq --arg script "$script_path" '. + {"statusline": {"script": $script}}' "$settings_file" > "$tmp"
            mv "$tmp" "$settings_file"
            echo "Updated $settings_file"
        else
            echo "Cannot update settings (jq not available)"
            echo "  Add manually to $settings_file:"
            echo '  "statusline": {"script": "'"$script_path"'"}'
        fi
    else
        # Create new settings file
        cat > "$settings_file" << EOF
{
  "statusline": {
    "script": "$script_path"
  }
}
EOF
        echo "Created $settings_file"
    fi
}

# Main
main() {
    choose_install_method
    echo

    check_common_deps

    if [ "$INSTALL_METHOD" = "python" ]; then
        check_python_deps
        echo
        install_python
    else
        install_binary
    fi

    echo
    setup_session_key
    echo
    update_settings
    echo
    echo "=== Installation complete ==="
    echo
    echo "Restart Claude Code to see the statusline."
    echo "If usage shows '--', check your session key."
}

main
