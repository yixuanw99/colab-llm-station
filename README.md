# Colab LLM Station 🚀

專為 Google Colab 與高階 GPU（如 NVIDIA A100-80GB）設計的**通用多模型運行、評測與 API 服務工作站**。

本專案基於 **Ollama 跨平台 CUDA 推論引擎**，完全擺脫單一模型或特定 Python 函式庫的相依性限制，支援自由切換與部署任意主流開源大模型（如 Qwen 3.8 / 2.5、DeepSeek-R1、Llama 3.3、Mistral 等）。

---

## 🌟 核心特色

1. **多模型無痛切換（Model-Agnostic）**：
   支援開源社群數百種主流模型，指令一鍵下載與秒級切換。
2. **零 Python 相依衝突（Zero Dependency Conflict）**：
   以獨立的 C++/CUDA 二進制運行時運作，不論 Python 3.10、3.12 或 3.13 均能穩定使用 A100 硬體加速。
3. **原生 OpenAI 相容端點（OpenAI-Compatible API）**：
   開箱即提供 `http://127.0.0.1:11434/v1`，直接相容 Cursor, Aider, Cline, LangChain, OpenHands 等全部外掛與 Agent 工具。
4. **一鍵跨 Session 還原**：
   重開 Colab 時只需執行 `./setup.sh`，5 秒即可自動恢復所有服務。
5. **Git 與雲端硬碟雙重持久化**：
   儲存在 Google Drive 掛載區，並自帶 `./llm.sh sync` 支援隨時自動 Push 至 GitHub。

---

## 🚀 快速開始

### 1. 初次部署 / 跨 Session 一鍵還原
```bash
cd /content/drive/MyDrive/colab/colab-llm-station
bash setup.sh
```

---

## 🛠️ 統一指令工具 (`./llm.sh`)

本專案提供統一的管理腳本 `./llm.sh`：

| 操作目標 | 指令 | 說明 |
| :--- | :--- | :--- |
| **查看狀態** | `./llm.sh status` | 顯示當前 GPU 顯存使用量與已載入模型 |
| **模型清單** | `./llm.sh list` | 檢視本地已安裝模型與針對 A100-80GB 推薦的模型 |
| **下載模型** | `./llm.sh pull <model>` | 例如：`./llm.sh pull deepseek-r1:32b` |
| **終端對話** | `./llm.sh chat [model]` | 進入多輪互動式對話（預設使用當前模型） |
| **效能評測** | `./llm.sh bench [model]` | 實測 TTFT、Throughput (tokens/s) 與顯存曲線 |
| **背景服務** | `./llm.sh serve` | 確保本機 API 服務已啟動 |
| **代碼備份** | `./llm.sh sync` | 自動 Commit 並同步到 GitHub |

---

## 📊 A100-80GB 推薦模型配置 (`models.json`)

| 模型標籤 | 核心強項 | 顯存需求 (VRAM) | 推薦場景 |
| :--- | :--- | :---: | :--- |
| **`qwen3.8:27b`** | 2026 最新代號、代碼生成、多模態、256K 上下文 | ~36 GB | 日常 Coding、多語言開發、長文件處理 |
| **`deepseek-r1:32b`** | 自主思考鏈（CoT）、邏輯演算法深層推演 | ~40 GB | 複雜演算法（LeetCode Hard）、數學論證 |
| **`deepseek-r1:70b`** | 70B 滿血思維旗艦，4-bit 量化最佳化 | ~44 GB | 專家級架構規劃與極限代碼重構 |
| **`llama3.3:70b`** | Meta 旗艦通用模型、128K 視窗 | ~42 GB | 西方英文生態、複雜指示跟隨、多領域創作 |
| **`qwen2.5-coder:32b`** | 經典代碼模型，相容性極高 | ~38 GB | 廣泛相容現有外掛與工具鏈 |

---

## 🔗 連接外部開發工具 (Cursor / Aider / LangChain)

本地運行的模型提供標準 OpenAI REST 接口：
* **Base URL**: `http://127.0.0.1:11434/v1`
* **API Key**: `ollama`（可任意輸入）
* **Model**: 當前已下載的任何模型名稱（如 `qwen3.8:27b`）

範例 Python 呼叫（使用 `api_client_example.py`）：
```python
import urllib.request, json

req = urllib.request.Request(
    "http://127.0.0.1:11434/v1/chat/completions",
    data=json.dumps({
        "model": "qwen3.8:27b",
        "messages": [{"role": "user", "content": "Hello!"}]
    }).encode("utf-8"),
    headers={"Content-Type": "application/json"}
)
```

---

## 🔄 GitHub 同步設定

```bash
# 1. 綁定您的 GitHub 遠端儲存庫
git remote add origin https://<YOUR_GITHUB_TOKEN>@github.com/<USERNAME>/<REPO_NAME>.git

# 2. 隨時執行同步
./llm.sh sync
```
*(已配置 `.gitignore`，自動排除巨大權重與日誌檔案，僅備份腳本與配置)*
