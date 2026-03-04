# 📚 03 — main()：kernel 初始化

> 19 道菜的套餐，順序不能亂，少一道就開天窗。

---

## 🍽️ 初始化：為什麼順序重要？

`main()` 要初始化整個 kernel。這些步驟有 **相依關係**：

```
頁表需要物理頁面           → kinit1 要在 kvmalloc 之前
偵測多核需要記憶體         → kinit1 要在 mpinit 之前
中斷處理需要 LAPIC         → lapicinit 要在 ioapicinit 之前
其他 CPU 需要 kernel 頁表  → kvmalloc 要在 startothers 之前
第一個行程需要所有東西     → userinit 要最後才跑
```

**比喻：** 就像蓋一棟大樓——你得先打地基（記憶體），再蓋結構（頁表），再裝水電（中斷），再隔間（行程表），最後才能讓住戶入住（userinit）。

---

## 📄 `main.c`：完整中文註解

```c
// 檔案：main.c
// 功能：kernel 初始化
// entry.S 跳到這裡，此時分頁已開，在高位址執行

int
main(void)
{
  // ====================================================
  // 第一階段：記憶體 + 頁表
  // ====================================================

  kinit1(end, P2V(4*1024*1024));
  // 初始化物理頁面分配器（第一階段）
  // 只管 kernel 結尾 ~ 4MB 的記憶體
  // 為什麼只管 4MB？因為現在用的 entrypgdir 只映射了 4MB！
  // 4MB 以上的記憶體，等建好新頁表後再加入（kinit2）
  //
  // end = kernel 的 BSS 段結尾（linker 產生的符號）
  // 從 end 到 4MB 之間的頁面，加入 free list

  kvmalloc();
  // 建立完整的 kernel 頁表 + 切換過去！
  // 取代 entrypgdir → 映射所有物理記憶體
  // 之後 entrypgdir 的低位址映射就沒了
  // （所以之前必須跳到高位址的 main() 才安全）

  // ====================================================
  // 第二階段：硬體偵測 + 中斷
  // ====================================================

  mpinit();
  // 偵測多處理器（Multi-Processor）
  // 透過 MP Configuration Table 找到有幾個 CPU
  // 這是 Intel 的古老規格，存在 BIOS 記憶體區域

  lapicinit();
  // 初始化 Local APIC（每個 CPU 一個）
  // APIC = Advanced Programmable Interrupt Controller
  // 用來接收和傳送中斷

  seginit();
  // 設定每個 CPU 的 GDT！
  // 🔥 這裡有 DPL 的設定：
  //   SEG_KCODE: DPL=0（kernel code）
  //   SEG_KDATA: DPL=0（kernel data）
  //   SEG_UCODE: DPL=3（user code）← Ring 3！
  //   SEG_UDATA: DPL=3（user data）← Ring 3！
  //   SEG_TSS:   （task state segment）
  //
  // 這就是 x86 特權等級的核心——
  // 什麼程式碼在 Ring 0，什麼在 Ring 3，全看 GDT 裡的 DPL

  picinit();
  // 停用舊的 8259A PIC（Programmable Interrupt Controller）
  // 我們用更新的 IOAPIC

  ioapicinit();
  // 初始化 I/O APIC
  // 負責把外部設備中斷（鍵盤、磁碟）分配給 CPU

  // ====================================================
  // 第三階段：Console + 周邊設備
  // ====================================================

  consoleinit();
  // 初始化 console（VGA + 鍵盤）
  // 之後 cprintf 才能印東西到螢幕

  uartinit();
  // 初始化串列埠（serial port）
  // QEMU 的 -nographic 模式用串列埠做 I/O

  // ====================================================
  // 第四階段：行程 + Trap + 檔案系統
  // ====================================================

  pinit();
  // 初始化行程表的鎖（ptable.lock）

  tvinit();
  // 初始化 trap 向量（IDT = Interrupt Descriptor Table）
  // 設定 256 個中斷向量 entry
  // 🔥 系統呼叫（T_SYSCALL = 64 = 0x40）的 DPL 設為 3
  //    → User 程式（Ring 3）可以觸發 int 0x40
  //    → 其他中斷的 DPL = 0，User 不能直接觸發

  binit();
  // 初始化磁碟 buffer cache
  // 磁碟讀寫的快取層，用 LRU 策略

  fileinit();
  // 初始化全域檔案表（ftable）
  // 系統所有開啟的檔案都在這裡

  ideinit();
  // 初始化 IDE 磁碟驅動
  // 設定磁碟中斷（IRQ 14）

  // ====================================================
  // 第五階段：啟動其他 CPU + 更多記憶體
  // ====================================================

  startothers();
  // 啟動其他 CPU！
  // 把 entryother.S 的程式碼複製到 0x7000
  // 用 LAPIC 送 INIT + STARTUP IPI 喚醒每個 AP（Application Processor）
  // 每個 AP 會跑 entryother.S → mpenter() → mpmain()

  kinit2(P2V(4*1024*1024), P2V(PHYSTOP));
  // 物理頁面分配器第二階段
  // 把 4MB ~ PHYSTOP（224MB）的記憶體加入 free list
  // 為什麼要分兩階段？
  // kinit1 時只有 entrypgdir（4MB 映射）
  // kinit2 時已有完整頁表，可以管理所有記憶體
  // 而且必須在 startothers() 之後
  // 因為 AP 需要用 entrypgdir（它映射了低位址）

  userinit();
  // 建立第一個 user 行程！（亞當！）
  // 這個行程執行 initcode.S
  // initcode 呼叫 exec("/init")
  // init 開啟 console、fork、exec("/sh")
  // → 你看到 $ 了！

  mpmain();
  // 不會返回！
}
```

