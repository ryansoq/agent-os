#!/bin/bash
# Agent OS — QEMU 啟動腳本
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
IMAGES="$ROOT/images"

KERNEL="${AGENTOS_KERNEL:-$IMAGES/bzImage}"
ROOTFS="${AGENTOS_ROOTFS:-$IMAGES/rootfs.ext2}"
MEMORY="${AGENTOS_MEMORY:-256M}"

if [ ! -f "$KERNEL" ] || [ ! -f "$ROOTFS" ]; then
  echo "❌ Image 不存在！請先執行: make build"
  echo "   Kernel: $KERNEL"
  echo "   Rootfs: $ROOTFS"
  exit 1
fi

echo "🚀 啟動 Agent OS..."
echo "   Kernel: $KERNEL"
echo "   Rootfs: $ROOTFS"
echo "   Memory: $MEMORY"
echo ""

qemu-system-x86_64 \
  -kernel "$KERNEL" \
  -drive "file=$ROOTFS,format=raw,if=virtio" \
  -append "root=/dev/vda console=ttyS0 rw" \
  -nographic \
  -m "$MEMORY" \
  -smp 2 \
  -net nic,model=virtio \
  -net user \
  -no-reboot
