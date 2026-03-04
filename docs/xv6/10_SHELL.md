# 📚 10 — Shell：一切串起來

> 「Shell = 前台接待。你說『幫我訂會議室、印文件、叫外賣』，接待把每件事翻譯成部門聽得懂的指令，分派出去，等結果回報給你。」

---

## 🏢 比喻：前台接待

```
你（使用者）               前台接待（Shell）           各部門（Kernel）
    │                          │                          │
    │  「ls | grep foo」       │                          │
    │  ──────────────────→     │                          │
    │                          │  解析命令                │
    │                          │  建立管道               │
    │                          │                          │
    │                          │  fork → exec(ls)   ────→│ 列出檔案
    │                          │  fork → exec(grep) ────→│ 過濾
    │                          │                          │
    │                          │  wait → 結果回來        │
    │  ←──────────────────     │                          │
    │  「foo.txt」             │                          │
```

Shell 本身就是一個普通的 user program（`sh.c`），跑在 Ring 3。
它的超能力不是特權，而是**組合**——把 fork、exec、pipe、重導向組合起來。

---

## 📄 `sh.c` 的主迴圈

```c
// sh.c — main()

int
main(void)
{
  static char buf[100];
  int fd;

  // 確保 fd 0, 1, 2 是開的（stdin, stdout, stderr）
  while((fd = open("console", O_RDWR)) >= 0){
    if(fd >= 3){
      close(fd);
      break;
    }
  }

  // 🔑 Shell 的主迴圈：讀命令 → 執行 → 重複
  while(getcmd(buf, sizeof(buf)) >= 0){

    // cd 要在 parent 裡做（不能 fork 出去做）
    if(buf[0] == 'c' && buf[1] == 'd' && buf[2] == ' '){
      buf[strlen(buf)-1] = 0;    // 去掉 \n
      if(chdir(buf+3) < 0)
        printf(2, "cannot cd %s\n", buf+3);
      continue;
    }

    // 🔑 fork + exec + wait 模式
    if(fork1() == 0)              // fork 子行程
      runcmd(parsecmd(buf));      // 子行程：解析並執行命令
    wait();                       // 父行程：等子行程結束
  }
  exit();
}
```

```
Shell 的核心模式：fork + exec + wait

  Shell（PID=2）
    │
    │ fork()
    ├──────────────→ 子行程（PID=3）
    │                    │
    │ wait()             │ exec("ls", ...)
    │ ⏳ 等待             │ → 載入 ls 程式
    │                    │ → ls 跑起來
    │                    │ → ls exit()
    │                    │
    │ wait() 返回 ←──────┘
    │
    │ 印 "$" → 等下一個命令

為什麼要 fork？
  → exec 會取代整個行程的記憶體
  → 如果 shell 自己 exec，shell 就不見了
  → fork 出子行程，讓子行程 exec → shell 安全地等
```

---

## 📄 命令解析與執行

sh.c 把命令解析成樹狀結構，然後遞迴執行：

```c
// 5 種命令類型：
#define EXEC  1    // 一般命令：ls -l
#define REDIR 2    // 重導向：ls > out.txt
#define PIPE  3    // 管道：ls | grep foo
#define LIST  4    // 分號列表：cmd1 ; cmd2
#define BACK  5    // 背景執行：cmd &

// 命令結構（多型：用 type 區分）
struct execcmd  { int type; char *argv[MAXARGS]; ... };
struct redircmd { int type; struct cmd *cmd; char *file; int mode; int fd; };
struct pipecmd  { int type; struct cmd *left; struct cmd *right; };
struct listcmd  { int type; struct cmd *left; struct cmd *right; };
struct backcmd  { int type; struct cmd *cmd; };
```

```
「ls -l | grep foo > out.txt」 解析成：

  pipecmd
  ├─ left: execcmd["ls", "-l"]
  └─ right: redircmd
             ├─ cmd: execcmd["grep", "foo"]
             ├─ file: "out.txt"
             ├─ mode: O_WRONLY|O_CREATE
             └─ fd: 1（stdout）
```

### runcmd：遞迴執行命令

