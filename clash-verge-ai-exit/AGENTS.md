# AGENTS.md — 給 AI agent 的入口指示

這個資料夾是一套 **Clash Verge 設定包**：把指定服務的流量**固定導向一個專屬靜態代理出口**，
並確保沒有旁路洩漏；其餘流量直連。

## 預設組態（直接套用，**不要叫使用者選**）

使用者不想在技術選項之間做選擇。請直接套用以下預設，然後回報結果：

1. `install.ps1` 會自動設定 `enable_system_proxy: true` 與 `enable_proxy_guard: true`（這是 fail-closed 的關鍵）
2. **TUN**：Clash Verge 的系統服務可用 → 在 App 內開啟（多一層覆蓋面）；**服務未安裝 → 不要為了 TUN 去安裝服務**，改用系統代理（對 AI 流量已足夠），並在回報中說明
3. 瀏覽器 **QUIC 關閉**（與 mihomo 的 UDP 443 阻擋形成雙保險）
4. Claude Code 的 `HTTPS_PROXY`（fail-closed）
5. 只有使用者**主動問「為什麼」**時才解釋取捨（見 `SETUP.md` 第 13 節）；不要把「TUN 還是明確代理」當成問題丟回給使用者

## 當使用者要求「在這台電腦設定 Clash Verge / 固定出口」時

1. **先完整讀 `SETUP.md`**（唯一權威手冊），再讀 `DEVICES.md`（手機／瀏覽器／CLI）。
2. 確認前置：
   - Windows 已安裝 Clash Verge Rev，且 Verge 的 `profiles.yaml` 存在
   - 使用者**手上有代理資訊**（host / port / username / password），且該代理是
     **專屬**（單一用戶）＋ **租期內靜態不變**
3. 需要使用者先在 Verge 建立一個**本機（Local）設定檔**，並**打開一次增強編輯器**
   （Merge / Rules / Proxies / Groups / Script 各存一次），讓 Verge 產生那 5 個檔案。
4. 請使用者**完全關閉 Clash Verge**（托盤 → 退出），然後執行：
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1 -IncludeMainProfile
   ```
   代理密碼由使用者輸入（或用 `-SecretsFile`）；**不要**把密碼寫進任何檔案或對話。
5. 依 `SETUP.md` 第 6～7 節完成：關閉瀏覽器 QUIC、Claude Code 的 `env` 區塊、
   **Windows 地區／時區一致性檢查**（`check-windows-locale.ps1`，需回報
   `all settings are consistent`）、三關驗證。
6. 回報結果時附上三關的實際輸出（IP / `loc` / HTTP code）。

## 不要做的事

| 不要 | 原因 |
|---|---|
| 把代理密碼、`local-secrets.psd1`、`mobile-clash.yaml` 提交進 git | 憑證外洩 |
| 把 `AI-Exit` 群組改成 `url-test` 或 `load-balance` | 會在使用中自動換節點 → 出口 IP 變動，直接破壞本設定包的目的 |
| 用「清 cookie」解決 Cloudflare 驗證 | `cf_clearance` 綁 IP + UA，清了只會更慢；先查 QUIC 洩漏（見 `SETUP.md` 第 8 節） |
| 建議指紋瀏覽器 | 單一帳號不需要；額外偽裝會製造不一致訊號 |
| 建議「用多個帳號**輪替**以規避用量上限」 | 這通常是條款明文禁止的行為，且付款工具／電話／裝置會讓帳號被關聯；應引導至官方更高方案／企業合約／按量計費 API。⚠️ 注意區分：**「有多個帳號」本身不是問題**（家庭、公司、個人＋工作都很常見，共用一條線也正常），要指出的問題是「輪替以規避上限」這個行為 —— 詳見 `SETUP.md` 第 11.1 節 |
| 用猜測取代實測 | 所有決策以 `proxy-bench.ps1` 的實測數據為準（`loc` / `colo` / TTFB / 抖動／是否觸發驗證） |

## 修改設定後的必要動作

1. 用 `verge-mihomo -t -f <檔案>` 驗證（沒有錯誤才算通過）
2. 確認寫出的檔案是 **UTF-8 無 BOM**（有 BOM 會讓 mihomo YAML 解析失敗）
3. 提醒使用者：**在 Clash Verge 重新載入設定檔**，並在「連線」頁確認目標網域的
   鏈路是 `AI-Exit / <節點名>`（不是 `DIRECT`）

## 檔案角色速查

| 檔案 | 角色 |
|---|---|
| `SETUP.md` | 主要操作手冊（權威） |
| `DEVICES.md` | iOS / Android / 瀏覽器 / Claude Code / Codex |
| `install.ps1` | 自動安裝（解析 Verge 隨機 uid、渲染範本、備份、驗證） |
| `show-verge-map.ps1` | 印出 uid ↔ 角色對應（排錯） |
| `check-windows-locale.ps1` | Windows 地區／時區一致性檢查（`-Apply` 可修正） |
| `proxy-bench.ps1` | 代理評測（TTFB / loc / colo / ASN） |
| `configs/` | 所有範本（`__PROXY_*__` 佔位符） |
| `launchers/` | `codex-p.cmd` / `claude-p.cmd`（fail-closed 啟動器） |
