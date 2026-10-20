use std::io::Write;
use std::process::{Command, Stdio};

fn run(input: &str) -> std::process::Output {
    let mut child = Command::new(env!("CARGO_BIN_EXE_harness-contract-kernel"))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .expect("spawn contract kernel");
    child
        .stdin
        .take()
        .expect("open stdin")
        .write_all(input.as_bytes())
        .expect("write request");
    child.wait_with_output().expect("read kernel output")
}

#[test]
fn malformed_json_exits_two_without_a_decision() {
    let output = run("{");
    assert_eq!(output.status.code(), Some(2));
    assert!(output.stdout.is_empty());
    assert!(String::from_utf8_lossy(&output.stderr).starts_with("harness-contract-kernel:"));
}

#[test]
fn serialized_decision_is_explicitly_non_authoritative() {
    let request = serde_json::json!({
        "contract_version": 2,
        "request_id": "request-1",
        "task_id": "task-1",
        "session_id": "session-1",
        "role": "implementer",
        "agent": "codex",
        "provider": "codex",
        "policy_revision": "policy-v1",
        "now": 100,
        "resource": {
            "resource_type": "directory",
            "canonical_target": "/workspace/project",
            "operation": "write"
        },
        "secret_access": false,
        "external_mutation": false,
        "provider_can_pause": true,
        "enforcement": {
            "status": "OBSERVED",
            "provider": "codex",
            "provider_version": "0.162.1",
            "evidence_ref": "evidence:probe-1"
        },
        "grants": []
    });
    let output = run(&request.to_string());
    assert!(
        output.status.success(),
        "{}",
        String::from_utf8_lossy(&output.stderr)
    );
    let response: serde_json::Value = serde_json::from_slice(&output.stdout).expect("JSON output");
    assert_eq!(response["mode"], "shadow");
    assert_eq!(response["authoritative"], false);
    assert_eq!(response["decision"], "ASK");
}

#[test]
fn legacy_v1_wire_request_is_rejected_before_grant_schema_parsing() {
    let request = serde_json::json!({
        "contract_version": 1,
        "policy_revision": "policy-v1",
        "grants": [{"revocation_evidence": null}]
    });
    let output = run(&request.to_string());
    assert!(output.status.success());
    let response: serde_json::Value = serde_json::from_slice(&output.stdout).expect("JSON output");
    assert_eq!(response["contract_version"], 2);
    assert_eq!(response["decision"], "DENY");
    assert_eq!(response["reason_code"], "unsupported_contract_version");
    assert_eq!(response["policy_revision"], "policy-v1");
}
