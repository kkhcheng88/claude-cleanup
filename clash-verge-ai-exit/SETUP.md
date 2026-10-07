# Clash Verge AI-Exit —把指定流量固定導向同一個專屬出口 IP

> 這份文件寫給「**沒有原始開發過程記憶的人或 AI agent**」。
> 照著做就能在一台新的 Windows 電腦上，複製出完全相同的設定。

---

## 1. 這套設定在做什麼

```
                    ┌─ Claude / Anthropic ─┐
你的裝置 ──► Clash ─┼─ OpenAI / ChatGPT  ─┼─► AI-Exit 群組 ─► 專屬靜態代理出口
（電腦/手機）        ├─ Cloudflare 驗證腳本 ┤        （select，不會自己換）
                    └─ Stripe 付款        ┘
        其他所有流量 ──────────────────────► MATCH,DIRECT（直連）
```

**技術目標有三個**：

1. **固定**：指定的服務流量永遠從**同一個出口 IP** 出去（適合需要穩定登入狀態的帳號）
2. **不洩漏**：沒有任何旁路（QUIC、系統 DoH、IPv6、VPN 斷線）能讓這些流量從其他路徑出去
3. **乾淨分流**：只有這些流量走代理，其餘直連 —— 延遲最低、也不浪費代理流量

---

## 2. 五條不可違背的原則

**本套件的預設組態（已定案，不需要使用者做技術選擇）**：

| 層 | 預設 | 為什麼是這個 |
|---|---|---|
| 擷取 | **系統代理 ON ＋ TUN ON（若服務可用）** | 系統代理讓核心停止時 fail-closed；TUN 補上「不吃代理設定的程式」 |
| QUIC | **mihomo 擋 UDP 443 ＋ 瀏覽器關 QUIC** | 兩處都擋 —— 少一處就會出現真實 IP 直連 |
| DNS | **`sniffer` ＋ `parse-pure-ip: true`** | 對抗瀏覽器／系統自帶的加密 DNS 繞過 |
| 分流 | **22 條 AI 網域 → `AI-Exit`（`select`）＋ `MATCH,DIRECT`** | 只有帳號相關流量走代理 |
| CLI | **`HTTPS_PROXY`（fail-closed）** | 代理不在時大聲失敗，而不是偷偷直連 |

`install.ps1` 會自動設定系統代理與代理守護；TUN 因為需要 Clash Verge 的系統服務，會在程式檢查後由你在 App 內開啟（服務不可用時**不要**為了 TUN 去安裝服務）。完整理由與失效模式分析見第 13 節。

| # | 原則 | 為什麼 |
|---|---|---|
| 1 | **出口群組必須是 `select`** | `url-test` / `load-balance` 會在使用中自動換節點 → 出口 IP 變動 |
| 2 | **出口 IP 要專屬且靜態** | 共用 IP 會被其他使用者的行為影響信譽；會輪替的 IP 讓登入狀態不穩定 |
| 3 | **QUIC / HTTP3（UDP 443）必須擋掉** | HTTP 代理無法轉發 UDP，而 QUIC 又比對不到域名規則 → 流量會從真實 IP 直連（**最常見的洩漏來源**） |
| 4 | **同一組帳號固定在同一條線** | 不要讓同一組帳號在網頁與 CLI 之間、或多條線之間跳動。注意：**多組帳號共用一條線本身沒有問題**（家庭、公司、宿舍的 NAT 後面本來就是這樣）—— 造成關聯的是付款工具、電話與裝置，不是 IP，詳見第 11.1 節 |
| 5 | **不要清 cookie、不要用無痕** | `cf_clearance` 綁 IP + User-Agent；清了就要重新驗證（偶發驗證是正常現象，不是故障） |

---

## 3. 前置需求

| 項目 | 說明 |
|---|---|
| Windows PC | 已安裝 **Clash Verge Rev 2.5.7+**（含 `verge-mihomo.exe`） |
| 代理 | 一個 **HTTP 代理**，供應商書面確認：**專屬**（單一用戶）＋ **租期內靜態不變** |
| 瀏覽器 | Edge / Chrome（要關閉 QUIC） |
| 手機／平板（可選） | iOS → **Stash**；Android → **Clash Meta for Android (CMFA)** |

⚠️ **代理憑證不要提交進 repo。** 範本使用 `__PROXY_PASSWORD__` 佔位符，由 `install.ps1` 執行時填入。

---

## 4. 新機完整流程（照著做即可，已含實測踩過的所有坑）

### 4.0 前置檢查（`install.ps1` 會自動印出）

| 檢查 | 為什麼 |
|---|---|
| **其他 VPN / 通道軟體**（Tailscale、WireGuard、OpenVPN…） | ⚠️ 最容易被忽略的變數：**exit node 一旦啟用就會接管全部流量並繞過 Clash**。確認它是登出狀態或沒有啟用 exit node |
| 使用中的網卡與**預設路由擁有者** | 確認沒有第二個東西在搶路由 |
| **Clash Verge 服務**是否已安裝 | TUN 的前置（見 4.3） |
| 是否以**系統管理員**身分執行 | 服務安裝與部分地區設定需要 |

