# 🤖 Agent-Pi — Agent OS 的智能層

這個資料夾放 Agent 的核心邏輯，未來接 pi-mono。

## 架構

```
agent-pi/
├── main.py          ← 入口（50 行 LLM client，v0.1）
├── config.json      ← Agent 設定（model, API key, tools...）
├── sessions/        ← 對話持久化（pi 的 --session）
├── tools/           ← Agent 可用的工具
│   ├── shell.py     ← 執行 shell 指令
│   ├── file.py      ← 讀寫檔案
│   └── http.py      ← HTTP 請求
└── providers/       ← LLM provider 設定
    ├── claude.py
    ├── openai.py
    └── local.py     ← Ollama 等本地模型
```

## 演進路線

```
v0.1（現在）：50 行 Python，直接呼叫 Claude API
     ↓
v0.2：加 tool calling + session 存檔
     ↓
v0.3：接 pi-mono，用 spawn("pi", ...) 取代自己的 LLM 邏輯
     ↓
v1.0：完整 Agent OS，開機即 Agent
```

## v0.3 接 pi-mono 時的樣子

```python
# main.py（v0.3）— 超簡單，因為 pi 處理一切
import subprocess, json

session_path = "/agent/sessions/default.json"

while True:
    user = input(">>> ")
    result = subprocess.run(
        ["pi", "--session", session_path, "--print", user],
        capture_output=True, text=True
    )
    print(result.stdout)
```

Pi 處理：LLM API、tool calling、context compact、記憶
我們只管：I/O（stdin/stdout）
