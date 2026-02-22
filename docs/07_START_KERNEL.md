# 📚 07 — start_kernel()：C 語言的起點

> 組合語言的旅程結束了。從這裡開始，一切都是 C。

---

## 🎉 歡迎來到 C 的世界

經過 Real Mode → Protected Mode → Long Mode 的漫長旅途，kernel 終於被解壓縮並跳到了 `init/main.c` 的 `start_kernel()`。

**比喻：** 之前的組合語言像是在荒野中鋪路搭橋（設定 GDT、頁表、模式切換）。現在我們終於到了城市入口，可以用現代工具（C 語言）來建設了。

---

## 📝 start_kernel() 完整導覽

```c
// 檔案：init/main.c（Linux 6.19.3，第 1005 行）
// 這是整個 Linux kernel 的 C 語言起點

void start_kernel(void)
{
    char *command_line;
    char *after_dashes;

    // ===== 第一階段：最基本的初始化 =====

    set_task_stack_end_magic(&init_task);
    //  在 init_task 的堆疊底部寫入 magic number
    //  用來偵測堆疊溢位（如果被覆蓋就知道溢位了）

    smp_setup_processor_id();
    //  設定當前 CPU 的 ID（多核心系統用）

    cgroup_init_early();
    //  早期 cgroup 初始化（容器的資源控制）

    local_irq_disable();
    //  關閉中斷！接下來的初始化不能被打斷

    // ===== 第二階段：架構相關初始化 =====

    boot_cpu_init();
    //  標記當前 CPU 為「已啟動」

    page_address_init();
    //  初始化高記憶體的頁面地址映射

    pr_notice("%s", linux_banner);
    //  印出 "Linux version 6.19.3 ..."（你在開機時看到的第一行）

    setup_arch(&command_line);
    //  🔥 最重要的函數之一！
    //  設定 CPU 架構相關的一切：
    //  - 解析 boot_params
    //  - 建立完整的記憶體映射
    //  - 初始化 ACPI
    //  - 偵測 CPU 功能

    setup_command_line(command_line);
    //  解析 kernel command line（例如 "root=/dev/sda1 console=ttyS0"）

    setup_per_cpu_areas();
    //  為每個 CPU 分配獨立的資料區域

    // ===== 第三階段：核心子系統初始化 =====

    trap_init();
    //  設定異常處理（除零錯誤、Page Fault 等）

    mm_core_init();
    //  初始化記憶體管理核心（buddy allocator、slab）

    sched_init();
    //  🔥 初始化排程器（Scheduler）
    //  從此 kernel 可以排程行程了

    // ===== 第四階段：中斷與時間 =====

    early_irq_init();
    init_IRQ();
    //  初始化中斷控制器

    tick_init();
    timers_init();
    hrtimers_init();
    //  初始化各種計時器（tick、一般計時器、高精度計時器）

    timekeeping_init();
    time_init();
    //  初始化時間系統（從此 kernel 知道現在幾點了）

    local_irq_enable();
    //  🎉 重新開啟中斷！從此 kernel 可以回應硬體事件

    // ===== 第五階段：裝置與檔案系統 =====

    console_init();
    //  初始化 console（從此可以在螢幕上顯示文字）

    vfs_caches_init();
    //  初始化 VFS（Virtual File System）快取

    signals_init();
    //  初始化信號機制（kill、SIGTERM 等）

    proc_root_init();
    //  建立 /proc 檔案系統

    // ===== 最後：啟動第一個行程 =====

    rest_init();
    //  🔥 這個函數會建立 PID 1 和 PID 2，然後當前執行緒變成 idle
}
```

---

## 🌱 rest_init() — PID 0, 1, 2 的誕生

`rest_init()` 是 `start_kernel()` 的最後一步，但也是最重要的一步：

```c
// 檔案：init/main.c（第 711 行）

static noinline void __ref __noreturn rest_init(void)
{
    int pid;

    rcu_scheduler_starting();
    // RCU（Read-Copy-Update）排程器開始運作

    // ===== 建立 PID 1：init 行程 =====
    pid = user_mode_thread(kernel_init, NULL, CLONE_FS);
    //  建立一個新執行緒，執行 kernel_init()
    //  這就是 PID 1 — Linux 的「初始行程」
    //  之後會變成 /sbin/init（User Space 的第一個程式）

    // ===== 建立 PID 2：kthreadd =====
    pid = kernel_thread(kthreadd, NULL, NULL, CLONE_FS | CLONE_FILES);
    //  建立 kthreadd — kernel 執行緒的管家
    //  所有 kernel thread 都由它建立

    // ===== PID 0：idle 行程 =====
    schedule_preempt_disabled();
    cpu_startup_entry(CPUHP_ONLINE);
    //  當前執行緒（PID 0）變成 idle 行程
    //  CPU 沒事做的時候就執行它（省電）
    //  這個函數永遠不會返回！
}
```

