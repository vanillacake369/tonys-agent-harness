#!/usr/bin/env bash
# Shared fail-closed guard for sensitive paths and dangerous shell input.
set -euo pipefail
INPUT=$(cat)
if ! jq -e 'type == "object" and (.tool_name | type == "string" and length > 0) and
  (.tool_input | type == "object") and
  (((.tool_input.command // "") | type == "string" and length > 0) or
   (((.tool_input.file_path // .tool_input.path // .tool_input.notebook_path // "") | type == "string" and length > 0)))' <<<"$INPUT" >/dev/null 2>&1; then
  echo "blocked: invalid tool payload" >&2
  exit 2
fi
tool_name=$(jq -r '.tool_name // ""' <<<"$INPUT" 2>/dev/null || true)
file_path=$(jq -r '.tool_input.file_path // .tool_input.path // .tool_input.notebook_path // ""' <<<"$INPUT" 2>/dev/null || true)
command=$(jq -r '.tool_input.command // ""' <<<"$INPUT" 2>/dev/null || true)
# Provider file fields are paths and receive strict matching. Bash input is
# free-form text, so only clear path-shaped references are matched there;
# searching docs for words such as "secrets" is not itself secret access.
normalized_file=${file_path//\"/ }
normalized_file=${normalized_file//\'/ }
normalized_command=${command//\"/ }
normalized_command=${normalized_command//\'/ }
if [[ "$normalized_file" =~ (^|[[:space:]/])\.env([.[:space:]/]|$) || "$normalized_file" =~ (^|[[:space:]/])(secrets|credentials|\.ssh|\.gnupg)([[:space:]/]|$) || "$normalized_file" =~ (private[_-]?key|id_rsa|\.pem|\.key)([[:space:]/]|$) ]] \
  || [[ "$normalized_command" =~ (^|[[:space:]])([^[:space:]]*/)?\.env([./[:space:]]|$) ]] \
  || [[ "$normalized_command" =~ (^|[[:space:]])([^[:space:]]*/)(secrets|credentials|\.ssh|\.gnupg)(/[^[:space:]]*|[[:space:]]|$) ]] \
  || [[ "$normalized_command" =~ (^|[[:space:]])(secrets|credentials|\.ssh|\.gnupg)/[^[:space:]]+ ]] \
  || [[ "$normalized_command" =~ (^|[[:space:]])[^[:space:]]*(private[_-]?key|id_rsa|\.pem|\.key)([[:space:]]|$) ]]; then
  echo "blocked: sensitive path or credential material is not accessible ($tool_name)" >&2
  exit 2
fi
if [[ "$command" =~ (rm[[:space:]]+-rf[[:space:]]+(/|\$HOME|~)|git[[:space:]]+push[[:space:]]+.*--force|curl[^|]*\|[[:space:]]*(sh|bash)|git[[:space:]]+reset[[:space:]]+--hard) ]]; then
  echo "blocked: dangerous command requires deterministic policy review" >&2
  exit 2
fi
exit 0
