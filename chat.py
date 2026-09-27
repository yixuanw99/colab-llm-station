#!/usr/bin/env python3
"""
通用 LLM 終端多輪互動對話工具 (支援任何 Ollama 模型)
"""
import argparse
import urllib.request
import json
import sys

def chat_loop(model: str):
    print("=" * 65)
    print(f"歡迎使用通用 LLM 終端工作站！當前加載模型: [{model}]")
    print("指令提示: 輸入 'exit' 或 'quit' 結束，輸入 'clear' 清除對話記錄")
    print("=" * 65)

    messages = []
    
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
            messages = []
            print("[系統] 對話歷史已清空。")
            continue

        messages.append({"role": "user", "content": user_input})

        payload = {
            "model": model,
            "messages": messages,
            "stream": True
        }

        req = urllib.request.Request(
            "http://127.0.0.1:11434/api/chat",
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"}
        )

        print(f"\n[{model}] > ", end="", flush=True)
        assistant_reply = ""
        try:
            with urllib.request.urlopen(req) as resp:
                for line in resp:
                    if not line:
                        continue
                    chunk = json.loads(line.decode("utf-8"))
                    msg = chunk.get("message", {})
                    content = msg.get("content", "")
                    print(content, end="", flush=True)
                    assistant_reply += content
            print()
            messages.append({"role": "assistant", "content": assistant_reply})
        except Exception as e:
            print(f"\n[錯誤] 請求失敗: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="通用 LLM 終端多輪對話")
    parser.add_argument("--model", type=str, default="qwen3.8:27b", help="模型標籤 (如 qwen3.8:27b, deepseek-r1:32b 等)")
    args = parser.parse_args()
    chat_loop(args.model)
