#!/usr/bin/env bash
# ==============================================================================
# Colab LLM Station - 統一多模型管理工具
# ==============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

function show_help() {
    echo "================================================================"
    echo " Colab LLM Station - 多模型通用工作站管理工具"
    echo "================================================================"
    echo "用法: ./llm.sh [子指令] [參數]"
    echo ""
    echo "可用子指令："
    echo "  status            查看 GPU 顯存與運行中模型狀態"
    echo "  list              列出已安裝與推薦的模型清單"
    echo "  pull <model>      下載任何開源模型 (例如: ./llm.sh pull deepseek-r1:32b)"
    echo "  chat [model]      啟動終端多輪互動對話 (預設使用目前最新模型)"
    echo "  bench [model]     執行模型效能評測 (測量 tokens/s, TTFT, 顯存)"
    echo "  serve             確保 Ollama 背景 API 服務運行中"
    echo "  sync              自動提交變更並同步至 GitHub"
    echo "================================================================"
}

function ensure_serve() {
    if ! curl -s http://127.0.0.1:11434/api/version &> /dev/null; then
        echo "正在啟動 Ollama 服務..."
        nohup ollama serve > "$DIR/ollama.log" 2>&1 &
        sleep 4
    fi
}

CMD="${1:-help}"

case "$CMD" in
    status)
        echo "=== [GPU 狀態] ==="
        nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,utilization.gpu --format=table
        echo -e "\n=== [已下載的模型] ==="
        ollama list
        ;;
    list)
        echo "=== [本地已安裝模型] ==="
        ollama list
        echo -e "\n=== [推薦適用於 A100-80GB 的模型清單] ==="
        python3 -c "
import json
with open('models.json') as f:
    data = json.load(f)
for k, v in data['recommended_models'].items():
    print(f'• {k:<20} | 需顯存: ~{v[\"vram_required_gb\"]}GB | {v[\"description\"]}')
"
        ;;
    pull)
        MODEL="$2"
        if [ -z "$MODEL" ]; then
            echo "錯誤: 請指定要下載的模型名稱，例如: ./llm.sh pull deepseek-r1:32b"
            exit 1
        fi
        ensure_serve
        echo "開始下載模型: $MODEL ..."
        ollama pull "$MODEL"
        ;;
    chat)
        ensure_serve
        MODEL="${2:-qwen3.8:27b}"
        python3 "$DIR/chat.py" --model "$MODEL"
        ;;
    bench)
        ensure_serve
        MODEL="${2:-qwen3.8:27b}"
        python3 "$DIR/benchmark.py" --model "$MODEL"
        ;;
    serve)
        ensure_serve
        echo "Ollama API 服務已在 http://127.0.0.1:11434 運行中。"
        ;;
    sync)
        "$DIR/sync_git.sh"
        ;;
    *)
        show_help
        ;;
esac
