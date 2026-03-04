# 🔐 05 — CPL / DPL / RPL：x86 權限機制

> 「你是訪客（Ring 3），想進總經理辦公室（Ring 0）。門禁系統不會讓你刷卡進去——但你可以按對講機請總經理幫你拿東西（syscall）。」

---

## 🏢 先來個比喻：大樓門禁系統

想像一棟辦公大樓，有 4 種門禁等級：

```
┌─────────────────────────────────────────────────┐
│                                                 │
│   Ring 0 — 總經理辦公室（最高權限）              │
│   ┌─────────────────────────────────────────┐   │
│   │  可以做任何事：開關電源、存取所有資料     │   │
│   │  = Kernel Mode                          │   │
│   └─────────────────────────────────────────┘   │
│                                                 │
│   Ring 1, 2 — 主管辦公室（x86 定義了但幾乎沒人用）│
│                                                 │
│   Ring 3 — 大廳（最低權限）                      │
│   ┌─────────────────────────────────────────┐   │
│   │  只能用公共設施，碰不到機密               │   │
│   │  = User Mode                            │   │
│   └─────────────────────────────────────────┘   │
│                                                 │
└─────────────────────────────────────────────────┘
```

x86 用了三個「等級標籤」來實作這套門禁：

| 名稱 | 全名 | 比喻 | 在哪裡 |
|------|------|------|--------|
| **CPL** | Current Privilege Level | 你的**身份證等級** | CS 暫存器的低 2 位 |
| **DPL** | Descriptor Privilege Level | 這扇**門要求的等級** | GDT/IDT entry 裡 |
| **RPL** | Requested Privilege Level | 你**手上拿的通行證等級** | Segment selector 的低 2 位 |

---

## 🎯 三個等級怎麼配合？

### CPL：你現在是誰？

```
CS 暫存器（16 bits）：
┌──────────────────────────┬───┬───┐
│     GDT Index (13 bits)  │ TI│RPL│
└──────────────────────────┴───┴───┘
                                ↑
                            這就是 CPL！
                            00 = Ring 0（kernel）
                            11 = Ring 3（user）
```

- 當 CPU 在跑 kernel code → CS 指向 `SEG_KCODE`（DPL=0）→ **CPL = 0**
- 當 CPU 在跑 user code → CS 指向 `SEG_UCODE`（DPL=3）→ **CPL = 3**

**你不能自己改 CPL！** CPU 只在特定時刻改它（中斷、iret、far call 等）。

### DPL：這扇門要什麼等級？

每個 GDT entry 和 IDT entry 都有一個 DPL 欄位。

**對 GDT（segment descriptor）：**
- DPL = 0 → 只有 Ring 0 能用這個 segment
- DPL = 3 → Ring 0 ~ Ring 3 都能用

**對 IDT（gate descriptor）：**
- DPL = 0 → 只有 Ring 0 能用 `int` 觸發這個中斷
- DPL = 3 → User mode 也能用 `int` 觸發（**syscall 就靠這個！**）

### RPL：通行證上寫的等級

Segment selector 的低 2 位是 RPL。通常 RPL = CPL，但 kernel 可以故意設高一點。

**為什麼需要 RPL？** 防止這種攻擊：

```
惡意 user 程式：
  "kernel 大哥，幫我讀地址 0x80000000 的資料"
  （偷偷傳了一個 RPL=0 的 selector，假裝自己是 kernel）

有了 RPL 檢查：
  kernel 會把 RPL 設成 3（呼叫者的真實等級）
  CPU 檢查：max(CPL, RPL) <= DPL → max(0, 3) = 3 > 0 → ❌ 拒絕！
```

---

## 🔑 權限檢查規則

CPU 在存取 segment 時的檢查：

```
能不能存取這個 segment？

  max(CPL, RPL) <= DPL  →  ✅ 允許
  max(CPL, RPL) >  DPL  →  ❌ General Protection Fault！

例子 1：user 程式存取 user data segment
  CPL=3, RPL=3, DPL=3
  max(3,3) = 3 <= 3  →  ✅

例子 2：user 程式嘗試存取 kernel data segment
  CPL=3, RPL=3, DPL=0
  max(3,3) = 3 > 0   →  ❌ GPF！

例子 3：kernel 存取 kernel data segment
  CPL=0, RPL=0, DPL=0
  max(0,0) = 0 <= 0  →  ✅
```

