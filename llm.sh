#!/usr/bin/env bash
# ==============================================================================
# Colab LLM Station - Unified CLI Manager
# Dual Inference Engines (vLLM / Ollama) & Dual Networking (Tailscale / Cloudflare)
# ==============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$DIR/configs"
SCRIPTS_DIR="$DIR/scripts"
TOOLS_DIR="$DIR/tools"
LOG_DIR="$DIR/logs"

mkdir -p "$LOG_DIR"
cd "$DIR"

function detect_hardware() {
    if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
        GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -n 1)
        GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n 1 | tr -dc '0-9')
        GPU_MEM="${GPU_MEM:-0}"
    else
        GPU_NAME="None"
        GPU_MEM="0"
    fi
    
    echo "=== Hardware Profile ==="
    echo "Detected GPU: $GPU_NAME (${GPU_MEM} MB VRAM)"
    
    if [[ "$GPU_NAME" =~ "A100" ]] || [[ "$GPU_NAME" =~ "H100" ]] || [[ "$GPU_MEM" -gt 60000 ]]; then
        echo "Recommendation: Enterprise GPU detected. Use [vLLM] for high-throughput serving and PagedAttention."
    elif [[ "$GPU_NAME" =~ "T4" ]] || [[ "$GPU_NAME" =~ "V100" ]] || [[ "$GPU_NAME" =~ "L4" ]] || [[ "$GPU_MEM" -lt 30000 ]]; then
        echo "Recommendation: Standard GPU detected. Use [Ollama] (GGUF format) to prevent Out-Of-Memory errors."
    else
        echo "Recommendation: Select vLLM or Ollama depending on target workload."
    fi
}

function show_help() {
    echo "================================================================================"
    echo "Colab LLM Station - Multi-Engine & Tunnel Management Utility"
    echo "================================================================================"
    echo "Usage: ./llm.sh [command] [options...]"
    echo ""
    echo "General Commands:"
    echo "  setup [mode]             Provision environment (ollama, vllm, tunnels, or all)"
    echo "  status                   Display GPU metrics, active engines, and network tunnels"
    echo "  list                     Show catalogue of recommended models for vLLM & Ollama"
    echo "  test                     Run automated inference latency and output verification"
    echo "  sync                     Stage, commit, and push updates to remote Git repository"
    echo ""
    echo "Engine: vLLM (Port 8000, high-concurrency, Safetensors / AWQ):"
    echo "  vllm start [model]       Launch background vLLM OpenAI-compatible server"
    echo "  vllm stop                Terminate running vLLM server instance"
    echo "  vllm logs                Tail live vLLM output logs"
    echo "  vllm bench [model]       Execute throughput and latency benchmark"
    echo "  vllm chat [model]        Start interactive CLI session via vLLM endpoint"
    echo ""
    echo "Engine: Ollama (Port 11434, lightweight GGUF format):"
    echo "  ollama start             Ensure background Ollama daemon is running"
    echo "  ollama stop              Terminate running Ollama daemon"
    echo "  ollama logs              Tail live Ollama output logs"
    echo "  ollama pull <model>      Download GGUF model from registry (e.g. qwen3.8:27b)"
    echo "  ollama chat [model]      Start interactive multi-turn chat session"
    echo "  ollama bench [model]     Run generation performance benchmark"
    echo "  ollama list              List all locally cached Ollama models"
    echo ""
    echo "Network & Remote IDE Tunnels:"
    echo "  tunnel cloudflare [port] Create public HTTPS endpoint via Cloudflare Tunnel (POC)"
    echo "  tunnel tailscale [cmd]   Manage private mesh network via Tailscale (Production)"
    echo "                           Subcommands: up, status, down, serve [port]"
    echo "  tunnel vscode [cmd]      Manage VS Code Remote Tunnel (Web & Desktop IDE)"
    echo "                           Subcommands: setup, login, start [name], status, stop"
    echo "================================================================================"
}

CMD="${1:-help}"