---

## 🔀 `mpmain()`：每個 CPU 的最後設定

```c
static void
mpmain(void)
{
  cprintf("cpu%d: starting %d\n", cpuid(), cpuid());

  idtinit();
  // 載入 IDT（lidt 指令）
  // 每個 CPU 都要自己載入一次
  // IDT 內容是共享的，但 IDTR 暫存器是每個 CPU 各自的

  xchg(&(mycpu()->started), 1);
  // 原子操作：告訴主 CPU「我好了！」
  // startothers() 在等這個旗標

  scheduler();
  // 開始排程！永遠不返回
  // 不斷從行程表找 RUNNABLE 的行程來跑
}
```

---

## 🗺️ 初始化順序圖

```
main()（CPU 0，BSP = Bootstrap Processor）
    │
    │ 📦 記憶體 + 頁表
    ├─ kinit1()       「先管 4MB 以內的記憶體」
    ├─ kvmalloc()     「建立完整頁表，取代 entrypgdir」
    │
    │ 🔌 硬體偵測
    ├─ mpinit()       「偵測有幾個 CPU」
    ├─ lapicinit()    「初始化本地中斷控制器」
    ├─ seginit()      「設定 GDT（DPL=0/3！）」
    ├─ picinit()      「停用舊 PIC」
    ├─ ioapicinit()   「初始化 I/O 中斷控制器」
    │
    │ 🖥️ Console
    ├─ consoleinit()  「螢幕 + 鍵盤」
    ├─ uartinit()     「串列埠」
    │
    │ ⚙️ 行程 + Trap + FS
    ├─ pinit()        「行程表鎖」
    ├─ tvinit()       「IDT — 256 個中斷向量」
    ├─ binit()        「磁碟快取」
    ├─ fileinit()     「檔案表」
    ├─ ideinit()      「磁碟驅動」
    │
    │ 🚀 啟動其他 CPU + 完成
    ├─ startothers()  「喚醒其他 CPU」
    │                   │
    │                   │  CPU 1, 2...
    │                   │  entryother.S → mpenter()
    │                   │  → switchkvm, seginit, lapicinit
    │                   └─→ mpmain() → scheduler()
    │
    ├─ kinit2()       「加入剩餘記憶體（4MB ~ 224MB）」
    ├─ userinit()     「建立第一個行程！」
    └─ mpmain()       「載入 IDT → scheduler()」
```

---

## 👶 `userinit()`：第一個行程的誕生

