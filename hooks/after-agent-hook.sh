#!/bin/bash
# hooks/after-agent-hook.sh
# The "Controller" hook for the Ralph Wiggum loop.
# Decides if the loop should continue, and if so, leaves a message
# for the "Injector" hook.

set -euo pipefail

STATE_FILE=".gemini/ralph-loop.json"
REPROMPT_FILE=".gemini/ralph-reprompt.tmp"
DEBUG_LOG=".gemini/ralph-debug.log"

log() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S')] $*" >> "$DEBUG_LOG"
}

log "--- Hook Started ---"

# If state file doesn't exist, the loop isn't active. Exit silently.
if [[ ! -f "$STATE_FILE" ]]; then
  log "State file not found. Exiting."
  exit 0
fi

# Read all necessary data first.
HOOK_INPUT=$(cat)
# log "Hook Input: $HOOK_INPUT" # Commented out to reduce noise, enable if needed

ORIGINAL_PROMPT=$(jq -r '.prompt' "$STATE_FILE")
CURRENT_PROMPT=$(echo "$HOOK_INPUT" | jq -r '.prompt')

# Handle user interjection.
if [[ "$CURRENT_PROMPT" != "$ORIGINAL_PROMPT" ]]; then
  log "Interjection detected!"
  log "Original len: ${#ORIGINAL_PROMPT}, Current len: ${#CURRENT_PROMPT}"
  # log "Original: $ORIGINAL_PROMPT"
  # log "Current: $CURRENT_PROMPT"
  exit 0
fi

log "Prompt match confirmed. Proceeding."

# Get other state variables.
ITERATION=$(jq -r '.iteration' "$STATE_FILE")
MAX_ITERATIONS=$(jq -r '.max_iterations' "$STATE_FILE")
COMPLETION_PROMISE=$(jq -r '.completion_promise' "$STATE_FILE")
PROMPT_RESPONSE=$(echo "$HOOK_INPUT" | jq -r '.prompt_response')

log "Iteration: $ITERATION, Max: $MAX_ITERATIONS"
log "Promise Target: $COMPLETION_PROMISE"
log "Response substring: ${PROMPT_RESPONSE:0:100}..."

# Termination Check 1: Completion Promise
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  # Use perl for portable regex matching (grep -P is not available on macOS).
  # We use \Q...\E to quote the promise text to treat it as a literal.
  # -0777 enables "slurp" mode to match across newlines (multiline output).
  if echo "$PROMPT_RESPONSE" | perl -0777 -ne 'exit 0 if /<promise>\s*\Q'"$COMPLETION_PROMISE"'\E\s*<\/promise>/; exit 1'; then
    echo "✅ Ralph loop: Completion promise detected." >&2
    log "Promise matched! Terminating loop."
    rm "$STATE_FILE"
    rm -f "$REPROMPT_FILE"
    exit 0
  else
    log "Promise check failed."
  fi
fi

# Termination Check 2: Max Iterations
if [[ "$MAX_ITERATIONS" -gt 0 ]] && [[ "$ITERATION" -ge "$MAX_ITERATIONS" ]]; then
  echo "🛑 Ralph loop: Max iterations ($MAX_ITERATIONS) reached." >&2
  log "Max iterations reached. Terminating."
  rm "$STATE_FILE"
  rm -f "$REPROMPT_FILE"
  exit 0
fi

# --- Continuation Logic ---

NEXT_ITERATION=$((ITERATION + 1))
log "Incrementing to iteration $NEXT_ITERATION"

# Use jq to update the iteration in-place.
if jq ".iteration = $NEXT_ITERATION" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"; then
  log "State file updated successfully."
else
  log "ERROR: Failed to update state file."
  exit 1
fi

# Create the reprompt file
# Use printf to avoid adding a trailing newline, which ensures exact prompt matching in the next turn.
printf "%s" "$ORIGINAL_PROMPT" > "$REPROMPT_FILE"
log "Reprompt file created."

# Construct system message

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
