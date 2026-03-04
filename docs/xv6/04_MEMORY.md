# 📚 04 — 虛擬記憶體與頁表

> 「每個程式以為自己獨佔 4GB 記憶體，其實都是 CPU 在後面偷偷翻電話簿。」

---

## 📖 比喻：頁表 = 電話簿

想像你住在一棟大樓，每個住戶有一本**私人電話簿**：

```
你的電話簿（頁表）：
┌──────────────┬──────────────┐
│ 虛擬號碼      │ 實際號碼      │
├──────────────┼──────────────┤
│ 0001（客廳）  │ 實體頁 #37   │
│ 0002（臥室）  │ 實體頁 #142  │
│ 0003（廚房）  │ 實體頁 #8    │
│ 0004          │ ❌ 不存在     │  ← PTE_P = 0
│ 0005（機房）  │ 實體頁 #200  │  ← PTE_U = 0（住戶不能進！）
└──────────────┴──────────────┘
```

- **虛擬號碼**（虛擬地址）：程式看到的地址
- **實際號碼**（物理地址）：RAM 裡真正的位置
- **電話簿**（頁表）：CPU 每次存取記憶體都要查的對照表
- **PTE_P**：這個號碼存不存在？
- **PTE_U**：住戶（user）能不能打這個號碼？

每個行程有自己的電話簿 → **同一個虛擬地址，不同行程對應到不同物理頁面** → 互相隔離！

---

## 🏗️ x86 二級頁表：10-10-12

一個 32-bit 虛擬地址（4GB 空間），拆成三段：

```
虛擬地址（32 bits）：
┌────── 10 ──────┬────── 10 ──────┬──────── 12 ────────┐
│ Page Directory │  Page Table    │   Offset（頁內偏移） │
│   Index (PDX)  │  Index (PTX)  │                      │
└────────────────┴────────────────┴──────────────────────┘
     ↓                  ↓                   ↓
  查 PD 第幾項      查 PT 第幾項        頁內第幾個 byte

PDX: 10 bits → 1024 個 entry → Page Directory 有 1024 項
PTX: 10 bits → 1024 個 entry → 每個 Page Table 有 1024 項
Offset: 12 bits → 4096 bytes = 4KB → 每頁 4KB

總共：1024 × 1024 × 4096 = 4GB ✅
```

### 為什麼用二級？

如果用一級（flat page table）：
- 4GB ÷ 4KB = 1M 個 entry × 4 bytes = **4MB** 的頁表！
- 每個行程都要 4MB → 64 個行程 = 256MB 光頁表就吃掉了

二級頁表的好處：
- Page Directory 固定 4KB（1024 × 4 bytes）
- Page Table **只在需要時才分配**
- 大部分虛擬地址沒用到 → 對應的 Page Table 不用建 → 省記憶體！

### 翻譯過程（MMU 硬體自動做）

```
CR3 暫存器 → 指向 Page Directory 的物理位址

虛擬地址 0x80100000 要翻譯成物理地址：

Step 1: 拆解虛擬地址
  0x80100000 = 1000_0000_0001_0000_0000_0000_0000_0000
  PDX = 1000000000 = 512     ← 高 10 bits
  PTX = 0100000000 = 256     ← 中 10 bits  
  Offset = 000000000000 = 0  ← 低 12 bits

Step 2: 查 Page Directory
  PDE = PageDirectory[512]
  → 取出 Page Table 的物理地址

Step 3: 查 Page Table
  PTE = PageTable[256]
  → 取出物理頁面的地址 + flags

Step 4: 組合
  物理地址 = PTE 的物理頁面地址 + Offset
  
                    CR3
                     │
                     ↓
              Page Directory（4KB）
              ┌──────────────┐
          0   │              │
              │   ...        │
        512   │ PDE ─────────│──→ Page Table（4KB）
              │   ...        │    ┌──────────────┐
       1023   │              │    │   ...        │
              └──────────────┘  256│ PTE ─────────│──→ Physical Page
                                  │   ...        │    ┌──────────┐
                                  └──────────────┘    │ 你要的    │
                                                      │ 資料在這！│
                                                      └──────────┘
```

