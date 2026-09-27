# Colab LLM Station

A reproducible, dual-engine inference and networking deployment framework designed for Google Colab and cloud GPU environments.

[English] | [繁體中文](README_zh.md)

---

## Architectural Overview

Colab LLM Station is built to address two major operational challenges in cloud GPU environments:
1. **Dynamic Hardware Allocations**: Automated adaptation between high-throughput serving for enterprise GPUs (NVIDIA A100/H100) and memory-efficient GGUF execution for standard tiers (T4/L4/V100).
2. **Access Control & Ingress**: Native support for zero-trust private networking (Tailscale), instant public ingress (Cloudflare Tunnel), and persistent-authenticated remote IDE development (VS Code Remote Tunnel).

```
                      +-----------------------------+
                      |      Colab LLM Station      |
                      +--------------+--------------+
                                     |
              +----------------------+----------------------+
              |                                             |
              v                                             v
     Inference Engines                          Networking & Remote Tunnels
+----------------------------+                +----------------------------+
| vLLM (Port 8000)           |                | Tailscale (Production)     |
| - PagedAttention           |                | - WireGuard Mesh Network   |
| - Continuous Batching      |                | - Zero Public Exposure     |
| - Safetensors / AWQ / FP8  |                +----------------------------+
+----------------------------+                | Cloudflare Tunnel (POC)    |
| Ollama (Port 11434)        |                | - Public HTTPS Ingress     |
| - Low-memory footprint     |                | - No Account Required      |
| - GGUF Quantization        |                +----------------------------+
| - T4 / L4 OOM Protection   |                | VS Code Tunnel (Dev IDE)   |
+----------------------------+                | - Full Remote Desktop IDE  |
                                              | - Persistent Auth in Drive |
                                              +----------------------------+
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

All runtime components are locked to verified versions via `configs/versions.env` and `configs/requirements.lock` to guarantee deterministic provisioning:

* **Ollama**: `v0.34.4`
* **vLLM**: `v0.30.0`
* **Cloudflared**: `v2026.9.3`
* **Tailscale**: `v1.102.4`
* **VS Code CLI**: Stable x64

---

## Repository Architecture

```
colab-llm-station/
├── llm.sh                  # Master CLI lifecycle controller (vLLM, Ollama, Tailscale, Cloudflare)
├── setup.sh                # Root forwarder -> scripts/setup.sh
├── sync_git.sh             # Root forwarder -> scripts/sync_git.sh
├── colab_station.ipynb     # Primary interactive deployment notebook (English source of truth)
├── colab_station-zh.ipynb  # Mirrored interactive deployment notebook (Traditional Chinese)
├── AGENTS.md               # AI agent operating standards & execution guardrails
├── configs/                # Central configurations, models catalog, and version locks
│   ├── models.json         # Model catalog and hardware recommendations
│   ├── versions.env        # Pinned binary and system versions
│   └── requirements.lock   # Pinned Python package dependencies
├── scripts/                # Shell automation & lifecycle scripts
│   ├── setup.sh            # Environment bootstrap & dependency installer
│   └── sync_git.sh         # Non-interactive Git commit & push synchronization tool
├── tools/                  # Python diagnostic, benchmarking, and interactive CLI utilities
│   ├── benchmark.py        # Latency, TTFT, and generation throughput benchmarking utility
│   ├── chat.py             # Interactive terminal chat client for local testing
│   ├── test_inference.py   # Automated engine diagnostic script
│   └── api_client_example.py # OpenAI-compatible client API usage sample
├── templates/
│   └── opencode.json       # OpenCode client configuration template for Tailscale mesh
└── logs/                   # Dedicated directory for runtime logs and PID files (git-ignored)
```

---

## Quickstart (Colab Notebook Execution Flow)

This repository provides ready-to-run Jupyter notebooks: **[`colab_station.ipynb`](colab_station.ipynb)** (English) and **[`colab_station-zh.ipynb`](colab_station-zh.ipynb)** (繁體中文). You can open and run them directly in Google Colab.

### Step 0: Prerequisites & Tailscale Auth Key Setup (One-Time Configuration)

Google Colab runtimes reside behind internal network address translation (NAT) without dedicated public IPv4 addresses. An ephemeral Tailscale Auth Key enables headless, automated authentication during runtime boot without manual browser logins or QR codes.

#### 1. Generate Auth Key in Tailscale Admin Console
1. Navigate to the [Tailscale Admin Console - Settings - Keys](https://login.tailscale.com/admin/settings/keys).
2. Click **Generate auth key**.
3. Configure the key parameters:
   * **Description**: Enter an identifier, e.g., `colab-llm-station`.
   * **Reusable**: **Enabled**. Permits key reuse across multiple Colab runtime restarts.
   * **Ephemeral**: **Enabled (Crucial)**. Automatically deregisters offline nodes when Colab disconnects, preventing accumulation of zombie hosts in your Tailnet.
   * **Pre-authorized**: **Enabled**. Automatically approves the device into your network without manual admin approval.
   * **Tags** (Optional): Assign tags if mandated by your Tailnet ACL policy (e.g., `tag:server`).
4. Click **Generate key** and copy the generated `tskey-auth-...` string. Tailscale displays this key only once.

#### 2. Configure Google Colab Secrets
1. In Google Colab, open the left navigation panel and select the **Secrets** panel (padlock/key icon).
2. Click **Add new secret**.
3. Enter the required fields:
   * **Name**: `TAILSCALE_AUTHKEY` (case-sensitive).
   * **Value**: Paste your `tskey-auth-...` key string.
   * *(Optional)* Add `HF_TOKEN` with your Hugging Face Access Token if downloading gated models.
4. Toggle the **Notebook access** switch to **ON** to permit runtime access via `google.colab.userdata`.

---

### Step 1: [Optional] Standalone SSH Startup Cell in Colab
> **Note**: This step is strictly **optional**. If you only want to serve LLM inference endpoints via Cloudflare or Tailscale without remote terminal access, you can skip this step and proceed directly to Step 3.

Run the following cell in your Colab notebook (or run Step 1 in [`colab_station.ipynb`](colab_station.ipynb)):

```python
# ==============================================================================
# [OPTIONAL] Standalone SSH Startup Cell (Tailscale SSH: Zero-config, Passwordless)
# ==============================================================================
import os
from google.colab import userdata

