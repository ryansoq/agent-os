# 📚 06 — 進入 64-bit Long Mode

> 從 32-bit 到 64-bit，CPU 的最後一次進化。

---

## 🛤️ 為什麼需要這麼多步驟？

從 Real Mode 到 Long Mode，CPU 經歷了三次模式切換：

```
Real Mode (16-bit)
    │ CR0.PE = 1 + Far Jump
    ↓
Protected Mode (32-bit)
    │ PAE + EFER.LME + CR0.PG + Far Jump
    ↓
Long Mode (64-bit)
```

**為什麼不能直接從 Real Mode 跳到 Long Mode？**

因為 CPU 的設計是累進的——每個模式的啟用都依賴前一個模式的基礎設施：

1. **Protected Mode** 需要 GDT → 必須先從 Real Mode 設定
2. **Long Mode** 需要分頁 + PAE → 必須在 Protected Mode 中建立頁表
3. 每次模式切換都需要 Far Jump 來更新 CS

**比喻：** 就像蓋房子——你不能直接蓋 3 樓，必須先有地基（Real Mode → GDT），再蓋 1 樓（Protected Mode → 頁表），最後才能蓋 3 樓（Long Mode）。

---

## 🔧 進入 Long Mode 的完整步驟

```
前置條件（在 Protected Mode 中完成）：
 ✅ GDT 已設定
 ✅ PAE 已啟用（CR4.PAE = 1）
 ✅ 4 級頁表已建立
 ✅ 頁表載入 CR3

進入 Long Mode 的步驟：
 1. 設定 EFER.LME = 1    ← 告訴 CPU「我要 Long Mode」
 2. 設定 CR0.PG = 1       ← 啟用分頁 → Long Mode 自動啟動
 3. Far Jump (CS.L = 1)   ← 真正進入 64-bit 執行模式
```

### Step 1: EFER.LME = 1

**EFER（Extended Feature Enable Register）** 是一個 MSR（Model Specific Register）：

```
EFER（MSR 0xC0000080）

Bit 10   Bit 8    Bit 0
┌──────┬────────┬────────┐
│ LMA  │  LME   │  SCE   │
└──────┴────────┴────────┘

LME (Long Mode Enable) = 1: 準備啟用 Long Mode
LMA (Long Mode Active)  = CPU 自動設定（LME + PG 都為 1 時）
SCE (System Call Enable) = 1: 啟用 SYSCALL/SYSRET 指令
```

```asm
movl    $MSR_EFER, %ecx   # ECX = EFER 的 MSR 編號
rdmsr                      # 讀取 EFER 到 EDX:EAX
btsl    $_EFER_LME, %eax  # 設定 LME 位 = 1
wrmsr                      # 寫回 EFER
```

### Step 2: CR0.PG = 1

```asm
movl    $CR0_STATE, %eax   # CR0_STATE = PE + PG + 其他
movl    %eax, %cr0         # 啟用分頁！
                            # 此刻 LME=1 + PG=1 → CPU 自動設定 LMA=1
                            # → Long Mode 已啟動（但還在 32-bit 相容模式）
```

### Step 3: Far Jump（CS.L = 1）

```asm
leal    rva(startup_64)(%ebp), %eax  # 64-bit 進入點的地址
pushl   $__KERNEL_CS                 # 新的 CS（L bit = 1）
pushl   %eax                        # 跳轉目標
lret                                 # Far Return = Far Jump
                                     # CS 被更新 → CPU 開始 64-bit 執行！
```

---

## 📐 32-bit GDT vs 64-bit GDT（L bit 的差別）

32-bit 和 64-bit 的 GDT entry 格式**幾乎一樣**，唯一的關鍵差別是 **L bit**：

```
GDT Entry 的 Flags（4 bits）：

32-bit Code Segment:    G=1, D=1, L=0, AVL=0
                              ↑ D=1 表示 32-bit
64-bit Code Segment:    G=1, D=0, L=1, AVL=0
                              ↑ D=0   ↑ L=1 表示 64-bit

規則：L=1 時，D 必須 = 0（Intel 規定）
```

```
L bit 的效果：

L = 0, D = 1: CPU 以 32-bit 模式執行程式碼
L = 1, D = 0: CPU 以 64-bit 模式執行程式碼

當 CS 被載入 L=1 的 selector 時，CPU 切換到 64-bit 指令解碼。
這就是 Far Jump 的真正作用——切換 CS 來改變 L bit。
```

---

## 💻 原始碼：startup_32 → startup_64 轉換

