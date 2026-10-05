#!/usr/bin/env python3
"""Audit and safely clean Claude Code / Claude Desktop local state.

Cross-platform version of the claude-cleanup skill: macOS, Windows and Linux.

It keeps the upstream safety model:
  * narrow whitelist; no ad-hoc deletions
  * the first write is a verified backup (the whole ~/.claude tree by default)
  * every removal is a MOVE into a timestamped trash directory, never a delete
  * protected paths are refused and telemetry keys are verified unchanged
  * processes are never killed

Upstream (macOS only):
https://github.com/suyuan2022/suyuan-skill/tree/main/claude-cleanup
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import glob
import io
import json
import os
import pathlib
import platform
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile

SYSTEM = platform.system()
IS_WINDOWS = SYSTEM == "Windows"
IS_MACOS = SYSTEM == "Darwin"

TELEMETRY_KEYS = (
    "DISABLE_TELEMETRY",
    "DISABLE_ERROR_REPORTING",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC",
)

ACCOUNT_CACHE_KEYS = {
    "additionalModelCostsCache", "additionalModelOptionsCache", "anonymousId", "autoCompactWindowsCache",
    "cachedChromeExtensionInstalled", "cachedDynamicConfigs", "cachedExperimentData", "cachedExperimentFeatures",
    "cachedExtraUsageDisabledReason", "cachedGrowthBookFeatures", "cachedGrowthBookFeaturesAt", "cachedStatsigGates",
    "clientDataCache", "clientDataCacheSlots", "feedbackSurveyState", "groveConfigCache", "metricsStatusCache",
    "modelAccessCache", "oauthAccount", "orgModelDefaultCache", "passesEligibilityCache", "s1mAccessCache",
}

PROTECTED = {
    "CLAUDE.md", "agents", "backups", "commands", "debug", "file-history", "history.jsonl", "hooks",
    "mcp-servers", "plans", "plugins", "projects", "scripts", "session-env", "sessions", "settings.json",
    "settings.local.json", "skills", "tasks", "todos",
    # Runtime assets some installs keep under ~/.claude that are NOT Claude Code
    # data (worker / daemon state). Never touched.
    "bin", "daemon", "state",
}

CLI_CACHE = ("cache", "stats-cache.json", "telemetry", "usage-data", "usage.jsonl", "usage.with-fix.jsonl")

# Regenerable debris that the upstream macOS whitelist predates. Used only when
# the operator passes --extra-leftovers. Plugin state markers are deliberately
# NOT listed: they are state, not junk.
EXTRA_LEFTOVERS = (
    "tmp", "paste-cache", "shell-snapshots", "daemon.log", "gh-pr-status-cache.json",
    ".claude.json", "config.json", "package.json", ".last-cleanup", ".last-update-result.json",
    "ide", "transcripts",
)

MAC_SAFE_RELATIVE = ("Library/Caches/claude-cli-nodejs", "Library/Logs/Claude")
MAC_SAFE_GLOBS = (
    "Library/Caches/com.anthropic.claudefordesktop*",
    "Library/Logs/DiagnosticReports/Claude*",
    "Library/Application Support/CrashReporter/Claude*",
)
MAC_DESKTOP_RELATIVE = (
    "Library/Application Support/Claude",
    "Library/Application Support/Claude-3p",
    "Library/Application Support/com.anthropic.claudefordesktop",
    "Library/HTTPStorages/com.anthropic.claudefordesktop",
    "Library/Preferences/com.anthropic.claudefordesktop.plist",
    "Library/Saved Application State/com.anthropic.claudefordesktop.savedState",
    "Library/WebKit/com.anthropic.claudefordesktop",
)
MAC_DESKTOP_GLOBS = ("Library/Preferences/ByHost/com.anthropic.claudefordesktop*.plist",)
MAC_APP = pathlib.Path("/Applications/Claude.app")


def env_dir(name: str, fallback: pathlib.Path) -> pathlib.Path:
    value = os.environ.get(name)
    return pathlib.Path(value) if value else fallback


def read_json(path: pathlib.Path, default: object | None = None) -> object:
    if not path.exists() and default is not None:
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: pathlib.Path, data: object) -> None:
    """Atomic UTF-8 write with no BOM and LF newlines (BOM breaks JSON.parse)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    fd, name = tempfile.mkstemp(prefix="." + path.name + ".", dir=path.parent)
    temp = pathlib.Path(name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp, mode)
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def settings_env(data: object) -> dict[str, object]:
    if not isinstance(data, dict):
        raise ValueError("settings.json top level is not a JSON object; refusing to modify")
    env = data.get("env")
    if env is None:
        return {}
    if not isinstance(env, dict):
        raise ValueError("settings.json env is not a JSON object; refusing to modify")
    return env


