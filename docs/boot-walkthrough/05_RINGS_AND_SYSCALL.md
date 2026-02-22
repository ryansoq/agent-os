# 05: Ring 特權級與 Syscall — 作業系統的安全基石

> **這不是開機流程的一部分，而是一篇概念補充。**
> 前面幾篇我們看到 GDT、CR0、頁表……但一直沒解釋：**這些東西到底在保護什麼？**
> 答案就是 Ring 特權級機制。

---

## 🎯 這篇教你什麼？

為什麼 Chrome 不能直接讀你的硬碟？  
為什麼病毒不能隨便改 kernel？  
為什麼一個 crash 的 App 不會拖垮整台電腦？

答案就在 CPU 的 **Ring 特權機制**。

這不是作業系統的軟體功能 — 這是 **CPU 矽晶片裡燒死的電路**。

---

## 🏰 大樓比喻 — 一棟辦公大樓

想像一棟 4 層的辦公大樓：

```
┌─────────────────────────────────────────────┐
│  Ring 0 — 地下室（機房）                      │
│  🔧 水電、電梯控制、門禁總開關                │
│  只有大樓管理員（kernel）能進                 │
├─────────────────────────────────────────────┤
│  Ring 1 — 設備層（幾乎沒人用）                │
│  🚪 理論上給「特殊維修人員」                  │
├─────────────────────────────────────────────┤
│  Ring 2 — 設備層（幾乎沒人用）                │
│  🚪 理論上給「進階服務人員」                  │
├─────────────────────────────────────────────┤
│  Ring 3 — 辦公樓層（開放區域）                │
│  🧑‍💻 所有租戶（Chrome、VS Code、你的程式）    │
│  只能用大樓提供的「服務」                     │
└─────────────────────────────────────────────┘
```

**現實中，Linux/Windows 只用 Ring 0 和 Ring 3。** 中間兩層空著。

- **Ring 0**（Kernel Mode）：可以做任何事 — 讀寫硬碟、改頁表、關中斷
- **Ring 3**（User Mode）：只能算算數、讀自己的記憶體、**透過 syscall 請求服務**

**比喻總結**：
> 你是租戶（Ring 3），想寄一封信？按服務鈴（syscall）叫管理員（kernel）幫你寄。
> 你不能自己走進郵局（硬體），因為門鎖住了（CPU 硬體保護）。

---

## Ring 在哪裡設定？— 三個關鍵位置

### 1. CPL（Current Privilege Level）— 你的識別證

CPL 就是 **「你現在是誰」**。存在 `CS`（Code Segment）暫存器的最低 2 bits。

```
CS Register (16 bits):
┌──────────────────────────┬─────┐
│    Segment Selector      │ CPL │   ← 最低 2 bits
│     (bits 15-2)          │(1:0)│
└──────────────────────────┴─────┘
                             ▲
                             │
                        00 = Ring 0 (kernel)
                        01 = Ring 1 (未使用)
                        10 = Ring 2 (未使用)
                        11 = Ring 3 (user)
```

**比喻**：CPL 是你掛在胸前的識別證。  
- 開機時 BIOS 在 Ring 0 啟動 → kernel 接手，天生 Ring 0  
- kernel 準備好 user process 後，用 `iret`/`sysret` **故意降級到 Ring 3**  
- 一旦到了 Ring 3，你就 **回不去了**（除非走 syscall）

### 2. DPL（Descriptor Privilege Level）— 門上的等級

DPL 是寫在 **GDT entry** 裡的，代表 **「這個段需要什麼等級才能用」**。

```
GDT Entry 的 Access Byte (8 bits):
┌───┬────┬───┬────┬────┬───┬───┬───┐
│ P │ DPL    │ S │ Type              │
│   │(2 bits)│   │                   │
└───┴────┴───┴────┴────┴───┴───┴───┘
  7   6  5   4    3    2   1   0

  P   = Present（段是否存在）
  DPL = Descriptor Privilege Level
        00 = 只有 Ring 0 能用
        11 = Ring 3 也能用
  S   = 系統段(0) / 程式碼或資料段(1)
  Type = 段的類型（可讀/可寫/可執行...）
```

