# Ch07 實作：新增 getcount syscall

## 目標
在 xv6 新增一個 `getcount()` syscall，回傳目前行程呼叫 syscall 的總次數。

## 需要修改的檔案（共 7 個）

### 1. `syscall.h` — 新增 syscall 號碼
```c
// 在最後面加上：
#define SYS_getcount 22
```

### 2. `proc.h` — 在 struct proc 加計數器
```c
// 在 struct proc 裡加：
int syscall_count;
```

### 3. `syscall.c` — 修改分派表 + 計數
```c
// 加 extern 宣告：
extern int sys_getcount(void);

// 在 syscalls[] 陣列加上：
[SYS_getcount] sys_getcount,

// 在 syscall() 函數的 if 分支裡，呼叫前加：
curproc->syscall_count++;
```

### 4. `sysproc.c` — 實現 sys_getcount
```c
int
sys_getcount(void)
{
  return myproc()->syscall_count;
}
```

### 5. `usys.S` — user-space 包裝
```asm
SYSCALL(getcount)
```

### 6. `user.h` — 宣告
```c
int getcount(void);
```

### 7. `Makefile` — 加測試程式
在 `UPROGS` 加上 `_getcounttest\`

## 測試程式

把 `getcounttest.c` 放到 xv6-public 目錄：

```bash
cd ~/xv6-public
cp ~/agentos-builder/docs/xv6/examples/ch07-syscall/getcounttest.c .
# 修改上述 7 個檔案
make clean && make && make qemu-nox
```

在 xv6 shell 裡：
```
$ getcounttest
=== getcount syscall 測試 ===
第一次 getcount: 5
做了 4 個 syscall 後: 10
差值: 5（應該 >= 5，因為 getcount 本身也算）
=== 測試完成 ===
```