### 4.1 建立本機設定檔

Clash Verge → Profiles → 新增 → **本機（Local）** → 打開一次增強編輯器（Merge / Script / Rules / Proxies / Groups **各存一次**），讓 Verge 產生它的 5 個隨機 uid 檔。

### 4.2 套用設定（Verge 必須完全關閉）

```powershell
cd clash-verge-ai-exit
powershell -ExecutionPolicy Bypass -File .\install.ps1 -IncludeMainProfile
```

代理密碼由你親自輸入（或用 `-SecretsFile .\local-secrets.psd1`）。這一步會寫入主設定檔 + 5 個增強檔 + `mobile-clash.yaml`，並自動設定 `enable_system_proxy` 與 `enable_proxy_guard`（fail-closed 的關鍵）。

### 4.3 服務與 TUN（想要「未知程式也覆蓋」就必須做）

在同一個**系統管理員** PowerShell 視窗：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -InstallService
```

服務安裝器位於 **`C:\Program Files\Clash Verge\resources\clash-verge-service-install.exe`** —— 在 `resources\` 子目錄，**不是**安裝根目錄（這個路徑很容易搞錯）。安裝後服務名為 `clash_verge_service`，狀態 `Running / Automatic`。

（同一個提權視窗可以順便做：`check-windows-locale.ps1 -Apply`、以及有企業／學校 OneDrive 時的 `fix-uwp-loopback.ps1 -Apply` —— 見第 14.2 節。）

### 4.4 重啟 Verge GUI

`verge.yaml` 的修改**只有重啟 GUI 才生效**。

想要 TUN 的話：**`enable_tun_mode` 與 `enable_dns_settings` 必須一起設為 true** —— Verge 只在 TUN 開啟時才注入 `dns:` 區塊，單獨開 DNS 會看起來像沒生效（見第 14 節）。

### 4.5 驗收

```powershell
powershell -ExecutionPolicy Bypass -File .\verify-exit.ps1
```

必須以 `RESULT: all automated checks passed.` 結束。逐項標準見第 7 節。

---

## 5. `install.ps1` 到底改了什麼

它會**自動解析 Clash Verge 的隨機 uid 檔名**（每台電腦都不一樣，所以不能硬編檔名），然後寫入：

| 角色 | 來源範本 | 寫到哪裡 |
|---|---|---|
| `merge` | `configs/enh-merge.sniffer.yaml` | Verge 的 Merge 增強檔 |
| `rules` | `configs/enh-rules.ai-exit.yaml` | Verge 的 Rules 增強檔 |
| `proxies` | `configs/enh-proxies.empty.yaml` | Verge 的 Proxies 增強檔（清空） |
| `groups` | `configs/enh-groups.empty.yaml` | Verge 的 Groups 增強檔（清空） |
| `script` | `configs/enh-script.empty.js` | Verge 的 Script 增強檔（清空） |
| `main` | `configs/main-profile.template.yaml` | **當前本機設定檔**（僅在加 `-IncludeMainProfile` 時） |
| — | `configs/mobile-clash.template.yaml` | 產生 `mobile-clash.yaml`（給手機／平板） |

**安全機制**：寫入前備份到 `backup-<時間戳>\`；`-IncludeMainProfile` 會拒絕在「非本機(Local)設定檔」上執行（避免覆蓋訂閱）；寫入後呼叫 `verge-mihomo -t` 驗證；所有檔案以 **UTF-8 無 BOM** 寫出（有 BOM 會讓 mihomo 的 YAML 解析失敗）。

**想知道哪個 uid 檔是什麼角色**：

```powershell
powershell -ExecutionPolicy Bypass -File .\show-verge-map.ps1
```

```
role      uid-file                        bytes
merge     mSMymKbjj6er.yaml                 847
rules     r4wn3k0RYL4e.yaml                3364
...
```

---

## 6. 三個一定要做的外部設定

### 6.1 關閉瀏覽器 QUIC

| 瀏覽器 | 位置 | 設定 |
|---|---|---|
| Edge | `edge://flags/#enable-quic` | **Disabled** |
| Chrome | `chrome://flags/#enable-quic` | **Disabled** |

改完**完全關閉瀏覽器再重開**（只開新分頁不夠 —— QUIC / Alt-Svc 有快取）。
⚠️ **瀏覽器大版本更新後要回來檢查**，flag 有時會被重置。

### 6.2 Claude Code 的逐工具代理（fail-closed）

編輯 `%USERPROFILE%\.claude\settings.json`，在既有的 `env` 物件加入：

