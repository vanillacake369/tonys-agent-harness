use std::io::{self, Read};

use harness_contract_kernel::{DecisionRequest, decide};

fn main() {
    if let Err(error) = run() {
        eprintln!("harness-contract-kernel: {error}");
        std::process::exit(2);
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input)?;
    let request: DecisionRequest = serde_json::from_str(&input)?;
    serde_json::to_writer(io::stdout(), &decide(&request))?;
    println!();
    Ok(())
}
