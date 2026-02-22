/* === 04: C Kernel Bootstrap ===
 * 🔑 這個 boot loader 的工作：設定 32-bit 環境，然後跳到 C 的 kernel_main()
 * 🔑 使用 Multiboot header 讓 GRUB 也能載入（但我們用自己的 linker script）
 */

.globl _start
.extern kernel_main

/* === Multiboot Header === */
/* 🔑 Multiboot 是 bootloader 的標準介面 */
/* 🔑 GRUB 會搜尋這個 magic number 來辨識 kernel */
.equ MULTIBOOT_MAGIC, 0x1BADB002           /* 🔑 Multiboot magic number */
.equ MULTIBOOT_FLAGS, 0x00000003           /* 🔑 Flag: 對齊 module + 提供 memory info */
.equ MULTIBOOT_CHECKSUM, -(MULTIBOOT_MAGIC + MULTIBOOT_FLAGS) /* 🔑 checksum 使三者相加 = 0 */

.section .multiboot, "a"         /* 🔑 放在特殊的 section，linker 會把它放在最前面 */
    .align 4                     /* 🔑 必須 4-byte 對齊 */
    .long MULTIBOOT_MAGIC        /* 🔑 Magic number */
    .long MULTIBOOT_FLAGS        /* 🔑 Flags */
    .long MULTIBOOT_CHECKSUM     /* 🔑 Checksum */

/* === 程式進入點 === */
.section .text                   /* 🔑 程式碼段 */

_start:
    /* === 設定 Stack === */
    movl $stack_top, %esp        /* 🔑 ESP 指向 stack 頂端（stack 向下生長） */
                                 /* 🔑 C 語言需要 stack 才能呼叫函數 */

    /* === 呼叫 C Kernel === */
    call kernel_main             /* 🔑 跳到 C 的 kernel_main()！ */
                                 /* 🔑 這就像 Linux 的 head.S 呼叫 start_kernel() */

    /* === kernel_main 返回後，停止 CPU === */
    cli                          /* 🔑 關閉中斷 */
1:  /* .halt */
    hlt                          /* 🔑 停止 CPU */
    jmp 1b                       /* 🔑 無限迴圈 */

/* === Stack 空間 === */
.section .bss                    /* 🔑 BSS = 未初始化的資料（不佔檔案空間） */
    .align 16                    /* 🔑 Stack 要 16-byte 對齊（ABI 要求） */
stack_bottom:
    .space 16384                 /* 🔑 保留 16KB 的 stack 空間 */
stack_top:                       /* 🔑 Stack 頂端（ESP 從這裡開始向下生長） */
