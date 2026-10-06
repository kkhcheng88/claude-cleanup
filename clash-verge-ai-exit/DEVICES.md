# 裝置設定與驗證

同一份 `mobile-clash.yaml` 可用於 iOS（Stash）與 Android（CMFA）。
**三台裝置使用同一個出口 IP**，讓同一個帳號在任何裝置上看起來都是同一個來源。

---

## A. iOS（iPhone / iPad）— Stash

### A1. 前置
- App Store 需要**非中國區帳號**（香港/台灣皆可）
- Stash 是付費 App（同一 Apple ID 在第二台裝置**不用再付費**）

### A2. 把設定檔傳到裝置
1. 把 `mobile-clash.yaml` 上傳到 OneDrive / Google Drive / iCloud Drive（或 Email 給自己）
2. 在裝置上開啟 → **儲存到「檔案」→ 我的 iPhone/iPad**
3. ⚠️ **不要用公開分享連結** —— 檔案裡有代理帳密

### A3. 匯入並啟用
1. 開 Stash → 允許**加入 VPN 設定**（要 Face ID / 密碼）
2. Stash → **設定（Configuration）** → 右上 `+` → **從檔案匯入** → 選 `mobile-clash.yaml`
3. 點一下該設定檔 → 選為**使用中**
4. 回主畫面 → **開啟 Stash 開關**

### A4. 必做設定
| 項目 | 位置 | 動作 |
|---|---|---|
| **保持常駐** | Stash → 設定 | **開啟**（等於 iOS 版的隨選連線） |
| iCloud+ **私密轉送**（若你有訂閱 iCloud+） | 設定 → Apple ID → iCloud → 私密轉送 | **關閉**（否則 Safari 會走 Apple 的中繼路徑） |
| **限制 IP 位址追蹤** | 設定 → Wi-Fi → 該網路 ⓘ | **關閉**（同上，會改變 Safari 的出口） |
| **時區 / 地區** | 設定 → 一般 → 語言與地區 | 與你的出口國家一致 |
| 低耗電模式 | 設定 → 電池 | 使用時盡量關閉（可能讓 VPN 被系統回收） |
| 背景 App 重新整理 | 設定 → 一般 → 背景 App 重新整理 | 允許 Stash |

### A5. 驗證（Safari）
```
① https://ipinfo.io/ip                → 必須是代理 IP
② https://claude.ai/cdn-cgi/trace     → ip= 是代理 IP、loc= 是你預期的國家
③ https://claude.ai                   → 正常開（第一次可能過一次 Cloudflare 驗證）
```
若 ③ 出現地區限制或服務不可用，但 ①② 正常 → **代表有旁路洩漏**（多半是 QUIC 或 VPN 掉了）。

---

## B. Android（手機 / 平板）— Clash Meta for Android (CMFA)

### B1. 安裝
- 只從官方 GitHub 下載：`https://github.com/MetaCubeX/ClashMetaForAndroid/releases`
- **選 `arm64-v8a`**（2016 年後的裝置幾乎都是；裝不起來才換 `armeabi-v7a`）
- Android 會問「允許安裝未知應用程式」→ 允許

### B2. 匯入（若檔案選擇器看不到 `.yaml`）
1. 把 `mobile-clash.yaml` 放到裝置的 **Download** 資料夾
2. CMFA → **設定檔 → `+` → Import from file**
3. 在選擇器裡：**左上 ☰ →「顯示內部儲存空間」** → 選 **Internal storage → Download** → 選檔案
4. **若選擇器仍看不到檔案**（Android 對 `.yaml` 的 MIME 判定常是 `application/octet-stream`，會被過濾）→ 改用 **Import from URL**：
   - 在電腦上起一個臨時服務：
     ```powershell
     & "<python.exe 路徑>" -m http.server 8000 --directory "<這個資料夾>"
     ```
   - 查電腦的區網 IP：`ipconfig` → 找**正在使用的網卡**（**不要用 `198.18.x.x`，那是 Clash 的虛擬網卡**）
   - CMFA → Import from URL → `http://<區網IP>:8000/mobile-clash.yaml`
   - 手機與電腦要在**同一個 Wi-Fi**；Windows 防火牆要允許 Python（私人網路）
   - 匯入完 **Ctrl + C 關掉服務**

### B3. 啟動
CMFA → 點一下該設定檔 → 選為使用中 → 回主畫面開啟開關 → 允許 VPN 權限

