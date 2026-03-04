# 📚 08 — 鎖與並行：Spinlock 和 Sleeplock

> 「spinlock = 廁所門鎖：你一直轉門把等，轉到開為止。sleeplock = 醫院叫號：你先坐下休息，等到叫你的號碼。」

---

## 🚽 比喻：為什麼需要鎖？

想像一間只有一間廁所的辦公室，三個人同時想上廁所：

```
沒有鎖的世界（災難）：
  A 打開門，走進去
  B 也打開門，走進去（！？）
  C 也想進去...

  → 共享資源（廁所）被多人同時使用 → 出事

有鎖的世界（正常）：
  A 走進去，鎖門 🔒
  B 到了，轉門把 → 鎖住了 → 等 ⏳
  A 出來，開門 🔓
  B 進去，鎖門 🔒
  C 到了，等 ⏳
  ...
```

在 OS 裡，「廁所」就是共享資料（ptable、ticks、buffer cache...），「人」就是同時跑的 CPU 核心。

```
為什麼 xv6 需要鎖？

1. 多 CPU（xv6 支援 SMP 多核）
   → 兩個 CPU 可能同時跑 scheduler → 同時改 ptable → 💥

2. 中斷
   → CPU 0 正在改 ticks → timer 中斷進來也要改 ticks → 💥

3. 搶佔（preemption）
   → 行程 A 改到一半 → timer yield → 行程 B 也來改 → 💥
```

---

## 📄 `spinlock.h`：結構定義

```c
// spinlock.h

struct spinlock {
  uint locked;       // 0 = 沒鎖, 1 = 鎖住

  // Debug 用：
  char *name;        // 鎖的名字（如 "ptable", "bcache"）
  struct cpu *cpu;   // 拿到鎖的 CPU
  uint pcs[10];      // 拿鎖時的 call stack（debug 用）
};
```

---

## 📄 `spinlock.c`：完整中文註解

```c
// spinlock.c — 互斥自旋鎖

#include "types.h"
#include "defs.h"
#include "param.h"
#include "x86.h"
#include "memlayout.h"
#include "mmu.h"
#include "proc.h"
#include "spinlock.h"

void
initlock(struct spinlock *lk, char *name)
{
  lk->name = name;
  lk->locked = 0;
  lk->cpu = 0;
}

// ========================================
// acquire() — 拿鎖
// ========================================
// 如果鎖已被別人拿走，就一直空轉（spin）等待
// 這就是 spinlock 名字的由來
void
acquire(struct spinlock *lk)
{
  pushcli();          // 🔑 關閉中斷！（下面解釋為什麼）

  if(holding(lk))
    panic("acquire"); // 同一個 CPU 重複拿同一把鎖 → deadlock → panic

  // 🔑 核心：用 xchg 原子操作來搶鎖
  // xchg(&lk->locked, 1) 做了兩件事（不可分割！）：
  //   1. 把 lk->locked 設為 1
  //   2. 回傳 lk->locked 的舊值
  //
  // 如果舊值 = 0 → 之前沒人鎖 → 我搶到了！→ 跳出迴圈
  // 如果舊值 = 1 → 有人鎖著   → 繼續 spin → 再試
  //
  // 為什麼不能用 if(lk->locked == 0) lk->locked = 1？
  //   → 兩行之間可能被另一個 CPU 插入！
  //   → 兩個 CPU 都看到 0，都設為 1，都以為自己搶到了
  //   → xchg 是 CPU 保證的原子操作，不會被插入
  while(xchg(&lk->locked, 1) != 0)
    ;

  // Memory barrier：確保鎖之後的讀寫不會被 CPU/compiler 重排到鎖之前
  // 否則 critical section 的操作可能「洩漏」到鎖外面
  __sync_synchronize();

  // Debug 記錄
  lk->cpu = mycpu();
  getcallerpcs(&lk, lk->pcs);
}

// ========================================
// release() — 放鎖
// ========================================
void
release(struct spinlock *lk)
{
  if(!holding(lk))
    panic("release"); // 沒拿鎖就放 → bug

  lk->pcs[0] = 0;
  lk->cpu = 0;

  // Memory barrier：確保 critical section 的所有寫入
  // 在放鎖之前對其他 CPU 可見
  __sync_synchronize();

  // 🔑 放鎖：把 locked 設為 0
  // 用 asm volatile 而不是 lk->locked = 0
  // 因為 C 的賦值可能不是原子的（compiler 可能優化成多步）
  asm volatile("movl $0, %0" : "+m" (lk->locked) : );

  popcli();           // 恢復中斷（配對 pushcli）
}

// ========================================
// holding() — 這個 CPU 是否持有這把鎖？
// ========================================
int
holding(struct spinlock *lock)
{
  int r;
  pushcli();
  r = lock->locked && lock->cpu == mycpu();
  popcli();
  return r;
}
```