case "$CMD" in
    setup)
        "$SCRIPTS_DIR/setup.sh" "${@:2}"
        ;;

    status)
        detect_hardware
        echo -e "\n=== Engine Status ==="
        if curl -s http://127.0.0.1:8000/v1/models &> /dev/null; then
            echo "[RUNNING] vLLM Service (Port: 8000)"
        else
            echo "[STOPPED] vLLM Service"
        fi
        
        if curl -s http://127.0.0.1:11434/api/version &> /dev/null; then
            echo "[RUNNING] Ollama Service (Port: 11434)"
        else
            echo "[STOPPED] Ollama Service"
        fi

        echo -e "\n=== Network Tunnel Status ==="
        CF_URL=$(grep -o 'https://[-a-zA-Z0-9.]*\.trycloudflare\.com' "$LOG_DIR/tunnel.log" 2>/dev/null | tail -n 1 || true)
        if [ -n "$CF_URL" ] && pgrep -f "cloudflared tunnel" > /dev/null; then
            echo "[ACTIVE]  Cloudflare Public Tunnel: $CF_URL"
        else
            echo "[INACTIVE] Cloudflare Public Tunnel"
        fi

        if tailscale status 2>/dev/null | grep -qv "Logged out"; then
            echo "[ACTIVE]  Tailscale Mesh Network"
            tailscale status | head -n 3
        else
            echo "[INACTIVE] Tailscale Mesh Network (Run './llm.sh tunnel tailscale up')"
        fi

        if pgrep -f "code tunnel" > /dev/null; then
            VSCODE_NAME=$(grep -o '"name": *"[^"]*"' /root/.vscode/cli/code_tunnel.json 2>/dev/null | cut -d'"' -f4 || echo "my-colab-gpu")
            echo "[ACTIVE]  VS Code Remote Tunnel (Name: $VSCODE_NAME)"
            echo "          Endpoint: https://vscode.dev/tunnel/$VSCODE_NAME"
        else
            echo "[INACTIVE] VS Code Remote Tunnel (Run './llm.sh tunnel vscode start')"
        fi
        ;;

    list)
        python3 -c "
import json
with open('$CONFIG_DIR/models.json') as f:
    d = json.load(f)
print('=== vLLM Models (Production / A100 / H100) ===')
for m, v in d['engines']['vllm']['models'].items():
    print(f'• {m:<42} | ~{v[\"vram_gb\"]}GB | {v[\"description\"]}')
print('\n=== Ollama Models (Lightweight / T4 / L4) ===')
for m, v in d['engines']['ollama']['models'].items():
    print(f'• {m:<25} | ~{v[\"vram_gb\"]}GB | {v[\"description\"]}')