---

## 📄 PTE 的旗標（flags）

每個 Page Table Entry 是 32 bits：

```
PTE（32 bits）：
┌──────────── 20 ────────────┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┬──┐
│  Physical Page Address     │  │  │  │  │PS│ D│ A│CD│WT│ U│ W│ P│
│  （物理頁面地址，4KB 對齊）  │  │  │  │  │  │  │  │  │  │  │  │  │
└────────────────────────────┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┴──┘
                              11  10  9   8  7  6  5  4  3  2  1  0
```

xv6 用到的三個重要 flags：

| Flag | 值 | 名稱 | 含義 |
|------|----|------|------|
| **PTE_P** | 0x001 | Present | 這個頁面存在嗎？0 = 不存在，存取會 Page Fault |
| **PTE_W** | 0x002 | Writeable | 可以寫入嗎？0 = 唯讀，寫入會 Page Fault |
| **PTE_U** | 0x004 | User | **User mode 能存取嗎？** 0 = 只有 kernel 能碰 |

### PTE_U 的重要性

```
Kernel 記憶體（KERNBASE 以上）：PTE_U = 0
  → User 程式碰不到 kernel 的資料
  → 即使 user 知道虛擬地址，存取也會 Page Fault

User 記憶體（KERNBASE 以下）：PTE_U = 1
  → User 程式可以正常讀寫自己的記憶體

這就是為什麼 user 程式不能搞壞 kernel！
不是因為 kernel 藏起來了，而是頁表上明確寫著「你不能進」。
```

---

## 📄 `entrypgdir`：為什麼需要 identity mapping？

在 `entry.S` 開啟分頁的那一刻，CPU 的世界觀徹底改變：

```
開啟分頁前：CPU 用物理地址取指令
  EIP = 0x0010000C（物理地址）→ 直接去 RAM 取

開啟分頁後：CPU 用虛擬地址取指令
  EIP 還是 0x0010000C → 但現在要查頁表翻譯！
  如果頁表裡沒有 0x0010000C 的映射 → 💥 Page Fault → 死機
```

所以 `entrypgdir` 需要做兩件事：

```c
// main.c 裡的 entrypgdir
__attribute__((__aligned__(PGSIZE)))
pde_t entrypgdir[NPDENTRIES] = {
  // 映射 1：虛擬 [0, 4MB) → 物理 [0, 4MB)（identity mapping）
  // 為什麼？因為開啟分頁那一刻，EIP 還在低位址（~0x00100000）
  // 沒有這個映射，下一條指令就炸了
  [0] = (0) | PTE_P | PTE_W | PTE_PS,

  // 映射 2：虛擬 [KERNBASE, KERNBASE+4MB) → 物理 [0, 4MB)
  // 為什麼？因為 kernel 的程式碼被 linker 安排在 0x80100000+
  // main() 等函數的地址都是 0x8010xxxx
  // 要跳到 main() 就需要這個映射
  [KERNBASE>>PDXSHIFT] = (0) | PTE_P | PTE_W | PTE_PS,
};
```

```
entrypgdir 的映射（用 4MB 大頁，PTE_PS=1）：

虛擬地址空間：
┌─────────────────┐ 0xFFFFFFFF
│                 │
│  （未映射）     │
│                 │
├─────────────────┤ 0x80400000
│ kernel 映射     │ → 物理 [0, 4MB)     ← 映射 2
├─────────────────┤ 0x80000000 = KERNBASE
│                 │
│  （未映射）     │
│                 │
├─────────────────┤ 0x00400000
│ identity 映射   │ → 物理 [0, 4MB)     ← 映射 1
├─────────────────┤ 0x00000000

entry.S 的執行過程：
  1. EIP 在 ~0x00100000（低位址）
  2. 開啟分頁 → identity mapping 讓低位址繼續能用
  3. jmp *%eax 跳到 main()（地址 0x8010xxxx）
  4. 用映射 2 繼續執行
  5. 之後 kvmalloc() 建立完整頁表，identity mapping 就不需要了
```

