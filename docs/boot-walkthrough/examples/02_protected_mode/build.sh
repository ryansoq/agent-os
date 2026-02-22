#!/bin/bash
# 🔧 02_protected_mode 編譯 & 執行腳本
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "📝 使用 GNU 工具鏈（跟 Linux kernel / xv6 一致）"
echo "   as  = GNU Assembler（AT&T 語法）"
echo "   ld  = GNU Linker"

echo "🔧 編譯 02_protected_mode..."
as --32 boot.S -o boot.o
ld -m elf_i386 -Ttext=0x7C00 --oformat binary -o boot.bin boot.o
echo "✅ boot.bin ($(wc -c < boot.bin) bytes)"

if [[ "$1" == "--build-only" ]]; then
    echo "📦 僅編譯模式，跳過 QEMU"
    exit 0
fi

echo "🚀 啟動 QEMU...（按 Ctrl+A 然後 X 離開）"
echo "💡 Protected Mode 用 serial port 輸出，直接在 terminal 看結果"
qemu-system-x86_64 -drive format=raw,file=boot.bin -nographic -serial mon:stdio
