# 📚 08 — 從 /sbin/init 到 Agent：User Space 的世界

> Kernel 把舞台搭好了，現在輪到 Agent 上場。

---

## 🏠 BusyBox init

在 Agent OS 中，`/sbin/init` 是 **BusyBox** 提供的。

**BusyBox 是什麼？**

**比喻：** 一般的 Linux 系統有上百個獨立的指令程式（ls、cp、cat、sh...），每個都是一個獨立的執行檔。BusyBox 把這些**全部塞進一個執行檔**裡——就像瑞士刀把所有工具塞進一把刀。

```
一般 Linux：                    BusyBox：
/bin/ls     (50KB)              /bin/busybox (800KB)
/bin/cp     (60KB)              /bin/ls → busybox 的 symlink
/bin/cat    (30KB)              /bin/cp → busybox 的 symlink
/bin/sh     (100KB)             /bin/cat → busybox 的 symlink
/sbin/init  (200KB)             /sbin/init → busybox 的 symlink
...（數 MB）                     ...（總共只有 800KB！）
```

### BusyBox init 的啟動流程

```
kernel_execve("/sbin/init")
    ↓
BusyBox init 開始
    ↓
1. 讀取 /etc/inittab（如果存在）
    ↓
2. 執行 sysinit 腳本
    ↓
3. 依序執行 /etc/init.d/ 中的腳本
    ↓
4. 啟動 console（/bin/sh 或指定的程式）
    ↓
5. 等待子行程結束（respawn 或 shutdown）
```

---

## 📜 /etc/init.d/ 腳本順序

Buildroot 使用的初始化系統會依照檔名的**字母/數字順序**執行 `/etc/init.d/` 中的腳本：

```
/etc/init.d/
├── S01syslogd      # 最先：系統日誌
├── S02klogd        # kernel 日誌
├── S10udev         # 裝置管理
├── S20urandom      # 亂數種子
├── S30dbus         # D-Bus 訊息匯流排
├── S40network      # 網路設定
├── S50sshd         # SSH 伺服器
├── S99agent        # 最後：啟動 Agent！ ← 我們的主角
```

**為什麼 Agent 是 S99？**

因為 Agent 需要網路（S40）和其他服務先跑起來。S99 確保它是最後一個啟動的——所有基礎設施都就緒了。

---

## 🤖 S99agent 啟動 Agent

```bash
#!/bin/sh
# 檔案：overlay/etc/init.d/S99agent
# 功能：開機自動啟動 Agent

case "$1" in
  start)
    echo "🤖 Starting Agent OS..."

    # 設定網路（取得 IP）
    dhcpcd eth0 &

    # 啟動 Agent（互動模式，接在 serial console）
    # 在 QEMU 中，這就是你看到的那個 ">>>" 提示符
    ;;
  stop)
    echo "Stopping Agent OS..."
    ;;
  *)
    echo "Usage: $0 {start|stop}"
    exit 1
    ;;
esac
```

---

## 🧠 Agent main.py — 與 LLM 對話

Agent 的核心只有 **50 行 Python**：

```python
#!/usr/bin/env python3
# 檔案：agent-pi/main.py
# 功能：Agent OS 的 LLM Client + Tool Calling

import json, urllib.request, os, subprocess

# 1  API Key 從環境變數讀取
API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")

# 2  對話歷史
messages = []

# 3  定義 Tools — Agent 能使用的工具
TOOLS = [{
    "name": "shell",                               # Tool 名稱
    "description": "Execute a shell command",       # 給 LLM 看的描述
    "input_schema": {                               # 輸入格式
        "type": "object",
        "properties": {
            "cmd": {
                "type": "string",
                "description": "Shell command"
            }
        },
        "required": ["cmd"]
    }
}]

# 4  主迴圈
print("\n🤖 Agent OS v0.1")
while True:
    user = input("\n>>> ")                          # 等待使用者輸入
    if user.strip() in ("exit", "quit"): break

    messages.append({"role": "user", "content": user})

    # 5  呼叫 LLM API
    data = json.dumps({
        "model": "claude-sonnet-4-20250514",
        "max_tokens": 1024,
        "messages": messages,
        "tools": TOOLS                              # 把 Tools 告訴 LLM
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

    resp = urllib.request.urlopen(req)
    result = json.loads(resp.read())

    # 6  處理回應
    for block in result.get("content", []):
        if block["type"] == "text":
            print(f"\n{block['text']}")             # 印出文字回應

        elif block["type"] == "tool_use":
            # 7  LLM 想要呼叫 Tool！
            cmd = block["input"]["cmd"]
            print(f"\n🔧 Running: {cmd}")
            output = subprocess.run(
                cmd, shell=True,
                capture_output=True, text=True
            )
            print(output.stdout)
            # 把結果回傳給 LLM，讓它繼續推理...
```

