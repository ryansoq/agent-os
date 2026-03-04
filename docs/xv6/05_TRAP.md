# 📚 05 — Trap 機制：中斷與系統呼叫

> 「Ring 3 的你想進 Ring 0 的門？只有一個合法入口：`int` 指令。其他方式？CPU 直接報警。」

---

## 🏢 回顧：CPL / DPL / RPL（門禁系統）

上一章（[05_PRIVILEGE.md](05_PRIVILEGE.md)）詳細解釋了三個權限等級。這裡快速回顧，然後聚焦在 **Trap 的完整流程**。

```
CPL = 你的身份證等級（CS 的低 2 位）
      0 = 總經理（kernel）
      3 = 訪客（user）

DPL = 這扇門要求的等級（IDT/GDT entry 裡）
      IDT[64].DPL = 3 → 訪客也能按這個門鈴（syscall！）
      IDT[13].DPL = 0 → 只有總經理能按（#GP handler）

RPL = 通行證上的等級（selector 低 2 位）
      防止 kernel 被騙去幫 user 做壞事

門禁檢查（int 指令）：CPL <= Gate DPL → ✅ 放行
```

本章的重點：**Trap 發生時，CPU 和 xv6 分別做了什麼？**

---

## 🎯 什麼是 Trap？

Trap 是 CPU 從 user mode 切到 kernel mode 的統一機制，有三種觸發方式：

```
┌──────────────┬────────────────────────┬───────────────────┐
│ 類型          │ 觸發方式               │ 例子               │
├──────────────┼────────────────────────┼───────────────────┤
│ 中斷         │ 硬體觸發（非同步）      │ Timer、鍵盤、磁碟  │
│ (Interrupt)  │ 任何時候都可能發生      │                   │
├──────────────┼────────────────────────┼───────────────────┤
│ 例外         │ CPU 執行指令時出錯      │ Page Fault、#GP   │
│ (Exception)  │ 同步（確定性的）        │ 除以零             │
├──────────────┼────────────────────────┼───────────────────┤
│ 系統呼叫     │ 程式故意用 int 指令     │ int $0x40          │
│ (Syscall)    │ 合法的 user→kernel 請求 │ (xv6 的 syscall)  │
└──────────────┴────────────────────────┴───────────────────┘
```

不管哪種，CPU 做的事情是一樣的：查 IDT → 切 stack → 跳到 handler。

---

## 📄 IDT：256 個中斷門

IDT（Interrupt Descriptor Table）是一張 256 個 entry 的表，每個 entry 告訴 CPU：
「發生第 N 號 trap 時，跳到哪裡、用什麼權限。」

### Gate Descriptor 的結構

```
IDT Entry（Gate Descriptor，8 bytes）：
┌─────────────────────┬──┬─────┬──────┬─────────────────────┐
│ Handler offset 高16  │ P│ DPL │ Type │ Handler offset 低16  │
│                     │  │     │      │                     │
│ bits 31-16          │  │ 2位 │ 4位  │ bits 15-0           │
└─────────────────────┴──┴─────┴──────┴─────────────────────┘
                            ↑      ↑
                            │      │
                     誰能用 int    Interrupt Gate (0xE)
                     觸發這個      或 Trap Gate (0xF)
                     中斷？        差別：IF 旗標

DPL 的意義（對 IDT 而言）：
  DPL = 0 → 只有 CPL=0（kernel）能用 int 指令觸發
           硬體中斷不受此限制！Timer 中斷 DPL=0 但仍能打斷 user
  DPL = 3 → CPL=3（user）也能用 int 指令觸發
           xv6 只有 int 64（T_SYSCALL）設成 DPL=3
```

### Interrupt Gate vs Trap Gate

```
Interrupt Gate（type = 0xE）：
  進入 handler 時 CPU 自動關閉中斷（IF = 0）
  → 不會被其他中斷打斷
  → xv6 大多數中斷用這個

Trap Gate（type = 0xF）：
  進入 handler 時 CPU 不改 IF
  → 可以被其他中斷打斷
  → xv6 的 T_SYSCALL 用這個（syscall 執行時允許中斷）
```

---

## 📄 `tvinit()`：設定 IDT

