#!/usr/bin/env bash
# Validate repository-bound PRD -> design -> implementation -> test -> evidence.
set -euo pipefail

[[ $# -ge 1 && -f "${1:-}" ]] || {
  echo "usage: $0 TRACEABILITY.tsv [--repo-root DIR] [--prd-root DIR]" >&2
  exit 2
}
TRACE=$1
shift
REPO_ROOT=.
PRD_ROOT=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-root) REPO_ROOT=$2; shift 2 ;;
    --prd-root) PRD_ROOT=$2; shift 2 ;;
    *) echo "traceability gate: invalid argument" >&2; exit 2 ;;
  esac
done
[[ -d "$REPO_ROOT" ]] || { echo "traceability gate: repository root missing" >&2; exit 2; }
REPO_ROOT=$(cd "$REPO_ROOT" && pwd -P)
if [[ -n "$PRD_ROOT" ]]; then
  [[ -d "$PRD_ROOT" ]] || { echo "traceability gate: PRD root missing" >&2; exit 2; }
  PRD_ROOT=$(cd "$PRD_ROOT" && pwd -P)
fi

awk -F '\t' '
  NR == 1 {
    expected = "repository\trevision\tphase\trequirement_id\tstatus\tdesign\timplementation\ttest\tverification"
    if ($0 != expected) {
      print "invalid traceability header" > "/dev/stderr"
      exit 2
    }
    next
  }
  NF != 9 {
    printf "line %d: expected 9 TSV columns\n", NR > "/dev/stderr"
    exit 2
  }
  $1 != "self" {
    printf "line %d (%s): unsupported repository identity %s\n", NR, $4, $1 > "/dev/stderr"
    exit 2
  }
  $3 !~ /^[0-5]$/ {
    printf "line %d (%s): invalid phase %s\n", NR, $4, $3 > "/dev/stderr"
    exit 2
  }
  $4 == "" || $4 == "-" {
    printf "line %d: missing requirement_id\n", NR > "/dev/stderr"
    exit 2
  }
  $5 !~ /^(proposed|specified|ready|in_progress|implemented|verified|deferred|rejected|blocked)$/ {
    printf "line %d (%s): unknown status %s\n", NR, $4, $5 > "/dev/stderr"
    exit 2
  }
  ($5 == "implemented" || $5 == "verified") && $2 !~ /^[0-9a-f]{7,40}$/ {
    printf "line %d (%s): immutable revision required for %s\n", NR, $4, $5 > "/dev/stderr"
    exit 2
  }
  {
    seen[$4]++
    required["proposed"] = "6"
    required["specified"] = "6"
    required["ready"] = "6,8"
    required["in_progress"] = "6,8"
    required["implemented"] = "6,7,8,9"
    required["verified"] = "6,7,8,9"
    required["deferred"] = "6,9"
    required["rejected"] = "6,9"
    required["blocked"] = "6,9"
    count = split(required[$5], fields, ",")
    for (i = 1; i <= count; i++) {
      field = fields[i]
      if ($field == "" || $field == "-") {
        printf "line %d (%s): missing traceability field %s\n", NR, $4, field > "/dev/stderr"
        exit 2
      }
    }
    rows++
  }
  END {
    if (rows == 0) {
      print "traceability file has no requirements" > "/dev/stderr"
      exit 2
    }
    for (id in seen) if (seen[id] > 1) {
      printf "duplicate requirement_id: %s\n", id > "/dev/stderr"
      exit 2
    }
    printf "traceability schema valid: %d requirements\n", rows
  }
' "$TRACE"

resolve_artifact() {
  local reference=$1 artifact candidate real
  artifact=${reference%%#*}
  artifact=${artifact%%:*}
  [[ -n "$artifact" && "$artifact" != "-" && "$artifact" != /* && "$artifact" != *".."* ]] || {
    echo "traceability blocked: reference escapes repository root: $reference" >&2
    return 2
  }
  candidate="$REPO_ROOT/$artifact"
  [[ -e "$candidate" ]] || {
    echo "traceability blocked: missing artifact $reference" >&2
    return 2
  }
  real=$(cd "$(dirname "$candidate")" && pwd -P)/$(basename "$candidate")
  case "$real" in
    "$REPO_ROOT"|"$REPO_ROOT"/*) ;;
    *) echo "traceability blocked: reference escapes repository root: $reference" >&2; return 2 ;;
  esac
}

while IFS=$'\t' read -r repository revision phase requirement state design implementation test verification; do
  [[ "$state" == verified ]] || continue
  for references in "$design" "$implementation" "$test" "$verification"; do
    IFS=';' read -r -a values <<<"$references"
    for reference in "${values[@]}"; do resolve_artifact "$reference"; done
  done
done < <(tail -n +2 "$TRACE")

if [[ -n "$PRD_ROOT" ]]; then
  prd_index=$(mktemp)
  trap 'rm -f "$prd_index"' EXIT
  awk '
    /^### (FR|PH)-[A-Za-z0-9-]+/ {id=$2; next}
    id != "" && /^- Status: / {print id "\t" $3; id=""}
  ' "$PRD_ROOT"/*.md > "$prd_index"
  while IFS=$'\t' read -r _repository _revision _phase requirement state _rest; do
    matches=$(awk -F '\t' -v id="$requirement" '$1 == id {print $2}' "$prd_index")
    [[ -n "$matches" ]] || { echo "traceability blocked: $requirement missing from PRD" >&2; exit 2; }
    [[ "$(wc -l <<<"$matches" | tr -d ' ')" == 1 && "$matches" == "$state" ]] || {
      echo "traceability blocked: $requirement PRD/TSV state mismatch" >&2
      exit 2
    }
  done < <(tail -n +2 "$TRACE")
fi

count=$(awk 'END {print NR-1}' "$TRACE")
echo "traceability gate passed: $count requirements"
