# Approval contract

Provider-native permission checks and OS permissions are the execution boundary.
Agent instructions and static validators cannot grant authority. Start with bounded read-only observations.
For network, credentials, production mutation, destructive or billable operations, obtain explicit scope approval.
Delegation does not extend authority. If approval is absent, return NEEDS_APPROVAL without executing.