def telemetry(data: object) -> dict[str, object | None]:
    try:
        env = settings_env(data)
    except ValueError:
        return {key: None for key in TELEMETRY_KEYS}
    return {key: env.get(key) for key in TELEMETRY_KEYS}


def _dedupe_existing(paths) -> list[pathlib.Path]:
    seen, out = set(), []
    for path in paths:
        try:
            key = os.path.normcase(str(path.absolute()))
        except OSError:
            continue
        if key in seen:
            continue
        seen.add(key)
        if path.exists() or path.is_symlink():
            out.append(path)
    return sorted(out, key=str)


def discover_safe(home: pathlib.Path) -> list[pathlib.Path]:
    claude = home / ".claude"
    targets = [claude / name for name in CLI_CACHE]
    if IS_MACOS:
        targets += [home / name for name in MAC_SAFE_RELATIVE]
        for pattern in MAC_SAFE_GLOBS:
            targets += [pathlib.Path(p) for p in glob.glob(str(home / pattern))]
    return _dedupe_existing(targets)


def discover_desktop(home: pathlib.Path) -> list[pathlib.Path]:
    if IS_MACOS:
        targets = [home / name for name in MAC_DESKTOP_RELATIVE]
        for pattern in MAC_DESKTOP_GLOBS:
            targets += [pathlib.Path(p) for p in glob.glob(str(home / pattern))]
        return _dedupe_existing(targets)
    if IS_WINDOWS:
        local = env_dir("LOCALAPPDATA", home / "AppData" / "Local")
        roaming = env_dir("APPDATA", home / "AppData" / "Roaming")
        return _dedupe_existing([roaming / "Claude", local / "Claude", local / "AnthropicClaude"])
    return _dedupe_existing([home / ".config" / "Claude", home / ".local" / "share" / "Claude"])


def discover_extras(home: pathlib.Path) -> list[pathlib.Path]:
    claude = home / ".claude"
    targets = [claude / name for name in EXTRA_LEFTOVERS]
    targets += [pathlib.Path(p) for p in glob.glob(str(home / ".claude.json.tmp.*"))]
    targets += [home / ".claude.json.bak"]
    return _dedupe_existing(targets)


def assert_no_overlap(targets: list[pathlib.Path]) -> None:
    normalized = sorted({pathlib.Path(os.path.normcase(str(t.absolute()))) for t in targets}, key=str)
    for index, first in enumerate(normalized):
        for second in normalized[index + 1:]:
            if first == second or first in second.parents:
                raise RuntimeError(f"overlapping targets would corrupt the move: {first} and {second}")


def claude_processes() -> list[str]:
    if IS_WINDOWS:
        try:
            result = subprocess.run(["tasklist", "/FO", "CSV", "/NH"], capture_output=True,
                                    text=True, check=False, errors="replace")
        except OSError:
            return []
        found = []
        for row in csv.reader(io.StringIO(result.stdout)):
            if row and row[0].strip().lower().startswith("claude"):
                found.append(row[0].strip())
        return found
    result = subprocess.run(["ps", "-axo", "pid=,comm=,args="], capture_output=True, text=True, check=False)
    found = []
    for line in result.stdout.splitlines():
        parts = line.strip().split(maxsplit=2)
        if len(parts) < 2 or parts[0] == str(os.getpid()):
            continue
        command = pathlib.Path(parts[1]).name.lower()
        args = parts[2] if len(parts) == 3 else ""
        first = pathlib.Path(args.split(maxsplit=1)[0]).name.lower() if args else ""
        if command in {"claude", "claude-code"} or first in {"claude", "claude-code"} or "/Claude.app/" in args:
            found.append(line.strip())
    return found