```json
"HTTPS_PROXY": "http://127.0.0.1:7897",
"HTTP_PROXY":  "http://127.0.0.1:7897",
"NO_PROXY":    "localhost,127.0.0.1,::1"
```

效果：只有 Claude Code 走代理（`npm` / `git` / `pip` 完全不受影響）；Clash Verge 沒開時 **Claude Code 直接失敗**，而不是從非預期路徑連出去。

（Codex 沒有逐工具設定 → 用 `launchers\codex-p.cmd` 啟動。詳見 `DEVICES.md`。）

### 6.3 Windows 的地區／時區一致性

出口在目標國家，但裝置仍顯示別的時區／地區，就是一種**互相矛盾的訊號**。用附帶的腳本檢查（**唯讀，不會改任何設定**）：

```powershell
powershell -ExecutionPolicy Bypass -File .\check-windows-locale.ps1
```

它檢查**四項（列入判定）**：時區、住家位置（GeoId）、系統地區、使用者格式；
另外**兩項僅供參考**：語言清單、時鐘同步。

全部一致時的輸出：

```
OK        Time zone              current: Taipei Standard Time    expected: Taipei Standard Time
OK        Home location (GeoId)  current: 237                     expected: 237
OK        System locale          current: zh-TW                   expected: zh-TW
OK        User culture (formats) current: zh-TW                   expected: zh-TW
OK        Language list          current: zh-Hant-TW, en-US       expected: contains zh-TW
RESULT: all settings are consistent.
```

要修正（`-Apply`）：

```powershell
powershell -ExecutionPolicy Bypass -File .\check-windows-locale.ps1 -Apply
```

| 項目 | 權限 | 生效時機 |
|---|---|---|
| 時區 | 可能需要系統管理員（依 Windows 版本／原則而異；Win11 上有標準使用者成功的實測案例） | 立即 |
| 住家位置 | 一般使用者 | 立即 |
| 系統地區 | **系統管理員** | **需重開機** |
| 使用者格式 | 一般使用者 | 立即 |
| 語言清單 | — | **腳本不會改它**（見下方限制），僅供參考、不列入判定 |

⚠️ **語言清單的兩個 Windows 限制（已實測，不要在這裡浪費時間）**

1. `Set-WinUserLanguageList` 可以**回報成功卻什麼都沒改** —— registry
   `HKCU\Control Panel\International\User Profile\Languages` 維持原值、不拋任何錯，
   設定介面甚至可能把目標語言顯示成**灰色不可選**。這是 Windows 行為，不是腳本問題。
2. **用程式重建語言清單會刪掉輸入法**：新建的 `WinUserLanguage` 物件帶的是該語言的
   **預設輸入法**，重新送出整份清單會覆蓋使用者原有的 IME
   （實測案例：使用者的倉頡 profile 被靜默刪除）。

因此 `check-windows-locale.ps1` **完全不碰語言清單**：只回報、不列入 RESULT 判定、`-Apply` 也會跳過它。
要新增語言請用「設定 → 時間與語言 → 語言與地區」（會保留 IME）。

（腳本不會改動語言清單或顯示語言；時區、住家位置、系統地區、使用者格式的變更都能在 Windows 設定介面還原。）

---

## 7. 驗證（三關，缺一不可）

```powershell
# ① 目前出口 IP（ipinfo 被規則導向 AI-Exit）
curl.exe -x http://127.0.0.1:7897 -s -w "`n" https://ipinfo.io/ip

# ② Cloudflare 眼中的出口資訊
curl.exe -x http://127.0.0.1:7897 -s https://claude.ai/cdn-cgi/trace

