# 📚 02 — entry.S：開啟分頁，跳到 main()

> 分頁就像地址翻譯員——你說「中文路名」，它翻成「GPS 座標」。

---

## 🤔 為什麼需要分頁？

`bootmain()` 把 kernel 載入到物理位址 `0x100000`（1MB 處，Extended Memory 的起點）。但 xv6 的 kernel 程式碼是用虛擬位址 `0x80100000`（KERNBASE + 1MB）來編譯連結的。

```
問題：
  kernel 程式碼裡的所有位址都是 0x8xxxxxxx
  但 kernel 實際在物理記憶體的 0x00100000

如果不開分頁，CPU 去存取 0x80100000 時
會找到...什麼都沒有（超出物理記憶體範圍）→ 💥 當機！

解法：
  開啟分頁，建立映射：
  虛擬 0x80000000 → 物理 0x00000000
  這樣 0x80100000 就會被翻譯成 0x00100000 ✅
```

**比喻：** kernel 的程式碼裡都寫著「送到中文路名」（虛擬位址），但實際包裹要送到「GPS 座標」（物理位址）。分頁就是那個翻譯對照表。

---

## 📄 `entry.S`：完整中文註解

```asm
# 檔案：entry.S
# 功能：kernel 的進入點（bootmain 跳到這裡）
# 任務：開啟分頁，設定 stack，跳到 main()

#include "asm.h"
#include "memlayout.h"
#include "mmu.h"
#include "param.h"

# ============================================================
# 前置知識：entrypgdir（定義在 main.c 底部）
# ============================================================
# 這是一個臨時頁目錄（Page Directory），只有兩個 entry：
#
#   entrypgdir[0]：虛擬 [0, 4MB) → 物理 [0, 4MB)
#   entrypgdir[512]：虛擬 [KERNBASE, KERNBASE+4MB) → 物理 [0, 4MB)
#
# 為什麼要兩個映射？
# 因為 entry.S 本身的程式碼在物理低位址（~0x10xxxx）
# 開啟分頁後，如果只有高位址映射，下一行指令（在低位址）就找不到了！
# 所以低位址和高位址都要映射，等跳到 main() 之後才能安全移除低位址映射。

.text
.globl multiboot_header
multiboot_header:
  # Multiboot header（給 GRUB 用的，QEMU 不需要）
  #define magic 0x1badb002
  #define flags 0
  .long magic
  .long flags
  .long (-magic-flags)

# _start 是 ELF 的進入點符號
# V2P_WO(entry) 把 entry 的虛擬位址轉成物理位址
# 因為 bootmain 是用物理位址跳過來的（分頁還沒開）
.globl _start
_start = V2P_WO(entry)

# ============================================================
# entry：kernel 真正開始的地方
# ============================================================
.globl entry
entry:
  # ---- 第一步：啟用 4MB 大頁 ----
  movl    %cr4, %eax          # 1  讀 CR4
  orl     $(CR4_PSE), %eax    # 2  設定 PSE（Page Size Extension）位
  movl    %eax, %cr4          # 3  寫回 CR4
  # PSE 允許用 4MB 的大頁（而不是 4KB 小頁）
  # 這讓 entrypgdir 只需要 Page Directory 就夠了
  # 不需要第二級的 Page Table → 簡單！

  # ---- 第二步：設定頁目錄 ----
  movl    $(V2P_WO(entrypgdir)), %eax  # 4  entrypgdir 的物理位址
  movl    %eax, %cr3                    # 5  CR3 = 頁目錄位址
  # CR3 告訴 CPU：去哪裡找頁表
  # 必須用物理位址（因為分頁還沒開）

  # ---- 第三步：開啟分頁！ ----
  movl    %cr0, %eax          # 6  讀 CR0
  orl     $(CR0_PG|CR0_WP), %eax  # 7  設定 PG（分頁）+ WP（寫保護）
  movl    %eax, %cr0          # 8  寫回 CR0
  #
  # 🎉 分頁啟動！
  # 從這一刻起，所有記憶體存取都會經過頁表翻譯
  # 但因為 entrypgdir 同時映射了低位址和高位址
  # 所以下一行指令（在低位址）還是能正常執行

  # ---- 第四步：設定 kernel stack ----
  movl $(stack + KSTACKSIZE), %esp  # 9  ESP = kernel stack 頂端
  # stack 是 .comm 宣告的 BSS 變數（KSTACKSIZE = 4KB）
  # 注意：這裡用的是高位址（因為 stack 是連結在 KERNBASE 以上的）

  # ---- 第五步：跳到高位址的 main()！ ----
  mov $main, %eax             # 10 EAX = main 的虛擬位址（0x8010xxxx）
  jmp *%eax                   # 11 跳！
  # 為什麼用間接跳轉？
  # 因為直接 jmp 會產生相對位址的指令
  # 我們目前在低位址執行，相對跳轉會算錯
  # 用暫存器間接跳轉就沒問題

.comm stack, KSTACKSIZE       # 12 在 BSS 區分配 KSTACKSIZE bytes 的 stack
```

---

## 📊 entrypgdir：臨時頁表

定義在 `main.c` 底部：

