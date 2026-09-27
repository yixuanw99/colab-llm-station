#!/usr/bin/env python3
"""
Interactive Multi-Turn CLI Chat for Colab LLM Station
Supports both vLLM and Ollama via standard OpenAI-compatible completions.
"""
import argparse
import urllib.request
import json
import sys

def chat_loop(engine: str, port: int, model: str):
    api_url = f"http://127.0.0.1:{port}/v1/chat/completions"
    
    print("=" * 70)
    print(f"Colab LLM Station - Interactive Shell")
    print(f"Engine: [{engine.upper()}] | Endpoint: {api_url} | Model: [{model}]")
    print("Commands: Type 'exit' to quit, 'clear' to reset conversation context")
    print("=" * 70)

    messages = [
        {"role": "system", "content": "You are an expert AI software engineer. Provide concise, clear, and accurate answers."}
    ]
    
    while True:
        try:
            user_input = input("\n[User] > ").strip()
        except (KeyboardInterrupt, EOFError):
            print("\nExiting session.")
            break

        if not user_input:
            continue
        if user_input.lower() in ("exit", "quit"):
            print("Exiting session.")
            break
        if user_input.lower() == "clear":
            messages = [{"role": "system", "content": "You are an expert AI software engineer. Provide concise, clear, and accurate answers."}]
            print("[System] Conversation context reset.")
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
            print(f"\n[ERROR] Request failed: {e}")
            print(f"Check if {engine} is listening on port {port}.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Colab LLM Station Chat Interface")
    parser.add_argument("--engine", type=str, default="ollama", choices=["ollama", "vllm"])
    parser.add_argument("--port", type=int, default=11434)
    parser.add_argument("--model", type=str, default="qwen3.8:27b")
    args = parser.parse_args()

    if args.port == 11434 and args.engine == "vllm":
        args.port = 8000

    chat_loop(args.engine, args.port, args.model)
