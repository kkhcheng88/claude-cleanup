---
name: claude-cleanup
description: Audit, fully back up, clean or reset local Claude Code and Claude Desktop state on macOS, Windows or Linux. Use when clearing regenerable caches and logs, rotating local IDs, resetting desktop login state, enabling minimal-prompt mode, or decommissioning a machine. Not for evading bans, payment checks, or platform risk controls.
---

# Claude 本機清理（跨平台）

使用隨附腳本執行，不要臨時拼接 `rm` / `Remove-Item`。腳本採用窄白名單、完整備份、一次最終知情確認、失敗即停止。

`scripts/claude_cleanup.py` 是上游 macOS 版腳本的跨平台版本（macOS / Windows / Linux），CLI 與安全語意一致。上游原版：<https://github.com/suyuan2022/suyuan-skill/tree/main/claude-cleanup>。

## 執行順序

1. 如果當前執行者就是 Claude Code，只執行唯讀稽核，並提醒使用者切換到其他執行者或普通終端。不要讓正在使用 `~/.claude` 的 Claude Code 自己修改該目錄。

   ```bash
   python scripts/claude_cleanup.py --audit
   ```

2. 先執行稽核，並向使用者說明：
   - 第一個寫入操作是完整複製並校驗 `~/.claude`，同時備份 `~/.claude.json`；
   - 可再生快取與日誌會自動納入最終清單，不逐項詢問；
   - 身分輪換、憑證、桌面端登入態、應用、精簡模式屬於風險操作，仍由使用者選擇；
   - 所有移除只進入時間戳廢紙簍目錄，不會永久刪除，也不會清空資源回收筒；
   - 保護路徑與遙測設定保持不變。

3. 使用者明確要求繼續後再寫入。有真實終端時用互動模式：

   ```bash
   python scripts/claude_cleanup.py
   ```

   互動模式顯示展開後的完整清單，使用者輸入一次 `CONFIRM` 才開始寫入。不要用管道代答。

   沒有 TTY 的執行者（例如 GUI 裡的 agent）改用顯式旗標，並且**必須先取得使用者確認**，不可自行代答：

   ```bash
   python scripts/claude_cleanup.py --confirm CONFIRM \
       [--rotate-identity] [--delete-credentials] \
       [--desktop-mode 0|1|2] [--simple-mode 0|1|2] \
       [--extra-leftovers] [--backup-mode full|targeted]
   ```

   只有自動安全清理且 Claude 正在執行時，腳本直接跳過安全目標；若使用者選擇風險操作而 Claude 仍在執行，腳本會拒絕並要求使用者自行正常退出。腳本不會結束任何行程。

4. 結束後報告：備份路徑、廢紙簍批次、實際選擇、遙測繼承結果、時區。任何中途停止都報告為部分完成，不可籠統聲稱清理成功。

## 平台對照

| 概念 | macOS | Windows |
| --- | --- | --- |
| Claude 目錄 | `~/.claude` | `%USERPROFILE%\.claude` |
| 憑證 | 鑰匙圈項目 `Claude Code-credentials` | `~/.claude/.credentials.json` |
| 桌面端資料 | `~/Library/Application Support/Claude` | `%APPDATA%\Claude`、`%LOCALAPPDATA%\Claude` |
| 桌面端日誌 | `~/Library/Logs/Claude` 等 | `%LOCALAPPDATA%\Claude\Logs` |
| 應用程式 | `/Applications/Claude.app` | 未提供應用移除（無標準安裝目錄） |
| 時區 | `sudo systemsetup` | 不適用，自動跳過 |
| 廢紙簍 | `~/.Trash/claude-cleanup-<時間戳>` | `%USERPROFILE%\.Trash\claude-cleanup-<時間戳>` |

Linux 只涵蓋 `~/.claude` 的 CLI 快取與 `.credentials.json`，以及 `~/.config/Claude`、`~/.local/share/Claude`。

## Windows 注意事項

- 憑證是**檔案**而非鑰匙圈，刪除後 CLI 會登出。
- 不要用 PowerShell 的 `Set-Content -Encoding UTF8` 寫 `settings.json`：PowerShell 5.1 會寫入 UTF-8 BOM，導致 `JSON.parse` 拋錯。腳本用 Python 寫入，天然無 BOM 並使用 LF。
- `~/.claude.json` 的 `projects` 可能含只差磁碟機代號大小寫的鍵（`C:/projects/VLOS` 與 `c:/projects/VLOS`），Windows PowerShell 的 `ConvertFrom-Json` 會因重複機碼失敗。腳本用 Python `json`，大小寫敏感，可正確處理。
- 行程偵測用 `tasklist`；結束行程需使用者自行用工作管理員，腳本永不 kill。

