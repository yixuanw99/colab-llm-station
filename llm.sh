#!/usr/bin/env bash
# ==============================================================================
# Colab LLM Station - 雙推論引擎 (vLLM / Ollama) 與雙通道 (Tailscale / Cloudflare)
# ==============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# ------------------------------------------------------------------------------
# 輔助函式：硬體檢測與引擎推薦
# ------------------------------------------------------------------------------
function detect_hardware() {
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n 1 || echo "None")
    GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1 || echo "0")
    
    echo "=== [硬體與推薦] ==="
    echo "檢測到顯卡: $GPU_NAME (${GPU_MEM} MB VRAM)"
    
    if [[ "$GPU_NAME" =~ "A100" ]] || [[ "$GPU_NAME" =~ "H100" ]] || [[ "$GPU_MEM" -gt 60000 ]]; then
        echo "💡 評估: 具備 80GB 大顯存與高頻寬！強烈推薦使用 [vLLM] 享受業界生產級的高併發與 PagedAttention 吞吐量。"
    elif [[ "$GPU_NAME" =~ "T4" ]] || [[ "$GPU_NAME" =~ "V100" ]] || [[ "$GPU_NAME" =~ "L4" ]] || [[ "$GPU_MEM" -lt 30000 ]]; then
        echo "💡 評估: 顯存較有限（16GB~24GB）。建議使用 [Ollama] 載入量化版 (GGUF)，兼顧記憶體與穩定性。"
    else
        echo "💡 評估: 可依據任務規模自由切換 vLLM 或 Ollama。"
    fi
}

function show_help() {
    echo "================================================================================"
    echo " 🚀 Colab LLM Station - 雙推論引擎 (vLLM / Ollama) 與雙通道管理工具"
    echo "================================================================================"
    echo "用法: ./llm.sh [子指令] [選項...]"
    echo ""
    echo "📌 總覽指令："
    echo "  status                   查看 GPU、各引擎運行狀態與連線通道"
    echo "  list                     檢視所有推薦模型清單 (vLLM / Ollama)"
    echo "  sync                     自動提交代碼並同步至 GitHub"
    echo ""
    echo "⚡ 企業級引擎 - vLLM (高併發、高吞吐、原生 Safetensors / AWQ，預設 Port 8000)："
    echo "  vllm serve [model]       背景啟動 vLLM OpenAI API 伺服器 (預設: Qwen2.5-Coder-32B)"
    echo "  vllm stop                停止 vLLM 服務"
    echo "  vllm bench [model]       對 vLLM 進行高吞吐量基準評測"
    echo "  vllm chat [model]        終端互動對話 (透過 vLLM 端點)"
    echo ""
    echo "🦙 輕量級引擎 - Ollama (節約顯存、小卡防 OOM、GGUF，預設 Port 11434)："
    echo "  ollama serve             背景啟動 Ollama 服務"
    echo "  ollama pull <model>      下載 GGUF 模型 (如 qwen3.8:27b, deepseek-r1:32b)"
    echo "  ollama chat [model]      終端多輪互動對話"
    echo "  ollama bench [model]     對 Ollama 進行基準評測"
    echo "  ollama list              列出本機已下載的 Ollama 模型"
    echo ""
    echo "🌐 連線通道管理 (雙通道)："
    echo "  tunnel cloudflare [port] 啟動 Cloudflare HTTPS 公開穿透 (POC / 演示展示用，免註冊)"
    echo "  tunnel tailscale [cmd]   管理 Tailscale 私有安全網 (真實部署用，零公網暴露)"
    echo "                           子指令: up, status, down, serve"
    echo "================================================================================"
}

# ------------------------------------------------------------------------------
# 子命令處理
# ------------------------------------------------------------------------------
CMD="${1:-help}"

