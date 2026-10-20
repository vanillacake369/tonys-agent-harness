use serde::{Deserialize, Serialize};
use std::path::{Component, Path};

pub const CONTRACT_VERSION: u32 = 1;

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
    Revoke { evidence_ref: String },
    ObserveTime { now: u64 },
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
    pub revocation_evidence: Option<String>,
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
            GrantState::Active | GrantState::Expired => grant.revocation_evidence.is_none(),
            GrantState::Revoked => grant.revocation_evidence.as_deref().is_some_and(nonempty),
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
                return Err("revocation_evidence_required");
            }
            grant.state = GrantState::Revoked;
            grant.revocation_evidence = Some(evidence_ref);
        }
        GrantEvent::ObserveTime { now } => {
            if now >= grant.expires_at {
                grant.state = GrantState::Expired;
            }
        }
    }
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
    if !matches!(
        request.provider.as_str(),
        "codex" | "claude" | "gemini" | "kiro"
    ) || request.enforcement.provider != request.provider
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
