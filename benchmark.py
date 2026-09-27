#!/usr/bin/env python3
"""
通用 LLM 基準與推論效能測試工具 (支援任何 Ollama 模型)
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
        return f"{used} MiB / {total} MiB ({used / total * 100:.1f}%), 利用率: {util}%"
    except Exception as e:
        return f"無法獲取 GPU 資訊 ({e})"

def run_benchmark(model: str, prompt: str):
    print("=" * 65)
    print(f"評測模型: {model}")
    print(f"初始 GPU 顯存: {get_gpu_vram()}")
    print(f"評測問題: {prompt}")
    print("=" * 65)

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
    eval_duration = 0
    
    print("\n[模型輸出開始]\n")
    try:
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
    except Exception as e:
        print(f"\n[錯誤] 請求失敗: {e}")
        return

    t1 = time.time()
    print("\n\n[模型輸出結束]\n")

    print("=" * 65)
    print("效能基準報告：")
    print(f"• 首字延遲 (TTFT): {first_token_time - t0:.2f} 秒" if first_token_time else "• 首字延遲: N/A")
    print(f"• 總花費時間: {t1 - t0:.2f} 秒")
    print(f"• 產出 Token 數: {total_tokens} tokens")
    if total_tokens > 0 and eval_duration > 0:
        print(f"• 生成速度 (Throughput): {total_tokens / eval_duration:.2f} tokens/s")
    print(f"• 運行後 GPU 顯存: {get_gpu_vram()}")
    print("=" * 65)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="通用 LLM 評測工具")
    parser.add_argument("--model", type=str, default="qwen3.8:27b", help="模型標籤 (如 qwen3.8:27b, deepseek-r1:32b 等)")
    parser.add_argument("--prompt", type=str, default="請實作一個執行緒安全的任務排程器（Task Scheduler），支援優先級佇列與定時觸發。", help="自訂測試 Prompt")
    args = parser.parse_args()

    run_benchmark(args.model, args.prompt)