def running_under_claude() -> bool:
    for key in ("CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT"):
        if os.environ.get(key):
            return True
    if IS_WINDOWS:
        try:
            import psutil  # optional
        except ImportError:
            return False
        try:
            process = psutil.Process()
            for entry in [process, *process.parents()][:12]:
                if pathlib.Path(entry.name()).stem.lower() in {"claude", "claude-code"}:
                    return True
        except Exception:
            return False
        return False
    pid = os.getppid()
    for _ in range(12):
        result = subprocess.run(["ps", "-p", str(pid), "-o", "ppid=,comm=,args="],
                                capture_output=True, text=True, check=False)
        parts = result.stdout.strip().split(maxsplit=2)
        if len(parts) < 2:
            return False
        command = pathlib.Path(parts[1]).name.lower()
        first = pathlib.Path(parts[2].split(maxsplit=1)[0]).name.lower() if len(parts) == 3 else ""
        if command in {"claude", "claude-code"} or first in {"claude", "claude-code"}:
            return True
        try:
            next_pid = int(parts[0])
        except ValueError:
            return False
        if next_pid <= 1 or next_pid == pid:
            return False
        pid = next_pid
    return False


def current_timezone() -> str:
    if IS_WINDOWS:
        try:
            return subprocess.run(["tzutil", "/g"], capture_output=True, text=True, check=False).stdout.strip() or "unknown"
        except OSError:
            return "unknown"
    try:
        target = pathlib.Path("/etc/localtime").readlink().as_posix()
    except OSError:
        return "unknown"
    return target.split("/zoneinfo/", 1)[1] if "/zoneinfo/" in target else "unknown"


def stats(root: pathlib.Path) -> tuple[int, int]:
    regular = [p for p in root.rglob("*") if p.is_file() and not p.is_symlink()]
    return len(regular), sum(p.stat().st_size for p in regular)


def targeted_backup_files(home: pathlib.Path) -> list[pathlib.Path]:
    claude = home / ".claude"
    files = [p for p in (home / ".claude.json", claude / "settings.json", claude / ".credentials.json") if p.is_file()]
    backups = claude / "backups"
    if backups.is_dir():
        files += sorted(p for p in backups.glob(".claude.json.backup.*") if p.is_file() and not p.is_symlink())
    return files


def create_backup(home: pathlib.Path, mode: str) -> pathlib.Path:
    claude, identity = home / ".claude", home / ".claude.json"
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
    partial = home / "ClaudeBackups" / ("claude-cleanup-" + stamp + ".partial")
    final = partial.with_suffix("")
    partial.mkdir(parents=True)
    manifest: dict[str, object] = {
        "createdUtc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source": str(claude),
        "mode": mode,
    }
    if mode == "full":
        if not claude.is_dir():
            raise FileNotFoundError("~/.claude does not exist; a full backup cannot be satisfied")
        dest = partial / "dot-claude"
        try:
            shutil.copytree(claude, dest, symlinks=True)
        except (OSError, shutil.Error):
            if dest.exists():
                shutil.rmtree(dest)
            shutil.copytree(claude, dest, symlinks=False)
        if stats(claude) != stats(dest):
            raise RuntimeError(f"~/.claude backup verification failed; partial kept at {partial}")
        manifest["files"], manifest["regularFileBytes"] = stats(claude)
    else:
        copied = []
        files_dir = partial / "files"
        files_dir.mkdir()
        for path in targeted_backup_files(home):
            try:
                relative = path.relative_to(home)
            except ValueError:
                continue
            destination = files_dir / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)
            if path.stat().st_size != destination.stat().st_size:
                raise RuntimeError(f"targeted backup verification failed for {path}; partial kept at {partial}")
            copied.append(str(relative))
        manifest["copiedFiles"] = copied
    if identity.is_file():
        shutil.copy2(identity, partial / "claude.json")
        if identity.stat().st_size != (partial / "claude.json").stat().st_size:
            raise RuntimeError(f"~/.claude.json backup verification failed; partial kept at {partial}")
        manifest["claudeJsonCopied"] = True
    write_json(partial / "manifest.json", manifest)
    partial.rename(final)
    return final