**比喻**：DPL 是門上貼的標籤 —「本房間僅限管理員進入」。
- Kernel 的 code segment → DPL = 00（管理員專用）
- User 的 code segment → DPL = 11（一般租戶可用）

### 3. CPU 硬體自動檢查 — 每一次都查

**這不是軟體檢查，是電路級別的。**

CPU 執行每一條指令時都會做：

```
if (CPL > DPL) {
    觸發 #GP (General Protection Fault)
    → kernel 收到異常 → 通常直接殺掉這個 process
}
```

你沒辦法「跳過」這個檢查，因為它在 CPU 的解碼電路裡。  
不是 kernel 在查你 — 是 **矽晶片在查你**。

**比喻**：不是保全在門口查證件（軟體可以騙），是 **門本身認不對的卡就不會開**（硬體）。

---

## 🔒 為什麼 User 拿不到 Ring 0？— 四次闖關失敗

假設你是一個壞人（惡意程式），在 Ring 3 運行。你想拿到 Ring 0 的權限。

### 嘗試 1: 直接改 CS 暫存器

```nasm
mov ax, 0x08      ; Ring 0 的 kernel code segment selector
mov cs, ax        ; ❌ #GP (General Protection Fault)
```

**結果**：CPU 立刻觸發 #GP 異常。因為你 CPL = 3，你試圖載入一個 DPL = 0 的段。

**比喻**：偷改識別證 → 識別證是金屬刻的（硬體），你沒工具改。  
CS 暫存器不能被一般 `mov` 指令任意修改 — CPU 會在載入時檢查權限。

### 嘗試 2: Far jump 到 Ring 0 的程式碼

```nasm
jmp 0x08:0xSOME_KERNEL_ADDRESS  ; ❌ #GP
```

**結果**：一樣 #GP。Far jump 也要過 CPL vs DPL 檢查。

**比喻**：假裝管理員直接闖進機房 → 每扇門都有 CPU 警衛即時驗證你的身份證。  
不管你怎麼跑、怎麼跳，每扇門（每次段切換）都會查你的 CPL。

### 嘗試 3: 直接寫 GDT 改權限

「如果 DPL 是門上的標籤，我直接把標籤撕掉改成 Ring 3 不就好了？」

```nasm
; 假設我知道 GDT 在記憶體哪裡
mov byte [GDT_BASE + offset], 0xFA  ; 把 DPL 改成 11
; ❌ Page Fault — 這塊記憶體被頁表標記為 Supervisor only
```

**結果**：Page Fault。GDT 所在的記憶體被頁表標記為 Supervisor only（U/S = 0）。Ring 3 的程式根本讀不到那塊記憶體。

**比喻**：想偷門禁卡 → 門禁卡鎖在管理室（kernel memory），管理室的門也鎖著（頁表保護）。

### 嘗試 4: 改 CR0 / CR3 / GDTR

「那我直接改 CPU 的控制暫存器，關掉保護模式不就好了？」

```nasm
mov eax, cr0
and eax, ~1        ; 關掉 PE bit (Protection Enable)
mov cr0, eax       ; ❌ #GP — 這是特權指令
```

**結果**：#GP。`mov cr0`、`mov cr3`、`lgdt`、`lidt` 全都是 **特權指令（privileged instructions）**，只有 Ring 0 能執行。

**比喻**：想改門禁系統的設定 → 設定面板在機房裡（Ring 0 才能碰），你還是進不去機房。

### 四條路全死了！

```
偷改識別證    → 識別證是硬體刻的     ❌
假裝管理員    → 每扇門都有警衛       ❌
偷改門禁卡    → 門禁卡鎖在管理室     ❌
改系統設定    → 設定工具也鎖住了     ❌
```

**這就是為什麼 Ring 機制這麼強 — 它是自我封閉的。**  
Ring 0 的保護機制本身也需要 Ring 0 才能修改。  
形成了一個 **不可破的邏輯環**（除非有硬體漏洞）。