---

## 📄 `setupkvm()` / `kvmalloc()`：完整的 kernel 頁表

`entrypgdir` 只映射了 4MB，不夠用。`kvmalloc()` 建立完整的 kernel 頁表：

```c
// vm.c

// kernel 的記憶體映射表
static struct kmap {
  void *virt;        // 虛擬地址起點
  uint phys_start;   // 物理地址起點
  uint phys_end;     // 物理地址終點
  int perm;          // 權限旗標
} kmap[] = {
  // 虛擬地址                物理起點        物理終點      權限
  { (void*)KERNBASE,         0,              EXTMEM,       PTE_W },
  // KERNBASE ~ KERNBASE+1MB → 物理 0 ~ 1MB
  // I/O 空間（VGA、BIOS）
  // 可寫（要寫 VGA buffer）

  { (void*)KERNLINK,         V2P(KERNLINK),  V2P(data),    0 },
  // KERNLINK(0x80100000) ~ data → kernel 的 text + rodata
  // 唯讀！（不可寫）→ 保護 kernel 程式碼不被意外覆寫
  // 注意：沒有 PTE_W

  { (void*)data,             V2P(data),      PHYSTOP,      PTE_W },
  // data ~ KERNBASE+PHYSTOP → kernel 的 data + 所有可用物理記憶體
  // 可讀寫

  { (void*)DEVSPACE,         DEVSPACE,       0,            PTE_W },
  // 0xFE000000+ → 裝置映射空間（LAPIC、IOAPIC）
  // 直接映射（虛擬 = 物理）
};

// 建立 kernel 頁表
pde_t*
setupkvm(void)
{
  pde_t *pgdir;
  struct kmap *k;

  // 分配一頁當 Page Directory
  if((pgdir = (pde_t*)kalloc()) == 0)
    return 0;
  memset(pgdir, 0, PGSIZE);  // 清零，所有 PTE_P = 0

  if (P2V(PHYSTOP) > (void*)DEVSPACE)
    panic("PHYSTOP too high");

  // 對 kmap 裡的每個區段，建立頁表映射
  for(k = kmap; k < &kmap[NELEM(kmap)]; k++)
    if(mappages(pgdir, k->virt, k->phys_end - k->phys_start,
                (uint)k->phys_start, k->perm) < 0) {
      freevm(pgdir);
      return 0;
    }
  return pgdir;
}

// 建立 kernel 頁表並切換過去
void
kvmalloc(void)
{
  kpgdir = setupkvm();  // 建立完整頁表
  switchkvm();           // 把 CR3 指向新頁表
}

void
switchkvm(void)
{
  lcr3(V2P(kpgdir));    // CR3 = 新頁表的物理地址
  // 從此 entrypgdir 的 identity mapping 消失
  // 但沒關係，我們已經在高位址（0x8010xxxx）執行了
}
```

```
setupkvm() 建立的記憶體映射全景圖：

虛擬地址空間（每個行程都有這些 kernel 映射）：
┌──────────────────┐ 0xFFFFFFFF
│ DEVSPACE         │ → 物理 0xFE000000+（裝置）
├──────────────────┤ 0xFE000000
│                  │
│ kernel data +    │ → 物理 V2P(data) ~ PHYSTOP
│ 可用記憶體       │   PTE_W（可寫）
│                  │   ⚠️ 沒有 PTE_U → user 碰不到！
├──────────────────┤ data
│ kernel text      │ → 物理 V2P(KERNLINK) ~ V2P(data)
│ (唯讀！)         │   沒有 PTE_W → 連 kernel 自己也不能寫！
├──────────────────┤ 0x80100000 = KERNLINK
│ I/O 空間         │ → 物理 0 ~ 0x100000
├──────────────────┤ 0x80000000 = KERNBASE
│                  │
│ User 空間        │ → 每個行程不同的物理頁面
│ （之後才映射）    │   PTE_U = 1 → user 可以存取
│                  │
├──────────────────┤ 0x00000000
```

---

## 📄 `walkpgdir()` 與 `mappages()`：建立映射

