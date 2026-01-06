#!/bin/bash
# scripts/setup-ralph-loop.sh

# This script initializes the Ralph Wiggum loop by creating a state file.

set -euo pipefail

# Parse arguments
PROMPT_PARTS=()
MAX_ITERATIONS=0
COMPLETION_PROMISE="null"

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
      PROMPT_PARTS+=("$1")
      shift
      ;;
  esac
done

PROMPT="${PROMPT_PARTS[*]}"

if [[ -z "$PROMPT" ]]; then
  echo "ERROR: No prompt provided for the loop." >&2
  exit 1
fi

# Create state directory and file
mkdir -p .gemini
cat > .gemini/ralph-loop.json <<EOF
{
  "prompt": $(jq -n --arg prompt "$PROMPT" '$prompt'),
  "iteration": 1,
  "max_iterations": $MAX_ITERATIONS,
  "completion_promise": $(jq -n --arg promise "$COMPLETION_PROMISE" '$promise'),
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# Output setup message
echo "🔄 Ralph loop activated in this session!"
echo "Max iterations: $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo $MAX_ITERATIONS; else echo "unlimited"; fi)"
echo "Completion promise: $(if [[ "$COMPLETION_PROMISE" != "null" ]]; then echo "'$COMPLETION_PROMISE'"; else echo "none"; fi)"
echo "The SessionEnd hook is now active. It will intercept session exit to continue the loop."
echo "To manually stop, use the /cancel-ralph command."
echo ""
echo "Initial prompt:"
echo "$PROMPT"
