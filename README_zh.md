# Colab LLM Station

適用於 Google Colab 與雲端 GPU 環境之雙推論引擎與雙連線通道部署框架。

[繁體中文] | [English](README.md)

---

## 架構總覽

Colab LLM Station 旨在解決雲端暫態 GPU 環境中的兩大工程挑戰：
1. **動態硬體適配**：自動辨識企業級 GPU（NVIDIA A100/H100）以啟用高併發 vLLM 服務，或在標準級 GPU（T4/L4/V100）切換為節約顯存之 Ollama GGUF 格式。
2. **安全存取與入口通道**：同時支援零公網暴露的私有網格網路（Tailscale）、免認證的即時公開入口（Cloudflare Tunnel），以及整合 Google Drive 憑證持久化的 VS Code 遠端開發通道（VS Code Remote Tunnel）。

```
                      +-----------------------------+
                      |      Colab LLM Station      |
                      +--------------+--------------+
                                     |
              +----------------------+----------------------+
              |                                             |
              v                                             v
        推論引擎架構                                  網絡與遠端通道架構
+----------------------------+                +----------------------------+
| vLLM (Port 8000)           |                | Tailscale (正式部署)       |
| - PagedAttention           |                | - WireGuard 虛擬局域網     |
| - Continuous Batching      |                | - 零公網暴露               |
| - Safetensors / AWQ / FP8  |                +----------------------------+
+----------------------------+                | Cloudflare Tunnel (POC展示)|
| Ollama (Port 11434)        |                | - 公開 HTTPS 入口          |
| - 低顯存佔用               |                | - 免註冊即開即用           |
| - GGUF 量化格式            |                +----------------------------+
| - T4 / L4 防 OOM 機制      |                | VS Code Tunnel (遠端開發)  |
+----------------------------+                | - 本機 VS Code / Web IDE   |
                                              | - Google Drive 憑證持久化  |
                                              +----------------------------+
```

---

## 硬體適配與引擎矩陣

| 評估維度 | 企業級運算資源 (A100 / H100) | 標準級運算資源 (T4 / L4 / V100) |
| :--- | :--- | :--- |
| **預設推論引擎** | **vLLM** (預設 Port: 8000) | **Ollama** (預設 Port: 11434) |
| **模型格式** | Hugging Face Safetensors, AWQ, FP8 | GGUF 量化格式 |
| **吞吐量特徵** | 透過 PagedAttention 與動態批處理實現高併發 | 針對單一串流最佳化 |
| **顯存配置策略** | 動態 KV Cache 配置（最高 90% VRAM） | 緊湊型靜態配置以防止 OOM 溢出 |

---

## 確定性與版本鎖定

所有執行階段二進制與核心相依性均透過 `versions.env` 與 `requirements.lock` 進行鎖定，杜絕跨機器部署時的版本漂移：

* **Ollama**: `v0.34.4`
* **vLLM**: `v0.30.0`
* **Cloudflared**: `v2026.9.3`
* **Tailscale**: `v1.102.4`
* **VS Code CLI**: Stable x64

---

## 快速啟動 (Colab 筆記本執行流程)

本專案提供立即可用的 Jupyter 範例筆記本：**[`colab_station.ipynb`](colab_station.ipynb)**（英文版）與 **[`colab_station-zh.ipynb`](colab_station-zh.ipynb)**（繁體中文版），你可以直接在 Google Colab 中開啟並執行。

### 步驟 0：前置作業與 Tailscale Auth Key 設定（僅需設定一次）

Google Colab 執行個體位於內部 NAT 網路後方，未配置獨立公網 IPv4 位址。使用具備暫態屬性（Ephemeral）的 Tailscale Auth Key，可在虛擬機器啟動時自動完成身分認證並建立網路節點，無需在執行過程中透過瀏覽器手動登入或掃描 QR Code。

