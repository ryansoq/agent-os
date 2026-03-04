# 📚 06 — 行程與排程：Context Switch

> 「context switch = 暫停遊戲存檔 → 載入另一個存檔 → 繼續玩。CPU 從來都只在玩一個遊戲，但切得太快，看起來像同時玩好幾個。」

---

## 🎮 比喻：遊戲存檔

想像你有一台遊戲機（CPU），同時要玩三款遊戲（行程 A、B、C）：

```
1. 正在玩遊戲 A → timer 響了！
2. 暫停遊戲 A → 存檔（存到 A 的記憶卡）
3. 取出遊戲 B 的記憶卡 → 讀檔
4. 繼續玩遊戲 B → timer 又響了！
5. 暫停遊戲 B → 存檔 → 讀遊戲 C 的檔 → ...

存檔裡有什麼？
  - 所有暫存器的值（EIP, ESP, EAX, ...）
  - 遊戲畫面的位置（頁表 = pgdir）
  - 遊戲進度（kernel stack 上的 trapframe）

這就是 context switch！
```

---

## 📄 `struct proc`：行程結構

```c
// proc.h

enum procstate { UNUSED, EMBRYO, SLEEPING, RUNNABLE, RUNNING, ZOMBIE };

struct proc {
  uint sz;                     // 行程記憶體大小（bytes）
  pde_t* pgdir;                // 行程的頁表 ← 每個行程有自己的！
  char *kstack;                // kernel stack 底部
  enum procstate state;        // 行程狀態
  int pid;                     // Process ID
  struct proc *parent;         // 父行程
  struct trapframe *tf;        // Trap frame（中斷時的暫存器快照）
  struct context *context;     // Context（context switch 時的存檔）
  void *chan;                  // Sleep channel（在等什麼？）
  int killed;                  // 被標記要殺掉？
  struct file *ofile[NOFILE];  // 開啟的檔案
  struct inode *cwd;           // 當前工作目錄
  char name[16];               // 名字（debug 用）
};
```

### 行程狀態轉換

```
          allocproc()                    scheduler()
UNUSED ──────────→ EMBRYO ──→ RUNNABLE ──────────→ RUNNING
                                  ↑                    │
                                  │    yield()/        │
                                  │    timer中斷       │
                                  ←────────────────────┘
                                  
                               sleep()              exit()
                    RUNNABLE ←──────── SLEEPING    RUNNING ──→ ZOMBIE
                     wakeup()                              │
                                                    wait()  │
                                              UNUSED ←──────┘
                                              (parent 回收)
```

---

## 📄 `allocproc()`：分配行程結構 + kernel stack

```c
// proc.c

static struct proc*
allocproc(void)
{
  struct proc *p;
  char *sp;

  acquire(&ptable.lock);

  // 在 process table 裡找一個 UNUSED 的 slot
  for(p = ptable.proc; p < &ptable.proc[NPROC]; p++)
    if(p->state == UNUSED)
      goto found;

  release(&ptable.lock);
  return 0;  // 沒有空位了

found:
  p->state = EMBRYO;     // 標記為「正在建立」
  p->pid = nextpid++;

  release(&ptable.lock);

  // 分配 kernel stack（4KB）
  if((p->kstack = kalloc()) == 0){
    p->state = UNUSED;
    return 0;
  }
  sp = p->kstack + KSTACKSIZE;  // sp 指向 stack 頂端

  // ========================================
  // 在 kernel stack 上佈局 trapframe 和 context
  // ========================================

  // 1. 預留 trapframe 的空間
  sp -= sizeof *p->tf;
  p->tf = (struct trapframe*)sp;

  // 2. 放一個「返回地址」= trapret
  //    forkret() return 時會跳到 trapret
  //    → trapret 做 iret → 跳到 user space
  sp -= 4;
  *(uint*)sp = (uint)trapret;

  // 3. 預留 context 的空間
  sp -= sizeof *p->context;
  p->context = (struct context*)sp;
  memset(p->context, 0, sizeof *p->context);
  p->context->eip = (uint)forkret;
  // → swtch() 會跳到 forkret
  // → forkret return → trapret → iret → user

  return p;
}
```

