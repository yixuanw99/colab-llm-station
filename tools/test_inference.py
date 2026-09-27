#!/usr/bin/env python3
"""
Qwen3.8-27B 基準與推論測試腳本
"""
import urllib.request
import json
import time
import subprocess

def get_gpu_vram():
    try:
        out = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=memory.used,memory.total", "--format=csv,nounits,noheader"],
            encoding="utf-8"
        ).strip().split(",")
        used, total = int(out[0].strip()), int(out[1].strip())
        return f"{used} MiB / {total} MiB ({used / total * 100:.1f}%)"
    except Exception as e:
        return f"無法獲取 GPU 資訊 ({e})"

def test_inference(prompt: str, model: str = "qwen3.8:27b"):
    print("=" * 60)
    print(f"測試模型: {model}")
    print(f"當前 GPU 顯存: {get_gpu_vram()}")
    print(f"測試問題: {prompt}")
    print("=" * 60)

    payload = {
        "model": model,
        "prompt": prompt,
        "stream": True
    }
    
    req = urllib.request.Request(
        "http://127.0.0.1:11434/api/generate",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )

    t0 = time.time()
    total_tokens = 0
    first_token_time = None
    
    print("\n[模型回答開始]")
    with urllib.request.urlopen(req) as resp:
        for line in resp:
            if not line:
                continue
            chunk = json.loads(line.decode("utf-8"))
            if not first_token_time:
                first_token_time = time.time()
            text = chunk.get("response", "")
            print(text, end="", flush=True)
            if chunk.get("done", False):
                total_tokens = chunk.get("eval_count", 0)
                eval_duration = chunk.get("eval_duration", 0) / 1e9
    t1 = time.time()
    print("\n[模型回答結束]\n")

    print("=" * 60)
    print("效能統計：")
    print(f"首字延遲 (TTFT): {first_token_time - t0:.2f} 秒" if first_token_time else "N/A")
    print(f"總生成時間: {t1 - t0:.2f} 秒")
    print(f"生成 Token 數: {total_tokens}")
    if total_tokens > 0 and 'eval_duration' in locals() and eval_duration > 0:
        print(f"生成速度 (Throughput): {total_tokens / eval_duration:.2f} tokens/s")
    print(f"推論後 GPU 顯存: {get_gpu_vram()}")
    print("=" * 60)

if __name__ == "__main__":
    prompt = (
        "請使用 Python 實作一個高效的 LRU Cache（包含 get 和 put 操作，"
        "時間複雜度需為 O(1)），並加上詳細型別標註與使用範例。"
    )
    test_inference(prompt)
