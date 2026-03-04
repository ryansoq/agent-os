// ptetest.c — 展示頁表保護的威力
// 在 Ring 3 嘗試存取 kernel 記憶體 → Page Fault → 被殺掉
//
// 加到 xv6 的步驟：
//   1. 複製到 ~/xv6-public/ptetest.c
//   2. 在 Makefile 的 UPROGS 加上 _ptetest\
//   3. make clean && make && make qemu-nox CPUS=1
//   4. 在 xv6 shell 裡輸入 ptetest

#include "types.h"
#include "stat.h"
#include "user.h"

int
main(int argc, char *argv[])
{
  printf(1, "=== 頁表保護測試 ===\n\n");
  printf(1, "我是 user 程式 (Ring 3)\n");
  printf(1, "嘗試讀取 kernel 記憶體 0x80000000...\n");

  // kernel 記憶體的 PTE_U = 0 → user 不能存取
  char *kernel_addr = (char*)0x80000000;
  char c = *kernel_addr;  // 💥 Page Fault (trap 14)!

  // 不會執行到這裡
  printf(1, "讀到: %d（你不應該看到這行）\n", c);
  exit();
}