"
        ;;

    test)
        python3 "$TOOLS_DIR/test_inference.py" "${@:2}"
        ;;

    vllm)
        SUBCMD="${2:-help}"
        case "$SUBCMD" in
            serve|start)
                MODEL="${3:-Qwen/Qwen2.5-Coder-32B-Instruct-AWQ}"
                MAX_LEN="${VLLM_MAX_MODEL_LEN:-32768}"
                echo "[INFO] Starting vLLM server (Model: $MODEL, MaxLen: $MAX_LEN, Port: 8000)..."
                nohup vllm serve "$MODEL" \
                    --port 8000 \
                    --trust-remote-code \
                    --max-model-len "$MAX_LEN" \
                    --gpu-memory-utilization 0.90 \
                    --enable-auto-tool-choice \
                    --tool-call-parser hermes > "$LOG_DIR/vllm.log" 2>&1 &
                echo "$!" > "$LOG_DIR/vllm.pid" 2>/dev/null || true
                echo "[INFO] Daemon started. Logs: $LOG_DIR/vllm.log"
                echo "[INFO] Waiting for endpoint readiness..."
                # Wait up to 360 seconds (180 iterations * 2s) for model loading & CUDA graph compilation
                for i in {1..180}; do
                    if curl -s http://127.0.0.1:8000/v1/models &> /dev/null; then
                        echo "[SUCCESS] vLLM endpoint ready at http://127.0.0.1:8000/v1"
                        exit 0
                    fi
                    if ! pgrep -f "vllm serve" > /dev/null; then
                        echo "[ERROR] vLLM process died unexpectedly during startup. Last log entries:"
                        tail -n 25 "$LOG_DIR/vllm.log"
                        exit 1
                    fi
                    if (( i % 15 == 0 )); then
                        echo "[INFO] Still loading weights and compiling CUDA graphs ($((i * 2))s elapsed)..."
                    fi
                    sleep 2
                done
                echo "[WARN] Server is still loading weights after 6 minutes. Monitor progress with 'tail -f $LOG_DIR/vllm.log'."
                ;;
            stop)
                echo "[INFO] Terminating vLLM process..."
                pkill -f "vllm serve" || true
                pkill -f "VLLM::EngineCore" || true
                rm -f "$LOG_DIR/vllm.pid" 2>/dev/null || true
                echo "[SUCCESS] Process terminated."
                ;;
            logs)
                tail -n 50 -f "$LOG_DIR/vllm.log"
                ;;
            bench)
                MODEL="${3:-Qwen/Qwen2.5-Coder-32B-Instruct}"
                python3 "$TOOLS_DIR/benchmark.py" --engine vllm --port 8000 --model "$MODEL"
                ;;
            chat)
                MODEL="${3:-Qwen/Qwen2.5-Coder-32B-Instruct}"
                python3 "$TOOLS_DIR/chat.py" --engine vllm --port 8000 --model "$MODEL"
                ;;
            *)
                echo "Usage: ./llm.sh vllm [start|stop|logs|bench|chat] [model]"
                ;;
        esac
        ;;

    ollama)
        SUBCMD="${2:-help}"
        case "$SUBCMD" in
            serve|start)
                if ! curl -s http://127.0.0.1:11434/api/version &> /dev/null; then
                    echo "[INFO] Starting Ollama daemon..."
                    OLLAMA_ORIGINS="*" OLLAMA_HOST="0.0.0.0:11434" nohup ollama serve > "$LOG_DIR/ollama.log" 2>&1 &
                    sleep 3
                fi
                echo "[SUCCESS] Ollama running at http://127.0.0.1:11434"
                ;;
            stop)
                echo "[INFO] Terminating Ollama daemon..."
                pkill -f "ollama serve" || true
                echo "[SUCCESS] Ollama stopped."
                ;;
            logs)
                tail -n 50 -f "$LOG_DIR/ollama.log"
                ;;
            pull)
                MODEL="$3"
                [ -z "$MODEL" ] && { echo "Error: Specify model identifier (e.g. ./llm.sh ollama pull qwen3.8:27b)"; exit 1; }
                ollama pull "$MODEL"
                ;;
            bench)
                MODEL="${3:-qwen3.8:27b}"
                python3 "$TOOLS_DIR/benchmark.py" --engine ollama --port 11434 --model "$MODEL"
                ;;
            chat)
                MODEL="${3:-qwen3.8:27b}"
                python3 "$TOOLS_DIR/chat.py" --engine ollama --port 11434 --model "$MODEL"
                ;;
            list)
                ollama list
                ;;
            *)
                echo "Usage: ./llm.sh ollama [start|stop|logs|pull|bench|chat|list] [model]"
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
                        echo "[INFO] Detected active vLLM service; routing tunnel to port 8000."
                    else
                        PORT=11434
                        echo "[INFO] Routing tunnel to Ollama service on port 11434."
                    fi
                fi
                echo "[INFO] Establishing Cloudflare Tunnel to 127.0.0.1:$PORT..."
                pkill -f "cloudflared tunnel" || true
                nohup cloudflared tunnel --url "http://127.0.0.1:$PORT" --logfile "$LOG_DIR/tunnel.log" > /dev/null 2>&1 &
                sleep 6
                CF_URL=$(grep -o 'https://[-a-zA-Z0-9.]*\.trycloudflare\.com' "$LOG_DIR/tunnel.log" | tail -n 1 || true)
                echo "================================================================"
                echo "Cloudflare Public Tunnel Established:"
                echo "  Base URL: $CF_URL/v1"
                echo "  Endpoint: $CF_URL"
                echo "================================================================"
                ;;
            tailscale)
                ACTION="${3:-status}"
                case "$ACTION" in
                    up)
                        AUTHKEY="${4:-$TAILSCALE_AUTHKEY}"
                        mkdir -p "$DIR/.tailscale"
                        if ! command -v tailscale > /dev/null 2>&1 || ! command -v tailscaled > /dev/null 2>&1; then
                            echo "[INFO] Tailscale not detected. Installing Tailscale..."
                            curl -fsSL https://tailscale.com/install.sh | sh
                        fi
                        if ! pgrep -f "tailscaled" > /dev/null; then
                            echo "[INFO] Starting tailscaled daemon (Userspace networking mode)..."
                            nohup tailscaled --tun=userspace-networking \
                                --state="$DIR/.tailscale/tailscaled.state" \
                                --socks5-server=localhost:1055 \
                                --outbound-http-proxy-listen=localhost:1055 > "$LOG_DIR/tailscaled.log" 2>&1 &
                            sleep 2
                        fi
                        if [ -n "$AUTHKEY" ]; then
                            echo "[INFO] Authenticating Tailscale with provided authkey (SSH enabled)..."
                            tailscale up --authkey="$AUTHKEY" --hostname="colab-llm-station" --ssh --accept-risk=all
                        else
                            echo "[INFO] Complete authentication via URL/QR (SSH enabled):"
                            tailscale up --hostname="colab-llm-station" --qr --ssh --accept-risk=all
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
                        echo "[INFO] Exposing local port $PORT to private Tailnet via TCP proxy..."
                        tailscale serve --bg --tcp "$PORT" "$PORT"
                        tailscale serve status
                        ;;
                    *)
                        echo "Usage: ./llm.sh tunnel tailscale [up|status|down|serve] [authkey/port]"
                        ;;
                esac
                ;;
            vscode)
                ACTION="${3:-status}"
                PERSIST_DIR="/content/drive/MyDrive/.vscode_colab"
                case "$ACTION" in
                    setup)
                        echo "[INFO] Checking VS Code CLI..."
                        if ! command -v code > /dev/null 2>&1; then
                            echo "[INFO] Downloading VS Code CLI..."
                            curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' --output /tmp/vscode_cli.tar.gz
                            tar -xf /tmp/vscode_cli.tar.gz -C /usr/local/bin
                            chmod +x /usr/local/bin/code
                            rm -f /tmp/vscode_cli.tar.gz
                        fi
                        mkdir -p "$PERSIST_DIR"
                        mkdir -p /root/.vscode/cli
                        if [ -f "$PERSIST_DIR/token.json" ]; then
                            echo "[INFO] Restoring credentials from Google Drive ($PERSIST_DIR)..."
                            cp -rn "$PERSIST_DIR"/* /root/.vscode/cli/ 2>/dev/null || true
                        fi
                        echo "[SUCCESS] VS Code CLI ready: $(code --version | head -n 1)"
                        ;;
                    login)
                        mkdir -p "$PERSIST_DIR"
                        mkdir -p /root/.vscode/cli
                        cp -rn "$PERSIST_DIR"/* /root/.vscode/cli/ 2>/dev/null || true
                        if code tunnel user show >/dev/null 2>&1; then
                            echo "[INFO] Already authenticated to VS Code Tunnel via GitHub:"
                            code tunnel user show
                        else
                            echo "[INFO] Authenticating VS Code Tunnel via GitHub..."
                            code tunnel user login --provider github
                            cp -f /root/.vscode/cli/token.json /root/.vscode/cli/code_tunnel.json "$PERSIST_DIR/" 2>/dev/null || true
                            echo "[SUCCESS] Credentials saved to $PERSIST_DIR for persistence across sessions."
                        fi
                        ;;
                    start)
                        NAME="${4:-my-colab-gpu}"
                        mkdir -p "$PERSIST_DIR"
                        mkdir -p /root/.vscode/cli
                        cp -rn "$PERSIST_DIR"/* /root/.vscode/cli/ 2>/dev/null || true
                        if pgrep -f "code tunnel" > /dev/null; then
                            echo "[WARN] VS Code Tunnel is already running."
                        else
                            echo "[INFO] Starting VS Code Remote Tunnel (Name: $NAME)..."
                            nohup code tunnel --accept-server-license-terms --name "$NAME" > "$LOG_DIR/vscode_tunnel.log" 2>&1 &
                            sleep 4
                        fi
                        echo "================================================================"
                        echo "VS Code Remote Tunnel Status:"
                        echo "  Machine Name: $NAME"
                        echo "  Web URL:      https://vscode.dev/tunnel/$NAME"
                        echo "  Log File:     $LOG_DIR/vscode_tunnel.log"
                        echo "================================================================"
                        ;;
                    status)
                        if pgrep -f "code tunnel" > /dev/null; then
                            echo "[ACTIVE] VS Code Remote Tunnel is running."
                            code tunnel status || true
                        else
                            echo "[INACTIVE] VS Code Remote Tunnel is not running."
                        fi
                        ;;
                    stop)
                        echo "[INFO] Stopping VS Code Tunnel..."
                        pkill -f "code tunnel" || true
                        echo "[SUCCESS] VS Code Tunnel stopped."
                        ;;
                    *)
                        echo "Usage: ./llm.sh tunnel vscode [setup|login|start [name]|status|stop]"
                        ;;
                esac
                ;;
            stop)
                echo "[INFO] Terminating all tunnel services..."
                pkill -f "cloudflared" || true
                tailscale serve reset || true
                pkill -f "code tunnel" || true
                echo "[SUCCESS] All tunnels stopped."
                ;;
            *)
                echo "Usage: ./llm.sh tunnel [cloudflare|tailscale|vscode|stop]"
                ;;
        esac
        ;;

    sync)
        "$SCRIPTS_DIR/sync_git.sh"
        ;;

    *)
        show_help
        ;;
esac
