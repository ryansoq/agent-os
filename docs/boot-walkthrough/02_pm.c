// === 教學筆記 ===
// 📁 原始檔案：arch/x86/boot/pm.c (Linux 6.19.3) — 完整檔案
//
// 🔄 這是開機流程的【第二站】
//
// 上一步：01_header.S 的 start_of_setup → main() → go_to_protected_mode()
// 這個檔案的 go_to_protected_mode() 是 main() 最後呼叫的函數。
//
// 這個檔案做的事：
//   1. 關閉中斷（CLI + 關 NMI）
//   2. 開啟 A20 gate（讓 CPU 能存取 1MB 以上的記憶體）
//   3. 設定 GDT（Global Descriptor Table）— 定義記憶體段的權限和範圍
//   4. 設定 IDT（Interrupt Descriptor Table）— 設為空，因為保護模式下還沒準備好
//   5. 呼叫 protected_mode_jump() 真正切換到保護模式
//
// 下一步：03_pmjump.S 的 protected_mode_jump()
// ===

// SPDX-License-Identifier: GPL-2.0-only
/* -*- linux-c -*- ------------------------------------------------------- *
 *
 *   Copyright (C) 1991, 1992 Linus Torvalds
 *   Copyright 2007 rPath, Inc. - All Rights Reserved
 *
 * ----------------------------------------------------------------------- */

/*
 * Prepare the machine for transition to protected mode.
 */

#include "boot.h"
#include <asm/desc_defs.h>
#include <asm/segment.h>

// --- 區塊一：關閉 Real Mode 中斷 ---
// 💡 進入保護模式前必須把中斷全部關掉，
//    因為 Real Mode 的中斷處理方式和 Protected Mode 完全不同

/*
 * Invoke the realmode switch hook if present; otherwise
 * disable all interrupts.
 */
static void realmode_switch_hook(void)
{
	if (boot_params.hdr.realmode_swtch) {
		// 💡 有些 bootloader 會提供自己的 real mode switch hook
		asm volatile("lcallw *%0"
			     : : "m" (boot_params.hdr.realmode_swtch)
			     : "eax", "ebx", "ecx", "edx");
	} else {
		asm volatile("cli");
		// 🔑 CLI = Clear Interrupt Flag，關閉可遮罩中斷
		outb(0x80, 0x70); /* Disable NMI */
		// 🔑 寫入 port 0x70 的 bit 7 = 1 來關閉 NMI (Non-Maskable Interrupt)
		// ⚠️ NMI 不能被 CLI 關掉，必須透過 I/O port 控制
		io_delay();
	}
}

// --- 區塊二：遮罩 PIC 中斷 ---
// 💡 8259 PIC (Programmable Interrupt Controller) 是舊式中斷控制器
// 💡 就算 CLI 了，PIC 本身還是會產生信號，所以要從源頭遮罩

/*
 * Disable all interrupts at the legacy PIC.
 */
static void mask_all_interrupts(void)
{
	outb(0xff, 0xa1);	/* Mask all interrupts on the secondary PIC */
	// 🔑 port 0xA1 = 副 PIC (IRQ 8-15)，寫 0xFF = 遮罩全部
	io_delay();
	outb(0xfb, 0x21);	/* Mask all but cascade on the primary PIC */
	// 🔑 port 0x21 = 主 PIC (IRQ 0-7)，0xFB = 11111011
	// 💡 保留 IRQ2 (cascade)，因為副 PIC 透過 IRQ2 連接主 PIC
	io_delay();
}

// --- 區塊三：重設協處理器 ---

/*
 * Reset IGNNE# if asserted in the FPU.
 */
static void reset_coprocessor(void)
{
	outb(0, 0xf0);
	io_delay();
	outb(0, 0xf1);
	io_delay();
	// 💡 重設 x87 FPU 的 IGNNE# 信號，歷史遺留操作
}

// --- 區塊四：設定 GDT (Global Descriptor Table) ---
// 🔑🔑🔑 這是進入保護模式最關鍵的步驟之一！
//
// 💡 GDT 是什麼？
//    在 Protected Mode 中，segment register (CS, DS 等) 不再直接存放段基址，
//    而是存放一個「selector」，指向 GDT 中的一個 entry。
//    每個 GDT entry (8 bytes) 定義了：段基址、段限制、存取權限等。
//
// 💡 為什麼需要 GDT？
//    Real Mode 沒有記憶體保護，任何程式都能存取任何記憶體。
//    Protected Mode 透過 GDT 來控制每個段的權限。

/*
 * Set up the GDT
 */

struct gdt_ptr {
	u16 len;
	u32 ptr;
} __attribute__((packed));
// 💡 GDTR 暫存器的格式：2 bytes 長度 + 4 bytes 基址

