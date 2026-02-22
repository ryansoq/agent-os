/* === 03: Long Mode (64-bit) ===
 * 🔑 從 Real Mode → Protected Mode → Long Mode (64-bit)
 * 🔑 需要：GDT + 4 級頁表 + PAE + EFER.LME + CR0.PG
 */
.code16                      /* 🔑 開機時是 16-bit Real Mode */

.globl _start
_start:
    /* === 初始化 === */
    xorw %ax, %ax            /* 🔑 AX = 0 */
    movw %ax, %ds            /* 🔑 Data Segment = 0 */
    movw %ax, %es            /* 🔑 Extra Segment = 0 */
    movw %ax, %ss            /* 🔑 Stack Segment = 0 */
    movw $0x7C00, %sp        /* 🔑 Stack 向下生長 */

    cli                      /* 🔑 關閉中斷 */

    /* === 開啟 A20 Gate === */
    inb $0x92, %al           /* 🔑 Fast A20 */
    orb $2, %al              /* 🔑 設定 bit 1 */
    outb %al, $0x92          /* 🔑 開啟 A20 */

    /* === 檢查 CPUID 是否支援 Long Mode === */
    movl $0x80000000, %eax   /* 🔑 檢查 extended CPUID 是否可用 */
    cpuid                    /* 🔑 執行 CPUID */
    cmpl $0x80000001, %eax   /* 🔑 需要至少支援到 0x80000001 */
    jb no_long_mode          /* 🔑 不支援就跳到錯誤處理 */

    movl $0x80000001, %eax   /* 🔑 查詢 extended feature flags */
    cpuid                    /* 🔑 執行 CPUID */
    testl $(1 << 29), %edx   /* 🔑 檢查 bit 29 = LM (Long Mode) 支援 */
    jz no_long_mode          /* 🔑 不支援就跳到錯誤處理 */

    /* === 建立 4 級頁表 (Identity Map 前 2MB) ===
     *
     * 🗺️ 比喻：頁表就像每個房客拿到的「客製化地圖」
     *     Chrome 的地圖：「地址 0x1000 → 實際在 RAM 的 0x50000」
     *     Firefox 的地圖：「地址 0x1000 → 實際在 RAM 的 0x80000」
     *     兩個人用同一個地址，但去到不同地方！互相看不到！
     *
     *     Identity Map = 「地圖上的地址 = 實際地址」（開機時最簡單的做法）
     *
     * 🔑 Long Mode 強制使用分頁，需要 4 級頁表結構：
     *     PML4 → PDPT → PD → PT（或用 2MB 大頁省略 PT）
     *
     * 🔑 頁表記憶體配置（每個表 4KB = 0x1000 bytes）：
     *     PML4  = 0x1000
     *     PDPT  = 0x2000
     *     PD    = 0x3000
     */

    /* --- 先清空頁表區域 --- */
    movl $0x1000, %edi       /* 🔑 從 0x1000 開始清空 */
    movl %edi, %cr3          /* 🔑 同時把 PML4 位址存入 CR3 */
    xorl %eax, %eax          /* 🔑 EAX = 0 */
    movl $0xC00, %ecx        /* 🔑 清空 3 個頁面 = 3 × 4KB / 4 = 0xC00 個 dword */
    rep stosl                /* 🔑 用 0 填滿 [EDI] 到 [EDI + ECX*4] */

    /* --- 設定 PML4[0] → PDPT --- */
    movl $0x1000, %edi               /* 🔑 EDI = PML4 起始位址 */
    movl $0x2003, (%edi)             /* 🔑 PML4[0] = 0x2003 */
    /*
     * 🔑 PML4 Entry 格式 (低 32 bits)：
     * ┌────────────────────────────┬───┬───┬───┬───┬───┬───┐
     * │ PDPT 物理位址 (高位)      │...│ 0 │ 0 │ 0 │R/W│ P │
     * │ 0x2000                    │   │   │   │   │ 1 │ 1 │
     * └────────────────────────────┴───┴───┴───┴───┴───┴───┘
     * P=1:   Present（存在）
     * R/W=1: Read/Write（可讀寫）
     * 位址=0x2000: 指向 PDPT 表
     */

    /* --- 設定 PDPT[0] → PD --- */
    movl $0x2000, %edi               /* 🔑 EDI = PDPT 起始位址 */
    movl $0x3003, (%edi)             /* 🔑 PDPT[0] = 0x3003 */
    /*
     * 🔑 PDPT Entry 格式：與 PML4 Entry 相同
     * P=1, R/W=1, 位址=0x3000: 指向 PD 表
     */

    /* --- 設定 PD[0] → 2MB 大頁 (identity map) --- */
    movl $0x3000, %edi               /* 🔑 EDI = PD 起始位址 */
    movl $0x0083, (%edi)             /* 🔑 PD[0] = 0x0083 */
    /*
     * 🔑 PD Entry 格式 (2MB 大頁)：
     * ┌────────────────────────────┬───┬───┬───┬───┬───┬───┬───┐
     * │ 物理位址 (高位)           │...│PS │ 0 │ 0 │ 0 │R/W│ P │
     * │ 0x00000                   │   │ 1 │   │   │   │ 1 │ 1 │
     * └────────────────────────────┴───┴───┴───┴───┴───┴───┴───┘
     * P=1:   Present（存在）
     * R/W=1: Read/Write（可讀寫）
     * PS=1:  Page Size = 2MB（不再往下查 PT，直接映射 2MB）
     * 位址=0x0: 物理位址 0x0 → 虛擬位址 0x0（Identity Map）
     *
     * 🔑 這樣 virtual 0x00000000-0x001FFFFF = physical 0x00000000-0x001FFFFF
     */

    /* === 開啟 PAE (Physical Address Extension) === */
    movl %cr4, %eax          /* 🔑 讀取 CR4 */
    orl $(1 << 5), %eax      /* 🔑 設定 bit 5 = PAE */
    movl %eax, %cr4          /* 🔑 寫回 CR4 */
    /* 🔑 PAE 是 Long Mode 的前提，允許使用 4 級頁表 */

    /* === 設定 EFER.LME = 1 (啟用 Long Mode) ===
     * 🚀 比喻：從 32-bit 到 64-bit 就像從「縣道」到「高速公路」
     *     32-bit: 最多 4GB RAM（像只有 4 個車道的縣道）
     *     64-bit: 理論 16 EB RAM（像 1800 萬條車道的高速公路）
     *     但上高速公路之前，你得先拿到「ETC 通行證」(EFER.LME=1)
     *     然後開過「收費站」(CR0.PG=1)
     */
    movl $0xC0000080, %ecx   /* 🔑 EFER (Extended Feature Enable Register) 的 MSR 編號 */
    rdmsr                    /* 🔑 讀取 MSR 到 EDX:EAX */
    orl $(1 << 8), %eax      /* 🔑 設定 bit 8 = LME (Long Mode Enable) */
    wrmsr                    /* 🔑 寫回 MSR */
    /* 🔑 注意：此時還沒真正進入 Long Mode，要等開啟 Paging */

    /* === 載入 GDT（含 64-bit code segment）=== */
    lgdt gdt_descriptor      /* 🔑 載入 GDT */

    /* === 開啟 Paging + Protection Enable === */
    movl %cr0, %eax          /* 🔑 讀取 CR0 */
    orl $((1 << 31) | (1 << 0)), %eax  /* 🔑 bit 31 = PG (Paging), bit 0 = PE (Protection) */
    movl %eax, %cr0          /* 🔑 寫回！現在正式進入 Long Mode (compatibility sub-mode) */

    /* === Far Jump 到 64-bit Code === */
    ljmp $0x08, $lm_entry    /* 🔑 跳到 64-bit code segment（GDT entry 1, offset 0x08） */