# 1. Retrieve Secrets & Set Environment Variables
os.environ['TAILSCALE_AUTHKEY'] = userdata.get('TAILSCALE_AUTHKEY')
try:
    os.environ['HF_TOKEN'] = userdata.get('HF_TOKEN')
except Exception:
    pass

# 2. Clone Repository to Local Instance Storage
!git clone https://github.com/yixuanw99/colab-llm-station.git /content/colab-llm-station 2>/dev/null || (cd /content/colab-llm-station && git pull)

# 3. Connect to Tailscale with Native SSH Server (Instant connection, zero setup overhead)
!cd /content/colab-llm-station && bash llm.sh tunnel tailscale up "$TAILSCALE_AUTHKEY"

print("\n" + "="*60)
print("[OK] Tailscale SSH service is ready.")
print("1. Local Terminal Connection:")
print("   ssh root@colab-llm-station")
print("\n2. Local VS Code (Remote - SSH) Connection:")
print("   Press F1 -> Select Remote-SSH: Connect to Host... -> root@colab-llm-station")
print("   (Open Folder: /content/colab-llm-station)")
print("="*60)
```

---

### Step 2: [Optional] Connect from Local Workstation

#### Option A: Direct Terminal Connection (PowerShell / macOS Terminal / Linux)
```bash
ssh root@colab-llm-station
```
*(Tailscale handles identity verification automatically—zero passwords or SSH keys required!)*

#### Option B: VS Code Remote - SSH Development
1. In your local VS Code, install the official extension **"Remote - SSH"** (`ms-vscode-remote.remote-ssh`).
2. Press `F1`, search and choose `Remote-SSH: Connect to Host...`.
3. Enter `root@colab-llm-station`.
4. Once connected, click "Open Folder" and select `/content/colab-llm-station`!
*(Also works identically with Cursor, Zed, and PyCharm Gateway)*.

---

### Step 3: Choose Deployment Solution & Serve Inference
Provision the environment and launch your chosen combination (either in your connected SSH terminal or directly inside the Colab notebook):

#### Provision Dependencies (Run once per runtime)
```bash
cd /content/colab-llm-station

# Option A: Fast Ollama install for T4/L4 (~15 seconds)
bash setup.sh ollama

# Option B: High-throughput vLLM install for A100/H100 (~2-3 minutes)
# bash setup.sh vllm

