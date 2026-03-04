# 📚 07 — System Call：從 User Space 呼叫 Kernel

> 「你在餐廳裡想吃牛排，但你不能自己走進廚房。你得跟服務生說：『我要牛排』，服務生進廚房幫你做，再端出來給你。syscall 就是那個服務生。」

---

## 🍽️ 比喻：餐廳點餐

```
你（User Process, Ring 3）     廚房（Kernel, Ring 0）
    │                              │
    │  「我要牛排！」              │
    │  ──────────────────────→     │
    │  （int $0x40 = 按下服務鈴）  │
    │                              │
    │       服務生看你的菜單號碼    │
    │       （EAX = syscall 號碼） │
    │       進廚房做菜              │
    │       （執行 sys_xxx()）      │
    │                              │
    │  ←──────────────────────     │
    │  牛排端上來了                 │
    │  （結果放在 EAX 裡回傳）     │
```

重點：
- **你不能自己進廚房**（Ring 3 不能執行 kernel code）
- **只有一個合法入口**（`int $0x40`，IDT 設定 DPL=3）
- **要告訴服務生你要什麼**（EAX = syscall 號碼）
- **參數放在 user stack 上**（服務生會去讀你的菜單）

---

## 🔄 Syscall 完整路徑

```
User 程式呼叫 write(fd, buf, n)
    │
    ↓
user.h 宣告：int write(int, const void*, int);
    │
    ↓
usys.S 展開：
    movl $SYS_write, %eax    # EAX = 16（write 的號碼）
    int $T_SYSCALL            # 觸發中斷 64
    ret
    │
    ↓ ═══════ 跨越 Ring 3 → Ring 0 ═══════
    │
vectors.S → vector64:
    pushl $0                  # 假 error code
    pushl $64                 # trapno
    jmp alltraps
    │
    ↓
trapasm.S → alltraps:
    push 段暫存器 + pushal    # 建立 trapframe
    call trap
    │
    ↓
trap.c → trap(tf):
    tf->trapno == T_SYSCALL → syscall()
    │
    ↓
syscall.c → syscall():
    num = tf->eax             # 取出 syscall 號碼 = 16
    syscalls[16]()            # 呼叫 sys_write()
    tf->eax = 回傳值          # 結果放回 EAX
    │
    ↓
sysfile.c → sys_write():
    argfd(), argptr(), argint()   # 從 user stack 取參數
    filewrite(f, p, n)            # 真正寫檔案
    │
    ↓ ═══════ 返回 Ring 0 → Ring 3 ═══════
    │
trapasm.S → trapret:
    popal → pop 段暫存器 → iret
    │
    ↓
User 程式：write() 回傳，EAX 裡有結果
```

---

## 📄 `usys.S`：User 端的 syscall 入口

```asm
# usys.S — 每個 syscall 的 user-space 包裝函數
#
# 用巨集產生，每個 syscall 長一樣：
#   1. 把 syscall 號碼放到 EAX
#   2. int $64（觸發 trap）
#   3. ret（回傳，EAX 裡有結果）

#include "syscall.h"      # SYS_fork = 1, SYS_write = 16, ...
#include "traps.h"        # T_SYSCALL = 64

#define SYSCALL(name) \
  .globl name; \           # 匯出符號（讓 C 程式能呼叫）
  name: \                  # 函數入口
    movl $SYS_ ## name, %eax; \  # EAX = syscall 號碼
    int $T_SYSCALL; \             # 🔑 觸發中斷 64！
    ret                           # 回傳（EAX = kernel 放的結果）

SYSCALL(fork)              # fork: movl $1, %eax; int $64; ret
SYSCALL(exit)              # exit: movl $2, %eax; int $64; ret
SYSCALL(wait)              # wait: movl $3, %eax; int $64; ret
SYSCALL(pipe)
SYSCALL(read)              # read: movl $5, %eax; int $64; ret
SYSCALL(write)             # write: movl $16, %eax; int $64; ret
SYSCALL(close)
SYSCALL(kill)
SYSCALL(exec)
SYSCALL(open)
SYSCALL(mknod)
SYSCALL(unlink)
SYSCALL(fstat)
SYSCALL(link)
SYSCALL(mkdir)
SYSCALL(chdir)
SYSCALL(dup)
SYSCALL(getpid)            # getpid: movl $11, %eax; int $64; ret
SYSCALL(sbrk)
SYSCALL(sleep)
SYSCALL(uptime)
```

