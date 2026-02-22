# 🤔 思考題解答

> **建議先自己想過再看答案！** 想錯沒關係，重要的是思考過程。

---

## 01: Hello Real Mode

### Q1: 為什麼用 `-Ttext=0x7C00` 而不是在原始碼裡寫 `org`？

GAS（GNU Assembler）沒有像 NASM 的 `[org 0x7C00]` 指令。

在 NASM 裡，`org` 告訴組譯器「這段 code 會被載入到哪個地址」，讓它計算 label 的正確位址。

在 GNU 工具鏈裡，這件事由 **linker** 負責：
```bash
ld -Ttext=0x7C00 ...
```
意思是「把 `.text` section 放在 0x7C00」。效果一樣，但職責分離更乾淨 — 組譯器負責組譯，linker 負責安排地址。

**類比**：NASM 的 `org` 像是「在信紙上寫好地址」，GNU 的 `-Ttext` 像是「在信封上寫地址」。信的內容和地址分開處理。

---

### Q2: 如果把 `0xAA55` 拿掉會怎樣？

**BIOS 不會認為這是可開機的磁碟。**

BIOS 讀取磁碟的第一個磁區（512 bytes）後，會檢查最後兩個 byte 是不是 `0x55AA`（注意 little-endian，在檔案裡是 `0x55, 0xAA`）。如果不是，BIOS 會跳過這個磁碟，試下一個，或者顯示「No bootable device found」。

```
磁碟第一磁區（512 bytes）：
  byte 0-509:   你的程式
  byte 510:     0x55  ← 
  byte 511:     0xAA  ← BIOS 只看這兩個 byte！

沒有 → BIOS: 「這不是開機碟，下一個」
有   → BIOS: 「OK，載入到 0x7C00，跳過去」
```

**類比**：`0xAA55` 就像信封上的郵票 — 沒貼郵票，郵局（BIOS）不會寄。

---

### Q3: SP 為什麼設在 0x7C00？Stack 往哪個方向生長？

**x86 的 stack 是向下生長的。** `push` 會 `SP -= 2`，`pop` 會 `SP += 2`。

```
記憶體地圖：
  0x0000 ┌──────────┐
         │ IVT      │ ← 中斷向量表（BIOS 用的）
  0x0500 ├──────────┤
         │ 可用空間  │ ← Stack 往這裡長
         │    ↑     │
         │    │     │
  0x7C00 ├──────────┤ ← SP 起始位置 = 我們的 code 起始位置
         │ 我們的    │
         │ boot code │
  0x7E00 └──────────┘ ← boot sector 結束（0x7C00 + 512）
```

SP 設在 0x7C00，stack 往下長（往 0x0500 方向），所以 stack 不會覆蓋到我們的程式碼。我們的 code 在 0x7C00 往上，stack 在 0x7C00 往下，完美分開。

**如果 SP 設在 0x7E00 以上呢？** Stack 往下長可能覆蓋到我們的 code → 程式爆掉 💥

---

### Q4: 為什麼要設 DS = 0？如果不設會怎樣？

在 Real Mode 下，記憶體存取的實際地址 = `DS × 16 + offset`。

```
如果 DS = 0:
  mov msg 的地址 = 0 × 16 + msg_offset = msg_offset ✅

如果 DS = 隨機值（BIOS 沒保證）：
  mov msg 的地址 = 隨機 × 16 + msg_offset = 錯誤地址 ❌
  → 讀到垃圾資料，印出亂碼
```

BIOS 跳到 0x7C00 時，**不保證 DS 的值是 0**（不同 BIOS 行為不同）。所以我們必須自己設。

**類比**：DS 像是「從哪條街開始算門牌號」。如果不先確認你在正確的街上，門牌 100 號可能跑到完全不同的地方。

---

## 02: Protected Mode

### Q1: 為什麼 GDT 第一個 entry 必須是 null？

**CPU 規定的。** 如果 segment register 被載入 0x0000（index 0），CPU 不會去查 GDT，而是直接觸發 #GP。

