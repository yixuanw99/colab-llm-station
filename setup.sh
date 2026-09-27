#!/usr/bin/env bash
# ==============================================================================
# Colab LLM Station - 通用環境一鍵還原與部署腳本
# ==============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

DEFAULT_MODEL="${1:-qwen3.8:27b}"

echo "=== [1/4] 安裝系統依賴 (zstd, pciutils, curl, git) ==="
apt-get update -qq
apt-get install -y -qq zstd pciutils curl git

echo "=== [2/4] 檢查並配置 Ollama 推論引擎 ==="
if ! command -v ollama &> /dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo "Ollama 已安裝: $(ollama --version)"
fi

echo "=== [3/4] 啟動背景 Ollama API 服務 ==="
if ! curl -s http://127.0.0.1:11434/api/version &> /dev/null; then
    echo "正在背景啟動 Ollama 服務 (日誌寫入 $DIR/ollama.log)..."
    nohup ollama serve > "$DIR/ollama.log" 2>&1 &
    
    # 輪詢等待服務就緒
    for i in {1..15}; do
        if curl -s http://127.0.0.1:11434/api/version &> /dev/null; then
            echo "Ollama 服務已就緒！"
            break
        fi
        sleep 1
    done
else
    echo "Ollama 服務運行中。"
fi

echo "=== [4/4] 檢查初始模型 ($DEFAULT_MODEL) ==="
if ollama list | grep -q "${DEFAULT_MODEL%%:*}"; then
    echo "模型 $DEFAULT_MODEL 已存在，隨時可調用。"
else
    echo "下載初始模型: $DEFAULT_MODEL ..."
    ollama pull "$DEFAULT_MODEL"
fi

echo "================================================================"
echo " 歡迎使用 Colab LLM Station 通用工作站！"
echo " 常用管理指令："
echo "   • 查看狀態與 GPU:    ./llm.sh status"
echo "   • 查看推薦模型清單:   ./llm.sh list"
echo "   • 下載其他模型:       ./llm.sh pull <model_name>"
echo "   • 啟動多輪對話:       ./llm.sh chat [model_name]"
echo "   • 執行效能評測:       ./llm.sh bench [model_name]"
echo "   • 程式碼自動同步:     ./llm.sh sync"
echo "================================================================"