```asm
# 檔案：arch/x86/boot/compressed/head_64.S（Linux 6.19.3）

# ===== startup_32：32-bit 進入點 =====
SYM_FUNC_START(startup_32)
    cld                             # 1  清除方向旗標（字串操作向前）
    cli                             # 2  關閉中斷

    # 載入新的 GDT（包含 64-bit segment）
    leal    rva(gdt)(%ebp), %eax    # 3  EAX = GDT 的地址
    movl    %eax, 2(%eax)           # 4  修正 GDT 指標中的地址
    lgdt    (%eax)                  # 5  載入 GDT

    # 重新載入 segment registers
    movl    $__BOOT_DS, %eax        # 6  EAX = 資料段 selector
    movl    %eax, %ds               # 7  更新所有資料段
    movl    %eax, %es
    movl    %eax, %fs
    movl    %eax, %gs
    movl    %eax, %ss

    # ...（建立頁表、啟用 PAE — 見上一章）...

    # ===== 啟用 Long Mode =====

    # Step 1: EFER.LME = 1
    movl    $MSR_EFER, %ecx         # 8  EFER 的 MSR 編號
    rdmsr                           # 9  讀取 EFER
    btsl    $_EFER_LME, %eax       # 10 設定 LME = 1
    wrmsr                           # 11 寫回 EFER

    # Step 2: 準備 Far Jump 的參數
    leal    rva(startup_64)(%ebp), %eax  # 12 64-bit 進入點
    pushl   $__KERNEL_CS                 # 13 CS（L=1 的 64-bit segment）
    pushl   %eax                         # 14 跳轉目標地址

    # Step 3: 啟用分頁 + Far Jump
    movl    $CR0_STATE, %eax        # 15 CR0 = PE + PG + ...
    movl    %eax, %cr0              # 16 🎉 啟用分頁 → Long Mode 啟動！
    lret                            # 17 Far Return → 跳到 startup_64
                                    #    CS 被更新為 __KERNEL_CS（L=1）
                                    #    → CPU 切換到 64-bit 指令解碼

SYM_FUNC_END(startup_32)

# ===== startup_64：64-bit 進入點 =====
    .code64                         # 18 告訴組譯器：以下是 64-bit
    .org 0x200                      # 19 固定在偏移量 0x200（ABI 規定）

SYM_CODE_START(startup_64)
    cld                             # 20 清除方向旗標
    cli                             # 21 關閉中斷

    # 清除所有資料段（64-bit 模式下，段基址被忽略）
    xorl    %eax, %eax              # 22 EAX = 0
    movl    %eax, %ds               # 23 DS = 0
    movl    %eax, %es               # 24 ES = 0
    movl    %eax, %ss               # 25 SS = 0
    movl    %eax, %fs               # 26 FS = 0
    movl    %eax, %gs               # 27 GS = 0

    # 設定堆疊
    leaq    rva(boot_stack_end)(%rbx), %rsp  # 28 RSP = 堆疊頂部

    # ...接下來是解壓縮 kernel、然後跳到真正的 kernel 進入點...

SYM_CODE_END(startup_64)
```

### 狀態轉換圖

```
startup_32（32-bit Protected Mode）
    │
    ├── 載入新 GDT（包含 L=1 的 64-bit segment）
    ├── 建立 4GB Identity Mapping 頁表
    ├── 啟用 PAE（CR4.PAE = 1）
    ├── 頁表載入 CR3
    ├── EFER.LME = 1
    ├── CR0.PG = 1    → Long Mode 啟動（但還在 32-bit 相容模式）
    ├── lret          → Far Jump 到 startup_64
    │                     CS 被載入 __KERNEL_CS（L=1）
    │                     → CPU 切換到 64-bit 指令解碼
    ↓
startup_64（64-bit Long Mode）🎉
    │
    ├── 清除段暫存器
    ├── 設定堆疊
    ├── 解壓縮 kernel
    └── 跳到解壓縮後的 kernel 進入點
```

---

## 📊 模式總結

| 模式 | 位元 | 定址 | 分段 | 分頁 | 保護 |
|------|------|------|------|------|------|
| Real Mode | 16-bit | 1MB | Segment×16+Offset | ❌ | ❌ |
| Protected Mode | 32-bit | 4GB | GDT 查表 | 可選 | ✅ |
| Long Mode | 64-bit | 256TB* | 形同虛設 | 必須 | ✅ |

*48-bit 虛擬地址 = 256TB

---

## 🔑 關鍵概念回顧

| 概念 | 說明 |
|------|------|
| EFER.LME | 設為 1 = 準備啟用 Long Mode |
| CR0.PG | 設為 1 = 啟用分頁（配合 LME → Long Mode 啟動） |
| L bit | GDT entry 的 Long mode 位，L=1 → 64-bit |
| lret | 用 Far Return 來實現 Far Jump（更新 CS） |
| startup_64 | 64-bit 的第一行程式碼 |

---

## ⏭️ 下一步

我們終於進入 64-bit 了！kernel 被解壓縮後，接下來會跳到 **C 語言** 的世界——`start_kernel()`。

這是整個 Linux kernel 真正開始初始化的地方。

start_kernel() 做了什麼？→ [07_START_KERNEL.md](07_START_KERNEL.md)