### xchg 的原子性

```
xchg 指令（x86.h 裡的 inline asm）：

static inline uint
xchg(volatile uint *addr, uint newval)
{
  uint result;
  asm volatile("lock; xchgl %0, %1" :
               "+m" (*addr), "=a" (result) :
               "1" (newval) :
               "cc");
  return result;
}

lock 前綴 + xchgl：
  CPU 保證在這條指令執行期間
  鎖住記憶體匯流排（或用 cache coherence）
  → 其他 CPU 看不到中間狀態
  → 不可能兩個 CPU 同時搶到

這是硬體提供的原子操作，是所有鎖機制的基石。
```

---

## 🔒 為什麼 acquire 要關中斷？

```
場景：CPU 0 拿了 tickslock

  acquire(&tickslock);
  ticks++;                     ← 正在 critical section
  ... timer 中斷來了！         ← 如果沒關中斷，會跳到 trap()
      trap() 裡也要 acquire(&tickslock)
      但鎖已經被 CPU 0 拿了
      → CPU 0 等自己放鎖
      → 但自己在中斷裡，不會回到 release()
      → 💀 DEADLOCK！

解法：拿 spinlock 前關中斷 → 不會被自己打斷

  pushcli();                   ← 關中斷
  acquire(&tickslock);
  ticks++;
  release(&tickslock);
  popcli();                    ← 開中斷
```

### pushcli / popcli：可嵌套的關中斷

```c
// 為什麼不直接用 cli/sti？
// 因為可能巢狀拿鎖：
//   acquire(lock_A) → cli
//     acquire(lock_B) → cli（第二次）
//     release(lock_B) → sti ← 這裡如果直接 sti，lock_A 的保護就被破壞了！
//
// pushcli/popcli 用計數器（ncli）解決：
//   pushcli: ncli++ → 如果 ncli 從 0 變 1，記錄原本的中斷狀態
//   popcli: ncli-- → 只有 ncli 回到 0 且原本中斷是開的，才 sti

void
pushcli(void)
{
  int eflags;
  eflags = readeflags();
  cli();                              // 關中斷
  if(mycpu()->ncli == 0)
    mycpu()->intena = eflags & FL_IF;  // 記錄原始中斷狀態
  mycpu()->ncli += 1;                 // 計數 +1
}

void
popcli(void)
{
  if(readeflags() & FL_IF)
    panic("popcli - interruptible");  // 應該是關的才對
  if(--mycpu()->ncli < 0)
    panic("popcli");                  // 多 pop 了
  if(mycpu()->ncli == 0 && mycpu()->intena)
    sti();                            // 全部放完了，恢復中斷
}
```

---

## 📄 `sleeplock.c`：可以 sleep 的鎖

Spinlock 有個問題：**等鎖時 CPU 空轉，浪費效能。**

如果你要鎖住一個可能很久的東西（如磁碟 I/O），用 spinlock 太浪費了。

```
Spinlock（廁所門鎖）：
  你站在門外一直轉門把
  CPU 100% 忙碌（空轉）
  適合：短暫的 critical section（幾十條指令）

Sleeplock（醫院叫號）：
  你抽了號碼牌，坐下來休息（sleep）
  等裡面的人出來，叫你的號（wakeup）
  CPU 可以去做別的事
  適合：長時間的操作（磁碟讀寫、inode 操作）
```

