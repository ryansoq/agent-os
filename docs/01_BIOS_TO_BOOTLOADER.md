# 📚 01 — 電源到 Bootloader：開機的第一秒

> 按下電源按鈕後，CPU 做了什麼？

---

## ⚡ 電源開啟的瞬間

**比喻：** 想像你在一個完全黑暗的房間裡醒來。你不知道自己在哪、不知道現在幾點、甚至不知道自己是誰。你唯一知道的事情是：**伸手去摸床頭的那本說明書**。

CPU 開機就是這樣。

### 電源開啟後發生的事：

```
1. 電源供應器穩定 → 送出 "Power Good" 信號
2. CPU 被重置（Reset）
3. CPU 的所有暫存器被設為預設值
4. 最重要的：指令指標（IP）被設為 0xFFF0
5. 代碼段（CS）被設為 0xF000
6. 實體地址 = 0xF000 × 16 + 0xFFF0 = 0xFFFF0
```

**0xFFFF0** 是什麼？那是 BIOS ROM 的位置，離 1MB 邊界只差 16 bytes。

為什麼是這個地址？因為 Intel 在 1978 年設計 8086 時就決定了，而所有後來的 CPU 都要**向下相容**。這個地址一直沿用到今天的最新處理器。

---

## 🔍 BIOS POST（Power-On Self-Test）

CPU 開始執行 BIOS 的程式碼後，第一件事是 **POST**（開機自檢）：

```
POST 檢查清單：
✅ CPU 正常嗎？
✅ 記憶體能讀寫嗎？（寫入 → 讀回 → 比對）
✅ 鍵盤控制器在嗎？
✅ 顯示卡能用嗎？
✅ 硬碟/USB 有接嗎？
```

**比喻：** 就像你早上起床先檢查——眼睛能看嗎？手能動嗎？腳能站嗎？確認身體各部分都正常才開始一天的活動。

如果 POST 失敗，你會聽到**嗶嗶聲**（beep code）。不同的嗶聲模式代表不同的錯誤——這是 BIOS 在記憶體和顯示卡都不能用的情況下，唯一能告訴你「哪裡壞了」的方式。

---

## 💾 MBR — 512 Bytes 的奇蹟

POST 完成後，BIOS 要找到作業系統。它會按照設定的開機順序（硬碟 → USB → 網路）依序嘗試。

找到開機裝置後，BIOS 讀取第一個磁區（sector）——剛好 **512 bytes**——到記憶體的 **0x7C00**，然後跳過去執行。

```
512 bytes 的 MBR（Master Boot Record）結構：

偏移量    大小      內容
───────────────────────────────
0x000     446 bytes   開機程式碼（Bootloader 第一階段）
0x1BE     64 bytes    分割表（4 個分割區，每個 16 bytes）
0x1FE     2 bytes     Magic Number: 0x55AA
───────────────────────────────
                      總計 512 bytes
```

### 為什麼是 512 bytes？

因為傳統硬碟的最小讀取單位就是一個磁區（sector） = 512 bytes。BIOS 只負責把這 512 bytes 載入記憶體，剩下的事情就交給 Bootloader 自己搞定。

### 0x55AA 是什麼？

這是 MBR 的「簽章」。BIOS 讀完 512 bytes 後，會檢查最後兩個 byte 是不是 `0x55AA`。如果不是，BIOS 就會認為這個磁碟沒有有效的開機紀錄，跳到下一個裝置繼續找。

```
記憶體位置：

0x00000 ┌──────────────────┐
        │  Interrupt Vector │
        │  Table (IVT)      │  ← BIOS 的中斷向量表
0x00400 ├──────────────────┤
        │  BIOS Data Area   │
0x00500 ├──────────────────┤
        │     可用空間       │
0x07C00 ├──────────────────┤
        │  MBR (512 bytes)  │  ← BIOS 把 MBR 載入到這裡
0x07E00 ├──────────────────┤
        │     可用空間       │
0x9FFFF ├──────────────────┤
        │  Extended BIOS    │
0xA0000 ├──────────────────┤
        │  Video Memory     │
0xC0000 ├──────────────────┤
        │  BIOS ROM         │
0xFFFFF └──────────────────┘  ← 1MB 邊界
```

---

## 🔧 GRUB vs QEMU 直接載入

### 傳統方式：GRUB

在真實電腦上，Bootloader 通常是 **GRUB**（GRand Unified Bootloader）：

```
BIOS → MBR (GRUB Stage 1, 512 bytes)
         → GRUB Stage 1.5（檔案系統驅動）
         → GRUB Stage 2（選單、載入 kernel）
         → bzImage（Linux kernel）
```

GRUB 的工作：
1. 顯示開機選單
2. 從檔案系統中找到 Linux kernel（bzImage）
3. 把 bzImage 載入記憶體的正確位置
4. 設定好 boot parameters
5. 跳到 kernel 的進入點

### QEMU 的快捷方式：`-kernel`

```bash
qemu-system-x86_64 -kernel bzImage -initrd rootfs.cpio.gz
```

當你用 QEMU 的 `-kernel` 參數時，**QEMU 直接扮演 Bootloader 的角色**：

```
QEMU 做的事（取代 BIOS + GRUB）：
1. 解析 bzImage 的 header
2. 把 kernel 載入記憶體的正確位置
3. 設定好 boot_params 結構
4. 直接跳到 kernel 的 32-bit 進入點
```

### 為什麼 QEMU `-kernel` 可以跳過 Bootloader？

**比喻：** 正常開機就像搭公車（BIOS → Bootloader → Kernel），QEMU `-kernel` 就像直接叫計程車送到目的地。目的地一樣，只是省略了中間的轉車過程。

技術原因：
- bzImage 的 header（`arch/x86/boot/header.S`）包含了所有 Bootloader 需要的資訊
- QEMU 直接讀這個 header，知道要把 kernel 放在記憶體的哪個位置
- QEMU 自己填好 `boot_params` 結構（通常 GRUB 負責填）
- 然後直接跳到 kernel 的進入點

這就是為什麼我們開發 Agent OS 時不需要安裝 GRUB——QEMU 幫我們搞定了。

---

## 🔑 關鍵概念回顧

| 概念 | 說明 |
|------|------|
| 0xFFFF0 | CPU 重置後執行的第一個地址（BIOS ROM） |
| POST | 開機自檢，確認硬體正常 |
| MBR | 第一個磁區，512 bytes，包含 Bootloader 第一階段 |
| 0x7C00 | BIOS 把 MBR 載入記憶體的位置 |
| 0x55AA | MBR 的魔術數字，表示「這是有效的開機磁區」 |
| GRUB | 最常用的 Linux Bootloader |
| QEMU -kernel | 跳過 BIOS+GRUB，直接載入 kernel |

---

## ⏭️ 下一步

MBR 被載入、GRUB 把 kernel 送到記憶體後，CPU 開始執行 Linux kernel 的第一行程式碼。

但此時 CPU 還在 **16-bit Real Mode**——一個 1978 年的古老模式。

為什麼？→ [02_REAL_MODE.md](02_REAL_MODE.md)
