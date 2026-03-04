// clitest.c — 在 Ring 3 嘗試執行特權指令
// 預期結果：被 kernel 殺掉（General Protection Fault, trap 13）
//
// 用法：在 xv6 shell 裡輸入 clitest
//
// 為什麼會失敗？
//   cli 是特權指令，只有 CPL=0（Ring 0）能執行
//   user 程式的 CPL=3（Ring 3）
//   CPU 觸發 #GP（中斷 13）→ kernel 殺掉行程

#include "types.h"
#include "stat.h"
#include "user.h"

int
main(int argc, char *argv[])
{
  printf(1, "=== CPL/DPL 實驗 1：特權指令 ===\n");
  printf(1, "我現在是 Ring 3 (user mode)\n");
  printf(1, "嘗試執行 cli（關中斷）...\n");
  printf(1, "\n");

  // cli = Clear Interrupt Flag
  // 只有 Ring 0 能執行
  // Ring 3 執行 → #GP (trap 13)
  asm volatile("cli");

  // 這行永遠不會執行到
  printf(1, "你不應該看到這行！如果看到了，權限機制壞了。\n");
  exit();
}
