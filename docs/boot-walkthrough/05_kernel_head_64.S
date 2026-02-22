// === 教學筆記 ===
// 📁 原始檔案：arch/x86/kernel/head_64.S (Linux 6.19.3) — 關鍵段落
//
// 🔄 這是開機流程的【第五站】
//
// 上一步：04_head_64.S 解壓縮核心後跳到這裡
// 這個檔案是「正式」64-bit kernel 的入口點。
//
// 這個檔案做的事：
//   1. 保存 boot_params 指標
//   2. 設定 GDT/IDT、GSBASE（per-CPU 資料）
//   3. 修正頁表（fixup page tables for actual load address）
//   4. 設定 CR0/CR4/EFER（NX bit、System Call 等）
//   5. 呼叫 x86_64_start_kernel() → start_kernel()
//
// 下一步：06_main.c 的 start_kernel()
// ===

#include <linux/export.h>
#include <linux/linkage.h>
#include <linux/threads.h>
#include <linux/init.h>
#include <linux/pgtable.h>
#include <asm/segment.h>
#include <asm/page.h>
#include <asm/msr.h>
#include <asm/cache.h>
#include <asm/processor-flags.h>
#include <asm/percpu.h>
#include <asm/nops.h>

// --- startup_64: 解壓後 kernel 的 64-bit 入口 ---

	__INIT
	.code64
SYM_CODE_START_NOALIGN(startup_64)
	UNWIND_HINT_END_OF_STACK
	/*
	 * At this point the CPU runs in 64bit mode CS.L = 1 CS.D = 0,
	 * and someone has loaded an identity mapped page table
	 * for us.  These identity mapped page tables map all of the
	 * kernel pages and possibly all of memory.
	 *
	 * %RSI holds the physical address of the boot_params structure
	 * provided by the bootloader. Preserve it in %R15 so C function calls
	 * will not clobber it.
	 *
	 * We come here either directly from a 64bit bootloader, or from
	 * arch/x86/boot/compressed/head_64.S.
	 */
	// 🔑 此時 CPU 在 64-bit Long Mode (CS.L=1, CS.D=0)
	// 💡 RSI = boot_params 的實體位址（從 bootloader 或壓縮核心傳來）

	mov	%rsi, %r15
	// 🔑 把 boot_params 存到 R15（callee-saved register）
	// 💡 C function 呼叫不會修改 R15

	/* Set up the stack for verify_cpu() */
	leaq	__top_init_kernel_stack(%rip), %rsp
	// 💡 設定初始 stack

	// --- 設定 GSBASE ---
	/*
	 * Set up GSBASE.
	 * Note that on SMP the boot CPU uses the init data section until
	 * the per-CPU areas are set up.
	 */
	movl	$MSR_GS_BASE, %ecx
	xorl	%eax, %eax
	xorl	%edx, %edx
	wrmsr
	// 🔑 GSBASE = 0（暫時）
	// 💡 GS base 在 x86-64 用來存取 per-CPU 資料
	// 💡 後面 setup_per_cpu_areas() 會設定正確的值

	call	__pi_startup_64_setup_gdt_idt
	// 🔑 設定 GDT 和 IDT

	/* Now switch to __KERNEL_CS so IRET works reliably */
	pushq	$__KERNEL_CS
	leaq	.Lon_kernel_cs(%rip), %rax
	pushq	%rax
	lretq
	// 🔑 用 push + lretq 做 far jump，確保 CS = __KERNEL_CS
.Lon_kernel_cs:

	// --- SEV/SME 加密記憶體 (AMD) ---
#ifdef CONFIG_AMD_MEM_ENCRYPT
	movq	%r15, %rdi
	call	__pi_sme_enable
	// 💡 如果是 AMD SEV/SME 環境，啟用記憶體加密
