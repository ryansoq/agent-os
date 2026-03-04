// getcounttest.c — 測試自訂 syscall getcount()
#include "types.h"
#include "stat.h"
#include "user.h"

int
main(void)
{
  printf(1, "=== getcount syscall 測試 ===\n");

  int c1 = getcount();
  printf(1, "第一次 getcount: %d\n", c1);

  // 做一些 syscall
  getpid();
  getpid();
  getpid();
  uptime();

  int c2 = getcount();
  printf(1, "做了 4 個 syscall 後: %d\n", c2);
  printf(1, "差值: %d（應該 >= 5，因為 getcount 本身也算）\n", c2 - c1);

  printf(1, "=== 測試完成 ===\n");
  exit();
}
