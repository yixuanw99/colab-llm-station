# Colab LLM Station 🚀

專為 Google Colab 與各式 GPU 環境設計的**全功能開源大模型工作站**。

本專案採模組化架構，同時內建 **雙推論引擎（vLLM / Ollama）** 與 **雙網絡通道（Tailscale / Cloudflare Tunnel）**，讓您不論在 Colab 抽到哪種規格顯卡、不論是臨時展示還是真實安全部署，都能獲得最佳體驗！

---

## 🌟 核心架構矩陣

### 1. 雙推論引擎（Dual Inference Engines）
* **⚡ 企業級高併發引擎：`vLLM`（Port: 8000）**
  * **適用硬體**：A100 (80GB)、H100 等企業級大顯卡。
  * **核心技術**：PagedAttention（零顯存碎片）、Continuous Batching（動態批處理）、原生吃 Hugging Face `safetensors` 與 AWQ 量化。
  * **適用場景**：**真實生產環境**、多用戶同時請求、極致吞吐量需求。
* **🦙 輕量級節約引擎：`Ollama`（Port: 11434）**
  * **適用硬體**：T4 (16GB)、L4 (24GB)、V100 (16GB) 或顯存較小的環境。
  * **核心技術**：GGUF 格式、超低記憶體開銷、單卡防 OOM。
  * **適用場景**：**資源有限時的保底方案**、單人快速驗證、輕量 CLI 聊天。

### 2. 雙網絡連線通道（Dual Network Tunnels）
* **🔒 真實安全部署：`Tailscale`（私有 Mesh VPN）**
  * **原理**：透過 WireGuard 建立加密虛擬局域網，將 Colab 與您的個人電腦加入同一私網。
  * **優點**：**零公網暴露**、外界完全無法掃描或攻擊，您在筆電直接連 `http://colab-llm-station:8000` 即可使用。
* **🌐 臨時演示展示：`Cloudflare Tunnel`（公開 HTTPS 穿透）**
  * **原理**：透過 Cloudflare 邊緣節點產生臨時的公開 HTTPS 網址（`*.trycloudflare.com`）。
  * **優點**：**免註冊、免密鑰、即開即用**，專為 POC（概念驗證）、客戶展示或跨團隊快速測試設計。

---

## 🚀 快速上手指南

### 1. 初次安裝 / 跨 Session 一鍵還原
在任何全新的 Colab 執行階段中執行：
```bash
cd /content/drive/MyDrive/colab/colab-llm-station
bash setup.sh
```
*(腳本會自動檢測並安裝 vLLM、Ollama、Tailscale 與 Cloudflared，並自動修復 CUDA 版本相依)*

---

## 🛠️ 統一指令手冊 (`./llm.sh`)

### 📌 總覽與硬體建議
```bash
./llm.sh status
```
*系統會自動偵測目前的 GPU 型號（A100 / T4 等），並給予最合適的引擎推薦與顯存即時監控。*

---

### ⚡ 模式 A：使用企業級 vLLM 引擎 (A100 推薦)
```bash
# 1. 啟動 vLLM OpenAI API 伺服器 (背景運行，預設 port 8000)
./llm.sh vllm serve Qwen/Qwen2.5-Coder-32B-Instruct

# 2. 執行高吞吐量基準評測
./llm.sh vllm bench Qwen/Qwen2.5-Coder-32B-Instruct

# 3. 終端互動對話
./llm.sh vllm chat Qwen/Qwen2.5-Coder-32B-Instruct

# 4. 停止服務
./llm.sh vllm stop
```

---

### 🦙 模式 B：使用輕量級 Ollama 引擎 (T4 / 小卡保底)
```bash
# 1. 啟動 Ollama 服務 (背景運行，預設 port 11434)
./llm.sh ollama serve

# 2. 下載任意 GGUF 模型
./llm.sh ollama pull qwen3.8:27b

# 3. 終端互動對話
./llm.sh ollama chat qwen3.8:27b

# 4. 效能基準評測
./llm.sh ollama bench qwen3.8:27b
```

---

### 🌐 模式 C：設定連線通道 (外界串接)

#### ① 真實安全部署：Tailscale (推薦)
```bash
# 登入 Tailscale (可使用 Authkey 自動登入，或不帶參數顯示登入連結)
./llm.sh tunnel tailscale up [YOUR_AUTH_KEY]

# 查看 Tailscale 節點狀態
./llm.sh tunnel tailscale status

# 將 vLLM 或 Ollama 服務映射給 Tailnet 私網成員
./llm.sh tunnel tailscale serve 8000
```
*連線成功後，您在自己的電腦、Cursor 或本機終端機中，只需將 Base URL 設為 `http://colab-llm-station:8000/v1` 即可如同區域網般私密調用！*

#### ② 快速 POC / 客戶展示：Cloudflare Tunnel
```bash
./llm.sh tunnel cloudflare
```
*系統會自動偵測目前正在運行的引擎（8000 或 11434），並立刻生成一組公網 HTTPS 網址（如 `https://xxxx.trycloudflare.com`）。*

---

## 🔄 代碼自動備份到 GitHub

```bash
# 1. 綁定您的 GitHub 遠端儲存庫 (僅需一次)
git remote add origin https://<YOUR_GITHUB_TOKEN>@github.com/<USERNAME>/<REPO_NAME>.git

# 2. 隨時自動 Commit 與 Push
./llm.sh sync
```
*(已配置 `.gitignore`，自動過濾大型權重、日誌與 Tailscale 憑證，僅備份腳本與設定)*
