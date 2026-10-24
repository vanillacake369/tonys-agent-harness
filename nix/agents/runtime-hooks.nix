# 활성 agent provider가 공유해서 쓰는 hook script를 배치한다.
{lib, pkgs, ...}: let
  policyPython = pkgs.python3.withPackages (ps: [ps.tomli-w]);
in {
  home.file = {
    ".config/agents/governance/python3".source = lib.getExe policyPython;
    ".config/agents/hooks/agent-notify.sh".source = ./providers/claude/hooks/agent-notify.sh;
    ".config/agents/hooks/agent-notify-open.sh".source = ./providers/claude/hooks/agent-notify-open.sh;
    ".config/agents/orchestrator/route.sh".source = ../../runtime/orchestrator/route.sh;
    ".config/agents/orchestrator/traceability-gate.sh".source = ../../runtime/orchestrator/traceability-gate.sh;
    ".config/agents/orchestrator/decision.sh".source = ../../runtime/orchestrator/decision.sh;
    ".config/agents/orchestrator/telemetry.sh".source = ../../runtime/orchestrator/telemetry.sh;
    ".config/agents/orchestrator/execution-plan.sh".source = ../../runtime/orchestrator/execution-plan.sh;
    ".config/agents/orchestrator/execution-authorize.sh".source = ../../runtime/orchestrator/execution-authorize.sh;
    ".config/agents/orchestrator/telemetry-summary.sh".source = ../../runtime/orchestrator/telemetry-summary.sh;
    ".config/agents/governance/evidence-gate.sh".source = ../../runtime/governance/evidence-gate.sh;
    ".config/agents/governance/retry-budget.sh".source = ../../runtime/governance/retry-budget.sh;
    ".config/agents/governance/git-lifecycle-gate.sh".source = ../../runtime/governance/git-lifecycle-gate.sh;
    ".config/agents/governance/external-operation.sh".source = ../../runtime/governance/external-operation.sh;
    ".config/agents/governance/provider-instructions-gate.sh".source = ../../runtime/governance/provider-instructions-gate.sh;
    ".config/agents/governance/memory-lifecycle.sh".source = ../../runtime/governance/memory-lifecycle.sh;
    ".config/agents/governance/configuration-gate.sh".source = ../../runtime/governance/configuration-gate.sh;
    ".config/agents/governance/path-guard.sh".source = ../../runtime/governance/path-guard.sh;
    ".config/agents/governance/mcp-allowlist-gate.sh".source = ../../runtime/governance/mcp-allowlist-gate.sh;
    ".config/agents/governance/mcp-hook.sh".source = ../../runtime/governance/mcp-hook.sh;
    ".config/agents/governance/completion-gate.sh".source = ../../runtime/governance/completion-gate.sh;
    ".config/agents/governance/record-verification.py".source = ../../runtime/governance/record-verification.py;
    ".config/agents/governance/task-lifecycle.py".source = ../../runtime/governance/task-lifecycle.py;
    ".config/agents/governance/approval-gate.sh".source = ../../runtime/governance/approval-gate.sh;
    ".config/agents/governance/receipt-signature-gate.sh".source = ../../runtime/governance/receipt-signature-gate.sh;
    ".config/agents/governance/provider-native-conformance.sh".source = ../../runtime/governance/provider-native-conformance.sh;
    ".config/agents/governance/test-review-gate.sh".source = ../../runtime/governance/test-review-gate.sh;
    ".config/agents/governance/retry-hook.sh".source = ../../runtime/governance/retry-hook.sh;
    ".config/agents/governance/kiro-stop.sh".source = ../../runtime/governance/kiro-stop.sh;
    ".config/agents/governance/pre-tool-gate.sh".source = ../../runtime/governance/pre-tool-gate.sh;
    ".config/agents/governance/execution-gate.py".source = ../../runtime/governance/execution-gate.py;
    ".config/agents/governance/operation_policy.py".source = ../../runtime/governance/operation_policy.py;
    ".config/agents/governance/policy-feedback.py".source = ../../runtime/governance/policy-feedback.py;
    ".config/agents/governance/policy-preflight.py".source = ../../runtime/governance/policy-preflight.py;
    ".config/agents/governance/managed-config-sync.py".source = ../../runtime/governance/managed-config-sync.py;
  };
}
