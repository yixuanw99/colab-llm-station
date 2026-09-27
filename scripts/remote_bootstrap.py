#!/usr/bin/env python3
"""
Colab LLM Station - Remote Bootstrap Script
Executed on the remote Google Colab VM by `colab exec`.
Clones repository, provisions packages, establishes Tailscale mesh, and launches LLM engine.
"""
import os
import sys
import subprocess
import time

def log(msg: str):
    print(f"[REMOTE] {msg}", flush=True)

def run(cmd: str, check: bool = True):
    log(f"> {cmd}")
    res = subprocess.run(cmd, shell=True, text=True)
    if check and res.returncode != 0:
        raise RuntimeError(f"Command failed with exit code {res.returncode}: {cmd}")
    return res

def main():
    repo_url = os.environ.get("STATION_REPO_URL", "https://github.com/yixuanw99/colab-llm-station.git")
    branch = os.environ.get("STATION_BRANCH", "main")
    engine = os.environ.get("STATION_ENGINE", "vllm").lower()
    model = os.environ.get("STATION_MODEL", "")
    authkey = os.environ.get("TAILSCALE_AUTHKEY", "")
    hf_token = os.environ.get("HF_TOKEN", "")

    station_dir = "/content/colab-llm-station"

    log("=" * 60)
    log("Colab LLM Station - Remote Provisioning Starting")
    log(f"Engine: {engine} | Model: {model or 'Catalog Default'}")
    log("=" * 60)

    # 1. Hugging Face credentials if provided
    if hf_token:
        os.environ["HF_TOKEN"] = hf_token
        os.environ["HUGGING_FACE_HUB_TOKEN"] = hf_token

    # 2. Clone or update repository
    if not os.path.exists(station_dir):
        log(f"Cloning {repo_url} (branch: {branch}) into {station_dir}...")
        run(f"git clone -b {branch} {repo_url} {station_dir}")
    else:
        log(f"Repository exists at {station_dir}; updating...")
        run(f"cd {station_dir} && git fetch && git checkout {branch} && git pull")

    # 3. Environment bootstrap (Ollama, vLLM, or all)
    log(f"Executing dependency bootstrap for '{engine}'...")
    run(f"cd {station_dir} && bash scripts/setup.sh {engine}")

    # 4. Tailscale Mesh Network Setup
    if authkey:
        log("Authenticating to Tailscale Mesh Network with provided Auth Key...")
        run(f"cd {station_dir} && bash llm.sh tunnel tailscale up '{authkey}'")
    else:
        log("WARNING: TAILSCALE_AUTHKEY was not provided. Starting daemon in headless mode...")
        run(f"cd {station_dir} && bash llm.sh tunnel tailscale up")

    # 5. Start Inference Engine
    log(f"Launching inference daemon for {engine.upper()}...")
    if engine == "vllm":
        start_cmd = f"cd {station_dir} && bash llm.sh vllm start"
        if model:
            start_cmd += f" '{model}'"
        run(start_cmd)
        # Map port 8000 to Tailnet
        run(f"cd {station_dir} && tailscale serve --bg --tcp 8000 8000 || true")
    elif engine == "ollama":
        run(f"cd {station_dir} && bash llm.sh ollama start")
        if model:
            log(f"Pulling Ollama model: {model}...")
            run(f"cd {station_dir} && bash llm.sh ollama pull '{model}'")
        # Map port 11434 to Tailnet
        run(f"cd {station_dir} && tailscale serve --bg --tcp 11434 11434 || true")

    # 6. Overall system diagnostic report
    log("=" * 60)
    log("Remote Provisioning Completed Successfully!")
    log("=" * 60)
    run(f"cd {station_dir} && bash llm.sh status")

if __name__ == "__main__":
    main()
