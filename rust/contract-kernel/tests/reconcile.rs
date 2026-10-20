use harness_contract_kernel::{
    CONTRACT_VERSION, EnforcementStatus, ProviderObservation, ReconcileRequest, ReconcileStatus,
    reconcile,
};

fn request(status: EnforcementStatus) -> ReconcileRequest {
    ReconcileRequest {
        contract_version: CONTRACT_VERSION,
        desired_digest: "desired-1".into(),
        providers: vec!["codex".into()],
        observations: vec![ProviderObservation {
            provider: "codex".into(),
            provider_version: "0.162.1".into(),
            desired_digest: "desired-1".into(),
            applied_digest: Some("desired-1".into()),
            observed_digest: Some("desired-1".into()),
            enforcement_status: status,
            evidence_ref: "evidence:probe-1".into(),
        }],
    }
}

#[test]
fn observed_matching_state_is_in_sync_but_non_authoritative() {
    let result = reconcile(&request(EnforcementStatus::Observed));
    assert_eq!(result.status, ReconcileStatus::InSync);
    assert_eq!(result.mode, "shadow");
    assert!(!result.authoritative);
}

#[test]
fn unsupported_and_unobserved_enforcement_are_truthful() {
    assert_eq!(
        reconcile(&request(EnforcementStatus::Unsupported)).status,
        ReconcileStatus::Unenforceable
    );
    assert_eq!(
        reconcile(&request(EnforcementStatus::Unobserved)).status,
        ReconcileStatus::PartiallyEnforced
    );
}

#[test]
fn digest_mismatch_is_drift_and_missing_provider_is_partial() {
    let mut drifted = request(EnforcementStatus::Observed);
    drifted.observations[0].observed_digest = Some("other".into());
    assert_eq!(reconcile(&drifted).status, ReconcileStatus::Drifted);

    let mut missing = request(EnforcementStatus::Observed);
    missing.observations.clear();
    assert_eq!(
        reconcile(&missing).status,
        ReconcileStatus::PartiallyEnforced
    );
}

#[test]
fn malformed_or_unknown_provider_evidence_is_error() {
    let mut unknown = request(EnforcementStatus::Observed);
    unknown.providers[0] = "unknown".into();
    assert_eq!(reconcile(&unknown).status, ReconcileStatus::Error);

    let mut duplicate = request(EnforcementStatus::Observed);
    duplicate
        .observations
        .push(duplicate.observations[0].clone());
    assert_eq!(reconcile(&duplicate).status, ReconcileStatus::Error);
}