# ③ 連通性
curl.exe -x http://127.0.0.1:7897 -s -o NUL -w "%{http_code}`n" https://claude.ai/
```

| 關卡 | 通過標準 |
|---|---|
| ① | 顯示**代理的 IP**（不是你的真實 IP） |
| ② | `ip=` 是代理 IP、`loc=` 是你預期的國家；`colo=` 是封包進入 Cloudflare 的位置（歐洲＝延遲高，亞洲＝快） |
| ③ | `200` / `302` / `403` 都算連得到（curl 沒有瀏覽器指紋，403 通常是 Cloudflare 挑戰頁） |

**④ 在 Clash Verge 的「連線」頁確認**：`claude.ai` 的「規則」欄是 `DomainSuffix(claude.ai)`、「鏈路」欄是 `AI-Exit / <節點名>`。**若是 `DIRECT`，就是洩漏。**

**⑤ 瀏覽器實測**：第一次開目標網站可能過一次 Cloudflare 挑戰（延遲高的線路會等比較久），**通過後第二次就應該免驗**。之後不要清 cookie。

---

### 7.1 一鍵驗收（推薦）

```powershell
powershell -ExecutionPolicy Bypass -File .\verify-exit.ps1
```

它會產出證據並直接給出 PASS／FAIL 表：

| 測試 | 通過標準 | 為什麼是這個測試 |
|---|---|---|
| **proxy path** | `ip=` 是代理 IP | 明確／系統代理真的通到出口 |
| **TUN coverage** | 用 `--noproxy "*"` **繞過所有代理設定**後，`ip=` 仍是代理 IP | ✅ **這是 TUN 唯一有效的驗收方式**（程式不吃代理設定仍能走出口） |
| **split tunnelling** | 非 AI 網域（`api.ipify.org`）仍是**真實 IP** | 證明沒有過度代理（`MATCH,DIRECT` 生效） |
| **exit country** | `loc=` 是目標國家 | Cloudflare 眼中出口在哪一國 |
| **no HTTP/3 via proxy** | `http_version` 不是 `3` | 沒有走 QUIC 旁路 |
| **DNS (fake-ip)** | `claude.ai` 解析為 `198.18.x` | fake-ip 運作中 |
| **regional check** | `all settings are consistent` | 裝置與出口國家一致 |

### 7.2 完整驗收清單（缺一不可）

| # | 標準 | 證據 |
|---|---|---|
| a | 繞過所有代理設定仍為代理 IP | `verify-exit.ps1` 的 TUN coverage = PASS |
| b | 經系統／明確代理為代理 IP | proxy path = PASS |
| c | 非 AI 網域仍為真實 IP | split tunnelling = PASS |
| d | 所有域名解析成功（fake-ip `198.18.x`） | DNS = PASS |
| e | **瀏覽器** `claude.ai/cdn-cgi/trace`：`ip=` 代理、`loc=` 正確、`http/2`（非 `http/3`） | 手動（**curl 不能代替瀏覽器**） |
| f | 地區檢查一致（語言清單不阻擋判定） | `check-windows-locale.ps1` |
| g | fail-closed：核心停止時**大聲失敗**而非靜默直連 | 見第 14 節 |

### 7.3 「沒有洩漏」的權威證據

優先順序：**mihomo 的 info 日誌行 ＞ GUI 連線頁 ＞ 猜測**。日誌行同時給出程序名、命中規則、群組與節點：

```
[TCP] 127.0.0.1:58593(msedge.exe) --> claude.ai:443
      match DomainKeyword(claude) using AI-Exit[ProxySeller-TW1]
