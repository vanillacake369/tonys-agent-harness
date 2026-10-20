use harness_contract_kernel::{DecisionRequest, decide};
use serde_json::Value;

fn merge(target: &mut Value, patch: &Value) {
    if let (Some(target), Some(patch)) = (target.as_object_mut(), patch.as_object()) {
        for (key, value) in patch {
            match target.get_mut(key) {
                Some(target_value) => merge(target_value, value),
                None => {
                    target.insert(key.clone(), value.clone());
                }
            }
        }
    } else {
        *target = patch.clone();
    }
}

#[test]
fn canonical_v2_decisions_match_the_frozen_fixture() {
    let fixture: Value = serde_json::from_str(include_str!(
        "../../../tests/fixtures/contract-kernel/decision-v2.json"
    ))
    .expect("valid differential fixture");
    for case in fixture["cases"].as_array().expect("fixture cases") {
        let mut input = fixture["base"].clone();
        merge(&mut input, &case["patch"]);
        if let Some(grant_patch) = case.get("grant_patch") {
            merge(&mut input["grants"][0], grant_patch);
        }
        let request: DecisionRequest = serde_json::from_value(input).expect("valid request");
        let actual = serde_json::to_value(decide(&request)).expect("serialize decision");
        let expected = &case["expected"];
        for field in ["decision", "reason_code", "grant_id"] {
            assert_eq!(actual[field], expected[field], "{}: {field}", case["name"]);
        }
        assert_eq!(actual["contract_version"], 2);
        assert_eq!(actual["policy_revision"], request.policy_revision);
        assert_eq!(actual["mode"], "shadow");
        assert_eq!(actual["authoritative"], false);
    }
}
