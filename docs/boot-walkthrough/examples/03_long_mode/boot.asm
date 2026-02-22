; === 03: Long Mode (64-bit) ===
; 🔑 從 Real Mode → Protected Mode → Long Mode (64-bit)
; 🔑 需要：GDT + 4 級頁表 + PAE + EFER.LME + CR0.PG
;
[bits 16]               ; 🔑 開機時是 16-bit Real Mode
[org 0x7C00]            ; 🔑 BIOS 載入位址

start:
    ; === 初始化 ===
    xor ax, ax          ; 🔑 AX = 0
    mov ds, ax          ; 🔑 Data Segment = 0
    mov es, ax          ; 🔑 Extra Segment = 0
    mov ss, ax          ; 🔑 Stack Segment = 0
    mov sp, 0x7C00      ; 🔑 Stack 向下生長

    cli                 ; 🔑 關閉中斷

    ; === 開啟 A20 Gate ===
    in al, 0x92         ; 🔑 Fast A20
    or al, 2            ; 🔑 設定 bit 1
    out 0x92, al        ; 🔑 開啟 A20

    ; === 檢查 CPUID 是否支援 Long Mode ===
    mov eax, 0x80000000 ; 🔑 檢查 extended CPUID 是否可用
    cpuid               ; 🔑 執行 CPUID
    cmp eax, 0x80000001 ; 🔑 需要至少支援到 0x80000001
    jb no_long_mode     ; 🔑 不支援就跳到錯誤處理

    mov eax, 0x80000001 ; 🔑 查詢 extended feature flags
    cpuid               ; 🔑 執行 CPUID
    test edx, (1 << 29) ; 🔑 檢查 bit 29 = LM (Long Mode) 支援
    jz no_long_mode     ; 🔑 不支援就跳到錯誤處理

    ; === 建立 4 級頁表 (Identity Map 前 2MB) ===
    ;
    ; 🗺️ 比喻：頁表就像每個房客拿到的「客製化地圖」
    ;     Chrome 的地圖：「地址 0x1000 → 實際在 RAM 的 0x50000」
    ;     Firefox 的地圖：「地址 0x1000 → 實際在 RAM 的 0x80000」
    ;     兩個人用同一個地址，但去到不同地方！互相看不到！
    ;
    ;     Identity Map = 「地圖上的地址 = 實際地址」（開機時最簡單的做法）
    ;
    ; 🔑 Long Mode 強制使用分頁，需要 4 級頁表結構：
    ;     PML4 → PDPT → PD → PT（或用 2MB 大頁省略 PT）
    ;
    ; 🔑 頁表記憶體配置（每個表 4KB = 0x1000 bytes）：
    ;     PML4  = 0x1000
    ;     PDPT  = 0x2000
    ;     PD    = 0x3000

    ; --- 先清空頁表區域 ---
    mov edi, 0x1000     ; 🔑 從 0x1000 開始清空
    mov cr3, edi        ; 🔑 同時把 PML4 位址存入 CR3
    xor eax, eax        ; 🔑 EAX = 0
    mov ecx, 0xC00      ; 🔑 清空 3 個頁面 = 3 × 4KB / 4 = 0xC00 個 dword
    rep stosd           ; 🔑 用 0 填滿 [EDI] 到 [EDI + ECX*4]

    ; --- 設定 PML4[0] → PDPT ---
    mov edi, 0x1000             ; 🔑 EDI = PML4 起始位址
    mov dword [edi], 0x2003     ; 🔑 PML4[0] = 0x2003
    ;                           ;
    ; 🔑 PML4 Entry 格式 (低 32 bits)：
    ; ┌────────────────────────────┬───┬───┬───┬───┬───┬───┐
    ; │ PDPT 物理位址 (高位)      │...│ 0 │ 0 │ 0 │R/W│ P │
    ; │ 0x2000                    │   │   │   │   │ 1 │ 1 │
    ; └────────────────────────────┴───┴───┴───┴───┴───┴───┘
    ; P=1:   Present（存在）
    ; R/W=1: Read/Write（可讀寫）
    ; 位址=0x2000: 指向 PDPT 表

    ; --- 設定 PDPT[0] → PD ---
    mov edi, 0x2000             ; 🔑 EDI = PDPT 起始位址
    mov dword [edi], 0x3003     ; 🔑 PDPT[0] = 0x3003
    ;
    ; 🔑 PDPT Entry 格式：與 PML4 Entry 相同
    ; P=1, R/W=1, 位址=0x3000: 指向 PD 表

    ; --- 設定 PD[0] → 2MB 大頁 (identity map) ---
    mov edi, 0x3000             ; 🔑 EDI = PD 起始位址
    mov dword [edi], 0x0083     ; 🔑 PD[0] = 0x0083
    ;
    ; 🔑 PD Entry 格式 (2MB 大頁)：
    ; ┌────────────────────────────┬───┬───┬───┬───┬───┬───┬───┐
    ; │ 物理位址 (高位)           │...│PS │ 0 │ 0 │ 0 │R/W│ P │
    ; │ 0x00000                   │   │ 1 │   │   │   │ 1 │ 1 │
    ; └────────────────────────────┴───┴───┴───┴───┴───┴───┴───┘
    ; P=1:   Present（存在）
    ; R/W=1: Read/Write（可讀寫）
    ; PS=1:  Page Size = 2MB（不再往下查 PT，直接映射 2MB）
    ; 位址=0x0: 物理位址 0x0 → 虛擬位址 0x0（Identity Map）
    ;
    ; 🔑 這樣 virtual 0x00000000-0x001FFFFF = physical 0x00000000-0x001FFFFF

    ; === 開啟 PAE (Physical Address Extension) ===
    mov eax, cr4        ; 🔑 讀取 CR4
    or eax, (1 << 5)    ; 🔑 設定 bit 5 = PAE
    mov cr4, eax        ; 🔑 寫回 CR4
    ; 🔑 PAE 是 Long Mode 的前提，允許使用 4 級頁表

    ; === 設定 EFER.LME = 1 (啟用 Long Mode) ===
    ; 🚀 比喻：從 32-bit 到 64-bit 就像從「縣道」到「高速公路」
    ;     32-bit: 最多 4GB RAM（像只有 4 個車道的縣道）
    ;     64-bit: 理論 16 EB RAM（像 1800 萬條車道的高速公路）
    ;     但上高速公路之前，你得先拿到「ETC 通行證」(EFER.LME=1)
    ;     然後開過「收費站」(CR0.PG=1)
    mov ecx, 0xC0000080 ; 🔑 EFER (Extended Feature Enable Register) 的 MSR 編號
    rdmsr               ; 🔑 讀取 MSR 到 EDX:EAX
    or eax, (1 << 8)    ; 🔑 設定 bit 8 = LME (Long Mode Enable)
    wrmsr               ; 🔑 寫回 MSR
    ; 🔑 注意：此時還沒真正進入 Long Mode，要等開啟 Paging

    ; === 載入 GDT（含 64-bit code segment）===
    lgdt [gdt_descriptor] ; 🔑 載入 GDT

    ; === 開啟 Paging + Protection Enable ===
    mov eax, cr0        ; 🔑 讀取 CR0
    or eax, (1 << 31) | (1 << 0)  ; 🔑 bit 31 = PG (Paging), bit 0 = PE (Protection)
    mov cr0, eax        ; 🔑 寫回！現在正式進入 Long Mode (compatibility sub-mode)

    ; === Far Jump 到 64-bit Code ===
    jmp 0x08:lm_entry   ; 🔑 跳到 64-bit code segment（GDT entry 1, offset 0x08）

