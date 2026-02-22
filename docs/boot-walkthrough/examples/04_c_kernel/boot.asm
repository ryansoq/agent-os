; === 04: C Kernel Bootstrap ===
; 🔑 這個 boot loader 的工作：設定 32-bit 環境，然後跳到 C 的 kernel_main()
; 🔑 使用 Multiboot header 讓 GRUB 也能載入（但我們用自己的 linker script）
;
[bits 32]                   ; 🔑 我們會用自己的 linker，直接從 32-bit 開始
[global _start]             ; 🔑 讓 linker 知道程式進入點
[extern kernel_main]        ; 🔑 C 語言的 kernel_main() 函數

; === Multiboot Header ===
; 🔑 Multiboot 是 bootloader 的標準介面
; 🔑 GRUB 會搜尋這個 magic number 來辨識 kernel
MULTIBOOT_MAGIC equ 0x1BADB002      ; 🔑 Multiboot magic number
MULTIBOOT_FLAGS equ 0x00000003      ; 🔑 Flag: 對齊 module + 提供 memory info
MULTIBOOT_CHECKSUM equ -(MULTIBOOT_MAGIC + MULTIBOOT_FLAGS) ; 🔑 checksum 使三者相加 = 0

section .multiboot                  ; 🔑 放在特殊的 section，linker 會把它放在最前面
    align 4                         ; 🔑 必須 4-byte 對齊
    dd MULTIBOOT_MAGIC              ; 🔑 Magic number
    dd MULTIBOOT_FLAGS              ; 🔑 Flags
    dd MULTIBOOT_CHECKSUM           ; 🔑 Checksum

; === 程式進入點 ===
section .text                       ; 🔑 程式碼段

_start:
    ; === 設定 Stack ===
    mov esp, stack_top              ; 🔑 ESP 指向 stack 頂端（stack 向下生長）
                                    ; 🔑 C 語言需要 stack 才能呼叫函數

    ; === 呼叫 C Kernel ===
    call kernel_main                ; 🔑 跳到 C 的 kernel_main()！
                                    ; 🔑 這就像 Linux 的 head.S 呼叫 start_kernel()

    ; === kernel_main 返回後，停止 CPU ===
    cli                             ; 🔑 關閉中斷
.halt:
    hlt                             ; 🔑 停止 CPU
    jmp .halt                       ; 🔑 無限迴圈

; === Stack 空間 ===
section .bss                        ; 🔑 BSS = 未初始化的資料（不佔檔案空間）
    align 16                        ; 🔑 Stack 要 16-byte 對齊（ABI 要求）
stack_bottom:
    resb 16384                      ; 🔑 保留 16KB 的 stack 空間
stack_top:                          ; 🔑 Stack 頂端（ESP 從這裡開始向下生長）
