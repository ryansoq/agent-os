# 📚 05 — 分頁機制：虛擬記憶體的秘密

> 每個程式都以為自己擁有整個記憶體空間——分頁讓這個幻覺成為可能。

---

## 🤔 為什麼分段不夠，還需要分頁？

**分段的問題：**

```
假設 3 個程式各需要 100MB 記憶體：

分段方式：
┌────────────────┐ 0MB
│  程式 A (100MB) │
├────────────────┤ 100MB
│  程式 B (100MB) │
├────────────────┤ 200MB
│  程式 C (100MB) │
├────────────────┤ 300MB
│    空閒          │
└────────────────┘ 1GB

程式 B 結束後：
┌────────────────┐ 0MB
│  程式 A (100MB) │
├────────────────┤ 100MB
│  💀 空洞 (100MB)│ ← 外部碎片！程式 D 需要 150MB 放不進去
├────────────────┤ 200MB
│  程式 C (100MB) │
├────────────────┤ 300MB
│    空閒 (200MB) │ ← 明明總共有 300MB 空閒，但不連續
└────────────────┘ 1GB
```

**分頁的解法：把記憶體切成小塊（Page），按需分配。**

```
分頁方式（每頁 4KB）：

實體記憶體：                  程式 D 的虛擬記憶體：
┌──────┐ Page 0              ┌──────┐ 虛擬 Page 0 → 實體 Page 3
│ A    │                     │ D    │
├──────┤ Page 1              ├──────┤ 虛擬 Page 1 → 實體 Page 7
│ A    │                     │ D    │
├──────┤ Page 2              ├──────┤ 虛擬 Page 2 → 實體 Page 12
│ C    │                     │ D    │
├──────┤ Page 3              └──────┘
│ D ←──│──────── 程式 D 的頁面散布在各處
├──────┤ Page 4              但程式 D 以為自己的記憶體是連續的！
│ C    │
├──────┤ ...
```

**比喻：** 分段像分一整層公寓給一個人（必須連續）。分頁像把整棟大樓的房間隨意分配——1 樓 3 號、5 樓 7 號、12 樓 2 號都可以是你的，你只需要一張**房間對照表**就好。

---

## 📖 虛擬地址 → 實體地址的翻譯過程

CPU 收到一個虛擬地址時，需要翻譯成實體地址：

```
程式使用的地址（虛擬）→ [頁表翻譯] → 實際的記憶體地址（實體）

例子：
虛擬地址 0x00401000 → 查頁表 → 實體地址 0x0B203000
```

### 為什麼不用一張大表？

如果虛擬地址是 48-bit（256TB），每頁 4KB：
- 需要 256TB / 4KB = 64G 個 entry
- 每個 entry 8 bytes → **頁表大小 = 512GB** 😱

所以 CPU 用**多層頁表**——只建立需要的部分。

---

## 🏗️ 4 級頁表結構

64-bit x86 使用 4 級頁表（48-bit 虛擬地址）：

```
48-bit 虛擬地址的切法：

Bit 47-39   Bit 38-30   Bit 29-21   Bit 20-12   Bit 11-0
┌──────────┬──────────┬──────────┬──────────┬──────────┐
│ PML4 索引 │ PDPT 索引 │  PD 索引  │  PT 索引  │ 頁內偏移  │
│  9 bits   │  9 bits   │  9 bits  │  9 bits  │ 12 bits  │
└──────────┴──────────┴──────────┴──────────┴──────────┘
  ↓            ↓           ↓          ↓          ↓
  第4層        第3層       第2層       第1層     頁內位置
```

翻譯過程（4 次查表）：

```
CR3（存放 PML4 的實體地址）
 │
 ↓
PML4（Page Map Level 4）—— 512 個 entry
 │  用 Bit[47:39] 當索引
 ↓
PDPT（Page Directory Pointer Table）—— 512 個 entry
 │  用 Bit[38:30] 當索引
 ↓
PD（Page Directory）—— 512 個 entry
 │  用 Bit[29:21] 當索引
 ↓
PT（Page Table）—— 512 個 entry
 │  用 Bit[20:12] 當索引
 ↓
Page（4KB）
    用 Bit[11:0] 當頁內偏移量
    ↓
  最終的實體地址！
```

