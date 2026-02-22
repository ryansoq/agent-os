// === 教學筆記 ===
// 📁 原始檔案：arch/x86/boot/compressed/head_64.S (Linux 6.19.3) — 關鍵段落
//
// 🔄 這是開機流程的【第四站】— 最複雜也最精彩的一站！
//
// 上一步：03_pmjump.S 跳到 32-bit 的 startup_32
// 這個檔案做的事：
//   1. 載入新的 GDT（包含 64-bit 的 segment descriptors）
//   2. 建立 4 級頁表 (PML4→PDPT→PD) 做 identity mapping
//   3. 開啟 PAE (Physical Address Extension)
//   4. 設定 EFER.LME (Long Mode Enable)
//   5. 開啟分頁 + far jump → 進入 64-bit Long Mode！
//   6. 在 64-bit mode 中解壓縮核心，跳到真正的 kernel
//
// 下一步：05_kernel_head_64.S 的 startup_64（解壓後的 kernel）
//
// 🔑 從 32-bit Protected Mode 到 64-bit Long Mode 的必要步驟：
//    CR4.PAE = 1 → EFER.LME = 1 → CR0.PG = 1 → far jump (CS.L=1)
// ===

	.code32
	.text

#include <linux/init.h>
#include <linux/linkage.h>
#include <asm/segment.h>
#include <asm/boot.h>
#include <asm/msr.h>
#include <asm/processor-flags.h>
#include <asm/asm-offsets.h>
#include <asm/bootparam.h>
#include <asm/desc_defs.h>
#include <asm/trapnr.h>

// --- startup_32: 32-bit 入口點 ---

	.code32
SYM_FUNC_START(startup_32)
	/*
	 * 32bit entry is 0 and it is ABI so immutable!
	 * If we come here directly from a bootloader,
	 * kernel(text+data+bss+brk) ramdisk, zero_page, command line
	 * all need to be under the 4G limit.
	 */
	cld
	cli
	// 🔑 CLD = 清除方向旗標，CLI = 關中斷

// --- 計算載入偏移 ---
// 💡 kernel 可能被載入到跟編譯時不同的位址（relocatable kernel）
// 💡 需要計算 delta = 實際位址 - 編譯位址

	leal	(BP_scratch+4)(%esi), %esp
	call	1f
1:	popl	%ebp
	subl	$ rva(1b), %ebp
	// 🔑 經典技巧：用 CALL+POP 取得當前 EIP
	// 💡 CALL 會把下一行的位址 push 到 stack
	// 💡 POP 出來就知道我們「真正在」哪個位址
	// 💡 減去編譯時的位址 rva(1b) = 得到偏移量 delta → 存在 EBP

// --- 載入新 GDT ---

	/* Load new GDT with the 64bit segments using 32bit descriptor */
	leal	rva(gdt)(%ebp), %eax
	movl	%eax, 2(%eax)
	lgdt	(%eax)
	// 🔑 載入新 GDT（包含 64-bit 的 segment descriptors）
	// 💡 rva(gdt)(%ebp) = gdt 的實際執行時位址
	// 💡 GDT 內容在檔案末尾定義（見下方 GDT 段落）

	/* Load segment registers with our descriptors */
	movl	$__BOOT_DS, %eax
	movl	%eax, %ds
	movl	%eax, %es
	movl	%eax, %fs
	movl	%eax, %gs
	movl	%eax, %ss

	/* Setup a stack and load CS from current GDT */
	leal	rva(boot_stack_end)(%ebp), %esp

	pushl	$__KERNEL32_CS
	leal	rva(1f)(%ebp), %eax
	pushl	%eax
	lretl
	// 🔑 用 push + lret 技巧做 far jump，載入 __KERNEL32_CS 到 CS
	// 💡 __KERNEL32_CS 是 32-bit code segment (CS.D=1, CS.L=0)
1:

	/* Make sure cpu supports long mode. */
	call	verify_cpu
	testl	%eax, %eax
	jnz	.Lno_longmode
	// ⚠️ 如果 CPU 不支援 Long Mode (64-bit)，直接 HLT 停機