```

看到 `using DIRECT` 就是洩漏。⚠️ 服務模式下 sidecar 日誌會停止更新（見第 14 節）。

## 8. 疑難排解（依症狀查）

| 症狀 | 真正原因 | 動作 |
|---|---|---|
| 服務回報**地區限制 / 無法使用**，但 curl 的 `loc=` 正確 | **QUIC 洩漏**：瀏覽器用 HTTP/3 從真實 IP 直連 | ① 確認 Rules 增強檔第一條是 `AND,((NETWORK,udp),(DST-PORT,443)),REJECT` ② 關閉瀏覽器 QUIC（6.1）③ 完全重開瀏覽器 |
| 一直卡在 `Just a moment...` 輪迴 | IP 信譽不足，或擴充功能干擾 | ① 向供應商換 IP（指定「本地 ISP ASN」）② 用無痕 + 關閉所有擴充測一次 ③ 確認 `challenges.cloudflare.com` 在規則內 |
| 第一次很慢、之後很快 | 正常：`cf_clearance` 建立中 | 讓它跑完，**不要清 cookie** |
| 剛剛還好好的，突然不行 | VPN / Stash / CMFA 掉了 → 走真實 IP | 檢查連線狀態；Android 開「封鎖沒有 VPN 的連線」 |
| 裝置的地區／時區與出口國家不一致 | 訊號互相矛盾 | Windows 跑 `check-windows-locale.ps1`；手機依 `DEVICES.md` 檢查地區／時區 |
| 服務模式下 `Stop-Process verge-mihomo` 被拒（`Access is denied`） | 核心改由特權服務管理 | 不要用「殺掉核心再重啟」驗證 —— 改用 GUI 重新載入設定檔（見第 14 節） |
| `logs\sidecar\sidecar_latest.log` 不再更新 | 服務模式的日誌位置不同，`C:\ProgramData\clash-verge-service` 一般權限讀不到 | 改用 Verge「連線」頁。「用日誌確認分流」在服務模式下會**靜默失效**，容易誤判成「沒有流量／沒有洩漏」 |
| 想用 HTTP API 查 `/connections` 卻連不上 9097 | 生成的 `external-controller` 是**空字串**，API 走 **named pipe** | 用 GUI「連線」頁，或在 Verge 設定中明確開啟 External Controller |
| 單獨開 `enable_dns_settings` 看起來沒生效 | Verge **只在 TUN 開啟時**才注入 `dns:` 區塊 | `enable_tun_mode` 與 `enable_dns_settings` **一起開**，然後重啟 GUI |
| 以為 `dns_config.yaml` 的 nameserver 在生效 | 生成的 `dns:` 只有 5 行（enable / ipv6 / enhanced-mode / fake-ip-range ×2），**沒有任何 nameserver** | 別對不存在的風險做決策：此版本 `dns_config.yaml` 形同未使用 |
| 第一次連新出口出現 TLS 中斷（`SSL UNEXPECTED_EOF_WHILE_READING`） | 出口暖機中 | **重測 2–3 次再判斷**，不要立刻當成故障 |
| 裝過 Tailscale / WireGuard 等 | exit node 或 subnet route 會接管路由、繞過 Clash | 事前確認已登出或未啟用 exit node（見 4.0） |
| `Get-Process` 顯示 Verge 沒在執行，但其實在跑 | **受限的 shell 看不到其他程序**（實測踩過：因此改了 `verge.yaml` 卻完全沒生效） | 也檢查 `logs\latest.log` 的修改時間；`install.ps1` 現在會用日誌時間做第二個判斷。**改 `verge.yaml` 前務必確認 Verge 真的關閉，改完要重啟 GUI**（C2） |
| 驗收腳本顯示 `no HTTP/3 via proxy = INFO` | **此 shell 沒有 HTTPS 出口**（HTTP 可用、HTTPS 回空） | `verify-exit.ps1` 的 IP／出口國家測試已改用 HTTP，所以仍可判定；HTTP/3 只能在有 HTTPS 的 shell 測 |
| **企業／學校 OneDrive 永遠卡在「正在登入」**（個人 OneDrive 正常；**關掉 Clash 就正常**） | **AppContainer loopback 隔離**：UWP 沙盒預設禁止連 `127.0.0.1`，而企業登入走的 WAM broker（`Microsoft.AAD.BrokerPlugin`）正是 AppContainer → 連不到本地代理 → 無聲卡住。**擷取層問題，加任何域名規則都無效** | 系統管理員跑 `fix-uwp-loopback.ps1 -Apply`，然後登出／重開。詳見第 14.2 節 |
| **付款表單載入失敗**（`Failed to load the payment form` / `Failed to load Stripe.js`，瀏覽器與 Claude Desktop 都一樣） | 出口**連得上** Stripe 但**拿不到內容**：TCP 隧道成功、TLS／內容階段失敗（實測 `curl https://js.stripe.com/v3/` = **`000` / 0 bytes / 5 s**。⚠️ 注意：**mihomo 的 `CONNECT` 200 是樂觀回應** —— 對不存在的域名與 `192.0.2.1` 也回 200，不可當作可達性證據；只有實際抓取內容才算）。付款**不需要** AI 出口 —— 帳單國家由**卡片**決定，不是 IP | 把 Stripe 改成直連（本套件範本預設已是 `DIRECT`）：`DOMAIN-SUFFIX,stripe.com,DIRECT` + `DOMAIN-SUFFIX,stripe.network,DIRECT` → 重新載入設定檔。診斷：`curl.exe -x http://127.0.0.1:7897 -s -o NUL -w "%{http_code} %{size_download}" https://js.stripe.com/v3/`（正常 = 200 且數百 KB；**修正後實測 = `200` / 1,127,141 bytes / 0.17 s**） |
| 設定檔載入失敗 | YAML 語法 / BOM / 規則引用不存在的群組名 | 用 `verge-mihomo -t -f <檔案>` 驗證；確認檔案是 UTF-8 **無 BOM** |
| 規則沒生效（全部 DIRECT） | 增強檔沒被套用 / 沒重新載入設定檔 | Verge → Profiles → 點設定檔卡片重新載入；用 `show-verge-map.ps1` 確認檔案對應 |
| 改了 `ipv6` 卻沒生效 | **Verge 會用自己的設定覆蓋頂層鍵**（`ipv6`、`unified-delay`、`dns`、`tun`…） | 別在 Merge 裡改這些；用 Verge 的設定頁 |
| 增強檔名看起來是亂碼 | Verge 用**隨機 uid** 當檔名，且每台電腦不同 | 正常。用 `show-verge-map.ps1` 看對應 |

---

## 9. 維護與紀律

| 情境 | 做法 |
|---|---|
| **想換出口線路** | 只有在「要換線」時才手動切 `AI-Exit`；切了就是一次出口 IP 變更 |
| **絕不要做的事** | 把 `AI-Exit` 切成 `DIRECT`、把群組改成 `url-test`、清目標網站 cookie、用無痕當日常 |
| **換代理密碼** | 改供應商後台 → 更新**三個地方**：Verge 主設定檔、repo 工作副本、`mobile-clash.yaml` → 重新載入 + 重新匯入到手機 |
| **換 IP** | 換了要重建 `cf_clearance`（一次性）；先確認新 IP 的 `loc` 與延遲符合預期 |
| **Verge / 瀏覽器更新後** | 檢查 QUIC flag 是否被重置、設定檔是否仍正常載入 |