```c
// trap.c

struct gatedesc idt[256];     // 256 個 gate descriptor
extern uint vectors[];         // vectors.S 產生的 256 個入口地址

void
tvinit(void)
{
  int i;

  // 預設：所有中斷都是 Interrupt Gate，DPL = 0
  for(i = 0; i < 256; i++)
    SETGATE(idt[i], 0, SEG_KCODE<<3, vectors[i], 0);
  //               ↑  ↑              ↑            ↑
  //               │  │              │            DPL = 0（只有 kernel）
  //               │  │              handler 地址
  //               │  目標 segment = kernel code（0x08）
  //               type = 0 → Interrupt Gate

  // 唯一例外：T_SYSCALL（64）用 Trap Gate，DPL = 3
  SETGATE(idt[T_SYSCALL], 1, SEG_KCODE<<3, vectors[T_SYSCALL], DPL_USER);
  //                      ↑                                    ↑
  //                      type = 1 → Trap Gate                DPL = 3（user 可以！）
  //                      （進入時不關中斷）

  initlock(&tickslock, "time");
}
```

```
IDT 全景圖（xv6）：

 中斷號  │ DPL │ Type           │ 用途
─────────┼─────┼────────────────┼──────────────────
    0    │  0  │ Interrupt Gate │ 除以零
    6    │  0  │ Interrupt Gate │ Invalid Opcode
   13    │  0  │ Interrupt Gate │ General Protection Fault
   14    │  0  │ Interrupt Gate │ Page Fault
   32    │  0  │ Interrupt Gate │ Timer（硬體觸發，不看 DPL）
   33    │  0  │ Interrupt Gate │ Keyboard
   46    │  0  │ Interrupt Gate │ IDE Disk
   ⭐64  │  3  │ Trap Gate      │ T_SYSCALL（user 可觸發！）
  其他   │  0  │ Interrupt Gate │ 各種例外/保留

⚠️ 只有 int 指令才檢查 DPL
   硬體中斷（timer、keyboard）直接觸發，不管 DPL
   所以 timer 可以打斷 Ring 3 的程式，即使 DPL=0
```

---

## 🔑 Trap 發生時 CPU 自動做的事（最關鍵！）

當 `int $0x40` 從 Ring 3 觸發時，CPU **硬體**自動做以下步驟：

```
┌─────────────────────────────────────────────────────────┐
│ CPU 硬體自動完成（不是軟體！）                            │
│                                                         │
│ 1. 權限檢查                                              │
│    CPL(3) <= IDT[64].DPL(3) → ✅ 允許                   │
│                                                         │
│ 2. 從 TSS 載入 kernel stack                              │
│    SS  = TSS.ss0  = 0x10（kernel data segment）          │
│    ESP = TSS.esp0 = proc->kstack + KSTACKSIZE           │
│    → 現在用 kernel 的堆疊了！                             │
│                                                         │
│ 3. 在 kernel stack 上 push 5 個值：                       │
│    ┌──────────────┐ ← ESP（往下長）                      │
│    │ old SS       │    user 的 SS（0x23）                │
│    │ old ESP      │    user 的堆疊指標                   │
│    │ old EFLAGS   │    包含 IF 旗標等                    │
│    │ old CS       │    user 的 CS（0x1B）← RPL=3        │
│    │ old EIP      │    int 指令的下一條指令              │
│    └──────────────┘                                      │
│                                                         │
│ 4. 設定新的 CS 和 EIP                                    │
│    CS  = IDT[64].selector = 0x08（kernel code segment）  │
│    → CPL 變成 0！現在是 Ring 0 了！                       │
│    EIP = vectors[64] 的地址                              │
│    → 跳到 vector64 開始執行                              │
│                                                         │
│ 5.（Interrupt Gate）清除 IF → 關閉中斷                    │
│   （Trap Gate）不動 IF → 中斷保持開啟                     │
└─────────────────────────────────────────────────────────┘
```

### 為什麼要切 stack？