### Kernel Stack 的完整佈局

```
allocproc() 建好後，kernel stack 長這樣：

         高位址
    ┌──────────────┐ ← kstack + KSTACKSIZE
    │              │
    │  trapframe   │ ← p->tf
    │  (76 bytes)  │   存 user 的所有暫存器
    │              │   （userinit 或 fork 會填入）
    ├──────────────┤
    │  trapret     │ ← forkret() 的返回地址
    │  (4 bytes)   │   （被 ret 指令 pop 出來）
    ├──────────────┤
    │              │
    │  context     │ ← p->context
    │  (20 bytes)  │   存 edi, esi, ebx, ebp, eip
    │              │   eip = forkret
    │              │
    ├──────────────┤
    │              │
    │ （空的空間） │
    │              │
    └──────────────┘ ← kstack（底部）
         低位址

swtch() 的執行過程：
  1. scheduler 呼叫 swtch(&scheduler_ctx, p->context)
  2. swtch 把 ESP 指向 p->context
  3. pop edi, esi, ebx, ebp（恢復暫存器）
  4. ret → EIP = forkret（context 裡存的）
  5. forkret 做一些初始化
  6. forkret return → pop trapret → 跳到 trapret
  7. trapret 做 iret → 從 trapframe 恢復 user 的暫存器 → Ring 3！
```

---

## 📄 `userinit()`：第一個 user process

```c
// proc.c

void
userinit(void)
{
  struct proc *p;
  extern char _binary_initcode_start[], _binary_initcode_size[];

  p = allocproc();         // 分配 proc + kernel stack
  initproc = p;

  // 建立頁表
  if((p->pgdir = setupkvm()) == 0)
    panic("userinit: out of memory?");

  // 把 initcode.S 的機器碼放到虛擬地址 0
  inituvm(p->pgdir, _binary_initcode_start, (int)_binary_initcode_size);
  p->sz = PGSIZE;

  // 🔑 設定 trapframe：決定 iret 回去後是什麼狀態
  memset(p->tf, 0, sizeof(*p->tf));
  p->tf->cs = (SEG_UCODE << 3) | DPL_USER;   // CS = 0x1B → CPL=3！
  p->tf->ds = (SEG_UDATA << 3) | DPL_USER;   // DS = 0x23
  p->tf->es = p->tf->ds;
  p->tf->ss = p->tf->ds;
  p->tf->eflags = FL_IF;     // 開啟中斷
  p->tf->esp = PGSIZE;       // user stack 頂端
  p->tf->eip = 0;            // 從虛擬地址 0 開始執行（initcode.S）

  safestrcpy(p->name, "initcode", sizeof(p->name));
  p->cwd = namei("/");

  acquire(&ptable.lock);
  p->state = RUNNABLE;       // 可以跑了！
  release(&ptable.lock);
}
```

```
userinit() 的巧妙設計：

  它從來不直接「跳到 user space」。
  它只是設好 trapframe 和 context，然後等 scheduler 排到它。

  當 scheduler 選中它 →
    swtch → forkret → trapret → iret →
    CPU 從 trapframe pop 出 CS=0x1B, EIP=0, ESP=PGSIZE
    → Ring 3！開始跑 initcode.S！

  看起來就像是「從一個不存在的 syscall 返回」。
  實際上第一個行程從來沒有 int 進 kernel 過——
  但 kernel 幫它假裝了一個 trapframe，讓 iret 能「返回」到 user space。
```

---

## 📄 `struct context` 與 `swtch.S`：context switch 的核心

### struct context

```c
// proc.h

// context switch 時需要保存的暫存器
// 只有 callee-saved registers + EIP
struct context {
  uint edi;
  uint esi;
  uint ebx;
  uint ebp;
  uint eip;   // swtch 的返回地址
};
```

**為什麼只存這 5 個？不用存 EAX, ECX, EDX 嗎？**

