use harness_contract_kernel::{
    CONTRACT_VERSION, DecisionKind, DecisionRequest, EnforcementObservation, EnforcementStatus,
    Grant, GrantEvent, GrantScope, GrantState, LeaseEndCondition, Operation, Resource,
    ResourceType, decide, transition_grant,
};

fn request() -> DecisionRequest {
    DecisionRequest {
        contract_version: CONTRACT_VERSION,
        request_id: "request-1".into(),
        task_id: "task-1".into(),
        session_id: Some("session-1".into()),
        role: "implementer".into(),
        agent: "codex".into(),
        provider: "codex".into(),
        policy_revision: "policy-v1".into(),
        now: 100,
        resource: Resource {
            resource_type: ResourceType::Directory,
            canonical_target: "/workspace/project".into(),
            operation: Operation::Write,
        },
        secret_access: false,
        external_mutation: false,
        provider_can_pause: true,
        enforcement: EnforcementObservation {
            status: EnforcementStatus::Observed,
            provider: "codex".into(),
            provider_version: "0.162.1".into(),
            evidence_ref: "evidence:probe-1".into(),
        },
        grants: vec![Grant {
            grant_id: "grant-1".into(),
            task_id: "task-1".into(),
            session_id: Some("session-1".into()),
            role: "implementer".into(),
            agent: "codex".into(),
            resource_type: ResourceType::Directory,
            canonical_target: "/workspace/project".into(),
            allowed_operations: vec![Operation::Read, Operation::Write],
            scope: GrantScope::Task,
            expires_at: 200,
            end_condition: LeaseEndCondition::TaskEnd,
            state: GrantState::Active,
            revocation_evidence: None,
            approval_identity: "human:owner".into(),
            evidence_ref: "evidence:approval-1".into(),
            policy_revision: "policy-v1".into(),
        }],
    }
}

#[test]
fn matching_active_observed_grant_allows() {
    let result = decide(&request());
    assert_eq!(result.decision, DecisionKind::Allow);
    assert_eq!(result.reason_code, "active_grant_observed");
    assert_eq!(result.grant_id.as_deref(), Some("grant-1"));
    assert_eq!(result.mode, "shadow");
    assert!(!result.authoritative);
}

#[test]
fn directory_grant_contains_descendants_but_not_string_prefix_collisions() {
    let mut descendant = request();
    descendant.resource.canonical_target = "/workspace/project/src/main.rs".into();
    assert_eq!(decide(&descendant).decision, DecisionKind::Allow);

    let mut collision = request();
    collision.resource.canonical_target = "/workspace/project-escape/file".into();
    assert_eq!(decide(&collision).decision, DecisionKind::Ask);
}

#[test]
fn network_grant_matches_only_the_exact_canonical_target() {
    let mut input = request();
    input.resource.resource_type = ResourceType::Network;
    input.resource.canonical_target = "https://api.example.test:443".into();
    input.resource.operation = Operation::Connect;
    input.grants[0].resource_type = ResourceType::Network;
    input.grants[0].canonical_target = "https://api.example.test:443".into();
    input.grants[0].allowed_operations = vec![Operation::Connect];
    assert_eq!(decide(&input).decision, DecisionKind::Allow);

    input.resource.canonical_target = "https://redirect.example.test:443".into();
    assert_eq!(decide(&input).decision, DecisionKind::Ask);
}

#[test]
fn malformed_network_authorities_fail_closed() {
    for target in [
        "https://::443",
        "https://api example.test:443",
        "https://api.example.test:0",
        "ftp://api.example.test:21",
    ] {
        let mut input = request();
        input.resource.resource_type = ResourceType::Network;
        input.resource.canonical_target = target.into();
        input.resource.operation = Operation::Connect;
        assert_eq!(decide(&input).decision, DecisionKind::Deny, "{target}");
    }
}

#[test]
fn invariant_denials_dominate_a_matching_grant() {
    for mutate in ["secret", "external"] {
        let mut input = request();
        if mutate == "secret" {
            input.secret_access = true;
        } else {
            input.external_mutation = true;
        }
        assert_eq!(decide(&input).decision, DecisionKind::Deny);
    }
}

