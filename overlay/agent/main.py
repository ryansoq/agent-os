#!/usr/bin/env python3
"""Agent OS v0.2 — Multi-Provider LLM Client

支援的 Provider（優先順序）：
  1. Groq   — 免費、超快（Llama 3）  → GROQ_API_KEY
  2. Claude — 最強（需付費）          → ANTHROPIC_API_KEY

免費取得 Groq API Key：https://console.groq.com/keys
"""
import json, urllib.request, os, subprocess, sys

# ===== Provider 自動偵測 =====
GROQ_KEY = os.environ.get("GROQ_API_KEY", "")
CLAUDE_KEY = os.environ.get("ANTHROPIC_API_KEY", "")

if CLAUDE_KEY:
    PROVIDER = "claude"
    API_KEY = CLAUDE_KEY
    MODEL = "claude-sonnet-4-20250514"
    API_URL = "https://api.anthropic.com/v1/messages"
elif GROQ_KEY:
    PROVIDER = "groq"
    API_KEY = GROQ_KEY
    MODEL = "llama-3.3-70b-versatile"
    API_URL = "https://api.groq.com/openai/v1/chat/completions"
else:
    PROVIDER = None
    API_KEY = None

# ===== Tool Definitions =====
TOOLS_CLAUDE = [{
    "name": "shell",
    "description": "Execute a shell command on this Agent OS",
    "input_schema": {
        "type": "object",
        "properties": {"cmd": {"type": "string", "description": "Shell command"}},
        "required": ["cmd"]
    }
}]

TOOLS_OPENAI = [{
    "type": "function",
    "function": {
        "name": "shell",
        "description": "Execute a shell command on this Agent OS",
        "parameters": {
            "type": "object",
            "properties": {"cmd": {"type": "string", "description": "Shell command"}},
            "required": ["cmd"]
        }
    }
}]

def run_shell(cmd):
    """執行 shell 指令並回傳結果"""
    print(f"\n🔧 Running: {cmd}")
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        output = (r.stdout + r.stderr).strip()
        print(output if output else "(no output)")
        return output or "(no output)"
    except subprocess.TimeoutExpired:
        print("⏰ Command timed out")
        return "Command timed out after 30 seconds"

# ===== Claude API =====
def call_claude(messages):
    data = json.dumps({
        "model": MODEL,
        "max_tokens": 1024,
        "messages": messages,
        "tools": TOOLS_CLAUDE,
        "system": "You are an AI agent running on Agent OS, a minimal Linux system. You can execute shell commands to help the user. Be concise."
    }).encode()
    req = urllib.request.Request(API_URL, data=data, headers={
        "x-api-key": API_KEY,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
        "user-agent": "AgentOS/0.2"
    })
    resp = urllib.request.urlopen(req)
    return json.loads(resp.read())

def handle_claude(result, messages):
    text_parts = []
    for block in result.get("content", []):
        if block["type"] == "text":
            text_parts.append(block["text"])
            print(f"\n{block['text']}")
        elif block["type"] == "tool_use" and block["name"] == "shell":
            output = run_shell(block["input"]["cmd"])
            messages.append({"role": "assistant", "content": result["content"]})
            messages.append({"role": "user", "content": [
                {"type": "tool_result", "tool_use_id": block["id"], "content": output}
            ]})
            # Continue conversation after tool use
            follow = call_claude(messages)
            handle_claude(follow, messages)
            return
    if text_parts:
        messages.append({"role": "assistant", "content": "\n".join(text_parts)})

# ===== Groq/OpenAI API =====
SYSTEM_PROMPT = "You are an AI agent running on Agent OS, a minimal Linux system. You have a 'shell' tool to execute commands. IMPORTANT: Only use the shell tool when the user asks you to DO something on the system. For normal conversation, just reply with text. Be concise. Reply in the same language as the user."

