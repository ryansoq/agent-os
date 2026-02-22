// === 教學筆記 ===
// 📁 原始檔案：arch/x86/boot/header.S (Linux 6.19.3)
//
// 🔄 這是開機流程的【第一站】
//
// 當 BIOS 載入 boot sector 後，控制權來到這裡。
// 這個檔案有兩大部分：
//   1. Setup Header — 給 bootloader 讀的資料結構（告訴它 kernel 的版本、大小等）
//   2. start_of_setup — Real Mode 的入口點，設定 stack、清 BSS、跳到 C code
//
// 流程：BIOS → bootloader (GRUB/syslinux) → _start → start_of_setup → main() → go_to_protected_mode()
//
// ⚠️ 此時 CPU 在 Real Mode (16-bit)，使用 segment:offset 定址
// ⚠️ 只擷取關鍵段落，完整檔案約 500 行
// ===

/* SPDX-License-Identifier: GPL-2.0 */
/*
 *	header.S
 *
 *	Copyright (C) 1991, 1992 Linus Torvalds
 *
 *	Based on bootsect.S and setup.S
 *	modified by more people than can be counted
 *
 *	Rewritten as a common file by H. Peter Anvin (Apr 2007)
 *
 * BIG FAT NOTE: We're in real mode using 64k segments.  Therefore segment
 * addresses must be multiplied by 16 to obtain their respective linear
 * addresses. To avoid confusion, linear addresses are written using leading
 * hex while segment addresses are written as segment:offset.
 *
 */

// --- 常數定義 ---
// 💡 這些是歷史遺留的記憶體位址
BOOTSEG		= 0x07C0		/* original address of boot-sector */
// 🔑 0x07C0 就是 BIOS 載入 boot sector 的經典位址 0x7C00 >> 4
SYSSEG		= 0x1000		/* historical load address >> 4 */

	.code16
// 🔑 .code16 告訴 assembler：我們在 16-bit Real Mode

// --- Setup Header 區塊 ---
// 💡 這個 header 是 bootloader 和 kernel 之間的「合約」
// 💡 bootloader 讀這些欄位來知道怎麼載入 kernel

	.section ".header", "a"
	.globl	sentinel
sentinel:	.byte 0xff, 0xff        /* Used to detect broken loaders */

	.globl	hdr
hdr:
		.byte setup_sects - 1
root_flags:	.word ROOT_RDONLY
syssize:	.long ZO__edata / 16
ram_size:	.word 0			/* Obsolete */
vid_mode:	.word SVGA_MODE
root_dev:	.word 0			/* Default to major/minor 0/0 */
boot_flag:	.word 0xAA55
// 🔑 0xAA55 是 BIOS 辨識可開機磁區的 magic number

	# offset 512, entry point

	.globl	_start
_start:
// 🔑 _start 是 kernel 的第一個進入點！bootloader 跳到這裡
		# Explicitly enter this as bytes, or the assembler
		# tries to generate a 3-byte jump here, which causes
		# everything else to push off to the wrong offset.
		.byte	0xeb		# short (2-byte) jump
		.byte	start_of_setup-1f
// 🔑 這是一個 2-byte 的 short jump，跳到 start_of_setup
// 💡 故意用 .byte 硬編碼，因為 assembler 可能生成 3-byte jump 導致 offset 錯位
1:

	# Part 2 of the header, from the old setup.S

		.ascii	"HdrS"		# header signature
// 🔑 "HdrS" = Header Signature，bootloader 用這個確認 header 格式正確
		.word	0x020f		# header version number (>= 0x0105)
// 💡 header 版本 2.15，不同版本支援不同欄位

		.globl realmode_swtch
realmode_swtch:	.word	0, 0		# default_switch, SETUPSEG
start_sys_seg:	.word	SYSSEG		# obsolete and meaningless

type_of_loader:	.byte	0		# 0 means ancient bootloader
// 💡 bootloader 會把自己的 ID 寫在這裡（GRUB = 0x72）