```c
// 開機用的臨時頁目錄
// 4MB 大頁，只需要 Page Directory，不需要 Page Table
__attribute__((__aligned__(PGSIZE)))
pde_t entrypgdir[NPDENTRIES] = {
  // 映射 1：虛擬 [0, 4MB) → 物理 [0, 4MB)
  //   entry.S 的程式碼在這個範圍，開啟分頁後仍需執行
  [0] = (0) | PTE_P | PTE_W | PTE_PS,

  // 映射 2：虛擬 [KERNBASE, KERNBASE+4MB) → 物理 [0, 4MB)
  //   kernel 連結在 KERNBASE 以上，main() 在這個範圍
  [KERNBASE>>PDXSHIFT] = (0) | PTE_P | PTE_W | PTE_PS,
};
// PTE_P  = Present（這個 entry 有效）
// PTE_W  = Writable（可寫）
// PTE_PS = Page Size（4MB 大頁）
```

### 記憶體映射圖

```
開啟分頁後的位址翻譯：

虛擬位址                    物理位址
0x80400000 ┌──────────┐
           │ 未映射   │
0x80000000 ├──────────┤   ┌──────────┐ 0x00400000
           │ 映射 2   │──→│          │
           │ 4MB 大頁 │   │ 物理 RAM │
           ├──────────┤   │ 0-4MB    │
           │ 未映射   │   │          │
           │   ...    │   │          │
0x00400000 ├──────────┤   │          │
           │ 映射 1   │──→│          │
           │ 4MB 大頁 │   └──────────┘ 0x00000000
0x00000000 └──────────┘

兩個虛擬位址範圍指向同一塊物理記憶體！
entry.S 在低位址執行 → 靠映射 1
跳到 main() 在高位址 → 靠映射 2
```

### 為什麼之後要換頁表？

`entrypgdir` 只映射了 4MB，但 kernel 需要更多記憶體。`main()` 裡的 `kvmalloc()` 會建立完整的 kernel 頁表，映射所有物理記憶體。

---

## 🔑 x86 分頁快速入門

```
x86 32-bit 二級頁表（正式版，非 4MB 大頁）：

虛擬位址 32 bits：
┌──────────┬──────────┬──────────────┐
│ PDX (10) │ PTX (10) │ Offset (12)  │
└────┬─────┴────┬─────┴──────┬───────┘
     │          │            │
     │ Page Directory        │
     │ ┌──────────┐          │
     └→│ PDE      │          │
       │ 指向 PT  │          │
       └────┬─────┘          │
            │ Page Table     │
            │ ┌──────────┐   │
            └→│ PTE      │   │
              │ 物理頁號 │   │
              └────┬─────┘   │
                   │         │
                   └────┬────┘
                        ↓
                   物理位址

Page Directory：1024 個 entry，每個指向一個 Page Table
Page Table：1024 個 entry，每個指向一個 4KB 頁面
Offset：頁面內偏移（4KB = 2^12）

但 entry.S 用 4MB 大頁（PTE_PS）：
  跳過 Page Table 這一級
  Page Directory entry 直接指向 4MB 物理區塊
  簡單，但粒度粗
```

---

## 🔄 entry.S 流程圖

```
bootmain() 跳到這裡
    │  物理位址 ~0x0010000c
    │  分頁未開
    ↓
entry:
    │
    ├─ CR4.PSE = 1     「啟用 4MB 大頁」
    │
    ├─ CR3 = entrypgdir 「告訴 CPU 頁表在哪」
    │
    ├─ CR0.PG = 1       「🎉 開啟分頁！」
    │   ↓
    │   現在執行的指令在虛擬低位址
    │   靠 entrypgdir[0] 映射還能跑
    │
    ├─ ESP = stack + KSTACKSIZE  「設定 kernel stack」
    │
    └─ jmp *main        「跳到高位址 0x8010xxxx」
         ↓               靠 entrypgdir[512] 映射
    main()（下一章！）
```

---

## 💻【實作】觀察 entrypgdir 的效果

用 QEMU monitor 可以直接看頁表：

```bash
# 用 QEMU monitor 模式啟動 xv6
cd ~/xv6-public
make qemu-nox-gdb &

# 另一個 terminal：
# 連接到 QEMU monitor
# (Ctrl-A C 切換到 QEMU monitor)
```

在 QEMU monitor 裡輸入：
```
info mem
```

你會看到類似：
```
0000000000000000-0000000000400000 0000000000400000 -rw
0000000080000000-0000000080400000 0000000000400000 -rw
```

這就是 entrypgdir 的兩個 4MB 映射！

更簡單的觀察方式——看 `entrypgdir` 的定義：

```bash
cd ~/xv6-public
grep -A 5 'entrypgdir\[' main.c
```

---

## 🔑 關鍵概念回顧

| 概念 | 說明 |
|------|------|
| KERNBASE | 0x80000000，kernel 虛擬位址起點 |
| V2P / P2V | 虛擬 ↔ 物理位址轉換巨集 |
| CR3 | 存放頁目錄的物理位址 |
| CR0.PG | 設為 1 → 啟用分頁 |
| CR4.PSE | 啟用 4MB 大頁 |
| entrypgdir | 臨時頁表，映射低位址 + 高位址 |
| _start = V2P_WO(entry) | ELF 進入點用物理位址 |
| 間接 jmp | 避免相對跳轉的位址計算問題 |

---

## ⏭️ 下一步

`entry.S` 把分頁打開了，跳到 `main()`。接下來——

**19 個 init 函式，建好 kernel 的一切基礎設施，然後啟動第一個 user process。**

→ [03_MAIN.md — main()：kernel 初始化](03_MAIN.md)