**代理評測工具**：`proxy-bench.ps1`（量 TTFB / `loc` / `colo` / ASN，並與直連對照）

```powershell
powershell -ExecutionPolicy Bypass -File .\proxy-bench.ps1 -Proxy "http://USER:PASS@HOST:PORT" -IncludeDirect
```

---

## 10. 實測案例：為什麼「資料庫評分」不能取代實測

同一台電腦、同一個目標、兩個代理供應商：

| 供應商 | `loc` | `colo` | HTTPS TTFB | 抖動 | Cloudflare 挑戰 |
|---|---|---|---|---|---|
| 供應商 A（已停用） | 正確 | **CDG（巴黎）** | 2.17 s | ±0.6 s | **每次都要驗證** |
| 供應商 B（現役） | 正確 | BCN | **0.95 s** | **±0.006 s** | **零挑戰** |

**結論**：
- `loc` 對了不代表體驗好 —— **`colo` 與 TTFB 才反映路由品質**（A 的 IP 註冊在目標國家，流量卻繞歐洲）。
- 某些資料庫會把 IP 標成 `hosting`、或顯示與預期不同的網段登記人，但**實測 Cloudflare 零挑戰** → **以實測行為為準**。
- 選代理時要向供應商講清楚：**「專屬 + 靜態 + 目標國家的本地 ISP ASN」**。

---

## 11. 前提與界線

這套設定只做一件事：**把指定流量固定導向你自己擁有的代理出口，並確保沒有旁路**。它不涉及瀏覽器指紋偽裝、也不處理付款或帳單驗證。

使用前請自行確認：

1. 你使用的服務條款是否允許你在所在地區使用；
2. 你的代理位於你想呈現的國家；
3. 付款方式與帳單國家符合該服務的要求（這通常是比 IP 更硬的門檻）；
4. 你的帳號安排是否符合條款 —— 見 11.1。

### 11.1 「有多個帳號」與「用多個帳號規避用量上限」是兩件事

**多個帳號本身不是問題。** 家庭、公司、宿舍、公共 Wi-Fi 的 NAT 後面本來就有多個帳號共用一個 IP；
同一個人同時擁有「工作」與「個人」帳號也很常見。單靠 IP，服務方無法區分「N 個人」與「1 個人有 N 個帳號」。

**問題出在「用多個帳號輪替來規避用量上限」**（例如「一個的額度用完就換下一個」）。這通常是條款明文禁止的行為，
而且它同時是一種**行為特徵**，與你使用幾個 IP 無關。

會讓多個帳號被視為同一來源的訊號（依強度排序）：

| 強度 | 訊號 | 說明 |
|---|---|---|
| 最強 | **付款工具** | 同一張卡／同一個商店帳號 → 直接關聯，換幾個 IP 都無效 |
| 強 | 電話 / Email | 同一支號碼註冊多個帳號 |
| 強 | 裝置與系統層 | 同一台機器；`MachineGuid`、電腦名、使用者名稱等**不會因為刪除本機檔案而改變** |
| 中 | 行為模式 | 「額度一用完就切換帳號」的規律 |
| 弱 | 網路 IP | 最弱，而且共用本身很正常（家用 NAT、公司網路、宿舍） |

**實務結論**：

- 帳號屬於**不同的人**（家人、同事）→ 共用一條線（含專屬代理 IP）沒有問題；每個人自然會有自己的付款與電話。
- 你是**同一人**且需要更多容量 → 癥結在**條款與付款關聯**，不在 IP。正規做法是升級更高階方案、
  團隊使用 Team 席位、或走企業合約／按量計費 API（Bedrock、Vertex）。
- **不要**把「清除本機狀態 + 換 IP」當成讓新帳號看不出關聯的手段 —— 付款、電話與硬體層訊號都不會被本機清理改變。

---

## 12. 檔案清單

```
clash-verge-ai-exit/
├── SETUP.md                      ← 本文件（主要操作手冊）
├── DEVICES.md                    ← iOS / Android / 瀏覽器 / Claude Code / Codex
├── AGENTS.md                     ← 給 AI agent 的入口指示
├── install.ps1                   ★ 安裝腳本（前置檢查、解析 uid、渲染範本、備份、驗證）
├── verify-exit.ps1               ★ 一鍵驗收（TUN 覆蓋、分流、出口國家、HTTP 版本、DNS、地區）
├── check-windows-locale.ps1      ← Windows 地區／時區一致性檢查（-Apply 可修正）
├── proxy-logger.py               ← 只記錄不轉發的代理：驗證某程式是否真的吃代理設定
├── fix-uwp-loopback.ps1          ← AppContainer loopback 豁免（企業 OneDrive 卡登入的修法）
├── show-verge-map.ps1            ← 印出 uid ↔ 角色對應
├── proxy-bench.ps1               ← 代理評測
├── .gitignore                    ← 排除 local-secrets.psd1 / mobile-clash.yaml / backup-*
├── configs/
│   ├── main-profile.template.yaml
│   ├── enh-merge.sniffer.yaml
│   ├── enh-rules.ai-exit.yaml
│   ├── enh-proxies.empty.yaml
│   ├── enh-groups.empty.yaml
│   ├── enh-script.empty.js
│   └── mobile-clash.template.yaml
└── launchers/
    ├── codex-p.cmd
    └── claude-p.cmd
```

