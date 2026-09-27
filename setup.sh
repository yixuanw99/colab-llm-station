#!/usr/bin/env bash
# ==============================================================================
# Colab LLM Station - Idempotent Bootstrap & Version-Locked Provisioning
# Enforces exact binary versions via versions.env and requirements.lock
# ==============================================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

if [ -f "$DIR/versions.env" ]; then
    source "$DIR/versions.env"
else
    echo "[WARN] versions.env not found; using fallback pinned versions."
    OLLAMA_VERSION="0.34.4"
    CLOUDFLARED_VERSION="2026.9.3"
    TAILSCALE_VERSION="1.102.4"
    VLLM_VERSION="0.30.0"
fi

MODE="${1:-all}"

echo "================================================================================"
echo "Colab LLM Station - Environment Provisioning ($MODE mode)"
echo "Target Versions:"
echo "  - Ollama:      v${OLLAMA_VERSION}"
echo "  - Cloudflared: v${CLOUDFLARED_VERSION}"
echo "  - Tailscale:   v${TAILSCALE_VERSION}"
echo "  - vLLM:        v${VLLM_VERSION}"
echo "================================================================================"

# 1. Base OS Packages
echo "[Step 1/5] Checking OS dependencies..."
apt-get update -qq
apt-get install -y -qq zstd pciutils curl git iptables

# 2. Network Tunnels
if [[ "$MODE" == "all" ]] || [[ "$MODE" == "tunnels" ]]; then
    echo "[Step 2/5] Provisioning network tunneling utilities..."
    
    # Cloudflared
    CURRENT_CF=$(cloudflared --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)
    if [ "$CURRENT_CF" != "$CLOUDFLARED_VERSION" ]; then
        echo "[INFO] Installing cloudflared v${CLOUDFLARED_VERSION}..."
        curl -L -s --output /tmp/cloudflared.deb \
            "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64.deb"
        dpkg -i /tmp/cloudflared.deb > /dev/null 2>&1
        rm /tmp/cloudflared.deb
    else
        echo "[OK] Cloudflared version matched: v${CURRENT_CF}"
    fi

    # Tailscale
    CURRENT_TS=$(tailscale version 2>/dev/null | head -n 1 || true)
    if [[ ! "$CURRENT_TS" =~ "$TAILSCALE_VERSION" ]]; then
        echo "[INFO] Installing Tailscale v${TAILSCALE_VERSION}..."
        curl -fsSL https://tailscale.com/install.sh | sh
    else
        echo "[OK] Tailscale version matched: ${CURRENT_TS}"
    fi
    mkdir -p "$DIR/.tailscale"

    # VS Code CLI
    if ! command -v code > /dev/null 2>&1; then
        echo "[INFO] Installing VS Code CLI..."
        curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' --output /tmp/vscode_cli.tar.gz
        tar -xf /tmp/vscode_cli.tar.gz -C /usr/local/bin
        chmod +x /usr/local/bin/code
        rm -f /tmp/vscode_cli.tar.gz
    else
        echo "[OK] VS Code CLI version matched: $(code --version 2>/dev/null | head -n 1)"
    fi

    # Restore VS Code credentials from Google Drive if present
    PERSIST_VSCODE="/content/drive/MyDrive/.vscode_colab"
    if [ -d "$PERSIST_VSCODE" ]; then
        mkdir -p /root/.vscode/cli
        cp -rn "$PERSIST_VSCODE"/* /root/.vscode/cli/ 2>/dev/null || true
    fi
fi

# 3. Ollama Engine
if [[ "$MODE" == "all" ]] || [[ "$MODE" == "ollama" ]]; then
    echo "[Step 3/5] Provisioning Ollama engine..."
    CURRENT_OLLAMA=$(ollama --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true)
    if [ "$CURRENT_OLLAMA" != "$OLLAMA_VERSION" ]; then
        echo "[INFO] Installing Ollama v${OLLAMA_VERSION}..."
        OLLAMA_VERSION="${OLLAMA_VERSION}" curl -fsSL https://ollama.com/install.sh | sh
    else
        echo "[OK] Ollama version matched: v${CURRENT_OLLAMA}"
    fi
fi

# 4. vLLM Engine
if [[ "$MODE" == "all" ]] || [[ "$MODE" == "vllm" ]]; then
    echo "[Step 4/5] Provisioning vLLM engine..."
    if ! python3 -c "import vllm; assert vllm.__version__ == '${VLLM_VERSION}'" 2>/dev/null; then
        echo "[INFO] Installing pinned vLLM packages..."
        pip install -q -r "$DIR/requirements.lock"
    else
        echo "[OK] vLLM version matched: v$(python3 -c 'import vllm; print(vllm.__version__)')"
    fi

    # Remove conflicting torchaudio ABI package if present
    if python3 -c "import torchaudio" 2>/dev/null; then
        pip uninstall -y -q torchaudio || true
    fi
fi

# 5. Permissions
echo "[Step 5/5] Finalizing permissions..."
chmod +x "$DIR/llm.sh" "$DIR/sync_git.sh"

echo "================================================================================"
echo "[SUCCESS] Environment verified and locked. Ready for execution."
echo "Run './llm.sh status' to inspect current runtime status."
echo "================================================================================"
