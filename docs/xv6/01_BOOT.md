# 📚 01 — 開機：bootasm.S → bootmain.c

> BIOS 把 512 bytes 載入記憶體，CPU 從 1978 年開始醒來。

---

## 🔌 x86 開機流程總覽

```
電源開啟
    │
    ↓
BIOS（韌體）
    ├─ POST（自我檢測）
    ├─ 找到第一顆硬碟
    ├─ 讀取第一個磁區（512 bytes）→ 載入到 0x7C00
    └─ 跳到 0x7C00 開始執行
         │
         │  CPU 狀態：Real Mode, 16-bit
         │  CS=0, IP=0x7C00
         ↓
    bootasm.S（我們的程式碼從這裡開始！）
```

這 512 bytes 叫做 **boot sector**（開機磁區），裡面要做三件大事：

1. **啟用 A20 Gate** — 突破 1MB 記憶體限制
2. **載入 GDT，切換到 Protected Mode** — 從 16-bit 進入 32-bit
3. **呼叫 bootmain()** — 用 C 語言從磁碟載入 kernel

---

## 📄 `bootasm.S`：完整中文註解

```asm
# 檔案：bootasm.S
# 功能：開機第一段程式碼
# BIOS 把這段 code 從硬碟第一個磁區載入到 0x7C00
# CPU 處於 Real Mode，16-bit，CS=0, IP=0x7C00

#include "asm.h"
#include "memlayout.h"
#include "mmu.h"

.code16                       # 1  告訴組譯器：這是 16-bit 程式碼
.globl start
start:
  cli                         # 2  關閉中斷！
                              #    切換模式的過程不能被打斷
                              #    就像搬家時要先把門鎖上

  # ========================================
  # 清零段暫存器
  # ========================================
  xorw    %ax,%ax             # 3  AX = 0
  movw    %ax,%ds             # 4  DS = 0（資料段）
  movw    %ax,%es             # 5  ES = 0（額外段）
  movw    %ax,%ss             # 6  SS = 0（堆疊段）
  # Real Mode 下，實體位址 = segment × 16 + offset
  # 全設 0 表示用純 offset 定址

  # ========================================
  # 啟用 A20 Gate
  # ========================================
  # 為什麼？
  # 8086（1978）只有 20 條位址線（A0-A19），最多定址 1MB
  # 286+（1982）有更多位址線，但為了相容，A20 預設被鎖住
  # 不解鎖 A20，位址第 20 位永遠是 0，超過 1MB 的位址會繞回去
  #
  # 方法：透過鍵盤控制器（i8042）的 port 0x64/0x60 來啟用
  # 是的，鍵盤控制器。歷史包袱。

seta20.1:
  inb     $0x64,%al           # 7  讀鍵盤控制器狀態
  testb   $0x2,%al            # 8  bit 1 = 輸入緩衝區滿？
  jnz     seta20.1            # 9  滿的話繼續等

  movb    $0xd1,%al           # 10 命令 0xD1 = 寫輸出 port
  outb    %al,$0x64           # 11 送出命令

seta20.2:
  inb     $0x64,%al           # 12 再等鍵盤控制器準備好
  testb   $0x2,%al
  jnz     seta20.2

  movb    $0xdf,%al           # 13 0xDF = 啟用 A20
  outb    %al,$0x60           # 14 送到資料 port → A20 啟用！

  # ========================================
  # 載入 GDT，切換到 Protected Mode
  # ========================================
  # GDT = Global Descriptor Table
  # 告訴 CPU 記憶體段的基底位址、大小、權限
  # Protected Mode 必須要有 GDT

  lgdt    gdtdesc             # 15 載入 GDT 描述符
                              #    告訴 CPU：GDT 在哪裡、多大

  movl    %cr0, %eax          # 16 讀取 CR0
  orl     $CR0_PE, %eax       # 17 設定 PE 位 = 1
  movl    %eax, %cr0          # 18 寫回 CR0
                              #    🎉 CPU 現在進入 Protected Mode 了！
                              #    但 CS 還是舊的 Real Mode 值...

  # ========================================
  # Far Jump：更新 CS，正式進入 32-bit！
  # ========================================
  ljmp    $(SEG_KCODE<<3), $start32
  #                                    ↑
  # SEG_KCODE = 1, 左移 3 位 = 0x08 = GDT 第 1 個 entry（kernel code 段）
  # Far Jump 會更新 CS = 0x08
  # 同時跳到 start32 標籤繼續執行
  #
  # 為什麼需要 Far Jump？
  # 因為 CS 只能透過 far jump/call/ret 來修改
  # 不做這步，CPU 會精神分裂（Protected Mode + Real Mode 的 CS）

.code32                       # 19 以下是 32-bit 程式碼
start32:
  # ========================================
  # 設定 32-bit 的段暫存器
  # ========================================
  movw    $(SEG_KDATA<<3), %ax # 20 AX = 0x10 = GDT 第 2 個 entry（kernel data 段）
  movw    %ax, %ds             # 21 DS = kernel data
  movw    %ax, %es             # 22 ES = kernel data
  movw    %ax, %ss             # 23 SS = kernel data
  movw    $0, %ax
  movw    %ax, %fs             # 24 FS = 0（暫時不用）
  movw    %ax, %gs             # 25 GS = 0（暫時不用）

  # ========================================
  # 設定 stack，呼叫 C 語言！
  # ========================================
  movl    $start, %esp         # 26 stack 頂端 = 0x7C00
                               #    stack 往下長（往低位址）
                               #    0x7C00 以下是可用的記憶體

  call    bootmain             # 27 呼叫 bootmain()（在 bootmain.c）
                               #    → 從磁碟載入 kernel
                               #    → 不應該返回！

  # 如果 bootmain 返回了（不應該），死迴圈
spin:
  jmp     spin

# ========================================
# Bootstrap GDT（最小的 GDT）
# ========================================
.p2align 2                     # 4-byte 對齊
gdt:
  SEG_NULLASM                              # Entry 0: null 段（規定）
  SEG_ASM(STA_X|STA_R, 0x0, 0xffffffff)   # Entry 1: code 段
  #         可執行+可讀   基底=0  限制=4GB    DPL=0（Ring 0）
  SEG_ASM(STA_W, 0x0, 0xffffffff)          # Entry 2: data 段
  #       可寫           基底=0  限制=4GB    DPL=0（Ring 0）

gdtdesc:
  .word   (gdtdesc - gdt - 1)  # GDT 大小（bytes - 1）
  .long   gdt                  # GDT 位址
```

