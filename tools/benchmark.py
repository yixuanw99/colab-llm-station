#!/usr/bin/env python3
"""
Performance & Throughput Benchmark Suite for Colab LLM Station
Supports both vLLM and Ollama via standard OpenAI-compatible completions.
"""
import argparse
import urllib.request
import json
import time
import subprocess

def get_gpu_vram():
    try:
        out = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=memory.used,memory.total,utilization.gpu", "--format=csv,nounits,noheader"],
            encoding="utf-8"
        ).strip().split(",")
        used, total, util = int(out[0].strip()), int(out[1].strip()), int(out[2].strip())
        return f"{used} MiB / {total} MiB ({used / total * 100:.1f}%), Utilization: {util}%"
    except Exception as e:
        return f"GPU query error: {e}"

def run_benchmark(engine: str, port: int, model: str, prompt: str):
    api_url = f"http://127.0.0.1:{port}/v1/chat/completions"

    print("=" * 70)
    print(f"Engine:    {engine.upper()} ({api_url})")
    print(f"Model:     {model}")
    print(f"Init VRAM: {get_gpu_vram()}")
    print(f"Prompt:    {prompt}")
    print("=" * 70)

    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "stream": True,
        "temperature": 0.2
    }
    
    req = urllib.request.Request(
        api_url,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": "Bearer token"
        }
    )

    t0 = time.time()
    first_token_time = None
    full_text = ""
    
    print("\n[Streaming Output Begin]\n")
    try:
        with urllib.request.urlopen(req) as resp:
            for raw_line in resp:
                line = raw_line.decode("utf-8").strip()
                if not line or not line.startswith("data:"):
                    continue
                data_str = line[5:].strip()
                if data_str == "[DONE]":
                    break
                try:
                    chunk = json.loads(data_str)
                    if not first_token_time:
                        first_token_time = time.time()
                    choices = chunk.get("choices", [])
                    if choices:
                        delta = choices[0].get("delta", {})
                        content = delta.get("content", "")
                        print(content, end="", flush=True)
                        full_text += content
                except json.JSONDecodeError:
                    pass
    except Exception as e:
        print(f"\n[ERROR] Request failed: {e}")
        print(f"Check if {engine} is listening on port {port}.")
        return

    t1 = time.time()
    print("\n\n[Streaming Output End]\n")

    total_time = t1 - t0
    gen_time = (t1 - first_token_time) if first_token_time else total_time
    output_chars = len(full_text)
    approx_tokens = int(output_chars * 0.75) if any(ord(c) > 127 for c in full_text) else int(output_chars / 4)

    print("=" * 70)
    print("Benchmark Metrics:")
    print(f"  Time To First Token (TTFT): {first_token_time - t0:.2f} s" if first_token_time else "  TTFT: N/A")
    print(f"  Total Duration:             {total_time:.2f} s (Generation phase: {gen_time:.2f} s)")
    print(f"  Output Volume:              {output_chars} characters (~{approx_tokens} tokens)")
    if gen_time > 0 and approx_tokens > 0:
        print(f"  Estimated Throughput:       ~{approx_tokens / gen_time:.2f} tokens/s")
    print(f"  Post-Inference VRAM:        {get_gpu_vram()}")
    print("=" * 70)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Colab LLM Station Benchmark")
    parser.add_argument("--engine", type=str, default="ollama", choices=["ollama", "vllm"])
    parser.add_argument("--port", type=int, default=11434)
    parser.add_argument("--model", type=str, default="qwen3.8:27b")
    parser.add_argument("--prompt", type=str, default="Implement a thread-safe task scheduler with priority queue and timeout support in Python.")
    args = parser.parse_args()

    if args.port == 11434 and args.engine == "vllm":
        args.port = 8000

    run_benchmark(args.engine, args.port, args.model, args.prompt)
