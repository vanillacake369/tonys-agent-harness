use std::io::{self, Read};

use harness_contract_kernel::{
    CONTRACT_VERSION, DecisionRequest, decide, unsupported_contract_decision,
};

fn main() {
    if let Err(error) = run() {
        eprintln!("harness-contract-kernel: {error}");
        std::process::exit(2);
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input)?;
    let value: serde_json::Value = serde_json::from_str(&input)?;
    if value
        .get("contract_version")
        .and_then(serde_json::Value::as_u64)
        != Some(u64::from(CONTRACT_VERSION))
    {
        let policy_revision = value
            .get("policy_revision")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default();
        serde_json::to_writer(
            io::stdout(),
            &unsupported_contract_decision(policy_revision),
        )?;
        println!();
        return Ok(());
    }
    let request: DecisionRequest = serde_json::from_value(value)?;
    serde_json::to_writer(io::stdout(), &decide(&request))?;
    println!();
    Ok(())
}