CPU 在 `int N` 指令時的檢查：

```
能不能觸發這個中斷？

  CPL <= IDT[N].DPL  →  ✅ 允許（然後 CPL 變成 gate 指向的 segment 的 DPL）
  CPL >  IDT[N].DPL  →  ❌ GPF！

xv6 的 IDT 設定：
  中斷 0~63:    DPL = 0  →  只有 kernel 能用 int 觸發
  中斷 64 (T_SYSCALL): DPL = 3  →  user 也能用 int $0x40！

這就是為什麼 user 程式能發 syscall，但不能觸發其他中斷。
```

---

## 💡 特權指令

有些指令只有 Ring 0 能執行：

```
Ring 0 才能用的指令（CPL 必須 = 0）：
┌────────────────────────────────────────────┐
│  cli / sti     關閉/開啟中斷               │
│  lgdt / lidt   載入 GDT/IDT               │
│  ltr           載入 TSS                    │
│  mov CRn       讀寫控制暫存器              │
│  in / out      I/O port 操作（看 IOPL）    │
│  hlt           停止 CPU                    │
│  invlpg        刷新 TLB                    │
└────────────────────────────────────────────┘

Ring 3 也能用的指令：
┌────────────────────────────────────────────┐
│  mov / add / sub / ...   一般運算           │
│  int $N                  觸發中斷（看 IDT DPL）│
│  push / pop / call / ret 堆疊操作           │
└────────────────────────────────────────────┘
```

**如果 Ring 3 執行了特權指令會怎樣？**

→ CPU 產生 **General Protection Fault（#GP, 中斷 13）**
→ 跳到 IDT[13] 的 handler
→ xv6 的 handler 會印錯誤訊息然後殺掉那個行程

---

## 💻【實作】在 xv6 裡試試看！

### 實驗 1：Ring 3 執行 `cli` → 💥 crash

我們寫一個 xv6 user 程式，在 Ring 3 執行 `cli`（關中斷）：

**檔案：`clitest.c`**（放到 `~/xv6-public/`）

```c
// clitest.c — 在 Ring 3 嘗試執行特權指令
// 預期結果：被 kernel 殺掉（General Protection Fault）

#include "types.h"
#include "stat.h"
#include "user.h"

int
main(int argc, char *argv[])
{
  printf(1, "我現在是 Ring 3 (user mode)\n");
  printf(1, "嘗試執行 cli（關中斷）...\n");

  // cli 是 Ring 0 才能執行的指令
  // Ring 3 執行它 → CPU 觸發 #GP（中斷 13）
  asm volatile("cli");

  // 這行永遠不會執行到
  printf(1, "你不應該看到這行！\n");
  exit();
}
```

**檔案：`syscalltest.c`**（放到 `~/xv6-public/`）

```c
// syscalltest.c — 透過 syscall 請 kernel 幫忙
// 預期結果：成功！

#include "types.h"
#include "stat.h"
#include "user.h"

int
main(int argc, char *argv[])
{
  printf(1, "我現在是 Ring 3 (user mode)\n");
  printf(1, "透過 syscall 請 kernel 幫忙取得 PID...\n");

  // getpid() 內部做的事：
  //   mov $SYS_getpid, %eax
  //   int $0x40              ← 觸發中斷 64
  //   ret
  //
  // CPU 檢查：CPL(3) <= IDT[64].DPL(3) → ✅ 允許！
  // 然後 CPL 切到 0，跳到 kernel 的 trap handler
  int pid = getpid();

  printf(1, "成功！我的 PID = %d\n", pid);
  printf(1, "kernel 幫我做完事後，用 iret 把我送回 Ring 3\n");
  exit();
}
```

### 加到 xv6 的步驟

```bash
cd ~/xv6-public

# 1. 把兩個檔案放進去（已由 example 複製）

# 2. 修改 Makefile，在 UPROGS 加上：
#    _clitest\
#    _syscalltest\

# 3. 編譯跑起來
make clean && make && make qemu-nox CPUS=1
```