### B4. 必做系統設定
| 項目 | 位置 | 動作 |
|---|---|---|
| **一律開啟的 VPN** | 設定 → 網路與網際網路 → VPN → CMFA ⚙️ | **開** |
| **封鎖沒有 VPN 的連線** ⭐ | 同上一頁 | **開** ← VPN 一斷就全部封鎖，不會從非預期路徑連出去（fail-closed） |
| **電池 → 不受限制** | 設定 → 應用程式 → Clash Meta → 電池 | 開 |
| **私人 DNS** | 設定 → 網路與網際網路 → 私人 DNS | 「自動」或關閉 |
| 時區 / 地區 | 設定 → 系統 → 日期與時間 / 語言 | 與出口國家一致 |

### B5. 驗證
與 A5 相同三關；另外可在 CMFA 的**連線記錄**確認目標服務相關條目的「策略」欄是 **`AI-Exit`**（不是 `DIRECT`）。

> 桌面版的 `PROCESS-NAME-REGEX` 安全網**在手機上不存在**（手機不支援程序名稱規則），
> 所以手機端完全依賴**域名清單**。若在連線記錄看到「目標服務相關但走 DIRECT」的域名，
> 請把它加進 `configs/enh-rules.ai-exit.yaml` 與 `configs/mobile-clash.template.yaml`，然後重新安裝。

---

## C. 瀏覽器（Edge / Chrome）

| 設定 | 位置 | 動作 |
|---|---|---|
| **QUIC** | `edge://flags/#enable-quic` / `chrome://flags/#enable-quic` | **Disabled**（改完完全重開瀏覽器；大版本更新後要回來檢查） |
| 不要裝的擴充 | — | VPN / 代理 / 網路加速 / **指紋或 UA 偽裝** 類 |
| Cookie 紀律 | — | 不要清目標網站的 cookie、不要用無痕當日常 |

**不需要指紋瀏覽器**：那類工具是為「多組帳號」與「自動化」設計的。單一帳號 + 真人操作 + 一致的 IP／時區，用一般瀏覽器最自然；額外偽裝反而製造不一致的訊號。

---

## D. Claude Code（逐工具代理，fail-closed）

編輯 `%USERPROFILE%\.claude\settings.json`，在**既有的** `env` 物件加入：

```json
"HTTPS_PROXY": "http://127.0.0.1:7897",
"HTTP_PROXY":  "http://127.0.0.1:7897",
"NO_PROXY":    "localhost,127.0.0.1,::1"
```

- 只影響 Claude Code（`npm` / `git` / `pip` 不受影響）
- Clash Verge 沒開時，Claude Code **直接失敗**（不會從非預期路徑連出去）
- 驗證方式：在 Claude Code 裡執行 `echo $env:HTTPS_PROXY`

## E. Codex（沒有逐工具設定）

用 `launchers\codex-p.cmd` 啟動（`install.ps1` 會複製到 `%APPDATA%\npm`），它會設定同樣的環境變數後再啟動 Codex。

---

## G. Windows 主機（地區／時區一致性）

主機本身就是最重要的一台裝置：**出口在目標國家、裝置卻仍顯示別的時區／地區**，是一種互相矛盾的訊號。

```powershell
# 唯讀檢查（六項：時區 / 住家位置 / 系統地區 / 使用者格式 / 語言清單 / 時鐘同步）
powershell -ExecutionPolicy Bypass -File .\check-windows-locale.ps1

# 修正（時區與系統地區需要系統管理員權限；系統地區需重開機、語言清單需重新登入）
powershell -ExecutionPolicy Bypass -File .\check-windows-locale.ps1 -Apply
```

通過標準：輸出結尾是 `RESULT: all settings are consistent.`
（腳本只新增缺少的語言，不會移除既有語言或改掉顯示語言；所有變更都可在 Windows 設定介面還原。）

---

## H. 所有裝置共同紀律

1. **不要**把 `AI-Exit` 切成 `DIRECT`、不要改成 `url-test`
2. **不要**清目標網站 cookie、不要用無痕當日常
3. VPN / Stash / CMFA **保持連線**（斷線時流量會走真實路徑）
4. 同一組帳號**固定在同一條線**上使用（**多組帳號共用一條線沒問題** —— 見 `SETUP.md` 第 11.1 節）
