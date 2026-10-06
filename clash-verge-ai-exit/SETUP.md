# Clash Verge AI-Exit — 讓 Claude / ChatGPT 帳號永遠從同一個乾淨 IP 出去

> 這份文件是寫給「**沒有這段對話記憶的人或 AI agent**」看的。
> 照著做就能在一台新的 Windows 電腦上，複製出完全相同的設定。

---

## 1. 這套東西在做什麼

```
                    ┌─ Claude / Anthropic ─┐
你的裝置 ──► Clash ─┼─ OpenAI / ChatGPT  ─┼─► AI-Exit 群組 ─► 專屬固定 IP（支援地區）
（電腦/手機）        ├─ Cloudflare 驗證腳本 ┤        （select，不會自己換）
                    └─ Stripe 付款        ┘
        其他所有流量 ──────────────────────► MATCH,DIRECT（直連）
```

**目標只有一個**：讓 AI 服務帳號在整個生命週期裡，**永遠看到同一個 IP、同一個國家**，並且不洩漏真實 IP。

**為什麼不全部走代理？** 只有帳號相關流量需要「固定身分」；其他流量直連最快、也省代理流量。

---

## 2. 五條不可違背的原則

| # | 原則 | 為什麼 |
|---|---|---|
| 1 | **出口必須是 `select` 群組** | `url-test` / `load-balance` 會在使用中自動換節點 → 帳號看到新 IP |
| 2 | **出口 IP 要專屬且靜態** | 共用 IP 會被別人的濫用行為連坐；會輪替的 IP 讓帳號身分不穩定 |
| 3 | **QUIC / HTTP3（UDP 443）必須擋掉** | HTTP 代理無法轉發 UDP，而 QUIC 又比對不到域名規則 → 瀏覽器會用真實 IP 直連（**這是「不支援你的地區」最常見的真因**） |
| 4 | **一個帳號 = 一條線 = 一個 IP** | 不要網頁走一條、CLI 走另一條；不要把同一個帳號綁兩顆 IP |
| 5 | **不要清 cookie、不要用無痕** | `cf_clearance` 綁 IP + User-Agent，清了就要重驗（偶發驗證不是故障） |

---

## 3. 前置需求

| 項目 | 說明 |
|---|---|
| Windows PC | 已安裝 **Clash Verge Rev 2.5.7+**（含 `verge-mihomo.exe`） |
| 代理 | 一個**支援地區**（例如台灣）的 **HTTP 代理**，且供應商書面確認：**專屬 + 租期內靜態不變** |
| 瀏覽器 | Edge / Chrome（要關閉 QUIC） |
| 手機／平板（可選） | iOS → **Stash**；Android → **Clash Meta for Android (CMFA)** |

⚠️ **代理憑證不要提交進 repo。** 本文件的範本使用 `__PROXY_PASSWORD__` 這類佔位符，由 `install.ps1` 在執行時填入。

---

## 4. 快速開始（四步）

```powershell
# 0) 複製 repo / 進入這個資料夾
cd clash-verge-ai-exit

# 1) 在 Clash Verge 建立一個「本機(Local)」設定檔，並打開一次增強編輯器
#    （Profiles → 新增 → 本機；然後開增強/Merge、Rules... 各存一次，讓 Verge 建立 5 個檔案）

# 2) 完全關閉 Clash Verge（托盤 → 退出），然後執行：
powershell -ExecutionPolicy Bypass -File .\install.ps1 -IncludeMainProfile

# 3) 開啟 Clash Verge → Profiles → 點設定檔卡片重新載入

# 4) 關閉瀏覽器 QUIC（見第 6 節），然後跑第 7 節的驗證
```

（也可以把值放進本機檔案，避免每次輸入：`-SecretsFile .\local-secrets.psd1`，格式見 `install.ps1` 開頭註解；該檔已在 `.gitignore` 內。）

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

輸出範例：

```
role      uid-file                        bytes
merge     mSMymKbjj6er.yaml                 847
rules     r4wn3k0RYL4e.yaml                3364
...
```

---