這是一個**安全機制**：防止未初始化的 segment register 意外存取記憶體。

```
DS = 0x0000 → 存取記憶體 → #GP ❌（提早抓到 bug）
DS = 0x0010 → 查 GDT[2] → 正常存取 ✅
```

**類比**：GDT[0] 就像門禁卡系統的「0 號卡位」故意留空 — 如果有人拿著編號 0 的卡來刷，系統知道一定有問題。

---

### Q2: far jump `ljmp $0x08, $pm_entry` 的 0x08 是怎麼算出來的？

```
GDT 結構：
  GDT[0] = null descriptor    → offset 0x00（8 bytes × 0）
  GDT[1] = code descriptor    → offset 0x08（8 bytes × 1）
  GDT[2] = data descriptor    → offset 0x10（8 bytes × 2）
```

每個 GDT entry 是 8 bytes，所以：
- `0x08` = 第 1 個有效 entry（code segment）
- `0x10` = 第 2 個有效 entry（data segment）

完整的 selector 其實是：
```
┌─────────────────┬────┬─────┐
│  Index (13 bits) │ TI │ RPL │
│     0x0001       │ 0  │ 00  │
└─────────────────┴────┴─────┘
= 0000000000001 | 0 | 00 = 0x0008

TI = 0: 查 GDT（不是 LDT）
RPL = 00: 請求的權限等級 = Ring 0
```

---

### Q3: 為什麼 Protected Mode 不能用 BIOS 中斷？

BIOS 中斷是 **Real Mode 的機制**：
1. 它依賴 Real Mode 的中斷向量表（IVT，在記憶體 0x0000-0x03FF）
2. BIOS 中斷處理程式本身是 **16-bit Real Mode 的 code**
3. Protected Mode 用的是 IDT（Interrupt Descriptor Table），格式完全不同

```
Real Mode:
  int 0x10 → 查 IVT[0x10] → 跳到 BIOS 的 16-bit 程式 ✅

Protected Mode:
  int 0x10 → 查 IDT[0x10] → 我們沒設定 IDT → #GP 💥
  就算設了 IDT → BIOS 的 16-bit code 在 32-bit 模式下跑不了 💥
```

**所以 Protected Mode 要自己操作硬體**（用 I/O port），不能再依賴 BIOS。這也是為什麼我們的範例改用 serial port（COM1 = 0x3F8）輸出。

**類比**：BIOS 中斷像是「叫服務生送餐」。進了 Protected Mode，服務生下班了（Real Mode 機制失效），你得自己走到廚房（直接操作硬體 I/O port）。

---

### Q4: 如果不開 A20 Gate 會怎樣？

**地址會 wrap around，只能存取 1MB 以內的記憶體。**

```
A20 關閉（預設）：
  第 21 條地址線永遠是 0
  地址 0x100000 (1MB) → 實際存取 0x000000 (0)
  地址 0x100001        → 實際存取 0x000001
  → 看起來像記憶體「捲回」了

A20 開啟：
  第 21 條地址線正常
  地址 0x100000 → 真的存取 0x100000 ✅
```

**歷史原因**：IBM PC/AT 為了相容 8086（只有 20 條地址線，1MB），故意用鍵盤控制器的一條線把 A20 拉低。這個「bug」變成了「feature」，一直保留到今天。

**如果不開 A20 就進 Protected Mode？** GDT 的 code/data segment 設定了 4GB 範圍，但只要地址超過 1MB 就會 wrap → 跳到完全錯誤的位置 → 當機 💥

---

## 03: Long Mode

### Q1: 為什麼 Long Mode 強制使用分頁？

在 32-bit Protected Mode，分頁是可選的（可以只用 segmentation）。但 **64-bit Long Mode 強制開啟分頁**，原因：

1. **Segmentation 在 64-bit 幾乎被廢了**
   - Long Mode 忽略 GDT 的 base 和 limit（全部當 0 和 max）
   - 沒有 segmentation 保護 → 必須靠分頁來隔離程式