static void setup_gdt(void)
{
	/* There are machines which are known to not boot with the GDT
	   being 8-byte unaligned.  Intel recommends 16 byte alignment. */
	static const u64 boot_gdt[] __attribute__((aligned(16))) = {
		/* CS: code, read/execute, 4 GB, base 0 */
		[GDT_ENTRY_BOOT_CS] = GDT_ENTRY(DESC_CODE32, 0, 0xfffff),
		// 🔑 Code Segment：可讀+可執行，Base=0, Limit=4GB
		// 💡 DESC_CODE32 = 32-bit code segment descriptor type
		// 💡 Limit=0xFFFFF * 4KB (Granularity=1) = 4GB

		/* DS: data, read/write, 4 GB, base 0 */
		[GDT_ENTRY_BOOT_DS] = GDT_ENTRY(DESC_DATA32, 0, 0xfffff),
		// 🔑 Data Segment：可讀+可寫，Base=0, Limit=4GB
		// 💡 這種 Base=0, Limit=4GB 的設定叫做 "flat model"
		// 💡 意思是段基址=0，整個 4GB 空間都可以存取（等於沒有分段）

		/* TSS: 32-bit tss, 104 bytes, base 4096 */
		/* We only have a TSS here to keep Intel VT happy;
		   we don't actually use it for anything. */
		[GDT_ENTRY_BOOT_TSS] = GDT_ENTRY(DESC_TSS32, 4096, 103),
		// 💡 TSS (Task State Segment) 在這裡只是為了讓 Intel VT (虛擬化) 開心
		// 💡 實際上開機過程不使用 hardware task switching
	};

	/* Xen HVM incorrectly stores a pointer to the gdt_ptr, instead
	   of the gdt_ptr contents.  Thus, make it static so it will
	   stay in memory, at least long enough that we switch to the
	   proper kernel GDT. */
	static struct gdt_ptr gdt;

	gdt.len = sizeof(boot_gdt)-1;
	// 💡 GDTR.limit = GDT 大小 - 1（慣例）
	gdt.ptr = (u32)&boot_gdt + (ds() << 4);
	// 🔑 計算 GDT 的線性位址：段內偏移 + DS*16
	// 💡 因為我們還在 Real Mode，需要手動計算線性位址

	asm volatile("lgdtl %0" : : "m" (gdt));
	// 🔑 LGDT 指令：把 GDT 的位址和大小載入 GDTR 暫存器
	// 🔄 載入 GDT 後，CPU 就知道怎麼解讀 segment selector 了
}

// --- 區塊五：設定 IDT ---
// 💡 IDT 設為空（null），因為在切換過程中不處理任何中斷
// ⚠️ 中斷已經被 CLI + NMI disable + PIC mask 完全關掉了

/*
 * Set up the IDT
 */
static void setup_idt(void)
{
	static const struct gdt_ptr null_idt = {0, 0};
	asm volatile("lidtl %0" : : "m" (null_idt));
	// 🔑 LIDT 指令：載入一個空的 IDT
	// 💡 如果這時候有中斷發生，CPU 會 triple fault → 重開機
}

// --- 區塊六：go_to_protected_mode() — 主流程 ---
// 🔑🔑🔑 這是從 Real Mode 到 Protected Mode 的總控函數

/*
 * Actual invocation sequence
 */
void go_to_protected_mode(void)
{
	/* Hook before leaving real mode, also disables interrupts */
	realmode_switch_hook();
	// 🔑 第一步：關閉所有中斷 (CLI + NMI)

	/* Enable the A20 gate */
	if (enable_a20()) {
		puts("A20 gate not responding, unable to boot...\n");
		die();
	}
	// 🔑 第二步：開啟 A20 gate
	// 💡 A20 gate 是什麼？
	//    8086 CPU 只有 20 條地址線 (A0-A19)，最多定址 1MB。
	//    286 以後有更多地址線，但為了向下相容，A20 (第 21 條線) 預設被關閉。
	//    如果不開 A20，位址會 wrap around：存取 1MB+X 會變成存取 X。
	//    必須開啟 A20 才能存取 1MB 以上的記憶體！

	/* Reset coprocessor (IGNNE#) */
	reset_coprocessor();
	// 💡 第三步：重設 FPU

	/* Mask all interrupts in the PIC */
	mask_all_interrupts();
	// 🔑 第四步：從 PIC 源頭遮罩所有中斷

	/* Actual transition to protected mode... */
	setup_idt();
	// 🔑 第五步：載入空 IDT
	setup_gdt();
	// 🔑 第六步：載入 GDT（定義 flat model 的 code/data segments）

	protected_mode_jump(boot_params.hdr.code32_start,
			    (u32)&boot_params + (ds() << 4));
	// 🔑🔑🔑 第七步：跳到 Protected Mode！
	// 💡 參數 1：code32_start = 32-bit code 的進入點（通常是 0x100000 = 1MB）
	// 💡 參數 2：boot_params 的線性位址（傳給後面的 kernel 用）
	// 🔄 → 接下來看 03_pmjump.S
}