case "$CMD" in
    status)
        detect_hardware
        echo -e "\n=== [引擎運行狀態] ==="
        if curl -s http://127.0.0.1:8000/v1/models &> /dev/null; then
            echo "• vLLM 服務: [🟢 運行中] (Port: 8000)"
        else
            echo "• vLLM 服務: [⚪ 未運行] (可執行 ./llm.sh vllm serve 啟動)"
        fi
        
        if curl -s http://127.0.0.1:11434/api/version &> /dev/null; then
            echo "• Ollama 服務: [🟢 運行中] (Port: 11434)"
        else
            echo "• Ollama 服務: [⚪ 未運行] (可執行 ./llm.sh ollama serve 啟動)"
        fi

        echo -e "\n=== [連線通道狀態] ==="
        CF_URL=$(grep -o 'https://[-a-zA-Z0-9.]*\.trycloudflare\.com' "$DIR/tunnel.log" 2>/dev/null | tail -n 1 || true)
        if [ -n "$CF_URL" ] && pgrep -f "cloudflared tunnel" > /dev/null; then
            echo "• Cloudflare 公開穿透: [🟢 活躍] URL: $CF_URL"
        else
            echo "• Cloudflare 公開穿透: [⚪ 未連線] (可執行 ./llm.sh tunnel cloudflare 啟動)"
        fi

        if tailscale status 2>/dev/null | grep -qv "Logged out"; then
            echo "• Tailscale 私有網: [🟢 活躍] 節點已上線"
            tailscale status | head -n 3
        else
            echo "• Tailscale 私有網: [⚪ 未登入/未連線] (可執行 ./llm.sh tunnel tailscale up 啟動)"
        fi
        ;;

    list)
        python3 -c "
import json
with open('models.json') as f:
    d = json.load(f)
print('=== 企業級引擎: vLLM 推薦模型 ===')
for m, v in d['engines']['vllm']['recommended_models'].items():
    print(f'• {m:<42} | ~{v[\"vram_gb\"]}GB | {v[\"description\"]}')
print('\n=== 輕量級引擎: Ollama 推薦模型 ===')
for m, v in d['engines']['ollama']['recommended_models'].items():
    print(f'• {m:<25} | ~{v[\"vram_gb\"]}GB | {v[\"description\"]}')
