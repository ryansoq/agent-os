/* === 02: Protected Mode ===
 * 🔑 從 16-bit Real Mode 切換到 32-bit Protected Mode
 * 🔑 需要：關中斷 → 開 A20 → 設 GDT → 設 CR0.PE → far jump
 */
.code16                      /* 🔑 一開始還是 16-bit Real Mode */

.globl _start
_start:
    /* === 初始化 segment registers === */
    xorw %ax, %ax            /* 🔑 AX = 0 */
    movw %ax, %ds            /* 🔑 Data Segment = 0 */
    movw %ax, %es            /* 🔑 Extra Segment = 0 */
    movw %ax, %ss            /* 🔑 Stack Segment = 0 */
    movw $0x7C00, %sp        /* 🔑 Stack 向下生長 */

    /* === 關閉中斷 === */
    cli                      /* 🔑 進入 Protected Mode 前必須關中斷 */
                             /*     因為 Real Mode 的中斷向量表在 PM 下無效 */

    /* === 開啟 A20 Gate === */
    /* 🔑 A20 是第 21 條位址線，預設被關閉（為了相容 8086） */
    /* 🔑 不開 A20 的話，位址會 wrap around，只能存取 1MB */
    inb $0x92, %al           /* 🔑 讀取 System Control Port A */
    orb $2, %al              /* 🔑 設定 bit 1 = 啟用 A20 */
    outb %al, $0x92          /* 🔑 寫回，Fast A20 Gate 開啟 */

    /* === 載入 GDT === */
    lgdt gdt_descriptor      /* 🔑 載入 GDT 描述符到 GDTR 暫存器 */

    /* === 設定 CR0.PE = 1，進入 Protected Mode === */
    /* 🔑 設 CR0.PE=1 就像按下「升級開關」
     *     Real Mode → Protected Mode
     *     從「沒有門禁的老舊公寓」→「有門禁的現代大樓」
     *     按下去之後，所有記憶體存取都要經過 GDT 的權限檢查 */
    movl %cr0, %eax          /* 🔑 讀取 Control Register 0 */
    orl $1, %eax             /* 🔑 設定 bit 0 = PE (Protection Enable) */
    movl %eax, %cr0          /* 🔑 寫回！CPU 現在進入 Protected Mode */

    /* === Far Jump 到 32-bit Code Segment === */
    /* 🔑 far jump 做兩件事：
     *     1. 清空 CPU pipeline（因為模式切換了）
     *     2. 載入新的 CS selector (0x08 = GDT 第 1 個 entry） */
    ljmp $0x08, $pm_entry    /* 🔑 0x08 = GDT code segment 的 offset */

/* ============================================================
 * GDT (Global Descriptor Table)
 *
 * 🏰 比喻：GDT 就像辦公大樓的門禁卡設定表
 *     卡片 0: 空卡（CPU 規定第一張一定要是空的）
 *     卡片 1: 員工卡（Code Segment）→ 能進辦公區執行程式
 *     卡片 2: 倉庫卡（Data Segment）→ 能進倉庫讀寫資料
 *
 * 🎖️ DPL（特權等級）就像門禁卡的等級：
 *     Ring 0 = 大樓管理員 👑 → 能開所有門、改門禁、關電源
 *     Ring 3 = 一般訪客 🧑 → 只能進大廳和會議室
 *     想從 Ring 3 進 Ring 0？→ 按「服務鈴」(syscall)，管理員決定幫不幫你
 *
 * 🔑 GDT 定義記憶體分段的存取權限和範圍
 * 🔑 每個 entry 8 bytes，描述一個 segment
 * ============================================================ */

gdt_start:

gdt_null:
    /* 🔑 GDT 第 0 個 entry 必須是 null descriptor（CPU 規定） */
    .quad 0x0000000000000000   /* 🔑 全部填 0 */

gdt_code:
    /* 🔑 Code Segment Descriptor (0x00CF9A000000FFFF)
     *
     *  完整 8 bytes 的 Bit Field 拆解：
     *  ┌─────────┬──────┬───┬────┬───┬─────┬──────────┬──────────┐
     *  │ Base    │ Flags│ L │ Sz │ 0 │ Lim │ Access   │ Base     │
     *  │ 31:24  │ G  D │   │    │   │19:16│ P DPL S  │ 23:16   │
     *  │ 0x00   │ 1  1 │ 0 │ 0  │ 0 │ 0xF │1 00  1   │ 0x00    │
     *  └─────────┴──────┴───┴────┴───┴─────┴──────────┴──────────┘
     *
     *  G=1: Granularity，Limit 單位是 4KB（0xFFFFF × 4KB = 4GB）
     *  D=1: Default operand size = 32-bit
     *  L=0: 非 64-bit 模式（Long Mode 才用）
     *  P=1: Present，段存在於記憶體中
     *  DPL=00: Descriptor Privilege Level = Ring 0（最高權限）
     *  S=1: 非系統段（Code 或 Data）
     *  Type=1010: Execute/Read（可執行、可讀取） */
    .word 0xFFFF       /* 🔑 Limit 15:0 = 0xFFFF（搭配 G=1，最大 4GB） */
    .word 0x0000       /* 🔑 Base 15:0 = 0x0000（從位址 0 開始） */
    .byte 0x00         /* 🔑 Base 23:16 = 0x00 */
    .byte 0b10011010   /* 🔑 Access Byte: P=1, DPL=00, S=1, Type=1010 (exec/read) */
    .byte 0b11001111   /* 🔑 Flags: G=1, D=1, L=0, 0 + Limit 19:16 = 0xF */
    .byte 0x00         /* 🔑 Base 31:24 = 0x00 */