**比喻：** 就像查字典——先查部首表（PML4）→ 再查筆畫索引（PDPT）→ 再翻到某頁（PD）→ 找到字的位置（PT）→ 讀到內容。

---

## 📋 Page Table Entry 每個位元的意義

每個 PTE（Page Table Entry）是 64 bits：

```
Bit 63     Bit 62-52    Bit 51-12           Bit 11-0
┌─────────┬───────────┬──────────────────┬──────────────┐
│   NX    │  保留/OS   │ 實體地址 [51:12]  │    Flags     │
│         │  可用位元   │  (頁框號碼)       │              │
└─────────┴───────────┴──────────────────┴──────────────┘
```

### 低 12 bits（Flags）詳解：

```
Bit   名稱    意義
──────────────────────────────────────────
 0    P      Present — 1: 頁面在記憶體中, 0: 不在（會觸發 Page Fault）
 1    R/W    Read/Write — 1: 可寫, 0: 唯讀
 2    U/S    User/Supervisor — 1: User Mode 可存取, 0: 只有 Kernel
 3    PWT    Page-level Write-Through — 快取策略
 4    PCD    Page-level Cache Disable — 關閉快取
 5    A      Accessed — CPU 存取過這頁後自動設為 1
 6    D      Dirty — CPU 寫過這頁後自動設為 1
 7    PAT/PS Page Size — 在 PD 層：1 表示 2MB 大頁
 8    G      Global — TLB 切換時不清除此 entry
11-9  AVL    OS 自由使用的位元
```

### Bit 63: NX（No-Execute）

```
NX = 0: 這頁的內容可以被當作程式碼執行
NX = 1: 這頁不可執行（防止 buffer overflow 攻擊）
```

---

## 🔄 Identity Mapping：開機必需的自我映射

**Identity Mapping = 虛擬地址 === 實體地址**

```
Identity Mapping：
虛擬地址 0x1000 → 實體地址 0x1000  ← 一模一樣！
虛擬地址 0x2000 → 實體地址 0x2000
虛擬地址 0x3000 → 實體地址 0x3000
...
```

### 為什麼開機需要 Identity Mapping？

**想像一下：** 你正在跑步，突然有人說「從現在開始，所有地址都要查表」。

如果啟用分頁前，你的程式碼在實體地址 `0x100000` 處。啟用分頁後，CPU 下一條指令的地址 `0x100004` 會去查頁表。如果頁表說 `0x100004` 映射到 `0x500000`——你的程式就跑到錯誤的地方了！

**解法：** 開機時先建立 Identity Mapping（虛擬 = 實體），讓啟用分頁的前後一切不變。等穩定後再切換到真正的虛擬記憶體映射。

---

## 💻 原始碼：`head_64.S` 建立頁表