在 xv6 shell 裡：

```
$ syscalltest
我現在是 Ring 3 (user mode)
透過 syscall 請 kernel 幫忙取得 PID...
成功！我的 PID = 3
kernel 幫我做完事後，用 iret 把我送回 Ring 3

$ clitest
我現在是 Ring 3 (user mode)
嘗試執行 cli（關中斷）...
pid 4 clitest: trap 13 err 0 on cpu 0 eip 0x... addr 0x...—kill proc
```

### 🔍 發生了什麼？

```
syscalltest（成功的路）：           clitest（失敗的路）：

User (Ring 3)                     User (Ring 3)
  │ int $0x40                       │ cli
  │ CPU 檢查 IDT[64].DPL = 3       │ CPU 檢查 CPL
  │ CPL(3) <= 3 ✅                  │ CPL(3) != 0
  ▼                                 ▼
Kernel (Ring 0)                   CPU 觸發 #GP（中斷 13）
  │ syscall()                       │
  │ 取得 PID                        ▼
  │ iret（回 Ring 3）              Kernel trap handler
  ▼                                 │ 印錯誤訊息
User (Ring 3)                       │ 殺掉行程
  │ 拿到結果 ✅                      ▼
  ▼                               行程消失 💀
```

---

## 📖 xv6 源碼：GDT 的 5 個 entry

現在你理解了「為什麼」，來看 xv6 怎麼實作。

### seginit()（vm.c）

```c
void
seginit(void)
{
  struct cpu *c;
  c = &cpus[cpuid()];

  //            型別              base  limit       DPL
  //            ─────────────     ────  ──────────  ───
  c->gdt[SEG_KCODE] = SEG(STA_X|STA_R, 0, 0xffffffff, 0);
  // Entry 1 (selector 0x08): Kernel Code Segment
  // DPL = 0 → 只有 Ring 0 能用
  // 型別 = 可執行 + 可讀
  // 當 CS = 0x08 時，CPL = 0

  c->gdt[SEG_KDATA] = SEG(STA_W, 0, 0xffffffff, 0);
  // Entry 2 (selector 0x10): Kernel Data Segment
  // DPL = 0 → 只有 Ring 0 能用
  // 當 DS/SS = 0x10 時，kernel 在存取資料

  c->gdt[SEG_UCODE] = SEG(STA_X|STA_R, 0, 0xffffffff, DPL_USER);
  // Entry 3 (selector 0x18|3 = 0x1B): User Code Segment
  // DPL = 3 → Ring 3 可以用
  // 當 CS = 0x1B 時，CPL = 3（user mode）
  //                       ↑
  //                  低 2 位 = RPL = 3

  c->gdt[SEG_UDATA] = SEG(STA_W, 0, 0xffffffff, DPL_USER);
  // Entry 4 (selector 0x20|3 = 0x23): User Data Segment
  // DPL = 3 → Ring 3 可以用

  lgdt(c->gdt, sizeof(c->gdt));
  // 載入 GDT 到 GDTR
}
```

```
xv6 的 GDT 全景圖：

Index  Selector  名稱          DPL   用途
─────  ────────  ────────────  ────  ──────────────
  0    0x00      null          -     CPU 規定要有
  1    0x08      SEG_KCODE     0     Kernel code（CS=0x08 → CPL=0）
  2    0x10      SEG_KDATA     0     Kernel data（DS=0x10）
  3    0x1B*     SEG_UCODE     3     User code（CS=0x1B → CPL=3）
  4    0x23*     SEG_UDATA     3     User data（DS=0x23）
  5    ---       SEG_TSS       0     Task State Segment

* selector = (index << 3) | RPL，user 的 RPL = 3
  所以 SEG_UCODE selector = (3 << 3) | 3 = 0x1B
```

### 為什麼不能共用 code segment？

注意 `seginit()` 裡的註解：

```
// Cannot share a CODE descriptor for both kernel and user
// because it would have to have DPL_USR, but the CPU forbids
// an interrupt from CPL=0 to DPL=3.
```

