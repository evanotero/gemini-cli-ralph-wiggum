#!/bin/bash
# scripts/setup-ralph-loop.sh

# This script initializes the Ralph Wiggum loop by creating a state file.

set -euo pipefail

# Parse arguments
PROMPT_PARTS=()
MAX_ITERATIONS=0
COMPLETION_PROMISE="null"

# If we received a single argument that contains spaces, it's likely the full {{args}} string.
# We use xargs to correctly split the string respecting quotes (shell-style parsing),
# which is safer and more robust than simple whitespace splitting.
if [[ $# -eq 1 ]] && [[ "$1" == *" "* ]]; then
  SPLIT_ARGS=()
  while IFS= read -r -d '' arg; do
    SPLIT_ARGS+=("$arg")
  done < <(printf "%s" "$1" | xargs printf "%s\0")
  set -- "${SPLIT_ARGS[@]}"
fi

while [[ $# -gt 0 ]]; do
  case $1 in
    --max-iterations)
      if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "ERROR: --max-iterations requires a number." >&2
        exit 1
      fi
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --completion-promise)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --completion-promise requires a text argument." >&2
        exit 1
      fi
      COMPLETION_PROMISE="$2"
      shift 2
      ;;
    *)
      # Non-option argument - collect all as prompt parts
      PROMPT_PARTS+=("$1")
      shift
      ;;
  esac
done

# If no prompt parts were collected, raise an error immediately.
if [ ${#PROMPT_PARTS[@]} -eq 0 ]; then
  echo "ERROR: No prompt provided for the loop." >&2
  exit 1
fi

PROMPT="${PROMPT_PARTS[*]}"

# Construct the full prompt including instructions
SYSTEM_INSTRUCTIONS=$(cat <<EOF

---
**SYSTEM INSTRUCTIONS: RALPH WIGGUM LOOP**

You are now in a **persistent, self-correcting development loop**.
1.  **Iterative Workflow:** When you complete this turn, the **exact same prompt** (above) will be fed back to you automatically.
2.  **Memory:** You will see your previous work (files, git history) in the next iteration. Use this to refine, debug, and improve your solution step-by-step.
3.  **Termination:** The loop continues INDEFINITELY until the termination condition is met.

**CRITICAL RULE: COMPLETION PROMISE**
If a "Completion promise" is defined above (e.g., specific text to output):
*   You **MUST NOT** output that phrase until the condition is **100% GENUINELY TRUE**.
*   **DO NOT LIE** to exit the loop. If tests are failing, fix them. If the feature is incomplete, finish it.
*   **REQUIRED FORMAT:** When the condition is met, you must output the promise wrapped in XML tags like this:
    \`<promise>YOUR_PROMISE_TEXT</promise>\`
    (Example: \`<promise>PROMISE_KEPT</promise>\`)
*   If you output the promise prematurely, you defeat the purpose of the loop.

**Goal:** Work autonomously to satisfy the initial prompt completely.
EOF
)

# Banner information
MAX_ITER_TXT=$(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo "$MAX_ITERATIONS"; else echo "unlimited"; fi)
PROMISE_TXT=$(if [[ "$COMPLETION_PROMISE" != "null" ]]; then echo "'$COMPLETION_PROMISE'"; else echo "none"; fi)

# Construct the exact text that will be the "Original Prompt"
# We include the banner info so the model is aware of its constraints.
FULL_PROMPT="Max iterations: $MAX_ITER_TXT
Completion promise: $PROMISE_TXT

Initial prompt:
$PROMPT
$SYSTEM_INSTRUCTIONS"

# Create state directory and file
mkdir -p .gemini
cat > .gemini/ralph-loop.json <<EOF
{
  "prompt": $(jq -n --arg prompt "$FULL_PROMPT" '$prompt'),
  "iteration": 1,
  "max_iterations": $MAX_ITERATIONS,
  "completion_promise": $(jq -n --arg promise "$COMPLETION_PROMISE" '$promise'),
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# Initialize debug log
echo "[$(date +'%Y-%m-%dT%H:%M:%S')] --- Loop Started ---" >> .gemini/ralph-debug.log
echo "[$(date +'%Y-%m-%dT%H:%M:%S')] Prompt length: ${#FULL_PROMPT} chars" >> .gemini/ralph-debug.log
echo "[$(date +'%Y-%m-%dT%H:%M:%S')] Max iterations: $MAX_ITERATIONS" >> .gemini/ralph-debug.log
echo "[$(date +'%Y-%m-%dT%H:%M:%S')] Promise: $COMPLETION_PROMISE" >> .gemini/ralph-debug.log

# Output setup message (and prompt) to stdout for the model
printf "%s" "$FULL_PROMPT"

# Output info to stderr for the user (optional, but good for feedback if !{...} hides stdout)
echo "🔄 Ralph loop activated! " >&2
