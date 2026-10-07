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
5. 依 `SETUP.md` 第 4.3～4.5 與第 6～7 節完成：
   - **服務與 TUN 只在需要覆蓋未知程式時才做**：`install.ps1 -InstallService`（**要提權**，
     安裝器在 `C:\Program Files\Clash Verge\resources\`）；`enable_tun_mode` 與
     `enable_dns_settings` **必須一起開**，然後重啟 GUI
   - 關閉瀏覽器 QUIC；Claude Code 的 `env` 區塊
   - 地區一致性：`check-windows-locale.ps1`（語言清單僅供參考，**絕對不要**用程式改它）
   - **一鍵驗收：`verify-exit.ps1` 必須以 `RESULT: all automated checks passed.` 結束**
6. **瀏覽器必須單獨驗證**（curl 不能代替）：`claude.ai/cdn-cgi/trace` 的 `ip=` 要是代理 IP。
7. 回報時附上原始輸出：`verify-exit.ps1` 的整張表、瀏覽器 trace 的 `ip=` 與 `loc=`、
   以及「連線」頁（或 mihomo 日誌行）中 `claude.ai` 的鏈路。
8. 開 TUN／服務之後：非提權無法停止核心、sidecar 日誌會停止更新（見 `SETUP.md` 第 14 節）——
   不要用「殺掉核心再重啟」驗證，也不要因為日誌乾淨就判定沒有洩漏。

## 不要做的事

| 不要 | 原因 |
|---|---|
| 把代理密碼、`local-secrets.psd1`、`mobile-clash.yaml` 提交進 git | 憑證外洩 |
| 把 `AI-Exit` 群組改成 `url-test` 或 `load-balance` | 會在使用中自動換節點 → 出口 IP 變動，直接破壞本設定包的目的 |
| 用「清 cookie」解決 Cloudflare 驗證 | `cf_clearance` 綁 IP + UA，清了只會更慢；先查 QUIC 洩漏（見 `SETUP.md` 第 8 節） |
| 建議指紋瀏覽器 | 單一帳號不需要；額外偽裝會製造不一致訊號 |
| 建議「用多個帳號**輪替**以規避用量上限」 | 這通常是條款明文禁止的行為，且付款工具／電話／裝置會讓帳號被關聯；應引導至官方更高方案／企業合約／按量計費 API。⚠️ 注意區分：**「有多個帳號」本身不是問題**（家庭、公司、個人＋工作都很常見，共用一條線也正常），要指出的問題是「輪替以規避上限」這個行為 —— 詳見 `SETUP.md` 第 11.1 節 |
| 用猜測取代實測 | 所有決策以 `proxy-bench.ps1` 的實測數據為準（`loc` / `colo` / TTFB / 抖動／是否觸發驗證） |
| **用程式改動使用者的語言清單**（`Set-WinUserLanguageList` / `New-WinUserLanguageList`） | 兩重風險：Windows 可能**靜默拒絕**（回報成功、registry 不變）；而且重建清單會**刪掉既有輸入法**（實測：使用者的倉頡 profile 被刪）。要加語言請使用者自己在設定介面加 |
| 用 `Stop-Process verge-mihomo` 驗證重啟 | 服務模式下會 `Access is denied`。要用 GUI 重新載入設定檔，否則你會以為重啟成功但核心沒換 |
| 在服務模式下把 sidecar 日誌當成「沒有洩漏」的證據 | 該日誌在服務模式下停止更新 → 只會得到假陰性。改用 GUI「連線」頁或 mihomo 的 info 日誌行 |
| 假設 `dns_config.yaml` 的 nameserver 正在生效 | 實測：生成的 `dns:` 區塊沒有任何 nameserver，`dns_config.yaml` 形同未使用。不要對不存在的風險做決策 |
| **用域名規則修「企業 OneDrive 卡在登入」** | 那是**擷取層**問題（AppContainer loopback 隔離），規則引擎只在連上代理後才執行 → 任何 `DOMAIN-*` 調整都無效。正解是 `fix-uwp-loopback.ps1 -Apply`（見 `SETUP.md` 第 14.2 節） |
| 用 `CheckNetIsolation ... -n=$var`（未加引號）就相信結果 | 必須透過 cmd.exe 帶 `-n="..."`；而且**印「成功」不等於註冊成功** —— 要用 `-s` 驗證「每筆 SID 不同」 |
| 把付款表單失敗當成需要「加規則塞進 AI 出口」 | 反過來：`Failed to load the payment form` 的實測根因是**出口拿不到 Stripe 的內容**（CONNECT 200 但 curl 000）。正解是把 Stripe 改成 **DIRECT**（範本預設已是），因為帳單國家由卡片決定、付款不需要 AI 出口 |
| 只用「CONNECT 成功」就判定一條線路可用 | CONNECT 只證明 TCP 可達。要驗證**內容**必須實際抓取（例如 `curl https://js.stripe.com/v3/` 要 200 且數百 KB）。這次就是靠內容層測試才找到真因 |

## 修改設定後的必要動作

1. 用 `verge-mihomo -t -f <檔案>` 驗證（沒有錯誤才算通過）
2. 確認寫出的檔案是 **UTF-8 無 BOM**（有 BOM 會讓 mihomo YAML 解析失敗）
3. **`.ps1` / `.cmd` 必須 ASCII-only** —— PowerShell 5.1 會把「無 BOM 的 UTF-8 腳本」當 ANSI 讀取，
   任何中文字面值都會變亂碼（實測踩過：正則裡的「拒絕存取」變成 `?摮?`，直接拋 `{x,y}` 剖析錯誤）。
   需要判斷本地化訊息時，**改用 exit code 或結構化特徵**，不要比對翻譯字串。
4. 提醒使用者：**在 Clash Verge 重新載入設定檔**，並在「連線」頁確認目標網域的
   鏈路是 `AI-Exit / <節點名>`（不是 `DIRECT`）

## 檔案角色速查

| 檔案 | 角色 |
|---|---|
| `SETUP.md` | 主要操作手冊（權威） |
| `DEVICES.md` | iOS / Android / 瀏覽器 / Claude Code / Codex |
| `install.ps1` | 自動安裝（解析 Verge 隨機 uid、渲染範本、備份、驗證） |
| `show-verge-map.ps1` | 印出 uid ↔ 角色對應（排錯） |
| `check-windows-locale.ps1` | Windows 地區／時區一致性檢查（`-Apply` 可修正；**永不碰語言清單**） |
| `verify-exit.ps1` | 一鍵驗收：TUN 覆蓋、分流、出口國家、HTTP 版本、DNS、地區 |
| `proxy-logger.py` | 只記錄不轉發的代理 —— 驗證某程式是否真的吃代理設定（不開 TUN 時必備） |
| `fix-uwp-loopback.ps1` | AppContainer loopback 豁免（企業 OneDrive 卡在登入的修法；`-Apply` / `-Delete`） |
| `proxy-bench.ps1` | 代理評測（TTFB / loc / colo / ASN） |
| `configs/` | 所有範本（`__PROXY_*__` 佔位符） |
| `launchers/` | `codex-p.cmd` / `claude-p.cmd`（fail-closed 啟動器） |
