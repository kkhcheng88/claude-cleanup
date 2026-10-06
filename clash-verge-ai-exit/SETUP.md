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

## 4. 快速開始（四步）

```powershell
# 0) 進入這個資料夾
cd clash-verge-ai-exit

# 1) 在 Clash Verge 建立一個「本機(Local)」設定檔，並打開一次增強編輯器
#    （Profiles → 新增 → 本機；然後開 Merge / Rules 各存一次，讓 Verge 建立 5 個檔案）

# 2) 完全關閉 Clash Verge（托盤 → 退出），然後執行：
powershell -ExecutionPolicy Bypass -File .\install.ps1 -IncludeMainProfile

# 3) 開啟 Clash Verge → Profiles → 點設定檔卡片重新載入

# 4) 關閉瀏覽器 QUIC（見第 6 節），然後跑第 7 節的驗證
```

也可把值放進本機檔案避免重複輸入：`-SecretsFile .\local-secrets.psd1`（格式見 `install.ps1` 開頭註解；該檔已在 `.gitignore` 內）。

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

它檢查六項：時區、住家位置（GeoId）、系統地區、使用者格式、語言清單（比對「語言＋地區」，所以 `zh-Hant-TW` 會被視為符合 `zh-TW`）、時鐘同步。

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
| 語言清單 | 一般使用者 | **需重新登入**（Windows 可能**靜默忽略**這次變更 —— 若檢查仍顯示 MISMATCH，請到「設定 → 時間與語言 → 語言與地區」手動加入） |

（腳本只**新增**缺少的語言，不會移除你原有的語言或改掉顯示語言；所有變更都能在 Windows 設定介面還原。）

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

## 8. 疑難排解（依症狀查）

| 症狀 | 真正原因 | 動作 |
|---|---|---|
| 服務回報**地區限制 / 無法使用**，但 curl 的 `loc=` 正確 | **QUIC 洩漏**：瀏覽器用 HTTP/3 從真實 IP 直連 | ① 確認 Rules 增強檔第一條是 `AND,((NETWORK,udp),(DST-PORT,443)),REJECT` ② 關閉瀏覽器 QUIC（6.1）③ 完全重開瀏覽器 |
| 一直卡在 `Just a moment...` 輪迴 | IP 信譽不足，或擴充功能干擾 | ① 向供應商換 IP（指定「本地 ISP ASN」）② 用無痕 + 關閉所有擴充測一次 ③ 確認 `challenges.cloudflare.com` 在規則內 |
| 第一次很慢、之後很快 | 正常：`cf_clearance` 建立中 | 讓它跑完，**不要清 cookie** |
| 剛剛還好好的，突然不行 | VPN / Stash / CMFA 掉了 → 走真實 IP | 檢查連線狀態；Android 開「封鎖沒有 VPN 的連線」 |
| 裝置的地區／時區與出口國家不一致 | 訊號互相矛盾 | Windows 跑 `check-windows-locale.ps1`；手機依 `DEVICES.md` 檢查地區／時區 |
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
├── install.ps1                   ★ 安裝腳本（解析 uid、渲染範本、備份、驗證）
├── check-windows-locale.ps1      ← Windows 地區／時區一致性檢查（-Apply 可修正）
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
