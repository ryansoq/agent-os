# 🐧 Linux 開機流程原始碼教學 (Linux 6.19.3)

> 從 BIOS 把控制權交給 Linux 開始，一路到 `start_kernel()` 為止。
> 每個檔案都是從真實原始碼複製關鍵段落，加上繁體中文逐行註解。

## 📋 開機流程總覽

```
BIOS/UEFI
  │
  ▼
┌─────────────────────────────────────────────┐
│ 01_header.S  — Real Mode 入口點             │
│   BIOS 載入 boot sector → _start            │
│   設定 stack、清 BSS、跳到 C code (main)     │
└──────────────────┬──────────────────────────┘
                   ▼
┌─────────────────────────────────────────────┐
│ 02_pm.c — 準備進入保護模式                   │
│   關中斷、開 A20、設定 GDT/IDT              │
│   呼叫 protected_mode_jump()                │
└──────────────────┬──────────────────────────┘
                   ▼
┌─────────────────────────────────────────────┐
│ 03_pmjump.S — 切換到 Protected Mode         │
│   設定 CR0.PE、far jump 到 32-bit code      │
│   設定 data segments、跳到 32-bit entry     │
└──────────────────┬──────────────────────────┘
                   ▼
┌─────────────────────────────────────────────┐
│ 04_head_64.S — 壓縮核心的 32→64 bit 轉換    │
│   建立 4 級頁表、開啟 PAE                    │
│   設定 EFER.LME (Long Mode Enable)          │
│   開啟分頁 + far jump 到 64-bit mode        │
│   解壓縮核心、跳到真正的 kernel              │
└──────────────────┬──────────────────────────┘
                   ▼
┌─────────────────────────────────────────────┐
│ 05_kernel_head_64.S — 64-bit Kernel 入口    │
│   設定 GDT/IDT、GSBASE                      │
│   修正頁表、設定 CR0/CR4/EFER               │
│   呼叫 x86_64_start_kernel()                │
└──────────────────┬──────────────────────────┘
                   ▼
┌─────────────────────────────────────────────┐
│ 06_main.c — start_kernel()                  │
│   所有子系統初始化：記憶體、排程器、         │
│   中斷、檔案系統、網路……                    │
│   最後 rest_init() → 啟動 init process      │
└─────────────────────────────────────────────┘
```

## 📂 檔案列表

| 編號 | 檔案 | 原始碼位置 | 說明 |
|------|------|-----------|------|
| 01 | [01_header.S](01_header.S) | `arch/x86/boot/header.S` | Real Mode 入口、setup header |
| 02 | [02_pm.c](02_pm.c) | `arch/x86/boot/pm.c` | 進入保護模式的流程（完整檔案） |
| 03 | [03_pmjump.S](03_pmjump.S) | `arch/x86/boot/pmjump.S` | CR0.PE + far jump（完整檔案） |
| 04 | [04_head_64.S](04_head_64.S) | `arch/x86/boot/compressed/head_64.S` | 頁表建立、Long Mode、64-bit 跳轉 |
| 05 | [05_kernel_head_64.S](05_kernel_head_64.S) | `arch/x86/kernel/head_64.S` | 正式 64-bit kernel entry |
| 06 | [06_main.c](06_main.c) | `init/main.c` | `start_kernel()` 初始化 |

## 🔑 關鍵概念索引

- **GDT (Global Descriptor Table)** → 02_pm.c, 04_head_64.S
- **CR0.PE (Protection Enable)** → 03_pmjump.S
- **4 級頁表 (PML4→PDPT→PD→PT)** → 04_head_64.S
- **CR4.PAE / EFER.LME / CR0.PG** → 04_head_64.S
- **Identity Mapping** → 04_head_64.S
- **`__KERNEL32_CS` vs `__KERNEL_CS`** → 04_head_64.S (D-bit vs L-bit)

## 💡 閱讀建議

1. 按編號順序讀，每個檔案開頭的「教學筆記」會說明前後文
2. 🔑 標記的是最關鍵的行，優先看
3. GDT 和頁表段落有詳細的 bit field 拆解，慢慢看
4. 如果某段看不懂，先跳過繼續往下，回頭再看會更清楚
