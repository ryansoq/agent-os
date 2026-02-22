; === 02: Protected Mode ===
; 🔑 從 16-bit Real Mode 切換到 32-bit Protected Mode
; 🔑 需要：關中斷 → 開 A20 → 設 GDT → 設 CR0.PE → far jump
;
[bits 16]               ; 🔑 一開始還是 16-bit Real Mode
[org 0x7C00]            ; 🔑 BIOS 載入位址

start:
    ; === 初始化 segment registers ===
    xor ax, ax          ; 🔑 AX = 0
    mov ds, ax          ; 🔑 Data Segment = 0
    mov es, ax          ; 🔑 Extra Segment = 0
    mov ss, ax          ; 🔑 Stack Segment = 0
    mov sp, 0x7C00      ; 🔑 Stack 向下生長

    ; === 關閉中斷 ===
    cli                 ; 🔑 進入 Protected Mode 前必須關中斷
                        ;     因為 Real Mode 的中斷向量表在 PM 下無效

    ; === 開啟 A20 Gate ===
    ; 🔑 A20 是第 21 條位址線，預設被關閉（為了相容 8086）
    ; 🔑 不開 A20 的話，位址會 wrap around，只能存取 1MB
    in al, 0x92         ; 🔑 讀取 System Control Port A
    or al, 2            ; 🔑 設定 bit 1 = 啟用 A20
    out 0x92, al        ; 🔑 寫回，Fast A20 Gate 開啟

    ; === 載入 GDT ===
    lgdt [gdt_descriptor] ; 🔑 載入 GDT 描述符到 GDTR 暫存器

    ; === 設定 CR0.PE = 1，進入 Protected Mode ===
    mov eax, cr0        ; 🔑 讀取 Control Register 0
    or eax, 1           ; 🔑 設定 bit 0 = PE (Protection Enable)
    mov cr0, eax        ; 🔑 寫回！CPU 現在進入 Protected Mode

    ; === Far Jump 到 32-bit Code Segment ===
    ; 🔑 far jump 做兩件事：
    ;     1. 清空 CPU pipeline（因為模式切換了）
    ;     2. 載入新的 CS selector (0x08 = GDT 第 1 個 entry)
    jmp 0x08:pm_entry   ; 🔑 0x08 = GDT code segment 的 offset

; ============================================================
; GDT (Global Descriptor Table)
; 🔑 GDT 定義記憶體分段的存取權限和範圍
; 🔑 每個 entry 8 bytes，描述一個 segment
; ============================================================

gdt_start:

gdt_null:
    ; 🔑 GDT 第 0 個 entry 必須是 null descriptor（CPU 規定）
    dq 0x0000000000000000   ; 🔑 全部填 0

gdt_code:
    ; 🔑 Code Segment Descriptor (0x00CF9A000000FFFF)
    ;
    ;  完整 8 bytes 的 Bit Field 拆解：
    ;  ┌─────────┬──────┬───┬────┬───┬─────┬──────────┬──────────┐
    ;  │ Base    │ Flags│ L │ Sz │ 0 │ Lim │ Access   │ Base     │
    ;  │ 31:24  │ G  D │   │    │   │19:16│ P DPL S  │ 23:16   │
    ;  │ 0x00   │ 1  1 │ 0 │ 0  │ 0 │ 0xF │1 00  1   │ 0x00    │
    ;  └─────────┴──────┴───┴────┴───┴─────┴──────────┴──────────┘
    ;
    ;  G=1: Granularity，Limit 單位是 4KB（0xFFFFF × 4KB = 4GB）
    ;  D=1: Default operand size = 32-bit
    ;  L=0: 非 64-bit 模式（Long Mode 才用）
    ;  P=1: Present，段存在於記憶體中
    ;  DPL=00: Descriptor Privilege Level = Ring 0（最高權限）
    ;  S=1: 非系統段（Code 或 Data）
    ;  Type=1010: Execute/Read（可執行、可讀取）
    ;
    dw 0xFFFF       ; 🔑 Limit 15:0 = 0xFFFF（搭配 G=1，最大 4GB）
    dw 0x0000       ; 🔑 Base 15:0 = 0x0000（從位址 0 開始）
    db 0x00         ; 🔑 Base 23:16 = 0x00
    db 10011010b    ; 🔑 Access Byte: P=1, DPL=00, S=1, Type=1010 (exec/read)
    db 11001111b    ; 🔑 Flags: G=1, D=1, L=0, 0 + Limit 19:16 = 0xF
    db 0x00         ; 🔑 Base 31:24 = 0x00