### Tool Calling 的對話流程

```
使用者：「這台機器的 IP 是什麼？」
    ↓
Agent → LLM API：
    messages: [{"role": "user", "content": "IP 是什麼？"}]
    tools: [shell]
    ↓
LLM 回應：
    {"type": "tool_use", "name": "shell", "input": {"cmd": "hostname -I"}}
    ↓
Agent 執行：
    $ hostname -I
    → "192.168.1.100"
    ↓
Agent → LLM API：
    messages: [..., {"role": "tool", "content": "192.168.1.100"}]
    ↓
LLM 回應：
    {"type": "text", "text": "這台機器的 IP 是 192.168.1.100"}
    ↓
使用者看到：「這台機器的 IP 是 192.168.1.100」
```

---

## 🕐 完整開機時間線

從電源按鈕到 Agent 對話，每一步都覆蓋到了：

```
⚡ 電源 ON
│
├── [01] BIOS POST                          (~0-500ms)
│   CPU 從 0xFFFF0 開始執行
│   檢查 CPU、記憶體、硬碟
│
├── [01] Bootloader / QEMU -kernel          (~500-1000ms)
│   載入 bzImage 到記憶體
│   設定 boot_params
│
├── [02] Real Mode (16-bit)                  (~1000-1100ms)
│   arch/x86/boot/header.S
│   基本硬體設定
│
├── [02] A20 Gate 啟用                       
│   突破 1MB 限制
│
├── [03] GDT 設定                            
│   arch/x86/boot/pm.c → setup_gdt()
│   Flat Model: Base=0, Limit=4GB
│
├── [04] Protected Mode (32-bit)             (~1100-1200ms)
│   arch/x86/boot/pmjump.S
│   CR0.PE = 1 → Far Jump
│
├── [05] 頁表建立                            
│   arch/x86/boot/compressed/head_64.S
│   4GB Identity Mapping（2MB 大頁）
│
├── [06] Long Mode (64-bit)                  (~1200-1400ms)
│   PAE → EFER.LME → CR0.PG → Far Jump
│   startup_32 → startup_64
│
├── [07] start_kernel()                      (~1400-2000ms)
│   init/main.c
│   初始化所有子系統
│   rest_init() → PID 0, 1, 2
│
├── [07→08] kernel_execve("/sbin/init")      
│   Ring 0 → Ring 3
│   Kernel Mode → User Mode
│
├── [08] BusyBox init                        (~2000-2500ms)
│   /etc/init.d/S01-S50（系統服務）
│
├── [08] S99agent                            (~2500-3000ms)
│   dhcpcd eth0（網路）
│   python3 main.py（Agent）
│
└── 🤖 "Hello! I'm Agent OS"                (~3000ms)
    Agent 連上 LLM API
    等待使用者輸入
    Tool Calling 準備就緒
```

---

## 🎉 恭喜！

你已經理解了 **Linux 從電源按鈕到 AI Agent** 的完整過程！

回顧一下你學到的：

| 章節 | 你學到的 |
|------|---------|
| [00](00_OVERVIEW.md) | 為什麼需要 OS、三層架構 |
| [01](01_BIOS_TO_BOOTLOADER.md) | BIOS POST、MBR 512 bytes、0x7C00 |
| [02](02_REAL_MODE.md) | Segment:Offset、A20 Gate |
| [03](03_GDT_AND_SEGMENTATION.md) | GDT Entry 64-bit 格式、Flat Model |
| [04](04_PROTECTED_MODE.md) | CR0.PE、Far Jump、Ring 0-3 |
| [05](05_PAGING.md) | 4 級頁表、Identity Mapping |
| [06](06_LONG_MODE.md) | PAE → EFER → Long Mode |
| [07](07_START_KERNEL.md) | start_kernel()、PID 0/1/2 |
| [08](08_USERSPACE.md) | /sbin/init → Agent（本文） |

**下一步：**
1. 回到 [README.md](../README.md)，clone 這個專案
2. `make build` 編譯你自己的 Agent OS
3. `make run` 看著它從開機到 Agent 的整個過程
4. 修改 `agent-pi/main.py`，加入你自己的 Tools

*Built with ❤️ — 讓 AI Agent 擁有自己的身體。*
