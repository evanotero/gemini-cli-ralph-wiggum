#!/bin/bash
# hooks/before-agent-hook.sh
# The "Injector" hook for the Ralph Wiggum loop.
# Checks for a temporary file left by the controller hook and injects the
# original prompt back into the agent's context.

set -euo pipefail

REPROMPT_FILE=".gemini/ralph-reprompt.tmp"

# If the reprompt file doesn't exist, this isn't a loop turn. Exit silently.
if [[ ! -f "$REPROMPT_FILE" ]]; then
  exit 0
fi

# Read the prompt from the temp file.
PROMPT_FROM_FILE=$(cat "$REPROMPT_FILE")

# Immediately delete the temp file so this hook doesn't run again accidentally.
rm "$REPROMPT_FILE"

# If the prompt read from the file is empty, something is wrong.
# Exit to avoid injecting an empty prompt.
if [[ -z "$PROMPT_FROM_FILE" ]]; then
  exit 0
fi

# Use jq to construct the JSON output that adds the prompt to the context.
# The Gemini CLI will prepend this to the user's (empty) input.
jq -n \
  --arg prompt "$PROMPT_FROM_FILE" \
  '{ 
    "hookSpecificOutput": { 
      "hookEventName": "BeforeAgent", 
      "additionalContext": $prompt 
    } 
  }'

exit 0
