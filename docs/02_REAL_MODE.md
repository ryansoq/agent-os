# 📚 02 — 16-bit Real Mode：回到 1978 年

> CPU 開機後為什麼從 16-bit 開始？因為要向下相容 45 年前的 8086。

---

## 🕰️ 什麼是 Real Mode？

**比喻：** 你買了最新的跑車，但每次發動時引擎都會先進入「腳踏車模式」，你必須手動切換到「跑車模式」。聽起來很蠢？但這就是 x86 CPU 的現實。

**Real Mode（真實模式）** 是 Intel 8086（1978 年）的原始運行模式：

| 特性 | Real Mode | 你期望的現代模式 |
|------|-----------|----------------|
| 位元寬度 | 16-bit | 64-bit |
| 可定址記憶體 | 1MB | 16EB (理論上) |
| 記憶體保護 | ❌ 沒有 | ✅ 有 |
| 多工 | ❌ 不行 | ✅ 可以 |
| 特權等級 | ❌ 沒有 | ✅ Ring 0-3 |

### 為什麼從 Real Mode 開始？

**一個字：相容性。**

Intel 的鐵律：**新 CPU 必須能跑舊軟體。** 1981 年的 DOS 程式要能在 2024 年的 i9 上跑。所以每次 CPU 重置，它都先假裝自己是一顆 8086。

這意味著你的 64 核、128GB RAM 的伺服器，開機瞬間其實是一台只能用 1MB 記憶體的 1978 年電腦。

---

## 📐 記憶體定址：Segment × 16 + Offset

Real Mode 的暫存器只有 16-bit，最大值是 `0xFFFF`（65535）。

但 8086 要定址 1MB（`0xFFFFF` = 1048575）的記憶體。16-bit 暫存器不夠大怎麼辦？

Intel 的解法：**用兩個 16-bit 值拼出 20-bit 地址。**

```
實體地址 = Segment × 16 + Offset
         = Segment << 4  + Offset

例子：
  CS = 0xF000, IP = 0xFFF0
  實體地址 = 0xF000 × 16 + 0xFFF0
           = 0xF0000 + 0xFFF0
           = 0xFFFF0        ← 就是 CPU 開機的第一個地址！
```

**比喻：** 就像地址系統「3 區 205 號」。區號 × 1000 + 門牌號 = 3205。兩個小數字拼出一個大地址。

```
20-bit 地址空間 = 1MB

0x00000 ┌──────────────┐
        │              │
        │   可用記憶體   │  ← Segment:Offset 能存取的範圍
        │              │
0xFFFFF └──────────────┘  ← 1MB 天花板
```

### Segment:Offset 的缺陷

同一個實體地址可以用多種 Segment:Offset 表示：

```
0x07C00 = 0x0000:0x7C00
        = 0x07C0:0x0000
        = 0x0700:0x0C00
        ...（還有很多種）
```

這造成了很多混亂，也是後來要改用分段/分頁的原因之一。

---

## 🚪 A20 Gate 的故事

### 問題的起源

8086 的地址線只有 20 條（A0-A19），所以最大地址是 `0xFFFFF`（1MB）。

但 Segment:Offset 能算出超過 1MB 的地址：

```
0xFFFF:0xFFFF = 0xFFFF × 16 + 0xFFFF
              = 0xFFFFF + 0xFFFF
              = 0x10FFEF    ← 超過 1MB！
```

在 8086 上，這個地址會自動「溢位」回到 0（因為只有 20 條地址線）：

```
0x10FFEF → 砍掉最高位 → 0x0FFEF
```

**有些 DOS 程式故意利用這個溢位行為！**

### 80286 的問題

80286 有 24 條地址線，`0x10FFEF` 不會溢位了。這導致那些依賴溢位的 DOS 程式壞掉了。

IBM 的解決方案：**在鍵盤控制器（!）上加一個 Gate 來控制第 21 條地址線（A20）。**

```
A20 Gate = OFF → 地址線 A20 強制為 0 → 效果等同 1MB 溢位
A20 Gate = ON  → 地址線 A20 正常 → 可以存取 1MB 以上
```

### 為什麼是鍵盤控制器？

因為 8042 鍵盤控制器剛好有一個空的輸出腳位。IBM 工程師就把 A20 Gate 接到那裡了。這個看起來荒謬的設計一直沿用到今天。

### Linux 怎麼處理 A20

在 `arch/x86/boot/pm.c` 的 `go_to_protected_mode()` 中：

```c
/* 啟用 A20 Gate — 打開 1MB 以上的記憶體存取 */
if (enable_a20()) {
    puts("A20 gate not responding, unable to boot...\n");
    die();
}
```

Linux 會嘗試多種方式開啟 A20（鍵盤控制器、Fast A20、BIOS 中斷），確保在所有硬體上都能成功。

---

## 📝 原始碼：`arch/x86/boot/header.S`

這是 Linux kernel 最開頭的程式碼。Bootloader（GRUB 或 QEMU）載入 bzImage 後，就是從這裡開始執行。

```asm
# 檔案：arch/x86/boot/header.S（Linux 6.19.3）

BOOTSEG     = 0x07C0    # 1  傳統 boot sector 載入地址（歷史原因）
SYSSEG      = 0x1000    # 2  kernel 歷史載入地址 >> 4

    .code16              # 3  告訴組譯器：以下是 16-bit 程式碼（Real Mode）
    .section ".bstext", "ax"  # 4  放在 boot sector 的 text section

# --- 如果是 EFI 啟動，這裡有 PE header ---
#ifdef CONFIG_EFI_STUB
    .word   IMAGE_DOS_SIGNATURE  # 5  "MZ" — DOS/PE 可執行檔的標誌
    # ...（EFI 相關的 PE header）
#endif
```

### header.S 的關鍵結構

header.S 定義了 **Linux Boot Protocol** 的 header，Bootloader 讀這個 header 來知道：

```
header 的重要欄位：

偏移量   欄位名              用途
─────────────────────────────────────
0x01F1   setup_sects        setup 程式碼的大小（幾個 sector）
0x0202   header              Magic: "HdrS"（表示這是 Linux kernel）
0x020E   kernel_version     kernel 版本字串的偏移量
0x0214   type_of_loader     Bootloader 的類型代碼
0x0228   cmd_line_ptr       kernel command line 的記憶體地址
0x0230   initrd_addr_max    initrd 能放的最高地址
0x0236   kernel_alignment   kernel 要對齊到幾 bytes
0x0250   init_size          kernel 解壓後的大小
```

**比喻：** header.S 就像一本書的目錄——Bootloader 讀目錄就知道 kernel 有多大、要放在哪裡、需要什麼。

---

## 🔑 關鍵概念回顧

| 概念 | 說明 |
|------|------|
| Real Mode | CPU 重置後的 16-bit 模式，相容 8086 |
| Segment:Offset | 兩個 16-bit 值拼出 20-bit 地址 |
| A20 Gate | 控制第 21 條地址線，突破 1MB 限制 |
| header.S | Linux kernel 的第一個檔案，定義 Boot Protocol |

---

## ⏭️ 下一步

Real Mode 只能定址 1MB，而且沒有記憶體保護（任何程式都能讀寫任何地址）。要進入現代的 Protected Mode，CPU 需要先設定 **GDT（全局描述符表）**。

GDT 是什麼？→ [03_GDT_AND_SEGMENTATION.md](03_GDT_AND_SEGMENTATION.md)
