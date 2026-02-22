# 🐧 Linux 開機流程 — 從按下電源到螢幕出現字

> **給好奇寶寶的完整教學** 🧐
>
> 你有沒有想過：按下電源鍵之後，到底發生了什麼事？
> 為什麼螢幕會亮？為什麼 Windows/Linux 會跑起來？
> CPU 開機的第一條指令是什麼？
>
> 這份教學帶你從**真正的 Linux 原始碼**一步步看懂整個過程。
> 不需要是大神，只要有好奇心就夠了 ✨

---

## 🗺️ 學習路線

我們準備了**兩套教材**，建議搭配使用：

### 🎮 路線 A：動手做（先跑再說）

> 「我不想只看理論，我要自己寫、自己編、自己跑！」

到 [`examples/`](examples/) 資料夾，4 個迷你範例，每個都能編譯 + QEMU 執行：

```bash
cd examples/01_hello_realmode
./build.sh    # 編譯 + 啟動 QEMU，馬上看到輸出！
```

| 順序 | 範例 | 你會學到 | 你會看到 |
|------|------|---------|---------|
| 1️⃣ | [01_hello_realmode](examples/01_hello_realmode/) | CPU 開機的第一個程式 | `Hello from Real Mode!` |
| 2️⃣ | [02_protected_mode](examples/02_protected_mode/) | GDT 是什麼？為什麼需要門禁？ | `Hello from 32-bit Protected Mode!` |
| 3️⃣ | [03_long_mode](examples/03_long_mode/) | 頁表怎麼建？怎麼進 64-bit？ | `Hello from 64-bit Long Mode!` |
| 4️⃣ | [04_c_kernel](examples/04_c_kernel/) | 怎麼從組語跳到 C 語言？ | `Hello from C kernel!` |

**需要的工具**：`nasm`、`gcc`、`qemu-system-x86_64`
```bash
# Ubuntu/WSL 安裝
sudo apt install nasm gcc qemu-system-x86
```

---

### 📖 路線 B：讀原始碼（看 Linux 怎麼做）

> 「我想看真正的 Linux kernel 是怎麼寫的！」

6 個檔案，從 Linux 6.19.3 原始碼複製關鍵段落，**每一行都有中文註解**：

| 順序 | 檔案 | 來源 | 在幹嘛？ |
|------|------|------|---------|
| 1️⃣ | [01_header.S](01_header.S) | `arch/x86/boot/header.S` | BIOS 把 kernel 載入後的第一站 |
| 2️⃣ | [02_pm.c](02_pm.c) | `arch/x86/boot/pm.c` | 準備離開 Real Mode |
| 3️⃣ | [03_pmjump.S](03_pmjump.S) | `arch/x86/boot/pmjump.S` | 按下「升級開關」跳到 32-bit |
| 4️⃣ | [04_head_64.S](04_head_64.S) | `arch/x86/boot/compressed/head_64.S` | 蓋頁表、開 64-bit |
| 5️⃣ | [05_kernel_head_64.S](05_kernel_head_64.S) | `arch/x86/kernel/head_64.S` | 正式 kernel 的第一步 |
| 6️⃣ | [06_main.c](06_main.c) | `init/main.c` | `start_kernel()` — C 語言的起點 |

---

### 📚 路線 C：概念深入（搞懂「為什麼」）

> 「我想知道為什麼要這樣設計？」

| 檔案 | 你會搞懂的問題 |
|------|---------------|
| [05_RINGS_AND_SYSCALL.md](05_RINGS_AND_SYSCALL.md) | 為什麼 Chrome 不能直接讀你的硬碟？為什麼 Ring 3 進不了 Ring 0？Syscall 到底怎麼運作？ |

---

## 🤔 先回答你最好奇的問題

### Q: 按下電源後到底發生什麼事？

