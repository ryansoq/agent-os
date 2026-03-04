// hello.c — 一個自訂 xv6 命令
#include "types.h"
#include "stat.h"
#include "user.h"

int
main(int argc, char *argv[])
{
  printf(1, "Hello from xv6!\n");
  printf(1, "My PID is %d\n", getpid());
  printf(1, "Uptime: %d ticks\n", uptime());

  if(argc > 1){
    printf(1, "You said: ");
    int i;
    for(i = 1; i < argc; i++)
      printf(1, "%s ", argv[i]);
    printf(1, "\n");
  }

  exit();
}