2. **64-bit 地址空間太大（16 EB），必須用虛擬記憶體**
   - 沒有任何電腦有 16 EB 的 RAM
   - 分頁讓你把虛擬地址映射到實際有的 RAM

3. **安全性**
   - 分頁的 U/S bit 提供 Ring 0 / Ring 3 的記憶體隔離
   - NX bit（No Execute）防止 data 被當 code 執行
   - 這些都需要分頁才有

**類比**：32-bit 時代，門禁（segmentation）和地圖（paging）都能用。64-bit 時代，Intel 說「門禁太老了，以後全部用地圖管理」。

---

### Q2: Identity Map 是什麼意思？為什麼開機時需要？

**Identity Map = 虛擬地址 == 實體地址**

```
一般的頁表映射：
  虛擬 0x1000 → 實體 0x50000（不同）

Identity Map：
  虛擬 0x1000 → 實體 0x1000（一樣！）
  虛擬 0x2000 → 實體 0x2000（一樣！）
```

**為什麼開機時需要？** 因為開啟分頁的那一瞬間，CPU 的「下一條指令」的地址必須在新的頁表裡是有效的。

```
假設你的 code 在實體地址 0x1000：

沒有 identity map：
  mov cr0, eax   ← 實體地址 0x1000，OK
  // 分頁開啟！
  下一條指令     ← CPU 用 0x1002 查頁表 → 頁表裡沒有 → #PF 💥

有 identity map：
  mov cr0, eax   ← 實體地址 0x1000，OK
  // 分頁開啟！
  下一條指令     ← CPU 用 0x1002 查頁表 → 映射到 0x1002 → OK ✅
```

**之後 kernel 會重新設定頁表**，把 identity map 換成正式的虛擬記憶體佈局。但開機那一瞬間必須有，不然 CPU 會迷路。

---

### Q3: 2MB 大頁和 4KB 小頁各有什麼優缺點？

```
4KB 小頁（3 級：PML4 → PDPT → PD → PT）：
  ✅ 精細控制 — 每 4KB 可以有不同權限
  ✅ 記憶體碎片少
  ❌ 頁表佔更多空間（多一級 PT）
  ❌ TLB miss 時要多查一級

2MB 大頁（2 級：PML4 → PDPT → PD，PD 的 PS=1）：
  ✅ 頁表更小（少一級 PT）
  ✅ TLB 效率高（一個 entry 覆蓋 2MB）
  ❌ 粒度粗 — 2MB 全部同權限
  ❌ 浪費記憶體（只需要 100KB 也得分 2MB）
```

**開機時用大頁**是因為：簡單！映射 4GB 只需要 2048 個 PD entry，不用建 PT。

**正式運行用小頁**是因為：需要精細控制（每個程式的每一頁都可能有不同的 RWX 權限）。

---

### Q4: 為什麼 64-bit GDT 的 D 位元必須為 0？

D 位元（Default operand size）和 L 位元（Long mode）的組合：

```
D=1, L=0 → 32-bit Protected Mode（預設 32-bit 運算元）
D=0, L=1 → 64-bit Long Mode（預設 64-bit 運算元）
D=1, L=1 → ❌ 未定義！CPU 會出錯

所以 64-bit 下 D 必須為 0。
```

**原因**：L=1 已經表示「64-bit 模式」，D 在這個模式下被重新定義。Intel 規定 L=1 時 D 必須為 0，否則行為未定義。

**比喻**：就像一個開關面板，「64-bit 模式」和「32-bit 預設」不能同時打開 — 邏輯矛盾。

---

## 04: C Kernel

### Q1: 為什麼 kernel 載入在 1MB (0x100000)？低於 1MB 有什麼？

