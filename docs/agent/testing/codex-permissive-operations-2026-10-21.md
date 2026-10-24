# Test and Delivery Workflow: Codex Default-Allow Guardrail

> Superseded by [Default-Allow Operations v1](../spec/default-allow-operations-v1.md).
> The authoritative Pre/Mid/Post workflow and acceptance criteria live there.

## Pre: specification and research

1. Inventory installed Codex/client versions without reading credentials or
   contacting mutable resources.
2. Freeze the v1 command matrix and stable reason IDs.
3. Add an allow counterexample for every deny rule.
4. Record aliases, expansions, scripts, SDKs, HTTP, and unknown clients as
   accepted false negatives; never add a fail-closed catch-all.
5. Confirm Codex-only selection and the static sandbox projection.

Exit: PRD and ADR agree on default allow, deny scope, residual risk, isolation,
and rollback.

## Mid: implementation and verification

1. Write table tests first, one command family at a time.
2. Implement the smallest deterministic rule and stable reason; avoid broad
   substring regexes.
3. Integrate it in the shared runtime gate; only Codex enables the profile.
4. Render and structurally validate the Codex filesystem/network profile.
5. Run focused tests per family, then Python, Bats, Nix, and repository checks.
6. Run native probes for workspace write, sibling read, secret denial, and
   network. Never execute a real DB write, cluster mutation, push, or removal.

Negative fixtures cover destructive Git push, SQL/MongoDB/Redis writes,
Docker/Podman existing-resource mutation, Compose up/down, kubectl mutation,
Kustomize-to-kubectl apply, and mutating kubeadm lifecycle commands. Positive
fixtures cover local work, ordinary push, DB reads, container read/build/pull/
create/run/start, kubectl read/create/run, standalone Kustomize build/edit, and
kubeadm inspection/upgrade-plan.

Characterization fixtures (`g=git; $g ...`, aliases, generated SQL, SDK writes,
`curl -X DELETE`) must document their accepted `ALLOW` result.

Exit: enumerated fixtures pass, non-Codex behavior is unchanged, and no claim of
complete external-mutation prevention remains.

## Post: review, commit, rollout, observation

1. Independent review checks wording, provider isolation, false positives,
   disclosed false negatives, tests, and rollback.
2. Keep commits to at most three responsibilities: specification/docs;
   classifier/runtime/tests; Codex adapter/config/tests.
3. Run the post-commit workflow; publish only with explicit authorization.
4. Update `tonys-nix` only after the harness revision is available, then run its
   repository-native Nix checks.
5. Observe denial reason IDs and reported misses without collecting secrets or
   raw sensitive commands. Extend v1 only from concrete evidence and paired
   regression tests.
6. Disable `[codex].permissive_operations` if false positives or profile
   incompatibility impede normal work.

Exit: focused/full checks and downstream consumption pass, residual risks are
in the handoff, and unrelated providers remain unchanged.
