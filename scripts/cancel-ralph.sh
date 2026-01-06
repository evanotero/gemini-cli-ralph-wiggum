#!/bin/bash
# scripts/cancel-ralph.sh

# This script cancels an active Ralph Wiggum loop by removing the state file.

set -euo pipefail

STATE_FILE=".gemini/ralph-loop.json"

if [[ -f "$STATE_FILE" ]]; then
  ITERATION=$(jq -r '.iteration' "$STATE_FILE")
  rm "$STATE_FILE"
  echo "✅ Ralph loop canceled at iteration $ITERATION."
else
  echo "No active Ralph loop found."
fi