```c
void
runcmd(struct cmd *cmd)
{
  int p[2];
  struct execcmd *ecmd;
  struct redircmd *rcmd;
  struct pipecmd *pcmd;

  if(cmd == 0) exit();

  switch(cmd->type){

  case EXEC:
    // 一般命令：直接 exec
    ecmd = (struct execcmd*)cmd;
    if(ecmd->argv[0] == 0) exit();
    exec(ecmd->argv[0], ecmd->argv);     // 🔑 exec！
    printf(2, "exec %s failed\n", ecmd->argv[0]);
    break;

  case REDIR:
    // 重導向：close(fd) → open(file) → 自動得到被 close 的 fd 號碼
    rcmd = (struct redircmd*)cmd;
    close(rcmd->fd);                      // 關掉 stdout（fd=1）
    if(open(rcmd->file, rcmd->mode) < 0){ // open 自動分配最小 fd = 1
      printf(2, "open %s failed\n", rcmd->file);
      exit();
    }
    runcmd(rcmd->cmd);                    // 遞迴執行（stdout 已指向 file）
    break;

  case PIPE:
    // 管道：fork 兩個子行程，用 pipe 連接
    pcmd = (struct pipecmd*)cmd;
    if(pipe(p) < 0) panic("pipe");

    // 左邊命令：stdout → pipe 寫端
    if(fork1() == 0){
      close(1);           // 關 stdout
      dup(p[1]);           // 複製 pipe 寫端到 fd 1
      close(p[0]);
      close(p[1]);
      runcmd(pcmd->left);  // 執行左邊（輸出進 pipe）
    }

    // 右邊命令：stdin → pipe 讀端
    if(fork1() == 0){
      close(0);           // 關 stdin
      dup(p[0]);           // 複製 pipe 讀端到 fd 0
      close(p[0]);
      close(p[1]);
      runcmd(pcmd->right); // 執行右邊（從 pipe 讀入）
    }

    close(p[0]);
    close(p[1]);
    wait();               // 等兩個子行程
    wait();
    break;

  case LIST:
    // 分號列表：依序執行
    if(fork1() == 0) runcmd(((struct listcmd*)cmd)->left);
    wait();
    runcmd(((struct listcmd*)cmd)->right);
    break;

  case BACK:
    // 背景執行：fork 但不 wait
    if(fork1() == 0) runcmd(((struct backcmd*)cmd)->cmd);
    break;
  }
  exit();
}
```

---

## 🔧 I/O 重導向的精妙設計

```
「ls > out.txt」的執行過程：

1. Shell fork 出子行程
2. 子行程執行：
   close(1);           // 關掉 stdout（fd 1 空出來了）
   open("out.txt", O_WRONLY|O_CREATE);
   // open 回傳最小的可用 fd → 就是 1！
   // 現在 fd 1 = out.txt（而不是 console）
3. exec("ls", ...);
   // ls 照常 write(1, ...)
   // 但 fd 1 已經是 out.txt → 輸出到檔案！
   // ls 完全不知道自己被重導向了 ✨

這就是 Unix 的優雅：
  程式不需要知道輸出到哪裡
  fd 就是抽象層
  shell 透過 close + open + dup 控制 fd 指向
```

---

## 📄 `pipe.c`：管道實現

```c
// pipe.c — 管道：記憶體中的環形緩衝區

#define PIPESIZE 512

struct pipe {
  struct spinlock lock;
  char data[PIPESIZE];     // 512 bytes 的環形 buffer
  uint nread;              // 已讀 bytes 數（只增不減）
  uint nwrite;             // 已寫 bytes 數（只增不減）
  int readopen;            // 讀端還開著？
  int writeopen;           // 寫端還開著？
};

// pipewrite：寫入管道
int pipewrite(struct pipe *p, char *addr, int n)
{
  int i;
  acquire(&p->lock);

  for(i = 0; i < n; i++){
    // pipe 滿了？（寫了 512 bytes 但讀端還沒讀）
    while(p->nwrite == p->nread + PIPESIZE){
      if(p->readopen == 0 || myproc()->killed){
        release(&p->lock);
        return -1;                    // 讀端關了 → broken pipe
      }
      wakeup(&p->nread);             // 叫讀端起來讀
      sleep(&p->nwrite, &p->lock);    // 自己睡等空間
    }
    p->data[p->nwrite++ % PIPESIZE] = addr[i];
    //       ↑ 取模 → 環形！nwrite 超過 512 就繞回來
  }

  wakeup(&p->nread);                 // 寫完了，叫讀端
  release(&p->lock);
  return n;
}

// piperead：從管道讀取
int piperead(struct pipe *p, char *addr, int n)
{
  int i;
  acquire(&p->lock);

  // pipe 空的？等寫端寫東西進來
  while(p->nread == p->nwrite && p->writeopen){
    if(myproc()->killed){
      release(&p->lock);
      return -1;
    }
    sleep(&p->nread, &p->lock);      // 睡，等寫端 wakeup
  }

  // 讀取（可能不到 n bytes）
  for(i = 0; i < n; i++){
    if(p->nread == p->nwrite)        // 沒東西了
      break;
    addr[i] = p->data[p->nread++ % PIPESIZE];
  }

  wakeup(&p->nwrite);               // 讀完了，叫寫端（可能在等空間）
  release(&p->lock);
  return i;
}
```