#### 1. 於 Tailscale Admin Console 產生金鑰
1. 開啟 [Tailscale Admin Console - Settings - Keys](https://login.tailscale.com/admin/settings/keys)。
2. 點擊 **Generate auth key**。
3. 設定金鑰各項參數：
   * **Description**: 輸入識別名稱（例如 `colab-llm-station`）。
   * **Reusable**: **開啟 (Enabled)**。允許同一金鑰在 Colab Runtime 重啟後重複使用。
   * **Ephemeral**: **開啟 (Enabled，重要)**。當 Colab 執行個體中斷連線或關閉時，系統會自動自 Tailnet 裝置清單中移除該節點，避免累積無效離線主機。
   * **Pre-authorized**: **開啟 (Enabled)**。設備連線後自動核准加入網路，無需至後台手動審批。
   * **Tags**（選用）: 若組織 Tailnet ACL 規範需要標籤，可指定標籤（如 `tag:server`）。
4. 點擊 **Generate key** 並複製產生的金鑰字串（格式為 `tskey-auth-...`）。請妥善保存，Tailscale 僅會顯示此金鑰一次。

#### 2. 於 Google Colab Secrets 儲存金鑰
1. 在 Google Colab 左側工具列點擊 **Secrets** 面板（鑰匙圖示）。
2. 點擊 **Add new secret**（新增密鑰）。
3. 填入設定數值：
   * **名稱 (Name)**：`TAILSCALE_AUTHKEY`（大小寫需完全一致）。
   * **值 (Value)**：貼上剛才複製的 `tskey-auth-...` 金鑰字串。
4. 將 **Notebook access**（筆記本存取權限）開關切換為 **開啟 (ON)**，以允許 Python 透過 `google.colab.userdata` 讀取金鑰。

---

### 步驟 1：在 Colab 執行「獨立連線儲存格」建立 SSH
在 Colab 執行以下儲存格（或直接開啟 [`colab_station.ipynb`](colab_station.ipynb) / [`colab_station-zh.ipynb`](colab_station-zh.ipynb) 執行步驟 1）：

```python
# ==============================================================================
# 獨立 SSH 啟動儲存格（基於 Tailscale SSH，免密碼、免管理金鑰）
# ==============================================================================
from google.colab import drive, userdata

# 1. 掛載 Google Drive
drive.mount('/content/drive')

# 2. 取得剛剛存好的 Tailscale Auth Key
authkey = userdata.get('TAILSCALE_AUTHKEY')

# 3. 啟動 Tailscale 並啟用內建 SSH 伺服器（秒級純連線，不佔用時間進行套件安裝）
!cd /content/drive/MyDrive/colab/colab-llm-station && \
 bash llm.sh tunnel tailscale up "$authkey"

print("\n" + "="*60)
print("[OK] Tailscale SSH 連線已就緒。")
print("1. 本機終端機連線指令：")
print("   ssh root@colab-llm-station")
print("\n2. 本機 VS Code (Remote - SSH) 連線：")
print("   按 F1 -> 輸入 Remote-SSH: Connect to Host... -> 輸入 root@colab-llm-station")
print("="*60)
```

---

### 步驟 2：本機電腦連線方式

#### 方式 A：本機終端機直連（PowerShell / macOS Terminal / Linux）
```bash
ssh root@colab-llm-station
```
*(Tailscale 會自動進行身分驗證，完全免輸入密碼、免設定金鑰！)*

#### 方式 B：本機 VS Code (Remote - SSH) 遠端開發
1. 在本機 VS Code 安裝官方擴充套件 **「Remote - SSH」** (`ms-vscode-remote.remote-ssh`)。
2. 按 `F1` 鍵，輸入並選擇 `Remote-SSH: Connect to Host...`。
3. 輸入 `root@colab-llm-station`。
4. 連入後點擊「開啟資料夾」，選取 `/content/drive/MyDrive/colab/colab-llm-station` 即可開始開發！
*(亦相容於 Cursor、Zed、PyCharm Gateway 等工具)*。

---

### 步驟 3：初始化環境與啟動 LLM 推論服務
SSH 連線就緒後，你可以在本機終端機（SSH 或 VS Code 內建終端機）直接執行環境初始化與推論啟動，亦可在 Colab 筆記本的後續儲存格執行：

```bash
cd /content/drive/MyDrive/colab/colab-llm-station

# 1. 初始化環境依賴（每個新 Runtime 僅需執行一次）
bash setup.sh

# 亦可依需求單獨安裝特定推論引擎：
# bash setup.sh vllm    # 僅安裝 vLLM 與系統依賴
# bash setup.sh ollama  # 僅安裝 Ollama 與系統依賴

# 2. 啟動推論引擎：
# 企業級 GPU (A100 / H100): 啟動 vLLM (Port 8000)
bash llm.sh tunnel tailscale serve 8000
bash llm.sh vllm serve Qwen/Qwen2.5-Coder-32B-Instruct

# 標準級 GPU (T4 / L4): 啟動 Ollama (Port 11434)
# bash llm.sh tunnel tailscale serve 11434
# bash llm.sh ollama serve
```

啟動後，本機的 OpenCode、Python 腳本或任何客戶端即可直接透過 `http://colab-llm-station:8000/v1` 調用模型！

---

### 備用方案：VS Code Remote Tunnel (Web IDE)
若本機未安裝 Tailscale 或需使用純瀏覽器 `vscode.dev` 開發，亦可選用微軟 VS Code Remote Tunnel：
<details>
<summary>點擊展開 VS Code Remote Tunnel 儲存格程式碼</summary>

```bash
%%bash
# 1. 下載並安裝 VS Code CLI
if [ ! -f "/usr/local/bin/code" ]; then
    curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' --output /tmp/vscode_cli.tar.gz
    tar -xf /tmp/vscode_cli.tar.gz -C /usr/local/bin
    chmod +x /usr/local/bin/code
    rm -f /tmp/vscode_cli.tar.gz
fi

# 2. Google Drive 憑證持久化與登入
PERSIST_DIR="/content/drive/MyDrive/.vscode_colab"
mkdir -p "$PERSIST_DIR" /root/.vscode/cli
cp -rn "$PERSIST_DIR"/* /root/.vscode/cli/ 2>/dev/null || true

if ! code tunnel user show >/dev/null 2>&1; then
    code tunnel user login --provider github
    cp -f /root/.vscode/cli/token.json /root/.vscode/cli/code_tunnel.json "$PERSIST_DIR/" 2>/dev/null || true
fi

# 3. 啟動 Tunnel
code tunnel --accept-server-license-terms --name my-colab-gpu
```
</details>

---

## 指令手冊 (`bash llm.sh`)

### 企業級引擎操作：vLLM
```bash
# 啟動背景 vLLM OpenAI 相容伺服器 (預設 Port 8000)
bash llm.sh vllm serve Qwen/Qwen2.5-Coder-32B-Instruct

# 執行高吞吐量基準評測
bash llm.sh vllm bench Qwen/Qwen2.5-Coder-32B-Instruct

# 啟動終端互動對話
bash llm.sh vllm chat Qwen/Qwen2.5-Coder-32B-Instruct

# 終止 vLLM 服務
bash llm.sh vllm stop
```

### 輕量級引擎操作：Ollama
```bash
# 啟動背景 Ollama 守護程序 (Port 11434)
bash llm.sh ollama serve

# 下載 GGUF 模型
bash llm.sh ollama pull qwen3.8:27b

# 執行基準評測
bash llm.sh ollama bench qwen3.8:27b

# 啟動終端互動對話
bash llm.sh ollama chat qwen3.8:27b
```

### 網絡與遠端通道配置

#### Tailscale（加密私有網格）
```bash
# 認證並連線至 Tailnet 私網
bash llm.sh tunnel tailscale up [AUTHKEY]

# 檢查節點連線狀態
bash llm.sh tunnel tailscale status

# 將本機端口暴露給 Tailnet 成員
bash llm.sh tunnel tailscale serve 8000
```
*連線完成後，本機開發環境可直接透過 `http://colab-llm-station:8000/v1` 進行私密調用，完全不經公網。*

#### Cloudflare Tunnel（臨時公開 POC 演示）
```bash
bash llm.sh tunnel cloudflare [PORT]
```
*自動生成公開 HTTPS 入口（`https://*.trycloudflare.com`），直接映射至目前活躍之推論引擎。*

#### VS Code Remote Tunnel（雲端與桌面 IDE 開發通道）
```bash
# 安裝 VS Code CLI 並自 Google Drive 還原憑證
bash llm.sh tunnel vscode setup

# 進行 GitHub 授權登入（憑證將自動持久化至 Google Drive）
bash llm.sh tunnel vscode login

# 於背景啟動 VS Code Tunnel
bash llm.sh tunnel vscode start [MACHINE_NAME]

# 檢查 VS Code Tunnel 連線狀態
bash llm.sh tunnel vscode status

# 停止 VS Code Tunnel
bash llm.sh tunnel vscode stop
```
*可在本機 VS Code 或 `vscode.dev` 中直接編輯專案、管理 Git、啟動模型服務與終端除錯。*

---

## 客戶端整合：OpenCode (v2)

Colab LLM Station 支援透過私人 Tailnet 內網無縫串接 [OpenCode](https://opencode.ai) 開發環境，採用官方最新之 OpenCode v2 提供者規格。

### 1. 配置設定檔 (`opencode.json` / `opencode.jsonc`)

將以下設定放置於專案根目錄，或放在 `%USERPROFILE%\.config\opencode\opencode.json` (Windows) / `~/.config/opencode/opencode.json` (Linux/macOS)：

```json
{
  "$schema": "https://opencode.ai/config.json",
  "providers": {
    "colab-station": {
      "package": "@opencode/ai/providers/openai-compatible",
      "name": "Colab LLM Station",
      "settings": {
        "baseURL": "http://colab-llm-station:11434/v1",
        "apiKey": "ollama"
      },
      "models": {
        "qwen3.8:27b": {
          "name": "Qwen 3.8 (27B)",
          "limit": { "context": 262144, "output": 16384 }
        },
        "deepseek-r1:32b": {
          "name": "DeepSeek R1 (32B)",
          "limit": { "context": 131072, "output": 16384 }
        },
        "qwen2.5-coder:32b": {
          "name": "Qwen 2.5 Coder (32B)",
          "limit": { "context": 32768, "output": 16384 }
        }
      }
    }
  }
}
```

> 提示：若使用 vLLM 引擎，請將 `baseURL` 端口改為 `8000`，並填入對應的 Hugging Face 模型名稱。

### 2. Windows PowerShell 快速一鍵設定

在客戶端筆電的 PowerShell 執行以下指令自動生成設定檔：

```powershell
New-Item -ItemType Directory -Force "$HOME\.config\opencode" | Out-Null
Copy-Item "templates\opencode.json" -Destination "$HOME\.config\opencode\opencode.json"
```

### 3. 生效與使用
重啟 OpenCode 服務（`opencode service restart` 或重啟桌面客戶端），於 OpenCode 終端輸入 `/models` 即可直接選擇模型展開推論。

---

## 版本控制與遠端同步

```bash
# 自動提交變更並推送至遠端倉庫
bash llm.sh sync
```
*(已配置 `.gitignore`，自動過濾大型模型權重、日誌檔與敏感憑證)。*

