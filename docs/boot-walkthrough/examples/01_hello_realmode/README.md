# 01: Hello Real Mode

## 🎯 這個範例教你什麼？

CPU 開機後的第一個程式——512 bytes 的 boot sector。
這是所有作業系統的起點：BIOS 從磁碟讀取第一個磁區，載入到記憶體 0x7C00，然後跳過去執行。

## 📋 前置知識

- x86 CPU 開機從 **Real Mode (16-bit)** 開始
- BIOS 把第一個磁碟的前 **512 bytes** 載入到記憶體位址 `0x7C00`
- 最後兩個 byte 必須是 `0x55AA`（Boot Signature）
- Real Mode 可以使用 **BIOS 中斷**（INT 10h 印字、INT 13h 讀磁碟等）

## 🔧 編譯 & 執行

```bash
chmod +x build.sh
./build.sh
```

按 `Ctrl+A` 然後 `X` 離開 QEMU。

## 🔍 你會看到什麼

```
Hello from Real Mode! This is your CPU speaking from 1978.
```

印在 QEMU 的終端上。

## 📖 逐行解析

| 行 | 說明 |
|----|------|
| `[bits 16]` | 告訴組譯器產生 16-bit 指令 |
| `[org 0x7C00]` | 設定程式起始位址為 0x7C00（BIOS 載入位置） |
| `xor ax, ax` | AX 清零，用來初始化 segment registers |
| `mov ds, ax` | Data Segment = 0，讓資料存取使用絕對位址 |
| `mov sp, 0x7C00` | Stack Pointer 設在 0x7C00，向下生長 |
| `lodsb` | 從 [DS:SI] 讀一個 byte 到 AL，SI 自動加 1 |
| `int 0x10` | 呼叫 BIOS 影片中斷，AH=0Eh 印一個字元 |
| `hlt` | 停止 CPU 執行 |
| `times 510-($-$$) db 0` | 用 0 填充到 510 bytes |
| `dw 0xAA55` | Boot Signature，BIOS 識別可開機磁碟的標誌 |

## 🤔 思考題

1. 為什麼 `org` 是 `0x7C00` 而不是 `0x0000`？
2. 如果把 `0xAA55` 拿掉會怎樣？
3. `SP` 為什麼設在 `0x7C00`？Stack 往哪個方向生長？
4. 為什麼要設 `DS = 0`？如果不設會怎樣？
5. `lodsb` 和 `mov al, [si]` + `inc si` 有什麼差別？