如果只有一個 DPL=3 的 code segment，那 kernel 也會是 CPL=3（因為 CS 的 DPL 決定 CPL）。
那 kernel 就不是 Ring 0 了——什麼特權指令都不能用。

所以必須有兩套：DPL=0 給 kernel，DPL=3 給 user。

---

## 📖 IDT：哪些中斷 user 能觸發？

### tvinit()（trap.c）

```c
void
tvinit(void)
{
  int i;

  // 預設：所有中斷的 gate DPL = 0
  // → user mode 的 int 指令觸發不了
  for(i = 0; i < 256; i++)
    SETGATE(idt[i], 0, SEG_KCODE<<3, vectors[i], 0);
  //                                              ↑
  //                                          DPL = 0

  // 唯一的例外：T_SYSCALL（64）的 gate DPL = 3
  // → user mode 可以用 int $0x40 觸發！
  SETGATE(idt[T_SYSCALL], 1, SEG_KCODE<<3, vectors[T_SYSCALL], DPL_USER);
  //                                                            ↑
  //                                                        DPL = 3
}
```

```
IDT 的權限設計：

中斷號  DPL  誰能用 int 觸發？     用途
──────  ───  ──────────────────  ────────────
  0     0    只有 kernel          除法錯誤
  13    0    只有 kernel          General Protection Fault
  14    0    只有 kernel          Page Fault
  32    0    只有 kernel          Timer（硬體觸發，不受 DPL 限制）
  64    3    ✅ User 也能！        系統呼叫（int $0x40）
  ...

⚠️ 重要：硬體中斷（timer、鍵盤）不經過 IDT 的 DPL 檢查
   只有 int 指令才會檢查 DPL
   所以 timer 中斷（DPL=0）仍然能打斷 user 程式
```

---

## 📖 Syscall 的完整 Ring 切換流程

把所有東西串起來：

```
User 程式（Ring 3）
  │
  │ getpid() → 展開成：
  │   mov $SYS_getpid, %eax    # syscall 號碼放 EAX
  │   int $0x40                 # 觸發中斷 64
  │
  ▼ ──── CPU 做了什麼？────────────────────────
  │
  │ 1. 檢查權限：CPL(3) <= IDT[64].DPL(3) → ✅
  │
  │ 2. 因為要從 Ring 3 → Ring 0，CPU 切換 stack：
  │    - 從 TSS 取出 Ring 0 的 SS 和 ESP
  │    - SS = SEG_KDATA << 3 = 0x10
  │    - ESP = proc->kstack + KSTACKSIZE
  │
  │ 3. 在新 stack 上 push（自動的！）：
  │    ┌──────────────┐
  │    │ old SS       │ ← user 的 SS（0x23）
  │    │ old ESP      │ ← user 的堆疊指標
  │    │ old EFLAGS   │ ← 包含 IF 旗標
  │    │ old CS       │ ← user 的 CS（0x1B）← CPL 就藏在這！
  │    │ old EIP      │ ← int 指令的下一條指令
  │    └──────────────┘
  │
  │ 4. CS = IDT[64].selector = SEG_KCODE<<3 = 0x08
  │    → CPL 變成 0！現在是 Ring 0！
  │
  │ 5. EIP = vectors[64] 的地址
  │    → 跳到 vector64 → alltraps → trap()
  │
  ▼ ──── 現在在 Kernel（Ring 0）──────────────
  │
  │ alltraps: 保存所有暫存器（建立 trapframe）
  │ trap(): 看到 trapno == T_SYSCALL → 呼叫 syscall()
  │ syscall(): 從 EAX 取出 syscall 號碼 → 呼叫對應函式
  │ 回到 trap() → 回到 alltraps
  │
  │ trapret:
  │   popal / popl gs, fs, es, ds   # 恢復暫存器
  │   iret                           # 🔑 關鍵指令！
  │
  ▼ ──── iret 做了什麼？──────────────────────
  │
  │ 1. 從 stack pop 出 EIP, CS, EFLAGS
  │ 2. CS = 0x1B → CPL = 3（回到 Ring 3！）
  │ 3. 因為 CPL 變了（0→3），再 pop SS 和 ESP
  │    → 切回 user 的堆疊
  │ 4. CPU 繼續從 int $0x40 的下一條指令執行
  │
  ▼ ──── 回到 User（Ring 3）─────────────────
  │
  │ ret    # getpid() 回傳，EAX 裡有 PID
  ▼
  程式繼續跑 ✅
```