### walkpgdir()：找到虛擬地址對應的 PTE

```c
// 給一個虛擬地址 va，找到它在頁表裡的 PTE
// 如果 Page Table 不存在且 alloc=1，就分配一個
static pte_t *
walkpgdir(pde_t *pgdir, const void *va, int alloc)
{
  pde_t *pde;
  pte_t *pgtab;

  // Step 1: 用 PDX(va) 找到 Page Directory Entry
  pde = &pgdir[PDX(va)];

  if(*pde & PTE_P){
    // PDE 存在 → Page Table 已經分配了
    // PTE_ADDR 取出物理地址，P2V 轉成虛擬地址（因為我們在 kernel）
    pgtab = (pte_t*)P2V(PTE_ADDR(*pde));
  } else {
    // PDE 不存在 → 需要分配新的 Page Table
    if(!alloc || (pgtab = (pte_t*)kalloc()) == 0)
      return 0;
    memset(pgtab, 0, PGSIZE);  // 清零，全部 PTE_P = 0
    // 設定 PDE：指向新的 Page Table，標記 Present + Writable + User
    *pde = V2P(pgtab) | PTE_P | PTE_W | PTE_U;
    // ⚠️ PDE 的 PTE_U 設得很寬鬆（所有人能存取）
    // 真正的權限控制在 PTE 層級
  }

  // Step 2: 用 PTX(va) 找到 Page Table Entry
  return &pgtab[PTX(va)];
}
```

### mappages()：建立虛擬→物理的映射

```c
// 把虛擬地址 [va, va+size) 映射到物理地址 [pa, pa+size)
static int
mappages(pde_t *pgdir, void *va, uint size, uint pa, int perm)
{
  char *a, *last;
  pte_t *pte;

  a = (char*)PGROUNDDOWN((uint)va);        // 對齊到頁邊界（往下）
  last = (char*)PGROUNDDOWN(((uint)va) + size - 1);  // 最後一頁

  for(;;){
    // 找到這個虛擬地址的 PTE（沒有就分配）
    if((pte = walkpgdir(pgdir, a, 1)) == 0)
      return -1;

    // 如果已經映射了 → panic（不能重複映射）
    if(*pte & PTE_P)
      panic("remap");

    // 設定 PTE：物理地址 + 權限 + Present
    *pte = pa | perm | PTE_P;

    if(a == last)
      break;
    a += PGSIZE;   // 下一頁虛擬地址
    pa += PGSIZE;  // 下一頁物理地址
  }
  return 0;
}
```

```
mappages 的工作（以映射 2 頁為例）：

mappages(pgdir, 0x80100000, 8192, 0x00100000, PTE_W)

虛擬 0x80100000 → 物理 0x00100000
虛擬 0x80101000 → 物理 0x00101000

Page Directory[512] → Page Table
                        Page Table[256] → 物理頁 0x00100 | PTE_P | PTE_W
                        Page Table[257] → 物理頁 0x00101 | PTE_P | PTE_W
```

---

## 💻【實作】修改 PTE flag，QEMU 看 crash

### 實驗：拿掉 kernel text 的 PTE_P → 看 kernel 直接炸

```c
// ptetest.c — 展示頁表保護的威力
// 我們在 user 程式裡嘗試存取 kernel 記憶體

#include "types.h"
#include "stat.h"
#include "user.h"

int
main(int argc, char *argv[])
{
  printf(1, "=== 頁表保護測試 ===\n\n");

  printf(1, "我是 user 程式（Ring 3）\n");
  printf(1, "嘗試讀取 kernel 記憶體 0x80000000...\n");

  // kernel 記憶體從 KERNBASE (0x80000000) 開始
  // 頁表裡這些頁面的 PTE_U = 0
  // → user mode 不能存取 → Page Fault!
  char *kernel_addr = (char*)0x80000000;
  char c = *kernel_addr;  // 💥 Page Fault!

  // 不會執行到這裡
  printf(1, "讀到: %d（你不應該看到這行）\n", c);
  exit();
}
```

### 更有趣的實驗：在 kernel 裡拿掉 PTE_W

