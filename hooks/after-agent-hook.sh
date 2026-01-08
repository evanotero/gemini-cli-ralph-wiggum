#!/bin/bash
# hooks/after-agent-hook.sh
# The "Controller" hook for the Ralph Wiggum loop.
# Decides if the loop should continue, and if so, passes the prompt
# back via the 'reason' field.

set -euo pipefail

RALPH_STATE_FILE=".gemini/ralph-state.md"

# If state file doesn't exist, the loop isn't active. Exit silently.
if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  exit 0
fi

# Read necessary data
HOOK_INPUT=$(cat)

# Extract variables from Frontmatter
ITERATION=$(grep "^iteration:" "$RALPH_STATE_FILE" | head -n1 | cut -d' ' -f2)
MAX_ITERATIONS=$(grep "^max_iterations:" "$RALPH_STATE_FILE" | head -n1 | cut -d' ' -f2)
COMPLETION_PROMISE=$(grep "^completion_promise:" "$RALPH_STATE_FILE" | head -n1 | sed 's/^completion_promise: \(.*\)"$/\1/')

# --- Defensive Validation (Adopted from Claude Code logic) ---

# Validate numeric fields
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]] || [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "⚠️  Ralph loop: State file corrupted" >&2
  echo "   File: $RALPH_STATE_FILE" >&2
  echo "   Problem: 'iteration' or 'max_iterations' is not a valid number." >&2
  echo "" >&2
  echo "   Ralph loop is stopping. Run /ralph:loop again to start fresh." >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

# Extract PROMPT using awk (skip frontmatter)
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")

if [[ -z "$PROMPT_TEXT" ]]; then
  echo "⚠️  Ralph loop: State file corrupted or incomplete" >&2
  echo "   Problem: No prompt text found in $RALPH_STATE_FILE" >&2
  echo "   Ralph loop is stopping." >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

PROMPT_RESPONSE=$(echo "$HOOK_INPUT" | jq -r '.prompt_response // empty')

# --- Termination Checks ---

# 1. Completion Promise
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  if echo "$PROMPT_RESPONSE" | perl -0777 -ne 'exit 0 if /<promise>\s*\Q'"$COMPLETION_PROMISE"'\E\s*<\/promise>/; exit 1'; then
    echo "✅ Ralph loop: Completion promise detected." >&2
    rm "$RALPH_STATE_FILE"
    jq -n \
      --arg msg "✅ Ralph loop: Completion promise detected. Terminating." \
      '{
        "continue": false,
        "systemMessage": $msg
      }'
    exit 0
  fi
fi

# 2. Max Iterations
if [[ "$MAX_ITERATIONS" -gt 0 ]] && [[ "$ITERATION" -ge "$MAX_ITERATIONS" ]]; then
  echo "🛑 Ralph loop: Max iterations ($MAX_ITERATIONS) reached." >&2
  rm "$RALPH_STATE_FILE"
  jq -n \
    --arg msg "🛑 Ralph loop: Max iterations ($MAX_ITERATIONS) reached. Terminating." \
    '{
      "continue": false,
      "systemMessage": $msg
    }'
  exit 0
fi

# --- Continuation Logic ---

NEXT_ITERATION=$((ITERATION + 1))

# Update iteration in frontmatter atomically
TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$RALPH_STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$RALPH_STATE_FILE"

# Build system message with iteration count
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  SYSTEM_MSG="🔄 Ralph iteration $NEXT_ITERATION | To stop: output <promise>$COMPLETION_PROMISE</promise>"
else
  SYSTEM_MSG="🔄 Ralph iteration $NEXT_ITERATION | No completion promise set - loop runs infinitely"
fi

# Output JSON to inject the prompt back
jq -n \
  --arg prompt "$PROMPT_TEXT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "continue": true,
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