// --- 準備進入 64-bit Long Mode ---

	/* Enable PAE mode */
	movl	%cr4, %eax
	orl	$X86_CR4_PAE, %eax
	movl	%eax, %cr4
	// 🔑 CR4.PAE = 1 → 開啟 Physical Address Extension
	// 💡 PAE 是進入 Long Mode 的先決條件
	// 💡 PAE 讓 CPU 使用 36-bit 以上的實體位址（64GB+）
	// 💡 同時也啟用 4 級頁表結構

// --- 建立 4 級頁表 (Identity Mapping) ---
// 🔑🔑🔑 這是整個開機流程中最關鍵的段落之一！
//
// 💡 頁表的目的：建立 identity mapping（虛擬位址 = 實體位址）
//    因為開啟分頁後，所有記憶體存取都要經過頁表轉換。
//    如果虛擬位址 ≠ 實體位址，程式碼的下一行就會跑到錯誤的地方！
//
// 💡 4 級頁表結構 (x86-64):
//    PML4 (Level 4) → PDPT (Level 3) → PD (Level 2) → PT (Level 1)
//    每一級有 512 個 entry，每個 entry 8 bytes
//    一頁 = 4KB = 512 * 8 bytes
//
//    PML4[0] → PDPT[0..3] → PD[0..2047] → 2MB 大頁 (不需要 Level 1)
//    總共映射：2048 * 2MB = 4GB
//
// 💡 為什麼用 2MB 大頁？
//    4KB 小頁需要 Level 1 (PT)，要多一級頁表，浪費記憶體。
//    開機時只需要粗略映射，2MB 大頁就夠了。

	/* Initialize Page tables to 0 */
	leal	rva(pgtable)(%ebx), %edi
	xorl	%eax, %eax
	movl	$(BOOT_INIT_PGT_SIZE/4), %ecx
	rep	stosl
	// 🔑 先把整個頁表區域清零

	// --- Level 4: PML4 ---
	/* Build Level 4 */
	leal	rva(pgtable + 0)(%ebx), %edi
	leal	0x1007 (%edi), %eax
	movl	%eax, 0(%edi)
	addl	%edx, 4(%edi)
	// 🔑 PML4[0] = pgtable + 0x1000 + 0x7
	//    = 指向下一頁（PDPT 的位址）+ flags
	//
	// 💡 flags 0x007 拆解：
	//    bit 0 (P)   = 1 → Present（頁面存在）
	//    bit 1 (R/W) = 1 → Read/Write（可讀可寫）
	//    bit 2 (U/S) = 1 → User/Supervisor（用戶模式可存取）
	//    → 0x007 = 0b111 = Present + R/W + U/S
	//
	// 💡 0x1007 的意思：
	//    指向 pgtable + 0x1000（下一頁 = PDPT）
	//    加上 flags 0x007

	// --- Level 3: PDPT (Page Directory Pointer Table) ---
	/* Build Level 3 */
	leal	rva(pgtable + 0x1000)(%ebx), %edi
	leal	0x1007(%edi), %eax
	movl	$4, %ecx
1:	movl	%eax, 0x00(%edi)
	addl	%edx, 0x04(%edi)
	addl	$0x00001000, %eax
	addl	$8, %edi
	decl	%ecx
	jnz	1b
	// 🔑 建立 4 個 PDPT entries，每個指向一個 PD
	//    PDPT[0] → pgtable + 0x2000 (PD #0，映射 0-1GB)
	//    PDPT[1] → pgtable + 0x3000 (PD #1，映射 1-2GB)
	//    PDPT[2] → pgtable + 0x4000 (PD #2，映射 2-3GB)
	//    PDPT[3] → pgtable + 0x5000 (PD #3，映射 3-4GB)
	//    每個 PD 可以映射 512 * 2MB = 1GB

	// --- Level 2: PD (Page Directory) — 使用 2MB 大頁 ---
	/* Build Level 2 */
	leal	rva(pgtable + 0x2000)(%ebx), %edi
	movl	$0x00000183, %eax
	movl	$2048, %ecx