/* === 不支援 Long Mode 的錯誤處理 === */
no_long_mode:
    movw $no_lm_msg, %si    /* 🔑 印錯誤訊息 */
1:  /* .err_loop */
    lodsb
    testb %al, %al
    jz 2f
    movb $0x0E, %ah
    int $0x10
    jmp 1b
2:  /* .err_halt */
    hlt
    jmp 2b

no_lm_msg:
    .ascii "ERROR: CPU does not support 64-bit Long Mode!"
    .byte 0

/* ============================================================
 * GDT for Long Mode
 * ============================================================ */

gdt_start:

gdt_null:
    .quad 0x0000000000000000   /* 🔑 Null descriptor（必須） */

gdt_code64:
    /* 🔑 64-bit Code Segment Descriptor
     *
     * ┌─────────┬──────┬───┬────┬───┬─────┬──────────┬──────────┐
     * │ Base    │ Flags│ L │ Sz │ 0 │ Lim │ Access   │ Base     │
     * │ 31:24  │ G  D │   │    │   │19:16│ P DPL S  │ 23:16   │
     * │ 0x00   │ 0  0 │ 1 │ 0  │ 0 │ 0x0 │1 00  1   │ 0x00    │
     * └─────────┴──────┴───┴────┴───┴─────┴──────────┴──────────┘
     *
     * 🔑 L=1: Long Mode（64-bit）！這是和 32-bit 最大的差別
     * 🔑 D=0: 在 Long Mode 下 D 必須為 0
     * 🔑 G=0, Limit=0: Long Mode 忽略 Base 和 Limit
     */
    .word 0x0000       /* 🔑 Limit 15:0（Long Mode 忽略） */
    .word 0x0000       /* 🔑 Base 15:0（Long Mode 忽略） */
    .byte 0x00         /* 🔑 Base 23:16 */
    .byte 0b10011010   /* 🔑 Access: P=1, DPL=00, S=1, Type=1010 (exec/read) */
    .byte 0b00100000   /* 🔑 Flags: G=0, D=0, L=1, 0 + Limit 19:16 = 0x0 */
    .byte 0x00         /* 🔑 Base 31:24 */