```
C 語言的呼叫慣例（cdecl / System V ABI）：

  Caller-saved（呼叫者負責存）：EAX, ECX, EDX
    → 呼叫函數前，如果你還需要這些值，你自己 push
    → swtch() 是被 C 函數呼叫的 → 呼叫者已經處理了

  Callee-saved（被呼叫者負責存）：EBX, ESI, EDI, EBP
    → 函數如果用到這些暫存器，必須先存起來、結束時恢復
    → swtch() 必須存這些

  ESP → 切 stack 就等於存/恢復了
  EIP → call/ret 指令自動處理（push 返回地址 / pop EIP）

所以 swtch() 只需要 push/pop 4 個暫存器 + 切 ESP
合計 5 個值（加上 stack 上的返回地址當 EIP）
這就是 struct context！
```

### `swtch.S`：逐行中文註解

```asm
# Context switch
#
#   void swtch(struct context **old, struct context *new);
#
# 把當前暫存器存到 *old，然後從 new 恢復暫存器
# 效果：CPU 從一個 kernel thread 跳到另一個

.globl swtch
swtch:
  # ========================================
  # 取得參數
  # ========================================
  movl 4(%esp), %eax       # EAX = old（struct context **）
                            # → 要把當前 context 存到 *old
  movl 8(%esp), %edx       # EDX = new（struct context *）
                            # → 要從 new 恢復 context

  # ========================================
  # 保存當前的 callee-saved registers
  # ========================================
  # 此時 stack 上已經有 swtch 的返回地址（call 指令 push 的）
  # 所以 push 完這 4 個後，stack 上就是一個完整的 struct context
  pushl %ebp               # 存 EBP
  pushl %ebx               # 存 EBX
  pushl %esi               # 存 ESI
  pushl %edi               # 存 EDI

  # Stack 現在長這樣：
  # ┌────────────────┐
  # │ 返回地址 (EIP) │ ← call swtch 時 push 的
  # │ EBP            │
  # │ EBX            │
  # │ ESI            │
  # │ EDI            │ ← ESP 指向這裡
  # └────────────────┘
  # 這就是一個 struct context！

  # ========================================
  # 切換 stack！
  # ========================================
  movl %esp, (%eax)        # *old = ESP
                            # → 記錄當前的 stack pointer
                            # → 下次切回來時知道從哪恢復

  movl %edx, %esp          # ESP = new
                            # → 🔑 切換到新的 stack！
                            # → 從這一刻起，我們在另一個行程的 kernel stack 上

  # ========================================
  # 從新 stack 恢復暫存器
  # ========================================
  popl %edi                # 恢復 EDI
  popl %esi                # 恢復 ESI
  popl %ebx                # 恢復 EBX
  popl %ebp                # 恢復 EBP

  ret                      # pop EIP → 跳到新 context 的返回地址
                            # 如果是第一次執行 → EIP = forkret
                            # 如果是之前被切走的 → EIP = sched() 裡 swtch 的下一行
```

```
swtch 的精髓：只有一個 movl 切換了整個世界

  movl %edx, %esp    ← 就這一條指令！

  之前的所有 push 是在「存檔」
  之後的所有 pop 是在「讀檔」
  中間這一條 movl 就是「換遊戲卡匣」

  ESP 一換，整個 stack 都變了
  → pop 出來的是另一個行程的暫存器
  → ret 跳到另一個行程的程式碼
  → 世界完全不同了
```

---

## 📄 `scheduler()` 與 `sched()`：排程流程

### scheduler()：永不返回的迴圈

```c
// proc.c

void
scheduler(void)
{
  struct proc *p;
  struct cpu *c = mycpu();
  c->proc = 0;

  for(;;){
    sti();  // 開中斷（scheduler 跑在 kernel，需要收 timer 中斷）

    acquire(&ptable.lock);

    // Round-robin：從頭到尾掃 process table
    for(p = ptable.proc; p < &ptable.proc[NPROC]; p++){
      if(p->state != RUNNABLE)
        continue;

      // 找到一個 RUNNABLE 的行程！
      c->proc = p;
      switchuvm(p);          // 切到行程的頁表 + 更新 TSS
      p->state = RUNNING;

      // 🔑 context switch！
      swtch(&(c->scheduler), p->context);
      // ← 行程跑完（yield 或 sleep）後會回到這裡

      switchkvm();           // 切回 kernel 頁表
      c->proc = 0;
    }

    release(&ptable.lock);
  }
}
```

