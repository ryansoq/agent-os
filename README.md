# 🤖 Agent OS Builder

**Build your own AI Agent Operating System — from Kernel to LLM.**

從電源按鈕到 AI Agent 對話，一步步打造屬於你的作業系統。

```
⚙️ Kernel  →  📦 System  →  🤖 Agent
   能感知什麼      能用什麼工具      靈魂是誰
```

---

## 🌟 為什麼做這個？

大型語言模型（LLM）很強，但它們跑在別人的雲端、受限於別人的 sandbox。
如果 Agent 有自己的 OS，它就能：

- 🔧 直接控制硬體（GPIO、攝影機、感測器）
- 🐧 擁有完整的 Linux 工具鏈（bash、python、網路）
- 🧠 開機即運行，不需要人來啟動
- 🔒 在自己的環境裡安全地執行 Tool Calling

Agent OS Builder 讓你像組裝電腦一樣，勾選你要的元件，一鍵編譯出一個完整的 OS。

---

## 🏗️ Architecture — 三層架構

```
┌─────────────────────────────────────────────┐
│                 🤖 Agent Layer              │
│  LLM Client · Tool Calling · Prompt · RAG  │
├─────────────────────────────────────────────┤
│                📦 System Layer              │
│  BusyBox · Python · SSH · Network · Shell   │
├─────────────────────────────────────────────┤
│                ⚙️ Kernel Layer              │
│  Linux 6.x · Drivers · Filesystem · TCP/IP  │
└─────────────────────────────────────────────┘
         ↕ Buildroot 一次編譯搞定
```

| 層級 | 你決定的事 | 類比 |
|------|-----------|------|
| Kernel | 能感知什麼硬體 | 身體的神經系統 |
| System | 能用什麼工具 | 身體的手腳 |
| Agent | 靈魂是誰 | 大腦 |

---

## 🚀 Quick Start

```bash
# 1. Clone
git clone https://github.com/ryansoq/agent-os.git
cd agent-os

# 2. 安裝依賴
make install-deps

# 3. 編譯 OS（首次約 30-60 分鐘）
make build

# 4. 啟動 Web UI
make web
# 瀏覽器開啟 http://localhost:3001

# 5. QEMU 開機（也可以從 Web UI 啟動）
make run
```

### 系統需求

- Ubuntu 20.04+ / WSL2
- 10GB+ 磁碟空間
- Node.js 18+
- QEMU (`qemu-system-x86`)

---

## 📁 目錄結構

```
agent-os/
├── Makefile            # 主要指令入口
├── server.js           # Web UI 後端（Express + WebSocket）
├── public/             # Web UI 前端
├── scripts/
│   ├── build.sh        # Buildroot 編譯腳本
│   └── run-qemu.sh     # QEMU 啟動腳本
├── overlay/            # Root filesystem overlay
│   └── etc/init.d/
│       └── S99agent    # 開機自動啟動 Agent
├── agent-pi/
│   ├── main.py         # Agent LLM Client（50 行！）
│   ├── tools/          # Tool Calling 工具
│   ├── providers/      # LLM Provider 抽象
│   └── config.json     # Agent 設定
├── images/             # 編譯產出（bzImage, rootfs）
├── docs/               # 📚 學習文件（從 BIOS 到 main()）
└── watchdog.sh         # Agent 看門狗
```

---

## 🎛️ Profile 快速選擇

在 Web UI 中可以選擇預設的 Profile：

| Profile | 說明 | 大小 | 用途 |
|---------|------|------|------|
| 🤖 VM Agent | QEMU 虛擬機 + Agent | ~15MB | 開發測試 |
| 🍓 Pi Agent | Raspberry Pi + GPIO | ~20MB | 實體部署 |
| 📦 Full | 完整工具鏈 | ~50MB | 進階使用 |
| ⚡ Minimal | 最小 Linux | ~5MB | 學習用 |

---

## 🌐 Web UI

啟動 `make web` 後在 `http://localhost:3001` 可以：

1. **三層套件選擇** — 勾選 Kernel / System / Agent 各層要什麼
2. **一鍵編譯** — 呼叫 Buildroot 從原始碼編譯
3. **QEMU Terminal** — 在瀏覽器裡直接操作 VM（xterm.js + WebSocket）
4. **即時 Log** — 看到完整的編譯過程

---

## 📚 學習文件

**想理解 Linux 從開機到 `main()` 的完整過程？** 看 `docs/` 目錄：

| 文件 | 主題 | 你會學到 |
|------|------|---------|
| [00_OVERVIEW](docs/00_OVERVIEW.md) | 全景導覽 | 為什麼需要 OS？學習路線圖 |
| [01_BIOS_TO_BOOTLOADER](docs/01_BIOS_TO_BOOTLOADER.md) | 電源 → Bootloader | CPU 開機第一件事 |
| [02_REAL_MODE](docs/02_REAL_MODE.md) | 16-bit Real Mode | Segment:Offset、A20 Gate |
| [03_GDT_AND_SEGMENTATION](docs/03_GDT_AND_SEGMENTATION.md) | GDT 與分段 | 64-bit 描述符完整解碼 |
| [04_PROTECTED_MODE](docs/04_PROTECTED_MODE.md) | Protected Mode | CR0.PE、Far Jump、Ring 0-3 |
| [05_PAGING](docs/05_PAGING.md) | 分頁機制 | 4 級頁表、虛擬地址翻譯 |
| [06_LONG_MODE](docs/06_LONG_MODE.md) | 64-bit Long Mode | PAE → EFER → 64-bit |
| [07_START_KERNEL](docs/07_START_KERNEL.md) | start_kernel() | C 語言的起點、PID 0/1/2 |
| [08_USERSPACE](docs/08_USERSPACE.md) | User Space | /sbin/init → Agent 啟動 |

所有文件都是**繁體中文**，用比喻 + 原始碼（Linux 6.19.3）帶你一步步理解。

---

## 🤖 Agent 架構

Agent 只有 **50 行 Python**，開機即可與 LLM 對話 + Tool Calling：

```python
# agent-pi/main.py（簡化版）
while True:
    user = input(">>> ")
    response = call_llm(user, tools=[shell, read_file, ...])
    if response.tool_use:
        result = execute_tool(response.tool_use)
        # 把結果回傳給 LLM 繼續推理
```

支援的 Tools：
- `shell` — 執行系統指令
- `read_file` / `write_file` — 檔案操作
- 可自行擴充任何 Tool

---

## 📜 License

MIT

---

*Built with ❤️ by Ryan — 讓 AI Agent 擁有自己的身體。*
