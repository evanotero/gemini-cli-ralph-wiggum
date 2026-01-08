#!/bin/bash
# scripts/cancel-ralph.sh

# This script stops the Ralph Wiggum loop by removing the state file.

set -euo pipefail

STATE_FILE=".gemini/ralph-state.md"

if [[ -f "$STATE_FILE" ]]; then
  rm "$STATE_FILE"
  echo "✅ Ralph loop cancelled."
else
  echo "⚠️  No active Ralph loop found."
fi