---

## ✅ 唯一合法途徑：Syscall（服務鈴）

既然你不能自己進機房，那要怎麼做需要特權的事（讀檔案、開網路、分配記憶體）？

**按服務鈴。**

### syscall 指令做了什麼？

```
User (Ring 3)                          Kernel (Ring 0)
──────────────                         ──────────────

write(fd, buf, len)
      │
      │  libc 把參數放進暫存器：
      │  rax = __NR_write (系統呼叫號)
      │  rdi = fd
      │  rsi = buf
      │  rdx = len
      │
      ▼
  syscall 指令 ───────────────────────► entry_SYSCALL_64:
  ┌──────────────────────┐                │
  │ CPU 硬體自動做：      │                ▼
  │ 1. CPL: 3 → 0        │           1. swapgs（切到 kernel 的資料）
  │ 2. RIP → RCX (保存)  │           2. 保存 user 的 stack pointer
  │ 3. RFLAGS → R11      │           3. 切到 kernel stack
  │ 4. RIP = MSR_LSTAR   │           4. 查 syscall table
  │    (跳到 kernel 入口) │           5. 呼叫 sys_write()
  └──────────────────────┘           6. 執行完畢
                                          │
  回到 Ring 3 ◄──────────────────── sysret 指令
  ┌──────────────────────┐          ┌──────────────────────┐
  │ CPU 硬體自動做：      │          │ CPU 硬體自動做：      │
  │ 1. RIP = RCX (還原)  │          │ 1. CPL: 0 → 3        │
  │ 2. RFLAGS = R11      │          │ 2. 恢復 user context  │
  └──────────────────────┘          └──────────────────────┘
```

### 為什麼 syscall 是安全的？

1. **入口地址寫在 MSR**（Model Specific Register）  
   `MSR_LSTAR`（地址 `0xC0000082`）存著 syscall 的入口地址。  
   只有 Ring 0 能寫 MSR → 你不能把入口改成你自己的 code。

2. **你只能走 kernel 安排的路**  
   syscall 跳到的是 `entry_SYSCALL_64`，不是你想去的任意地址。  
   kernel 會驗證你的每一個參數。

3. **kernel 隨時可以拒絕你**  
   你說 `write(fd, buf, len)` → kernel 會檢查：
   - fd 是你的嗎？
   - buf 指向的記憶體你有權限讀嗎？
   - 這個檔案你有寫入權限嗎？

**比喻**：服務鈴只會通知前台，不會把鑰匙給你。  
你按鈴（syscall）→ 管理員來了 → 你說「幫我寄這封信」→ 管理員檢查信合不合規 → 幫你寄（或拒絕）→ 管理員回去機房。  
**全程你都沒進過機房。**

### Linux 真實原始碼：syscall entry

```asm
// arch/x86/entry/entry_64.S (Linux 6.x)

SYM_CODE_START(entry_SYSCALL_64)
    swapgs
    // 🔑 swapgs: 用 MSR 裡存的 kernel GS base 替換掉 user 的 GS base
    //    這樣 kernel 才能存取 per-CPU 資料結構

    movq    %rsp, PER_CPU_VAR(cpu_tss_rw + TSS_sp2)
    // 🔑 把 user 的 stack pointer 存起來（不然等下切 stack 就丟了）

    movq    PER_CPU_VAR(pcpu_hot + X86_top_of_stack), %rsp
    // 🔑 切到 kernel stack！
    //    從現在開始，我們在 kernel 的 stack 上執行
    //    user 的 stack 不可信（可能被竄改），所以一定要切

    pushq   $__USER_DS                  // 保存 user SS
    pushq   PER_CPU_VAR(cpu_tss_rw + TSS_sp2)  // 保存 user RSP
    pushq   %r11                        // 保存 RFLAGS (syscall 存在 R11)
    pushq   $__USER_CS                  // 保存 user CS
    pushq   %rcx                        // 保存 user RIP (syscall 存在 RCX)

    // 接下來：查 sys_call_table[rax]，呼叫對應的 handler
    // ...
SYM_CODE_END(entry_SYSCALL_64)
```

