# Ch10 實作：在 xv6 裡寫自訂命令

## 步驟

### 1. 建立 `hello.c`

把 `hello.c` 複製到 `~/xv6-public/` 目錄。

### 2. 修改 Makefile

在 `UPROGS` 列表加上：
```
_hello\
```

### 3. 編譯執行

```bash
cd ~/xv6-public
make clean && make && make qemu-nox
```

### 4. 測試

```
$ hello
Hello from xv6!
My PID is 3
Uptime: 42 ticks

$ hello world
Hello from xv6!
My PID is 4
Uptime: 55 ticks
You said: world

$ hello | grep PID
My PID is 5

$ hello > out.txt
$ cat out.txt
Hello from xv6!
My PID is 6
Uptime: 80 ticks
```

## 進階練習

1. 試試寫一個 `wc` 的簡化版，計算檔案的行數
2. 寫一個 `echo` 命令（其實 xv6 已經有了，可以看它的實現）
3. 用 `|` 和 `>` 組合你的命令