```
🔌 按下電源
   │
   ▼
🏭 CPU 醒來，從固定地址 0xFFFFFFF0 開始執行
   │  （這個地址指向主機板上的 BIOS/UEFI 晶片）
   │
   ▼
📋 BIOS 自檢（POST）
   │  鍵盤有嗎？記憶體有嗎？硬碟有嗎？
   │
   ▼
💾 BIOS 讀硬碟第一個磁區（512 bytes）到記憶體 0x7C00
   │  這 512 bytes 就是「boot sector」
   │  最後兩個 byte 必須是 0x55AA（BIOS 的暗號）
   │
   ▼
🚀 CPU 跳到 0x7C00 開始執行
   │  此時是 16-bit Real Mode（1978 年的模式！）
   │
   ▼
🔑 Linux 開始接管（就是我們教學的起點！）
   │
   │  01_header.S → Real Mode 設定
   │  02_pm.c     → 準備離開 Real Mode
   │  03_pmjump.S → 跳到 32-bit Protected Mode
   │  04_head_64.S → 建頁表、跳到 64-bit Long Mode
   │  05_kernel_head_64.S → 正式 kernel 設定
   │  06_main.c   → start_kernel() 初始化一切
   │
   ▼
🐧 Linux 啟動完成！
   │  執行 /sbin/init → 啟動系統服務 → 顯示登入畫面
```

### Q: 為什麼 CPU 開機是 16-bit？現在不是 64-bit 嗎？

**向下相容！** Intel 從 1978 年的 8086（16-bit）一路發展到現在。
為了讓 30 年前的程式還能跑，CPU 開機時會「裝作」自己是 1978 年的 8086。

```
CPU 開機 → 假裝是 8086（16-bit Real Mode）
    → 你手動升級到 32-bit（Protected Mode）
        → 再升級到 64-bit（Long Mode）

就像新款 iPhone 開機時先跑最基本的韌體，
確認一切正常後才進入完整的 iOS。
```

### Q: 什麼是 GDT？為什麼需要它？

**想像你住在一棟沒有門鎖的老公寓（Real Mode）：**
- 任何人都能進任何房間
- 隔壁的人可以翻你的抽屜
- 一個人放火 → 整棟樓一起燒

**GDT 就是幫大樓裝門禁系統（Protected Mode）：**
- 每扇門上面寫著「誰可以進」
- 管理員（Ring 0）能去所有地方
- 訪客（Ring 3）只能待在大廳
- 一個人出事 → 不會影響其他人

→ 詳細解說看 [02_pm.c](02_pm.c)（Linux 怎麼設定 GDT）
→ 自己動手做看 [examples/02_protected_mode](examples/02_protected_mode/)

### Q: 什麼是頁表？為什麼 Chrome 看不到 Firefox 的記憶體？

**頁表 = 每個程式拿到一份「假地圖」：**

```
Chrome 以為的世界：          Firefox 以為的世界：
  地址 0x1000 = 我的資料       地址 0x1000 = 我的資料
       ↓ 頁表翻譯                    ↓ 頁表翻譯
  實際在 RAM 0x50000            實際在 RAM 0x80000

同一個地址，不同的實際位置！
互相看不到、互相不影響 ✨
```

→ 詳細解說看 [04_head_64.S](04_head_64.S)（Linux 怎麼建頁表）
→ 自己動手做看 [examples/03_long_mode](examples/03_long_mode/)

### Q: 為什麼病毒不能直接控制整台電腦？

**因為 CPU 的 Ring 特權機制：**

```
Ring 0（Kernel）= 管理員 👑 → 能做任何事
Ring 3（User）  = 訪客 🧑  → 只能做被允許的事

病毒跑在 Ring 3，想要：
  ❌ 讀硬碟任意位置 → 被 Ring 擋住
  ❌ 改 kernel 記憶體 → 被頁表擋住  
  ❌ 直接操作硬體 → 特權指令，#GP 中斷

唯一的路：透過 syscall 請求 kernel 幫忙
  → kernel 會檢查：「你有權限嗎？」
  → 沒有就拒絕 ✋
```

→ 完整解說看 [05_RINGS_AND_SYSCALL.md](05_RINGS_AND_SYSCALL.md)

---

## 🔑 關鍵概念速查