```
❌ 如果不切 stack（繼續用 user stack）：

  問題 1：安全性
    惡意 user 可以把 ESP 設成不合法的地址
    → kernel 的 push 操作寫到不該寫的地方 → 系統崩潰

  問題 2：隔離性
    kernel 在 user stack 上存資料
    → user 回去後可以看到 kernel 的暫存器值
    → 洩漏 kernel 資訊

  問題 3：可靠性
    user 的 stack 可能已經溢出
    → 根本沒有空間給 kernel 用

✅ 切到 kernel stack：
    每個行程有獨立的 kernel stack（4KB）
    由 kernel 自己分配，user 碰不到
    安全、可靠、隔離
```

---

## 📄 `trapasm.S`：完整中文註解

CPU 硬體把我們送到 `vectors[N]`，然後是 `alltraps`，最後呼叫 `trap()`：

```asm
#include "mmu.h"

  # vectors.S 的每個 entry 會 push trapno，然後跳到這裡
  # 此時 stack 上已經有：
  #   （CPU 自動 push 的）SS, ESP, EFLAGS, CS, EIP
  #   （vectors.S push 的）error code（有些中斷沒有，vectors.S 補 0）
  #   （vectors.S push 的）trapno
  
.globl alltraps
alltraps:
  # ========================================
  # 建立 trapframe（保存所有暫存器）
  # ========================================
  pushl %ds               # 保存 data segment
  pushl %es               # 保存 extra segment
  pushl %fs
  pushl %gs
  pushal                  # push EAX ECX EDX EBX ESP EBP ESI EDI
                          # → 一口氣 push 8 個通用暫存器
  
  # ========================================
  # 切換到 kernel 的 data segment
  # ========================================
  # 雖然 CS 已經是 kernel code，但 DS/ES 還是 user 的（0x23）
  # 需要手動切到 kernel data segment（0x10）才能存取 kernel 資料
  movw $(SEG_KDATA<<3), %ax    # AX = 0x10
  movw %ax, %ds                # DS = kernel data
  movw %ax, %es                # ES = kernel data

  # ========================================
  # 呼叫 trap(tf)
  # ========================================
  # 此時 ESP 指向 struct trapframe 的開頭
  # 把 ESP 當作參數傳給 trap()
  pushl %esp             # 參數：trapframe 的地址
  call trap              # trap(tf) → 在 trap.c 裡
  addl $4, %esp          # 清掉參數

  # ========================================
  # 返回！（從 trap 回來，或是 forkret/userinit 跳到 trapret）
  # ========================================
.globl trapret
trapret:
  popal                  # 恢復 8 個通用暫存器
  popl %gs               # 恢復段暫存器
  popl %fs
  popl %es
  popl %ds
  addl $0x8, %esp        # 跳過 trapno 和 error code（不需要 pop）
  iret                   # 🔑 CPU 從 stack pop EIP, CS, EFLAGS
                         # 如果 CS.RPL != 當前 CPL → 還會 pop SS, ESP
                         # → 切回 user stack，CPL 變回 3！
```

### Kernel Stack 上 trapframe 的完整佈局

```
kernel stack（由高位址往低位址成長）：

                    ┌──────────────┐ ← TSS.esp0（kernel stack 頂端）
                    │    old SS    │ ┐
                    │    old ESP   │ │ CPU 自動 push
                    │   old EFLAGS │ │ （只在跨 Ring 時）
                    │    old CS    │ │
                    │    old EIP   │ ┘
                    ├──────────────┤
                    │   err code   │ ┐ vectors.S push
                    │    trapno    │ ┘
                    ├──────────────┤
                    │      ds      │ ┐
                    │      es      │ │ alltraps push
                    │      fs      │ │
                    │      gs      │ ┘
                    ├──────────────┤
                    │     edi      │ ┐
                    │     esi      │ │
                    │     ebp      │ │ pushal
                    │   (esp 佔位) │ │ （ESP 的值不有意義）
                    │     ebx      │ │
                    │     edx      │ │
                    │     ecx      │ │
                    │     eax      │ ┘
                    └──────────────┘ ← ESP = struct trapframe *tf

這整個結構就是 struct trapframe（定義在 x86.h）！
trap(tf) 可以透過 tf->eax、tf->cs、tf->eip 等存取所有暫存器
```

---

## 📄 `trap.c`：分辨 trap 類型

