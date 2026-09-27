#!/usr/bin/env bash
# ==============================================================================
# Colab LLM Station - 統一多模型與公開穿透管理工具
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
    echo "  status            查看 GPU 顯存、模型與穿透網址狀態"
    echo "  list              列出已安裝與推薦的模型清單"
    echo "  pull <model>      下載任何開源模型 (例如: ./llm.sh pull deepseek-r1:32b)"
    echo "  chat [model]      啟動終端多輪互動對話 (預設使用目前最新模型)"
    echo "  bench [model]     執行模型效能評測 (測量 tokens/s, TTFT, 顯存)"
    echo "  tunnel            啟動或查看公開 HTTPS 穿透網址 (讓外部/自己電腦串接)"
    echo "  serve             確保本機 Ollama 服務運行中"
    echo "  sync              自動提交變更並同步至 GitHub"
    echo "================================================================"
}

function ensure_serve() {
    if ! curl -s http://127.0.0.1:11434/api/version &> /dev/null; then
        echo "正在啟動 Ollama 服務 (允許外部連線)..."
        OLLAMA_ORIGINS="*" OLLAMA_HOST="0.0.0.0:11434" nohup ollama serve > "$DIR/ollama.log" 2>&1 &
        for i in {1..15}; do
            if curl -s http://127.0.0.1:11434/api/version &> /dev/null; then
                echo "Ollama 服務啟動成功！"
                break
            fi
            sleep 1
        done
    fi
}

function start_tunnel() {
    ensure_serve
    if ! command -v cloudflared &> /dev/null; then
        echo "正在安裝 Cloudflare 穿透工具..."
        curl -L -s --output /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        dpkg -i /tmp/cloudflared.deb > /dev/null 2>&1
        rm /tmp/cloudflared.deb
    fi

    # 檢查是否已有運行的穿透
    if ! pgrep -f "cloudflared tunnel" > /dev/null; then
        echo "正在建立全球 HTTPS 穿透連線..."
        nohup cloudflared tunnel --url http://127.0.0.1:11434 > "$DIR/tunnel.log" 2>&1 &
        sleep 6
    fi

    URL=$(grep -o 'https://[-a-zA-Z0-9.]*\.trycloudflare\.com' "$DIR/tunnel.log" | tail -n 1 || true)
    if [ -n "$URL" ]; then
        echo "================================================================"
        echo " 您的公開 API 接口已就緒！全球皆可直接串接："
        echo "   • 公開 Base URL:  $URL/v1"
        echo "   • 測試端點:       $URL/api/version"
        echo ""
        echo " 外部程式 (Cursor, Aider, Python 等) 配置方式："
        echo "   OPENAI_BASE_URL=\"$URL/v1\""
        echo "   OPENAI_API_KEY=\"ollama\""
        echo "================================================================"
    else
        echo "穿透建立中，請稍候執行 ./llm.sh tunnel 查看網址。"
    fi
}

CMD="${1:-help}"

case "$CMD" in
    status)
        echo "=== [GPU 狀態] ==="
        nvidia-smi --query-gpu=name,memory.total,memory.used,memory.free,utilization.gpu --format=csv
        echo -e "\n=== [已下載的模型] ==="
        ollama list
        echo -e "\n=== [公開穿透狀態] ==="
        URL=$(grep -o 'https://[-a-zA-Z0-9.]*\.trycloudflare\.com' "$DIR/tunnel.log" 2>/dev/null | tail -n 1 || true)
        if [ -n "$URL" ]; then
            echo "公開 HTTPS 網址: $URL/v1"
        else
            echo "目前未啟動公開穿透 (可執行 ./llm.sh tunnel 啟動)"
        fi
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
    tunnel)
        start_tunnel
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
