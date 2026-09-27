#!/usr/bin/env python3
"""
OpenAI-Compatible API 呼叫範例 (支援 LangChain, LlamaIndex, Aider 等現成生態)
"""
import urllib.request
import json

def call_openai_compatible_api():
    url = "http://127.0.0.1:11434/v1/chat/completions"
    headers = {
        "Content-Type": "application/json",
        "Authorization": "Bearer ollama"  # 可任意填寫
    }
    data = {
        "model": "qwen3.8:27b",
        "messages": [
            {"role": "system", "content": "你是一位頂尖的軟體架構工程師。"},
            {"role": "user", "content": "請列出微服務架構中分散式交易（Distributed Transaction）的三種常見實作模式與優缺點。"}
        ],
        "temperature": 0.3
    }

    req = urllib.request.Request(url, data=json.dumps(data).encode("utf-8"), headers=headers)
    with urllib.request.urlopen(req) as resp:
        res = json.loads(resp.read().decode("utf-8"))
        print(res["choices"][0]["message"]["content"])

if __name__ == "__main__":
    call_openai_compatible_api()
