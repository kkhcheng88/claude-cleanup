# AGENTS.md — 給 AI agent 的入口指示

這個資料夾是一套「**讓 Claude / ChatGPT 帳號固定從同一個乾淨 IP 出口**」的 Clash Verge 設定包。

## 當使用者要求「在這台電腦設定 Clash Verge / AI 固定出口」時

1. **先完整讀 `SETUP.md`**（那是唯一權威手冊），再讀 `DEVICES.md`（手機／瀏覽器／CLI）。
2. 確認前置：
   - Windows 已安裝 Clash Verge Rev，且 Verge 的 `profiles.yaml` 存在
   - 使用者**手上已有代理資訊**（host / port / username / password），而且該代理是
     **專屬、租期內靜態、位於服務支援的國家**
3. 需要使用者先在 Verge 建立一個**本機（Local）設定檔**，並**打開一次增強編輯器**
   （Merge / Rules / Proxies / Groups / Script 各存一次），讓 Verge 產生那 5 個檔案。
4. 請使用者**完全關閉 Clash Verge**（托盤 → 退出），然後執行：
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1 -IncludeMainProfile
   ```
   代理密碼由使用者輸入（或用 `-SecretsFile`），**不要**把密碼寫進任何檔案或對話。
5. 依 `SETUP.md` 第 6～7 節完成：關閉瀏覽器 QUIC、Claude Code 的 `env` 區塊、三關驗證。
6. 回報結果時附上三關的實際輸出（IP / `loc` / HTTP code）。

## 絕對不要做的事

| 禁止 | 原因 |
|---|---|
| 把代理密碼、`local-secrets.psd1`、`mobile-clash.yaml` 提交進 git | 帳密外洩 |
| 把 `AI-Exit` 群組改成 `url-test` 或 `load-balance` | 會在使用中自動換節點 → 出口 IP 變動，直接破壞本專案的目的 |
| 建議使用者「清 cookie」來解決 Cloudflare 驗證 | `cf_clearance` 綁 IP + UA，清了只會更慢；先查 QUIC 洩漏 |
| 建議使用指紋瀏覽器 | 單一帳號不需要；偽裝反而製造不一致訊號 |
| 建議「用多個帳號湊用量額度」 | 違反服務條款，且付款工具會把帳號關聯起來；應引導至官方更高方案／企業合約／按量計費 API |
| 用「地球上的猜測」取代實測 | 本專案所有決策都以 `proxy-bench.ps1` 的實測數據為準（`loc` / `colo` / TTFB / 抖動 / 是否觸發 Cloudflare 挑戰） |

## 修改設定後的必要動作

1. 用 `verge-mihomo -t -f <檔案>` 驗證（沒有錯誤才算通過）
2. 確認寫出的檔案是 **UTF-8 無 BOM**（有 BOM 會讓 mihomo YAML 解析失敗）
3. 提醒使用者：**在 Clash Verge 重新載入設定檔**，並在「連線」頁確認 `claude.ai`
   的鏈路是 `AI-Exit / <節點名>`（不是 `DIRECT`）

## 檔案角色速查

| 檔案 | 角色 |
|---|---|
| `SETUP.md` | 主要操作手冊（權威） |
| `DEVICES.md` | iOS / Android / 瀏覽器 / Claude Code / Codex |
| `install.ps1` | 自動安裝（解析 Verge 隨機 uid、渲染範本、備份、驗證） |
| `show-verge-map.ps1` | 印出 uid ↔ 角色對應（排錯） |
| `proxy-bench.ps1` | 代理評測（TTFB / loc / colo / ASN） |
| `configs/` | 所有範本（`__PROXY_*__` 佔位符） |
| `launchers/` | `codex-p.cmd` / `claude-p.cmd`（fail-closed 啟動器） |