### sched()：行程主動讓出 CPU

```c
void
sched(void)
{
  int intena;
  struct proc *p = myproc();

  // 各種安全檢查
  if(!holding(&ptable.lock))
    panic("sched ptable.lock");   // 必須持有 lock
  if(mycpu()->ncli != 1)
    panic("sched locks");         // 不能持有其他 lock
  if(p->state == RUNNING)
    panic("sched running");       // 狀態必須已經改了
  if(readeflags()&FL_IF)
    panic("sched interruptible"); // 中斷必須關閉

  intena = mycpu()->intena;

  // 🔑 切回 scheduler！
  swtch(&p->context, mycpu()->scheduler);
  // ← scheduler 再次選中我們時，會從這裡繼續

  mycpu()->intena = intena;  // 恢復中斷狀態
}
```

### yield()：timer 搶佔

```c
void
yield(void)
{
  acquire(&ptable.lock);
  myproc()->state = RUNNABLE;  // 我還能跑，但讓一下
  sched();                      // → swtch → scheduler
  release(&ptable.lock);
}
```

---

## 🔄 完整的 Context Switch 流程

```
行程 A 在 user space 跑（CPL=3）
    │
    │ Timer 中斷！
    ↓
CPU 自動切到 kernel stack（TSS.esp0）
CPU push SS, ESP, EFLAGS, CS, EIP
    │
    ↓
alltraps → trap()
    │ trapno == IRQ_TIMER
    │ → ticks++
    │ → yield()
    │     │
    │     │ p->state = RUNNABLE
    │     │ sched()
    │     │   │
    │     │   │ swtch(&A->context, scheduler)
    │     │   │
    │     │   │   ┌─── swtch 做的事 ────────────────────┐
    │     │   │   │ push EBP, EBX, ESI, EDI 到 A 的 stack │
    │     │   │   │ A->context = ESP（存檔！）             │
    │     │   │   │ ESP = scheduler 的 context（讀檔！）    │
    │     │   │   │ pop EDI, ESI, EBX, EBP 從 scheduler    │
    │     │   │   │ ret → 回到 scheduler                   │
    │     │   │   └─────────────────────────────────────────┘
    │     │   │
    ↓     ↓   ↓
scheduler 繼續跑
    │ 找到行程 B（RUNNABLE）
    │ switchuvm(B) → 切頁表 + 更新 TSS
    │ B->state = RUNNING
    │
    │ swtch(&scheduler, B->context)
    │
    │   ┌─── swtch 做的事 ──────────────────────────┐
    │   │ push scheduler 的暫存器                     │
    │   │ scheduler_ctx = ESP（存檔！）               │
    │   │ ESP = B->context（讀檔！）                  │
    │   │ pop B 的暫存器                              │
    │   │ ret → 回到 B 上次被切走的地方（sched 裡）    │
    │   └─────────────────────────────────────────────┘
    │
    ↓
B 的 sched() 繼續
    → 回到 yield()
    → 回到 trap()
    → 回到 trapret
    → iret → 回到 B 的 user space（CPL=3）
    
行程 B 繼續跑！
```

```
精簡版：

A(user) → timer → trap → yield → sched → swtch → scheduler
                                                      │
scheduler → swtch → sched → yield → trap → trapret → B(user)
```

---

## 💻【實作】觀察 context switch

在 `scheduler()` 裡加 `cprintf` 看切換過程：

```c
// 在 scheduler() 的 swtch 前後加 log：

      c->proc = p;
      switchuvm(p);
      p->state = RUNNING;

      cprintf("[SCHED] CPU %d: switch to pid %d (%s)\n",
              cpuid(), p->pid, p->name);

      swtch(&(c->scheduler), p->context);

      cprintf("[SCHED] CPU %d: back from pid %d (%s)\n",
              cpuid(), p->pid, p->name);

      switchkvm();
      c->proc = 0;
```