# Option C: Full dual-engine installation
# bash setup.sh
```

#### Choose Your Combination:

* **Solution A: Ollama + Cloudflare Tunnel** *(Standard Tier T4/L4, Zero-config Public HTTPS)*
  ```bash
  bash llm.sh ollama pull qwen2.5-coder:7b
  bash llm.sh ollama serve
  bash llm.sh tunnel cloudflare 11434
  # Returns public HTTPS URL: https://<subdomain>.trycloudflare.com/v1
  ```

* **Solution B: Ollama + Tailscale Mesh** *(Standard Tier T4/L4, Private Encrypted Mesh)*
  ```bash
  bash llm.sh tunnel tailscale up "$TAILSCALE_AUTHKEY"
  bash llm.sh ollama pull qwen2.5-coder:32b
  bash llm.sh ollama serve
  bash llm.sh tunnel tailscale serve 11434
  # Reachable at: http://colab-llm-station:11434/v1
  ```

* **Solution C: vLLM + Tailscale Mesh** *(Enterprise Tier A100/H100, High Concurrency Private Mesh)*
  ```bash
  bash llm.sh tunnel tailscale up "$TAILSCALE_AUTHKEY"
  bash llm.sh tunnel tailscale serve 8000
  bash llm.sh vllm serve Qwen/Qwen2.5-Coder-32B-Instruct
  # Reachable at: http://colab-llm-station:8000/v1
  ```

* **Solution D: vLLM + Cloudflare Tunnel** *(Enterprise Tier A100/H100, High Performance Public HTTPS)*
  ```bash
  bash llm.sh vllm serve Qwen/Qwen2.5-72B-Instruct-AWQ
  bash llm.sh tunnel cloudflare 8000
  # Returns public HTTPS URL: https://<subdomain>.trycloudflare.com/v1
  ```

---

### Fallback: VS Code Remote Tunnel (Web IDE)
If Tailscale cannot be installed on your client machine or you require a browser-based `vscode.dev` environment:
<details>
<summary>Click to view VS Code Remote Tunnel Cell Code</summary>

```bash
%%bash
# 1. Download & Install VS Code CLI
if [ ! -f "/usr/local/bin/code" ]; then
    curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' --output /tmp/vscode_cli.tar.gz
    tar -xf /tmp/vscode_cli.tar.gz -C /usr/local/bin
    chmod +x /usr/local/bin/code
    rm -f /tmp/vscode_cli.tar.gz
fi

# 2. Drive persistence and login
PERSIST_DIR="/content/drive/MyDrive/.vscode_colab"
mkdir -p "$PERSIST_DIR" /root/.vscode/cli
cp -rn "$PERSIST_DIR"/* /root/.vscode/cli/ 2>/dev/null || true

if ! code tunnel user show >/dev/null 2>&1; then
    code tunnel user login --provider github
    cp -f /root/.vscode/cli/token.json /root/.vscode/cli/code_tunnel.json "$PERSIST_DIR/" 2>/dev/null || true
fi

# 3. Launch tunnel
code tunnel --accept-server-license-terms --name my-colab-gpu
```
</details>

---

## CLI Reference (`bash llm.sh`)

### Engine Operations: vLLM
```bash
# Launch background vLLM OpenAI-compatible server (default: port 8000)
bash llm.sh vllm serve Qwen/Qwen2.5-Coder-32B-Instruct

# Run throughput and latency benchmark
bash llm.sh vllm bench Qwen/Qwen2.5-Coder-32B-Instruct

# Interactive shell
bash llm.sh vllm chat Qwen/Qwen2.5-Coder-32B-Instruct

# Terminate server
bash llm.sh vllm stop
```

### Engine Operations: Ollama
```bash
# Launch background Ollama daemon (port 11434)
bash llm.sh ollama serve

# Pull model from registry
bash llm.sh ollama pull qwen3.8:27b

# Benchmark model
bash llm.sh ollama bench qwen3.8:27b

# Interactive shell
bash llm.sh ollama chat qwen3.8:27b
```

### Networking & Ingress

#### Tailscale (Secure Private Mesh)
```bash
# Authenticate and connect to Tailnet
bash llm.sh tunnel tailscale up [AUTHKEY]

# Check node connection status
bash llm.sh tunnel tailscale status

# Expose local port to Tailnet members
bash llm.sh tunnel tailscale serve 8000
```
*Allows direct internal access from development workstations via `http://colab-llm-station:8000/v1` without public exposure.*

#### Cloudflare Tunnel (Temporary Public POC)
```bash
bash llm.sh tunnel cloudflare [PORT]
```
*Generates an ephemeral public HTTPS endpoint (`https://*.trycloudflare.com`) routing to the active engine.*

#### VS Code Remote Tunnel (Web & Desktop IDE)
```bash
# Setup CLI and restore credentials from Google Drive
bash llm.sh tunnel vscode setup

# Authenticate with GitHub (auto-saved to Google Drive)
bash llm.sh tunnel vscode login

# Launch background tunnel
bash llm.sh tunnel vscode start [MACHINE_NAME]

# Check tunnel status
bash llm.sh tunnel vscode status

# Terminate tunnel
bash llm.sh tunnel vscode stop
```
*Develop directly in local VS Code or `vscode.dev` with full terminal, file tree, Git management, and live model debugging.*

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
bash llm.sh sync
```
*(Pre-configured `.gitignore` prevents tracking of model binaries, logs, and sensitive credentials).*