```
userinit()
    │
    ├─ allocproc()          分配 proc 結構 + kernel stack
    │
    ├─ setupkvm()           建立 user 頁表（包含 kernel 映射）
    │
    ├─ inituvm()            把 initcode 複製到 user 空間第一頁
    │                       虛擬位址 0x0
    │
    ├─ 設定 trapframe:
    │   tf->cs = (SEG_UCODE<<3) | DPL_USER    ← CS 的 RPL = 3！
    │   tf->ds = (SEG_UDATA<<3) | DPL_USER    ← DS 的 RPL = 3！
    │   tf->eflags = FL_IF                      ← 啟用中斷
    │   tf->esp = PGSIZE                        ← user stack
    │   tf->eip = 0                             ← 從 initcode 開始
    │
    │   🔥 注意 DPL_USER = 3！
    │   當這個行程開始跑時，CS = Ring 3，DS = Ring 3
    │   → 這是一個 user mode 行程！
    │
    └─ p->state = RUNNABLE    交給 scheduler

initcode.S 做什麼？
    │
    │  # exec(init, argv)
    │  pushl $argv
    │  pushl $init     # "/init"
    │  pushl $0        # 假的 return addr
    │  movl $SYS_exec, %eax
    │  int $T_SYSCALL  # int 0x40 → 系統呼叫！
    │
    └→ /init 程式
        ├─ open("console", O_RDWR)   → fd 0 (stdin)
        ├─ dup(0)                     → fd 1 (stdout)
        ├─ dup(0)                     → fd 2 (stderr)
        ├─ fork()
        └─ exec("/sh")               → Shell 啟動！
```

---

## 🔄 完整開機流程（Ch.01 ~ Ch.03）

```
BIOS
  ↓
bootasm.S（Real Mode → Protected Mode）        Ch.01
  ↓
bootmain.c（載入 kernel ELF）                   Ch.01
  ↓
entry.S（開啟分頁，跳高位址）                     Ch.02
  ↓
main()（19 個 init）                             Ch.03
  ↓
scheduler()
  ↓
initcode（int 0x40 → exec("/init")）
  ↓
/init → fork → exec("/sh")
  ↓
$  █   ← 你看到的 shell 提示符！
```

---

## 💻【實作】修改 xv6，加一行自己的訊息

### 步驟

1. 編輯 `~/xv6-public/main.c`，在 `mpmain()` 的 `cprintf` 後加一行：

```c
static void
mpmain(void)
{
  cprintf("cpu%d: starting %d\n", cpuid(), cpuid());
  if(cpuid() == 0)
    cprintf("=== Welcome to MY xv6! ===\n");  // 加這行
```

2. 重新編譯並執行：

```bash
cd ~/xv6-guide
make run
```

3. 你應該會看到：

```
xv6...
cpu0: starting 0
=== Welcome to MY xv6! ===
cpu1: starting 1
...
init: starting sh
$
```

### 試試看

在 `$` 提示符下：

```
$ ls          # 列出檔案
$ cat README  # 讀取 README
$ echo hello  # 印出 hello
$ wc README   # 字數統計
```

按 `Ctrl-A X` 離開 QEMU。

---

## 🔑 關鍵概念回顧

| 概念 | 說明 |
|------|------|
| kinit1 / kinit2 | 兩階段記憶體初始化（因為頁表尚未完整） |
| kvmalloc | 建立完整 kernel 頁表，取代 entrypgdir |
| seginit | 設定 GDT，包含 DPL=0（kernel）和 DPL=3（user） |
| tvinit | 設定 IDT，int 0x40 的 DPL=3（user 可觸發） |
| startothers | 用 LAPIC IPI 喚醒其他 CPU |
| userinit | 建立第一個 user 行程（Ring 3！） |
| initcode | 第一個 user 程式，呼叫 exec("/init") |
| scheduler | 排程器，永遠不返回 |

---

## ⏭️ 下一步

`kvmalloc()` 建立了完整的 kernel 頁表。但 x86 的二級頁表到底怎麼運作？user 行程的頁表又是怎麼設定的？

**1024 × 1024 × 4KB = 4GB——用兩層索引映射整個位址空間。**

→ [04_MEMORY.md — 虛擬記憶體與 x86 二級頁表](04_MEMORY.md)