| 概念 | 一句話解釋 | 在哪學 |
|------|-----------|--------|
| **Real Mode** | CPU 開機的 16-bit 模式，沒有保護 | 01_header.S、examples/01 |
| **GDT** | 記憶體的門禁卡系統 | 02_pm.c、examples/02 |
| **Protected Mode** | 有門禁的 32-bit 模式 | 03_pmjump.S、examples/02 |
| **頁表** | 每個程式拿到的「假地圖」 | 04_head_64.S、examples/03 |
| **Long Mode** | 64-bit 模式，現代系統都用這個 | 04_head_64.S、examples/03 |
| **Ring 0/3** | CPU 的權限等級 | 05_RINGS_AND_SYSCALL.md |
| **Syscall** | User 請求 Kernel 幫忙的唯一方式 | 05_RINGS_AND_SYSCALL.md |
| **start_kernel()** | Linux 用 C 語言寫的起點 | 06_main.c、examples/04 |

---

## 💡 閱讀建議

**完全新手**：先跑 `examples/01`，看到 Hello 再往下
**有基礎的**：路線 A + B 對照看，精簡版理解概念，原始碼看 Linux 怎麼做
**想深入的**：路線 C 搞懂「為什麼這樣設計」

每個檔案裡：
- 🔑 = 最關鍵的行，優先看
- 🏰 = 比喻，幫助理解
- 💡 = 補充知識
- ⚠️ = 容易搞混的地方

看不懂就跳過，繼續往下，回頭再看會更清楚 😊

---

## 🏗️ 開機流程完整圖

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   BIOS/UEFI                                                     │
│   「我找到硬碟了，把第一個磁區載入到 0x7C00」                      │
│                                                                 │
└──────────────────────────┬──────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ 📍 01_header.S — Real Mode (16-bit)                             │
│                                                                 │
│   「我是 Linux，剛被 BIOS 叫醒」                                 │
│   • 設定 stack（程式需要記事本）                                  │
│   • 清空 BSS（把桌子清乾淨）                                     │
│   • 跳到 C code                                                 │
│                                                                 │
│   🎮 對應範例: examples/01_hello_realmode                        │
└──────────────────────────┬──────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ 📍 02_pm.c + 03_pmjump.S — Real Mode → Protected Mode          │
│                                                                 │
│   「16-bit 太老了，我要升級到 32-bit！」                          │
│   • 關中斷（升級期間請勿打擾 🚫）                                │
│   • 開 A20（解鎖 1MB 以上的記憶體）                              │
│   • 設定 GDT（裝門禁系統 🏰）                                   │
│   • CR0.PE = 1（按下升級開關！）                                  │
│   • Far Jump（跳到 32-bit 世界）                                 │
│                                                                 │
│   🎮 對應範例: examples/02_protected_mode                        │
└──────────────────────────┬──────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ 📍 04_head_64.S — Protected Mode → Long Mode (64-bit)           │
│                                                                 │
│   「32-bit 只能用 4GB RAM，不夠！我要 64-bit！」                  │
│   • 建立 4 級頁表（發地圖給每個程式 🗺️）                        │
│   • 開 PAE（拿到上高速公路的資格）                                │
│   • EFER.LME = 1（申請 ETC 通行證 🚀）                          │
│   • CR0.PG = 1（開過收費站，正式上高速公路）                      │
│   • Far Jump → 64-bit！                                         │
│                                                                 │
│   🎮 對應範例: examples/03_long_mode                             │
└──────────────────────────┬──────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ 📍 05_kernel_head_64.S — 64-bit Kernel 設定                     │
│                                                                 │
│   「終於到 64-bit 了，做最後的準備工作」                          │
│   • 重新設定 GDT/IDT                                            │
│   • 設定 GSBASE（per-CPU 資料）                                  │
│   • 修正頁表映射                                                 │
│   • 呼叫 C 語言！                                               │
└──────────────────────────┬──────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│ 📍 06_main.c — start_kernel()                                   │
│                                                                 │
│   「組語的工作結束了，C 語言登場！」                              │
│   • 初始化記憶體管理（mm_init）                                  │
│   • 初始化排程器（sched_init）                                   │
│   • 初始化檔案系統（vfs_caches_init）                            │
│   • 初始化網路（net_init）                                      │
│   • rest_init() → 啟動第一個 process（PID 1: init）             │
│   • 🎉 Linux 正式上線！                                         │
│                                                                 │
│   🎮 對應範例: examples/04_c_kernel                              │
└─────────────────────────────────────────────────────────────────┘
```

---

*基於 Linux 6.19.3 原始碼。由 Nami 🌊 製作。*
