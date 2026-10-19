# Security Policy

## Reporting a vulnerability

Please use the repository's GitHub **Report a vulnerability** flow so details
remain private until a fix is available. Do not open a public issue containing
credentials, exploit details, approval receipts, or sensitive logs.

Include the affected version or commit, reproduction conditions, impact, and
the smallest safe proof of concept. Remove secrets and personal data.

## Scope

Reports about policy weakening, approval bypass, secret-path access,
single-writer violations, generated-output ownership, or evidence tampering are
in scope. Provider service vulnerabilities should be reported to the relevant
provider unless this repository's adapter introduces the issue.

This project does not promise a response SLA. Until a report is resolved,
disable the affected adapter or gate and avoid production use of that path.