### 開機的模式切換

```
         Real Mode              Protected Mode
        (16-bit)                  (32-bit)

           cli                      start32:
           │                          │
           ├─ A20 Gate               ├─ 設定 DS, ES, SS
           │                          │
           ├─ lgdt                   ├─ 設定 stack
           │                          │
           ├─ CR0.PE = 1             └─ call bootmain
           │                               │
           └─ ljmp ──────────────────────→  │
              CS 更新！                      ↓
                                      bootmain.c（C 語言）
```

**跟 AgentOS 學過的比較：** 這跟 Linux 的 `pmjump.S` 幾乎一模一樣！差別在於 Linux 做完 Far Jump 後跳到解壓縮程式，xv6 跳到 `bootmain()`。

---

## 📄 `bootmain.c`：從磁碟載入 kernel

```c
// 檔案：bootmain.c
// 功能：從磁碟讀取 kernel 的 ELF 檔案，載入記憶體，然後跳過去
//
// 此時 CPU 在 Protected Mode，分頁還沒開
// 虛擬位址 = 物理位址（因為 GDT 的段基底 = 0）

void
bootmain(void)
{
  struct elfhdr *elf;
  struct proghdr *ph, *eph;
  void (*entry)(void);
  uchar* pa;

  elf = (struct elfhdr*)0x10000;  // 用 0x10000 當暫存區

  // 從磁碟讀第一頁（4096 bytes）
  // 這裡面包含 ELF header
  readseg((uchar*)elf, 4096, 0);

  // 確認是 ELF 格式（magic number = 0x7f454c46 = "\x7fELF"）
  if(elf->magic != ELF_MAGIC)
    return;  // 不是 ELF → 回到 bootasm.S 的死迴圈

  // 讀取每個 program segment（程式段）
  // ELF 檔案告訴我們：每段要放到哪個物理位址、多大
  ph = (struct proghdr*)((uchar*)elf + elf->phoff);
  eph = ph + elf->phnum;
  for(; ph < eph; ph++){
    pa = (uchar*)ph->paddr;           // 目標物理位址
    readseg(pa, ph->filesz, ph->off); // 從磁碟讀到記憶體
    if(ph->memsz > ph->filesz)
      stosb(pa + ph->filesz, 0, ph->memsz - ph->filesz);
      // BSS 段：檔案裡沒有但需要佔空間的部分，填 0
  }

  // 跳到 kernel 的進入點！
  // ELF header 記錄了 entry point（通常指向 entry.S）
  entry = (void(*)(void))(elf->entry);
  entry();
  // 不會返回！
}
```

### 磁碟讀取的細節