```
User 呼叫 write(1, "hi", 2) 時，C 編譯器產生的 stack 長這樣：

    ┌──────────────┐
    │ 2             │ ← 第 3 個參數（n）
    │ "hi" 的地址   │ ← 第 2 個參數（buf）
    │ 1             │ ← 第 1 個參數（fd）
    │ 返回地址      │ ← call write 時 push 的
    └──────────────┘ ← ESP

然後 usys.S 的 write:
    movl $16, %eax
    int $64           ← CPU 切到 kernel stack，但 user stack 不變
    ret

進 kernel 後，tf->esp 指向 user stack
kernel 要從 tf->esp + 4 開始讀參數（+4 跳過返回地址）
```

---

## 📄 `syscall.c`：完整中文註解

```c
// syscall.c — syscall 分派器
// 從 trapframe 取得 syscall 號碼，查表呼叫對應函數

#include "types.h"
#include "defs.h"
#include "param.h"
#include "memlayout.h"
#include "mmu.h"
#include "proc.h"
#include "x86.h"
#include "syscall.h"

// ========================================
// 從 user space 安全讀取資料
// ========================================

// 從 user 的地址 addr 讀一個 int
// 為什麼不能直接 *(int*)addr？
// → 需要檢查 addr 在行程的合法範圍內！
//   否則惡意程式可以讓 kernel 讀到不該讀的地方
int
fetchint(uint addr, int *ip)
{
  struct proc *curproc = myproc();

  // 安全檢查：addr 和 addr+4 都要在行程的記憶體範圍 [0, sz) 內
  if(addr >= curproc->sz || addr+4 > curproc->sz)
    return -1;              // 超出範圍 → 拒絕
  *ip = *(int*)(addr);     // 安全，直接讀（kernel 有完整頁表存取權）
  return 0;
}

// 從 user 的地址 addr 讀一個 NUL 結尾的字串
// 不會複製字串，只設定 *pp 指向它
// 回傳字串長度（不含 NUL），失敗回傳 -1
int
fetchstr(uint addr, char **pp)
{
  char *s, *ep;
  struct proc *curproc = myproc();

  if(addr >= curproc->sz)
    return -1;

  *pp = (char*)addr;           // 指向 user 空間的字串
  ep = (char*)curproc->sz;     // 行程記憶體的上限

  // 掃描找 NUL 結尾，同時確保不超出行程範圍
  for(s = *pp; s < ep; s++){
    if(*s == 0)
      return s - *pp;          // 找到 NUL → 回傳長度
  }
  return -1;                   // 沒找到 NUL → 字串沒有正確結尾
}

// ========================================
// 從 user stack 取 syscall 參數
// ========================================

// 取第 n 個 syscall 參數（int）
// user stack 佈局：[返回地址][arg0][arg1][arg2]...
//                   ↑ tf->esp
// 所以 arg0 在 tf->esp + 4，arg1 在 tf->esp + 8 ...
int
argint(int n, int *ip)
{
  return fetchint((myproc()->tf->esp) + 4 + 4*n, ip);
  //                                    ↑   ↑
  //                                    │   第 n 個參數的 offset
  //                                    跳過返回地址
}

// 取第 n 個參數，當作指向 size bytes 記憶體的指標
// 額外檢查：指標指向的整塊記憶體都要在行程範圍內
int
argptr(int n, char **pp, int size)
{
  int i;
  struct proc *curproc = myproc();

  if(argint(n, &i) < 0)       // 先取出指標值（是個整數）
    return -1;

  // 安全檢查：指標 i 到 i+size 都要在 [0, curproc->sz) 範圍內
  if(size < 0 || (uint)i >= curproc->sz || (uint)i+size > curproc->sz)
    return -1;

  *pp = (char*)i;              // 安全，回傳指標
  return 0;
}

// 取第 n 個參數，當作字串指標
// 檢查指標合法、字串有 NUL 結尾
int
argstr(int n, char **pp)
{
  int addr;
  if(argint(n, &addr) < 0)    // 先取出地址
    return -1;
  return fetchstr(addr, pp);   // 再驗證字串
}

// ========================================
// syscall 函數指標表
// ========================================
extern int sys_chdir(void);
extern int sys_close(void);
extern int sys_dup(void);
extern int sys_exec(void);
extern int sys_exit(void);
extern int sys_fork(void);
extern int sys_fstat(void);
extern int sys_getpid(void);
extern int sys_kill(void);
extern int sys_link(void);
extern int sys_mkdir(void);
extern int sys_mknod(void);
extern int sys_open(void);
extern int sys_pipe(void);
extern int sys_read(void);
extern int sys_sbrk(void);
extern int sys_sleep(void);
extern int sys_unlink(void);
extern int sys_wait(void);
extern int sys_write(void);
extern int sys_uptime(void);

// 🔑 syscall 分派表：用 syscall 號碼當 index 查到函數
// C 語言的 designated initializer：[SYS_fork] = sys_fork
// → syscalls[1] = sys_fork, syscalls[2] = sys_exit, ...
static int (*syscalls[])(void) = {
  [SYS_fork]    sys_fork,     // 1
  [SYS_exit]    sys_exit,     // 2
  [SYS_wait]    sys_wait,     // 3
  [SYS_pipe]    sys_pipe,     // 4
  [SYS_read]    sys_read,     // 5
  [SYS_kill]    sys_kill,     // 6
  [SYS_exec]    sys_exec,     // 7
  [SYS_fstat]   sys_fstat,    // 8
  [SYS_chdir]   sys_chdir,    // 9
  [SYS_dup]     sys_dup,      // 10
  [SYS_getpid]  sys_getpid,   // 11
  [SYS_sbrk]    sys_sbrk,     // 12
  [SYS_sleep]   sys_sleep,    // 13
  [SYS_uptime]  sys_uptime,   // 14
  [SYS_open]    sys_open,     // 15
  [SYS_write]   sys_write,    // 16
  [SYS_mknod]   sys_mknod,    // 17
  [SYS_unlink]  sys_unlink,   // 18
  [SYS_link]    sys_link,     // 19
  [SYS_mkdir]   sys_mkdir,    // 20
  [SYS_close]   sys_close,    // 21
};

// ========================================
// syscall() — 核心分派函數
// ========================================
void
syscall(void)
{
  int num;
  struct proc *curproc = myproc();

  num = curproc->tf->eax;     // 從 trapframe 取出 syscall 號碼
                               // （user 在 usys.S 裡放進 EAX 的）

  // 檢查號碼合法、對應函數存在
  if(num > 0 && num < NELEM(syscalls) && syscalls[num]) {
    // 🔑 呼叫對應的 sys_xxx() 函數
    // 回傳值放回 tf->eax → iret 後 user 的 EAX 就是這個值
    curproc->tf->eax = syscalls[num]();
  } else {
    // 不認識的 syscall → 印錯誤、回傳 -1
    cprintf("%d %s: unknown sys call %d\n",
            curproc->pid, curproc->name, num);
    curproc->tf->eax = -1;
  }
}
```

