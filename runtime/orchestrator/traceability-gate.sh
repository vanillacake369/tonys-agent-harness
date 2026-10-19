#!/usr/bin/env bash
# Validate PRD -> design -> code -> test -> verification traceability.
# Input is a TSV file with the exact header below. A dash is not evidence when
# the requirement state says the artifact is required.

set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 || ! -f "$1" ]]; then
  echo "usage: $0 TRACEABILITY.tsv [--prd-root DIR]" >&2
  exit 2
fi
TRACE=$1; shift
PRD_ROOT=
if [[ $# -eq 2 && "$1" == --prd-root && -d "$2" ]]; then PRD_ROOT=$2; elif [[ $# -ne 0 ]]; then exit 2; fi

awk -F '\t' '
  NR == 1 {
    if ($0 != "requirement_id\tstatus\tdesign\tcode\ttest\tverification") {
      print "invalid header: expected requirement_id, status, design, code, test, verification" > "/dev/stderr"
      exit 2
    }
    next
  }
  NF != 6 {
    printf "line %d: expected 6 TSV columns\n", NR > "/dev/stderr"
    exit 2
  }
  $1 == "" || $1 == "-" {
    printf "line %d: missing requirement_id\n", NR > "/dev/stderr"
    exit 2
  }
  $2 !~ /^(proposed|specified|ready|in_progress|implemented|verified|deferred|rejected|blocked)$/ {
    printf "line %d (%s): unknown status %s\n", NR, $1, $2 > "/dev/stderr"
    exit 2
  }
  {
    seen[$1]++
    required["proposed"] = "3"
    required["specified"] = "3"
    required["ready"] = "3,5"
    required["in_progress"] = "3,5"
    required["implemented"] = "3,4,5,6"
    required["verified"] = "3,4,5,6"
    required["deferred"] = "3,6"
    required["rejected"] = "3,6"
    required["blocked"] = "3,6"
    count = split(required[$2], fields, ",")
    for (i = 1; i <= count; i++) {
      field = fields[i]
      if ($field == "" || $field == "-") {
        printf "line %d (%s): missing traceability field %s\n", NR, $1, field > "/dev/stderr"
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

# Verified entries must reference persisted local artifacts, not command names.
# Paths are relative to the caller's repository root; :line and #anchor are
# allowed suffixes. Other states retain their state-specific schema checks.
while IFS=$'\t' read -r requirement state design code test verification; do
  [[ "$state" == verified ]] || continue
  for reference in "$design" "$code" "$test" "$verification"; do
    artifact=${reference%%#*}
    artifact=${artifact%%:*}
    if [[ ! -f "$artifact" ]]; then
      echo "traceability blocked: $requirement missing artifact $reference" >&2
      exit 2
    fi
  done
done < "$TRACE"
if [[ -n "$PRD_ROOT" ]]; then
  prd_index=$(mktemp)
  trap 'rm -f "$prd_index"' EXIT
  awk '
    /^### FR-[A-Za-z0-9-]+/ {id=$2; next}
    id != "" && /^- Status: / {print id "\t" $3; id=""}
  ' "$PRD_ROOT"/*.md > "$prd_index"
  while IFS=$'\t' read -r requirement state _; do
    matches=$(awk -F '\t' -v id="$requirement" '$1 == id {print $2}' "$prd_index")
    [[ -n "$matches" ]] || { echo "traceability blocked: $requirement missing from PRD" >&2; exit 2; }
    [[ "$(wc -l <<<"$matches" | tr -d ' ')" == 1 && "$matches" == "$state" ]] || {
      echo "traceability blocked: $requirement PRD/TSV state mismatch" >&2; exit 2;
    }
  done < <(tail -n +2 "$TRACE")
fi
count=$(awk 'END {print NR-1}' "$TRACE")
echo "traceability gate passed: $count requirements"