```c
// sleeplock.h
struct sleeplock {
  uint locked;        // 是否鎖住？
  struct spinlock lk;  // 保護 sleeplock 的 spinlock（很短）

  char *name;
  int pid;            // 持有者的 PID
};
```

```c
// sleeplock.c — 完整中文註解

void
initsleeplock(struct sleeplock *lk, char *name)
{
  initlock(&lk->lk, "sleep lock");  // 內部 spinlock
  lk->name = name;
  lk->locked = 0;
  lk->pid = 0;
}

void
acquiresleep(struct sleeplock *lk)
{
  acquire(&lk->lk);          // 短暫拿 spinlock（保護 lk->locked）

  while (lk->locked) {
    sleep(lk, &lk->lk);      // 🔑 鎖被佔了 → sleep！讓出 CPU
                               // sleep 會 release(&lk->lk) 然後切走
                               // 被 wakeup 後回來時 lk->lk 會被重新拿到
  }

  lk->locked = 1;             // 搶到了！
  lk->pid = myproc()->pid;
  release(&lk->lk);           // 放掉 spinlock（只是保護用的，短暫）
}

void
releasesleep(struct sleeplock *lk)
{
  acquire(&lk->lk);
  lk->locked = 0;
  lk->pid = 0;
  wakeup(lk);                 // 🔑 叫號！喚醒在等的行程
  release(&lk->lk);
}

int
holdingsleep(struct sleeplock *lk)
{
  int r;
  acquire(&lk->lk);
  r = lk->locked && (lk->pid == myproc()->pid);
  release(&lk->lk);
  return r;
}
```

---

## 💤 `sleep()` / `wakeup()`：條件變數

sleep/wakeup 是 xv6 的「條件同步」機制，類似 POSIX 的 condition variable：

```c
// proc.c

void
sleep(void *chan, struct spinlock *lk)
{
  struct proc *p = myproc();

  // 必須持有 lk（保護條件變數）
  // 必須取得 ptable.lock 後才能放 lk
  // 否則可能 miss wakeup

  acquire(&ptable.lock);      // 拿 ptable.lock
  release(lk);                // 放條件鎖
  //  ↑ 這兩步的順序很重要！
  //  如果先 release(lk) 再 acquire(ptable.lock)
  //  → 中間可能有人 wakeup 但我們還沒 sleep → 錯過！

  p->chan = chan;              // 記錄：我在等什麼
  p->state = SLEEPING;        // 標記為睡眠

  sched();                    // 讓出 CPU → scheduler

  // --- 被 wakeup 後從這裡繼續 ---
  p->chan = 0;                // 清除等待通道

  release(&ptable.lock);      // 放 ptable.lock
  acquire(lk);                // 重新拿回條件鎖
}

void
wakeup1(void *chan)  // 內部版本，呼叫者已持有 ptable.lock
{
  struct proc *p;

  for(p = ptable.proc; p < &ptable.proc[NPROC]; p++)
    if(p->state == SLEEPING && p->chan == chan)
      p->state = RUNNABLE;    // 喚醒！下次 scheduler 掃到就能跑
}

void
wakeup(void *chan)
{
  acquire(&ptable.lock);
  wakeup1(chan);
  release(&ptable.lock);
}
```

```
sleep/wakeup 的典型用法（以 pipe 為例）：

寫端（pipewrite）：
  acquire(&p->lock);
  while(pipe 滿了) {
    wakeup(&p->nread);           // 叫讀端起來讀
    sleep(&p->nwrite, &p->lock);  // 自己睡，等讀端讀完叫我
  }
  // pipe 有空間了，寫入
  wakeup(&p->nread);             // 叫讀端起來
  release(&p->lock);

讀端（piperead）：
  acquire(&p->lock);
  while(pipe 空的 && 寫端還開著) {
    sleep(&p->nread, &p->lock);  // 等寫端寫東西進來
  }
  // 有資料了，讀取
  wakeup(&p->nwrite);           // 叫寫端起來
  release(&p->lock);
```

---

## 🔑 Spinlock vs Sleeplock 比較