```c
void
trap(struct trapframe *tf)
{
  // ========================================
  // 1. Syscall？
  // ========================================
  if(tf->trapno == T_SYSCALL){
    // trapno == 64 → user 用 int $0x40 觸發的系統呼叫
    if(myproc()->killed)
      exit();
    myproc()->tf = tf;    // 記錄 trapframe，syscall 函數需要讀參數
    syscall();            // → 查 syscall 表，執行對應的函數
    if(myproc()->killed)
      exit();
    return;               // 回到 alltraps → trapret → iret → user
  }

  // ========================================
  // 2. 硬體中斷？
  // ========================================
  switch(tf->trapno){
  case T_IRQ0 + IRQ_TIMER:      // 32: Timer 中斷
    if(cpuid() == 0){
      acquire(&tickslock);
      ticks++;                   // 增加系統時鐘
      wakeup(&ticks);            // 喚醒在等 sleep(ticks) 的行程
      release(&tickslock);
    }
    lapiceoi();                  // 告訴 LAPIC：中斷處理完了
    break;

  case T_IRQ0 + IRQ_IDE:        // 46: 磁碟中斷
    ideintr();
    lapiceoi();
    break;

  case T_IRQ0 + IRQ_KBD:        // 33: 鍵盤中斷
    kbdintr();
    lapiceoi();
    break;

  case T_IRQ0 + IRQ_COM1:       // 36: 串口中斷
    uartintr();
    lapiceoi();
    break;

  // ========================================
  // 3. 不認識的 trap → fault!
  // ========================================
  default:
    if(myproc() == 0 || (tf->cs&3) == 0){
      // 在 kernel 裡出事 → 這是 kernel 的 bug → panic!
      cprintf("unexpected trap %d from cpu %d eip %x (cr2=0x%x)\n",
              tf->trapno, cpuid(), tf->eip, rcr2());
      panic("trap");
    }
    // 在 user space 出事 → 殺掉行程
    //   tf->cs & 3 → 取出 CPL（CS 的低 2 位）
    //   如果是 3 → user mode 的 fault
    cprintf("pid %d %s: trap %d err %d on cpu %d "
            "eip 0x%x addr 0x%x--kill proc\n",
            myproc()->pid, myproc()->name, tf->trapno,
            tf->err, cpuid(), tf->eip, rcr2());
    myproc()->killed = 1;  // 標記要殺掉
  }

  // ========================================
  // 4. Timer 搶佔：user 跑太久就讓出 CPU
  // ========================================
  if(myproc() && myproc()->state == RUNNING &&
     tf->trapno == T_IRQ0+IRQ_TIMER)
    yield();    // 讓出 CPU → scheduler 選下一個行程
}
```

```
trap() 的決策樹：

trap(tf)
  │
  ├─ trapno == 64？ → syscall() → 回到 user
  │
  ├─ trapno == 32？ → timer → ticks++ → maybe yield()
  │
  ├─ trapno == 33？ → keyboard → kbdintr()
  │
  ├─ trapno == 46？ → disk → ideintr()
  │
  └─ 其他？
      ├─ 在 kernel（CS&3==0）？ → panic（kernel bug）
      └─ 在 user（CS&3==3）？  → kill proc（user 的錯）
```

---

## 📄 TSS：告訴 CPU kernel stack 在哪

TSS（Task State Segment）存了 Ring 0 的 SS 和 ESP。
當 CPU 從 Ring 3 → Ring 0 時，自動從 TSS 載入這兩個值。

```c
// vm.c — switchuvm()
void
switchuvm(struct proc *p)
{
  // ...

  // 設定 TSS
  mycpu()->gdt[SEG_TSS] = SEG16(STS_T32A, &mycpu()->ts,
                                sizeof(mycpu()->ts)-1, 0);
  mycpu()->gdt[SEG_TSS].s = 0;   // s=0 表示這是 system segment

  mycpu()->ts.ss0 = SEG_KDATA << 3;     // Ring 0 的 SS = 0x10
  mycpu()->ts.esp0 = (uint)p->kstack + KSTACKSIZE;
  //                                      ↑
  //                         每個行程的 kernel stack 頂端
  //                         int 進來時 CPU 自動把 ESP 設成這個值

  mycpu()->ts.iomb = (ushort) 0xFFFF;  // 禁止 user 的 I/O 指令

  ltr(SEG_TSS << 3);       // 載入 TSS register → 告訴 CPU TSS 在哪
  lcr3(V2P(p->pgdir));     // 切到這個行程的頁表
}
```

