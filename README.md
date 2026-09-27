# Qwen3.8-27B 本地部署與重現指南 (A100-80GB)

本專案提供在 Google Colab（NVIDIA A100-80GB）環境中，一鍵部署與還原 2026 最新代號 **Qwen3.8-27B** 大模型的完整自動化流程。

---

##  硬體與環境配置

* **GPU**：NVIDIA A100-SXM4-80GB (80 GB VRAM)
* **作業系統**：Ubuntu 24.04 LTS (x86_64)
* **推論引擎**：Ollama + CUDA 13.0 加速
* **模型版本**：`qwen3.8:27b`（270 億參數 Dense 模型，原生支援 256K 超長上下文）
* **顯存佔用**：約 35.8 GB（包含 KV Cache 空間，剩餘 ~44GB 顯存支援超長代碼處理）
* **推論速度**：約 38~50+ tokens/秒

---

## ⚡ 一鍵重現環境 (Colab 重連時使用)

當 Google Colab 重新啟動或更換機器時，只需進入雲端硬碟掛載路徑並執行以下指令，系統將全自動完成所有依賴與模型還原：

```bash
cd /content/drive/MyDrive/colab/qwen3.8-deployment
bash setup.sh
```

`setup.sh` 會自動執行：
1. 安裝系統依賴（`zstd`, `pciutils`, `curl`, `git`）
2. 安裝與設定 Ollama 執行引擎
3. 背景啟動 Ollama 守護程序
4. 檢查並載入 `qwen3.8:27b` 模型

---

## 🛠️ 使用方式

### 1. 執行編程基準與效能測試
測試模型生成 LRU Cache 代碼並測量實際 TTFT、Throughput 與 GPU 顯存：
```bash
python3 test_inference.py
```

### 2. 啟動終端互動對話 (CLI Chat)
直接在終端機內進行多輪對話與上下文除錯：
```bash
python3 chat.py
```
*(輸入 `clear` 清空對話記錄，輸入 `exit` 退出)*

### 3. OpenAI-Compatible API 呼叫
本地提供原生 OpenAI 相容 API 端點（`http://127.0.0.1:11434/v1`），可直接無縫接入 Aider、Cline、OpenHands 或 LangChain：
```bash
python3 api_client_example.py
```

---

## 🔄 GitHub 遠端同步與自動備份

本目錄已初始化為 Git 儲存庫（已自動配置 `.gitignore`，過濾大模型權重與日誌，僅備份腳本與配置）。

### 綁定 GitHub 儲存庫：
```bash
# 綁定您的 GitHub 遠端倉庫（可使用 Personal Access Token）
git remote add origin https://<YOUR_GITHUB_TOKEN>@github.com/<USERNAME>/<REPO_NAME>.git

# 推送所有配置到 GitHub
./sync_git.sh
```

只要執行 `./sync_git.sh`，系統會自動比對變更、建立包含時間戳記的 Commit，並自動 push 至 GitHub。