```
Pipe 的環形 buffer：

  data[0] data[1] data[2] ... data[511]
  ┌───────────────────────────────────┐
  │  H  e  l  l  o  _  W  o  r  l  d │
  └───────────────────────────────────┘
     ↑ nread % 512        ↑ nwrite % 512

  nread = 100, nwrite = 111 → 有 11 bytes 可讀
  nwrite - nread == PIPESIZE → 滿了！
  nwrite == nread → 空的！
```

---

## 🔄 完整流程圖：從按下 Enter 到命令執行完畢

```
你在 xv6 裡輸入 "ls" 然後按 Enter：

┌──────────────────────────────────────────────────────────┐
│ 1. 鍵盤硬體                                              │
│    你按下 'l', 's', Enter                                │
│    鍵盤控制器發出 IRQ 1                                  │
└──────────────┬───────────────────────────────────────────┘
               ↓
┌──────────────────────────────────────────────────────────┐
│ 2. 中斷處理（ch05）                                      │
│    CPU 收到 IRQ 1 → IDT[33] → alltraps → trap()        │
│    trap(): trapno == IRQ_KBD → kbdintr()                │
│    kbdintr → consoleintr → 把字元放入 input buffer      │
│    按到 Enter → wakeup 等待 console 的行程               │
└──────────────┬───────────────────────────────────────────┘
               ↓
┌──────────────────────────────────────────────────────────┐
│ 3. Console read（ch09 檔案系統）                         │
│    Shell 之前呼叫 read(0, buf, n) → sys_read()          │
│    → fileread() → consoleread() → sleep 等字元          │
│    被 wakeup → 讀到 "ls\n" → 回傳給 shell              │
└──────────────┬───────────────────────────────────────────┘
               ↓
┌──────────────────────────────────────────────────────────┐
│ 4. Shell 解析（本章）                                    │
│    sh.c: getcmd() 回傳 "ls\n"                           │
│    parsecmd("ls\n") → execcmd{argv=["ls"]}              │
└──────────────┬───────────────────────────────────────────┘
               ↓
┌──────────────────────────────────────────────────────────┐
│ 5. fork（ch06 行程）                                     │
│    Shell 呼叫 fork() → sys_fork() → fork()              │
│    複製行程：新 pgdir、新 kstack、複製 trapframe        │
│    子行程回傳 0，父行程回傳子 PID                       │
└──────────────┬───────────────────────────────────────────┘
               ↓
┌──────────────────────────────────────────────────────────┐
│ 6. exec（ch07 syscall）                                  │
│    子行程呼叫 exec("ls", argv)                          │
│    sys_exec() → exec()：                                │
│    ├─ 用 namei("ls") 找到 ls 的 inode                   │
│    ├─ 讀 ELF header                                     │
│    ├─ 建立新頁表，載入程式段                            │
│    ├─ 設定 user stack（放 argv）                        │
│    └─ tf->eip = ELF entry → 回到 user 就跑 ls         │
└──────────────┬───────────────────────────────────────────┘
               ↓
┌──────────────────────────────────────────────────────────┐
│ 7. ls 執行 + 排程（ch06）                                │
│    scheduler 選中 ls 行程 → swtch → 開始跑              │
│    ls: 呼叫 open(".") → read → write(1, 結果)          │
│    每個 syscall 都走 ch07 的完整路徑                     │
│    timer 中斷可能 yield → scheduler → 切到其他行程      │
│    → 再切回來繼續跑                                     │
└──────────────┬───────────────────────────────────────────┘
               ↓
┌──────────────────────────────────────────────────────────┐
│ 8. ls exit → Shell 的 wait 返回                          │
│    ls 呼叫 exit() → 設為 ZOMBIE → wakeup parent(Shell) │
│    Shell 的 wait() 被喚醒 → 回收子行程 → 回到主迴圈    │
│    印 "$" → 等下一個命令                                │
└──────────────────────────────────────────────────────────┘
```

**這張圖串起了前面所有章節！**

| 步驟 | 涉及章節 |
|------|---------|
| 鍵盤中斷 | ch05 Trap |
| console read | ch09 Filesystem |
| Shell parse | ch10 Shell |
| fork | ch06 Process |
| exec (syscall) | ch07 Syscall |
| 排程 | ch06 Process |
| lock 保護 | ch08 Lock |

---

## 💻【實作】在 xv6 裡寫一個自訂命令

### `hello.c`：最簡單的命令

```c
// hello.c — 一個自訂 xv6 命令

#include "types.h"
#include "stat.h"
#include "user.h"

int
main(int argc, char *argv[])
{
  printf(1, "Hello from xv6!\n");
  printf(1, "My PID is %d\n", getpid());
  printf(1, "Uptime: %d ticks\n", uptime());

  if(argc > 1){
    printf(1, "You said: ");
    int i;
    for(i = 1; i < argc; i++)
      printf(1, "%s ", argv[i]);
    printf(1, "\n");
  }

  exit();
}
```

