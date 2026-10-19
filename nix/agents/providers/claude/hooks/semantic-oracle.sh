#!/usr/bin/env bash
# PostToolUse Oracle: semantic diagnostic gate after code edits.
#
# Enforces the *guarantee* (edit did not break the build) rather than forcing a
# navigation tool. Reads the per-language `diagnose` command from the SSoT table
# (modules/language/language.hm.nix → ~/.claude/lang-tools.json), runs it, and feeds NEW
# breakage back to Claude. No diagnose command → grep fallback (records intent,
# no hard check). nix is handled by live-oracle, so it has no diagnose entry.
#
# Scope (reversibility-tiered): S is exempt; M runs the check but only prints a
# non-blocking advisory on NEW breakage (thin ceremony for routine work); L
# hard-blocks on NEW breakage (thick control for risky/irreversible work). A/B is
# controlled at runtime by the experiment-arm file (on|off) — no rebuild needed.
#
# Env overrides (used by the bats suite):
#   LANG_TOOLS_JSON, EXPERIMENT_ARM_FILE, COMPLEXITY_DIR, TELEMETRY_FILE
#
# Exit codes: 2 = new breakage at L (forces Claude to address); 0 otherwise
# (including M new breakage, which emits an advisory + `advisory-new` telemetry).

set -uo pipefail

STATE_DIR="${AGENT_POLICY_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-policy}"
LANG_TOOLS_JSON="${LANG_TOOLS_JSON:-$HOME/.claude/lang-tools.json}"
EXPERIMENT_ARM_FILE="${EXPERIMENT_ARM_FILE:-$STATE_DIR/experiment-arm}"
COMPLEXITY_DIR="${COMPLEXITY_DIR:-/tmp/claude-complexity}"
TELEMETRY_FILE="${TELEMETRY_FILE:-$STATE_DIR/oracle-telemetry.jsonl}"
CACHE_DIR="${TMPDIR:-/tmp}/claude-oracle"

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty' 2>/dev/null)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "default"' 2>/dev/null)

case "$TOOL_NAME" in
  Write|Edit|NotebookEdit) ;;
  *) exit 0 ;;
esac

FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null)
[[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]] && exit 0
[[ ! -f "$LANG_TOOLS_JSON" ]] && exit 0

EXT="${FILE_PATH##*.}"
BASENAME=$(basename "$FILE_PATH")

# Resolve A/B arm (default on) and complexity (default missing → treated as skip).
ARM="on"
[[ -f "$EXPERIMENT_ARM_FILE" ]] && ARM=$(tr -d '[:space:]' < "$EXPERIMENT_ARM_FILE")
COMPLEXITY="unknown"
[[ -f "$COMPLEXITY_DIR/$SESSION_ID" ]] && COMPLEXITY=$(tr -d '[:space:]' < "$COMPLEXITY_DIR/$SESSION_ID")

emit() {
  # $1=result $2=fallback(bool) $3=latency_ms $4=tool
  mkdir -p "$(dirname "$TELEMETRY_FILE")"
  jq -nc \
    --arg ts "$(date -u +%FT%TZ)" \
    --arg lang "$EXT" --arg tool "${4:-}" --arg path "$FILE_PATH" \
    --arg result "$1" --argjson fallback "$2" --argjson latency "${3:-0}" \
    --arg arm "$ARM" --arg complexity "$COMPLEXITY" --arg session "$SESSION_ID" \
    '{ts:$ts, hook:"semantic-oracle", lang:$lang, tool:$tool, path:$path,
      result:$result, fallback:$fallback, latency_ms:$latency,
      arm:$arm, complexity:$complexity, session:$session}' \
    >> "$TELEMETRY_FILE" 2>/dev/null || true
}

# A/B OFF arm: record the sample, run no check.
if [[ "$ARM" == "off" ]]; then
  emit "skip-arm-off" true 0 ""
  exit 0
fi

# Scope gate: only M/L edits are worth a diagnostic pass.
case "$COMPLEXITY" in
  M|L) ;;
  *) emit "skip-scope" false 0 ""; exit 0 ;;
esac

DIAGNOSE_CMD=$(jq -r --arg e "$EXT" '.[$e].diagnose // empty' "$LANG_TOOLS_JSON" 2>/dev/null)

# No diagnose for this language → grep fallback (intent recorded, no hard gate).
if [[ -z "$DIAGNOSE_CMD" ]]; then
  emit "fallback-no-diagnose" true 0 ""
  exit 0
fi

# Diagnostic tool unavailable on PATH → fallback (the "LSP failed" branch).
read -ra DPARTS <<< "$DIAGNOSE_CMD"
if ! command -v "${DPARTS[0]}" &>/dev/null; then
  emit "fallback-tool-missing" true 0 "$DIAGNOSE_CMD"
  exit 0
fi

# Seconds granularity — portable across BSD/macOS (no GNU %N).
# timeout is optional (absent on stock macOS); fold it into one non-empty
# array so expansion stays safe under `set -u` on bash 3.2.
CMD=()
command -v timeout &>/dev/null && CMD=(timeout 60)
CMD+=("${DPARTS[@]}")
START=$(date +%s)
DIAG_OUTPUT=$("${CMD[@]}" 2>&1)
DIAG_RC=$?
LATENCY=$(( ($(date +%s) - START) * 1000 ))

if [[ $DIAG_RC -eq 0 ]]; then
  emit "pass" false "$LATENCY" "$DIAGNOSE_CMD"
  exit 0
fi

# Change-based gate: only force when the failure set is NEW vs the last run,
# so pre-existing/unrelated errors don't block every edit.
mkdir -p "$CACHE_DIR"
CACHE_KEY=$(echo "$FILE_PATH" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "$BASENAME")
CACHE_FILE="$CACHE_DIR/$CACHE_KEY"
CURRENT_HASH=$(echo "$DIAG_OUTPUT" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "none")

if [[ -f "$CACHE_FILE" ]] && [[ "$(cat "$CACHE_FILE")" == "$CURRENT_HASH" ]]; then
  emit "fail-unchanged" false "$LATENCY" "$DIAGNOSE_CMD"
  exit 0
fi
echo "$CURRENT_HASH" > "$CACHE_FILE"

# Tiered response on NEW breakage: L hard-blocks (thick control for risky work),
# M downgrades to a non-blocking advisory (thin ceremony for routine edits). The
# A/B telemetry stays distinguishable via the result tag (fail-new vs advisory-new).
if [[ "$COMPLEXITY" == "M" ]]; then
  emit "advisory-new" false "$LATENCY" "$DIAGNOSE_CMD"
  echo "[SEMANTIC-ORACLE][advisory] '$DIAGNOSE_CMD' failed after editing $BASENAME — your change may have broken the build (non-blocking at M complexity):" >&2
  echo "$DIAG_OUTPUT" | head -25 >&2
  exit 0
fi

emit "fail-new" false "$LATENCY" "$DIAGNOSE_CMD"
echo "[SEMANTIC-ORACLE] '$DIAGNOSE_CMD' failed after editing $BASENAME — your change may have broken the build:" >&2
echo "$DIAG_OUTPUT" | head -25 >&2
exit 2