---

## 13. 為什麼是這組預設（失效模式分析）

### 13.1 「兩種洩漏」必須分開看

| 模式 | 發生什麼 | 怎麼解 |
|---|---|---|
| **A：規則沒命中** | TUN 正常運作，但某條流（例如 QUIC／UDP 443）比對不到域名規則 → 落到 `MATCH,DIRECT` → 用真實 IP 出去 | 擋 UDP 443 ＋ 關瀏覽器 QUIC ＋ sniffer |
| **B：核心停止** | TUN 網卡消失 → 全機流量回到實體網卡 → 全部直連（**沒有錯誤訊息**） | 系統代理 ＋ `HTTPS_PROXY`：讓你在意的程式**大聲失敗** |

這兩者常被混為一談：A 是**設定漏洞**，B 是**失效模式**。修 A 的方法不能修 B，反之亦然。

### 13.2 擷取層與分流層是獨立的

TUN 只決定「**誰被抓進來**」與「**掛掉時怎麼失敗**」；**規則永遠照樣運作**。
所以 `TUN + MATCH,DIRECT` 完全可以並存 —— 本套件就是這樣：AI 網域走代理，其餘直連。

| 設定 | 核心正常 | 核心停止 | 覆蓋面 |
|---|---|---|---|
| 純 TUN | ✅ | ❌ 全部靜默直連 | 全部程式 |
| 純系統代理 | ✅ | ✅ 瀏覽器連不上 | 瀏覽器 ＋ WinINET 程式 |
| 純 `HTTPS_PROXY` | ✅ | ✅ CLI 連不上 | 有設定的 CLI |
| **系統代理 ＋ TUN ＋ `HTTPS_PROXY`**（本套件預設） | ✅ | ✅ 在意的程式全部失敗，只剩「不吃任何代理設定的非 AI 程式」會直連 | 全部 ＋ fail-closed |

### 13.3 什麼情況才考慮「不開 TUN」

只有一種：**你不想在這台機器安裝 Clash Verge 的系統服務／驅動**（例如機器上有受監管的資料）。

此時「系統代理 ＋ `HTTPS_PROXY` ＋ 關瀏覽器 QUIC」對 **AI 流量**已經足夠 —— 因為那些流量都來自你能設定的程式（瀏覽器、CLI）。
代價是：**你必須逐一驗證每個會碰 AI 服務的程式**（含桌面 App），否則它會靜默直連；而且失去「規則擋 UDP」這層保護（UDP 不會進 mihomo）。

### 13.4 自己驗證模式 B（30 秒，安全）

1. 完全退出 Clash Verge（托盤 → 退出）
2. 瀏覽器開 `https://claude.ai/cdn-cgi/trace`
3. **正常退出**時 Verge 會還原系統代理 → 會顯示真實 IP（這是預期的，因為是你主動關掉）
4. 想測**崩潰**情境：用工作管理員**強制結束** Verge 程序 → 此時系統代理仍指向死埠 → 瀏覽器應該**連不上**，而不是走真實 IP
5. 重新啟動 Verge → 重新載入設定檔

### 13.5 三個常見誤解（都被實測推翻過）

| 誤解 | 事實 |
|---|---|
| 「TUN 和系統代理是二選一」 | **是疊加**：TUN（覆蓋面）＋ 系統代理／`HTTPS_PROXY`（fail-closed）＋ QUIC 阻擋。只有在「用 TUN **取代**系統代理」時才會犧牲大聲失敗 |
| 「TUN + 規則比較安全」 | **規則層不會因 TUN 而改善**。TUN 只改變「誰被抓進來」與「掛掉時怎麼失敗」；而且 TUN 開著仍可能發生模式 A 洩漏（實測：`http/3` + `loc=HK`） |
| 「不開 TUN 一定比較差」 | 不開 TUN 的正當理由是**不想裝系統服務／驅動**（見 13.3）；反之，為了「未知程式也覆蓋」而選擇開 TUN 同樣合理。**重點是決策有據，不是預設哪一邊** |

---

## 14. 服務模式與可觀測性（開 TUN 之後一定要知道）

啟用 Clash Verge 服務（TUN 的前置）後，**核心改由特權服務管理**，行為有四個變化：

