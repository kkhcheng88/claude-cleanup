#!/usr/bin/env python3
"""Sandboxed self-test for claude_cleanup.py.

Builds a throwaway HOME with a representative ~/.claude tree, runs the real
cleanup non-interactively against it, and asserts that only whitelisted paths
moved, protected data survived, telemetry was untouched, and no BOM appeared.
"""
from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
SCRIPT = HERE.parent / "scripts" / "claude_cleanup.py"


def build_sandbox(root: pathlib.Path):
    home, local, roaming = root / "home", root / "local", root / "roaming"
    claude = home / ".claude"
    for name in ("cache", "telemetry", "projects", "skills/demo", "hooks", "backups",
                 "tmp", "paste-cache", "daemon", "bin", "file-history", "debug"):
        (claude / name).mkdir(parents=True, exist_ok=True)
    (claude / "stats-cache.json").write_text("{}", encoding="utf-8")
    (claude / "history.jsonl").write_text('{"x":1}\n', encoding="utf-8")
    (claude / "CLAUDE.md").write_text("# instructions\n", encoding="utf-8")
    (claude / "projects" / "p.jsonl").write_text("{}\n", encoding="utf-8")
    (claude / "skills" / "demo" / "SKILL.md").write_text("---\nname: demo\ndescription: d\n---\n", encoding="utf-8")
    (claude / "hooks" / "h.ps1").write_text("Write-Output hi\n", encoding="utf-8")
    (claude / "backups" / ".claude.json.backup.111").write_text(
        json.dumps({"userID": "old", "machineID": "oldm", "oauthAccount": {"a": 1}}), encoding="utf-8")
    (claude / ".credentials.json").write_text('{"token":"secret"}', encoding="utf-8")
    (claude / "tmp" / "junk.txt").write_text("junk", encoding="utf-8")
    (claude / "paste-cache" / "p.txt").write_text("paste", encoding="utf-8")
    (claude / "daemon" / "control.key").write_text("live-runtime", encoding="utf-8")
    (claude / "bin" / "worker.ps1").write_text("Write-Output worker\n", encoding="utf-8")
    (claude / "settings.json").write_text(json.dumps({
        "env": {"CLAUDE_WORKER": "deepseek"},
        "hooks": {"SessionStart": [{"matcher": "x", "hooks": []}]},
        "enabledPlugins": {"a@b": True},
    }, indent=2), encoding="utf-8")
    (home / ".claude.json").write_text(json.dumps({
        "userID": "old-user-id", "machineID": "old-machine-id",
        "oauthAccount": {"emailAddress": "x@y.z"}, "anonymousId": "anon", "numStartups": 5,
        "projects": {"C:/projects/VLOS": {"history": [1]}, "c:/projects/VLOS": {"history": [2]}},
    }, indent=2), encoding="utf-8")
    (local / "Claude" / "Logs").mkdir(parents=True, exist_ok=True)
    (local / "Claude" / "Logs" / "main.log").write_text("log", encoding="utf-8")
    (roaming / "Claude").mkdir(parents=True, exist_ok=True)
    (roaming / "Claude" / "config.json").write_text("{}", encoding="utf-8")
    return home, local, roaming, claude


def main() -> int:
    root = pathlib.Path(tempfile.mkdtemp(prefix="claude-cleanup-selftest-"))
    home, local, roaming, claude = build_sandbox(root)
    env = dict(os.environ)
    env.update({"USERPROFILE": str(home), "HOME": str(home),
                "LOCALAPPDATA": str(local), "APPDATA": str(roaming)})
    for key in ("CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"):
        env.pop(key, None)

    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--confirm", "CONFIRM", "--rotate-identity",
         "--delete-credentials", "--desktop-mode", "1", "--simple-mode", "1",
         "--extra-leftovers", "--backup-mode", "targeted"],
        capture_output=True, text=True, env=env, errors="replace")
    print(result.stdout)
    if result.stderr:
        print("STDERR:", result.stderr)

    checks = []
    def check(name, ok):
        checks.append((name, bool(ok)))

    check("exit code 0", result.returncode == 0)
    for name in ("projects", "skills", "hooks", "history.jsonl", "settings.json", "backups",
                 "CLAUDE.md", "file-history", "debug", "daemon", "bin"):
        check("protected intact: " + name, (claude / name).exists())
    for name in ("cache", "telemetry", "stats-cache.json", "tmp", "paste-cache", ".credentials.json"):
        check("removed: " + name, not (claude / name).exists())
    check("desktop data removed", not (local / "Claude").exists() and not (roaming / "Claude").exists())

    batches = sorted((home / ".Trash").glob("claude-cleanup-*")) if (home / ".Trash").is_dir() else []
    check("exactly one trash batch", len(batches) == 1)
    trashed = {p.name for p in batches[0].iterdir()} if batches else set()
    for name in ("cache", "telemetry", "stats-cache.json", "tmp", "paste-cache", ".credentials.json"):
        check("in trash: " + name, any(n.endswith("-" + name) for n in trashed))

    backups = sorted((home / "ClaudeBackups").glob("claude-cleanup-*")) if (home / "ClaudeBackups").is_dir() else []
    check("exactly one backup", len(backups) == 1)
    if backups:
        payload = backups[0] / "files"
        check("backup copied identity", (payload / ".claude.json").is_file())
        check("backup copied settings", (payload / ".claude" / "settings.json").is_file())
        check("backup copied credentials", (payload / ".claude" / ".credentials.json").is_file())

    ident = json.loads((home / ".claude.json").read_text(encoding="utf-8"))
    check("userID rotated (64 hex)", isinstance(ident.get("userID"), str) and len(ident["userID"]) == 64 and ident["userID"] != "old-user-id")
    check("machineID rotated (64 hex)", isinstance(ident.get("machineID"), str) and len(ident["machineID"]) == 64 and ident["machineID"] != "old-machine-id")
    check("oauthAccount removed", "oauthAccount" not in ident)
    check("anonymousId removed", "anonymousId" not in ident)
    check("case-variant projects kept", "C:/projects/VLOS" in ident.get("projects", {}) and "c:/projects/VLOS" in ident.get("projects", {}))
    check("unrelated key kept", ident.get("numStartups") == 5)

    raw = (claude / "settings.json").read_bytes()
    check("settings.json has no BOM", not raw.startswith(b"\xef\xbb\xbf"))
    settings = json.loads(raw.decode("utf-8"))
    check("CLAUDE_CODE_SIMPLE set", settings["env"].get("CLAUDE_CODE_SIMPLE") == "1")
    check("unrelated env kept", settings["env"].get("CLAUDE_WORKER") == "deepseek")
    check("hooks kept", "SessionStart" in settings.get("hooks", {}))
    check("plugins kept", settings.get("enabledPlugins") == {"a@b": True})
    check("telemetry untouched", not any(k in settings["env"] for k in (
        "DISABLE_TELEMETRY", "DISABLE_ERROR_REPORTING", "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC")))

    failed = [n for n, ok in checks if not ok]
    print()
    for name, ok in checks:
        print(("  PASS  " if ok else "  FAIL  ") + name)
    print()
    if failed:
        print(str(len(failed)) + " CHECK(S) FAILED; sandbox kept at " + str(root))
        return 1
    print("all " + str(len(checks)) + " checks passed")
    shutil.rmtree(root, ignore_errors=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
