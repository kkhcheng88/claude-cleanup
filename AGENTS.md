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
  as part of setup and require `RESULT: all settings are consistent.` — time zone,
  home location, system locale, user formats and language list must not contradict
  the exit country. `-Apply` fixes mismatches (time zone and system locale need
  Administrator; system locale needs a reboot, language list needs a sign-out).
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
