# 📚 04 — 進入 Protected Mode：歷史性的一跳

> CR0.PE = 1，CPU 從 1978 年跳到 1985 年。

---

## 🚀 CR0.PE = 1 的那一刻

進入 Protected Mode 的步驟其實很簡單：

```
1. 關閉中斷（cli）          ← 切換過程中不能被打斷
2. 啟用 A20 Gate           ← 突破 1MB 限制
3. 設定 GDT（lgdt）         ← 告訴 CPU 記憶體規則
4. 設定 IDT（lidt）         ← 設定中斷表（暫時用空的）
5. CR0.PE = 1              ← 🎉 開啟 Protected Mode！
6. Far Jump                ← 更新 CS，真正進入 32-bit
```

**比喻：** 就像飛機從跑道起飛——你先完成起飛前檢查（GDT、IDT），然後加速到起飛速度（CR0.PE=1），最後離開地面那一刻就是 Far Jump。

### CR0 暫存器

```
CR0（Control Register 0）— 32 bits

Bit 31   Bit 16   Bit 5   Bit 4   Bit 3   Bit 2   Bit 1   Bit 0
┌──────┬────────┬───────┬───────┬───────┬───────┬───────┬───────┐
│  PG  │  ...   │  NE   │  ET   │  TS   │  EM   │  MP   │  PE  │
└──────┴────────┴───────┴───────┴───────┴───────┴───────┴───────┘

PE (Protection Enable) = 0: Real Mode, 1: Protected Mode
PG (Paging)           = 0: 分頁關閉, 1: 分頁開啟
```

設定 PE=1 只需要一行：

```asm
movl    %cr0, %edx        # 讀取 CR0
orb     $X86_CR0_PE, %dl  # 把 PE 位設為 1
movl    %edx, %cr0        # 寫回 CR0 → Protected Mode 啟動！
```

---

## 🦘 Far Jump 為什麼必要？

設定 CR0.PE=1 後，CPU 已經進入 Protected Mode，但 **CS 暫存器還存著 Real Mode 的值**。

CPU 用 CS 來決定當前代碼段的屬性（16-bit 還是 32-bit、什麼特權等級）。如果不更新 CS，CPU 會精神分裂——已經在 Protected Mode 但還用 Real Mode 的 CS。

**問題：你不能直接 `mov` 值到 CS。** CS 只能透過 **Far Jump（遠跳轉）** 來更新：

```asm
# Far Jump 的格式：跳到 segment:offset
# segment 會被載入到 CS
# offset 會被載入到 EIP

.byte   0x66, 0xea        # ljmpl 的機器碼
.long   .Lin_pm32          # 跳轉目標的 offset
.word   __BOOT_CS          # 新的 CS 值（指向 GDT 的代碼段）
```

**比喻：** Far Jump 就像拿新護照過海關——你拿著 Protected Mode 的護照（`__BOOT_CS`）通過關卡後，你就正式是 Protected Mode 的公民了。

---

## 💻 原始碼：`arch/x86/boot/pmjump.S` 完整中文註解

```asm
# 檔案：arch/x86/boot/pmjump.S（Linux 6.19.3）
# 功能：從 Real Mode 跳入 Protected Mode

    .text
    .code16                 # 1  目前還是 16-bit Real Mode

# ============================================================
# void protected_mode_jump(u32 entrypoint, u32 bootparams);
#
# 參數：
#   %eax = entrypoint（32-bit 進入點地址）
#   %edx = bootparams（boot_params 結構的地址）
# ============================================================

SYM_FUNC_START_NOALIGN(protected_mode_jump)
    movl    %edx, %esi      # 2  把 boot_params 指標存到 ESI
                             #    （EDX 等下要用來操作 CR0）

    xorl    %ebx, %ebx      # 3  EBX = 0
    movw    %cs, %bx        # 4  EBX = 當前 CS 值（Real Mode 的段值）
    shll    $4, %ebx        # 5  EBX = CS × 16（轉成線性地址）
    addl    %ebx, 2f        # 6  修正下面 Far Jump 的目標地址
                             #    （因為程式碼可能不在 0 地址）

    jmp     1f              # 7  短跳轉 — 在 386/486 上序列化指令管線
                             #    確保之前的指令都執行完了
1:

    movw    $__BOOT_DS, %cx # 8  CX = 資料段的 Selector
                             #    等進入 32-bit 後用來設定 DS, ES, SS...
    movw    $__BOOT_TSS, %di# 9  DI = TSS 的 Selector（給 Intel VT 用）

    # ===== 🎉 關鍵時刻：進入 Protected Mode =====

    movl    %cr0, %edx      # 10 讀取 CR0
    orb     $X86_CR0_PE, %dl# 11 設定 PE 位 = 1
    movl    %edx, %cr0      # 12 寫回 CR0
                             #    → CPU 現在在 Protected Mode 了！
                             #    但 CS 還沒更新...

    # ===== Far Jump：更新 CS，正式進入 32-bit =====

    .byte   0x66, 0xea      # 13 ljmpl 的機器碼（32-bit far jump）
2:  .long   .Lin_pm32       # 14 跳轉目標的 32-bit offset
    .word   __BOOT_CS       # 15 新的 CS = 代碼段 Selector
                             #    CS 被更新 → CPU 開始用 32-bit 解碼指令

SYM_FUNC_END(protected_mode_jump)

# ============================================================
# 以下是 32-bit Protected Mode 的程式碼
# ============================================================

    .code32                 # 16 告訴組譯器：以下是 32-bit 程式碼
    .section ".text32","ax"

SYM_FUNC_START_LOCAL_NOALIGN(.Lin_pm32)
    # --- 設定所有資料段暫存器 ---
    movl    %ecx, %ds       # 17 DS = __BOOT_DS（資料段）
    movl    %ecx, %es       # 18 ES = __BOOT_DS
    movl    %ecx, %fs       # 19 FS = __BOOT_DS
    movl    %ecx, %gs       # 20 GS = __BOOT_DS
    movl    %ecx, %ss       # 21 SS = __BOOT_DS（堆疊段）

    addl    %ebx, %esp      # 22 調整堆疊指標（加上之前計算的偏移量）

    ltr     %di             # 23 載入 TSS（Task State Segment）
                             #    讓 Intel VT 虛擬化高興

    # --- 清除暫存器 ---
    xorl    %ecx, %ecx      # 24 清除 ECX
    xorl    %edx, %edx      # 25 清除 EDX
    xorl    %ebx, %ebx      # 26 清除 EBX
    xorl    %ebp, %ebp      # 27 清除 EBP
    xorl    %edi, %edi      # 28 清除 EDI
                             #    為什麼？為了未來 boot protocol 的擴展
                             #    確保暫存器是乾淨的

    lldt    %cx             # 29 載入 LDT（設為 0 = 不使用 LDT）

    jmpl    *%eax           # 30 跳到 32-bit 的進入點！
                             #    EAX = protected_mode_jump 的第一個參數
                             #    通常是解壓縮程式碼的位置

SYM_FUNC_END(.Lin_pm32)
```