```asm
# 檔案：arch/x86/boot/compressed/head_64.S（Linux 6.19.3）
# 功能：在 startup_32 中建立早期 4GB 的 Identity Mapping 頁表

# ===== 啟用 PAE（Physical Address Extension）=====
    movl    %cr4, %eax          # 1  讀取 CR4
    orl     $X86_CR4_PAE, %eax  # 2  設定 PAE 位 = 1
    movl    %eax, %cr4          # 3  寫回 CR4
                                #    PAE 是進入 Long Mode 的前置條件

# ===== 清零頁表空間 =====
    leal    rva(pgtable)(%ebx), %edi  # 4  EDI = 頁表的起始地址
    xorl    %eax, %eax                # 5  EAX = 0
    movl    $(BOOT_INIT_PGT_SIZE/4), %ecx  # 6  要清除的 dword 數量
    rep     stosl                      # 7  把整個頁表空間清零

# ===== 建立第 4 層（PML4）=====
    leal    rva(pgtable + 0)(%ebx), %edi     # 8  EDI = PML4 的地址
    leal    0x1007(%edi), %eax               # 9  EAX = PDPT 的地址 + 0x7
                                             #    0x7 = Present + R/W + User
    movl    %eax, 0(%edi)                    # 10 PML4[0] = 指向 PDPT
    addl    %edx, 4(%edi)                    # 11 高 32 位（SEV 加密用）

# ===== 建立第 3 層（PDPT）=====
    leal    rva(pgtable + 0x1000)(%ebx), %edi  # 12 EDI = PDPT 的地址
    leal    0x1007(%edi), %eax                 # 13 EAX = 第一個 PD + flags
    movl    $4, %ecx                           # 14 建立 4 個 entry
1:  movl    %eax, 0x00(%edi)                   # 15 PDPT[i] = 指向 PD[i]
    addl    %edx, 0x04(%edi)                   # 16 高 32 位
    addl    $0x00001000, %eax                  # 17 下一個 PD（隔 4KB）
    addl    $8, %edi                           # 18 下一個 PDPT entry
    decl    %ecx                               # 19 計數器 -1
    jnz     1b                                 # 20 迴圈 4 次

# ===== 建立第 2 層（PD）— 用 2MB 大頁 =====
    leal    rva(pgtable + 0x2000)(%ebx), %edi  # 21 EDI = PD 的起始地址
    movl    $0x00000183, %eax                  # 22 EAX = 0 + 0x183
                                               #    0x183 = Present + R/W
                                               #          + PS（2MB page）
                                               #          + Global
    movl    $2048, %ecx                        # 23 2048 個 2MB 頁 = 4GB
1:  movl    %eax, 0(%edi)                      # 24 PD[i] = 2MB 頁面
    addl    %edx, 4(%edi)                      # 25 高 32 位
    addl    $0x00200000, %eax                  # 26 下一個 2MB 區塊
    addl    $8, %edi                           # 27 下一個 PD entry
    decl    %ecx                               # 28 計數器 -1
    jnz     1b                                 # 29 迴圈 2048 次

# ===== 載入頁表到 CR3 =====
    leal    rva(pgtable)(%ebx), %eax  # 30 EAX = PML4 的地址
    movl    %eax, %cr3                # 31 CR3 = PML4
                                      #    告訴 CPU：頁表在這裡
```

### 建立的頁表結構：

```
PML4 (1 個 entry)
  └→ PDPT (4 個 entries)
       ├→ PD[0]   (512 × 2MB = 1GB)
       ├→ PD[1]   (512 × 2MB = 1GB)
       ├→ PD[2]   (512 × 2MB = 1GB)
       └→ PD[3]   (512 × 2MB = 1GB)
                                        共 4GB Identity Mapping

注意：這裡用 2MB 大頁（PS=1），所以只需要 3 層，不需要 PT 層。
虛擬地址 0x00000000 ~ 0xFFFFFFFF 直接映射到實體地址 0x00000000 ~ 0xFFFFFFFF
```

---

## 🔑 關鍵概念回顧

| 概念 | 說明 |
|------|------|
| Page | 記憶體的最小管理單位（通常 4KB） |
| 4 級頁表 | PML4 → PDPT → PD → PT → Page |
| PTE Flags | P, R/W, U/S, NX 等控制位元 |
| Identity Mapping | 虛擬地址 = 實體地址 |
| 2MB 大頁 | 用 PD 的 PS 位直接映射 2MB，省略 PT 層 |
| CR3 | 存放最頂層頁表（PML4）的實體地址 |

---

## ⏭️ 下一步

頁表建好了、PAE 開啟了，接下來就是進入 **64-bit Long Mode**——真正的現代世界。

怎麼從 32-bit 跳到 64-bit？→ [06_LONG_MODE.md](06_LONG_MODE.md)