## 6. 一定要做的兩個外部設定

### 6.1 關閉瀏覽器 QUIC（否則整套失效）

| 瀏覽器 | 位置 | 設定 |
|---|---|---|
| Edge | `edge://flags/#enable-quic` | **Disabled** |
| Chrome | `chrome://flags/#enable-quic` | **Disabled** |

改完**完全關閉瀏覽器再重開**（只開新分頁不夠 —— QUIC / Alt-Svc 有快取）。
⚠️ **瀏覽器大版本更新後要回來檢查**，flag 有時會被重置。

### 6.2 Claude Code 的逐工具代理（fail-closed）

編輯 `%USERPROFILE%\.claude\settings.json`，在既有的 `env` 物件裡加入：

```json
"HTTPS_PROXY": "http://127.0.0.1:7897",
"HTTP_PROXY":  "http://127.0.0.1:7897",
"NO_PROXY":    "localhost,127.0.0.1,::1"
```

效果：只有 Claude Code 走代理（`npm` / `git` / `pip` 完全不受影響）；Clash Verge 沒開時 **Claude Code 直接失敗**，而不是偷偷用真實 IP 連出去。

（Codex 沒有逐工具設定 → 用 `launchers\codex-p.cmd` 啟動。詳見 `DEVICES.md`。）

---

## 7. 驗證（三關，缺一不可）

```powershell
# ① 出口 IP（ipinfo 被規則導向 AI-Exit，所以這行測的就是 AI 線路）
curl.exe -x http://127.0.0.1:7897 -s -w "`n" https://ipinfo.io/ip

# ② Cloudflare 眼中的國家（最關鍵）
curl.exe -x http://127.0.0.1:7897 -s https://claude.ai/cdn-cgi/trace

