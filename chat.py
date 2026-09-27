#!/usr/bin/env python3
"""
Qwen3.8-27B 終端互動對話工具 (支援多輪對話與上下文記憶)
"""
import urllib.request
import json
import sys

def chat_loop(model: str = "qwen3.8:27b"):
    print("=" * 60)
    print(f"歡迎使用 Qwen3.8-27B 互動對話 (輸入 'exit' 或 'quit' 退出，輸入 'clear' 清除對話記錄)")
    print("=" * 60)

    messages = []
    
    while True:
        try:
            user_input = input("\n[使用者] > ").strip()
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

        print("\n[Qwen3.8] > ", end="", flush=True)
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
    chat_loop()
