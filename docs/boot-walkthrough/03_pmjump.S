// === 教學筆記 ===
// 📁 原始檔案：arch/x86/boot/pmjump.S (Linux 6.19.3) — 完整檔案
//
// 🔄 這是開機流程的【第三站】
//
// 上一步：02_pm.c 的 go_to_protected_mode() 呼叫 protected_mode_jump()
// 這個檔案就是 protected_mode_jump() 的實作。
//
// 這個檔案做的事：
//   1. 設定 CR0.PE = 1 → CPU 正式進入 Protected Mode！
//   2. 執行 far jump (ljmp) 來刷新 CS → 載入新的 code segment descriptor
//   3. 設定所有 data segment registers (DS, ES, FS, GS, SS)
//   4. 載入 TR (Task Register) 和 LDTR
//   5. 跳到 32-bit 的 entry point（壓縮核心的 startup_32）
//
// 下一步：04_head_64.S 的 startup_32
//
// 🔑 關鍵概念：為什麼需要 far jump？
//    設定 CR0.PE 後，CPU 進入 Protected Mode，但 CS 暫存器還裝著 Real Mode 的值。
//    必須執行一個 far jump 來把新的 segment selector 載入 CS。
//    這個 far jump 同時也會 flush CPU 的 instruction prefetch queue。
// ===

/* SPDX-License-Identifier: GPL-2.0-only */
/* ----------------------------------------------------------------------- *
 *
 *   Copyright (C) 1991, 1992 Linus Torvalds
 *   Copyright 2007 rPath, Inc. - All Rights Reserved
 *
 * ----------------------------------------------------------------------- */

/*
 * The actual transition into protected mode
 */

#include <asm/boot.h>
#include <asm/processor-flags.h>
#include <asm/segment.h>
#include <linux/linkage.h>

	.text
	.code16
// 🔑 還在 16-bit Real Mode（馬上就要離開了！）

// --- protected_mode_jump: Real Mode → Protected Mode ---

/*
 * void protected_mode_jump(u32 entrypoint, u32 bootparams);
 */
SYM_FUNC_START_NOALIGN(protected_mode_jump)
	movl	%edx, %esi		# Pointer to boot_params table
	// 💡 把 boot_params 指標存到 ESI（第二個參數，從 EDX 來）
	// 💡 ESI 會一路傳到後面的 kernel

	xorl	%ebx, %ebx
	movw	%cs, %bx
	shll	$4, %ebx
	addl	%ebx, 2f
	// 🔑 計算 far jump 目標的線性位址
	// 💡 因為還在 Real Mode，需要把 CS*16 加到 .Lin_pm32 的 offset 上
	// 💡 修改下面 label 2 處的 ljmpl 目標位址

	jmp	1f			# Short jump to serialize on 386/486
	// 💡 short jump 是為了在 386/486 上序列化 (serialize) 指令流
1:

	movw	$__BOOT_DS, %cx
	// 💡 把 data segment selector 存到 CX，等下用
	movw	$__BOOT_TSS, %di
	// 💡 把 TSS selector 存到 DI，等下用

	movl	%cr0, %edx
	orb	$X86_CR0_PE, %dl	# Protected mode
	movl	%edx, %cr0
	// 🔑🔑🔑 這就是那一刻！CR0.PE = 1 → CPU 進入 Protected Mode！
	//
	// 💡 CR0 (Control Register 0) 的 bit 0 = PE (Protection Enable)
	//    PE = 0 → Real Mode
	//    PE = 1 → Protected Mode
	//
	// ⚠️ 但此時 CS 還是 Real Mode 的值！
	// ⚠️ 必須馬上執行 far jump 來載入正確的 CS selector

	# Transition to 32-bit mode
	.byte	0x66, 0xea		# ljmpl opcode
	// 🔑 0x66 = operand size override (16→32 bit)
	// 🔑 0xEA = far jump (ljmp) opcode
2:	.long	.Lin_pm32		# offset
	// 🔑 目標 offset（已被上面的程式碼修正為線性位址）
	.word	__BOOT_CS		# segment
	// 🔑 目標 segment selector = __BOOT_CS
	// 💡 這個 far jump 同時做了兩件事：
	//    1. 載入 __BOOT_CS 到 CS register → CS 指向 GDT 中的 code segment
	//    2. 跳到 .Lin_pm32 → 開始執行 32-bit code
SYM_FUNC_END(protected_mode_jump)

// --- .Lin_pm32: 32-bit Protected Mode 的第一段程式碼 ---

	.code32
	// 🔑 從這裡開始是 32-bit 程式碼！
	.section ".text32","ax"
SYM_FUNC_START_LOCAL_NOALIGN(.Lin_pm32)
	# Set up data segments for flat 32-bit mode
	movl	%ecx, %ds
	movl	%ecx, %es
	movl	%ecx, %fs
	movl	%ecx, %gs
	movl	%ecx, %ss
	// 🔑 把所有 data segment registers 都設為 __BOOT_DS
	// 💡 __BOOT_DS 指向 GDT 中的 data segment descriptor (Base=0, Limit=4GB)
	// 💡 這就是 flat model：所有 segment 都從 0 開始，覆蓋整個 4GB

	# The 32-bit code sets up its own stack, but this way we do have
	# a valid stack if some debugging hack wants to use it.
	addl	%ebx, %esp
	// 💡 調整 stack pointer（加上之前計算的 CS base）

	# Set up TR to make Intel VT happy
	ltr	%di
	// 🔑 LTR = Load Task Register，載入 TSS selector
	// 💡 Intel VT (虛擬化技術) 要求 TR 必須指向有效的 TSS

	# Clear registers to allow for future extensions to the
	# 32-bit boot protocol
	xorl	%ecx, %ecx
	xorl	%edx, %edx
	xorl	%ebx, %ebx
	xorl	%ebp, %ebp
	xorl	%edi, %edi
	// 💡 清除暫存器，為 32-bit boot protocol 的未來擴充預留空間

	# Set up LDTR to make Intel VT happy
	lldt	%cx
	// 💡 LLDT = Load Local Descriptor Table Register，設為 0（不使用 LDT）

	jmpl	*%eax			# Jump to the 32-bit entrypoint
	// 🔑🔑🔑 跳到 32-bit 的進入點！
	// 💡 EAX = boot_params.hdr.code32_start（從 protected_mode_jump 的第一個參數來）
	// 💡 通常 = 0x100000 (1MB)，也就是壓縮核心的 startup_32
	// 🔄 → 接下來看 04_head_64.S 的 startup_32
SYM_FUNC_END(.Lin_pm32)