```
            │ Spinlock              │ Sleeplock
────────────┼───────────────────────┼────────────────────────
等待方式    │ 空轉（busy wait）     │ 睡眠（讓出 CPU）
中斷        │ 關閉（pushcli）       │ 允許（可被中斷）
適用場景    │ 短暫 critical section │ 長時間操作（I/O）
可以 sleep？│ ❌ 不行！              │ ✅ 可以
使用者      │ ptable, tickslock,    │ inode.lock,
            │ bcache.lock, ide.lock │ buffer.lock
```

**為什麼持有 spinlock 時不能 sleep？**

```
acquire(&some_spinlock);
  // ... 中斷關著，其他 CPU 在 spin 等這把鎖 ...
  sleep(...);  // 💀 切走了！
               // 但鎖還沒放！
               // 其他 CPU 永遠拿不到鎖 → DEADLOCK

所以 spinlock 的 critical section 必須短而快！
需要 sleep（如等 I/O）時用 sleeplock。
```

---

## 💻【實作】移除 lock 觀察 race condition

### 實驗：移除 tickslock

```c
// trap.c — 原本的程式碼：
case T_IRQ0 + IRQ_TIMER:
    if(cpuid() == 0){
      acquire(&tickslock);   // ← 移除這行
      ticks++;
      wakeup(&ticks);
      release(&tickslock);   // ← 移除這行
    }
```

用多 CPU 啟動：

```bash
cd ~/xv6-public
# 修改 trap.c，移除 tickslock 的 acquire/release
make clean && make && make qemu-nox CPUS=4
```

在 xv6 shell 裡跑 `sleep` 相關的程式，可能觀察到：
- `sleep` 時間不準確
- `uptime` 回傳奇怪的值
- 多個行程同時 sleep 時有的醒不過來

（因為 ticks 的讀寫沒有保護，多個 CPU 可能同時改 ticks → lost update）

### 更劇烈的實驗：移除 ptable.lock

**⚠️ 警告：這會讓 xv6 非常不穩定，可能直接 panic**

```c
// proc.c — 在 scheduler() 裡移除 ptable.lock
// 拿掉 acquire(&ptable.lock) 和 release(&ptable.lock)
```

```bash
make clean && make && make qemu-nox CPUS=4
```

可能看到：
- 多個 CPU 同時 switch 到同一個行程
- kernel panic（assertion failed）
- 隨機的記憶體錯誤

這就是為什麼鎖是不可或缺的！

---

## 🧠 本章小結

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  Spinlock（自旋鎖）：                                        │
│    acquire：pushcli → xchg 搶鎖 → spin 直到搶到             │
│    release：清除 locked → popcli                             │
│    xchg 是 CPU 原子操作 → 硬體保證不可分割                   │
│    pushcli/popcli → 拿鎖期間關中斷，避免 deadlock            │
│                                                              │
│  Sleeplock（睡眠鎖）：                                       │
│    acquiresleep：拿 spinlock → while(locked) sleep → 搶到   │
│    releasesleep：清除 locked → wakeup                        │
│    等待時讓出 CPU → 適合長時間操作                           │
│                                                              │
│  sleep / wakeup（條件同步）：                                │
│    sleep(chan, lk)：記錄 chan → SLEEPING → sched()           │
│    wakeup(chan)：掃描 ptable → 把 chan 匹配的改為 RUNNABLE   │
│    → 類似 condition variable，但更簡單                       │
│                                                              │
│  關鍵規則：                                                  │
│    1. 持有 spinlock 時不能 sleep                             │
│    2. 持有 spinlock 時中斷是關的                             │
│    3. sleep 前必須持有條件鎖 + ptable.lock → 不會 miss wakeup│
│    4. 鎖的粒度很重要：太粗 → 慢，太細 → 容易出 bug          │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**一句話：** spinlock 用硬體原子操作 + 關中斷保證互斥；sleeplock 用 sleep/wakeup 避免長時間空轉。

---

## ⏭️ 下一步

有了鎖的保護，我們可以安全地實現複雜的共享資料結構了——比如檔案系統。

→ [09_FILESYSTEM.md — 檔案系統：從磁碟到 inode](09_FILESYSTEM.md)