1:	movl	%eax, 0(%edi)
	addl	%edx, 4(%edi)
	addl	$0x00200000, %eax
	addl	$8, %edi
	decl	%ecx
	jnz	1b
	// 🔑 建立 2048 個 PD entries，每個映射 2MB
	//    PD[0]    = 0x00000000 + 0x183 → 映射 0x00000000-0x001FFFFF
	//    PD[1]    = 0x00200000 + 0x183 → 映射 0x00200000-0x003FFFFF
	//    ...
	//    PD[2047] = 0xFFE00000 + 0x183 → 映射到 4GB
	//
	// 💡 flags 0x183 拆解：
	//    bit 0 (P)     = 1 → Present
	//    bit 1 (R/W)   = 1 → Read/Write
	//    bit 2 (U/S)   = 0 → Supervisor only
	//    bit 7 (PS)    = 1 → Page Size = 2MB 大頁！
	//    → 0x183 = 0b110000011
	//       = bit 0 (P) + bit 1 (R/W) + bit 7 (PS) + bit 8 (G)
	//
	// 💡 bit 7 (PS = Page Size) 是關鍵：
	//    PS = 0 → 這個 entry 指向下一級頁表 (PT)，最終是 4KB 小頁
	//    PS = 1 → 這個 entry 直接是一個 2MB 大頁，不需要下一級
	//
	// 💡 bit 8 (G = Global)：
	//    G = 1 → 全域頁面，切換 CR3 時不會被 TLB flush
	//
	// 🔑 Identity Mapping 結果：
	//    虛擬位址 0x00000000 → 實體位址 0x00000000
	//    虛擬位址 0x00200000 → 實體位址 0x00200000
	//    ...一直到 4GB，虛擬 = 實體

	// --- 載入頁表到 CR3 ---
	/* Enable the boot page tables */
	leal	rva(pgtable)(%ebx), %eax
	movl	%eax, %cr3
	// 🔑 CR3 = 頁表基址暫存器
	// 💡 把 PML4 的實體位址載入 CR3
	// ⚠️ 注意：此時還沒開啟分頁 (CR0.PG=0)，所以還不會有位址轉換

	// --- 開啟 Long Mode ---
	/* Enable Long mode in EFER (Extended Feature Enable Register) */
	movl	$MSR_EFER, %ecx
	rdmsr
	btsl	$_EFER_LME, %eax
	wrmsr
	// 🔑 EFER.LME = 1 → Long Mode Enable
	// 💡 EFER (Extended Feature Enable Register) 是一個 MSR (Model Specific Register)
	// 💡 用 RDMSR/WRMSR 來讀寫 MSR
	//
	// 💡 EFER 的重要 bits：
	//    bit 8  (LME) = Long Mode Enable — 啟用 Long Mode
	//    bit 10 (LMA) = Long Mode Active — CPU 自動設定（開分頁後）
	//    bit 11 (NXE) = No-Execute Enable — 啟用 NX bit
	//
	// ⚠️ 設定 LME 後，Long Mode 還沒有真正啟動
	// ⚠️ 要等 CR0.PG = 1（開啟分頁）後，CPU 才會自動設定 LMA = 1

	/* After gdt is loaded */
	xorl	%eax, %eax
	lldt	%ax
	movl    $__BOOT_TSS, %eax
	ltr	%ax

	// --- 跳到 64-bit mode ---
	/*
	 * Setup for the jump to 64bit mode
	 *
	 * When the jump is performed we will be in long mode but
	 * in 32bit compatibility mode with EFER.LME = 1, CS.L = 0, CS.D = 1
	 * (and in turn EFER.LMA = 1). To jump into 64bit mode we use
	 * the new gdt/idt that has __KERNEL_CS with CS.L = 1.
	 * We place all of the values on our mini stack so lret can
	 * used to perform that far jump.
	 */
	leal	rva(startup_64)(%ebp), %eax
	pushl	$__KERNEL_CS
	pushl	%eax

	/* Enter paged protected Mode, activating Long Mode */
	movl	$CR0_STATE, %eax
	movl	%eax, %cr0
	// 🔑🔑🔑 CR0.PG = 1 → 開啟分頁！
	// 💡 CR0_STATE 包含：PE (Protection Enable) + PG (Paging) + 其他
	// 💡 PG = 1 的瞬間，因為 EFER.LME = 1，CPU 自動設定 EFER.LMA = 1
	//    → Long Mode 正式啟動！
	//
	// ⚠️ 但此時 CS.L = 0 (因為用 __KERNEL32_CS)
	// ⚠️ 所以 CPU 處於「32-bit 相容模式」(compatibility mode)
	// ⚠️ 需要 far jump 到 CS.L = 1 的 segment 才能進入真正的 64-bit mode

	/* Jump from 32bit compatibility mode into 64bit mode. */
	lret
	// 🔑🔑🔑 用 LRET 做 far jump！
	// 💡 之前 push 了 __KERNEL_CS 和 startup_64 的位址
	// 💡 LRET 會 pop 出 EIP 和 CS
	// 💡 __KERNEL_CS 的 CS.L = 1 → CPU 切換到 64-bit mode！
	// 🔄 → 跳到下面的 startup_64