```
TSS 的作用：

User 程式在 Ring 3 快樂地跑
  │
  │ int $0x40（或 timer 中斷）
  │
  ▼
CPU：「要切到 Ring 0！Ring 0 的 stack 在哪？」
  │
  │ 查 TSS → ss0 = 0x10, esp0 = 行程的 kstack 頂端
  │
  ▼
CPU：SS = 0x10, ESP = kstack + KSTACKSIZE
     push 舊的 SS, ESP, EFLAGS, CS, EIP
     開始跑 handler

每次 scheduler 切換行程時，switchuvm() 會更新 TSS.esp0
→ 確保 CPU 總是切到正確行程的 kernel stack
```

---

## 🔄 完整的 Syscall 流程（從頭到尾）

```
User 程式（CPL=3）
    │
    │ getpid() 展開成：
    │   mov $SYS_getpid, %eax     # syscall 號碼放 EAX
    │   int $0x40                  # 觸發中斷 64
    │
    ▼ ═══════ CPU 硬體 ═══════════════════════════════
    │
    │ 1. CPL(3) <= IDT[64].DPL(3) → ✅ 允許
    │ 2. 從 TSS 載入 kernel SS:ESP → 切到 kernel stack
    │ 3. push: SS, ESP, EFLAGS, CS, EIP
    │ 4. CS = 0x08 → CPL = 0（Ring 0！）
    │ 5. EIP = vectors[64]
    │
    ▼ ═══════ vectors.S ═════════════════════════════
    │
    │ vector64:
    │   pushl $0          # 假的 error code（統一格式）
    │   pushl $64         # trapno = 64
    │   jmp alltraps
    │
    ▼ ═══════ trapasm.S（alltraps）══════════════════
    │
    │ push ds, es, fs, gs     # 保存段暫存器
    │ pushal                  # 保存通用暫存器
    │ DS = ES = 0x10          # 切到 kernel data segment
    │ push %esp               # 參數 = trapframe 地址
    │ call trap
    │
    ▼ ═══════ trap.c ════════════════════════════════
    │
    │ trap(tf):
    │   tf->trapno == T_SYSCALL（64）→ ✅
    │   syscall()
    │     → 從 tf->eax 取出 syscall 號碼
    │     → 呼叫對應函數（sys_getpid）
    │     → 結果放回 tf->eax
    │   return
    │
    ▼ ═══════ trapasm.S（trapret）═══════════════════
    │
    │ popal                   # 恢復通用暫存器（包含 eax = 結果）
    │ pop gs, fs, es, ds      # 恢復段暫存器
    │ add $8, %esp            # 跳過 trapno + errcode
    │ iret                    # 🔑 返回！
    │
    ▼ ═══════ CPU 硬體（iret）══════════════════════
    │
    │ 1. pop EIP, CS, EFLAGS
    │ 2. CS = 0x1B → RPL = 3 → CPL 變回 3！
    │ 3. CPL 變了 → 再 pop SS, ESP（切回 user stack）
    │
    ▼ ═══════ 回到 User（CPL=3）═════════════════════
    │
    │ EAX 裡有 PID → getpid() 回傳
    │
    ▼
    程式繼續跑 ✅
```

---

## 💻【實作】觀察 Trap 的過程

### 實驗 1：在 trap.c 加 log

修改 `trap.c` 來觀察每個 trap：

```c
// 在 trap() 函數開頭加上：
void
trap(struct trapframe *tf)
{
  // 🔍 Debug: 印出每個 trap 的資訊
  if(tf->trapno == T_SYSCALL) {
    cprintf("[TRAP] syscall from pid %d, eax=%d (CS=0x%x CPL=%d)\n",
            myproc()->pid, tf->eax, tf->cs, tf->cs & 3);
  } else if(tf->trapno != T_IRQ0 + IRQ_TIMER) {
    // 不印 timer（太頻繁了）
    cprintf("[TRAP] trapno=%d from CS=0x%x (CPL=%d)\n",
            tf->trapno, tf->cs, tf->cs & 3);
  }

  // ... 原本的 trap 程式碼 ...
```

