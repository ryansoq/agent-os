/* === Linker Script for 04_c_kernel ===
 * 🔑 這個 linker script 告訴 linker 如何排列 kernel 的各個 section
 * 🔑 Kernel 載入位址從 1MB (0x100000) 開始 — 這是 Multiboot 的慣例
 */

ENTRY(_start)           /* 🔑 程式進入點是 boot.asm 的 _start */

SECTIONS {
    /* 🔑 從 1MB 開始放 kernel（低於 1MB 是 BIOS、VGA 等硬體區域） */
    . = 1M;

    /* 🔑 .multiboot section 必須在最前面，bootloader 才找得到 magic number */
    .multiboot BLOCK(4K) : ALIGN(4K) {
        *(.multiboot)
    }

    /* 🔑 .text = 程式碼 */
    .text BLOCK(4K) : ALIGN(4K) {
        *(.text)
    }

    /* 🔑 .rodata = 唯讀資料（字串常數等） */
    .rodata BLOCK(4K) : ALIGN(4K) {
        *(.rodata)
    }

    /* 🔑 .data = 已初始化的全域變數 */
    .data BLOCK(4K) : ALIGN(4K) {
        *(.data)
    }

    /* 🔑 .bss = 未初始化的全域變數（包含 stack 空間） */
    .bss BLOCK(4K) : ALIGN(4K) {
        *(COMMON)
        *(.bss)
    }
}