# ③ 連通性
curl.exe -x http://127.0.0.1:7897 -s -o NUL -w "%{http_code}`n" https://claude.ai/
```

| 關卡 | 通過標準 |
|---|---|
| ① | 顯示**代理的 IP**（不是你的真實 IP） |
| ② | `loc=` 是**支援的國家**（例如 `TW`）；`colo=` 是封包進入 Cloudflare 的位置（歐洲＝延遲高，亞洲＝快） |
| ③ | `200` / `302` / `403` 都算連得到（curl 沒有瀏覽器指紋，403 = Cloudflare 挑戰頁，正常） |

**④ 在 Clash Verge 的「連線」頁確認**：`claude.ai` 的「規則」欄是 `DomainSuffix(claude.ai)`、「鏈路」欄是 `AI-Exit / <節點名>`。**若是 `DIRECT`，就是洩漏。**

**⑤ 瀏覽器實測**：第一次開 `claude.ai` 可能過一次 Cloudflare 挑戰（尤其延遲高的線路會等比較久），**通過後第二次就應該免驗**。之後不要清 cookie。

---

## 8. 疑難排解（依症狀查）

| 症狀 | 真正原因 | 動作 |
|---|---|---|
| 瀏覽器顯示「**不支援你的地區**」，但 curl 的 `loc=TW` | **QUIC 洩漏**：瀏覽器用 HTTP/3 直連真實 IP | ① 確認 Rules 增強檔第一條是 `AND,((NETWORK,udp),(DST-PORT,443)),REJECT` ② 關閉瀏覽器 QUIC（6.1）③ 完全重開瀏覽器 |
| 一直卡在 `Just a moment...` 輪迴 | IP 信譽差，或擴充功能干擾 | ① 換 IP（向供應商要求，指定「本地 ISP ASN」）② 用無痕 + 關掉所有擴充測一次 ③ 確認 `challenges.cloudflare.com` 也在規則內 |
| 第一次很慢、之後很快 | 正常：`cf_clearance` 建立中 | 讓它跑完，**不要清 cookie** |
| 剛剛還好好的，突然不行 | VPN/Stash/CMFA 掉了 → 走真實 IP | 檢查連線狀態；Android 開「封鎖沒有 VPN 的連線」 |
| 設定檔載入失敗 | YAML 語法 / BOM / 規則引用不存在的群組名 | 用 `verge-mihomo -t -f <檔案>` 驗證；確認檔案是 UTF-8 **無 BOM** |
| 規則沒生效（全部 DIRECT） | 增強檔沒被套用 / 沒重新載入設定檔 | Verge → Profiles → 點設定檔卡片重新載入；用 `show-verge-map.ps1` 確認檔案對應 |
| 改了 `ipv6` 卻沒生效 | **Verge 會用自己的設定覆蓋頂層鍵**（`ipv6`、`unified-delay`、`dns`、`tun`…） | 別在 Merge 裡改這些；用 Verge 的設定頁 |
| 增強檔名看起來是亂碼 | Verge 用**隨機 uid** 當檔名，且每台電腦不同 | 正常。用 `show-verge-map.ps1` 看對應 |

---

## 9. 維護與紀律

| 情境 | 做法 |
|---|---|
| **想換出口線路** | 只有在「要換線」時才手動切 `AI-Exit`，切了就是一次 IP 變更（帳號會看到） |
| **絕不要做的事** | 把 `AI-Exit` 切成 `DIRECT`、把群組改成 `url-test`、清 `claude.ai` cookie、用無痕當日常 |
| **換代理密碼** | 改供應商後台 → 更新**三個地方**：Verge 主設定檔、repo 的工作副本、`mobile-clash.yaml` → 重新載入 + 重新匯入到手機 |
| **換 IP** | 換了就要重建 `cf_clearance`（一次性）；Pass= 先確認 `loc` 仍是支援國家 |
| **Verge / 瀏覽器更新後** | 檢查 QUIC flag 是否被重置、設定檔是否仍正常載入 |

**代理評測工具**：`proxy-bench.ps1`（量 TTFB / `loc` / `colo` / ASN 並與直連對照）

```powershell
powershell -ExecutionPolicy Bypass -File .\proxy-bench.ps1 -Proxy "http://USER:PASS@HOST:PORT" -IncludeDirect
```

---

## 10. 實測案例（為什麼「資料庫評分」不是重點）

同一台電腦、同一個目標、兩個供應商：

| 供應商 | `loc` | `colo` | HTTPS TTFB | 抖動 | Cloudflare 挑戰 |
|---|---|---|---|---|---|
| Bright Data ISP（已停用） | TW ✅ | **CDG（巴黎）** | 2.17 s | ±0.6 s | **每次都要驗證** |
| Proxy-Seller ISP（現役） | TW ✅ | BCN | **0.95 s** | **±0.006 s** | **零挑戰** |

**教訓**：
- `loc` 對了不代表體驗好 —— **`colo` 與 TTFB 才反映路由品質**（Bright Data 那顆 IP 註冊在台灣，流量卻繞歐洲）。
- 某個資料庫說這顆是 `hosting`、網段登記人在南非，但**實測 Cloudflare 零挑戰** → **以實測行為為準**，不要用 ASN 評分決定。
- 向供應商要求規格時要講清楚：**「專屬 + 靜態 + 支援地區的本地 ISP ASN」**。

---

## 11. 檔案清單

```
clash-verge-ai-exit/
├── SETUP.md                      ← 本文件（主要操作手冊）
├── DEVICES.md                    ← iOS / Android / Edge / Claude Code 設定與驗證
├── AGENTS.md                     ← 給 AI agent 的入口指示
├── install.ps1                   ★ 安裝腳本（解析 uid、渲染範本、備份、驗證）
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

## 12. 務實提醒（不是技術問題，但會決定成敗）

- **地區政策**：如果你的實際所在地不在服務支援清單內，使用代理仍屬規避地區限制，帳號有被停用的風險。
- **付款國家**：訂閱的帳單國家通常是比 IP 更硬的門檻（例如香港發行的卡無法訂閱 Claude Pro）。
- **多帳號**：用多個帳號湊用量額度是條款明文禁止的；付費工具（同一張卡）也會把帳號關聯起來。需要更多容量請走官方更高的方案、企業合約或按量計費的 API。
