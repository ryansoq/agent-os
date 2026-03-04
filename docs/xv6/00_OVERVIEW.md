# 📚 00 — 為什麼學 xv6？

> 「Linux 是一座城市，xv6 是一間教室模型。同一套建築原理，但你可以一磚一瓦看清楚。」

---

## 🤔 xv6 是什麼？

xv6 是 MIT 為作業系統課程（6.828）打造的教學 OS，靈感來自 Unix V6（1975）。

```
xv6 規模：≈ 6,000 行 C + 500 行 asm = 6,500 行
Linux：    > 30,000,000 行（xv6 的 0.02%）
```

麻雀雖小，五臟俱全：

| 概念 | xv6 | 對應檔案 |
|------|-----|----------|
| Bootloader | ✅ | `bootasm.S`, `bootmain.c` |
| 虛擬記憶體 | ✅ | `vm.c`, `entry.S` |
| 行程管理 | ✅ | `proc.c` |
| Context Switch | ✅ | `swtch.S` |
| 系統呼叫 | ✅ | `syscall.c`, `trapasm.S` |
| 檔案系統 | ✅ | `fs.c`, `file.c` |
| Shell | ✅ | `sh.c` |
| 多核支援 | ✅ | `mp.c`, `lapic.c` |

---

## 🔗 跟 AgentOS 教學的關係

```
AgentOS 你學了：                  xv6 帶你看：
✅ Real Mode → Protected Mode    bootasm.S（同一套！）
✅ GDT                           完整 GDT（user + kernel）
✅ 分頁基礎                       二級頁表、完整虛擬記憶體
✅ QEMU 除錯                      繼續用 QEMU！
                                  + 行程、syscall、FS、Shell、多核
```

**AgentOS 教你打地基，xv6 教你蓋完整棟房子。**

---

## 🗺️ x86 架構速覽

```
通用暫存器（32-bit）：EAX, EBX, ECX, EDX, ESI, EDI, EBP, ESP
段暫存器（16-bit）：  CS, DS, ES, FS, GS, SS
控制暫存器：          CR0(PE,PG), CR2(頁錯誤), CR3(頁目錄), CR4(PSE)
```

---

## 📍 學習路線

```
00 總覽 → 01 開機 → 02 entry.S → 03 main()
  → 04 記憶體 → 05 中斷 → 06 行程
  → 07 syscall → 08 鎖 → 09 FS → 10 Shell 🎉
```

---

## 🛠️ 環境設置

```bash
sudo apt install gcc make qemu-system-i386 git
git clone https://github.com/mit-pdos/xv6-public.git ~/xv6-public
cd ~/xv6-public
make
make qemu-nox CPUS=1   # 看到 $ 就成功了！Ctrl-A X 退出
```

---

## 📂 xv6 原始碼結構

```
bootasm.S    ← 🔵 Bootloader（ch01）     trap.c     ← 🔴 中斷（ch05）
bootmain.c   ← 🔵 Bootloader（ch01）     proc.c     ← 🟣 行程（ch06）
entry.S      ← 🟢 進入點（ch02）          swtch.S    ← 🟣 Context switch（ch06）
main.c       ← 🟢 初始化（ch03）          syscall.c  ← 🟤 系統呼叫（ch07）
vm.c         ← 🟡 虛擬記憶體（ch04）       fs.c       ← 🟠 檔案系統（ch09）
kalloc.c     ← 🟡 記憶體配置（ch04）       sh.c       ← 🔵 Shell（ch10）
```

➡️ [01 開機：BIOS → bootloader → kernel](01_BOOT.md)
