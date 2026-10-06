# claude-cleanup

在 **macOS、Windows、Linux** 上稽核、完整備份並安全清理本機的 **Claude Code** 與
**Claude Desktop** 狀態。

這是 [claude-cleanup skill](https://github.com/suyuan2022/suyuan-skill/tree/main/claude-cleanup)
的跨平台分支。原始腳本只能在 macOS 執行：它會呼叫 `ps -axo`、`security`、
`sudo systemsetup`，並讀取 `~/Library/...`，所以在 Windows 上根本無法啟動。
本分支保留完整的安全模型與相同的命令介面，並可在 Windows 執行。

English → [README.md](README.md)

## 本 repo 的另一個模組：clash-verge-ai-exit

[`clash-verge-ai-exit/`](clash-verge-ai-exit/) 是一套**獨立**的 **Clash Verge Rev** 設定包：
把指定服務的流量**固定導向一個專屬靜態代理出口**，並關閉常見的旁路
（QUIC/HTTP3、系統 DoH、IPv6），其餘流量一律直連。

它不屬於清理 skill，有自己的入口：

- [`clash-verge-ai-exit/SETUP.md`](clash-verge-ai-exit/SETUP.md) —— 設定手冊（權威）
- [`clash-verge-ai-exit/AGENTS.md`](clash-verge-ai-exit/AGENTS.md) —— 給 agent 的指示
- [`clash-verge-ai-exit/install.ps1`](clash-verge-ai-exit/install.ps1) —— 自動安裝腳本
  （自動解析 Clash Verge 的隨機 uid 檔名、渲染範本、備份、驗證）
- [`clash-verge-ai-exit/check-windows-locale.ps1`](clash-verge-ai-exit/check-windows-locale.ps1) ——
  檢查裝置的時區／地區／格式是否與出口國家一致（`-Apply` 可修正）

代理憑證永不提交：範本使用 `__PROXY_*__` 佔位符，安裝時由使用者輸入。

本文件下方的「適用界線」描述的是**清理 skill**；Clash 設定包是網路設定工具，
有它自己的前提與界線 —— 見 `SETUP.md` 第 11 節。

## 殘留最常漏掉的三個地方

汰換或退役機器時，通常會漏掉這三處：

| 位置 | macOS | Windows |
| --- | --- | --- |
| Agent 設定目錄 | `~/.claude` | `%USERPROFILE%\.claude` |
| 登入憑證 | 鑰匙圈項目 `Claude Code-credentials` | `~/.claude/.credentials.json` |
| 桌面端資料 | `~/Library/Application Support/Claude` | `%APPDATA%\Claude`、`%LOCALAPPDATA%\Claude` |

只刪資料夾並不夠：憑證與桌面端狀態會留下來。

## 保證

- **窄白名單**：不做臨時刪除，每個目標都來自明確清單。
- **第一個寫入就是備份**：任何東西移動之前，先做一份經校驗的副本。
- **只移動，不刪除**：所有移除都進入時間戳廢紙簍目錄
  （`~/.Trash/claude-cleanup-<時間戳>/`），也不會清空資源回收筒。
- **保護路徑一律拒絕**：工作階段歷史、skills、hooks、plugins、設定檔都無法
  被選為目標，執行後還會再次檢查它們仍然存在。
- **遙測逐值保留**：本工具永不改變遙測狀態。
- **永不結束任何行程**。
- **失敗即停止**：備份校驗失敗或違反白名單都會中止本次執行。

## 需求

Python 3.8 以上，不需要任何第三方套件。

## 安裝

安裝為 DSH 使用者層級 skill（每個 session 都可用）：

```bash
git clone https://github.com/kkhcheng88/claude-cleanup.git ~/.dsh/skills/claude-cleanup
```

安裝為 Claude Code / Codex skill：

```bash
git clone https://github.com/kkhcheng88/claude-cleanup.git ~/.claude/skills/claude-cleanup
```

或直接抓下來執行：

```bash
git clone https://github.com/kkhcheng88/claude-cleanup.git
cd claude-cleanup
```

## 使用方式

一律先稽核。`--audit` 是唯讀的，不會寫入任何東西：

```bash
python scripts/claude_cleanup.py --audit
```

接著二選一。有真實終端時用互動模式，它會印出完整清單並等待一次 `CONFIRM`：

```bash
python scripts/claude_cleanup.py
```

若執行者沒有 TTY（例如 GUI 裡的 agent），改用顯式旗標。`--confirm` 必須正好是
`CONFIRM`，且呼叫者必須先取得使用者同意；skill 明確禁止 agent 自行代答。

```bash
python scripts/claude_cleanup.py --confirm CONFIRM \
    [--rotate-identity] [--delete-credentials] \
    [--desktop-mode 0|1|2] [--simple-mode 0|1|2] \
    [--extra-leftovers] [--backup-mode full|targeted]
```

| 旗標 | 作用 |
| --- | --- |
| `--audit` | 唯讀報告；在 Claude Code 底下唯一允許的模式 |
| `--backup-mode full` | 預設，完整複製並校驗整個 `~/.claude` |
| `--backup-mode targeted` | 只備份本次會就地修改的檔案 |
| `--rotate-identity` | 輪換 `userID` / `machineID`，清除帳號快取 |
| `--delete-credentials` | macOS 刪鑰匙圈項目，其他平台刪 `.credentials.json` |
| `--desktop-mode 1` | 清除 Claude Desktop 持久資料與登入態 |
| `--desktop-mode 2` | 上述動作，再加上把應用程式移入廢紙簍 |
| `--simple-mode 1` | 在 `settings.json` 設定 `CLAUDE_CODE_SIMPLE=1` |
| `--simple-mode 2` | 移除 `CLAUDE_CODE_SIMPLE` |
| `--extra-leftovers` | 一併清掉需明示同意的陳舊殘留（見 `SKILL.md`） |

## 絕對不會被碰的資料

`projects`、`sessions`、`history.jsonl`、`file-history`、`debug`、`skills`、
`plugins`、`hooks`、`commands`、`scripts`、`agents`、`mcp-servers`、`backups`、
`CLAUDE.md`、`settings.json`、`settings.local.json`，以及 `bin`、`daemon`、`state`
—— 部分安裝會把不屬於 Claude Code 的執行期資產放在 `~/.claude` 底下，這些也不會動。

## 測試

自我測試會建立一個臨時 HOME，對它跑完整清理流程，並驗證只有白名單項目被移動：

```bash
python tests/selftest.py
```

它完全不會碰到你真正的 `~/.claude`。

## Windows 注意事項

- 憑證是**檔案**，不是鑰匙圈項目。
- 不要用 PowerShell 的 `Set-Content -Encoding UTF8` 寫 `settings.json`：
  PowerShell 5.1 會寫入 UTF-8 BOM，`JSON.parse` 之後會拋錯。
- `~/.claude.json` 的 `projects` 可能含有只差磁碟機代號大小寫的鍵
  （`C:/projects/VLOS` 與 `c:/projects/VLOS`）。PowerShell 的 `ConvertFrom-Json`
  會因重複機碼失敗；Python `json` 可正確處理。
- 行程偵測使用 `tasklist`，腳本永不結束任何行程。

## 致謝

原始 skill 與 macOS 腳本作者為
[Suyuan](https://github.com/suyuan2022/suyuan-skill)。本分支將其推廣到 Windows
與 Linux，以 MIT 授權釋出。

## 適用界線

本工具用於隱私清理、疑難排解與機器退役，不用於規避封禁、支付檢查、裝置或 IP
信譽、瀏覽器指紋，或任何平台風控。