"
        ;;

    vllm)
        SUBCMD="${2:-help}"
        case "$SUBCMD" in
            serve)
                MODEL="${3:-Qwen/Qwen2.5-Coder-32B-Instruct}"
                echo "正在背景啟動 vLLM 生產級服務 (模型: $MODEL, Port: 8000)..."
                nohup python3 -m vllm.entrypoints.openai.api_server \
                    --model "$MODEL" \
                    --port 8000 \
                    --trust-remote-code \
                    --max-model-len 32768 \
                    --gpu-memory-utilization 0.90 > "$DIR/vllm.log" 2>&1 &
                echo "vLLM 已在背景啟動，日誌記錄於 $DIR/vllm.log"
                echo "等待伺服器就緒..."
                for i in {1..30}; do
                    if curl -s http://127.0.0.1:8000/v1/models &> /dev/null; then
                        echo "vLLM 服務就緒！OpenAI 端點: http://127.0.0.1:8000/v1"
                        exit 0
                    fi
                    sleep 2
                done
                echo "提示: 模型較大，仍在加載權重中，可執行 tail -f $DIR/vllm.log 查看進度。"
                ;;
            stop)
                echo "停止 vLLM 服務..."
                pkill -f "vllm.entrypoints.openai.api_server" || true
                ;;
            bench)
                MODEL="${3:-Qwen/Qwen2.5-Coder-32B-Instruct}"
                python3 "$DIR/benchmark.py" --engine vllm --port 8000 --model "$MODEL"
                ;;
            chat)
                MODEL="${3:-Qwen/Qwen2.5-Coder-32B-Instruct}"
                python3 "$DIR/chat.py" --engine vllm --port 8000 --model "$MODEL"
                ;;
            *)
                echo "用法: ./llm.sh vllm [serve|stop|bench|chat] [model]"
                ;;
        esac
        ;;

    ollama)
        SUBCMD="${2:-help}"
        case "$SUBCMD" in
            serve)
                if ! curl -s http://127.0.0.1:11434/api/version &> /dev/null; then
                    echo "正在背景啟動 Ollama 服務..."
                    OLLAMA_ORIGINS="*" OLLAMA_HOST="0.0.0.0:11434" nohup ollama serve > "$DIR/ollama.log" 2>&1 &
                    sleep 3
                fi
                echo "Ollama 服務運行中 (Port: 11434)"
                ;;
            pull)
                MODEL="$3"
                [ -z "$MODEL" ] && { echo "錯誤: 請指定模型名稱，例如: ./llm.sh ollama pull qwen3.8:27b"; exit 1; }
                ollama pull "$MODEL"
                ;;
            bench)
                MODEL="${3:-qwen3.8:27b}"
                python3 "$DIR/benchmark.py" --engine ollama --port 11434 --model "$MODEL"
                ;;
            chat)
                MODEL="${3:-qwen3.8:27b}"
                python3 "$DIR/chat.py" --engine ollama --port 11434 --model "$MODEL"
                ;;
            list)
                ollama list
                ;;
            *)
                echo "用法: ./llm.sh ollama [serve|pull|bench|chat|list] [model]"
                ;;
        esac
        ;;

    tunnel)
        TARGET="${2:-help}"
        case "$TARGET" in
            cloudflare)
                PORT="${3:-auto}"
                if [ "$PORT" == "auto" ]; then
                    if curl -s http://127.0.0.1:8000/v1/models &> /dev/null; then
                        PORT=8000
                        echo "自動檢測到 vLLM 正在運行，穿透端口映射為 8000"
                    else
                        PORT=11434
                        echo "自動檢測到 Ollama 正在運行，穿透端口映射為 11434"
                    fi
                fi
                echo "正在建立 Cloudflare HTTPS 公開穿透 (指向 127.0.0.1:$PORT)..."
                pkill -f "cloudflared tunnel" || true
                nohup cloudflared tunnel --url "http://127.0.0.1:$PORT" --logfile "$DIR/tunnel.log" > /dev/null 2>&1 &
                sleep 6
                CF_URL=$(grep -o 'https://[-a-zA-Z0-9.]*\.trycloudflare\.com' "$DIR/tunnel.log" | tail -n 1 || true)
                echo "================================================================"
                echo " 🌐 Cloudflare 公開 HTTPS 端點就緒 (POC / Demo 演示用)："
                echo "   • Base URL:  $CF_URL/v1"
                echo "   • 測試端點:   $CF_URL"
                echo "================================================================"
                ;;
            tailscale)
                ACTION="${3:-status}"
                case "$ACTION" in
                    up)
                        AUTHKEY="$4"
                        mkdir -p /content/drive/MyDrive/colab/colab-llm-station/.tailscale
                        # 確保背景常駐啟動
                        if ! pgrep -f "tailscaled" > /dev/null; then
                            echo "啟動 tailscaled 背景服務 (Userspace Networking 模式)..."
                            nohup tailscaled --tun=userspace-networking \
                                --state="$DIR/.tailscale/tailscaled.state" \
                                --socks5-server=localhost:1055 \
                                --outbound-http-proxy-listen=localhost:1055 > "$DIR/tailscaled.log" 2>&1 &
                            sleep 2
                        fi
                        if [ -n "$AUTHKEY" ]; then
                            echo "使用 Authkey 登入 Tailscale..."
                            tailscale up --authkey="$AUTHKEY" --hostname="colab-llm-station"
                        else
                            echo "互動式登入 Tailscale (請點擊終端輸出的驗證連結或掃描 QR)："
                            tailscale up --hostname="colab-llm-station" --qr
                        fi
                        ;;
                    status)
                        tailscale status || true
                        ;;
                    down)
                        tailscale down || true
                        ;;
                    serve)
                        PORT="${4:-8000}"
                        echo "配置 Tailscale Serve (將本機 $PORT 映射給 Tailnet 私網成員)..."
                        tailscale serve --bg "$PORT"
                        ;;
                    *)
                        echo "用法: ./llm.sh tunnel tailscale [up|status|down|serve] [authkey/port]"
                        ;;
                esac
                ;;
            *)
                echo "用法: ./llm.sh tunnel [cloudflare|tailscale]"
                ;;
        esac
        ;;

    sync)
        "$DIR/sync_git.sh"
        ;;

    *)
        show_help
        ;;
esac