### 執行流程圖

```
protected_mode_jump(entrypoint, bootparams)
    │
    ├─ 儲存參數到暫存器
    ├─ 計算地址偏移量
    │
    ├─ CR0.PE = 1 ──── 🎉 進入 Protected Mode
    │
    ├─ Far Jump ──── CS 更新為 __BOOT_CS
    │                    │
    │                    ↓
    │              .Lin_pm32（32-bit 程式碼）
    │                    │
    │                    ├─ 設定 DS, ES, FS, GS, SS
    │                    ├─ 載入 TSS, LDT
    │                    ├─ 清除暫存器
    │                    │
    │                    └─ jmpl *%eax → 跳到解壓縮程式碼
```

---

## 👑 特權等級 Ring 0-3

Protected Mode 引入了 4 個特權等級（Privilege Level），稱為 **Ring**：

```
        ┌──────────────┐
        │   Ring 0     │  ← Kernel（最高權限）
        │  ┌────────┐  │
        │  │ Ring 1  │  │  ← OS 服務（Linux 不用）
        │  │┌──────┐│  │
        │  ││Ring 2││  │  ← OS 服務（Linux 不用）
        │  ││┌────┐││  │
        │  │││ R3 │││  │  ← User（應用程式）
        │  ││└────┘││  │
        │  │└──────┘│  │
        │  └────────┘  │
        └──────────────┘
```

| Ring | 誰住在這裡 | 能做什麼 |
|------|-----------|---------|
| Ring 0 | Linux Kernel | 一切：操作硬體、改頁表、管記憶體 |
| Ring 1 | （Linux 不用） | — |
| Ring 2 | （Linux 不用） | — |
| Ring 3 | 你的程式、Agent | 只能透過 System Call 請 Kernel 幫忙 |

### Linux 為什麼只用 Ring 0 和 Ring 3？

**簡單就是美。** Intel 設計了 4 個等級，但 Linux 只用 2 個：
- Ring 0 = Kernel Mode（完全控制）
- Ring 3 = User Mode（受限）

原因：
1. 大部分架構（ARM、RISC-V）只有 2 個等級，只用 0 和 3 比較好移植
2. 4 個等級增加了複雜度但沒帶來太多好處

### Ring 與 GDT 的關係

GDT Entry 的 **DPL（Descriptor Privilege Level）** 決定了這個 segment 的特權等級：

```
Kernel Code Segment: DPL = 0  → Ring 0 才能執行
User Code Segment:   DPL = 3  → Ring 3 可以執行
```

Segment Selector 的 **RPL（Requested Privilege Level）** 是「我請求以什麼等級存取」：

```
存取檢查：
if (RPL <= DPL && CPL <= DPL)
    → 允許存取
else
    → General Protection Fault (#GP)

CPL = 當前特權等級（CS 的 RPL）
RPL = Selector 的 RPL
DPL = 目標 Segment 的 DPL
```

---

## 🔑 關鍵概念回顧

| 概念 | 說明 |
|------|------|
| CR0.PE | 設為 1 = 進入 Protected Mode |
| Far Jump | 更新 CS 的唯一方式 |
| .Lin_pm32 | Protected Mode 的第一行 32-bit 程式碼 |
| Ring 0 | Kernel 特權等級（完全控制） |
| Ring 3 | User 特權等級（受限） |
| DPL | Segment 的特權等級 |
| RPL | 請求的特權等級 |

---

## ⏭️ 下一步

我們已經在 32-bit Protected Mode 了！但 32-bit 最多只能定址 4GB。現代系統需要更多記憶體，而且需要**記憶體保護**（每個程式有自己的地址空間）。

這就需要**分頁（Paging）** 機制。

分頁怎麼運作？→ [05_PAGING.md](05_PAGING.md)
