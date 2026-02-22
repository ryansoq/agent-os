#!/bin/bash
# 🔧 01_hello_realmode 編譯 & 執行腳本
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔧 編譯 01_hello_realmode..."
nasm -f bin boot.asm -o boot.bin
echo "✅ boot.bin ($(wc -c < boot.bin) bytes)"

# 🔑 如果傳入 --build-only，只編譯不執行
if [[ "$1" == "--build-only" ]]; then
    echo "📦 僅編譯模式，跳過 QEMU"
    exit 0
fi

echo "🚀 啟動 QEMU...（按 Ctrl+A 然後 X 離開）"
qemu-system-x86_64 -drive format=raw,file=boot.bin -nographic -serial mon:stdio