gdt_data:
    ; 🔑 Data Segment Descriptor (0x00CF92000000FFFF)
    ;
    ;  與 Code Segment 幾乎相同，差別在 Type：
    ;  Type=0010: Read/Write（可讀、可寫）
    ;  D=1 在 Data Segment 稱為 B(Big)=1：使用 32-bit stack pointer (ESP)
    ;
    dw 0xFFFF       ; 🔑 Limit 15:0 = 0xFFFF
    dw 0x0000       ; 🔑 Base 15:0 = 0x0000
    db 0x00         ; 🔑 Base 23:16 = 0x00
    db 10010010b    ; 🔑 Access Byte: P=1, DPL=00, S=1, Type=0010 (read/write)
    db 11001111b    ; 🔑 Flags: G=1, B=1, L=0, 0 + Limit 19:16 = 0xF
    db 0x00         ; 🔑 Base 31:24 = 0x00

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1  ; 🔑 GDT 大小（byte 數 - 1）
    dd gdt_start                ; 🔑 GDT 的線性位址

; ============================================================
; 32-bit Protected Mode 程式碼
; ============================================================
[bits 32]               ; 🔑 從這裡開始是 32-bit 指令

pm_entry:
    ; === 設定 data segment registers ===
    mov ax, 0x10        ; 🔑 0x10 = GDT 第 2 個 entry（data segment）的 selector
    mov ds, ax          ; 🔑 Data Segment 指向 GDT data descriptor
    mov es, ax          ; 🔑 Extra Segment
    mov fs, ax          ; 🔑 FS Segment
    mov gs, ax          ; 🔑 GS Segment
    mov ss, ax          ; 🔑 Stack Segment
    mov esp, 0x90000    ; 🔑 Stack pointer 設在高位址（有足夠空間向下生長）

    ; === 直接寫 VGA 記憶體印彩色字 ===
    ; 🔑 在 Protected Mode 不能用 BIOS 中斷了！
    ; 🔑 VGA text mode buffer 在 0xB8000
    ; 🔑 每個字元佔 2 bytes：[字元][屬性]
    ; 🔑 屬性格式：[背景色 4bit][前景色 4bit]
    ;     0x0F = 黑底白字, 0x0A = 黑底綠字, 0x0C = 黑底紅字
    mov edi, 0xB8000    ; 🔑 EDI 指向 VGA buffer 起始位址
    mov esi, pm_msg     ; 🔑 ESI 指向要印的字串
    mov ah, 0x0A        ; 🔑 屬性 = 綠色字

.pm_loop:
    lodsb               ; 🔑 AL = [ESI], ESI++
    test al, al         ; 🔑 檢查 null terminator
    jz .pm_done         ; 🔑 結束
    mov [edi], ax       ; 🔑 寫入 [字元(AL)][屬性(AH)] 到 VGA buffer
    add edi, 2          ; 🔑 移到下一個字元位置（每個佔 2 bytes）
    jmp .pm_loop        ; 🔑 繼續印下一個字元

.pm_done:
    cli                 ; 🔑 關中斷
.pm_halt:
    hlt                 ; 🔑 停止 CPU
    jmp .pm_halt        ; 🔑 無限迴圈

pm_msg: db "Hello from 32-bit Protected Mode! GDT works!", 0

; === 填充與 Boot Signature ===
times 510-($-$$) db 0   ; 🔑 填滿到 510 bytes
dw 0xAA55               ; 🔑 Boot signature
