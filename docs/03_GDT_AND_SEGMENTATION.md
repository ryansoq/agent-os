# 📚 03 — GDT 與分段：記憶體管理的第一步

> 從「直接算地址」變成「查表」——Protected Mode 的入場券。

---

## 🤔 什麼是 GDT？

**GDT = Global Descriptor Table = 全局描述符表**

**比喻：** 在 Real Mode 裡，記憶體就像一片沒有圍牆的空地——任何程式都能去任何地方。GDT 就是在這片空地上蓋圍牆、分房間、裝門禁。

```
Real Mode（沒有 GDT）：           Protected Mode（有 GDT）：

┌──────────────────┐              ┌──────────────────┐
│                  │              │   Ring 0 (Kernel) │ ← 只有 OS 能進
│  任何程式都能     │              ├──────────────────┤
│  存取任何地址     │              │   Ring 3 (User)   │ ← 普通程式
│                  │              ├──────────────────┤
│  完全沒有保護     │              │   不可存取         │ ← 禁區
└──────────────────┘              └──────────────────┘
```

---

## 📋 為什麼需要 GDT？

在 Real Mode 中，Segment 直接參與地址計算：

```
地址 = Segment × 16 + Offset    ← 直接算，沒有檢查
```

在 Protected Mode 中，Segment Register 不再直接代表地址，而是一個**索引**，指向 GDT 中的一個 entry：

```
地址計算方式改變了：

Segment Register 裡存的是 "Selector"
    ↓ 查表
GDT[Selector] → 得到 {Base Address, Limit, 權限}
    ↓
地址 = Base + Offset（如果權限允許的話）
```

**比喻：** 
- Real Mode：你直接說「我要去 3 樓 205 室」，沒人管你
- Protected Mode：你出示「員工證 #2」，門禁系統查表後說「你可以去 3-5 樓，但不能去 6 樓以上」

---

## 📐 GDT Entry：64-bit 格式完整解碼

GDT 中每個 entry 是 **8 bytes（64 bits）**，格式如下：

```
Byte 7    Byte 6    Byte 5    Byte 4    Byte 3    Byte 2    Byte 1    Byte 0
┌────────┬────────┬────────┬────────┬────────┬────────┬────────┬────────┐
│Base    │ Flags  │Access  │        │                 │                 │
│[31:24] │+ Limit │ Byte   │Base    │  Base [15:0]    │  Limit [15:0]  │
│        │[19:16] │        │[23:16] │                 │                 │
└────────┴────────┴────────┴────────┴────────┴────────┴────────┴────────┘
   8 bits   8 bits  8 bits   8 bits      16 bits           16 bits

（注意：Base 和 Limit 的 bits 被打散在不同位置，這是歷史設計造成的）
```

### 每個欄位詳解：

#### Base Address（32 bits，分散在 3 個地方）

```
Base = Base[31:24] | Base[23:16] | Base[15:0]

這個 segment 在記憶體中從哪裡開始。
例如 Base = 0x00000000 表示從記憶體最開頭開始。
```

#### Limit（20 bits，分散在 2 個地方）

```
Limit = Limit[19:16] | Limit[15:0]

這個 segment 有多大。
如果 G（Granularity）位 = 1，Limit 的單位是 4KB page：
  Limit = 0xFFFFF → 0xFFFFF × 4KB = 4GB

如果 G = 0，Limit 的單位是 byte：
  Limit = 0xFFFFF → 約 1MB
```

#### Access Byte（8 bits）— 最重要的部分

```
Bit 7   Bit 6-5   Bit 4    Bit 3    Bit 2    Bit 1    Bit 0
┌─────┬────────┬────────┬────────┬────────┬────────┬────────┐
│  P  │  DPL   │   S    │   E    │  DC    │  RW    │   A    │
└─────┴────────┴────────┴────────┴────────┴────────┴────────┘

P  (Present)      = 1: 這個 segment 在記憶體中（必須是 1）
DPL (Privilege)   = 0-3: 特權等級（0=最高=kernel, 3=最低=user）
S  (Type)         = 1: 代碼/資料 segment, 0: 系統 segment (TSS/Gate)
E  (Executable)   = 1: 代碼 segment（可執行）, 0: 資料 segment
DC (Direction)    = 代碼: Conforming, 資料: Direction（向上/向下成長）
RW (Read/Write)   = 代碼: 可讀?, 資料: 可寫?
A  (Accessed)     = CPU 存取過這個 segment 後自動設為 1
```

#### Flags（4 bits）

```
Bit 3    Bit 2    Bit 1    Bit 0
┌─────┬────────┬────────┬────────┐
│  G  │  D/B   │   L    │  AVL   │
└─────┴────────┴────────┴────────┘

G  (Granularity) = 1: Limit 單位是 4KB, 0: 單位是 byte
D/B (Size)       = 1: 32-bit segment, 0: 16-bit segment
L  (Long mode)   = 1: 64-bit 代碼 segment（D/B 必須為 0）
AVL (Available)  = 留給 OS 自由使用
```

---

## 🔍 Segment Selector 怎麼查 GDT

Segment Register（CS, DS, ES, FS, GS, SS）存放的是 **Selector**，不是地址：

