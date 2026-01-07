#!/bin/bash
# hooks/after-agent-hook.sh
# The "Controller" hook for the Ralph Wiggum loop.
# Decides if the loop should continue, and if so, leaves a message
# for the "Injector" hook.

set -euo pipefail

STATE_FILE=".gemini/ralph-loop.json"
REPROMPT_FILE=".gemini/ralph-reprompt.tmp"
DEBUG_LOG=".gemini/ralph-debug.log"

# Trap errors
trap 'echo "ERROR: Script crashed on line $LINENO" >> "$DEBUG_LOG"' ERR

# Log start
echo "DEBUG: Hook started." >> "$DEBUG_LOG"

# If state file doesn't exist, the loop isn't active. Exit silently.
if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# Log start
echo "DEBUG: Iteration: $(jq -r '.iteration' "$STATE_FILE")" >> "$DEBUG_LOG"

# Read all necessary data first.
HOOK_INPUT=$(cat)
ORIGINAL_PROMPT=$(jq -r '.prompt' "$STATE_FILE")
CURRENT_PROMPT=$(echo "$HOOK_INPUT" | jq -r '.prompt')

# Handle user interjection.
# Logic:
# 1. If CURRENT_PROMPT is empty, it's a loop continuation (User hit Enter/Auto-run). PROCEED.
# 2. If CURRENT_PROMPT matches ORIGINAL_PROMPT, it's the first turn or a re-prompt. PROCEED.
# 3. If CURRENT_PROMPT contains ORIGINAL_PROMPT (or vice versa), it's likely a formatting artifact. PROCEED.
# 4. Otherwise, the user typed something new. EXIT (Interjection).

if [[ -n "$CURRENT_PROMPT" ]]; then
  # Use Perl to check if one string contains the other (literally).
  # We pass strings as env vars to avoid argument length limits or escaping issues.
  export CURRENT_PROMPT ORIGINAL_PROMPT
  if ! perl -e '
      my $c = $ENV{CURRENT_PROMPT};
      my $o = $ENV{ORIGINAL_PROMPT};
      # 1. Exact match
      exit 0 if $c eq $o;
      # 2. Current contains Original (e.g. CLI added context wrapper)
      exit 0 if index($c, $o) != -1;
      # 3. Original contains Current (e.g. User typed a substring of the prompt?)
      # This case is debatable but present in original logic to handle potential truncation.
      exit 0 if index($o, $c) != -1;
      # No match found -> Interjection.
      exit 1;
    '; then
     # User interjected.
     # LOGGING FOR DEBUGGING
     echo "DEBUG: Ralph Interjection Detected!" >> .gemini/ralph-debug.log
     echo "DEBUG: Original Prompt Length: ${#ORIGINAL_PROMPT}" >> .gemini/ralph-debug.log
     echo "DEBUG: Current Prompt Length: ${#CURRENT_PROMPT}" >> .gemini/ralph-debug.log
     echo "DEBUG: Original Start: ${ORIGINAL_PROMPT:0:50}" >> .gemini/ralph-debug.log
     echo "DEBUG: Current Start: ${CURRENT_PROMPT:0:50}" >> .gemini/ralph-debug.log
     exit 0
  fi
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
  # -0777 enables "slurp" mode to match across newlines (multiline output).
  if echo "$PROMPT_RESPONSE" | perl -0777 -ne 'exit 0 if /<promise>\s*\Q'"$COMPLETION_PROMISE"'\E\s*<\/promise>/; exit 1'; then
    echo "✅ Ralph loop: Completion promise detected." >&2
    # Clean up all state files
    rm "$STATE_FILE"
    rm -f "$REPROMPT_FILE"
    # Explicitly tell the CLI to stop the loop
    jq -n \
      --arg msg "✅ Ralph loop: Completion promise detected. Terminating." \
      '{
        "continue": false,
        "systemMessage": $msg,
        "stopReason": "✅ Ralph loop: Completion promise detected."
      }'
    exit 0
  fi
fi

# Termination Check 2: Max Iterations
# Check if max_iterations is a non-zero value and if iteration has reached it.
if [[ "$MAX_ITERATIONS" -gt 0 ]] && [[ "$ITERATION" -ge "$MAX_ITERATIONS" ]]; then
  echo "🛑 Ralph loop: Max iterations ($MAX_ITERATIONS) reached." >&2
  # Clean up all state files
  rm "$STATE_FILE"
  rm -f "$REPROMPT_FILE"
  # Explicitly tell the CLI to stop the loop
  jq -n \
    --arg msg "🛑 Ralph loop: Max iterations ($MAX_ITERATIONS) reached. Terminating." \
    '{
      "continue": false,
      "systemMessage": $msg,
      "stopReason": ""🛑 Ralph loop: Max iterations ($MAX_ITERATIONS) reached."
    }'
  exit 0
fi

# --- Continuation Logic ---

NEXT_ITERATION=$((ITERATION + 1))
# Use jq to update the iteration in-place.
if jq ".iteration = $NEXT_ITERATION" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"; then
  echo "DEBUG: State updated to iteration $NEXT_ITERATION" >> "$DEBUG_LOG"
else
  echo "ERROR: Failed to update state file" >> "$DEBUG_LOG"
  exit 1
fi

# Create the reprompt file for the BeforeAgent hook to find.
# Use printf to avoid adding a trailing newline, which ensures exact prompt matching in the next turn.
printf "%s" "$ORIGINAL_PROMPT" > "$REPROMPT_FILE"

# Verify write
if [[ ! -s "$REPROMPT_FILE" ]]; then
  echo "ERROR: Failed to write reprompt file" >> "$DEBUG_LOG"
  exit 1
fi
echo "DEBUG: Reprompt file written (size: $(wc -c < "$REPROMPT_FILE"))" >> "$DEBUG_LOG"

# Construct system message
MAX_ITER_MSG_PART=$(if [[ "$MAX_ITERATIONS" -gt 0 ]]; then echo "/$MAX_ITERATIONS"; else echo " of ∞"; fi)
SYSTEM_MSG="🔄 Ralph iteration ${NEXT_ITERATION}${MAX_ITER_MSG_PART}. Continuing task..."

# Output JSON to force continuation.
jq -n \
  --arg msg "$SYSTEM_MSG" \
  '{
    "continue": true,
    "systemMessage": $msg,
    "hookSpecificOutput": "🔄 Ralph iteration ${NEXT_ITERATION}${MAX_ITER_MSG_PART}. Continuing task..."
  }'

exit 0
