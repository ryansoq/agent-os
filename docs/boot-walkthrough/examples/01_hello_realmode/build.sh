#!/bin/bash
# 🔧 01_hello_realmode 編譯 & 執行腳本
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "📝 使用 GNU 工具鏈（跟 Linux kernel / xv6 一致）"
echo "   as  = GNU Assembler（AT&T 語法）"
echo "   ld  = GNU Linker"

echo "🔧 編譯 01_hello_realmode..."
as --32 boot.S -o boot.o
ld -m elf_i386 -Ttext=0x7C00 --oformat binary -o boot.bin boot.o
echo "✅ boot.bin ($(wc -c < boot.bin) bytes)"

# 🔑 如果傳入 --build-only，只編譯不執行
if [[ "$1" == "--build-only" ]]; then
    echo "📦 僅編譯模式，跳過 QEMU"
    exit 0
fi

echo "🚀 啟動 QEMU...（按 Ctrl+A 然後 X 離開）"
qemu-system-x86_64 -drive format=raw,file=boot.bin -nographic -serial mon:stdio
