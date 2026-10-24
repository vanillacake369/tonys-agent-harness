"""Provider-neutral default-allow command policy."""
from __future__ import annotations
from dataclasses import dataclass
from pathlib import Path
import re
import shlex

PROFILE = "default-allow-operations-v1"
SUPPORTED_PROVIDERS = frozenset({"codex", "claude", "gemini", "kiro"})

@dataclass(frozen=True)
class Decision:
    decision: str
    family: str
    reason_code: str

ALLOW = Decision("ALLOW", "unclassified", "default_allow")

def deny(family: str, reason: str) -> Decision:
    return Decision("DENY", family, reason)

def _segments(command: str) -> list[list[str]] | None:
    try:
        lexer = shlex.shlex(command.replace("\n", ";"), posix=True, punctuation_chars=";&|<>")
        lexer.whitespace_split = True
        tokens = list(lexer)
    except ValueError:
        return None
    result: list[list[str]] = [[]]
    for token in tokens:
        if token in {";", "&", "&&", "||", "|"}:
            result.append([])
        else:
            result[-1].append(token)
    return result

def _exe(tokens: list[str]) -> tuple[str, list[str]]:
    for index, token in enumerate(tokens):
        name = Path(token).name.lower()
        if name in {"env", "command", "sudo"} or ("=" in token and not token.startswith("=")):
            continue
        return name, tokens[index + 1:]
    return "", []

def _has_word(text: str, words: set[str]) -> bool:
    return any(re.search(rf"\b{re.escape(word)}\b", text, re.I) for word in words)

def _subcommand(args: list[str], options_with_values: set[str]) -> tuple[str, int]:
    index = 0
    while index < len(args):
        token = args[index]
        option = token.split("=", 1)[0]
        if token.startswith("-"):
            index += 2 if option in options_with_values and "=" not in token else 1
            continue
        return token, index
    return "", len(args)

def _git(args: list[str]) -> Decision:
    command, index = _subcommand(args, {"-C", "-c", "--git-dir", "--work-tree", "--namespace"})
    if command != "push": return ALLOW
    push_args = args[index + 1:]
    if any(arg in {"--force", "-f", "--mirror", "--delete", "--prune"} or arg.startswith("--force-with-lease") for arg in push_args):
        return deny("git", "git_destructive_push")
    refs = [arg for arg in push_args if not arg.startswith("-")]
    if any(arg.startswith(("+", ":", "-")) or arg.endswith(":") for arg in refs):
        return deny("git", "git_destructive_refspec")
    return ALLOW

def _database(exe: str, args: list[str], raw: str) -> Decision:
    if exe in {"psql", "mysql", "mariadb", "sqlite3", "sqlcmd"}:
        if any(arg in {"-f", "--file", "-i", ".read", "source", "<", "<<"} or arg.startswith("-f") or arg.startswith("-i") or arg.startswith("--file=") for arg in args):
            return deny("database", "database_unclassified_input")
        sql = " ".join(args)
        words = {"insert", "update", "delete", "merge", "replace", "upsert", "create", "alter",
                 "drop", "truncate", "grant", "revoke", "call", "exec", "execute", "vacuum", "reindex"}
        if _has_word(sql, words) or re.search(r"\bcopy\b.*\bfrom\b|\bload\s+data\b", sql, re.I):
            return deny("database", "database_mutation")
        if re.search(r"\b(migrate|migration|db:migrate|prisma)\b", raw, re.I):
            return deny("database", "database_migration")
    if exe in {"mongosh", "mongo"} and re.search(
        r"\.(insert(?:one|many)?|update(?:one|many)?|replaceone|delete(?:one|many)?|bulkwrite|drop|renamecollection|createindex|dropindex|shutdownserver)\s*\(", raw, re.I):
        return deny("mongodb", "mongodb_mutation")
    if exe == "redis-cli":
        command = next((arg.upper() for arg in args if not arg.startswith("-")), "")
        if command in {"SET", "MSET", "DEL", "UNLINK", "EXPIRE", "PEXPIRE", "RENAME", "LPUSH", "RPUSH", "SADD", "ZADD", "HSET", "XADD", "FLUSHDB", "FLUSHALL", "MIGRATE", "RESTORE"}:
            return deny("redis", "redis_mutation")
        if " ".join(args).upper().startswith(("CONFIG SET", "ACL SETUSER")):
            return deny("redis", "redis_admin_mutation")
    return ALLOW