#[test]
fn expired_revoked_or_identity_mismatched_grants_do_not_allow() {
    let mut cases = Vec::new();
    let mut expired = request();
    expired.grants[0].expires_at = expired.now;
    cases.push(expired);
    let mut revoked = request();
    revoked.grants[0].state = GrantState::Revoked;
    cases.push(revoked);
    let mut other_task = request();
    other_task.grants[0].task_id = "task-2".into();
    cases.push(other_task);
    for input in cases {
        assert_eq!(decide(&input).decision, DecisionKind::Ask);
    }
}

#[test]
fn grant_lifecycle_records_revocation_and_expiry_evidence() {
    let mut grant = request().grants.remove(0);
    transition_grant(
        &mut grant,
        GrantEvent::Revoke {
            evidence_ref: "evidence:revoke-1".into(),
        },
    )
    .expect("revoke active grant");
    assert_eq!(grant.state, GrantState::Revoked);
    assert_eq!(
        grant.revocation_evidence.as_deref(),
        Some("evidence:revoke-1")
    );

    let mut expired = request().grants.remove(0);
    transition_grant(&mut expired, GrantEvent::ObserveTime { now: 200 })
        .expect("expire elapsed grant");
    assert_eq!(expired.state, GrantState::Expired);
}

#[test]
fn terminal_grant_state_cannot_be_reactivated_or_rewritten() {
    let mut grant = request().grants.remove(0);
    transition_grant(
        &mut grant,
        GrantEvent::Revoke {
            evidence_ref: "evidence:revoke-1".into(),
        },
    )
    .expect("first revoke");
    assert!(
        transition_grant(
            &mut grant,
            GrantEvent::Revoke {
                evidence_ref: "evidence:revoke-2".into(),
            },
        )
        .is_err()
    );
    assert_eq!(
        grant.revocation_evidence.as_deref(),
        Some("evidence:revoke-1")
    );
}

#[test]
fn task_scope_spans_sessions_but_session_scope_does_not() {
    let mut task_scope = request();
    task_scope.grants[0].session_id = Some("session-2".into());
    assert_eq!(decide(&task_scope).decision, DecisionKind::Allow);

    let mut session_scope = task_scope;
    session_scope.grants[0].scope = GrantScope::Session;
    session_scope.grants[0].end_condition = LeaseEndCondition::SessionEnd;
    assert_eq!(decide(&session_scope).decision, DecisionKind::Ask);
}

#[test]
fn invariant_reason_dominates_invalid_enforcement_evidence() {
    let mut input = request();
    input.secret_access = true;
    input.enforcement.evidence_ref.clear();
    assert_eq!(decide(&input).reason_code, "secret_access_forbidden");
}

#[test]
fn unobserved_enforcement_never_allows() {
    let mut input = request();
    input.enforcement.status = EnforcementStatus::Unobserved;
    assert_eq!(decide(&input).decision, DecisionKind::Ask);
    input.provider_can_pause = false;
    assert_eq!(decide(&input).decision, DecisionKind::Deny);
}

#[test]
fn empty_grant_evidence_and_unknown_provider_fail_closed() {
    let mut empty_evidence = request();
    empty_evidence.grants[0].evidence_ref.clear();
    assert_eq!(decide(&empty_evidence).decision, DecisionKind::Ask);

    let mut unknown_provider = request();
    unknown_provider.provider = "unknown".into();
    unknown_provider.enforcement.provider = "unknown".into();
    assert_eq!(decide(&unknown_provider).decision, DecisionKind::Deny);
}

#[test]
fn invalid_resource_shapes_fail_closed() {
    let mut relative = request();
    relative.resource.canonical_target = "relative/path".into();
    assert_eq!(decide(&relative).decision, DecisionKind::Deny);

    let mut network = request();
    network.resource.resource_type = ResourceType::Network;
    network.resource.canonical_target = "https://api.example.test".into();
    network.resource.operation = Operation::Connect;
    assert_eq!(decide(&network).decision, DecisionKind::Deny);
}

#[test]
fn unsupported_contract_version_denies() {
    let mut input = request();
    input.contract_version = 2;
    let result = decide(&input);
    assert_eq!(result.decision, DecisionKind::Deny);
    assert_eq!(result.reason_code, "unsupported_contract_version");
}
