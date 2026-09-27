#!/usr/bin/env bash
# ==============================================================================
# Qwen3.8-27B 一鍵還原與部署腳本 (適用於 Google Colab A100 環境)
# ==============================================================================
set -e

DEPLOY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DEPLOY_DIR"

echo "=== [1/4] 檢查並安裝系統依賴 ==="
apt-get update -qq
apt-get install -y -qq zstd pciutils curl git

echo "=== [2/4] 檢查並安裝 Ollama 執行引擎 ==="
if ! command -v ollama &> /dev/null; then
    curl -fsSL https://ollama.com/install.sh | sh
else
    echo "Ollama 已就緒: $(ollama --version)"
fi

echo "=== [3/4] 檢查並啟動 Ollama 背景服務 ==="
if ! curl -s http://127.0.0.1:11434/api/version &> /dev/null; then
    echo "正在背景啟動 Ollama 服務 (日誌寫入 $DEPLOY_DIR/ollama.log)..."
    nohup ollama serve > "$DEPLOY_DIR/ollama.log" 2>&1 &
    
    # 等待服務就緒
    for i in {1..15}; do
        if curl -s http://127.0.0.1:11434/api/version &> /dev/null; then
            echo "Ollama 服務啟動成功！"
            break
        fi
        sleep 1
    done
else
    echo "Ollama 服務已在運行中。"
fi

echo "=== [4/4] 檢查並下載 Qwen3.8-27B 模型 ==="
if ollama list | grep -q "qwen3.8:27b"; then
    echo "模型 qwen3.8:27b 已在本地就緒！"
else
    echo "開始下載 qwen3.8:27b (約 17GB)..."
    ollama pull qwen3.8:27b
fi

echo "======================================================="
echo " Qwen3.8-27B 部署完成！"
echo " 測試指令："
echo "   - 執行效能與編程測試: python3 test_inference.py"
echo "   - 進入互動式終端聊天: python3 chat.py"
echo "   - 透過命令列直接對話: ollama run qwen3.8:27b"
echo "======================================================="
