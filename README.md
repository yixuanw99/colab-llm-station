# Colab LLM Station

A reproducible, dual-engine inference and networking deployment framework designed for Google Colab and cloud GPU environments.

[English] | [繁體中文](README_zh.md)

---

## Architectural Overview

Colab LLM Station is built to address two major operational challenges in cloud GPU environments:
1. **Dynamic Hardware Allocations**: Automated adaptation between high-throughput serving for enterprise GPUs (NVIDIA A100/H100) and memory-efficient GGUF execution for standard tiers (T4/L4/V100).
2. **Access Control & Ingress**: Native support for zero-trust private networking (Tailscale) and instant public ingress (Cloudflare Tunnel).

```
                      +-----------------------------+
                      |      Colab LLM Station      |
                      +--------------+--------------+
                                     |
              +----------------------+----------------------+
              |                                             |
              v                                             v
     Inference Engines                              Networking Tunnels
+----------------------------+                +----------------------------+
| vLLM (Port 8000)           |                | Tailscale (Production)     |
| - PagedAttention           |                | - WireGuard Mesh Network   |
| - Continuous Batching      |                | - Zero Public Exposure     |
| - Safetensors / AWQ / FP8  |                | - Userspace Networking     |
+----------------------------+                +----------------------------+
| Ollama (Port 11434)        |                | Cloudflare Tunnel (POC)    |
| - Low-memory footprint     |                | - Public HTTPS Ingress     |
| - GGUF Quantization        |                | - No Account Required      |
| - T4 / L4 OOM Protection   |                | - Instant Verification     |
+----------------------------+                +----------------------------+
```

---

## Hardware Adaptation & Engine Matrix

| Component | Enterprise Tier (A100 / H100) | Standard Tier (T4 / L4 / V100) |
| :--- | :--- | :--- |
| **Engine** | **vLLM** (Default port: 8000) | **Ollama** (Default port: 11434) |
| **Model Format** | Hugging Face Safetensors, AWQ, FP8 | GGUF Quantized |
| **Throughput** | High concurrent throughput via PagedAttention | Optimized for single-stream generation |
| **Memory Strategy**| Dynamic KV cache allocation (up to 90% VRAM) | Compact memory allocation to prevent OOM |

---

## Reproducibility & Version Locking

All runtime components are locked to verified versions via `versions.env` and `requirements.lock` to guarantee deterministic provisioning:

* **Ollama**: `v0.34.4`
* **vLLM**: `v0.30.0`
* **Cloudflared**: `v2026.9.3`
* **Tailscale**: `v1.102.4`

---

## Quickstart

### 1. Provisioning
Execute the bootstrap script to restore the environment:

```bash
cd /content/drive/MyDrive/colab/colab-llm-station
bash setup.sh
```

### 2. Runtime Status
Inspect hardware metrics, active engines, and network tunnels:

```bash
./llm.sh status
```

---

## CLI Reference (`./llm.sh`)

### Engine Operations: vLLM
```bash
# Launch background vLLM OpenAI-compatible server (default: port 8000)
./llm.sh vllm serve Qwen/Qwen2.5-Coder-32B-Instruct

# Run throughput and latency benchmark
./llm.sh vllm bench Qwen/Qwen2.5-Coder-32B-Instruct

# Interactive shell
./llm.sh vllm chat Qwen/Qwen2.5-Coder-32B-Instruct

# Terminate server
./llm.sh vllm stop
```

### Engine Operations: Ollama
```bash
# Launch background Ollama daemon (port 11434)
./llm.sh ollama serve

# Pull model from registry
./llm.sh ollama pull qwen3.8:27b

# Benchmark model
./llm.sh ollama bench qwen3.8:27b

# Interactive shell
./llm.sh ollama chat qwen3.8:27b
```

### Networking & Ingress

#### Tailscale (Secure Private Mesh)
```bash
# Authenticate and connect to Tailnet
./llm.sh tunnel tailscale up [AUTHKEY]

# Check node connection status
./llm.sh tunnel tailscale status

# Expose local port to Tailnet members
./llm.sh tunnel tailscale serve 8000
```
*Allows direct internal access from development workstations via `http://colab-llm-station:8000/v1` without public exposure.*

#### Cloudflare Tunnel (Temporary Public POC)
```bash
./llm.sh tunnel cloudflare [PORT]
```
*Generates an ephemeral public HTTPS endpoint (`https://*.trycloudflare.com`) routing to the active engine.*

---

## Client Integration: OpenCode (v2)

Colab LLM Station integrates seamlessly with [OpenCode](https://opencode.ai) over your private Tailnet using the official OpenCode v2 provider specification.

### 1. Configuration (`opencode.json` / `opencode.jsonc`)

Place the following configuration in your project root or at `%USERPROFILE%\.config\opencode\opencode.json` (Windows) / `~/.config/opencode/opencode.json` (Linux/macOS):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "providers": {
    "colab-station": {
      "package": "@opencode/ai/providers/openai-compatible",
      "name": "Colab LLM Station",
      "settings": {
        "baseURL": "http://colab-llm-station:11434/v1",
        "apiKey": "ollama"
      },
      "models": {
        "qwen3.8:27b": {
          "name": "Qwen 3.8 (27B)",
          "limit": { "context": 262144, "output": 16384 }
        },
        "deepseek-r1:32b": {
          "name": "DeepSeek R1 (32B)",
          "limit": { "context": 131072, "output": 16384 }
        },
        "qwen2.5-coder:32b": {
          "name": "Qwen 2.5 Coder (32B)",
          "limit": { "context": 32768, "output": 16384 }
        }
      }
    }
  }
}
```

> Note: If serving via vLLM, switch the `baseURL` port to `8000` and specify the respective Hugging Face model identifier.

### 2. Windows PowerShell Quick Setup

Run the following command in PowerShell on your client machine to auto-generate the configuration:

```powershell
New-Item -ItemType Directory -Force "$HOME\.config\opencode" | Out-Null
Copy-Item "templates\opencode.json" -Destination "$HOME\.config\opencode\opencode.json"
```

### 3. Usage
Restart OpenCode (`opencode service restart` or restart the desktop app) and run `/models` to select any loaded model.

---

## Git Synchronization

```bash
# Push updates to remote repository
./llm.sh sync
```
*(Pre-configured `.gitignore` prevents tracking of model binaries, logs, and sensitive credentials).*

