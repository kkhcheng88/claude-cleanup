# claude-cleanup

Audit, back up and safely clean local **Claude Code** and **Claude Desktop**
state on **macOS, Windows and Linux**.

A cross-platform fork of the
[claude-cleanup skill](https://github.com/suyuan2022/suyuan-skill/tree/main/claude-cleanup).
The original script was macOS-only: it shells out to `ps -axo`, `security` and
`sudo systemsetup` and reads `~/Library/...`, so it never started on Windows.
This fork keeps the safety model and the same command surface, and runs on
Windows too.

繁體中文說明 → [README.zh-TW.md](README.zh-TW.md)

## The three places leftovers hide

When a machine is retired or replaced, three locations are usually missed:

| Location | macOS | Windows |
| --- | --- | --- |
| Agent config dir | `~/.claude` | `%USERPROFILE%\.claude` |
| Login credentials | keychain item `Claude Code-credentials` | `~/.claude/.credentials.json` |
| Desktop app data | `~/Library/Application Support/Claude` | `%APPDATA%\Claude`, `%LOCALAPPDATA%\Claude` |

Deleting the folder alone is not enough: the credentials and the desktop app
state survive it.

## Guarantees

- **Narrow whitelist.** Nothing is deleted ad hoc; every target comes from an
  explicit list.
- **Backup is the first write.** A verified copy is made before anything moves.
- **Move, never delete.** Every removal goes to a timestamped trash directory
  (`~/.Trash/claude-cleanup-<stamp>/`). No recycle bin is emptied.
- **Protected paths are refused.** Session history, skills, hooks, plugins and
  settings cannot be targeted, and are re-checked after the run.
- **Telemetry is preserved value by value.** This tool never changes it.
- **No process is ever killed.**
- **Fail fast.** A failed backup check or a whitelist violation stops the run.

## Requirements

Python 3.8 or newer. No third-party packages.

## Install

As a DSH user skill (available in every session):

```bash
git clone https://github.com/kkhcheng88/claude-cleanup.git ~/.dsh/skills/claude-cleanup
```

As a Claude Code / Codex skill:

```bash
git clone https://github.com/kkhcheng88/claude-cleanup.git ~/.claude/skills/claude-cleanup
```

Or just clone it and run the script directly:

```bash
git clone https://github.com/kkhcheng88/claude-cleanup.git
cd claude-cleanup
```

## Usage

Always audit first. `--audit` is read-only and writes nothing:

```bash
python scripts/claude_cleanup.py --audit
```

Then either run the interactive flow in a real terminal, which prints the full
manifest and waits for one `CONFIRM`:

```bash
python scripts/claude_cleanup.py
```

or, for an agent or a script with no TTY, state the choices explicitly.
`--confirm` must be exactly `CONFIRM`, and the caller must obtain consent from
the user first; the skill forbids an agent answering this on its own.

```bash
python scripts/claude_cleanup.py --confirm CONFIRM \
    [--rotate-identity] [--delete-credentials] \
    [--desktop-mode 0|1|2] [--simple-mode 0|1|2] \
    [--extra-leftovers] [--backup-mode full|targeted]
```

| Flag | Effect |
| --- | --- |
| `--audit` | read-only report; the only mode allowed under Claude Code |
| `--backup-mode full` | default: verified copy of the whole `~/.claude` tree |
| `--backup-mode targeted` | verified copy of only the files mutated in place |
| `--rotate-identity` | rotate `userID` / `machineID`, clear account caches |
| `--delete-credentials` | keychain item on macOS, `.credentials.json` elsewhere |
| `--desktop-mode 1` | clear Claude Desktop persistent data and login state |
| `--desktop-mode 2` | the above, plus move the app bundle to the trash |
| `--simple-mode 1` | set `CLAUDE_CODE_SIMPLE=1` in `settings.json` |
| `--simple-mode 2` | remove `CLAUDE_CODE_SIMPLE` |
| `--extra-leftovers` | also trash opt-in stale debris (see `SKILL.md`) |

## What is never touched

`projects`, `sessions`, `history.jsonl`, `file-history`, `debug`, `skills`,
`plugins`, `hooks`, `commands`, `scripts`, `agents`, `mcp-servers`, `backups`,
`CLAUDE.md`, `settings.json`, `settings.local.json`, plus `bin`, `daemon` and
`state` — runtime assets some installs keep under `~/.claude` that are not
Claude Code data.

## Testing

The self-test builds a throwaway HOME, runs the full cleanup against it and
asserts that only whitelisted paths moved:

```bash
python tests/selftest.py
```

It never touches the real `~/.claude`.

## Windows notes

- Credentials are a **file**, not a keychain item.
- Do not write `settings.json` with PowerShell `Set-Content -Encoding UTF8`:
  PowerShell 5.1 emits a UTF-8 BOM and `JSON.parse` then throws.
- `~/.claude.json` can contain `projects` keys that differ only by drive-letter
  case (`C:/projects/VLOS` vs `c:/projects/VLOS`). PowerShell `ConvertFrom-Json`
  fails on that with a duplicate-key error; Python `json` handles it.
- Process detection uses `tasklist`; the script never kills anything.

## Credits

The original skill and macOS script are by
[Suyuan](https://github.com/suyuan2022/suyuan-skill). This fork generalises
them to Windows and Linux. MIT licensed.

## Scope

This tool is for privacy hygiene, troubleshooting and decommissioning a
machine. It is not for evading bans, payment checks, device or IP reputation,
browser fingerprinting, or any platform risk control.