; === 不支援 Long Mode 的錯誤處理 ===
no_long_mode:
    mov si, no_lm_msg   ; 🔑 印錯誤訊息
.err_loop:
    lodsb
    test al, al
    jz .err_halt
    mov ah, 0x0E
    int 0x10
    jmp .err_loop
.err_halt:
    hlt
    jmp .err_halt

no_lm_msg: db "ERROR: CPU does not support 64-bit Long Mode!", 0

; ============================================================
; GDT for Long Mode
; ============================================================

gdt_start:

gdt_null:
    dq 0x0000000000000000   ; 🔑 Null descriptor（必須）

gdt_code64:
    ; 🔑 64-bit Code Segment Descriptor
    ;
    ; ┌─────────┬──────┬───┬────┬───┬─────┬──────────┬──────────┐
    ; │ Base    │ Flags│ L │ Sz │ 0 │ Lim │ Access   │ Base     │
    ; │ 31:24  │ G  D │   │    │   │19:16│ P DPL S  │ 23:16   │
    ; │ 0x00   │ 0  0 │ 1 │ 0  │ 0 │ 0x0 │1 00  1   │ 0x00    │
    ; └─────────┴──────┴───┴────┴───┴─────┴──────────┴──────────┘
    ;
    ; 🔑 L=1: Long Mode（64-bit）！這是和 32-bit 最大的差別
    ; 🔑 D=0: 在 Long Mode 下 D 必須為 0
    ; 🔑 G=0, Limit=0: Long Mode 忽略 Base 和 Limit
    ;
    dw 0x0000       ; 🔑 Limit 15:0（Long Mode 忽略）
    dw 0x0000       ; 🔑 Base 15:0（Long Mode 忽略）
    db 0x00         ; 🔑 Base 23:16
    db 10011010b    ; 🔑 Access: P=1, DPL=00, S=1, Type=1010 (exec/read)
    db 00100000b    ; 🔑 Flags: G=0, D=0, L=1, 0 + Limit 19:16 = 0x0
    db 0x00         ; 🔑 Base 31:24