### 為什麼 sys_xxx() 都是 `int func(void)`？

```
問題：write(fd, buf, n) 有三個參數，但 sys_write() 的 prototype 是 void？

答案：syscall 的參數不透過 C 函數參數傳遞！
      它們在 user stack 上，kernel 用 argint/argptr/argstr 去讀。

為什麼？
  因為 user → kernel 之間隔了一個 int $0x40。
  int 指令不會幫你傳 C 參數——它只是觸發中斷。
  kernel 只能透過 trapframe 裡的 user ESP 去找 user stack 上的值。

  user stack：[ret addr] [arg0] [arg1] [arg2]
               ↑ tf->esp
  argint(0, &fd)  → fetchint(tf->esp + 4, &fd)  → fd
  argint(1, &buf) → fetchint(tf->esp + 8, &buf)  → buf 地址
  argint(2, &n)   → fetchint(tf->esp + 12, &n)   → n
```

---

## 📄 `sysproc.c`：行程相關 syscall

```c
// sysproc.c — 行程管理相關的 syscall 實現

int
sys_fork(void)
{
  return fork();      // 直接呼叫 proc.c 的 fork()
}

int
sys_exit(void)
{
  exit();             // 不會返回
  return 0;
}

int
sys_wait(void)
{
  return wait();
}

int
sys_kill(void)
{
  int pid;

  if(argint(0, &pid) < 0)    // 從 user stack 取第 0 個參數
    return -1;
  return kill(pid);
}

int
sys_getpid(void)
{
  return myproc()->pid;       // 最簡單的 syscall：直接回傳 PID
}

int
sys_sbrk(void)
{
  int addr;
  int n;

  if(argint(0, &n) < 0)      // 取參數 n（要增加/減少多少 bytes）
    return -1;
  addr = myproc()->sz;        // 記錄舊的 size
  if(growproc(n) < 0)         // 增加/縮小行程記憶體
    return -1;
  return addr;                // 回傳舊的 size（跟 Linux 的 brk 類似）
}

int
sys_sleep(void)
{
  int n;
  uint ticks0;

  if(argint(0, &n) < 0)      // 取參數 n（要 sleep 幾個 tick）
    return -1;

  acquire(&tickslock);
  ticks0 = ticks;             // 記錄開始時間

  // 等到經過 n 個 tick
  while(ticks - ticks0 < n){
    if(myproc()->killed){     // 被殺了就提前醒來
      release(&tickslock);
      return -1;
    }
    sleep(&ticks, &tickslock);  // 睡眠，等 timer 中斷 wakeup
  }

  release(&tickslock);
  return 0;
}

int
sys_uptime(void)
{
  uint xticks;

  acquire(&tickslock);
  xticks = ticks;             // 讀取全域 tick 計數
  release(&tickslock);
  return xticks;
}
```