SYM_FUNC_END(startup_32)

// ============================================================
// === 64-bit mode 開始！ ===
// ============================================================

	.code64
	.org 0x200
SYM_CODE_START(startup_64)
	// 🔑 64-bit entry point! ABI 規定 offset 必須是 0x200
	// 💡 可以從 startup_32 跳過來，也可以從 64-bit bootloader 直接進入

	cld
	cli

	/* Setup data segments. */
	xorl	%eax, %eax
	movl	%eax, %ds
	movl	%eax, %es
	movl	%eax, %ss
	movl	%eax, %fs
	movl	%eax, %gs
	// 💡 64-bit mode 中 segment base 固定為 0（除了 FS/GS）
	// 💡 但還是要清 segment registers

	/* Set up the stack */
	leaq	rva(boot_stack_end)(%rbx), %rsp

	// ... (省略 5-level paging 和 SEV 相關程式碼) ...

	// --- 複製壓縮核心 ---
/*
 * Copy the compressed kernel to the end of our buffer
 * where decompression in place becomes safe.
 */
	leaq	(_bss-8)(%rip), %rsi
	leaq	rva(_bss-8)(%rbx), %rdi
	movl	$(_bss - startup_32), %ecx
	shrl	$3, %ecx
	std
	rep	movsq
	cld
	// 💡 把壓縮核心複製到 buffer 末尾，這樣原地解壓縮才安全

	// --- 跳到重定位後的程式碼 ---
	leaq	rva(.Lrelocated)(%rbx), %rax
	jmp	*%rax
SYM_CODE_END(startup_64)

	.text
SYM_FUNC_START_LOCAL_NOALIGN(.Lrelocated)
	// 🔑 現在在重定位後的位址執行

	/* Clear BSS */
	xorl	%eax, %eax
	leaq    _bss(%rip), %rdi
	leaq    _ebss(%rip), %rcx
	subq	%rdi, %rcx
	shrq	$3, %rcx
	rep	stosq

	/* Pass boot_params to initialize_identity_maps() */
	movq	%r15, %rdi
	call	initialize_identity_maps

	// --- 解壓縮核心！ ---
	/* pass struct boot_params pointer and output target address */
	movq	%r15, %rdi
	movq	%rbp, %rsi
	call	extract_kernel		/* returns kernel entry point in %rax */
	// 🔑 extract_kernel() 解壓縮核心映像
	// 💡 回傳值 (RAX) = 解壓後核心的 entry point

	// --- 跳到解壓後的真正 kernel！ ---
	movq	%r15, %rsi
	jmp	*%rax
	// 🔑🔑🔑 跳到解壓後的 kernel entry point！
	// 💡 RSI = boot_params 指標（傳給 kernel）
	// 🔄 → 接下來看 05_kernel_head_64.S 的 startup_64
SYM_FUNC_END(.Lrelocated)

// ============================================================
// === GDT (Global Descriptor Table) 定義 ===
// ============================================================
// 🔑🔑🔑 這是開機流程中最重要的資料結構之一！

	.data