def call_groq(messages, use_tools=True):
    payload = {
        "model": MODEL,
        "max_tokens": 1024,
        "messages": [{"role": "system", "content": SYSTEM_PROMPT}] + messages,
    }
    if use_tools:
        payload["tools"] = TOOLS_OPENAI
    data = json.dumps(payload).encode()
    req = urllib.request.Request(API_URL, data=data, headers={
        "authorization": f"Bearer {API_KEY}",
        "content-type": "application/json",
        "user-agent": "AgentOS/0.2"
    })
    resp = urllib.request.urlopen(req)
    return json.loads(resp.read())

def handle_groq(result, messages):
    choice = result["choices"][0]["message"]
    
    # Case 1: tool call
    if choice.get("tool_calls"):
        # Run each tool
        tool_outputs = []
        for tc in choice["tool_calls"]:
            if tc["function"]["name"] == "shell":
                args = json.loads(tc["function"]["arguments"])
                output = run_shell(args["cmd"])
                tool_outputs.append((tc["id"], output))
        
        # Add assistant message with tool calls (minimal format)
        messages.append({
            "role": "assistant",
            "content": choice.get("content") or "",
            "tool_calls": [{"id": tc["id"], "type": "function", "function": tc["function"]} for tc in choice["tool_calls"]]
        })
        # Add tool results
        for tc_id, output in tool_outputs:
            messages.append({"role": "tool", "tool_call_id": tc_id, "content": output})
        
        # Get follow-up (no tools this time to avoid infinite loop)
        try:
            follow = call_groq(messages, use_tools=False)
            fc = follow["choices"][0]["message"]
            if fc.get("content"):
                print(f"\n{fc['content']}")
                messages.append({"role": "assistant", "content": fc["content"]})
        except:
            pass  # Tool output already shown
    
    # Case 2: text only
    elif choice.get("content"):
        print(f"\n{choice['content']}")
        messages.append({"role": "assistant", "content": choice["content"]})

# ===== Main =====
print("\n🤖 Agent OS v0.2")
print("=" * 40)

if PROVIDER:
    label = {"claude": "Claude (Anthropic)", "groq": "Groq (Llama 3, 免費)"}[PROVIDER]
    print(f"  Provider: {label}")
    print(f"  Model:    {MODEL}")
else:
    print("  ⚠️  沒有設定 API Key！")
    print()
    print("  🆓 免費方案（推薦）：")
    print("    1. 去 https://console.groq.com/keys 申請 key")
    print("    2. export GROQ_API_KEY=gsk_...")
    print("    3. python3 /agent/main.py")
    print()
    print("  💎 付費方案：")
    print("    export ANTHROPIC_API_KEY=sk-ant-...")
    
print("=" * 40)
print("  輸入 exit 離開 | 我可以幫你執行 shell 指令！")

messages = []

while True:
    try:
        user = input("\n>>> ")
    except (EOFError, KeyboardInterrupt):
        print("\nBye!")
        break
    if user.strip().lower() in ("exit", "quit"):
        break
    if user.strip().lower() in ("reset", "clear"):
        messages.clear()
        print("🔄 對話已重置")
        continue
    if not user.strip():
        continue
    if not PROVIDER:
        print("❌ 請先設定 API Key（見上方說明）")
        continue
    
    messages.append({"role": "user", "content": user})
    
    # 保留最近 20 條訊息，避免 context 太長出錯
    if len(messages) > 20:
        messages[:] = messages[-20:]
    
    try:
        if PROVIDER == "claude":
            result = call_claude(messages)
            handle_claude(result, messages)
        else:
            result = call_groq(messages)
            handle_groq(result, messages)
    except urllib.error.HTTPError as e:
        body = e.read().decode() if hasattr(e, 'read') else ''
        print(f"❌ API Error {e.code}: {e.reason}")
        if body:
            try:
                err = json.loads(body)
                print(f"   {err.get('error', {}).get('message', body[:200])}")
            except:
                print(f"   {body[:200]}")
        messages.pop()
    except Exception as e:
        print(f"❌ Error: {e}")
        messages.pop()