```bash
cd ~/xv6-public
# 修改 trap.c 加上 debug log
make clean && make && make qemu-nox CPUS=1
```

你會看到大量的 syscall log：
```
[TRAP] syscall from pid 2, eax=7 (CS=0x1b CPL=3)
[TRAP] syscall from pid 2, eax=16 (CS=0x1b CPL=3)
```

注意 **CS=0x1B**：
- 0x1B = 0001_1011
- 低 2 位 = 11 = 3 → **CPL=3**（user mode）
- 高 13 位 = 3 → GDT entry #3 = SEG_UCODE

確認了：syscall 確實是從 Ring 3 來的！

### 實驗 2：clitest 和 syscalltest

（詳細程式碼在 [05_PRIVILEGE.md](05_PRIVILEGE.md) 的實作區段）

```bash
# 在 xv6 shell 裡：
$ syscalltest
我現在是 Ring 3 (user mode)
透過 syscall 請 kernel 幫忙取得 PID...
[TRAP] syscall from pid 3, eax=11 (CS=0x1b CPL=3)
成功！我的 PID = 3

$ clitest
我現在是 Ring 3 (user mode)
嘗試執行 cli（關中斷）...
[TRAP] trapno=13 from CS=0x1b (CPL=3)    ← #GP！
pid 4 clitest: trap 13 err 0 on cpu 0 eip 0x...--kill proc
```

**trap 13 = General Protection Fault**：Ring 3 執行 `cli` → CPU 檢查 CPL ≠ 0 → 觸發 #GP → kernel 殺掉行程。

---

## 📄 `vectors.S`：256 個入口

`vectors.S` 是用 `vectors.pl` 腳本自動產生的，每個中斷一個 entry：

```asm
# 自動產生的，長這樣：

# 有些中斷 CPU 會自動 push error code（如 #GP, #PF）
# 有些不會，所以我們手動 push 0 來統一格式

.globl vector0
vector0:
  pushl $0        # 假的 error code（除法錯誤沒有 error code）
  pushl $0        # trapno = 0
  jmp alltraps

.globl vector13
vector13:
  # CPU 已經自動 push 了 error code！不用再 push
  pushl $13       # trapno = 13（General Protection Fault）
  jmp alltraps

.globl vector64
vector64:
  pushl $0        # 假的 error code
  pushl $64       # trapno = 64（T_SYSCALL）
  jmp alltraps
```

---

## 🧠 本章小結

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  Trap = 中斷 + 例外 + 系統呼叫 的統一機制                    │
│                                                              │
│  IDT：256 個 gate，記錄 handler 地址 + DPL                   │
│    DPL=0 → 只有 kernel（或硬體）能觸發                       │
│    DPL=3 → user 也能用 int 觸發（syscall！）                 │
│                                                              │
│  CPU 硬體（int 時）自動做：                                   │
│    1. 檢查 CPL <= Gate DPL                                   │
│    2. 從 TSS 載入 kernel stack                                │
│    3. push SS, ESP, EFLAGS, CS, EIP                          │
│    4. CPL → 0（設定新 CS）                                    │
│                                                              │
│  alltraps：push 剩餘暫存器 → 建立 trapframe → call trap()   │
│                                                              │
│  trap()：看 trapno 決定做什麼                                 │
│    64 → syscall    │   32 → timer    │   其他 → fault/kill   │
│                                                              │
│  trapret：pop 暫存器 → iret → CPL 回到 3 → 回到 user        │
│                                                              │
│  TSS：存 kernel stack 的 SS:ESP                               │
│    每次切行程都更新 → CPU 才知道去哪找 kernel stack            │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**一句話：** int 進來 → CPU 自動切 stack + 切權限 → alltraps 存暫存器 → trap() 分辨做什麼 → trapret 恢復暫存器 → iret 回去。

---

## ⏭️ 下一步

Trap 讓我們能進出 kernel。但多個行程怎麼共用一個 CPU？

**答案是 context switch——暫停一個行程，切換到另一個。**

→ [06_PROCESS.md — 行程與排程：context switch](06_PROCESS.md)