#endif

	/* Sanitize CPU configuration */
	call verify_cpu

	// --- 修正頁表 ---
	/*
	 * Derive the kernel's physical-to-virtual offset
	 */
	leaq	common_startup_64(%rip), %rdi
	subq	.Lcommon_startup_64(%rip), %rdi
	// 💡 計算 phys-to-virt offset（實際載入位址 vs 連結時的虛擬位址）

	/*
	 * Perform pagetable fixups.
	 */
	movq	%r15, %rsi
	call	__pi___startup_64
	// 🔑 修正頁表中的位址，讓它們指向正確的實體記憶體

	/* Form the CR3 value being sure to include the CR3 modifier */
	leaq	early_top_pgt(%rip), %rcx
	addq	%rcx, %rax

	/*
	 * Switch to early_top_pgt which still has the identity mappings
	 * present.
	 */
	movq	%rax, %cr3
	// 🔑 切換到 kernel 自己的頁表（early_top_pgt）

	/* Branch to the common startup code at its kernel virtual address */
	ANNOTATE_RETPOLINE_SAFE
	jmp	*.Lcommon_startup_64(%rip)
	// 🔑 跳到 kernel 虛擬位址空間中的 common_startup_64
	// 💡 從這裡開始，程式碼在虛擬位址空間中執行！
SYM_CODE_END(startup_64)

// --- common_startup_64: 所有 CPU 共用的初始化 ---
// 💡 boot CPU 和 secondary CPUs (SMP) 都會經過這裡

SYM_INNER_LABEL(common_startup_64, SYM_L_LOCAL)
	UNWIND_HINT_END_OF_STACK

	// --- 設定 CR4 ---
	movl	$(X86_CR4_PAE | X86_CR4_LA57), %edx
	// 💡 保留 PAE 和 LA57 (5-level paging，如果有的話)
#ifdef CONFIG_X86_MCE
	orl	$X86_CR4_MCE, %edx
	// 💡 保留 MCE (Machine Check Exception)
#endif
	movq	%cr4, %rcx
	andl	%edx, %ecx

	/* Even if ignored in long mode, set PSE uniformly on all logical CPUs. */
	btsl	$X86_CR4_PSE_BIT, %ecx
	movq	%rcx, %cr4
	// 💡 PSE = Page Size Extension（雖然 Long Mode 會忽略）

	/* Set CR4.PGE to re-enable global translations. */
	btsl	$X86_CR4_PGE_BIT, %ecx
	movq	%rcx, %cr4
	// 🔑 PGE = Page Global Enable
	// 💡 啟用 global pages（CR3 切換時不會被 TLB flush 的頁面）

	// --- (省略 SMP APIC ID 查詢部分) ---

	// --- 設定 Stack ---
	/*
	 * Setup a boot time stack
	 */
	movq	current_task(%rdx), %rax
	movq	TASK_threadsp(%rax), %rsp
	// 🔑 從 current_task 取得 stack pointer
	// 💡 對 boot CPU，這是 init_task 的 stack

	// --- 載入最終 GDT ---
.Lsetup_gdt:
	subq	$16, %rsp
	movw	$(GDT_SIZE-1), (%rsp)
	leaq	gdt_page(%rdx), %rax
	movq	%rax, 2(%rsp)
	lgdt	(%rsp)
	addq	$16, %rsp
	// 🔑 載入 kernel 正式的 GDT（per-CPU 的 gdt_page）

	/* set up data segments */
	xorl %eax,%eax
	movl %eax,%ds
	movl %eax,%ss
	movl %eax,%es
	movl %eax,%fs
	movl %eax,%gs
	// 💡 64-bit mode 中 data segments 設為 0

	// --- 設定 GSBASE (per-CPU) ---
	movl	$MSR_GS_BASE,%ecx
	movl	%edx, %eax
	shrq	$32, %rdx
	wrmsr
	// 🔑 把 per-CPU offset 載入 GSBASE
	// 💡 之後用 %gs:offset 就能存取 per-CPU 變數

	/* Setup and Load IDT */
	call	early_setup_idt
	// 🔑 設定早期 IDT

	// --- 設定 EFER ---
	/* Setup EFER (Extended Feature Enable Register) */
	movl	$MSR_EFER, %ecx
	rdmsr
	movl    %eax, %edx
	btsl	$_EFER_SCE, %eax	/* Enable System Call */
	// 🔑 EFER.SCE = 1 → 啟用 SYSCALL/SYSRET 指令
	// 💡 這是 64-bit Linux 系統呼叫的基礎！

	btl	$20,%edi		/* No Execute supported? */
	jnc     1f
	btsl	$_EFER_NX, %eax
	// 🔑 EFER.NX = 1 → 啟用 NX (No-Execute) bit
	// 💡 NX 讓某些頁面不可執行（安全性：防止 stack overflow 攻擊）
	btsq	$_PAGE_BIT_NX,early_pmd_flags(%rip)

