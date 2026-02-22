# 04: C Kernel

## 🎯 這個範例教你什麼？

從組合語言跳到 C 語言——這就是真正的 kernel 開發！
你會學到 Multiboot、linker script、freestanding C 等概念。

## 📋 前置知識

- 組合語言負責最初的硬體設定（stack、segment registers）
- C 語言負責 kernel 邏輯（因為用組合語言寫 OS 太痛苦了）
- 需要 linker script 控制記憶體佈局
- Freestanding C = 沒有 printf、沒有 malloc、沒有 libc

## 🔧 編譯 & 執行

```bash
chmod +x build.sh
./build.sh
```

需要安裝 `gcc` 和 32-bit 支援：
```bash
sudo apt-get install -y gcc gcc-multilib
```

## 🔍 你會看到什麼

Terminal 上會顯示（透過 serial port 輸出）：
```
=== Agent OS Example 04: C Kernel ===
Hello from C kernel! kernel_main() is running.
We jumped from assembly to C successfully!
VGA text mode: 80x25, direct memory at 0xB8000
No printf, no stdlib -- just raw hardware access.
System halted. Your kernel is alive!
```

如果用 QEMU 圖形模式，VGA 畫面也會同時顯示彩色版本。

## 📖 編譯流程

```
boot.asm ──[nasm]──→ boot.o ──┐
                               ├──[ld]──→ kernel.bin ──[qemu]──→ 🖥️
kernel.c ──[gcc]───→ kernel.o ─┘
                       ↑
                  linker.ld (控制記憶體佈局)
```

## 🤔 思考題

1. 為什麼 kernel 載入在 1MB (0x100000)？低於 1MB 有什麼？
2. 為什麼用 `-ffreestanding`？如果不用會怎樣？
3. `volatile` 在 VGA 指標上有什麼作用？拿掉會怎樣？
4. kernel_main() 為什麼不能 return？
5. 這個 kernel 和 Linux kernel 有什麼相似之處？
