# AGENTS.md

This repository contains **two independent things**. Pick the one that matches the request.

## 1. `claude-cleanup` — the cleanup skill (default)

Audit, back up and safely clean local **Claude Code** / **Claude Desktop** state on
macOS, Windows and Linux.

- Read [`SKILL.md`](SKILL.md) first — it is the authoritative spec for this skill.
- Safety model: narrow whitelist, backup is the first write, move-never-delete,
  protected paths are refused, no process is ever killed.
- Never delete anything ad hoc, and never answer the interactive `CONFIRM`
  prompt on the user's behalf.
- [`README.md`](README.md) (English) and [`README.zh-TW.md`](README.zh-TW.md)
  (繁體中文) describe usage.

## 2. `clash-verge-ai-exit/` — Clash Verge Rev configuration package

If the user asks to **set up Clash Verge** on a Windows PC, or to route selected
service traffic through a **fixed proxy exit**, this is the relevant module.

Read, in order:

1. [`clash-verge-ai-exit/AGENTS.md`](clash-verge-ai-exit/AGENTS.md) — constraints and procedure
2. [`clash-verge-ai-exit/SETUP.md`](clash-verge-ai-exit/SETUP.md) — the authoritative manual
3. [`clash-verge-ai-exit/DEVICES.md`](clash-verge-ai-exit/DEVICES.md) — iOS / Android / browser / Claude Code

Non-negotiable rules for that module:

- **Never commit proxy credentials.** `local-secrets.psd1` and the generated
  `mobile-clash.yaml` are gitignored — keep it that way. The templates carry
  `__PROXY_*__` placeholders and the installer asks for the values at run time.
- **The exit group must stay `type: select`.** Never switch it to `url-test` or
  `load-balance`: those change the exit IP by themselves, which defeats the point
  of the package.
- **Always validate** written configs with `verge-mihomo -t -f <file>` and keep
  them UTF-8 **without BOM** (a BOM breaks the mihomo YAML parser).
- **Never "fix" a Cloudflare challenge by clearing cookies** — `cf_clearance` is
  bound to IP + User-Agent. Check for a QUIC leak first (`SETUP.md` section 8).
- **Prefer measurements over database guesses**: use
  [`clash-verge-ai-exit/proxy-bench.ps1`](clash-verge-ai-exit/proxy-bench.ps1)
  to compare latency, `loc`, `colo` and whether a challenge is triggered.
- **Keep the device agreeing with the exit country.** Run
  [`clash-verge-ai-exit/check-windows-locale.ps1`](clash-verge-ai-exit/check-windows-locale.ps1)
  as part of setup and require `RESULT: all settings are consistent.` — the verdict is
  time zone, home location, system locale and user formats. The **language list is
  informational only** and never blocks the verdict: Windows can refuse the change
  silently, and writing the list programmatically destroys existing IMEs, so the
  script never touches it. Time zone and system locale may need Administrator; the
  system locale needs a reboot.
- **Apply the package's defaults; do not make the user choose.** The default is
  system proxy + proxy guard + `HTTPS_PROXY` + QUIC blocked in both places +
  sniffer + a `select` exit group (see `SETUP.md` section 13 for the failure-mode
  reasoning). Add TUN when the Clash Verge service is already available; when it
  is not, do **not** install the service just for TUN — use the system proxy
  instead. Explain trade-offs only if the user asks why.
- **Never rewrite the user's language list** (`Set-WinUserLanguageList` /
  `New-WinUserLanguageList`). Windows can report success while changing nothing, and
  rebuilding the list overwrites the existing input methods — a real Cangjie IME
  profile was destroyed this way. `check-windows-locale.ps1` reports the language
  list but never writes it; the script's `-Apply` skips it deliberately. Add languages
  through the Settings UI instead.
- **In Clash Verge service mode** (required for TUN) a non-elevated process can no
  longer stop the core — `Stop-Process verge-mihomo` fails with `Access is denied` —
  and `logs\sidecar\sidecar_latest.log` stops updating. Verify by reloading the
  profile in the GUI and read the Connections page (or the mihomo info log line), not
  the sidecar log, which otherwise yields a false "nothing leaked" conclusion.
- **Enterprise OneDrive stuck on "Signing in..." is a capture-layer problem, not a
  routing problem.** Windows blocks AppContainer apps from loopback, so the WAM broker
  (`Microsoft.AAD.BrokerPlugin`) cannot reach the local proxy at all; no `DOMAIN-*` or
  group change can fix it. Run
  [`clash-verge-ai-exit/fix-uwp-loopback.ps1`](clash-verge-ai-exit/fix-uwp-loopback.ps1)
  `-Apply` from an elevated shell (it only touches installed packages and verifies the
  result with `CheckNetIsolation LoopbackExempt -s` — a printed success message is not
  proof, and `-n` must be passed quoted through cmd.exe).
- The scope statement in `README.md` describes the **cleanup skill**; the Clash
  package is a network-configuration tool and carries its own prerequisites and
  boundaries (see `SETUP.md` section 11).

## 繁體中文摘要

本 repo 有兩個**互相獨立**的模組：

| 模組 | 入口 | 用途 |
|---|---|---|
| `claude-cleanup` | `SKILL.md` | 稽核／備份／安全清理本機 Claude Code 與 Claude Desktop 狀態 |
| `clash-verge-ai-exit/` | `SETUP.md` | 把指定服務流量固定導向一個專屬靜態代理出口，並關閉旁路 |

兩者的限制請分別閱讀上列文件。**代理憑證永不提交進 repo。**