```
Selector（16 bits）：

Bit 15-3    Bit 2    Bit 1-0
┌──────────┬───────┬────────┐
│  Index   │  TI   │  RPL   │
└──────────┴───────┴────────┘

Index = GDT entry 的編號（0, 1, 2, 3...）
TI    = 0: 查 GDT, 1: 查 LDT
RPL   = 請求的特權等級

例子：
  Selector = 0x10 = 0b 0000_0000_0001_0000
  Index = 2, TI = 0 (GDT), RPL = 0 (Ring 0)
  → 查 GDT 的第 2 個 entry
```

---

## 💻 原始碼：`arch/x86/boot/pm.c` 的 setup_gdt()

```c
// 檔案：arch/x86/boot/pm.c（Linux 6.19.3）
// 功能：在進入 Protected Mode 之前，設定 GDT

// 1  GDT 指標結構 — 告訴 CPU「GDT 在哪、多大」
struct gdt_ptr {
    u16 len;    // GDT 的大小（bytes）- 1
    u32 ptr;    // GDT 在記憶體中的線性地址
} __attribute__((packed));  // 不要自動對齊，緊密排列

// 2  設定 GDT 的函數
static void setup_gdt(void)
{
    // 3  定義 GDT 內容 — 16 byte 對齊（Intel 建議）
    static const u64 boot_gdt[] __attribute__((aligned(16))) = {
        // 4  GDT[0] — 永遠是 NULL（CPU 規定）
        //    （沒有明確寫出來，但陣列從 index 0 開始，值為 0）

        // 5  GDT[GDT_ENTRY_BOOT_CS] — 代碼段（Code Segment）
        //    屬性：可執行、可讀、32-bit、Base=0、Limit=4GB
        [GDT_ENTRY_BOOT_CS] = GDT_ENTRY(DESC_CODE32, 0, 0xfffff),

        // 6  GDT[GDT_ENTRY_BOOT_DS] — 資料段（Data Segment）
        //    屬性：可讀寫、32-bit、Base=0、Limit=4GB
        [GDT_ENTRY_BOOT_DS] = GDT_ENTRY(DESC_DATA32, 0, 0xfffff),

        // 7  GDT[GDT_ENTRY_BOOT_TSS] — 任務狀態段（Task State Segment）
        //    Intel VT（虛擬化）需要 TSS，我們只是讓它開心，不真的用
        [GDT_ENTRY_BOOT_TSS] = GDT_ENTRY(DESC_TSS32, 4096, 103),
    };

    // 8  設定 GDT 指標
    static struct gdt_ptr gdt;
    gdt.len = sizeof(boot_gdt) - 1;           // GDT 大小
    gdt.ptr = (u32)&boot_gdt + (ds() << 4);   // GDT 的線性地址
    //        ↑ 因為還在 Real Mode，要把 segment 地址轉成線性地址

    // 9  用 LGDT 指令告訴 CPU：GDT 在這裡
    asm volatile("lgdtl %0" : : "m" (gdt));
}
```

---

## 🏠 Linux 的 Flat Model：Base=0, Limit=4GB

注意到 Linux 的 GDT 設定了嗎？

```
Code Segment: Base = 0, Limit = 0xFFFFF (配合 G=1 → 4GB)
Data Segment: Base = 0, Limit = 0xFFFFF (配合 G=1 → 4GB)
```

**兩個 segment 都覆蓋整個 4GB 地址空間！**

這叫做 **Flat Model（平坦模型）**：

```
Flat Model 示意圖：

0x00000000 ┌──────────────────┐
           │                  │
           │  Code Segment    │ ← Base=0, Limit=4GB
           │  = Data Segment  │ ← Base=0, Limit=4GB
           │  = 整個記憶體     │
           │                  │
0xFFFFFFFF └──────────────────┘
```

### 為什麼要這樣？

**因為 Linux 不真的想用分段機制來管理記憶體。**

Intel 要求進入 Protected Mode 必須設定 GDT——但 Linux 用**分頁（Paging）** 來做真正的記憶體管理。GDT 只是為了滿足 CPU 的要求而存在。

所以 Linux 把 Code 和 Data segment 都設為「整個記憶體空間」，等於說：「分段？隨便啦，反正我用分頁。」

---

## 🔑 關鍵概念回顧

| 概念 | 說明 |
|------|------|
| GDT | 全局描述符表，定義記憶體 segment 的屬性 |
| GDT Entry | 8 bytes，包含 Base、Limit、權限 |
| Selector | 16-bit，存在 Segment Register 裡，索引到 GDT |
| LGDT | CPU 指令，載入 GDT 的位置和大小 |
| Flat Model | Base=0, Limit=4GB，讓分段形同虛設 |
| DPL | 描述符特權等級（0=kernel, 3=user） |

---

## ⏭️ 下一步

GDT 設定好了，接下來就是那個歷史性的一刻——**進入 Protected Mode**。

只需要把 CR0 暫存器的 PE 位設為 1，然後做一個 Far Jump……

怎麼跳？→ [04_PROTECTED_MODE.md](04_PROTECTED_MODE.md)