1:	cmpl	%edx, %eax
	je	1f
	xor	%edx, %edx
	wrmsr				/* Make changes effective */
	// 💡 只有在 EFER 有變化時才寫入（為了 TDX 虛擬化客戶端）
1:

	/* Setup cr0 */
	movl	$CR0_STATE, %eax
	movq	%rax, %cr0
	// 🔑 設定 CR0 最終狀態

	/* zero EFLAGS after setting rsp */
	pushq $0
	popfq
	// 💡 清除所有 EFLAGS

	/* Pass the boot_params pointer as first argument */
	movq	%r15, %rdi
	// 🔑 RDI = boot_params（第一個參數，x86-64 calling convention）

.Ljump_to_C_code:
	xorl	%ebp, %ebp	# clear frame pointer
	ANNOTATE_RETPOLINE_SAFE
	callq	*initial_code(%rip)
	// 🔑🔑🔑 呼叫 x86_64_start_kernel()！
	// 💡 initial_code = x86_64_start_kernel（定義在下方）
	// 💡 x86_64_start_kernel() 會呼叫 start_kernel()
	// 🔄 → 接下來看 06_main.c 的 start_kernel()
	ud2
	// ⚠️ 不應該回來！如果回來就 UD2 觸發 #UD exception

// --- initial_code 定義 ---
	__REFDATA
	.balign	8
SYM_DATA(initial_code,	.quad x86_64_start_kernel)
// 🔑 initial_code = x86_64_start_kernel 的位址

// --- 頁表定義 ---
// 💡 kernel 的正式頁表結構

	__INITDATA
SYM_DATA_START_PTI_ALIGNED(early_top_pgt)
	.fill	511,8,0
	.quad	level3_kernel_pgt - __START_KERNEL_map + _PAGE_TABLE_NOENC
	// 🔑 PML4[511] → level3_kernel_pgt
	// 💡 kernel 映射在虛擬位址空間的最高 512GB (0xFFFF800000000000+)
SYM_DATA_END(early_top_pgt)

SYM_DATA_START_PAGE_ALIGNED(level3_kernel_pgt)
	.fill	L3_START_KERNEL,8,0
	.quad	level2_kernel_pgt - __START_KERNEL_map + _KERNPG_TABLE_NOENC
	.quad	level2_fixmap_pgt - __START_KERNEL_map + _PAGE_TABLE_NOENC
	// 💡 PDPT entry 指向 kernel 的 PD 和 fixmap 的 PD
SYM_DATA_END(level3_kernel_pgt)

SYM_DATA_START_PAGE_ALIGNED(level2_kernel_pgt)
	/*
	 * Kernel high mapping.
	 */
	PMDS(0, __PAGE_KERNEL_LARGE_EXEC, KERNEL_IMAGE_SIZE/PMD_SIZE)
	// 🔑 用 2MB 大頁映射整個 kernel image
	// 💡 KERNEL_IMAGE_SIZE = 512MB 或 1GB（取決於 CONFIG_RANDOMIZE_BASE）
SYM_DATA_END(level2_kernel_pgt)