---

## 📄 `sysfile.c` 精選：sys_write 的路徑

`sysfile.c` 實現檔案相關的 syscall（open、read、write、close 等）。以 `sys_write` 為例：

```c
int
sys_write(void)
{
  struct file *f;
  int n;
  char *p;

  // 取三個參數：fd, buf 指標, 長度 n
  if(argfd(0, 0, &f) < 0 ||         // arg0 = fd → 轉成 file 結構
     argint(2, &n) < 0 ||           // arg2 = n（要寫多少 bytes）
     argptr(1, &p, n) < 0)          // arg1 = buf（指標，長度 n）
    return -1;

  return filewrite(f, p, n);        // 呼叫 file.c 的 filewrite
}
```

`argfd()` 是 sysfile.c 內部的 helper：

```c
// 取 fd 號碼，檢查合法，回傳對應的 file 結構
static int
argfd(int n, int *pfd, struct file **pf)
{
  int fd;
  struct file *f;

  if(argint(n, &fd) < 0)             // 從 user stack 取 fd 號碼
    return -1;
  if(fd < 0 || fd >= NOFILE ||       // fd 範圍檢查
     (f=myproc()->ofile[fd]) == 0)   // 從行程的 fd table 取 file
    return -1;

  if(pfd) *pfd = fd;
  if(pf) *pf = f;
  return 0;
}
```

```
參數安全檢查的層次：

  argint()  → 地址在行程範圍內？
  argptr()  → 指標 + size 在行程範圍內？
  argstr()  → 字串有 NUL 結尾？不超出行程範圍？
  argfd()   → fd 在 [0, NOFILE)？行程有開這個 fd？

  每一層都不信任 user 給的值！
  這就是「永遠不要相信用戶輸入」的核心安全原則。
```

---

## 📊 syscall 全家福

```
syscall    │ 號碼 │ 實現位置     │ 說明
───────────┼──────┼─────────────┼──────────────────
fork       │  1   │ sysproc.c   │ 複製行程
exit       │  2   │ sysproc.c   │ 結束行程
wait       │  3   │ sysproc.c   │ 等子行程結束
pipe       │  4   │ sysfile.c   │ 建立管道
read       │  5   │ sysfile.c   │ 讀檔案/裝置
kill       │  6   │ sysproc.c   │ 殺掉行程
exec       │  7   │ sysfile.c   │ 載入新程式執行
fstat      │  8   │ sysfile.c   │ 取檔案狀態
chdir      │  9   │ sysfile.c   │ 切換工作目錄
dup        │ 10   │ sysfile.c   │ 複製 fd
getpid     │ 11   │ sysproc.c   │ 取得 PID
sbrk       │ 12   │ sysproc.c   │ 增減記憶體
sleep      │ 13   │ sysproc.c   │ 睡眠 N 個 tick
uptime     │ 14   │ sysproc.c   │ 取得開機時間
open       │ 15   │ sysfile.c   │ 開啟檔案
write      │ 16   │ sysfile.c   │ 寫檔案/裝置
mknod      │ 17   │ sysfile.c   │ 建立裝置檔
unlink     │ 18   │ sysfile.c   │ 刪除檔案
link       │ 19   │ sysfile.c   │ 建立硬連結
mkdir      │ 20   │ sysfile.c   │ 建立目錄
close      │ 21   │ sysfile.c   │ 關閉 fd
```

---

## 💻【實作】新增自訂 syscall：`getcount`

在 xv6 裡新增一個 syscall `getcount()`，回傳目前行程呼叫 syscall 的總次數。

### 概覽：要改哪些檔案