| 變化 | 影響 | 你該怎麼做 |
|---|---|---|
| **C1：非提權行程無法停止核心** | `Stop-Process verge-mihomo` → `Access is denied`。「殺掉核心再重啟」這類驗證**全部失效** | 用 GUI 重新載入設定檔。不要以為自己重啟成功了 —— 其實核心沒換 |
| **C2：`verge.yaml` 修改要重啟 GUI 才生效** | 直接改檔案是可行的自動化路徑，但不會即時生效 | 改完 → 重啟 GUI |
| **C3：sidecar 日誌停止更新** | `%APPDATA%\...\logs\sidecar\sidecar_latest.log` 不再寫入；`C:\ProgramData\clash-verge-service` 一般權限讀不到 | **改用 GUI「連線」頁**。誤用日誌會得到「看起來很乾淨」的假結論 |
| **C4：`external-controller` 是空字串** | 9097 沒有監聽，HTTP API 全部失效（API 走 named pipe，受限沙盒不可存取） | 用 GUI「連線」頁；或在 Verge 設定中明確開啟 External Controller |

### 14.1 DNS 的兩件事（實測）

- **`enable_dns_settings` 只有在 `enable_tun_mode` 也開啟時才生效** —— Verge 只在 TUN 開啟時注入 `dns:` 區塊。單獨開 DNS 時生成的設定完全沒有 `dns:`，`:53` 也沒監聽，看起來像沒生效。
- **`dns_config.yaml` 在多數情況下沒有被套用**：即使啟用，生成的 `dns:` 也只有 5 行（`enable` / `ipv6` / `enhanced-mode` / `fake-ip-range` / `fake-ip-range6`），**沒有任何 nameserver**，`dns_config.yaml` 裡的 DoH 供應商全部缺席。**不要對不存在的風險做決策。**

### 14.2 AppContainer loopback 隔離（企業 OneDrive 卡在登入）

**症狀**：企業／學校 OneDrive 永遠卡在「正在登入」、**沒有錯誤碼**；個人 OneDrive 正常；**關掉 Clash 就正常** —— 最後這點最容易讓人誤判成 IP／地區問題，但認證端點其實全部可達（HTTP 200）。

**根因**：Windows 預設禁止 **AppContainer（UWP 沙盒）** 連線 loopback（`127.0.0.1`）。企業登入走 WAM broker `Microsoft.AAD.BrokerPlugin`，那是 AppContainer，必須連 `127.0.0.1:7897` 才能走代理 → 被沙盒拒絕 → 無聲卡住。個人 OneDrive 走不同路徑，所以不受影響。（決定性證據：該機器的豁免清單**原本是空的**。）

**為什麼「加規則」永遠無效**：規則引擎只在**連上代理之後**才執行；AppContainer 根本連不上代理。`DOMAIN-*→DIRECT`、改導向群組、IPv4-only DNS 全部無效 —— **這是擷取層問題，不是路由層問題**。

**修法**（需系統管理員）：

```powershell
powershell -ExecutionPolicy Bypass -File .\fix-uwp-loopback.ps1 -Apply
```

它會：列出目前豁免 → **只對實際已安裝**的套件加豁免（關鍵是 `Microsoft.AAD.BrokerPlugin`，其餘涵蓋 AccountsControl / CloudExperienceHost / OneDriveSync / Store / OfficeHub / XboxIdentityProvider / CredDialogHost / Win32WebViewHost）→ **重新讀取清單驗證**（不信任「成功」訊息）→ 完成後需**登出或重開機**再試登入。

**兩個會讓人繞遠路的陷阱**

1. `CheckNetIsolation` 必須**透過 cmd.exe 並帶引號的 `-n="..."`**；直接從 PowerShell 傳 `-n=$p` 會回「無效的參數」。分辨法：**正確語法在缺權限時回「拒絕存取」，錯誤語法回「無效的參數」**。
2. **印「成功」不等於註冊成功**：語法錯誤時 9 個都印成功，實際只註冊 1 筆，顯示成 `AppContainer NOT FOUND` 且 **SID 全部相同**。一定要用 `-s` 驗證：名稱欄須為套件名、**每筆 SID 須不同**。腳本會自動做這個檢查並在發現時警告。

**與預設組態的關係**：我們預設開啟**系統代理**，這正是觸發條件。若你有企業／學校 OneDrive，這個豁免就是必要的（可用 `-Delete` 還原）。

**已排除的假設（不要在新機器重測）**：端點不可達 ❌／IPv6 問題 ❌／`MATCH,DIRECT` 導致走錯出口 ❌／`dns_config.yaml` 的 CN nameserver 洩漏 ❌（此版本產生的 `dns:` 區塊根本沒有 nameserver）／Conditional Access 地區限制 ❌（加豁免後，同一出口就能登入成功）。

### 14.3 憑證的實情

生成的 runtime config（`clash-verge.yaml`）**含明文代理密碼** —— 這是 mihomo 的必然，不要以為密碼只存在於 `local-secrets.psd1`。
`.gitignore` 已排除 `local-secrets.psd1` 與 `mobile-clash.yaml`（可用 `git ls-files` 驗證）。
