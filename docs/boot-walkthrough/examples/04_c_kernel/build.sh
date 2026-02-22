#!/bin/bash
# 🔧 04_c_kernel 編譯 & 執行腳本
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "📝 使用 GNU 工具鏈（跟 Linux kernel / xv6 一致）"
echo "   as  = GNU Assembler（AT&T 語法）"
echo "   ld  = GNU Linker"
echo "   gcc = GNU C Compiler"

echo "🔧 編譯 04_c_kernel..."

# 🔑 Step 1: 組譯 boot.S → boot.o (ELF32 格式)
echo "  [AS] boot.S → boot.o"
as --32 boot.S -o boot.o

# 🔑 Step 2: 編譯 kernel.c → kernel.o
# -m32: 產生 32-bit 程式碼
# -ffreestanding: 不依賴標準函式庫（沒有 libc）
# -fno-pie -fno-stack-protector: 關閉不需要的安全機制
# -nostdlib: 不連結標準函式庫
echo "  [GCC] kernel.c → kernel.o"
gcc -m32 -ffreestanding -fno-pie -fno-stack-protector -c kernel.c -o kernel.o

# 🔑 Step 3: 連結 boot.o + kernel.o → kernel.bin
# -m elf_i386: 32-bit ELF 格式
# -T linker.ld: 使用我們的 linker script
echo "  [LD] boot.o + kernel.o → kernel.bin"
ld -m elf_i386 -T linker.ld -o kernel.bin boot.o kernel.o

echo "✅ kernel.bin ($(wc -c < kernel.bin) bytes)"

if [[ "$1" == "--build-only" ]]; then
    echo "📦 僅編譯模式，跳過 QEMU"
    exit 0
fi

echo "🚀 啟動 QEMU...（按 Ctrl+A 然後 X 離開）"
# 🔑 -kernel: 直接載入 ELF kernel（QEMU 內建 Multiboot bootloader）
qemu-system-i386 -kernel kernel.bin -nographic -serial mon:stdio
