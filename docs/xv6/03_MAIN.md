# 🏗️ 03 — main()：Kernel 初始化

> 「main() 就像開餐廳的開店流程：開電、備料、擦桌子、開門迎客。每一步都有順序，跳過一步就會出事。」

---

## 🗺️ main() 全景圖

```
entry.S → jmp main
              │
   ┌──────────┼─────────── 階段 1：記憶體 ──────────────┐
   │  kinit1(end, 4MB)     配置前 4MB 實體記憶體           │
   │  kvmalloc()           建完整頁表（entrypgdir 退役！）  │
   ├──────────┼─────────── 階段 2：硬體 ────────────────┤
   │  mpinit()             偵測多核                       │
   │  lapicinit()          Local APIC（中斷控制器）        │
   │  seginit()            正式 GDT                      │
   │  picinit()            關舊 PIC                      │
   │  ioapicinit()         I/O APIC                     │
   │  consoleinit()        螢幕/鍵盤                     │
   │  uartinit()           Serial port                   │
   ├──────────┼─────────── 階段 3：核心子系統 ───────────┤
   │  pinit()              行程表                        │
   │  tvinit()             IDT（中斷向量）                │
   │  binit()              磁碟 buffer cache             │
   │  fileinit()           檔案表                        │
   │  ideinit()            磁碟驅動                      │
   ├──────────┼─────────── 階段 4：啟動 ────────────────┤
   │  startothers()        啟動其他 CPU                   │
   │  kinit2(4MB, 224MB)   配置剩餘記憶體                  │
   │  userinit()           第一個 user 行程（init）        │
   │  mpmain()             → scheduler()（永不回來）      │
   └───────────────────────────────────────────────────┘
```

---

## 📖 main.c 完整逐行中文註解

```c
#include "types.h"
#include "defs.h"
#include "param.h"
#include "memlayout.h"
#include "mmu.h"
#include "proc.h"
#include "x86.h"

static void startothers(void);
static void mpmain(void) __attribute__((noreturn));
extern pde_t *kpgdir;
extern char end[];   // kernel ELF 結束位置（linker 提供）

int
main(void)
{
  kinit1(end, P2V(4*1024*1024));
  // 📦 初始化記憶體配置器（第一階段）
  // 範圍：kernel 結尾 ~ 4MB
  // 為什麼只到 4MB？因為 entrypgdir 只映射了 4MB！

  kvmalloc();
  // 🗺️ 建完整 kernel 頁表 → 取代 entrypgdir
  // 之後能存取所有實體記憶體

  mpinit();        // 🔍 偵測多核（讀 BIOS MP 表）
  lapicinit();     // 📡 初始化 Local APIC
  seginit();       // 📐 正式 GDT（kernel+user code/data + TSS）
  picinit();       // 🚫 關閉 8259 PIC（用 APIC 取代）
  ioapicinit();    // 📡 I/O APIC（硬體中斷路由）
  consoleinit();   // 🖥️ 螢幕/鍵盤
  uartinit();      // 🔌 Serial port（QEMU -nographic 輸出）
  pinit();         // 📋 行程表鎖（NPROC = 64）
  tvinit();        // 🚨 IDT 256 個中斷向量
  binit();         // 💾 磁碟 buffer cache（LRU）
  fileinit();      // 📁 檔案表鎖（NFILE = 100）
  ideinit();       // 💿 IDE 磁碟驅動
  startothers();   // 🚀 啟動其他 CPU

  kinit2(P2V(4*1024*1024), P2V(PHYSTOP));
  // 📦 初始化記憶體配置器（第二階段）
  // 範圍：4MB ~ PHYSTOP(224MB)
  // 要在 startothers() 之後（它用了低位記憶體）
  // 要在 kvmalloc() 之後（需要完整頁表才能碰 >4MB）

  userinit();
  // 👶 第一個 user 行程！
  // → allocproc() 配置 proc 結構
  // → setupkvm() 建立行程頁表
  // → inituvm() 複製 initcode.S 到虛擬地址 0
  // → initcode.S 會 exec("/init")
  // → init.c 會 fork() + exec("sh")
  // → 你看到 $ 提示字元！

  mpmain();
  // 🔄 進入 scheduler()，永不回來
}

static void mpmain(void) {
  cprintf("cpu%d: starting %d\n", cpuid(), cpuid());
  idtinit();                          // 載入 IDT
  xchg(&(mycpu()->started), 1);       // 告訴 BSP：我啟動了
  scheduler();                        // 無限迴圈，找 RUNNABLE 行程
}
```

---

## 🔑 為什麼 kinit 分兩階段？

```
比喻：發便當
  kinit1 = 先發前排（前 4MB，因為只看得到這裡）
  kvmalloc = 裝望遠鏡（完整頁表）
  kinit2 = 發後排（4MB ~ 224MB）

         entrypgdir 時期        kvmalloc 之後
         只映射 4MB            映射到 PHYSTOP
  0MB   ┌────────────┐      ┌────────────┐
        │ kernel code│      │ kernel code│
  end   │░░░░░░░░░░░░│      │████ kinit1 │
  4MB   │────────────│      │────────────│
        │  看不到！   │      │████ kinit2 │
  224MB │            │      │────────────│
        └────────────┘      └────────────┘
```

---

## 💻【實作】在 main() 加 cprintf

編輯 `~/xv6-public/main.c`，每個函式前加 `cprintf(">>> xxx\n");`

```bash
cd ~/xv6-public
# 加上 cprintf 後：
make clean && make && make qemu-nox CPUS=1
```

你會看到每個初始化步驟依序印出來，最後出現 `$`。

記得還原：`git checkout main.c`

---

## 🧠 本章小結

| 階段 | 做什麼 | 比喻 |
|------|--------|------|
| 記憶體 | kinit1 + kvmalloc | 開電 + 裝望遠鏡 |
| 硬體 | mp/lapic/seg/pic/ioapic/console/uart | 備料、擦桌子 |
| 子系統 | pinit/tvinit/binit/fileinit/ideinit | 準備各部門 |
| 啟動 | startothers + kinit2 + userinit + scheduler | 叫員工來 + 開門營業！ |

➡️ [04 記憶體：x86 二級頁表](04_MEMORY.md)