修改 `vm.c` 的 `kmap`，把 kernel data 的 `PTE_W` 拿掉：

```c
// 原始：
{ (void*)data, V2P(data), PHYSTOP, PTE_W },

// 改成（拿掉 PTE_W）：
{ (void*)data, V2P(data), PHYSTOP, 0 },
```

結果：kernel 啟動後，第一次嘗試寫入任何 kernel data 就會 Page Fault。
因為有 `CR0_WP` 旗標，即使 Ring 0 也不能寫入唯讀頁面！

```bash
cd ~/xv6-public
# 修改 vm.c 的 kmap（拿掉 PTE_W）
make clean && make && make qemu-nox CPUS=1
# → kernel 立刻 panic！因為它不能寫入自己的資料了
# 改回來之後就正常了
```

---

## 📄 其他重要的 vm.c 函數

### `allocuvm()`：幫 user 增加記憶體

```c
int
allocuvm(pde_t *pgdir, uint oldsz, uint newsz)
{
  // 從 oldsz 長到 newsz
  // 每一頁：kalloc() 分配物理頁 → mappages() 建立映射
  // 注意權限：PTE_W | PTE_U → user 可讀寫
  for(; a < newsz; a += PGSIZE){
    mem = kalloc();
    mappages(pgdir, (char*)a, PGSIZE, V2P(mem), PTE_W|PTE_U);
    //                                           ↑      ↑
    //                                         可寫  user 可存取
  }
}
```

### `clearpteu()`：建立 guard page

```c
void
clearpteu(pde_t *pgdir, char *uva)
{
  pte_t *pte;
  pte = walkpgdir(pgdir, uva, 0);
  *pte &= ~PTE_U;  // 清除 PTE_U → user 不能存取這頁
}
// 用在 user stack 下方：如果 stack overflow，會碰到 guard page
// → Page Fault → 被 kernel 抓到，而不是默默覆蓋其他資料
```

### `copyuvm()`：fork 時複製頁表

```c
pde_t*
copyuvm(pde_t *pgdir, uint sz)
{
  // fork() 時呼叫
  // 1. setupkvm() 建立新的 kernel 映射
  // 2. 遍歷父行程的每一頁 user 記憶體
  // 3. kalloc() 分配新物理頁
  // 4. memmove() 複製內容
  // 5. mappages() 在子行程的頁表建立映射
  // → 父子行程有相同的內容，但用不同的物理頁面 → 互不影響
}
```

---

## 🧠 本章小結

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  虛擬地址 32 bits = PDX(10) + PTX(10) + Offset(12)          │
│                                                             │
│  二級頁表：Page Directory → Page Table → Physical Page       │
│  每級 1024 項 × 每項 4 bytes = 4KB                          │
│                                                             │
│  PTE flags:                                                 │
│    PTE_P = 頁面存在？                                        │
│    PTE_W = 可以寫入？                                        │
│    PTE_U = User mode 可以存取？（kernel 隔離的關鍵！）        │
│                                                             │
│  entrypgdir: identity mapping + KERNBASE mapping             │
│    → 開啟分頁時不會炸 + 能跳到高位址的 main()               │
│                                                             │
│  setupkvm(): 完整 kernel 頁表（所有行程共用 kernel 映射）     │
│  mappages(): 逐頁建立 虛擬→物理 的對應                       │
│  walkpgdir(): 查頁表，找到 PTE 的位置                        │
│                                                             │
│  kernel text 唯讀 → 連 kernel 自己都不能改自己的程式碼       │
│  user 記憶體 PTE_U=1 → user 能存取                          │
│  kernel 記憶體 PTE_U=0 → user 碰了就 Page Fault              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## ⏭️ 下一步

頁表保護了記憶體，但 user 程式要怎麼請 kernel 幫忙？
答案是 **Trap 機制**——中斷、例外、系統呼叫的入口。

**而且，這裡會深入講 CPL/DPL/RPL 的權限檢查！**

→ [05_TRAP.md — Trap 機制：中斷與系統呼叫](05_TRAP.md)
