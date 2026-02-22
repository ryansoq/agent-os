# 02: Protected Mode

## 🎯 這個範例教你什麼？

從 16-bit Real Mode 切換到 32-bit Protected Mode。
這是現代作業系統開機的第二步——設定 GDT，開啟記憶體保護，進入 32-bit 世界。

## 📋 前置知識

- Real Mode 只能存取 1MB 記憶體，沒有記憶體保護
- Protected Mode 提供 4GB 定址、Ring 權限、記憶體分段保護
- 切換需要：關中斷 → 開 A20 → 設 GDT → CR0.PE=1 → far jump

## 🔧 編譯 & 執行

```bash
chmod +x build.sh
./build.sh
```

## 🔍 你會看到什麼

Terminal 上會顯示（透過 serial port 輸出）：
```
=== Agent OS Example 02: Protected Mode ===
Hello from 32-bit Protected Mode! GDT works!
We are using serial port (COM1) for output -- no VGA needed!
```

## 📖 關鍵概念

### GDT (Global Descriptor Table)
GDT 是一張表，每個 entry 8 bytes，定義一個記憶體段的：
- **Base**: 段的起始位址
- **Limit**: 段的大小
- **Access**: 存取權限（Ring level、可讀/可寫/可執行）

### A20 Gate
- 8086 只有 20 條位址線（A0-A19），最多 1MB
- 80286+ 有更多位址線，但為了相容，A20 預設關閉
- 必須手動開啟才能存取 1MB 以上的記憶體

### CR0.PE
- Control Register 0 的 bit 0 = Protection Enable
- 設為 1 就進入 Protected Mode

## 🤔 思考題

1. 為什麼 GDT 第一個 entry 必須是 null？
2. far jump `jmp 0x08:pm_entry` 的 0x08 是怎麼算出來的？
3. 為什麼 Protected Mode 不能用 BIOS 中斷？
4. 如果不開 A20 Gate 會怎樣？
5. Code Segment 和 Data Segment 的 Type 有什麼差別？