def _container(exe: str, args: list[str]) -> Decision:
    if exe not in {"docker", "podman"} or not args: return ALLOW
    args = [arg.lower() for arg in args]
    command, index = _subcommand(args, {"--context", "--host", "-h", "--config", "--log-level", "--connection"})
    if command == "compose":
        tail = args[index + 1:]
        if not tail: return ALLOW
        compose_command, compose_index = _subcommand(tail, {"-f", "--file", "--project-name", "-p", "--profile", "--env-file"})
        compose_args = tail[compose_index + 1:]
        if compose_command == "up" and any(flag in {"--force-recreate", "--remove-orphans"} or flag.startswith("--scale") for flag in compose_args):
            return deny("compose", "compose_recreate_or_scale")
        if compose_command in {"down", "stop", "restart", "rm", "kill", "exec", "push"}:
            return deny("compose", "compose_existing_resource_mutation")
        return ALLOW
    if command in {"rm", "rmi", "stop", "kill", "restart", "pause", "unpause", "rename", "update", "exec", "commit", "push", "prune"}:
        return deny("container", "container_existing_resource_mutation")
    if command in {"container", "image", "volume", "network", "system"} and index + 1 < len(args) and args[index + 1] in {"rm", "remove", "prune", "stop", "kill", "exec", "push", "update"}:
        return deny("container", "container_resource_removal")
    if command == "cp" and len(args) > index + 2 and ":" in args[-1]:
        return deny("container", "container_inbound_copy")
    if len(args) > 1 and args[1] in {"rm", "remove", "prune"}:
        return deny("container", "container_resource_removal")
    return ALLOW

def _kubernetes(exe: str, args: list[str]) -> Decision:
    args = [arg.lower() for arg in args]
    if exe == "kubectl" and args:
        verb, index = _subcommand(args, {"--context", "--namespace", "-n", "--kubeconfig", "--cluster", "--user", "--server"})
        if verb == "create" and any(word in args for word in {"secret", "token"}):
            return deny("kubernetes", "kubernetes_secret_or_token_create")
        if verb in {"apply", "patch", "edit", "replace", "delete", "scale", "set", "annotate", "label", "taint", "cordon", "uncordon", "drain", "autoscale"}:
            return deny("kubernetes", "kubernetes_resource_mutation")
        if verb == "rollout" and any(word in args for word in {"restart", "undo"}):
            return deny("kubernetes", "kubernetes_rollout_mutation")
        if verb in {"attach", "exec", "debug", "cp"}:
            return deny("kubernetes", "kubernetes_interactive_mutation")
    if exe == "kubeadm" and args:
        command, index = _subcommand(args, {"--config", "--kubeconfig", "--rootfs"})
        joined = " ".join(args[index:])
        if command in {"init", "join", "reset"} or joined.startswith(("upgrade apply", "upgrade node", "certs renew", "token create", "token delete")):
            return deny("kubeadm", "kubeadm_cluster_mutation")
        if command == "phase" and "--dry-run" not in args:
            return deny("kubeadm", "kubeadm_cluster_mutation")
    return ALLOW

def _infra(exe: str, args: list[str]) -> Decision:
    args = [arg.lower() for arg in args]
    if exe in {"terraform", "tofu"} and args:
        command, index = _subcommand(args, {"-chdir"})
        joined = " ".join(args[index:])
        if command == "destroy" or joined.startswith(("state rm", "state mv")):
            return deny("infrastructure", "infrastructure_explicit_removal")
    if exe == "pulumi" and args:
        command, _ = _subcommand(args, {"--cwd", "-c", "--stack", "-s", "--color"})
        if command in {"destroy", "state"}: return deny("infrastructure", "infrastructure_explicit_removal")
    if exe == "helm" and args:
        command, _ = _subcommand(args, {"--namespace", "-n", "--kube-context", "--kubeconfig", "--repository-config"})
        if command in {"uninstall", "rollback"}: return deny("infrastructure", "infrastructure_explicit_removal")
        if command == "upgrade" and "--install" not in args: return deny("infrastructure", "infrastructure_existing_resource_update")
    return ALLOW

def classify(command: str) -> Decision:
    if re.search(r"\|\s*(?:[^|;]+/)?(?:psql|mysql|mariadb|sqlite3|sqlcmd)\b", command, re.I):
        return deny("database", "database_unclassified_input")
    segments = _segments(command)
    if segments is None: return ALLOW
    for segment in segments:
        exe, args = _exe(segment)
        if exe == "rm":
            flags = [arg for arg in args if arg.startswith("-")]
            recursive = any("r" in flag.lower().lstrip("-") or flag == "--recursive" for flag in flags)
            force = any("f" in flag.lower().lstrip("-") or flag == "--force" for flag in flags)
            targets = [arg for arg in args if not arg.startswith("-")]
            if recursive and force and any(target in {"/", "~", "$HOME", "${HOME}"} for target in targets):
                return deny("filesystem", "catastrophic_filesystem_destruction")
        checks = (_git(args) if exe == "git" else ALLOW, _database(exe, args, " ".join(segment)), _container(exe, args), _kubernetes(exe, args), _infra(exe, args))
        for decision in checks:
            if decision.decision == "DENY": return decision
    return ALLOW
