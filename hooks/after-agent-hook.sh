#!/bin/bash
# hooks/after-agent-hook.sh
# The "Controller" hook for the Ralph Wiggum loop.
# Decides if the loop should continue, and if so, leaves a message
# for the "Injector" hook.

set -euo pipefail

STATE_FILE=".gemini/ralph-loop.json"
REPROMPT_FILE=".gemini/ralph-reprompt.tmp"

# If state file doesn't exist, the loop isn't active. Exit silently.
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# Read all necessary data first.
HOOK_INPUT=$(cat)
ORIGINAL_PROMPT=$(jq -r '.prompt' "$STATE_FILE")
CURRENT_PROMPT=$(echo "$HOOK_INPUT" | jq -r '.prompt')

# Handle user interjection. If the prompt for the turn that just
# finished is NOT the original loop prompt, the user interjected.
# Do nothing and allow the session to proceed normally (i.e., wait for user input).
if [[ "$CURRENT_PROMPT" != "$ORIGINAL_PROMPT" ]]; then
  exit 0
fi

# -- This is a loop turn, proceed with main logic. --

# Get other state variables.
ITERATION=$(jq -r '.iteration' "$STATE_FILE")
MAX_ITERATIONS=$(jq -r '.max_iterations' "$STATE_FILE")
COMPLETION_PROMISE=$(jq -r '.completion_promise' "$STATE_FILE")
PROMPT_RESPONSE=$(echo "$HOOK_INPUT" | jq -r '.prompt_response')

# Termination Check 1: Completion Promise
# Check for <promise>TEXT</promise> in the final response.
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  # Use perl for portable regex matching (grep -P is not available on macOS).
  # We use \Q...\E to quote the promise text to treat it as a literal.
  if echo "$PROMPT_RESPONSE" | perl -ne 'exit 0 if /<promise>\s*\Q'"$COMPLETION_PROMISE"'\E\s*<\/promise>/; exit 1'; then
    echo "✅ Ralph loop: Completion promise detected." >&2
    # Clean up all state files
    rm "$STATE_FILE"
    rm -f "$REPROMPT_FILE" # -f to avoid error if it doesn't exist
    exit 0 # Allow session to end.
  fi
fi

# Termination Check 2: Max Iterations
# Check if max_iterations is a non-zero value and if iteration has reached it.
if [[ "$MAX_ITERATIONS" -gt 0 ]] && [[ "$ITERATION" -ge "$MAX_ITERATIONS" ]]; then
  echo "🛑 Ralph loop: Max iterations ($MAX_ITERATIONS) reached." >&2
  # Clean up all state files
  rm "$STATE_FILE"
  rm -f "$REPROMPT_FILE"
  exit 0 # Allow session to end.
fi

# --- Continuation Logic ---

# Increment iteration count.
NEXT_ITERATION=$((ITERATION + 1))
# Use jq to update the iteration in-place.
jq ".iteration = $NEXT_ITERATION" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"

# Create the reprompt file for the BeforeAgent hook to find.
echo "$ORIGINAL_PROMPT" > "$REPROMPT_FILE"

# Construct system message for the user.
MAX_ITER_MSG_PART=$(if [[ "$MAX_ITERATIONS" -gt 0 ]]; then echo "/$MAX_ITERATIONS"; else echo " of ∞"; fi)
SYSTEM_MSG="🔄 Ralph iteration ${NEXT_ITERATION}${MAX_ITER_MSG_PART}. Continuing task..."

# Output JSON to force continuation.
jq -n \
  --arg msg "$SYSTEM_MSG" \
  '{
    "continue": true,
    "systemMessage": $msg
  }'

exit 0