loadflags:
		.byte	LOADED_HIGH	# The kernel is to be loaded high
// 🔑 LOADED_HIGH 表示 kernel 要載入到 1MB 以上的高位記憶體

code32_start:				# here loaders can put a different
					# start address for 32-bit code.
		.long	0x100000	# 0x100000 = default for big kernel
// 🔑 0x100000 = 1MB，32-bit code 的預設起始位址
// 💡 這個值會傳給 protected_mode_jump() 作為跳轉目標

ramdisk_image:	.long	0		# address of loaded ramdisk image
ramdisk_size:	.long	0		# its size in bytes

cmd_line_ptr:	.long	0		# (Header version 0x0202 or later)
// 💡 指向 kernel command line 的 32-bit 指標（例如 "root=/dev/sda1 console=ttyS0"）

kernel_alignment:  .long CONFIG_PHYSICAL_ALIGN	#physical addr alignment

pref_address:		.quad LOAD_PHYSICAL_ADDR	# preferred load addr
// 💡 kernel 希望被載入的實體位址

init_size:		.long INIT_SIZE		# kernel initialization size
// 💡 kernel 初始化需要的記憶體大小（含解壓縮空間）

// --- start_of_setup 入口 ---
// 🔄 bootloader 跳轉到 _start 後，short jump 到這裡
// 🔄 這段程式碼設定好 Real Mode 環境，然後跳到 C 的 main()

	.section ".entrytext", "ax"
start_of_setup:
# Force %es = %ds
	movw	%ds, %ax
	movw	%ax, %es
	cld
// 💡 確保 ES = DS，CLD 設定字串操作方向為正向

// --- 修正 Stack ---
// ⚠️ 有些古老的 bootloader 會把 SS 設錯，這裡要修正

	movw	%ss, %dx
	cmpw	%ax, %dx	# %ds == %ss?
	movw	%sp, %dx
	je	2f		# -> assume %sp is reasonably set

	# Invalid %ss, make up a new stack
	movw	$_end, %dx
	testb	$CAN_USE_HEAP, loadflags
	jz	1f
	movw	heap_end_ptr, %dx
1:	addw	$STACK_SIZE, %dx
	jnc	2f
	xorw	%dx, %dx	# Prevent wraparound

2:	# Now %dx should point to the end of our stack space
	andw	$~3, %dx	# dword align (might as well...)
	jnz	3f
	movw	$0xfffc, %dx	# Make sure we're not zero
3:	movw	%ax, %ss
	movzwl	%dx, %esp	# Clear upper half of %esp
	sti			# Now we should have a working stack
// 🔑 設定好 SS:SP，開啟中斷（STI）

# We will have entered with %cs = %ds+0x20, normalize %cs so
# it is on par with the other segments.
	pushw	%ds
	pushw	$6f
	lretw
// 🔑 用 lretw (far return) 技巧來修正 CS = DS
// 💡 push DS 和目標 offset，然後 lretw 會 pop 成 CS:IP
6:

# Check signature at end of setup
	cmpl	$0x5a5aaa55, setup_sig
	jne	setup_bad
// 🔑 檢查 setup 簽名，確保資料沒有損壞

# Zero the bss
	movw	$__bss_start, %di
	movw	$_end+3, %cx
	xorl	%eax, %eax
	subw	%di, %cx
	shrw	$2, %cx
	rep stosl
// 🔑 清零 BSS 段（未初始化的全域變數區域）

# Jump to C code (should not return)
	calll	main
// 🔑🔑🔑 跳到 C 語言的 main() 函數！
// 🔄 main() 會做各種硬體偵測，最後呼叫 go_to_protected_mode()
// 🔄 → 接下來看 02_pm.c

# Setup corrupt somehow...
setup_bad:
	movl	$setup_corrupt, %eax
	calll	puts
	# Fall through...

	.globl	die
	.type	die, @function
die:
	hlt
	jmp	die
// ⚠️ 如果出錯就 HLT 無限迴圈，CPU 停擺