## 自動安全清理

在 Claude Code 與 Claude Desktop 都已退出後，自動把下列現存目標納入最終清單，不需逐項提問：

```text
~/.claude/cache
~/.claude/stats-cache.json
~/.claude/telemetry
~/.claude/usage-data
~/.claude/usage.jsonl
~/.claude/usage.with-fix.jsonl
macOS: ~/Library/Caches/claude-cli-nodejs
macOS: ~/Library/Caches/com.anthropic.claudefordesktop*
macOS: ~/Library/Logs/Claude
macOS: ~/Library/Logs/DiagnosticReports/Claude*
macOS: ~/Library/Application Support/CrashReporter/Claude*
```

這些目標仍須通過白名單檢查，且只移入廢紙簍。

## 額外陳舊殘留（需 `--extra-leftovers`）

上游白名單未涵蓋、但明確可再生的殘留，只有在執行者明確選擇時才處理：

```text
~/.claude/tmp、paste-cache、shell-snapshots、daemon.log、gh-pr-status-cache.json
~/.claude/.claude.json、config.json、package.json
~/.claude/.last-cleanup、.last-update-result.json
~/.claude/ide、~/.claude/transcripts
~/.claude.json.bak、~/.claude.json.tmp.*
```

插件狀態標記（例如 `.ponytail-*`）、`settings.json.bak`、`feedback/drafts`、`uploads`、`jobs`、`output-styles`、`playbooks` 不在此清單，屬狀態或使用者內容。

## 絕對保護範圍

絕不刪除或移動：

```text
~/.claude/projects、sessions、history.jsonl、file-history、debug
~/.claude/skills、plugins、hooks、commands、scripts、agents、mcp-servers
~/.claude/backups、CLAUDE.md、settings.json、settings.local.json
~/.claude/bin、daemon、state（部分安裝把 worker/daemon 狀態放在此處，不是 Claude Code 資料）
任何專案目錄、Git 儲存庫、其他 agent 的工作階段，以及未明確列入白名單的路徑
```

`settings.json` 只允許結構化修改使用者明確選擇的鍵（`CLAUDE_CODE_SIMPLE`）。保留其他 env、hooks、plugins、權限、模型、MCP、狀態列與祕密。目標與保護路徑重疊時立即停止。

## 風險操作

- **本地身分輪換**：輪換 `~/.claude.json` 的 `userID`、`machineID`，清除已知帳號快取欄位，並把同一組新值同步到 `~/.claude/backups/.claude.json.backup.*`。僅用於隱私與排障，不宣稱能改變平台關聯判斷。
- **憑證**：macOS 刪除鑰匙圈 `Claude Code-credentials`；其他平台刪除 `~/.claude/.credentials.json`。單獨選擇，刪除後 CLI 會登出。
- **Claude Desktop**：可選擇僅清持久資料與登入態，或連應用程式一併移入廢紙簍。不能自動結束應用行程。
- **最小提示詞模式**：在 `settings.json` 的 `env` 設定或移除 `CLAUDE_CODE_SIMPLE=1`。啟用後使用最小系統提示詞與有限工具，並跳過 hooks、skills、plugins、MCP、自動記憶及 `CLAUDE.md` 自動探索；這些資產不會被刪除。
- **台北時區**：僅在 macOS 且目前不是 `Asia/Taipei` 時詢問，使用 `sudo systemsetup` 修改並驗證。

## 備份模式

- `--backup-mode full`（預設）：完整複製並以檔案數與位元組數校驗 `~/.claude`。
- `--backup-mode targeted`：只備份本次會就地修改的檔案（`~/.claude.json`、`settings.json`、`.credentials.json`、`backups/.claude.json.backup.*`）。被移入廢紙簍的項目本身就是可還原副本。僅在執行者明確要求跳過完整備份時使用。

## 遙測繼承

逐值保存以下鍵；目前關閉就保持關閉，目前未關閉就不主動關閉。改變遙測狀態不屬於本 skill 的清理範圍。

```text
DISABLE_TELEMETRY
DISABLE_ERROR_REPORTING
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
```

## 自我測試

在臨時 HOME 沙箱中驗證完整流程，不會碰到真實 `~/.claude`：

```bash
python tests/selftest.py
```

## 界線

本 skill 不用於規避封禁、支付檢查、裝置或 IP 信譽、瀏覽器指紋或任何平台風控。