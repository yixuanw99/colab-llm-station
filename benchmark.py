#!/usr/bin/env python3
"""
通用 LLM 效能評測工具 (支援 vLLM 與 Ollama 標準 OpenAI-Compatible 協議)
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

def run_benchmark(engine: str, port: int, model: str, prompt: str):
    base_url = f"http://127.0.0.1:{port}"
    api_url = f"{base_url}/v1/chat/completions"

    print("=" * 70)
    print(f"評測引擎: {engine.upper()} (端點: {api_url})")
    print(f"評測模型: {model}")
    print(f"初始 GPU 顯存: {get_gpu_vram()}")
    print(f"測試問題: {prompt}")
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
    output_tokens_approx = 0
    full_text = ""
    
    print("\n[模型串流輸出開始]\n")
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
        print(f"\n[錯誤] 請求失敗: {e}")
        print(f"提示: 請確認 {engine} 服務是否已在 port {port} 啟動。")
        return

    t1 = time.time()
    print("\n\n[模型串流輸出結束]\n")

    # 估算 token 數 (中文約 1.5 chars/token, 英文約 4 chars/token)
    total_time = t1 - t0
    gen_time = (t1 - first_token_time) if first_token_time else total_time
    output_chars = len(full_text)
    # 若無準確 usage，以字符統計做參考
    approx_tokens = int(output_chars * 0.75) if any(ord(c) > 127 for c in full_text) else int(output_chars / 4)

    print("=" * 70)
    print("效能基準報告：")
    print(f"• 首字延遲 (TTFT): {first_token_time - t0:.2f} 秒" if first_token_time else "• 首字延遲: N/A")
    print(f"• 總生成時間: {total_time:.2f} 秒 (生成階段: {gen_time:.2f} 秒)")
    print(f"• 產出字數: {output_chars} 字元 (約 ~{approx_tokens} tokens)")
    if gen_time > 0 and approx_tokens > 0:
        print(f"• 估計生成速度: ~{approx_tokens / gen_time:.2f} tokens/s")
    print(f"• 運行後 GPU 顯存: {get_gpu_vram()}")
    print("=" * 70)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="通用 LLM 評測工具")
    parser.add_argument("--engine", type=str, default="ollama", choices=["ollama", "vllm"], help="推論引擎")
    parser.add_argument("--port", type=int, default=11434, help="服務端口 (Ollama 預設 11434, vLLM 預設 8000)")
    parser.add_argument("--model", type=str, default="qwen3.8:27b", help="模型標籤或 Hugging Face ID")
    parser.add_argument("--prompt", type=str, default="請實作一個執行緒安全的任務排程器（Task Scheduler），支援優先級佇列與定時觸發。", help="測試問題")
    args = parser.parse_args()

    # 自動校正預設 port
    if args.port == 11434 and args.engine == "vllm":
        args.port = 8000

    run_benchmark(args.engine, args.port, args.model, args.prompt)