def move_to_trash(target: pathlib.Path, allowed: set[pathlib.Path], claude: pathlib.Path,
                  batch: pathlib.Path) -> pathlib.Path:
    absolute = target.absolute()
    protected = {claude / name for name in PROTECTED}
    if absolute == claude.absolute() or any(absolute == p.absolute() or p.absolute() in absolute.parents
                                            for p in protected):
        raise RuntimeError(f"refusing to touch a protected path: {target}")
    if absolute not in allowed:
        raise RuntimeError(f"target is not in the deletion whitelist: {target}")
    batch.mkdir(parents=True, exist_ok=True)
    destination = batch / f"{len(list(batch.iterdir())):02d}-{target.name}"
    shutil.move(str(target), str(destination))
    return destination


def rotate_identity(home: pathlib.Path) -> int:
    identity, backups = home / ".claude.json", home / ".claude/backups"
    if not identity.is_file():
        raise FileNotFoundError("~/.claude.json does not exist; cannot rotate local IDs")
    files = [identity]
    if backups.is_dir():
        files += sorted(p for p in backups.glob(".claude.json.backup.*") if p.is_file() and not p.is_symlink())
    ids, prepared = {"userID": secrets.token_hex(32), "machineID": secrets.token_hex(32)}, []
    for path in files:
        data = read_json(path)
        if not isinstance(data, dict):
            raise ValueError(f"identity file is not a JSON object: {path}")
        updated = dict(data)
        updated.update(ids)
        for key in ACCOUNT_CACHE_KEYS:
            updated.pop(key, None)
        prepared.append((path, updated))
    for path, data in prepared:
        write_json(path, data)
    return len(files) - 1


def update_simple(home: pathlib.Path, mode: int) -> None:
    path = home / ".claude/settings.json"
    if mode == 2 and not path.exists():
        return
    data = read_json(path, {})
    if not isinstance(data, dict):
        raise ValueError("settings.json top level must be a JSON object")
    before = telemetry(data)
    updated, env = dict(data), dict(settings_env(data))
    if mode == 1:
        env["CLAUDE_CODE_SIMPLE"] = "1"
    else:
        env.pop("CLAUDE_CODE_SIMPLE", None)
    updated["env"] = env
    if telemetry(updated) != before:
        raise RuntimeError("the simple-mode change touched telemetry settings")
    if updated != data:
        write_json(path, updated)


def credential_file(home: pathlib.Path) -> pathlib.Path | None:
    """On macOS credentials live in the keychain, not on disk."""
    if IS_MACOS:
        return None
    path = home / ".claude/.credentials.json"
    return path if path.is_file() else None