gdt_data:
    /* 🔑 Data Segment Descriptor (0x00CF92000000FFFF)
     *
     *  與 Code Segment 幾乎相同，差別在 Type：
     *  Type=0010: Read/Write（可讀、可寫）
     *  D=1 在 Data Segment 稱為 B(Big)=1：使用 32-bit stack pointer (ESP) */
    .word 0xFFFF       /* 🔑 Limit 15:0 = 0xFFFF */
    .word 0x0000       /* 🔑 Base 15:0 = 0x0000 */
    .byte 0x00         /* 🔑 Base 23:16 = 0x00 */
    .byte 0b10010010   /* 🔑 Access Byte: P=1, DPL=00, S=1, Type=0010 (read/write) */
    .byte 0b11001111   /* 🔑 Flags: G=1, B=1, L=0, 0 + Limit 19:16 = 0xF */
    .byte 0x00         /* 🔑 Base 31:24 = 0x00 */

gdt_end:

gdt_descriptor:
    .word gdt_end - gdt_start - 1  /* 🔑 GDT 大小（byte 數 - 1） */
    .long gdt_start                /* 🔑 GDT 的線性位址 */

/* ============================================================
 * 32-bit Protected Mode 程式碼
 * ============================================================ */
.code32                      /* 🔑 從這裡開始是 32-bit 指令 */

pm_entry:
    /* === 設定 data segment registers === */
    movw $0x10, %ax          /* 🔑 0x10 = GDT 第 2 個 entry（data segment）的 selector */
    movw %ax, %ds            /* 🔑 Data Segment 指向 GDT data descriptor */
    movw %ax, %es            /* 🔑 Extra Segment */
    movw %ax, %fs            /* 🔑 FS Segment */
    movw %ax, %gs            /* 🔑 GS Segment */
    movw %ax, %ss            /* 🔑 Stack Segment */
    movl $0x90000, %esp      /* 🔑 Stack pointer 設在高位址（有足夠空間向下生長） */

    /* --- 在 Protected Mode 下用 Serial Port 印字 ---
     * 🔑 在 Protected Mode 下不能用 BIOS 中斷！
     * 🔑 但我們可以直接用 I/O port 操作硬體（這就是 kernel 做的事！）
     * 🔑 COM1 serial port 的 I/O port 基底位址是 0x3F8
     *
     * 🔑 比喻：BIOS 中斷就像「叫服務生送餐」
     *     Serial port 就像「自己走到廚房拿」
     *     Protected Mode 沒有服務生了，你就是老闆，直接操作一切！ */

    .equ COM1, 0x3F8

    /* 初始化 serial port */
    movw $(COM1 + 1), %dx    /* Interrupt Enable Register */
    movb $0x00, %al          /* 關閉所有中斷 */
    outb %al, %dx
    movw $(COM1 + 3), %dx    /* Line Control Register */
    movb $0x80, %al          /* 啟用 DLAB (設定 baud rate) */
    outb %al, %dx
    movw $(COM1 + 0), %dx    /* Divisor (低 byte) */
    movb $0x03, %al          /* 38400 baud */
    outb %al, %dx
    movw $(COM1 + 1), %dx    /* Divisor (高 byte) */
    movb $0x00, %al
    outb %al, %dx
    movw $(COM1 + 3), %dx    /* Line Control Register */
    movb $0x03, %al          /* 8 bits, no parity, 1 stop bit */
    outb %al, %dx

    /* 印字串到 serial port */
    movl $pm_msg, %esi
1:  /* .pm_loop */
    lodsb                    /* 🔑 AL = [ESI], ESI++ */
    testb %al, %al           /* 🔑 檢查 null terminator */
    jz 2f                    /* 🔑 結束 */

    /* 等待 transmit ready */
    pushl %eax               /* 🔑 保存字元 */
    movw $(COM1 + 5), %dx    /* Line Status Register */
3:  /* .wait_tx */
    inb %dx, %al
    testb $0x20, %al         /* 🔑 bit 5 = Transmit Holding Register Empty */
    jz 3b

    /* 送出字元 */
    popl %eax                /* 🔑 取回字元 */
    movw $COM1, %dx
    outb %al, %dx            /* 🔑 送出到 serial port */
    jmp 1b                   /* 🔑 繼續印下一個字元 */

2:  /* .pm_done */
    cli                      /* 🔑 關中斷 */
4:  /* .pm_halt */
    hlt                      /* 🔑 停止 CPU */
    jmp 4b                   /* 🔑 無限迴圈 */

pm_msg:
    .byte 13, 10
    .ascii "=== Agent OS Example 02: Protected Mode ==="
    .byte 13, 10
    .ascii "Hello from 32-bit Protected Mode! GDT works!"
    .byte 13, 10
    .ascii "We are using serial port (COM1) for output -- no VGA needed!"
    .byte 13, 10, 0

/* === 填充與 Boot Signature === */
.org 510                     /* 🔑 填滿到 510 bytes */
.word 0xAA55                 /* 🔑 Boot signature */
