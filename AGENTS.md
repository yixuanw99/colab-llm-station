# AGENTS.md

Instructions and operating standards for autonomous AI coding agents working on `colab-llm-station`.

---

## 1. System Overview & Purpose

`colab-llm-station` provides an automated, production-grade infrastructure for deploying high-performance Large Language Model (LLM) inference engines (vLLM and Ollama) on Google Colab GPU runtimes. It enables private, remote access from local developer workstations (e.g., OpenCode, Cursor, VS Code Remote SSH) via Tailscale Mesh network, Cloudflare Tunnels, or VS Code Tunnels.

---

## 2. Core Directives & Persona Constraints

All AI agents interacting with this repository or acting within this project must strictly comply with the following communication and behavioral standards:

### 2.1 Communication Style & Tone
- **Professional Engineering Standard**: Maintain an objective, concise, and authoritative technical tone. Focus on system architecture, operational precision, and root-cause analysis.
- **Zero Filler**: Avoid conversational pleasantries, cheerleading, and boilerplate platitudes.
- **English-First**: Default language for documentation, code comments, commit messages, and agent reasoning is English. Traditional Chinese (繁體中文) is used exclusively when updating Chinese documentation files (`*_zh.md`, `*-zh.ipynb`) or when the user explicitly requests it.
- **Strictly No Emojis**: Do not use decorative emojis anywhere (no responses, commit messages, code comments, documentation headers, or log messages). Maintain clean, standard technical formatting.
- **Clickable References**: Hyperlink all referenced files, classes, methods, and configurations using Markdown links (e.g., [`llm.sh`](file:///content/colab-llm-station/llm.sh)).

---

## 3. Repository Architecture & File Mapping

```
colab-llm-station/
├── llm.sh                  # Master CLI lifecycle controller (vLLM, Ollama, Tailscale, Cloudflare)
├── setup.sh                # Environment bootstrap & dependency installer
├── sync_git.sh             # Non-interactive Git commit & push synchronization tool
├── colab_station.ipynb     # Primary interactive deployment notebook (English source of truth)
├── colab_station-zh.ipynb  # Mirrored interactive deployment notebook (Traditional Chinese)
├── models.json             # Model catalog metadata and hardware allocation recommendations
├── benchmark.py            # Latency, TTFT, and generation throughput benchmarking utility
├── chat.py                 # Interactive terminal chat client for local testing
├── test_inference.py       # Automated engine diagnostic script
├── templates/
│   └── opencode.json       # OpenCode client configuration template for Tailscale mesh
└── AGENTS.md               # AI agent operating instructions and repository guardrails
```

### Key Responsibilities:
- **`llm.sh`**: Centralized CLI wrapper. All engine operations (`start`, `stop`, `status`, `logs`) and tunnel management must go through `llm.sh`. Do not spawn raw background daemons directly in notebook cells or scripts when an `llm.sh` command exists.
- **`colab_station.ipynb` & `colab_station-zh.ipynb`**: User-facing entry points. Must be maintained as exact 1:1 mirrors in structure and logic.
- **`templates/opencode.json`**: Standardized provider config template mapping local OpenCode instances to Colab Tailscale mesh endpoints.

---

## 4. Execution Guardrails & Environmental Rules

### 4.1 Headless & Non-Interactive Execution
Google Colab operates in a headless Linux container without interactive TTY terminal input during cell execution.
- **Never prompt for user input**: All commands, scripts, and utilities must run non-interactively.
- Use explicit non-interactive flags (e.g., `apt-get install -y`, `curl -fsSL`).
- Never run bare `tailscale up` without `--authkey` or unattended flags in scripts.
- Never write scripts that block indefinitely on `read` or interactive confirmations.

### 4.2 Runtime Filesystem & Path Standards
- **Standard Colab Working Directory**: `/content/colab-llm-station`.
- **No Google Drive Hardcoding**: Never write runtime logic that assumes Google Drive is mounted at `/content/drive/MyDrive/...`. Standalone Colab users clone directly to `/content/colab-llm-station`.
- Files created during runtime (logs, PID files, sockets) must reside within the repository directory or `/tmp`, and must be covered by `.gitignore`.

### 4.3 Secrets & Credential Management
- Never commit private tokens, API keys, or Tailscale Auth Keys into git history.
- Read secrets in Colab using `google.colab.userdata`:
  ```python
  from google.colab import userdata
  tailscale_key = userdata.get('TAILSCALE_AUTHKEY')
  hf_token = userdata.get('HF_TOKEN')
  ```
- All temporary Auth Keys must be treated as ephemeral.

### 4.4 Compute Unit (CU) & Runtime Teardown
- Closing the browser tab does **not** stop a Google Colab VM; it continues running and consuming paid compute units until timeout.
- Every notebook workflow must conclude with the teardown sequence.
- Programmatic termination command:
  ```python
  from google.colab import runtime
  runtime.unassign()
  ```
- Always preserve this step when refactoring notebooks or termination scripts.

### 4.5 Hardware & VRAM Allocation Matrix
Agents modifying model parameters or configurations must adhere to strict hardware boundaries:

| Hardware Tier | Typical VRAM | Recommended Engines & Models | Constraints & Flags |
|---|---|---|---|
| **Tesla T4** | 16 GB | Ollama: 7B/8B (4-bit Q4_K_M)<br>vLLM: 7B/8B (AWQ / GPTQ) | `--gpu-memory-utilization 0.90`<br>`--max-model-len 4096` to `8192`<br>*Never attempt unquantized 27B+* |
| **NVIDIA L4** | 24 GB | Ollama: 7B/8B/14B<br>vLLM: 7B/8B (FP16/BF16), 14B (AWQ) | `--gpu-memory-utilization 0.92`<br>`--max-model-len 8192` to `16384` |
| **A100 (SXM4)** | 40 GB / 80 GB | vLLM: 27B/32B (AWQ or BF16), 70B (AWQ) | `--gpu-memory-utilization 0.95`<br>`--max-model-len 16384` to `32768` |

Agents must inspect available GPU hardware using `nvidia-smi` before proposing engine parameters.

### 4.6 Dual-Notebook Synchronization Rule
- `colab_station.ipynb` is the primary English source of truth.
- `colab_station-zh.ipynb` is the Traditional Chinese localized mirror.
- **Mandatory**: Any modification to cells, scripts, workflows, or deployment steps in one notebook must be mirrored identically in the other.
- Verify notebook integrity before committing:
  ```bash
  python3 -m json.tool colab_station.ipynb > /dev/null
  python3 -m json.tool colab_station-zh.ipynb > /dev/null
  ```

---

## 5. Standard CLI Operations & Workflows

### 5.1 Service Lifecycle Management (`llm.sh`)
```bash
# vLLM lifecycle
bash llm.sh vllm start --model "Qwen/Qwen2.5-Coder-7B-Instruct-AWQ" --quantization awq
bash llm.sh vllm stop
bash llm.sh vllm logs -f

# Ollama lifecycle
bash llm.sh ollama start
bash llm.sh ollama run "qwen2.5-coder:7b"
bash llm.sh ollama stop

# Tailscale mesh networking
bash llm.sh tunnel tailscale up --authkey "$TAILSCALE_AUTHKEY"
bash llm.sh tunnel tailscale down

# Cloudflare tunnel
bash llm.sh tunnel cloudflare up --port 8000
bash llm.sh tunnel cloudflare down

# Runtime diagnostics
bash llm.sh status
```

### 5.2 Service Health Endpoints
- **vLLM (OpenAI-compatible)**:
  - Base URL: `http://127.0.0.1:8000/v1`
  - Health check: `curl -s http://127.0.0.1:8000/v1/models`
- **Ollama**:
  - Base URL: `http://127.0.0.1:11434`
  - Health check: `curl -s http://127.0.0.1:11434/api/tags`
- **Tailscale Mesh Proxy**:
  - `tailscale serve status`
  - Target mappings: Port 8000 (vLLM) and Port 11434 (Ollama)

### 5.3 Git Synchronization
When synchronizing changes from Colab:
```bash
bash sync_git.sh
```
Or standard git operations:
```bash
git add -A
git commit -m "type(scope): concise technical description in english"
git push origin main
```
Commit messages must follow Conventional Commits format in lowercase English, without emojis.