def bytes_human(size: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            return f"{size:.1f} {unit}" if unit != "B" else f"{size} B"
        size /= 1024.0
    return f"{size:.1f} GB"


def ask_yes(prompt: str) -> bool:
    return input(f"{prompt} [y/N]: ").strip().lower() == "y"


def ask_choice(prompt: str, allowed: set[int]) -> int:
    value = input(prompt).strip() or "0"
    if not value.isdigit() or int(value) not in allowed:
        raise ValueError("input out of the allowed range; stopped without modifying anything")
    return int(value)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Audit and safely clean Claude local state")
    parser.add_argument("--audit", action="store_true", help="read-only audit; writes nothing")
    parser.add_argument("--backup-mode", choices=("full", "targeted"), default="full",
                        help="full (default): verified copy of the whole ~/.claude tree; "
                             "targeted: verified copy of only the files this run mutates")
    parser.add_argument("--rotate-identity", action="store_true", help="rotate userID/machineID")
    parser.add_argument("--delete-credentials", action="store_true", help="remove Claude Code login state")
    parser.add_argument("--desktop-mode", type=int, choices=(0, 1, 2), default=0,
                        help="0 keep; 1 clear desktop data; 2 also remove the app")
    parser.add_argument("--simple-mode", type=int, choices=(0, 1, 2), default=0,
                        help="0 keep; 1 enable CLAUDE_CODE_SIMPLE; 2 remove it")
    parser.add_argument("--extra-leftovers", action="store_true", help="also trash opt-in stale debris")
    parser.add_argument("--confirm", default=None, metavar="CONFIRM",
                        help="non-interactive consent token; must be exactly CONFIRM")
    args = parser.parse_args(argv)

    home = pathlib.Path.home()
    claude = home / ".claude"
    identity = home / ".claude.json"
    settings = claude / "settings.json"
    app = MAC_APP if IS_MACOS else None

    if running_under_claude() and not args.audit:
        print("Refusing to run: launched by Claude Code. Use another agent or a plain terminal; "
              "only --audit is allowed here.", file=sys.stderr)
        return 2

    try:
        env = settings_env(read_json(settings, {}))
        safe = discover_safe(home)
        desktop = discover_desktop(home)
        extras = discover_extras(home)
        processes = claude_processes()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Audit failed: {error}", file=sys.stderr)
        return 2

    disabled = [k for k in TELEMETRY_KEYS if str(env.get(k, "")).lower() in {"1", "true", "yes", "on"}]
    simple_on = str(env.get("CLAUDE_CODE_SIMPLE", "")).lower() in {"1", "true"}
    credential = credential_file(home)
    total_files, total_bytes = stats(claude) if claude.is_dir() else (0, 0)

    print(f"Claude Cleanup (cross-platform; detected {SYSTEM})")
    print("Nothing is written before the final CONFIRM, and every removal only moves into a")
    print("timestamped trash directory.\n")
    print("READ-ONLY AUDIT")
    print(f"- ~/.claude: {'present' if claude.is_dir() else 'absent'}; "
          f"~/.claude.json: {'present' if identity.is_file() else 'absent'}")
    for label, items in (("auto-safe cache/log targets", safe),
                         ("Claude Desktop / app-support targets", desktop),
                         ("opt-in stale leftovers", extras)):
        print(f"- {label}: {len(items)}")
        for item in items:
            print(f"    * {item}")
    if IS_MACOS:
        print("- Claude Code credentials: keychain item 'Claude Code-credentials' (removed only if selected)")
    else:
        print(f"- Claude Code credentials: {credential if credential else 'absent'}")
    print(f"- Claude.app: {'present' if (app and app.exists()) else 'absent (no bundled app removal on this platform)'}")
    print(f"- related processes: {len(processes)}")
    print(f"- telemetry keys currently disabled: {', '.join(disabled) if disabled else 'none detected'}")
    print(f"- simple mode: {'enabled' if simple_on else 'disabled'}; timezone: {current_timezone()}")
    print(f"- full backup would copy {total_files} files / {bytes_human(total_bytes)}")
    print("- protected (never touched): " + ", ".join(sorted(PROTECTED)))
    print("- this skill does not evade bans, payment checks, or platform risk controls.")

    if args.audit:
        return 0

    interactive = args.confirm is None
    if interactive and not sys.stdin.isatty():
        print("Refusing to write: the interactive flow needs a real TTY. "
              "Pass --confirm CONFIRM for a non-interactive run.", file=sys.stderr)
        return 2
    if not interactive and args.confirm != "CONFIRM":
        print("Refusing to write: --confirm must be exactly CONFIRM.", file=sys.stderr)
        return 2

    try:
        if interactive:
            print("\nOnly risky actions are asked about; regenerable caches and logs are automatic.")
            rotate = ask_yes("Rotate local userID/machineID and clear known account cache fields?")
            if IS_MACOS:
                keychain = ask_yes("Delete the keychain item 'Claude Code-credentials' (logs the CLI out)?")
                del_creds = False
            else:
                keychain = False
                del_creds = ask_yes(f"Delete {credential if credential else '~/.claude/.credentials.json'} (logs the CLI out)?")
            desktop_mode = ask_choice("Claude Desktop: 0 keep; 1 clear login state/persistent data; 2 also remove the app. Choose [0]: ", {0, 1, 2})
            simple_mode = ask_choice("Simple mode: 0 keep; 1 enable CLAUDE_CODE_SIMPLE; 2 remove it. Choose [0]: ", {0, 1, 2})
            set_timezone = (IS_MACOS and current_timezone() != "Asia/Taipei"
                            and ask_yes("Set the macOS timezone to Asia/Taipei?"))
        else:
            rotate = args.rotate_identity
            del_creds = args.delete_credentials
            keychain = del_creds and IS_MACOS
            desktop_mode = args.desktop_mode
            simple_mode = args.simple_mode
            set_timezone = False

        risky = bool(rotate or keychain or del_creds or desktop_mode or simple_mode)
        clean_safe = not processes
        if processes and risky:
            if not interactive:
                raise RuntimeError(f"Claude is running ({len(processes)} process(es)); this script never kills processes")
            print("\nThe selected risky actions need every Claude Code / Claude Desktop instance closed; "
                  "this script will not kill them.")
            input("Press Enter after quitting to re-check: ")
            if claude_processes():
                print("Claude processes are still running; cancelled without writing.", file=sys.stderr)
                return 2
            clean_safe = True

        targets: list[pathlib.Path] = []
        if clean_safe:
            targets += safe
        if desktop_mode:
            targets += desktop
        if args.extra_leftovers:
            targets += extras
        credential_target = credential if del_creds else None
        if credential_target:
            targets.append(credential_target)
        if desktop_mode == 2 and app and app.exists():
            targets.append(app)

        assert_no_overlap(targets)
        allowed = {t.absolute() for t in targets}

        print("\nFINAL MANIFEST")
        print(f"1. First write: verified backup ({args.backup_mode}) -> {home / 'ClaudeBackups'}")
        print(f"2. {'automatic cleanup' if clean_safe else 'SKIPPED (Claude is running)'}: {len(safe)} cache/log item(s)")
        print(f"3. targets ({len(targets)}):")
        for target in targets:
            print(f"   - {target}")
        print(f"4. identity rotation: {bool(rotate)}; credentials: {bool(credential_target or keychain)}; "
              f"desktop mode: {desktop_mode}; simple mode: {simple_mode}; timezone: {bool(set_timezone)}")
        print("Never touched: sessions, projects, history, skills, plugins, hooks, commands, agents, MCP, "
              "settings files, or any project/Git/Codex data.")
        print("All removals only go to a timestamped trash directory; telemetry keys stay unchanged.")

        if interactive and input("Type CONFIRM once you fully understand; anything else cancels: ").strip() != "CONFIRM":
            print("Cancelled; nothing was modified.")
            return 1

        before_telemetry = telemetry(read_json(settings, {}))
        protected_before = [claude / name for name in PROTECTED
                            if (claude / name).exists() or (claude / name).is_symlink()]

        backup = create_backup(home, args.backup_mode)
        print(f"\n[1/6] backup verified: {backup}")

        if set_timezone:
            print("[manual step] Enter the macOS password only in the native sudo prompt; "
                  "this script never reads or stores it.")
            subprocess.run(["sudo", "-v"], check=True)

        if rotate:
            print(f"[2/6] identity rotated; synced {rotate_identity(home)} internal backup file(s)")
        else:
            print("[2/6] identity unchanged")

        if keychain:
            result = subprocess.run(["security", "delete-generic-password", "-s", "Claude Code-credentials"],
                                    capture_output=True, text=True, check=False)
            if result.returncode not in {0, 44}:
                raise RuntimeError(f"keychain handling failed: {result.stderr.strip()}")
        print(f"[3/6] credentials: {'handled' if (keychain or credential_target) else 'unchanged'}")

        batch = home / ".Trash" / ("claude-cleanup-" + dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
        moved, failed = [], []
        for target in targets:
            try:
                moved.append(move_to_trash(target, allowed, claude, batch))
            except RuntimeError:
                raise
            except OSError as error:
                failed.append((target, error))
        print(f"[4/6] moved to trash: {len(moved)}")
        if failed:
            print(f"       FAILED, left in place: {len(failed)}")
            for target, error in failed:
                print(f"       - {target} :: {error}")

        if simple_mode:
            update_simple(home, simple_mode)
        print(f"[5/6] simple mode: {('keep', 'enable', 'remove')[simple_mode]}")

        if set_timezone:
            subprocess.run(["sudo", "/usr/sbin/systemsetup", "-settimezone", "Asia/Taipei"], check=True)
            if current_timezone() != "Asia/Taipei":
                raise RuntimeError("timezone verification failed after the change")

        if telemetry(read_json(settings, {})) != before_telemetry:
            raise RuntimeError("telemetry settings changed; stopped")

        missing = [p for p in protected_before if not (p.exists() or p.is_symlink())]
        if missing:
            raise RuntimeError("protected paths went missing: " + ", ".join(map(str, missing)))
        print("[6/6] telemetry unchanged; protected paths intact")
        print(f"\nDone. The trash was not emptied and nothing was permanently deleted.\nBackup: {backup}")
        if moved or failed:
            print(f"Trash batch: {batch}")
        return 0 if not failed else 1
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"Stopped: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
