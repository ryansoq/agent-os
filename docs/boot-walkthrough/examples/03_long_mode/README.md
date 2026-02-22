# 03: Long Mode (64-bit)

## 🎯 這個範例教你什麼？

從 Real Mode 一路切換到 64-bit Long Mode——現代作業系統的最終執行模式。
這裡你會學到 4 級頁表、PAE、EFER MSR 等關鍵概念。

## 📋 前置知識

- Protected Mode 是 32-bit，Long Mode 是 64-bit
- Long Mode **強制使用分頁**（Paging），不能只靠 Segmentation
- 需要建立 4 級頁表：PML4 → PDPT → PD → PT
- 可以用 2MB 大頁（PS=1）跳過最後一級 PT

## 🔧 編譯 & 執行

```bash
chmod +x build.sh
./build.sh
```

## 🔍 你會看到什麼

QEMU VGA 畫面上顯示黃色的：
```
Hello from 64-bit Long Mode! Welcome to the future!
```

## 📖 頁表結構圖

```
CR3 = 0x1000 (PML4)
  │
  └─ PML4[0] = 0x2003 ──→ PDPT @ 0x2000
                             │
                             └─ PDPT[0] = 0x3003 ──→ PD @ 0x3000
                                                       │
                                                       └─ PD[0] = 0x0083 ──→ 2MB page @ 0x0
                                                          (PS=1, 直接映射 0-2MB)
```

### Entry Flag 說明

| Bit | 名稱 | 值 | 說明 |
|-----|------|----|------|
| 0 | P (Present) | 1 | 此 entry 有效 |
| 1 | R/W | 1 | 可讀寫 |
| 7 | PS (Page Size) | 1 | 2MB 大頁（只在 PD level） |

## 🔑 切換步驟

1. 檢查 CPUID 是否支援 Long Mode
2. 建立 4 級頁表（identity map 前 2MB）
3. 開啟 PAE（CR4.PAE = 1）
4. 載入 PML4 到 CR3
5. 設定 EFER.LME = 1（啟用 Long Mode）
6. 開啟 Paging（CR0.PG = 1）+ PE
7. Far jump 到 64-bit code segment

## 🤔 思考題

1. 為什麼 Long Mode 強制使用分頁？
2. Identity Map 是什麼意思？為什麼開機時需要？
3. 2MB 大頁和 4KB 小頁各有什麼優缺點？
4. 為什麼 64-bit GDT 的 D 位元必須為 0？
5. EFER 是什麼？為什麼不是用 CR 暫存器控制 Long Mode？