```c
// 等磁碟準備好
void waitdisk(void)
{
  while((inb(0x1F7) & 0xC0) != 0x40)  // port 0x1F7 = IDE 狀態
    ;
}

// 讀一個磁區（512 bytes）
void readsect(void *dst, uint offset)
{
  waitdisk();
  outb(0x1F2, 1);                      // 讀 1 個磁區
  outb(0x1F3, offset);                  // LBA 位址（低 8 位）
  outb(0x1F4, offset >> 8);             // LBA 位址（8-15 位）
  outb(0x1F5, offset >> 16);            // LBA 位址（16-23 位）
  outb(0x1F6, (offset >> 24) | 0xE0);   // LBA 模式 + 高 4 位
  outb(0x1F7, 0x20);                    // 命令 0x20 = 讀取磁區

  waitdisk();
  insl(0x1F0, dst, SECTSIZE/4);         // 從 port 0x1F0 讀 128 個 dword
}
```

**比喻：** `bootmain` 就像快遞員——它知道包裹（kernel）在倉庫（磁碟）的哪裡，按照出貨單（ELF header）把每箱貨（program segment）搬到指定地址，最後打電話通知收件人（`entry()`）。

---

## 🔄 Boot 完整流程

```
BIOS
  │  讀硬碟第一個磁區（512 bytes）→ 0x7C00
  ↓
bootasm.S @ 0x7C00（Real Mode, 16-bit）
  │
  ├─ cli（關中斷）
  ├─ 清零段暫存器
  ├─ 啟用 A20 Gate（透過鍵盤控制器 🤦）
  ├─ lgdt（載入 bootstrap GDT）
  ├─ CR0.PE = 1 ─── 🎉 進入 Protected Mode！
  ├─ ljmp ─── CS 更新為 0x08
  │
  └─ start32（32-bit）
       ├─ 設定 DS/ES/SS = 0x10
       ├─ ESP = 0x7C00（stack）
       └─ call bootmain
            │
            ↓
bootmain.c（Protected Mode, 32-bit, 分頁未開）
  │
  ├─ 從磁碟讀 ELF header
  ├─ 驗證 ELF magic number
  ├─ 逐段載入 kernel 到記憶體
  └─ 跳到 kernel entry point
       │
       ↓
entry.S（下一章！）
```

### Boot Sector 大小限制

整個 `bootasm.S` + `bootmain.c` 編譯後必須 ≤ **512 bytes**！

```
512 bytes 的配置：
┌──────────────────────────────────┐
│ bootasm.S 的機器碼               │
│ bootmain.c 的機器碼              │  最多 510 bytes
│ ...                              │
│ （空間很緊！）                    │
├──────────────────────────────────┤
│ 0x55 0xAA                        │  最後 2 bytes = boot 簽名
└──────────────────────────────────┘
   byte 0                    byte 511

BIOS 檢查最後兩個 byte 是否為 0x55AA
如果不是，就不認為這是可開機的磁區
```

---

## 💻【實作】用 objdump 看 boot sector

不需要寫程式，直接觀察 xv6 的 boot sector：

```bash
cd ~/xv6-public

# 反組譯 boot sector
objdump -d bootblock.o | head -60

# 看看 boot sector 有多大
ls -la bootblock
# 應該剛好 512 bytes！

# 驗證最後兩個 byte 是 0x55 0xAA
xxd bootblock | tail -1
# 應該看到 ... 55aa
```

試試看：

```bash
cd ~/xv6-public
make
xxd bootblock | tail -3
```

你會看到：
```
000001e0: 0000 0000 0000 0000 0000 0000 0000 0000  ................
000001f0: 0000 0000 0000 0000 0000 0000 0000 55aa  ..............U.
```

最後兩個 byte `55 aa` —— 這就是 BIOS 辨認開機磁區的標記！

---

## 🔑 關鍵概念回顧

| 概念 | 說明 |
|------|------|
| 0x7C00 | BIOS 載入 boot sector 的位址 |
| A20 Gate | 啟用第 21 條位址線，突破 1MB 限制 |
| GDT | Global Descriptor Table，段描述符表 |
| CR0.PE | 設為 1 → Protected Mode |
| Far Jump (ljmp) | 更新 CS 的唯一方式 |
| ELF | kernel 的執行檔格式 |
| 0x55AA | Boot sector 的魔術簽名 |
| IDE port 0x1F0-0x1F7 | 磁碟 I/O 的控制 port |

---

## ⏭️ 下一步

`bootmain()` 把 kernel 從磁碟載入記憶體，然後跳到 `entry()`。接下來——

**開啟分頁、設定 kernel 的 stack、跳到高位址的 `main()`。**

→ [02_ENTRY.md — entry.S：開啟分頁，跳到 main()](02_ENTRY.md)