### 三個始祖行程

```
PID 0: idle（閒置行程）
  │    ← 就是執行 start_kernel() 的那個執行緒
  │    ← 當沒有其他行程需要 CPU 時，就執行它
  │
  ├── PID 1: init（初始行程）
  │    ← 由 kernel_init() 建立
  │    ← 之後會執行 /sbin/init
  │    ← 所有 User Space 行程的祖先
  │
  └── PID 2: kthreadd（kernel 執行緒管家）
       ← 負責建立所有 kernel thread
       ← 例如：kworker、ksoftirqd、kswapd...
```

---

## 🚀 kernel_init() → kernel_execve("/sbin/init")

PID 1 被建立後，它執行 `kernel_init()`：

```c
// 檔案：init/main.c（第 1569 行）

static int __ref kernel_init(void *unused)
{
    // 等 kthreadd 準備好
    wait_for_completion(&kthreadd_done);

    // 完成剩餘的初始化
    kernel_init_freeable();

    // 釋放 __init 標記的記憶體（那些只在開機時用的函數）
    free_initmem();

    system_state = SYSTEM_RUNNING;
    // 🎉 系統正式進入「運行中」狀態！

    // ===== 嘗試執行 init 程式 =====

    // 優先試 ramdisk 裡的 init
    if (ramdisk_execute_command) {
        ret = run_init_process(ramdisk_execute_command);
        if (!ret) return 0;  // 成功！
    }

    // 試 kernel command line 指定的 init=xxx
    if (execute_command) {
        ret = run_init_process(execute_command);
        // ...
    }

    // 都沒有？試預設路徑
    if (!try_to_run_init_process("/sbin/init") ||
        !try_to_run_init_process("/etc/init") ||
        !try_to_run_init_process("/bin/init") ||
        !try_to_run_init_process("/bin/sh"))
        return 0;

    panic("No working init found.");
    // 如果連 /bin/sh 都找不到 → kernel panic！
}
```

### run_init_process() 的關鍵

```c
// run_init_process() 最終呼叫：
return kernel_execve(init_filename, argv_init, envp_init);
```

**`kernel_execve()`** 是 kernel 版本的 `execve()` 系統呼叫。它把當前行程的記憶體空間替換成新程式的內容。

執行完 `kernel_execve("/sbin/init")` 後：
- PID 1 的程式碼從 kernel 的 `kernel_init()` 變成了 `/sbin/init`
- PID 1 從 **Ring 0（Kernel Mode）** 切換到 **Ring 3（User Mode）**
- 這是 **Kernel 和 User Space 的分界線**！

---

## 🔒 Ring 0 → Ring 3 的分界線

```
             Ring 0 (Kernel Mode)
                    │
    start_kernel() → rest_init() → kernel_init()
                    │
                    │  kernel_execve("/sbin/init")
                    │
    ═══════════════════════════════════════════  ← 分界線
                    │
                    ↓
             Ring 3 (User Mode)
                    │
              /sbin/init 開始執行
                    │
              啟動各種系統服務
                    │
              啟動 Agent main.py
```

從此刻起：
- **Ring 0** 只有 kernel 在跑
- **Ring 3** 的程式要做任何特權操作，都必須透過 **System Call** 請 kernel 幫忙
- 這就是 Linux 安全模型的基礎

---

## 🔑 關鍵概念回顧

| 概念 | 說明 |
|------|------|
| start_kernel() | Linux kernel 的 C 語言起點（init/main.c） |
| setup_arch() | 架構相關初始化（CPU、記憶體、ACPI） |
| sched_init() | 排程器初始化（從此可以排程行程） |
| rest_init() | 建立 PID 1 和 PID 2 |
| PID 0 | idle 行程（start_kernel 的執行緒） |
| PID 1 | init 行程（User Space 的始祖） |
| PID 2 | kthreadd（kernel thread 管家） |
| kernel_execve() | 把 PID 1 從 kernel 切換到 /sbin/init |

---

## ⏭️ 下一步

PID 1 執行了 `/sbin/init`，進入了 User Space。但 `/sbin/init` 又做了什麼？它怎麼啟動你的 Agent？

從 /sbin/init 到 Agent → [08_USERSPACE.md](08_USERSPACE.md)