```
低 1MB 的記憶體佈局（x86 的歷史包袱）：
  0x00000 - 0x003FF  IVT（中斷向量表）
  0x00400 - 0x004FF  BIOS Data Area
  0x00500 - 0x07BFF  可用（但通常留給 bootloader）
  0x07C00 - 0x07DFF  Boot sector（我們的 code！）
  0x07E00 - 0x7FFFF  可用
  0x80000 - 0x9FFFF  可能被 BIOS 使用
  0xA0000 - 0xBFFFF  VGA 顯示記憶體 ← 0xB8000 在這裡！
  0xC0000 - 0xFFFFF  BIOS ROM / 選項 ROM
  
  0x100000 (1MB) 以上  → 乾淨的、沒有歷史包袱的記憶體 ✅
```

**1MB 以下是「雷區」**，到處都是 BIOS、VGA、ROM 在用的記憶體。把 kernel 放在 1MB 以上，避開所有歷史包袱。

---

### Q2: 為什麼用 `-ffreestanding`？如果不用會怎樣？

```bash
gcc -ffreestanding  # 告訴 GCC：我不在一般的作業系統環境裡
```

**效果**：
- 不假設有標準函式庫（`printf`、`malloc` → 不存在）
- 不假設有 `main()` 函數
- 不自動連結 `libc`
- 不做某些依賴 OS 的最佳化

**如果不用？**
```
gcc kernel.c → 連結器找不到 printf、找不到 _start → 編譯失敗
或者
gcc 自動插入 libc 初始化碼 → 嘗試呼叫 OS 的 syscall → 沒有 OS → 當機
```

**類比**：`-ffreestanding` 告訴 GCC「我就是 OS 本身，不要期待有人罩我」。

---

### Q3: `volatile` 在 VGA 指標上有什麼作用？拿掉會怎樣？

```c
volatile unsigned short *const VGA_BUFFER = (volatile unsigned short *)0xB8000;
```

**`volatile` 告訴編譯器：「這個記憶體位址會被外部改變，不要優化掉對它的讀寫。」**

```c
// 沒有 volatile，GCC 可能會「優化」成：
VGA_BUFFER[0] = 'A';
VGA_BUFFER[0] = 'B';
// GCC: 「第一次寫入沒用，反正馬上被覆蓋」→ 只保留第二次 ❌

// 有 volatile：
VGA_BUFFER[0] = 'A';  // 真的寫入 0xB8000 → 螢幕顯示 A
VGA_BUFFER[0] = 'B';  // 真的寫入 0xB8000 → 螢幕顯示 B
// 兩次都會執行 ✅
```

**對 VGA 特別重要**：因為寫入 0xB8000 不只是「存資料」，而是**讓螢幕顯示字元**。每一次寫入都有「副作用」，不能被優化掉。

**所有硬體暫存器都要用 `volatile`**：UART、GPIO、DMA、timer……它們的值隨時會變，或寫入會觸發硬體動作。

---

### Q4: kernel_main() 為什麼不能 return？

```c
void kernel_main(void) {
    // ... 初始化 ...
    while (1) {
        __asm__ volatile ("hlt");  // 必須無限迴圈！
    }
}
```

**因為 `kernel_main()` 沒有「上一層」可以回去。**

```
一般程式：
  main() return → libc 的 __libc_start_main → exit() syscall → OS 回收

Kernel：
  kernel_main() return → boot.S 的 call 指令返回
  → 下一行是什麼？→ 未定義的記憶體 → CPU 執行垃圾指令 → 💥
```

**boot.asm 裡有保護**：
```asm
call kernel_main    ; 呼叫 C kernel
cli                 ; 如果 kernel_main 意外 return
.halt: hlt          ; 至少讓 CPU 停下來，不要亂跑
jmp .halt
```

但最佳做法是 kernel 自己確保永遠不 return（用 `while(1)` 或進入排程迴圈）。

**比喻**：`kernel_main()` 就是宇宙的起點 — 沒有「之前」，也不能「結束」。它必須永遠運行下去。

---

## 05: Ring 特權級與 Syscall

### Q1: 如果 CPU 沒有 Ring 機制，作業系統要怎麼保護自己？

**答案：基本上做不到。** 這就是 MS-DOS 的情況。

