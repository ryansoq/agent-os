; === 01: Hello Real Mode ===
; 🔑 這是最小的可開機程式 — 只有 512 bytes
; 🔑 CPU 開機後從 0x7C00 開始執行，此時是 16-bit Real Mode
;
[bits 16]           ; 🔑 告訴 NASM：產生 16-bit 指令
[org 0x7C00]        ; 🔑 BIOS 會把 boot sector 載入到記憶體 0x7C00

start:
    ; === 設定 segment registers ===
    xor ax, ax      ; AX = 0
    mov ds, ax      ; 🔑 Data Segment = 0（這樣 [msg] 才能正確存取）
    mov es, ax      ; 🔑 Extra Segment = 0
    mov ss, ax      ; 🔑 Stack Segment = 0
    mov sp, 0x7C00  ; 🔑 Stack 從 0x7C00 向下生長（在我們的 code 下方）

    ; === 用 BIOS 中斷印字 ===
    mov si, msg     ; 🔑 SI 指向要印的字串
.loop:
    lodsb           ; 🔑 AL = [DS:SI]，然後 SI++（從字串讀一個字元）
    test al, al     ; 🔑 檢查是否到字串結尾 (null terminator, 0x00)
    jz .done        ; 🔑 如果是 0，跳到 .done 結束
    mov ah, 0x0E    ; 🔑 BIOS INT 10h, AH=0Eh = Teletype 輸出（印一個字元）
    mov bx, 0x0007  ; 🔑 BH=0 頁面, BL=7 淺灰色（預設色）
    int 0x10        ; 🔑 呼叫 BIOS 中斷！這就是 Real Mode 的「系統呼叫」
    jmp .loop       ; 🔑 繼續印下一個字元

.done:
    cli             ; 🔑 關閉中斷，防止 CPU 被喚醒
.halt:
    hlt             ; 🔑 停止 CPU，等待中斷（我們的工作完成了）
    jmp .halt       ; 🔑 以防萬一，hlt 後再次停止

; === 資料區 ===
msg: db "Hello from Real Mode! This is your CPU speaking from 1978.", 0x0D, 0x0A, 0
; 🔑 0x0D = 回車 (CR), 0x0A = 換行 (LF), 0 = 字串結尾

; === 填充與 Boot Signature ===
; 🔑 Boot sector 必須恰好 512 bytes，最後兩個 byte 是 magic number
times 510-($-$$) db 0   ; 🔑 用 0 填滿到第 510 byte
dw 0xAA55               ; 🔑 Boot signature！BIOS 看到這個才會認為這是可開機磁碟
