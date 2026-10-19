#!/usr/bin/env bash
# UserPromptSubmit Hook: Complexity Router (Inferential Guide)
# Injects complexity classification prompt into Claude's context.
# Only injects on the FIRST turn (no state file yet) to save tokens.
#
# State files:
#   /tmp/claude-complexity/{session_id}          → "S", "M", or "L"
#   /tmp/claude-complexity/{session_id}.approved  → exists = strategy approved
#
# Exit codes:
#   0 = always (never blocks prompts)
#
# stdout → added as context Claude sees before processing the prompt.

set -uo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null)
PROMPT=$(echo "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)

STATE_DIR="${COMPLEXITY_DIR:-/tmp/claude-complexity}"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/$SESSION_ID"
REVERSIBILITY_FILE="$STATE_DIR/${SESSION_ID}.reversibility"

# --- Reversibility classification (runs every turn, overwriting on each call) ---
# Grep prompt for risk keywords (case-insensitive). Deterministic: any match = irreversible.
# Narrow on purpose: only genuinely destructive command/DDL patterns escalate to the
# heavy ceremony tier. Benign mentions (delete/remove/prod/deploy) must NOT over-escalate
# — routine action safety is handled by cmd-guard/branch-guard/path-guard hooks instead.
RISK_PATTERN='rm -rf|reset --hard|force[ -]push|drop table|drop database|truncate|migrate|revoke'
if echo "$PROMPT" | grep -qiE "$RISK_PATTERN"; then
  echo "irreversible" > "$REVERSIBILITY_FILE"
else
  echo "reversible" > "$REVERSIBILITY_FILE"
fi

# If complexity state already classified, skip injection (save tokens)
if [[ -f "$STATE_FILE" ]]; then
  exit 0
fi

# Inject classification prompt — Claude sees this as pre-context
cat <<EOF
[COMPLEXITY ROUTER] Before acting, classify this request:

  S — Target file and change are obvious. No design decision needed.
  M — Clear goal, but need to find where/how. Multiple files possible.
  L — Design decision required. Architecture, tradeoffs, or external research needed.

After classifying, run:  echo "S" > $STATE_FILE  (or M or L)

Workflow by classification:
  S → Grep/Read → Edit → done
  M → Brief research → TDD loop (Red→Green→Refactor) → done
  L → Research → Strategy + Pre-mortem → present to user → WAIT for approval
      → after user approves, run:  touch ${STATE_FILE}.approved
      → then proceed with TDD loop
EOF

exit 0
