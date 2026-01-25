#!/usr/bin/env python3
"""Claude Usage Status Fetcher - Retrieves usage data from Claude API."""

__version__ = "1.1.0"

from curl_cffi import requests
import sys
import os
from datetime import datetime

SESSION_KEY_FILE = os.path.expanduser("~/.claude-session-key")

def main():
    if len(sys.argv) > 1 and sys.argv[1] in ('-v', '-V', '--version'):
        print(f"claude-usage {__version__}")
        sys.exit(0)
    try:
        with open(SESSION_KEY_FILE) as f:
            session_key = f.read().strip()
    except FileNotFoundError:
        print("ERROR:No session key file", file=sys.stderr)
        sys.exit(1)

    session = requests.Session()
    session.headers.update({
        'Accept': 'application/json',
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36',
    })
    session.cookies.set('sessionKey', session_key, domain='claude.ai')

    try:
        # Get organizations
        resp = session.get('https://claude.ai/api/organizations', timeout=5)
        if resp.status_code != 200:
            print("ERROR:Failed to get orgs", file=sys.stderr)
            sys.exit(1)

        orgs = resp.json()
        if not orgs:
            print("ERROR:No organizations", file=sys.stderr)
            sys.exit(1)

        org_id = orgs[0].get('uuid')

        # Get usage
        usage_resp = session.get(f'https://claude.ai/api/organizations/{org_id}/usage', timeout=5)
        if usage_resp.status_code != 200:
            print("ERROR:Failed to get usage", file=sys.stderr)
            sys.exit(1)

        usage = usage_resp.json()
        five_hour = usage.get('five_hour', {})
        utilization = five_hour.get('utilization', 0)
        resets_at = five_hour.get('resets_at', '')

        # Calculate minutes remaining until reset
        if resets_at:
            dt = datetime.fromisoformat(resets_at.replace('+00:00', '+00:00'))
            now = datetime.now(dt.tzinfo)
            delta = dt - now
            minutes_remaining = max(0, int(delta.total_seconds() / 60))
        else:
            minutes_remaining = -1  # Unknown

        print(f"{int(utilization)}|{minutes_remaining}")

    except requests.exceptions.RequestException as e:
        print(f"ERROR:{e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR:{e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