```
DOS 時代（沒有 Ring）：
  ✅ 任何程式都能存取任何記憶體
  ✅ 任何程式都能直接操作硬體
  ✅ 任何程式都能覆寫 OS 本身
  
  結果：
  💀 一個 bug 就能搞垮整台電腦
  💀 病毒可以直接寫入硬碟 boot sector
  💀 沒有多工保護（一個程式 hang → 全部 hang）
```

**軟體層面的保護**（沒有硬體支援）理論上可以做，但：
- 用直譯器（interpreter）檢查每條指令 → 極慢
- 用軟體沙箱 → 可以被繞過（因為沒有硬體強制）
- Java 的 JVM 就是一種軟體保護，但它需要 OS + 硬體保護才真正安全

**結論**：沒有硬體級別的保護，軟體保護都是「紙門」。

---

### Q2: 為什麼 Ring 1 和 Ring 2 幾乎沒人用？

**因為分頁保護比分段保護更好用，而分頁只區分兩級（U/S bit = 0 或 1）。**

```
Intel 的設計（1985 年）：
  Ring 0: OS kernel
  Ring 1: OS 服務（驅動程式）
  Ring 2: OS 擴展
  Ring 3: 使用者程式

實際情況（1990 年代至今）：
  Ring 0: Kernel + 驅動程式
  Ring 1: （空）
  Ring 2: （空）
  Ring 3: 所有 user space
```

**原因**：
1. 分頁的 U/S bit 只有 1 bit → 只能分「Supervisor」和「User」兩級
2. 4 級 Ring 配合分段才有意義，但現代 OS 幾乎不用分段保護
3. 多級權限增加複雜度，但好處不大
4. Linux/Windows 都選擇只用 0 和 3，簡單又夠用

**例外**：OS/2 曾用過 Ring 2，但後來也放棄了。

---

### Q3: 虛擬化（VMX）引入了 Ring -1，這是什麼意思？

**Intel VT-x 在 Ring 0 「下面」加了一層。**

```
沒有虛擬化：
  Ring 0: Kernel（最高權限）
  Ring 3: User

有虛擬化（VT-x）：
  VMX Root Mode (Ring -1): Hypervisor（VMware/KVM/Hyper-V）
  Ring 0: Guest OS Kernel（以為自己是最高權限，其實不是）
  Ring 3: Guest User
```

**問題**：如果你要在一台電腦上跑多個 OS（虛擬機），誰來管理 Ring 0？
- Guest OS 以為自己在 Ring 0，可以改頁表、改 GDT
- 但實際上 Hypervisor 需要攔截這些操作
- 解法：在 Ring 0 下面再加一層 → VMX Root Mode

**比喻**：
```
以前：管理員（kernel）是大樓的最高權力者
現在：管理員上面還有「物業公司」（hypervisor）
      管理員以為自己在管整棟樓
      其實物業公司隨時可以介入
```

---

### Q4: ARM 的 EL0-EL3 和 x86 的 Ring 有什麼對應關係？

```
ARM Exception Levels        x86 等價
─────────────────           ────────
EL0 — User（應用程式）       Ring 3
EL1 — Kernel（作業系統）     Ring 0
EL2 — Hypervisor（虛擬化）   VMX Root Mode (Ring -1)
EL3 — Secure Monitor        （x86 沒有直接對應）
       （ARM TrustZone）
```

**差異**：
- ARM 從一開始就設計了 4 級，每級都有實際用途
- x86 設計了 4 個 Ring 但只用了 2 個，後來又加了 VMX
- ARM 的 EL3（TrustZone）是用來隔離「安全世界」和「普通世界」的，x86 用 SGX/SMM 做類似的事

**ARM 更乾淨**：因為沒有 40 年的歷史包袱。x86 要相容 8086 → 286 → 386 → 現在，所以有一堆只為了相容而存在的東西（Real Mode、A20 Gate、segmentation...）。

---

*看完這些解答，如果有些地方還是不太懂，那就對了 — 回去重讀對應的原始碼，搭配解答會更清楚！ 🌊*
