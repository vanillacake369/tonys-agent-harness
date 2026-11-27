#!/usr/bin/env bash
# Static contract and failure-branch fixtures. No DAG node is executed.
set -euo pipefail

root=${HARNESS_ROOT:-$(cd "$(dirname "$0")/.." && pwd -P)}
validator="$root/core/dag-validate.sh"
dag_skill="$root/tests/fixtures/review/capability/dag/dag-review"
manifest="$dag_skill/DAG.yaml"
schema="$dag_skill/dag-contract.schema.json"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

read_json() {
  python3 "$root/core/metadata-validate.py" yaml < "$manifest" > "$fixture/base.json"
}

reject() {
  local label=$1 filter=$2 expected=${3:-}
  jq "$filter" "$fixture/base.json" > "$fixture/$label.yaml"
  if bash "$validator" "$fixture/$label.yaml" "$schema" "$root/tests/fixtures/review" > "$fixture/$label.out" 2>&1; then
    printf 'DAG_NEGATIVE_FAILED=%s\n' "$label" >&2
    exit 1
  fi
  grep -q '^INVALID_DAG:' "$fixture/$label.out"
  if test -n "$expected"; then
    grep -Fq "INVALID_DAG:$expected" "$fixture/$label.out"
  fi
}

bash "$validator" "$manifest" "$schema" "$root/tests/fixtures/review" > "$fixture/valid.out"
grep -q '^DAG_CONTRACT=PASS (review)' "$fixture/valid.out"
read_json
jq -e '.source == "capability/dag/dag-review/SKILL.md"' "$fixture/base.json" >/dev/null

# Production regression caught: a mutating remediation silently skips approval.
reject ungated_remediation \
  '(.nodes[] | select(.id == "remediation")) |= (.approval = "none" | .on_missing_approval = null)' \
  'UNGATED_MUTATION_remediation'
# Production regression caught: an executable side effect loses its named recovery owner.
reject missing_compensation '(.nodes[] | select(.id == "remediation") | .compensation) = null'
# Production regression caught: a node refers to an absent prerequisite.
reject dangling_dependency '(.nodes[] | select(.id == "hypotheses") | .depends_on) = ["ghost"]'
# Production regression caught: a proposed retry creates an executable graph cycle.
reject graph_cycle \
  '(.nodes[] | select(.id == "record") | .on_success) = "hypotheses" |
   (.nodes[] | select(.id == "hypotheses") | .depends_on) += ["record"]' \
  CYCLE
# Production regression caught: an experiment can advance without observable evidence.
reject missing_evidence '(.nodes[] | select(.id == "experiment") | .evidence) = []'
# Production regression caught: denied approval has no explicit terminal outcome.
reject missing_approval_outcome '(.nodes[] | select(.id == "remediation") | .on_missing_approval) = null'
# Production regression caught: a failed experiment is recorded as verified recovery.
reject false_verified_failure '(.nodes[] | select(.id == "experiment") | .on_failure) = "VERIFIED"'
# Production regression caught: a stalled remediation has no declared stop outcome.
reject missing_timeout_outcome 'del(.nodes[] | select(.id == "remediation") | .on_timeout)'
# Production regression caught: an unresolved attempt loses its accountable owner.
reject missing_handoff_owner '.handoff -= ["owner"]'
# Production regression caught: Python considers True equal to integer 1 unless const types are compared.
reject boolean_schema_version '.schema_version = true'
# Production regression caught: a graph ID cannot claim an unrelated research source.
reject wrong_id '.id = "fake"' SOURCE_MAPPING
reject legacy_source '.source = "skills/candidates/dag-review/SKILL.md"' PATTERN_AT_dag_source

schema="$root/core/dag-contract.schema.json"
reject dangling_skip '(.nodes[] | select(.id == "experiment")) |= (.on_skip = "ghost" | .skip_if = "missing")' \
  INVALID_SKIP_experiment
reject incomplete_skip '(.nodes[] | select(.id == "experiment") | .on_skip) = "conclusion"' \
  INCOMPLETE_SKIP_experiment
reject cyclic_skip '(.nodes[] | select(.id == "experiment")) |= (.on_skip = "intake" | .skip_if = "again")' \
  INVALID_SKIP_experiment

printf '%s\n' 'DAG_FIXTURES=PASS (1 positive contract; 15 rejected unsafe or incomplete variants)'