gdt_data64:
    /* 🔑 64-bit Data Segment Descriptor */
    .word 0x0000       /* 🔑 Limit（Long Mode 忽略） */
    .word 0x0000       /* 🔑 Base */
    .byte 0x00         /* 🔑 Base */
    .byte 0b10010010   /* 🔑 Access: P=1, DPL=00, S=1, Type=0010 (read/write) */
    .byte 0b00000000   /* 🔑 Flags */
    .byte 0x00         /* 🔑 Base */

gdt_end:

gdt_descriptor:
    .word gdt_end - gdt_start - 1  /* 🔑 GDT 大小 */
    .long gdt_start                /* 🔑 GDT 位址 */

/* ============================================================
 * 64-bit Long Mode 程式碼
 * ============================================================ */
.code64                      /* 🔑 64-bit 指令 */

lm_entry:
    /* === 設定 data segments === */
    movw $0x10, %ax          /* 🔑 data segment selector */
    movw %ax, %ds            /* 🔑 Data Segment */
    movw %ax, %es            /* 🔑 Extra Segment */
    movw %ax, %fs            /* 🔑 FS */
    movw %ax, %gs            /* 🔑 GS */
    movw %ax, %ss            /* 🔑 Stack Segment */

    /* --- 在 Long Mode 下用 Serial Port 印字 ---
     * 🔑 在 Long Mode 下一樣可以用 out 指令操作 I/O port
     * 🔑 COM1 serial port 的 I/O port 基底位址是 0x3F8
     */

    /* 初始化 serial port */
    movw $0x3F9, %dx         /* COM1 + 1: Interrupt Enable Register */
    movb $0x00, %al
    outb %al, %dx
    movw $0x3FB, %dx         /* COM1 + 3: Line Control Register */
    movb $0x80, %al          /* DLAB */
    outb %al, %dx
    movw $0x3F8, %dx         /* COM1 + 0: Divisor low */
    movb $0x03, %al          /* 38400 baud */
    outb %al, %dx
    movw $0x3F9, %dx         /* COM1 + 1: Divisor high */
    movb $0x00, %al
    outb %al, %dx
    movw $0x3FB, %dx         /* COM1 + 3: Line Control Register */
    movb $0x03, %al          /* 8N1 */
    outb %al, %dx

    /* 印字串到 serial port */
    movq $lm_msg, %rsi       /* 🔑 RSI = 字串位址（64-bit 暫存器！） */
1:  /* .lm_loop */
    lodsb                    /* 🔑 AL = [RSI], RSI++ */
    testb %al, %al           /* 🔑 檢查 null terminator */
    jz 2f                    /* 🔑 結束 */

    /* 等待 transmit ready */
    pushq %rax               /* 🔑 保存字元 */
    movw $0x3FD, %dx         /* COM1 + 5: Line Status Register */
3:  /* .wait_tx */
    inb %dx, %al
    testb $0x20, %al         /* 🔑 bit 5 = Transmit Holding Register Empty */
    jz 3b

    /* 送出字元 */
    popq %rax                /* 🔑 取回字元 */
    movw $0x3F8, %dx         /* COM1 */
    outb %al, %dx            /* 🔑 送出到 serial port */
    jmp 1b                   /* 🔑 繼續 */

2:  /* .lm_done */
    cli                      /* 🔑 關中斷 */
4:  /* .lm_halt */
    hlt                      /* 🔑 停止 CPU */
    jmp 4b                   /* 🔑 無限迴圈 */

lm_msg:
    .byte 13, 10
    .ascii "=== Agent OS Example 03: Long Mode (64-bit) ==="
    .byte 13, 10
    .ascii "Hello from 64-bit Long Mode! Welcome to the future!"
    .byte 13, 10
    .ascii "We set up 4-level page tables and entered 64-bit mode!"
    .byte 13, 10, 0

/* === 填充與 Boot Signature === */
.org 510                     /* 🔑 填滿到 510 bytes */
.word 0xAA55                 /* 🔑 Boot signature */
