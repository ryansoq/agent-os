#!/bin/bash
# Agent OS Builder — 一鍵編譯
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
BR_DIR="$ROOT/buildroot"
IMAGES_DIR="$ROOT/images"
OVERLAY_DIR="$ROOT/overlay"

echo "🔧 Agent OS Builder"
echo "===================="

# 檢查 Buildroot
if [ ! -d "$BR_DIR" ]; then
  echo "[*] Cloning Buildroot..."
  git clone --depth 1 https://github.com/buildroot/buildroot.git "$BR_DIR"
fi

# 複製 overlay
echo "[*] 設定 overlay..."
mkdir -p "$BR_DIR/overlay"
cp -r "$OVERLAY_DIR"/* "$BR_DIR/overlay/"

# 載入 defconfig
echo "[*] 載入 agentos_defconfig..."
cd "$BR_DIR"
make agentos_defconfig 2>/dev/null || {
  echo "[!] agentos_defconfig 不存在，使用預設 .config"
}

# 編譯
JOBS="${1:-$(nproc)}"
echo "[*] 開始編譯 (make -j$JOBS)..."
echo "[*] 這可能需要 30-60 分鐘..."
make -j"$JOBS"

# 複製產出
echo "[*] 複製 images..."
mkdir -p "$IMAGES_DIR"
cp -v "$BR_DIR/output/images/bzImage" "$IMAGES_DIR/" 2>/dev/null || true
cp -v "$BR_DIR/output/images/rootfs.ext2" "$IMAGES_DIR/" 2>/dev/null || true
cp -v "$BR_DIR/output/images/rootfs.cpio.gz" "$IMAGES_DIR/" 2>/dev/null || true

echo ""
echo "✅ Agent OS 編譯完成！"
echo ""
echo "  images/bzImage       — Kernel"
echo "  images/rootfs.ext2   — Disk image"
echo "  images/rootfs.cpio.gz — RAM image"
echo ""
echo "啟動方式："
echo "  make run       — QEMU 開機"
echo "  make web       — Web UI"
