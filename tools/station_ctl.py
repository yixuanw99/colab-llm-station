#!/usr/bin/env python3
"""
Colab LLM Station - Local Workstation Orchestrator (Headless CLI)
Enables zero-browser provisioning, management, and teardown of Colab GPU runtimes
using Google Colab CLI (`google-colab-cli`) and Tailscale mesh networking.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path
from typing import Any, Callable

REPO_DIR = Path(__file__).resolve().parents[1]
REMOTE_BOOTSTRAP = REPO_DIR / "scripts" / "remote_bootstrap.py"
MODELS_CATALOG = REPO_DIR / "configs" / "models.json"


def load_dotenv():
    """Load key-value pairs from .env into os.environ if not already present."""
    env_file = REPO_DIR / ".env"
    if not env_file.is_file():
        return
    with open(env_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, val = line.split("=", 1)
            key = key.strip()
            val = val.strip().strip("'\"")
            if key and key not in os.environ:
                os.environ[key] = val


load_dotenv()


def log(msg: str):
    print(f"[STATION] {msg}", flush=True)


def log_err(msg: str):
    print(f"[ERROR] {msg}", file=sys.stderr, flush=True)


def check_colab_cli() -> str:
    """Verify that google-colab-cli is installed and reachable on PATH."""
    colab_bin = shutil.which("colab")
    if not colab_bin:
        log_err("Google Colab CLI ('colab') was not found on your system PATH.")
        print("\nInstallation instructions:")
        print("  1. Install via uv:   uv tool install google-colab-cli")
        print("     Or install pip:   pip install google-colab-cli")
        print("  2. Authenticate:     colab --auth=oauth2 usage\n")
        sys.exit(1)

    try:
        res = subprocess.run([colab_bin, "version"], capture_output=True, text=True, timeout=15)
        if res.returncode != 0:
            log_err(f"'colab version' failed. Output: {res.stderr.strip()}")
            sys.exit(1)
        return colab_bin
    except Exception as e:
        log_err(f"Failed to execute Colab CLI: {e}")
        sys.exit(1)


def run_colab_cmd(cmd_args: list[str], timeout: int = 1800, stream_output: bool = True) -> tuple[int, str]:
    """Execute a colab CLI command with optional real-time streaming."""
    colab_bin = check_colab_cli()
    auth_mode = os.environ.get("COLAB_AUTH", "oauth2")
    full_cmd = [colab_bin, f"--auth={auth_mode}", *cmd_args]

    if not stream_output:
        res = subprocess.run(full_cmd, capture_output=True, text=True, timeout=timeout)
        return res.returncode, res.stdout + res.stderr

    process = subprocess.Popen(
        full_cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    collected_output: list[str] = []
    assert process.stdout is not None
    for line in iter(process.stdout.readline, ""):
        print(line, end="", flush=True)
        collected_output.append(line)

    process.stdout.close()
    returncode = process.wait()
    return returncode, "".join(collected_output)


def get_catalog_recommendation(gpu: str, engine: str) -> str:
    """Recommend best model from configs/models.json based on GPU tier."""
    if not MODELS_CATALOG.is_file():
        return "Qwen/Qwen2.5-Coder-32B-Instruct-AWQ" if engine == "vllm" else "qwen2.5-coder:7b"

    try:
        with open(MODELS_CATALOG, "r", encoding="utf-8") as f:
            data = json.load(f)
        if engine == "vllm":
            if gpu.upper() in ("A100", "H100"):
                return "Qwen/Qwen2.5-Coder-32B-Instruct-AWQ"
            return "Qwen/Qwen2.5-Coder-7B-Instruct-AWQ"
        else:
            if gpu.upper() in ("A100", "H100"):
                return "qwen3.8:27b"
            elif gpu.upper() == "L4":
                return "qwen2.5-coder:14b"
            return "qwen2.5-coder:7b"
    except Exception:
        return "Qwen/Qwen2.5-Coder-32B-Instruct-AWQ"


def resolve_inference_host(port: int, default_host: str = "colab-llm-station") -> tuple[str, list[str]]:
    """Probe candidate hostnames to locate active inference engine across Tailscale suffix disambiguations."""
    candidates = [default_host]
    for suffix in ["-1", "-2", "-3"]:
        cand = f"{default_host}{suffix}"
        if cand not in candidates:
            candidates.append(cand)
    for host in candidates:
        try:
            req = urllib.request.Request(f"http://{host}:{port}/v1/models", headers={"User-Agent": "StationCtl"})
            with urllib.request.urlopen(req, timeout=2) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                models = [m.get("id", "") for m in data.get("data", [])]
                return host, models
        except Exception:
            continue
    return "", []


def cmd_up(args: argparse.Namespace):
    """Provision remote Colab GPU session and bootstrap station services."""
    check_colab_cli()
    session = args.session or os.environ.get("COLAB_SESSION", "colab-llm-station")
    gpu = (args.gpu or os.environ.get("COLAB_GPU", "A100")).upper()
    high_mem = args.high_mem or (gpu in ("A100", "H100"))

    # Auto engine selection
    engine = args.engine or os.environ.get("STATION_ENGINE", "")
    if not engine:
        engine = "vllm" if gpu in ("A100", "H100") else "ollama"

    model = args.model or os.environ.get("STATION_MODEL", "")
    if not model:
        model = get_catalog_recommendation(gpu, engine)

    authkey = args.authkey or os.environ.get("TAILSCALE_AUTHKEY", "")
    if not authkey:
        log_err("TAILSCALE_AUTHKEY is required for private mesh networking.")
        print("\nPlease supply your Tailscale Auth Key:")
        print("  1. Argument:              --authkey tskey-auth-...")
        print("  2. Local environment:     export TAILSCALE_AUTHKEY=tskey-auth-...")
        print("  3. File:                  Add TAILSCALE_AUTHKEY=tskey-auth-... in .env")
        print("\nGenerate reusable ephemeral key at: https://login.tailscale.com/admin/settings/keys\n")
        sys.exit(1)

    hf_token = args.hf_token or os.environ.get("HF_TOKEN", "")

    log("=" * 70)
    log("Colab LLM Station - Zero-Browser Automated Provisioning")
    log(f"Session Name: {session}")
    log(f"Hardware:     {gpu} (High-Memory: {high_mem})")
    log(f"Engine:       {engine.upper()}")
    log(f"Model:        {model}")
    log("=" * 70)

    # 1. Check account usage
    log("Checking Colab account compute unit balance...")
    code, out = run_colab_cmd(["usage"], timeout=30, stream_output=False)
    if code == 0 and out.strip():
        for line in out.strip().splitlines():
            print(f"  {line}")

    # 2. Check existing sessions
    log("Checking active sessions...")
    code, out = run_colab_cmd(["sessions"], timeout=30, stream_output=False)
    session_exists = session in out

    if not session_exists:
        log(f"Provisioning new Colab VM runtime (GPU: {gpu})...")
        new_args = ["new", "--session", session, "--gpu", gpu]
        if high_mem:
            new_args.append("--high-mem")
        if args.keep:
            new_args.append("--keep")

        ret, _ = run_colab_cmd(new_args, timeout=900, stream_output=True)
        if ret != 0:
            log_err("Failed to provision Colab VM. Ensure you have available compute units.")
            sys.exit(1)
        log("VM runtime successfully allocated.")
    else:
        log(f"Active session '{session}' detected. Reusing existing instance.")

    # 3. Remote bootstrap via colab exec
    log("Dispatching remote bootstrap payload to Colab instance...")
    if not REMOTE_BOOTSTRAP.is_file():
        log_err(f"Bootstrap script not found: {REMOTE_BOOTSTRAP}")
        sys.exit(1)

    exec_args = [
        "exec",
        "--session", session,
        "--timeout", str(args.timeout),
        "--env", f"STATION_ENGINE={engine}",
        "--env", f"STATION_MODEL={model}",
        "--env", f"TAILSCALE_AUTHKEY={authkey}",
        "--env", f"HF_TOKEN={hf_token}",
        "--file", str(REMOTE_BOOTSTRAP),
    ]

    ret, _ = run_colab_cmd(exec_args, timeout=args.timeout + 60, stream_output=True)
    if ret != 0:
        log_err("Remote bootstrap script encountered an error.")
        sys.exit(ret)

    # 4. Local Tailscale Reachability Verification
    port = 8000 if engine == "vllm" else 11434
    target_host = getattr(args, "host", None) or os.environ.get("TAILSCALE_HOST", "colab-llm-station")
    log("Verifying Tailscale peer reachability from local workstation...")
    log(f"Target Service Port: {port}")

    ready = False
    active_host = target_host
    for i in range(30):
        h, _ = resolve_inference_host(port, default_host=target_host)
        if h:
            ready = True
            active_host = h
            break
        time.sleep(2)

    if ready:
        log("=" * 70)
        log("[SUCCESS] Colab LLM Station is LIVE and accessible over your Tailnet!")
        log(f"Inference Base URL: http://{active_host}:{port}/v1")
        log(f"Active Engine:      {engine.upper()}")
        log(f"Active Model:       {model}")
        log("=" * 70)
        print("\nReady for OpenCode! Run `./station.sh test` to verify generation throughput.")
    else:
        log("[WARN] Model daemon started, but endpoint not yet reachable via local Tailscale DNS.")
        log(f"If local DNS resolution is pending, run 'tailscale ping {target_host}'.")


def cmd_down(args: argparse.Namespace):
    """Terminate remote Colab VM and cease compute unit deduction."""
    check_colab_cli()
    session = args.session or os.environ.get("COLAB_SESSION", "colab-llm-station")

    log(f"Stopping Colab session '{session}' and releasing GPU VM...")

    # 1. Unassign runtime via programmatic code
    teardown_py = (
        "import subprocess\n"
        "subprocess.run('tailscale logout || true', shell=True)\n"
        "from google.colab import runtime\n"
        "runtime.unassign()\n"
    )
    temp_teardown = REPO_DIR / ".temp_teardown.py"
    try:
        temp_teardown.write_text(teardown_py, encoding="utf-8")
        run_colab_cmd(
            ["exec", "--session", session, "--timeout", "60", "--file", str(temp_teardown)],
            timeout=70,
            stream_output=False,
        )
    except Exception:
        pass
    finally:
        if temp_teardown.is_file():
            temp_teardown.unlink()

    # 2. Issue official colab stop command
    ret, out = run_colab_cmd(["stop", "--session", session], timeout=60, stream_output=True)
    if ret == 0:
        log("=" * 70)
        log("[SUCCESS] Colab runtime terminated. Compute units ceased billing.")
        log("=" * 70)
    else:
        log_err(f"Colab stop returned code {ret}: {out}")


def cmd_status(args: argparse.Namespace):
    """Inspect Colab usage, active sessions, and local Tailnet connection."""
    check_colab_cli()
    log("=== Colab Account Quota & Usage ===")
    run_colab_cmd(["usage"], timeout=30, stream_output=True)

    log("\n=== Active Colab Sessions ===")
    run_colab_cmd(["sessions"], timeout=30, stream_output=True)

    log("\n=== Inference Endpoint Probing ===")
    default_host = getattr(args, "host", None) or os.environ.get("TAILSCALE_HOST", "colab-llm-station")
    for port, label in [(8000, "vLLM"), (11434, "Ollama")]:
        host, models = resolve_inference_host(port, default_host=default_host)
        if host:
            log(f"[ACTIVE]  {label} Service ({host}:{port}): Models = {models}")
        else:
            log(f"[OFFLINE] {label} Service ({default_host}:{port})")


def cmd_test(args: argparse.Namespace):
    """Send test completion request from local workstation to remote Colab."""
    port = args.port
    default_host = getattr(args, "host", None) or os.environ.get("TAILSCALE_HOST", "colab-llm-station")
    host, _ = resolve_inference_host(port, default_host=default_host)
    if not host:
        host = default_host
    endpoint = f"http://{host}:{port}/v1/chat/completions"
    log(f"Sending test completion request to {endpoint}...")

    payload = {
        "model": args.model or "default",
        "messages": [
            {"role": "system", "content": "You are a concise AI engineering assistant."},
            {"role": "user", "content": "Explain what Google Colab CLI and Tailscale achieve together in 2 sentences."}
        ],
        "max_tokens": 128,
        "temperature": 0.2
    }

    t0 = time.time()
    try:
        req = urllib.request.Request(
            endpoint,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json", "Authorization": "Bearer station"}
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            dur = time.time() - t0
            data = json.loads(resp.read().decode("utf-8"))
            answer = data["choices"][0]["message"]["content"]
            log("=" * 70)
            log("Remote Model Response:")
            log("=" * 70)
            print(answer.strip())
            log("=" * 70)
            log(f"Round-trip Latency: {dur:.2f}s")
    except Exception as e:
        log_err(f"Test request failed: {e}")


def cmd_ssh(args: argparse.Namespace):
    """Launch interactive SSH session via Tailscale into Colab runtime."""
    ssh_bin = shutil.which("ssh")
    if not ssh_bin:
        log_err("SSH client was not found on your system PATH.")
        sys.exit(1)
    target = f"root@{args.host}"
    log(f"Connecting to {target} via Tailscale SSH...")
    os.execvp(ssh_bin, [ssh_bin, target])


def main():
    parser = argparse.ArgumentParser(
        prog="station",
        description="Colab LLM Station - Local Workstation Headless Orchestrator"
    )
    subparsers = parser.add_subparsers(dest="command", help="Command to execute")

    # UP / START
    p_up = subparsers.add_parser("up", aliases=["start"], help="Provision Colab VM and launch LLM station")
    p_up.add_argument("--gpu", default="A100", choices=["A100", "H100", "L4", "T4"], help="GPU tier (default: A100)")
    p_up.add_argument("--engine", choices=["vllm", "ollama"], help="Inference engine (auto-detected by GPU)")
    p_up.add_argument("--model", help="Model identifier")
    p_up.add_argument("--session", help="Colab session name (default: colab-llm-station)")
    p_up.add_argument("--host", help="Tailscale host name (default: colab-llm-station)")
    p_up.add_argument("--authkey", help="Tailscale auth key")
    p_up.add_argument("--hf-token", help="Hugging Face access token")
    p_up.add_argument("--high-mem", action="store_true", help="Request high-memory instance")
    p_up.add_argument("--keep", action="store_true", help="Keep VM session alive against inactivity timeout")
    p_up.add_argument("--timeout", type=int, default=1800, help="Provisioning timeout in seconds")

    # DOWN / STOP
    p_down = subparsers.add_parser("down", aliases=["stop"], help="Stop Colab VM and cease billing")
    p_down.add_argument("--session", help="Colab session name (default: colab-llm-station)")

    # STATUS
    p_status = subparsers.add_parser("status", help="Inspect Colab usage, sessions, and endpoint health")
    p_status.add_argument("--host", help="Tailscale target host (default: auto-detect)")

    # TEST
    p_test = subparsers.add_parser("test", help="Test remote inference endpoint from local workstation")
    p_test.add_argument("--port", type=int, default=8000, help="Port to query (8000 for vLLM, 11434 for Ollama)")
    p_test.add_argument("--host", help="Tailscale target host (default: auto-detect)")
    p_test.add_argument("--model", default="", help="Model name")

    # SSH
    p_ssh = subparsers.add_parser("ssh", help="Connect to Colab via Tailscale SSH")
    p_ssh.add_argument("--host", default="colab-llm-station", help="Tailscale hostname (default: colab-llm-station)")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(0)

    cmd = args.command
    if cmd in ("up", "start"):
        cmd_up(args)
    elif cmd in ("down", "stop"):
        cmd_down(args)
    elif cmd == "status":
        cmd_status(args)
    elif cmd == "test":
        cmd_test(args)
    elif cmd == "ssh":
        cmd_ssh(args)


if __name__ == "__main__":
    main()
