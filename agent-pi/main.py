#!/usr/bin/env python3
"""Agent OS v0.1 — Minimal LLM Client"""
import json, urllib.request, os, subprocess

API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
messages = []
TOOLS = [{
    "name": "shell",
    "description": "Execute a shell command on this Agent OS",
    "input_schema": {
        "type": "object",
        "properties": {"cmd": {"type": "string", "description": "Shell command"}},
        "required": ["cmd"]
    }
}]

print("\n🤖 Agent OS v0.1")
print("=" * 40)
if not API_KEY:
    print("⚠️  Set ANTHROPIC_API_KEY first:")
    print("  export ANTHROPIC_API_KEY=sk-ant-...")
    print("=" * 40)

while True:
    try:
        user = input("\n>>> ")
    except (EOFError, KeyboardInterrupt):
        print("\nBye!")
        break
    if user.strip() in ("exit", "quit"): break
    if not user.strip(): continue
    
    messages.append({"role": "user", "content": user})
    
    data = json.dumps({
        "model": "claude-sonnet-4-20250514",
        "max_tokens": 1024,
        "messages": messages,
        "tools": TOOLS if API_KEY else []
    }).encode()
    
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=data,
        headers={
            "x-api-key": API_KEY,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        }
    )
    
    try:
        resp = urllib.request.urlopen(req)
        result = json.loads(resp.read())
        for block in result.get("content", []):
            if block["type"] == "text":
                print(f"\n{block['text']}")
            elif block["type"] == "tool_use" and block["name"] == "shell":
                cmd = block["input"]["cmd"]
                print(f"\n🔧 Running: {cmd}")
                r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
                output = r.stdout + r.stderr
                print(output)
                # Send tool result back
                messages.append({"role": "assistant", "content": result["content"]})
                messages.append({"role": "user", "content": [
                    {"type": "tool_result", "tool_use_id": block["id"], "content": output or "(no output)"}
                ]})
        if result["content"][0]["type"] == "text":
            messages.append({"role": "assistant", "content": result["content"][0]["text"]})
    except Exception as e:
        print(f"❌ Error: {e}")
