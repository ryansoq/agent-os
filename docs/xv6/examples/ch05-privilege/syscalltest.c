// syscalltest.c — 透過 syscall 正確請求 kernel 服務
// 預期結果：成功取得 PID
//
// 用法：在 xv6 shell 裡輸入 syscalltest
//
// 為什麼會成功？
//   getpid() 內部用 int $0x40 觸發中斷 64
//   IDT[64].DPL = 3 → user mode (CPL=3) 可以觸發
//   CPU 自動切到 Ring 0 → kernel 處理 → iret 回 Ring 3

#include "types.h"
#include "stat.h"
#include "user.h"

int
main(int argc, char *argv[])
{
  printf(1, "=== CPL/DPL 實驗 2：系統呼叫 ===\n");
  printf(1, "我現在是 Ring 3 (user mode)\n");
  printf(1, "透過 syscall 請 kernel 幫忙...\n");
  printf(1, "\n");

  // getpid() 展開成：
  //   mov $SYS_getpid, %eax    # syscall 號碼
  //   int $0x40                 # 觸發中斷 64
  //   ret
  //
  // CPU 權限檢查：
  //   CPL = 3（我是 user）
  //   IDT[64].DPL = 3（這個 gate 允許 Ring 3）
  //   3 <= 3 → ✅ 通過！
  //
  // 然後 CPU：
  //   1. 從 TSS 取 Ring 0 的 SS:ESP（切 stack）
  //   2. Push old SS, ESP, EFLAGS, CS, EIP
  //   3. CS = 0x08（kernel code）→ CPL = 0
  //   4. 跳到 vector64 → alltraps → trap() → syscall()
  int pid = getpid();

  printf(1, "成功！我的 PID = %d\n", pid);
  printf(1, "\n");
  printf(1, "流程：\n");
  printf(1, "  Ring 3 → int $0x40 → Ring 0 (kernel)\n");
  printf(1, "  kernel 處理完 → iret → Ring 3 (回到我)\n");
  printf(1, "\n");

  // 再試一個：fork + wait
  printf(1, "再試 fork()...\n");
  int child = fork();
  if (child == 0) {
    printf(1, "  子行程 PID=%d：我也是 Ring 3，用 syscall 才能做事\n", getpid());
    exit();
  } else {
    wait();
    printf(1, "  父行程 PID=%d：子行程結束了\n", pid);
  }

  printf(1, "\n結論：Ring 3 不能直接碰硬體，但 syscall 讓 kernel 幫你做 ✅\n");
  exit();
}
