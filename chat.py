#!/usr/bin/env python3
"""
通用 LLM 終端多輪互動對話工具 (支援 vLLM 與 Ollama 標準 OpenAI-Compatible 協議)
"""
import argparse
import urllib.request
import json
import sys

def chat_loop(engine: str, port: int, model: str):
    api_url = f"http://127.0.0.1:{port}/v1/chat/completions"
    
    print("=" * 70)
    print(f"歡迎使用通用 LLM 終端工作站！")
    print(f"當前引擎: [{engine.upper()}] | 端點: {api_url} | 模型: [{model}]")
    print("操作提示: 輸入 'exit' 結束，輸入 'clear' 清空歷史對話")
    print("=" * 70)

    messages = [
        {"role": "system", "content": "你是一位頂尖的 AI 助手與軟體工程師，請使用清晰有條理的繁體中文回答。"}
    ]
    
    while True:
        try:
            user_input = input("\n[您] > ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\n再見！")
            break

        if not user_input:
            continue
        if user_input.lower() in ("exit", "quit"):
            print("再見！")
            break
        if user_input.lower() == "clear":
            messages = [{"role": "system", "content": "你是一位頂尖的 AI 助手與軟體工程師，請使用繁體中文回答。"}]
            print("[系統] 對話歷史已清空。")
            continue

        messages.append({"role": "user", "content": user_input})

        payload = {
            "model": model,
            "messages": messages,
            "stream": True,
            "temperature": 0.7
        }

        req = urllib.request.Request(
            api_url,
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Authorization": "Bearer token"
            }
        )

        print(f"\n[{model}] > ", end="", flush=True)
        assistant_reply = ""
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
                        choices = chunk.get("choices", [])
                        if choices:
                            delta = choices[0].get("delta", {})
                            content = delta.get("content", "")
                            print(content, end="", flush=True)
                            assistant_reply += content
                    except json.JSONDecodeError:
                        pass
            print()
            messages.append({"role": "assistant", "content": assistant_reply})
        except Exception as e:
            print(f"\n[錯誤] 請求失敗: {e}")
            print(f"提示: 請確認 {engine} 服務是否已在 port {port} 啟動。")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="通用 LLM 終端多輪對話")
    parser.add_argument("--engine", type=str, default="ollama", choices=["ollama", "vllm"], help="推論引擎")
    parser.add_argument("--port", type=int, default=11434, help="服務端口")
    parser.add_argument("--model", type=str, default="qwen3.8:27b", help="模型名稱")
    args = parser.parse_args()

    if args.port == 11434 and args.engine == "vllm":
        args.port = 8000

    chat_loop(args.engine, args.port, args.model)
