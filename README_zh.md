# Colab LLM Station

適用於 Google Colab 與雲端 GPU 環境之雙推論引擎與雙連線通道部署框架。

[繁體中文] | [English](README.md)

---

## 架構總覽

Colab LLM Station 旨在解決雲端暫態 GPU 環境中的兩大工程挑戰：
1. **動態硬體適配**：自動辨識企業級 GPU（NVIDIA A100/H100）以啟用高併發 vLLM 服務，或在標準級 GPU（T4/L4/V100）切換為節約顯存之 Ollama GGUF 格式。
2. **安全存取與入口通道**：同時支援零公網暴露的私有網格網路（Tailscale）以及免認證的即時公開入口（Cloudflare Tunnel）。

```
                      +-----------------------------+
                      |      Colab LLM Station      |
                      +--------------+--------------+
                                     |
              +----------------------+----------------------+
              |                                             |
              v                                             v
       推論引擎架構                                  網絡通道架構
+----------------------------+                +----------------------------+
| vLLM (Port 8000)           |                | Tailscale (正式部署)       |
| - PagedAttention           |                | - WireGuard 虛擬局域網     |
| - Continuous Batching      |                | - 零公網暴露               |
| - Safetensors / AWQ / FP8  |                | - 用戶態網路 (Userspace)   |
+----------------------------+                +----------------------------+
| Ollama (Port 11434)        |                | Cloudflare Tunnel (POC展示)|
| - 低顯存佔用               |                | - 公開 HTTPS 入口          |
| - GGUF 量化格式            |                | - 免註冊即開即用           |
| - T4 / L4 防 OOM 機制      |                | - 概念驗證與即時展示       |
+----------------------------+                +----------------------------+
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

---

## 快速啟動

### 1. 環境初始化與還原
在全新的 Colab 執行階段中執行啟動腳本：

```bash
cd /content/drive/MyDrive/colab/colab-llm-station
bash setup.sh
```

### 2. 檢視當前運行狀態
檢視硬體監控、已啟動引擎與網絡通道狀態：

```bash
./llm.sh status
```

---

## 指令手冊 (`./llm.sh`)

### 企業級引擎操作：vLLM
```bash
# 啟動背景 vLLM OpenAI 相容伺服器 (預設 Port 8000)
./llm.sh vllm serve Qwen/Qwen2.5-Coder-32B-Instruct

# 執行高吞吐量基準評測
./llm.sh vllm bench Qwen/Qwen2.5-Coder-32B-Instruct

# 啟動終端互動對話
./llm.sh vllm chat Qwen/Qwen2.5-Coder-32B-Instruct

# 終止 vLLM 服務
./llm.sh vllm stop
```

### 輕量級引擎操作：Ollama
```bash
# 啟動背景 Ollama 守護程序 (Port 11434)
./llm.sh ollama serve

# 下載 GGUF 模型
./llm.sh ollama pull qwen3.8:27b

# 執行基準評測
./llm.sh ollama bench qwen3.8:27b

# 啟動終端互動對話
./llm.sh ollama chat qwen3.8:27b
```

### 網絡通道配置

#### Tailscale（加密私有網格）
```bash
# 認證並連線至 Tailnet 私網
./llm.sh tunnel tailscale up [AUTHKEY]

# 檢查節點連線狀態
./llm.sh tunnel tailscale status

# 將本機端口暴露給 Tailnet 成員
./llm.sh tunnel tailscale serve 8000
```
*連線完成後，本機開發環境可直接透過 `http://colab-llm-station:8000/v1` 進行私密調用，完全不經公網。*

#### Cloudflare Tunnel（臨時公開 POC 演示）
```bash
./llm.sh tunnel cloudflare [PORT]
```
*自動生成公開 HTTPS 入口（`https://*.trycloudflare.com`），直接映射至目前活躍之推論引擎。*

---

## 版本控制與遠端同步

```bash
# 自動提交變更並推送至遠端倉庫
./llm.sh sync
```
*(已配置 `.gitignore`，自動過濾大型模型權重、日誌檔與敏感憑證)。*
