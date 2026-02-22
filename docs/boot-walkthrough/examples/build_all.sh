#!/bin/bash
# 🔧 Agent OS Boot Examples — 一鍵編譯全部 + 選擇執行
echo "🔧 Agent OS Boot Examples — 一鍵編譯全部"
echo "========================================="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FAIL=0

for dir in 01_hello_realmode 02_protected_mode 03_long_mode 04_c_kernel; do
    echo ""
    echo "📦 Building $dir..."
    cd "$SCRIPT_DIR/$dir"
    if bash build.sh --build-only; then
        echo "  ✅ $dir 編譯成功"
    else
        echo "  ❌ $dir 編譯失敗！"
        FAIL=1
    fi
done

cd "$SCRIPT_DIR"

if [[ "$FAIL" == "1" ]]; then
    echo ""
    echo "⚠️  有些範例編譯失敗，請檢查錯誤訊息"
    exit 1
fi

echo ""
echo "✅ 全部編譯完成！"
echo ""
echo "選擇要執行的範例："
echo "  1) 01_hello_realmode  — Real Mode 印字"
echo "  2) 02_protected_mode  — GDT + Protected Mode"
echo "  3) 03_long_mode       — 頁表 + 64-bit"
echo "  4) 04_c_kernel        — ASM → C kernel"
echo "  q) 離開"
echo ""
read -p "請選擇 (1-4, q): " choice

case "$choice" in
    1) cd "$SCRIPT_DIR/01_hello_realmode" && bash build.sh ;;
    2) cd "$SCRIPT_DIR/02_protected_mode" && bash build.sh ;;
    3) cd "$SCRIPT_DIR/03_long_mode" && bash build.sh ;;
    4) cd "$SCRIPT_DIR/04_c_kernel" && bash build.sh ;;
    q) echo "👋 Bye!" ;;
    *) echo "❌ 無效選擇" ;;
esac
