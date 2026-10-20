use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::path::{Component, Path};

pub const CONTRACT_VERSION: u32 = 2;

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ResourceType {
    Directory,
    Network,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Operation {
    Read,
    Write,
    Execute,
    Delete,
    Connect,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum GrantScope {
    Task,
    Session,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum LeaseEndCondition {
    TaskEnd,
    SessionEnd,
    Expiry,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum GrantState {
    Active,
    Revoked,
    Expired,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(tag = "event", rename_all = "snake_case")]
pub enum GrantEvent {
    Revoke {
        evidence_ref: String,
    },
    ObserveTime {
        now: u64,
        evidence_ref: String,
    },
    TaskEnd {
        task_id: String,
        evidence_ref: String,
    },
    SessionEnd {
        session_id: String,
        evidence_ref: String,
    },
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
pub struct Resource {
    pub resource_type: ResourceType,
    pub canonical_target: String,
    pub operation: Operation,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
pub struct Grant {
    pub grant_id: String,
    pub task_id: String,
    pub session_id: Option<String>,
    pub role: String,
    pub agent: String,
    pub resource_type: ResourceType,
    pub canonical_target: String,
    pub allowed_operations: Vec<Operation>,
    pub scope: GrantScope,
    pub expires_at: u64,
    pub end_condition: LeaseEndCondition,
    pub state: GrantState,
    pub termination_evidence: Option<String>,
    pub approval_identity: String,
    pub evidence_ref: String,
    pub policy_revision: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum EnforcementStatus {
    Observed,
    Unobserved,
    Unsupported,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
pub struct EnforcementObservation {
    pub status: EnforcementStatus,
    pub provider: String,
    pub provider_version: String,
    pub evidence_ref: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
pub struct ProviderObservation {
    pub provider: String,
    pub provider_version: String,
    pub desired_digest: String,
    pub applied_digest: Option<String>,
    pub observed_digest: Option<String>,
    pub enforcement_status: EnforcementStatus,
    pub evidence_ref: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
pub struct ReconcileRequest {
    pub contract_version: u32,
    pub desired_digest: String,
    pub providers: Vec<String>,
    pub observations: Vec<ProviderObservation>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum ReconcileStatus {
    InSync,
    Drifted,
    PartiallyEnforced,
    Unenforceable,
    Error,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
pub struct ReconcileResult {
    pub contract_version: u32,
    pub mode: String,
    pub authoritative: bool,
    pub status: ReconcileStatus,
    pub reason_code: String,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
pub struct DecisionRequest {
    pub contract_version: u32,
    pub request_id: String,
    pub task_id: String,
    pub session_id: Option<String>,
    pub role: String,
    pub agent: String,
    pub provider: String,
    pub policy_revision: String,
    pub now: u64,
    pub resource: Resource,
    pub secret_access: bool,
    pub external_mutation: bool,
    pub provider_can_pause: bool,
    pub enforcement: EnforcementObservation,
    pub grants: Vec<Grant>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum DecisionKind {
    Allow,
    Ask,
    Deny,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq, Serialize)]
pub struct Decision {
    pub contract_version: u32,
    pub mode: String,
    pub authoritative: bool,
    pub policy_revision: String,
    pub decision: DecisionKind,
    pub reason_code: String,
    pub grant_id: Option<String>,
}

fn decision(
    request: &DecisionRequest,
    kind: DecisionKind,
    reason_code: &str,
    grant_id: Option<String>,
) -> Decision {
    Decision {
        contract_version: CONTRACT_VERSION,
        mode: "shadow".into(),
        authoritative: false,
        policy_revision: request.policy_revision.clone(),
        decision: kind,
        reason_code: reason_code.into(),
        grant_id,
    }
}

pub fn unsupported_contract_decision(policy_revision: &str) -> Decision {
    Decision {
        contract_version: CONTRACT_VERSION,
        mode: "shadow".into(),
        authoritative: false,
        policy_revision: policy_revision.into(),
        decision: DecisionKind::Deny,
        reason_code: "unsupported_contract_version".into(),
        grant_id: None,
    }
}

fn unavailable(request: &DecisionRequest, reason_code: &str) -> Decision {
    if request.provider_can_pause {
        decision(request, DecisionKind::Ask, reason_code, None)
    } else {
        decision(request, DecisionKind::Deny, reason_code, None)
    }
}

fn nonempty(value: &str) -> bool {
    !value.trim().is_empty()
}

fn known_provider(provider: &str) -> bool {
    matches!(provider, "codex" | "claude" | "gemini" | "kiro")
}

fn reconciliation(status: ReconcileStatus, reason_code: &str) -> ReconcileResult {
    ReconcileResult {
        contract_version: CONTRACT_VERSION,
        mode: "shadow".into(),
        authoritative: false,
        status,
        reason_code: reason_code.into(),
    }
}

pub fn reconcile(request: &ReconcileRequest) -> ReconcileResult {
    if request.contract_version != CONTRACT_VERSION
        || !nonempty(&request.desired_digest)
        || request.providers.is_empty()
        || request
            .providers
            .iter()
            .any(|provider| !known_provider(provider))
    {
        return reconciliation(ReconcileStatus::Error, "invalid_reconcile_request");
    }
    let selected: BTreeSet<_> = request.providers.iter().collect();
    if selected.len() != request.providers.len() {
        return reconciliation(ReconcileStatus::Error, "duplicate_provider");
    }

    let mut observed = BTreeSet::new();
    for observation in &request.observations {
        if !selected.contains(&observation.provider)
            || !observed.insert(&observation.provider)
            || !nonempty(&observation.provider_version)
            || !nonempty(&observation.evidence_ref)
            || observation.desired_digest != request.desired_digest
        {
            return reconciliation(ReconcileStatus::Error, "invalid_provider_observation");
        }
    }
    if request
        .observations
        .iter()
        .any(|observation| observation.enforcement_status == EnforcementStatus::Unsupported)
    {
        return reconciliation(ReconcileStatus::Unenforceable, "provider_unsupported");
    }
    if observed.len() != selected.len()
        || request
            .observations
            .iter()
            .any(|observation| observation.enforcement_status == EnforcementStatus::Unobserved)
    {
        return reconciliation(
            ReconcileStatus::PartiallyEnforced,
            "enforcement_not_fully_observed",
        );
    }
    if request.observations.iter().any(|observation| {
        observation.applied_digest.as_deref() != Some(request.desired_digest.as_str())
            || observation.observed_digest.as_deref() != Some(request.desired_digest.as_str())
    }) {
        return reconciliation(ReconcileStatus::Drifted, "provider_state_drifted");
    }
    reconciliation(ReconcileStatus::InSync, "provider_state_observed")
}

fn valid_directory_target(value: &str) -> bool {
    let path = Path::new(value);
    path.is_absolute()
        && path
            .components()
            .all(|component| !matches!(component, Component::ParentDir | Component::CurDir))
}

fn valid_network_target(value: &str) -> bool {
    let Some((scheme, authority)) = value.split_once("://") else {
        return false;
    };
    if !matches!(scheme, "http" | "https") || authority.contains(['/', '?', '#', '@']) {
        return false;
    }
    let Some((host, port_text)) = authority.rsplit_once(':') else {
        return false;
    };
    let host_is_valid = nonempty(host)
        && !host.starts_with(['-', '.'])
        && !host.ends_with(['-', '.'])
        && host.split('.').all(|label| {
            nonempty(label)
                && !label.starts_with('-')
                && !label.ends_with('-')
                && label
                    .chars()
                    .all(|character| character.is_ascii_alphanumeric() || character == '-')
        });
    let port_is_valid = port_text.parse::<u16>().is_ok_and(|port| port != 0);
    host_is_valid && port_is_valid
}

fn valid_resource(resource: &Resource) -> bool {
    match resource.resource_type {
        ResourceType::Directory => {
            resource.operation != Operation::Connect
                && valid_directory_target(&resource.canonical_target)
        }
        ResourceType::Network => {
            resource.operation == Operation::Connect
                && valid_network_target(&resource.canonical_target)
        }
    }
}

fn valid_grant(grant: &Grant, policy_revision: &str) -> bool {
    nonempty(&grant.grant_id)
        && nonempty(&grant.task_id)
        && nonempty(&grant.role)
        && nonempty(&grant.agent)
        && nonempty(&grant.approval_identity)
        && nonempty(&grant.evidence_ref)
        && grant.policy_revision == policy_revision
        && match grant.state {
            GrantState::Active => grant.termination_evidence.is_none(),
            GrantState::Revoked | GrantState::Expired => {
                grant.termination_evidence.as_deref().is_some_and(nonempty)
            }
        }
        && !grant.allowed_operations.is_empty()
        && grant
            .allowed_operations
            .iter()
            .all(|operation| match grant.resource_type {
                ResourceType::Directory => operation != &Operation::Connect,
                ResourceType::Network => operation == &Operation::Connect,
            })
        && match grant.scope {
            GrantScope::Task => matches!(
                grant.end_condition,
                LeaseEndCondition::TaskEnd | LeaseEndCondition::Expiry
            ),
            GrantScope::Session => {
                grant.session_id.is_some()
                    && matches!(
                        grant.end_condition,
                        LeaseEndCondition::SessionEnd | LeaseEndCondition::Expiry
                    )
            }
        }
        && valid_resource(&Resource {
            resource_type: grant.resource_type.clone(),
            canonical_target: grant.canonical_target.clone(),
            operation: grant.allowed_operations[0].clone(),
        })
}

pub fn transition_grant(grant: &mut Grant, event: GrantEvent) -> Result<(), &'static str> {
    if grant.state != GrantState::Active {
        return Err("grant_state_is_terminal");
    }
    match event {
        GrantEvent::Revoke { evidence_ref } => {
            if !nonempty(&evidence_ref) {
                return Err("termination_evidence_required");
            }
            grant.state = GrantState::Revoked;
            grant.termination_evidence = Some(evidence_ref);
        }
        GrantEvent::ObserveTime { now, evidence_ref } => {
            if now < grant.expires_at {
                return Ok(());
            }
            expire_grant(grant, evidence_ref)?;
        }
        GrantEvent::TaskEnd {
            task_id,
            evidence_ref,
        } => {
            if grant.scope != GrantScope::Task
                || grant.end_condition != LeaseEndCondition::TaskEnd
                || grant.task_id != task_id
            {
                return Err("task_end_does_not_match_grant");
            }
            expire_grant(grant, evidence_ref)?;
        }
        GrantEvent::SessionEnd {
            session_id,
            evidence_ref,
        } => {
            if grant.scope != GrantScope::Session
                || grant.end_condition != LeaseEndCondition::SessionEnd
                || grant.session_id.as_deref() != Some(session_id.as_str())
            {
                return Err("session_end_does_not_match_grant");
            }
            expire_grant(grant, evidence_ref)?;
        }
    }
    Ok(())
}

fn expire_grant(grant: &mut Grant, evidence_ref: String) -> Result<(), &'static str> {
    if !nonempty(&evidence_ref) {
        return Err("termination_evidence_required");
    }
    grant.state = GrantState::Expired;
    grant.termination_evidence = Some(evidence_ref);
    Ok(())
}

fn resource_matches(grant: &Grant, requested: &Resource) -> bool {
    if grant.resource_type != requested.resource_type {
        return false;
    }
    match requested.resource_type {
        ResourceType::Directory => {
            Path::new(&requested.canonical_target).starts_with(Path::new(&grant.canonical_target))
        }
        ResourceType::Network => grant.canonical_target == requested.canonical_target,
    }
}

fn identity_matches(grant: &Grant, request: &DecisionRequest) -> bool {
    grant.task_id == request.task_id
        && grant.role == request.role
        && grant.agent == request.agent
        && match grant.scope {
            GrantScope::Task => true,
            GrantScope::Session => grant.session_id == request.session_id,
        }
}

pub fn decide(request: &DecisionRequest) -> Decision {
    if request.contract_version != CONTRACT_VERSION {
        return decision(
            request,
            DecisionKind::Deny,
            "unsupported_contract_version",
            None,
        );
    }
    if !nonempty(&request.request_id)
        || !nonempty(&request.task_id)
        || !nonempty(&request.role)
        || !nonempty(&request.agent)
        || !nonempty(&request.provider)
        || !nonempty(&request.policy_revision)
        || !valid_resource(&request.resource)
    {
        return decision(request, DecisionKind::Deny, "invalid_request", None);
    }
    if request.secret_access {
        return decision(request, DecisionKind::Deny, "secret_access_forbidden", None);
    }
    if request.external_mutation {
        return decision(
            request,
            DecisionKind::Deny,
            "external_mutation_requires_operation_approval",
            None,
        );
    }
    if !known_provider(&request.provider)
        || request.enforcement.provider != request.provider
        || !nonempty(&request.enforcement.provider_version)
        || !nonempty(&request.enforcement.evidence_ref)
    {
        return decision(
            request,
            DecisionKind::Deny,
            "invalid_enforcement_observation",
            None,
        );
    }
    let grant = request.grants.iter().find(|grant| {
        valid_grant(grant, &request.policy_revision)
            && grant.state == GrantState::Active
            && grant.expires_at > request.now
            && identity_matches(grant, request)
            && resource_matches(grant, &request.resource)
            && grant
                .allowed_operations
                .iter()
                .any(|operation| operation == &request.resource.operation)
    });

    let Some(grant) = grant else {
        return unavailable(request, "matching_active_grant_required");
    };
    if request.enforcement.status != EnforcementStatus::Observed {
        return unavailable(request, "enforcement_not_observed");
    }

    decision(
        request,
        DecisionKind::Allow,
        "active_grant_observed",
        Some(grant.grant_id.clone()),
    )
}