### iret 的魔法

`iret` 不只是「從中斷返回」，它是 **CPU 唯一正規的降權方式**：

```
iret 根據 stack 上 CS 的 RPL 決定要不要切換 stack：

  如果 pop 出的 CS.RPL == 當前 CPL：
    → 只恢復 EIP, CS, EFLAGS（同權限返回）

  如果 pop 出的 CS.RPL > 當前 CPL（降權，例如 0→3）：
    → 恢復 EIP, CS, EFLAGS
    → 再 pop SS, ESP（切回低權限的堆疊）
```

---

## 📖 TSS：Ring 切換時的堆疊在哪？

從 Ring 3 → Ring 0 時，CPU 需要知道 Ring 0 的堆疊在哪。答案在 **TSS**（Task State Segment）：

```c
// proc.c 裡的 switchuvm()
void
switchuvm(struct proc *p)
{
  // ...
  mycpu()->ts.ss0 = SEG_KDATA << 3;    // Ring 0 的 SS = 0x10
  mycpu()->ts.esp0 = (uint)p->kstack + KSTACKSIZE;
                                          // Ring 0 的 ESP = kernel stack 頂端
  // ...
}
```

```
每個行程有自己的 kernel stack：

User Stack（Ring 3）         Kernel Stack（Ring 0）
┌────────────────┐          ┌────────────────┐
│  argv, argc    │          │                │
│  local vars    │          │  trapframe     │ ← int 進來時 CPU 自動 push
│  ...           │          │  context       │ ← context switch 時用
│                │          │                │
│  ESP ──────────│──┐       │  ESP0 ←────────│──── TSS.esp0
└────────────────┘  │       └────────────────┘
                    │              ↑
                    │              │
                    └── int $0x40 時，CPU 從 TSS 取 SS0:ESP0
                        然後 push old SS, ESP, EFLAGS, CS, EIP
```

---

## 🧪 完整實驗步驟

### 把測試程式加到 xv6

```bash
cd ~/xv6-public
```

1. 複製測試檔案：
```bash
cp ~/agentos-builder/docs/xv6/examples/ch05-privilege/clitest.c .
cp ~/agentos-builder/docs/xv6/examples/ch05-privilege/syscalltest.c .
```

2. 修改 `Makefile`，在 `UPROGS` 的 `_zombie\` 後面加上：
```
	_clitest\
	_syscalltest\
```

3. 編譯 & 跑：
```bash
make clean && make && make qemu-nox CPUS=1
```

4. 在 xv6 shell 裡：
```
$ syscalltest     ← 成功拿到 PID
$ clitest         ← trap 13 被殺掉
```

---

## 🧠 本章小結

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│  CPL = 你現在的身份（CS 的低 2 位）                         │
│        0 = kernel, 3 = user                                │
│                                                            │
│  DPL = 門要求的等級（GDT/IDT entry 裡）                     │
│        GDT: 決定誰能用這個 segment                          │
│        IDT: 決定誰能用 int 指令觸發這個中斷                  │
│                                                            │
│  RPL = 通行證的等級（selector 的低 2 位）                    │
│        防止 kernel 被騙去幫 user 做壞事                     │
│                                                            │
│  權限檢查：max(CPL, RPL) <= DPL → 允許                     │
│                                                            │
│  進入 kernel：int $0x40 → CPU 檢查 IDT DPL → 切 stack     │
│              → CPL 變 0 → 跑 kernel code                  │
│                                                            │
│  回到 user：  iret → pop CS（RPL=3）→ CPL 變 3            │
│              → 切回 user stack                             │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**一句話：** Ring 3 想做 Ring 0 的事？乖乖用 `int $0x40` 請 kernel 幫你。直接動手？`#GP` 殺掉你。

---

## ⏭️ 下一章

了解了權限機制，接下來看 IDT 和 trap 的完整流程：

➡️ [06 中斷與 Trap](06_TRAP.md)