gdt_data64:
    ; 🔑 64-bit Data Segment Descriptor
    dw 0x0000       ; 🔑 Limit（Long Mode 忽略）
    dw 0x0000       ; 🔑 Base
    db 0x00         ; 🔑 Base
    db 10010010b    ; 🔑 Access: P=1, DPL=00, S=1, Type=0010 (read/write)
    db 00000000b    ; 🔑 Flags
    db 0x00         ; 🔑 Base

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1  ; 🔑 GDT 大小
    dd gdt_start                ; 🔑 GDT 位址

; ============================================================
; 64-bit Long Mode 程式碼
; ============================================================
[bits 64]               ; 🔑 64-bit 指令

lm_entry:
    ; === 設定 data segments ===
    mov ax, 0x10        ; 🔑 data segment selector
    mov ds, ax          ; 🔑 Data Segment
    mov es, ax          ; 🔑 Extra Segment
    mov fs, ax          ; 🔑 FS
    mov gs, ax          ; 🔑 GS
    mov ss, ax          ; 🔑 Stack Segment

    ; --- 在 Long Mode 下用 Serial Port 印字 ---
    ; 🔑 在 Long Mode 下一樣可以用 out 指令操作 I/O port
    ; 🔑 COM1 serial port 的 I/O port 基底位址是 0x3F8

    ; 初始化 serial port
    mov dx, 0x3F9       ; COM1 + 1: Interrupt Enable Register
    mov al, 0x00
    out dx, al
    mov dx, 0x3FB       ; COM1 + 3: Line Control Register
    mov al, 0x80        ; DLAB
    out dx, al
    mov dx, 0x3F8       ; COM1 + 0: Divisor low
    mov al, 0x03        ; 38400 baud
    out dx, al
    mov dx, 0x3F9       ; COM1 + 1: Divisor high
    mov al, 0x00
    out dx, al
    mov dx, 0x3FB       ; COM1 + 3: Line Control Register
    mov al, 0x03        ; 8N1
    out dx, al

    ; 印字串到 serial port
    mov rsi, lm_msg     ; 🔑 RSI = 字串位址（64-bit 暫存器！）
.lm_loop:
    lodsb               ; 🔑 AL = [RSI], RSI++
    test al, al         ; 🔑 檢查 null terminator
    jz .lm_done         ; 🔑 結束

    ; 等待 transmit ready
    push rax            ; 🔑 保存字元
    mov dx, 0x3FD       ; COM1 + 5: Line Status Register
.wait_tx:
    in al, dx
    test al, 0x20       ; 🔑 bit 5 = Transmit Holding Register Empty
    jz .wait_tx

    ; 送出字元
    pop rax             ; 🔑 取回字元
    mov dx, 0x3F8       ; COM1
    out dx, al          ; 🔑 送出到 serial port
    jmp .lm_loop        ; 🔑 繼續

.lm_done:
    cli                 ; 🔑 關中斷
.lm_halt:
    hlt                 ; 🔑 停止 CPU
    jmp .lm_halt        ; 🔑 無限迴圈

lm_msg: db 13, 10, "=== Agent OS Example 03: Long Mode (64-bit) ===", 13, 10
        db "Hello from 64-bit Long Mode! Welcome to the future!", 13, 10
        db "We set up 4-level page tables and entered 64-bit mode!", 13, 10, 0

; === 填充與 Boot Signature ===
times 510-($-$$) db 0   ; 🔑 填滿到 510 bytes
dw 0xAA55               ; 🔑 Boot signature
