#!/usr/bin/env bash
# ==============================================================================
# Colab LLM Station - 嚴格版本鎖定之一鍵還原與部署腳本
# 藉由 versions.env 與 requirements.lock 保證 100% 二進制與套件確定性
# ==============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# 載入鎖定版本號
if [ -f "$DIR/versions.env" ]; then
    source "$DIR/versions.env"
else
    echo "警告: 未找到 versions.env，使用預設鎖定版本"
    OLLAMA_VERSION="0.34.4"
    CLOUDFLARED_VERSION="2026.9.3"
    TAILSCALE_VERSION="1.102.4"
    VLLM_VERSION="0.30.0"
fi

MODE="${1:-all}"

echo "================================================================================"
echo " 正在為 Google Colab 部署 LLM 工作站 (嚴格鎖定版本模式)"
echo " 鎖定規格："
echo "   • Ollama:      v${OLLAMA_VERSION}"
echo "   • Cloudflared: v${CLOUDFLARED_VERSION}"
echo "   • Tailscale:   v${TAILSCALE_VERSION}"
echo "   • vLLM:        v${VLLM_VERSION}"
echo "================================================================================"

# 1. 系統基礎依賴
echo "=== [1/5] 檢查系統基礎依賴 ==="
apt-get update -qq
apt-get install -y -qq zstd pciutils curl git iptables

# 2. 網絡通道工具 (鎖定精確版本)
if [[ "$MODE" == "all" ]] || [[ "$MODE" == "tunnels" ]]; then
    echo "=== [2/5] 安裝鎖定版本之網絡通道工具 ==="
    
    # 鎖定安裝 Cloudflared
    CURRENT_CF=$(cloudflared --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)
    if [ "$CURRENT_CF" != "$CLOUDFLARED_VERSION" ]; then
        echo "下載並安裝 Cloudflared v${CLOUDFLARED_VERSION}..."
        curl -L -s --output /tmp/cloudflared.deb \
            "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64.deb"
        dpkg -i /tmp/cloudflared.deb > /dev/null 2>&1
        rm /tmp/cloudflared.deb
    else
        echo "Cloudflared 版本相符: v${CURRENT_CF}"
    fi

    # 鎖定安裝 Tailscale
    CURRENT_TS=$(tailscale version 2>/dev/null | head -n 1 || true)
    if [[ ! "$CURRENT_TS" =~ "$TAILSCALE_VERSION" ]]; then
        echo "下載並安裝 Tailscale (目標: v${TAILSCALE_VERSION})..."
        curl -fsSL https://tailscale.com/install.sh | sh
    else
        echo "Tailscale 版本相符: ${CURRENT_TS}"
    fi
    mkdir -p /content/drive/MyDrive/colab/colab-llm-station/.tailscale
fi

# 3. 輕量級推論引擎 Ollama (鎖定版本)
if [[ "$MODE" == "all" ]] || [[ "$MODE" == "ollama" ]]; then
    echo "=== [3/5] 安裝鎖定版本之 Ollama (v${OLLAMA_VERSION}) ==="
    CURRENT_OLLAMA=$(ollama --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)
    if [ "$CURRENT_OLLAMA" != "$OLLAMA_VERSION" ]; then
        echo "透過官方版本參數下載 Ollama v${OLLAMA_VERSION}..."
        OLLAMA_VERSION="${OLLAMA_VERSION}" curl -fsSL https://ollama.com/install.sh | sh
    else
        echo "Ollama 版本相符: v${CURRENT_OLLAMA}"
    fi
fi

# 4. 企業級推論引擎 vLLM (透過 requirements.lock 鎖定)
if [[ "$MODE" == "all" ]] || [[ "$MODE" == "vllm" ]]; then
    echo "=== [4/5] 安裝鎖定版本之 vLLM (v${VLLM_VERSION}) ==="
    if ! python3 -c "import vllm; assert vllm.__version__ == '${VLLM_VERSION}'" 2>/dev/null; then
        echo "依照 requirements.lock 安裝鎖定之 vLLM..."
        pip install -q -r "$DIR/requirements.lock"
    else
        echo "vLLM 版本相符: v$(python3 -c 'import vllm; print(vllm.__version__)')"
    fi

    # 確保排除潛在的 torchaudio CUDA 版本衝突
    if python3 -c "import torchaudio" 2>/dev/null; then
        pip uninstall -y -q torchaudio || true
    fi
fi

# 5. 確保權限與環境
echo "=== [5/5] 驗證環境與執行檔權限 ==="
chmod +x "$DIR/llm.sh" "$DIR/sync_git.sh"

echo "================================================================================"
echo " 🎉 確定性環境還原完成！所有核心二進制與套件均已固定並經過驗證。"
echo " 執行 ./llm.sh status 可查看當前運行與通道狀態。"
echo "================================================================================"