SYM_DATA_START_LOCAL(gdt64)
	.word	gdt_end - gdt - 1
	// 💡 GDT 大小 - 1
	.quad   gdt - gdt64
	// 💡 GDT 相對於 gdt64 的偏移（會被動態修正為線性位址）
SYM_DATA_END(gdt64)
	.balign	8
SYM_DATA_START_LOCAL(gdt)
	.word	gdt_end - gdt - 1
	.long	0
	.word	0
	// 💡 GDT[0] = null descriptor（x86 規定 GDT 第一個 entry 必須是 null）

	.quad	0x00cf9a000000ffff	/* __KERNEL32_CS */
	// 🔑🔑🔑 __KERNEL32_CS — 32-bit Code Segment
	//
	// 💡 完整 bit field 拆解 (64-bit descriptor, 高位在前):
	//    0x00cf9a000000ffff
	//
	//    高 32-bit: 0x00cf9a00
	//    ┌─ Base[31:24]  = 0x00
	//    ├─ G (Granularity) = 1  → Limit 單位是 4KB
	//    ├─ D/B (Default/Big) = 1  → 32-bit operand/address size
	//    ├─ L (Long mode) = 0  → 不是 64-bit code segment！
	//    ├─ AVL = 0
	//    ├─ Limit[19:16] = 0xF
	//    ├─ P (Present) = 1  → 有效的 segment
	//    ├─ DPL = 00  → Ring 0 (kernel)
	//    ├─ S (System) = 1  → code/data segment (非 system)
	//    ├─ Type = 1010  → Execute/Read (code segment)
	//    └─ Base[23:16] = 0x00
	//
	//    低 32-bit: 0x0000ffff
	//    ┌─ Base[15:0] = 0x0000
	//    └─ Limit[15:0] = 0xFFFF
	//
	//    ✅ Base = 0x00000000 (flat model)
	//    ✅ Limit = 0xFFFFF * 4KB = 4GB
	//    ✅ D = 1, L = 0 → 32-bit code segment
	//    ✅ DPL = 0 → Ring 0 (kernel privilege)

	.quad	0x00af9a000000ffff	/* __KERNEL_CS */
	// 🔑🔑🔑 __KERNEL_CS — 64-bit Code Segment
	//
	// 💡 和 __KERNEL32_CS 的差異只有一個 byte: 0xcf → 0xaf
	//
	//    高 32-bit: 0x00af9a00
	//    ┌─ G = 1  → Limit 單位是 4KB
	//    ├─ D = 0  → ⚠️ 在 Long Mode 中 D 必須是 0！
	//    ├─ L = 1  → 🔑 這是 64-bit code segment！
	//    ├─ Limit[19:16] = 0xF
	//    └─ 其餘同上
	//
	// 🔑 __KERNEL32_CS vs __KERNEL_CS 的關鍵差異：
	//    __KERNEL32_CS: D=1, L=0 → 32-bit compatibility mode
	//    __KERNEL_CS:   D=0, L=1 → 64-bit long mode
	//
	// 💡 在 Long Mode 中：
	//    L=1, D=0 → 64-bit mode (指令預設 64-bit 位址，32-bit operand)
	//    L=0, D=1 → 32-bit compatibility mode (跑 32-bit code)
	//    L=1, D=1 → ❌ 保留！CPU 會產生 #GP exception

	.quad	0x00cf92000000ffff	/* __KERNEL_DS */
	// 💡 Data Segment：和 __KERNEL32_CS 類似，但 Type = 0010 (Read/Write data)
	// 💡 在 64-bit mode 中 DS/ES/SS 的 base/limit 被忽略，但還是需要有效的 descriptor

	.quad	0x0080890000000000	/* TS descriptor */
	.quad   0x0000000000000000	/* TS continued */
	// 💡 TSS descriptor（64-bit mode 中是 16 bytes）
SYM_DATA_END_LABEL(gdt, SYM_L_LOCAL, gdt_end)

// --- 頁表空間 ---
	.section ".pgtable","aw",@nobits
	.balign 4096
SYM_DATA_LOCAL(pgtable,		.fill BOOT_PGT_SIZE, 1, 0)
// 💡 預留的頁表空間，在 startup_32 中被填入 identity mapping