**注意 kernel 的第一件事是切 stack。** 因為 user 的 stack 可能被惡意修改，kernel 絕不信任它。

---

## 🗺️ 頁表 + Ring = 雙重保護

Ring 不是唯一的保護機制。頁表提供了 **第二層保護**。

### 頁表的 U/S bit

每個頁表 entry 都有一個 U/S（User/Supervisor）bit：

```
頁表 Entry (64-bit):
┌────────────────────────────────┬───┬───┬───┬───┐
│         實體地址 (bits 51-12)  │...│U/S│R/W│ P │
└────────────────────────────────┴───┴───┴───┴───┘
  bits 63                          2   1   0
                                   ↑
                              0 = Supervisor only
                                  只有 Ring 0 能存取
                              1 = User accessible
                                  Ring 3 也能存取
```

### Ring × 頁表 = 交叉保護

```
                    頁表 U/S = 0          頁表 U/S = 1
                  (Supervisor only)     (User accessible)
                ┌───────────────────┬───────────────────┐
  Ring 0        │    ✅ 可存取       │    ✅ 可存取       │
  (kernel)      │                   │                   │
                ├───────────────────┼───────────────────┤
  Ring 3        │    ❌ Page Fault   │    ✅ 可存取       │
  (user)        │                   │                   │
                └───────────────────┴───────────────────┘
```

**比喻**：Ring 是「身份證」，頁表是「每間房間的門鎖」。

- Ring 決定你是什麼人（管理員 vs 租戶）
- 頁表決定每間房間誰能進
- 即使你有 Ring 3 身份證，頁表也可以額外限制你能進哪些房間
- **雙重保護！** 兩關都要過才能存取記憶體

這也解釋了為什麼 [嘗試 3](#嘗試-3-直接寫-gdt-改權限) 會失敗 — GDT 所在的記憶體頁面被標記為 U/S = 0，Ring 3 碰不到。

---

## 🔄 回顧：這些概念在開機流程中的對應

| 概念 | 在哪裡設定的？ | 對應教學檔案 |
|------|--------------|-------------|
| GDT（定義段的 DPL） | `setup_gdt()` | 02_pm.c |
| CR0.PE（開啟保護模式） | `protected_mode_jump()` | 03_pmjump.S |
| 頁表（U/S bit） | `__startup_64()` | 04_head_64.S |
| MSR_LSTAR（syscall 入口） | `syscall_init()` | kernel 初始化階段 |

開機流程其實就是在 **一層一層蓋起這棟大樓的保全系統**。

---

## 🤔 思考題

1. **如果 CPU 沒有 Ring 機制，作業系統要怎麼保護自己？**  
   （提示：早期的 MS-DOS 就沒有保護，任何程式都能做任何事）

2. **為什麼 Ring 1 和 Ring 2 幾乎沒人用？**  
   （提示：Linux 只用 0 和 3。x86 的分段保護太複雜，大家都用分頁保護代替）

3. **虛擬化（VMX）引入了 Ring -1，這是什麼意思？**  
   （提示：Hypervisor 需要比 kernel 更高的權限。Intel VT-x 的 root mode）

4. **ARM 的 EL0-EL3 和 x86 的 Ring 有什麼對應關係？**  
   （EL0 ≈ Ring 3, EL1 ≈ Ring 0, EL2 ≈ Hypervisor, EL3 ≈ Secure Monitor）

---

## 📚 延伸閱讀

- **Intel SDM Vol.3 Chapter 5: Protection** — Ring 機制的權威參考
- **Linux 原始碼: `arch/x86/entry/entry_64.S`** — syscall 入口的真實實作
- **Linux 原始碼: `arch/x86/kernel/cpu/common.c` → `syscall_init()`** — 設定 MSR_LSTAR
- **OSDev Wiki: Security** — https://wiki.osdev.org/Security

---

*下一篇：繼續回到開機流程，看 kernel 怎麼初始化所有子系統 →*