```bash
cd ~/xv6-public
# 修改 proc.c
make clean && make && make qemu-nox CPUS=1
```

你會看到：
```
[SCHED] CPU 0: switch to pid 1 (initcode)
[SCHED] CPU 0: back from pid 1 (initcode)
[SCHED] CPU 0: switch to pid 1 (init)
[SCHED] CPU 0: back from pid 1 (init)
[SCHED] CPU 0: switch to pid 2 (sh)
[SCHED] CPU 0: back from pid 2 (sh)
[SCHED] CPU 0: switch to pid 2 (sh)
...
```

觀察重點：
- **pid 1** 一開始叫 `initcode`，後來 exec 成 `init`
- **pid 2** 是 `sh`（shell）
- scheduler 不停在 `switch to` → `back from` 之間切換
- 每次 `back from` 代表行程讓出了 CPU（yield、sleep、exit）

---

## 📄 `forkret()`：新行程的第一次排程

```c
// proc.c

void
forkret(void)
{
  static int first = 1;

  // 還持有 ptable.lock（scheduler 拿的）
  release(&ptable.lock);

  if (first) {
    // 第一個行程需要初始化檔案系統
    first = 0;
    iinit(ROOTDEV);
    initlog(ROOTDEV);
  }

  // return → 去哪？
  // 看 allocproc()：在 context 上面放了 trapret 當返回地址
  // 所以 return → trapret → iret → user space！
}
```

```
新行程第一次被 scheduler 排到時的路徑：

scheduler:
  swtch(&scheduler, p->context)
    │
    │ swtch 恢復 context：EIP = forkret
    │ ret → 跳到 forkret
    ↓
forkret:
  release(&ptable.lock)
  return
    │
    │ allocproc 在 stack 上放了 trapret 當返回地址
    │ ret → 跳到 trapret
    ↓
trapret (trapasm.S):
  popal              # 恢復通用暫存器
  pop gs, fs, es, ds # 恢復段暫存器
  add $8, %esp       # 跳過 trapno + errcode
  iret               # → 從 trapframe 恢復 CS, EIP, ESP
    │                #   CS = 0x1B → CPL=3 → Ring 3！
    ↓
User space！程式開始跑了！
```

---

## 🧠 本章小結

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  struct proc：行程的所有資訊                                  │
│    pgdir    → 頁表（每個行程獨立）                            │
│    kstack   → kernel stack（4KB）                            │
│    tf       → trapframe（user 的暫存器快照）                  │
│    context  → context（kernel 的暫存器存檔）                  │
│                                                              │
│  kernel stack layout：                                       │
│    [trapframe] [trapret 地址] [context] [空的]               │
│                                                              │
│  swtch.S 的精髓：                                             │
│    push 4 個 callee-saved registers（存檔）                  │
│    movl %esp, (%eax)     ← 存 stack pointer                 │
│    movl %edx, %esp       ← 🔑 切換世界！                    │
│    pop 4 個 registers（讀檔）                                │
│    ret → 跳到新 context 的返回地址                           │
│                                                              │
│  scheduler（永不返回的迴圈）：                                │
│    掃 ptable → 找 RUNNABLE → switchuvm → swtch → 跑行程    │
│    行程 yield/sleep → swtch 回 scheduler → 找下一個          │
│                                                              │
│  新行程的第一次：                                             │
│    swtch → forkret → trapret → iret → user space           │
│    看起來像「從 syscall 返回」，實際上從沒 int 進去過         │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**一句話：** context switch 就是 `movl %edx, %esp`——換了 stack，就換了整個世界。

---

## ⏭️ 下一步

行程能跑了，但它怎麼跟 kernel 溝通？

→ [07_SYSCALL.md — 系統呼叫：從 int $0x40 到 sys_write()](07_SYSCALL.md)