```
要改 7 個檔案（按順序）：

1. syscall.h     → 新增 SYS_getcount 號碼（22）
2. syscall.c     → 新增分派表 entry + 計數邏輯
3. sysproc.c     → 實現 sys_getcount()
4. proc.h        → 在 struct proc 加 syscall_count 欄位
5. usys.S        → 新增 user-space wrapper
6. user.h        → 新增 user-space 函數宣告
7. Makefile      → 新增測試程式 getcounttest

另外新增：
8. getcounttest.c → 測試程式
```

### 步驟 1：定義 syscall 號碼

```c
// syscall.h — 加在最後面
#define SYS_getcount 22
```

### 步驟 2：在 struct proc 加計數器

```c
// proc.h — 在 struct proc 裡加一行
struct proc {
  // ... 原有欄位 ...
  int syscall_count;         // 📊 syscall 呼叫次數
};
```

### 步驟 3：在 syscall() 裡計數

```c
// syscall.c — 修改 syscall() 函數

extern int sys_getcount(void);  // 新增宣告

static int (*syscalls[])(void) = {
  // ... 原有的 ...
  [SYS_getcount] sys_getcount,  // 新增
};

void
syscall(void)
{
  int num;
  struct proc *curproc = myproc();

  num = curproc->tf->eax;
  if(num > 0 && num < NELEM(syscalls) && syscalls[num]) {
    curproc->syscall_count++;    // 🔑 每次 syscall 都計數！
    curproc->tf->eax = syscalls[num]();
  } else {
    cprintf("%d %s: unknown sys call %d\n",
            curproc->pid, curproc->name, num);
    curproc->tf->eax = -1;
  }
}
```

### 步驟 4：實現 sys_getcount()

```c
// sysproc.c — 加在最後面
int
sys_getcount(void)
{
  return myproc()->syscall_count;
}
```

### 步驟 5：User-space 包裝

```asm
;; usys.S — 加在最後面
SYSCALL(getcount)
```

```c
// user.h — 加在 system call 宣告區
int getcount(void);
```

### 步驟 6：測試程式

```c
// getcounttest.c
#include "types.h"
#include "stat.h"
#include "user.h"

int
main(void)
{
  printf(1, "=== getcount syscall 測試 ===\n");

  int c1 = getcount();
  printf(1, "第一次 getcount: %d\n", c1);

  // 做一些 syscall
  getpid();
  getpid();
  getpid();
  uptime();

  int c2 = getcount();
  printf(1, "做了 4 個 syscall 後: %d\n", c2);
  printf(1, "差值: %d（應該 >= 5，因為 getcount 本身也算）\n", c2 - c1);

  printf(1, "=== 測試完成 ===\n");
  exit();
}
```

### 步驟 7：修改 Makefile

```makefile
# Makefile — 在 UPROGS 列表加上
_getcounttest\
```

### 完整 patch

完整的改動 patch 在 `examples/ch07-syscall/` 目錄。

---

## 🧠 本章小結

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  syscall 路徑：                                              │
│    user 呼叫 → usys.S (int $0x40) → alltraps → trap()      │
│    → syscall() → sys_xxx() → 結果放 tf->eax → iret 回去    │
│                                                              │
│  參數傳遞：                                                  │
│    不透過 C 函數參數！                                       │
│    user stack 上：[ret addr][arg0][arg1]...                  │
│    kernel 用 argint/argptr/argstr 從 tf->esp 計算偏移讀取   │
│                                                              │
│  安全檢查：                                                  │
│    fetchint → 位址在行程範圍內？                             │
│    fetchstr → 字串有 NUL 結尾？                              │
│    argptr  → 指標 + size 在行程範圍內？                      │
│    argfd   → fd 合法且已開啟？                               │
│    → 永遠不信任 user 給的值！                                │
│                                                              │
│  syscall 分派表：                                            │
│    syscalls[] = 函數指標陣列                                 │
│    用 EAX 的值當 index → O(1) 查找                          │
│                                                              │
│  實現分兩檔：                                                │
│    sysproc.c → 行程相關（fork, exit, kill, getpid, ...）     │
│    sysfile.c → 檔案相關（open, read, write, close, ...）     │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**一句話：** syscall = 把號碼放 EAX → int $0x40 → kernel 查表呼叫對應函數 → 結果放回 EAX → iret 回去。

---

## ⏭️ 下一步

多個行程同時跑，會同時存取共享資料（如 ptable、ticks）。怎麼避免衝突？

→ [08_LOCK.md — 鎖與並行：spinlock 和 sleeplock](08_LOCK.md)
