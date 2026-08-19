#!/bin/bash
# Reports line coverage from an .xcresult bundle. Defaults to the newest local test run.
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

BUNDLE="${1:-$(ls -dt build/Logs/Test/*.xcresult 2>/dev/null | head -1 || true)}"
[ -n "$BUNDLE" ] && [ -e "$BUNDLE" ] || { echo "No .xcresult found. Run the tests first." >&2; exit 1; }

xcrun xccov view --report --json "$BUNDLE" | python3 scripts/coverage.py