### 加入 Makefile

```makefile
# 在 UPROGS 加上：
_hello\
```

### 測試

```bash
cd ~/xv6-public
# 把 hello.c 放到 xv6-public/ 目錄
# 修改 Makefile 的 UPROGS 加上 _hello\
make clean && make && make qemu-nox

# 在 xv6 shell 裡：
$ hello
Hello from xv6!
My PID is 3
Uptime: 42 ticks

$ hello world
Hello from xv6!
My PID is 4
Uptime: 55 ticks
You said: world

# 試試管道：
$ hello | grep PID
My PID is 5

# 試試重導向：
$ hello > out.txt
$ cat out.txt
Hello from xv6!
My PID is 6
Uptime: 80 ticks
```

---

## 📊 xv6 完整架構回顧

```
            User Space (Ring 3)
┌────────────────────────────────────────────┐
│  sh.c    ls.c    cat.c    hello.c    ...  │
│                                            │
│  user.h + usys.S（syscall 包裝）           │
└────────────────────┬───────────────────────┘
                     │ int $0x40
═══════════════════════════════════════════════
                     │
            Kernel Space (Ring 0)
┌────────────────────┴───────────────────────┐
│                                            │
│  trapasm.S → trap.c → syscall.c            │  ← ch05, ch07
│                  │                         │
│          ┌───────┴────────┐                │
│          │                │                │
│     sysproc.c        sysfile.c             │  ← ch07
│     (fork,exit,      (open,read,           │
│      kill,wait)       write,close)         │
│          │                │                │
│          ↓                ↓                │
│       proc.c           file.c              │  ← ch06
│     (scheduler,      (fileread,            │
│      swtch,fork)      filewrite)           │
│          │                │                │
│          │                ↓                │
│          │             fs.c                │  ← ch09
│          │           (inode ops)           │
│          │                │                │
│          │                ↓                │
│          │             log.c               │  ← ch09
│          │           (journaling)          │
│          │                │                │
│          │                ↓                │
│          │             bio.c               │  ← ch09
│          │           (buffer cache)        │
│          │                │                │
│          │                ↓                │
│          │             ide.c               │
│          │           (disk I/O)            │
│          │                                 │
│          └─── spinlock.c / sleeplock.c ────┘  ← ch08
│                （保護所有共享資料）          │
│                                            │
│  vm.c（頁表管理）  kalloc.c（記憶體分配）   │  ← ch04
│                                            │
│  entry.S → main.c（開機初始化）             │  ← ch01-03
│                                            │
└────────────────────────────────────────────┘
```

---

## 🧠 本章小結

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  Shell = 普通的 user program，用 fork+exec+wait 執行命令    │
│                                                              │
│  命令解析：                                                  │
│    parsecmd → 遞迴下降解析器                                │
│    5 種命令：EXEC, REDIR, PIPE, LIST, BACK                  │
│                                                              │
│  I/O 重導向的精妙設計：                                      │
│    close(fd) → open(file) → fd 自動分配到被 close 的號碼    │
│    程式用 write(1, ...) 不需要知道輸出到哪裡               │
│                                                              │
│  Pipe（管道）：                                              │
│    512 bytes 的環形 buffer                                   │
│    用 sleep/wakeup 同步讀寫端                                │
│    fork + dup 把 pipe 連接到 stdin/stdout                    │
│                                                              │
│  完整流程（按 Enter 到命令完成）：                            │
│    鍵盤中斷 → console read → shell parse                   │
│    → fork → exec → 排程 → 執行 → exit → wait              │
│    串起了 ch05-ch10 的所有知識！                             │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**一句話：** Shell 是「膠水」——它不做重活，但把 fork、exec、pipe、重導向組合起來，讓你用一行命令控制整個 OS。

---

## 🎓 全系列完結

恭喜你讀完了 xv6 的完整導覽！

```
ch01 Boot      → BIOS 載入 512 bytes，Real Mode → Protected Mode
ch02 Entry     → 開啟分頁，跳到 main()
ch03 Main      → 初始化各子系統
ch04 Memory    → 頁表、kalloc、虛擬記憶體
ch05 Trap      → 中斷、IDT、trapframe、Ring 切換
ch06 Process   → 行程結構、context switch、scheduler
ch07 Syscall   → User→Kernel 的完整路徑、參數安全檢查
ch08 Lock      → spinlock（xchg 原子操作）、sleeplock、sleep/wakeup
ch09 Filesystem → inode、buffer cache、log（crash recovery）
ch10 Shell     → fork+exec+wait、pipe、重導向、一切串起來
```

**xv6 只有 ~10,000 行 C 程式碼，但包含了作業系統的所有核心概念。**
讀懂它，你就有了理解 Linux、Windows、macOS kernel 的基礎。

🎉
