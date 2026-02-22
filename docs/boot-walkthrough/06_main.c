// === 教學筆記 ===
// 📁 原始檔案：init/main.c (Linux 6.19.3) — start_kernel() 段落
//
// 🔄 這是開機流程的【第六站】— 最終站！
//
// 上一步：05_kernel_head_64.S → x86_64_start_kernel() → start_kernel()
// 這個函數是整個 Linux kernel 初始化的起點。
//
// start_kernel() 做的事（按順序）：
//   1. 基礎設施：stack canary、debug objects、cgroup
//   2. 關中斷，設定 boot CPU
//   3. 記憶體管理：page allocator、slab allocator
//   4. 排程器 (scheduler)
//   5. 中斷系統：IRQ、timer、softirq
//   6. 各種子系統：VFS、network、security、procfs
//   7. rest_init() → 啟動 init process (PID 1)
//
// 💡 看完這個函數，你就對 Linux kernel 的初始化有完整的地圖了！
// ===

// SPDX-License-Identifier: GPL-2.0-only
/*
 *  linux/init/main.c
 *
 *  Copyright (C) 1991, 1992  Linus Torvalds
 */

// --- start_kernel(): 所有初始化的起點 ---

void start_kernel(void)
{
	char *command_line;
	char *after_dashes;

	set_task_stack_end_magic(&init_task);
	// 💡 在 init_task 的 stack 底部寫入 magic number，用來偵測 stack overflow

	smp_setup_processor_id();
	// 💡 設定 boot CPU 的 processor ID

	debug_objects_early_init();
	init_vmlinux_build_id();

	cgroup_init_early();
	// 💡 早期 cgroup 初始化

// --- 關閉中斷 ---
	local_irq_disable();
	early_boot_irqs_disabled = true;
	// 🔑 關閉本地 CPU 中斷！
	// ⚠️ 接下來的初始化必須在中斷關閉的狀態下進行

	/*
	 * Interrupts are still disabled. Do necessary setups, then
	 * enable them.
	 */
	boot_cpu_init();
	// 🔑 標記 boot CPU 為 online/active/present/possible

	page_address_init();
	pr_notice("%s", linux_banner);
	// 💡 印出 Linux 版本資訊（你在 dmesg 看到的第一行）

// --- 架構相關初始化 ---
	setup_arch(&command_line);
	// 🔑🔑🔑 超重要！架構相關的初始化
	// 💡 對 x86 來說，這裡面做了：
	//    - 解析 boot_params
	//    - 設定記憶體映射 (e820 map)
	//    - 初始化頁表
	//    - 設定 CPU features
	//    - 初始化 ACPI tables
	//    - 等等……非常多

	jump_label_init();
	static_call_init();
	early_security_init();
	setup_boot_config();
	setup_command_line(command_line);
	// 💡 解析 kernel command line（例如 "root=/dev/sda1 console=ttyS0"）

	setup_nr_cpu_ids();
	setup_per_cpu_areas();
	// 🔑 設定 per-CPU 記憶體區域
	// 💡 每個 CPU 有自己的一塊記憶體，用 %gs:offset 存取

	smp_prepare_boot_cpu();	/* arch-specific boot-cpu hooks */
	early_numa_node_init();
	boot_cpu_hotplug_init();

	print_kernel_cmdline(saved_command_line);
	parse_early_param();
	// 💡 解析 early boot parameters

	after_dashes = parse_args("Booting kernel",
				  static_command_line, __start___param,
				  __stop___param - __start___param,
				  -1, -1, NULL, &unknown_bootoption);
	print_unknown_bootoptions();
	if (!IS_ERR_OR_NULL(after_dashes))
		parse_args("Setting init args", after_dashes, NULL, 0, -1, -1,
			   NULL, set_init_arg);
	if (extra_init_args)
		parse_args("Setting extra init args", extra_init_args,
			   NULL, 0, -1, -1, NULL, set_init_arg);

	/* Architectural and non-timekeeping rng init, before allocator init */
	random_init_early(command_line);

// --- 記憶體管理初始化 ---
	setup_log_buf(0);
	// 💡 設定 kernel log buffer（printk 的底層）

	vfs_caches_init_early();
	sort_main_extable();
	trap_init();
	// 🔑 設定 exception handlers（#PF, #GP, #UD 等）

	mm_core_init();
	// 🔑 記憶體管理核心初始化（page allocator 等）

	maple_tree_init();
	poking_init();
	ftrace_init();
	early_trace_init();

// --- 排程器初始化 ---
	/*
	 * Set up the scheduler prior starting any interrupts (such as the
	 * timer interrupt). Full topology setup happens at smp_init()
	 * time - but meanwhile we still have a functioning scheduler.
	 */
	sched_init();
	// 🔑🔑 排程器初始化！
	// 💡 從這裡開始，kernel 可以做基本的 task scheduling

	if (WARN(!irqs_disabled(),
		 "Interrupts were enabled *very* early, fixing it\n"))
		local_irq_disable();
	radix_tree_init();

	housekeeping_init();

	workqueue_init_early();
	// 💡 工作佇列早期初始化

	rcu_init();
	// 🔑 RCU (Read-Copy-Update) 初始化
	// 💡 RCU 是 Linux 最重要的同步機制之一

	kvfree_rcu_init();
	trace_init();

	if (initcall_debug)
		initcall_debug_enable();

	context_tracking_init();

// --- 中斷系統初始化 ---
	early_irq_init();
	init_IRQ();
	// 🔑 中斷系統初始化

	tick_init();
	rcu_init_nohz();
	timers_init();
	srcu_init();
	hrtimers_init();
	// 🔑 各種 timer 初始化

	softirq_init();
	// 🔑 softirq 初始化（軟中斷：網路封包處理等）

	timekeeping_init();
	time_init();
	// 🔑 時間子系統初始化

	random_init();

// --- 更多子系統 ---
	kfence_init();
	boot_init_stack_canary();

	perf_event_init();
	// 💡 效能計數器初始化

	profile_init();
	call_function_init();
	WARN(!irqs_disabled(), "Interrupts were enabled early\n");

	early_boot_irqs_disabled = false;
	local_irq_enable();
	// 🔑🔑 中斷終於開啟了！！！
	// 💡 從 start_kernel 開頭到這裡，中斷一直是關的

	kmem_cache_init_late();
	// 💡 slab allocator 後期初始化

	/*
	 * HACK ALERT! This is early. We're enabling the console before
	 * we've done PCI setups etc, and console_init() must be aware of
	 * this. But we do want output early, in case something goes wrong.
	 */
	console_init();
	// 🔑 主控台初始化！
	// 💡 從這裡開始，printk 的輸出才會顯示在螢幕上

	if (panic_later)
		panic("Too many boot %s vars at `%s'", panic_later,
		      panic_param);

	lockdep_init();
	locking_selftest();

	setup_per_cpu_pageset();
	numa_policy_init();
	acpi_early_init();
	// 💡 ACPI 早期初始化

	if (late_time_init)
		late_time_init();
	sched_clock_init();
	calibrate_delay();
	// 💡 校準 delay loop（計算 BogoMIPS）

	arch_cpu_finalize_init();

// --- Process 和 VFS 初始化 ---
	pid_idr_init();
	anon_vma_init();
	thread_stack_cache_init();
	cred_init();
	fork_init();
	// 🔑 fork() 系統呼叫初始化

	proc_caches_init();
	uts_ns_init();
	time_ns_init();
	key_init();
	security_init();
	// 🔑 安全子系統初始化 (LSM: SELinux, AppArmor 等)

	dbg_late_init();
	net_ns_init();
	// 💡 網路命名空間初始化

	vfs_caches_init();
	// 🔑 VFS (Virtual File System) 快取初始化
	// 💡 dentry cache, inode cache 等

	pagecache_init();
	signals_init();
	seq_file_init();
	proc_root_init();
	// 🔑 /proc 檔案系統初始化

	nsfs_init();
	pidfs_init();
	cpuset_init();
	mem_cgroup_init();
	cgroup_init();
	// 💡 cgroup 完整初始化

	taskstats_init_early();
	delayacct_init();

	acpi_subsystem_init();
	arch_post_acpi_subsys_init();
	kcsan_init();

	/* Do the rest non-__init'ed, we're now alive */
	rest_init();
	// 🔑🔑🔑 rest_init() — 開機流程的最後一步！
	//
	// 💡 rest_init() 做了什麼：
	//    1. 建立 kernel_init thread (PID 1)
	//       → kernel_init() → run_init_process("/sbin/init")
	//       → 這就是 userspace 的 init process！
	//    2. 建立 kthreadd (PID 2)
	//       → 所有 kernel thread 的父程序
	//    3. boot CPU 進入 idle loop
	//       → cpu_startup_entry(CPUHP_ONLINE)
	//
	// 🎉 到這裡，Linux kernel 初始化完成！
	// 🎉 init process (PID 1) 接手，開始啟動 userspace！
	// 🎉 開機流程結束！

	/*
	 * Avoid stack canaries in callers of boot_init_stack_canary for gcc-10
	 * and older.
	 */
#if !__has_attribute(__no_stack_protector__)
	prevent_tail_call_optimization();
#endif
}
