#!/usr/bin/env bash
# ==============================================================================
# Colab LLM Station - 全功能環境一鍵還原與部署腳本
# 包含：雙推論引擎 (vLLM / Ollama) + 雙通道 (Tailscale / Cloudflare)
# ==============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

MODE="${1:-all}"

echo "================================================================================"
echo " 正在為 Google Colab 部署 LLM 工作站 (安裝模式: $MODE)"
echo "================================================================================"

# 1. 系統基礎套件
echo "=== [1/5] 檢查系統核心依賴 ==="
apt-get update -qq
apt-get install -y -qq zstd pciutils curl git iptables

# 2. 網絡通道工具 (Cloudflare & Tailscale)
if [[ "$MODE" == "all" ]] || [[ "$MODE" == "tunnels" ]]; then
    echo "=== [2/5] 安裝網絡通道工具 (Cloudflare + Tailscale) ==="
    # Cloudflared
    if ! command -v cloudflared &> /dev/null; then
        echo "安裝 cloudflared..."
        curl -L -s --output /tmp/cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        dpkg -i /tmp/cloudflared.deb > /dev/null 2>&1
        rm /tmp/cloudflared.deb
    else
        echo "cloudflared 已就緒: $(cloudflared --version | head -n 1)"
    fi

    # Tailscale
    if ! command -v tailscale &> /dev/null; then
        echo "安裝 Tailscale..."
        curl -fsSL https://tailscale.com/install.sh | sh
    else
        echo "Tailscale 已就緒: $(tailscale version | head -n 1)"
    fi
    mkdir -p /content/drive/MyDrive/colab/colab-llm-station/.tailscale
fi

# 3. 輕量級引擎 Ollama
if [[ "$MODE" == "all" ]] || [[ "$MODE" == "ollama" ]]; then
    echo "=== [3/5] 安裝/檢查 Ollama 引擎 ==="
    if ! command -v ollama &> /dev/null; then
        curl -fsSL https://ollama.com/install.sh | sh
    else
        echo "Ollama 已就緒: $(ollama --version)"
    fi
fi

# 4. 企業級引擎 vLLM
if [[ "$MODE" == "all" ]] || [[ "$MODE" == "vllm" ]]; then
    echo "=== [4/5] 安裝/檢查 vLLM 生產級推論引擎 ==="
    if ! python3 -c "import vllm" 2>/dev/null; then
        echo "正在安裝 vLLM 與相依套件..."
        pip install -q vllm
    fi
    # 解決 torchaudio CUDA 版本不一致問題
    if python3 -c "import torchaudio" 2>/dev/null; then
        pip uninstall -y -q torchaudio || true
    fi
    echo "vLLM 已就緒: $(python3 -c 'import vllm; print(vllm.__version__)')"
fi

echo "=== [5/5] 完成環境配置 ==="
chmod +x "$DIR/llm.sh" "$DIR/sync_git.sh"

echo "================================================================================"
echo " 🎉 工作站環境安裝完成！"
echo " 快速指引："
echo "   1. 查看硬體與建議:      ./llm.sh status"
echo "   2. 啟動企業級 vLLM:     ./llm.sh vllm serve [model]"
echo "   3. 啟動輕量級 Ollama:   ./llm.sh ollama serve"
echo "   4. 啟動 Cloudflare 穿透: ./llm.sh tunnel cloudflare"
echo "   5. 登入 Tailscale 私網:  ./llm.sh tunnel tailscale up [authkey]"
echo "================================================================================"
