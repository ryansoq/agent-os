# Ch03 實驗：Main — 觀察 kernel 初始化順序

## 實驗 1：在 main() 加 cprintf 看初始化流程

套 patch 後，每個 init 函式前後都會印訊息，你可以看到 xv6 的啟動順序。

### 操作步驟

```bash
cd ~/xv6-public

# 備份
cp main.c main.c.bak

# 套 patch
patch -p1 < ~/agentos-builder/docs/xv6/examples/ch03-main/initlog.patch

# 編譯 + 跑
make clean && make qemu-nox CPUS=1
# Ctrl-A X 退出
```

你會看到：
```
[main] kinit1...
[main] kinit1 done
[main] kvmalloc...
[main] kvmalloc done
[main] mpinit...
...
[main] userinit...
[main] userinit done
[main] starting scheduler
```

## 實驗 2：調換初始化順序 → Crash！

把 `kvmalloc()` 移到 `kinit1()` 前面：

```bash
patch -p1 < ~/agentos-builder/docs/xv6/examples/ch03-main/swap-init.patch
make clean && make qemu-nox CPUS=1
```

💥 Crash！因為 `kvmalloc()` 需要分配記憶體，但 `kinit1()` 還沒初始化記憶體分配器。

**教訓：** 初始化順序不是隨便排的，每個 init 都依賴前面的結果。

## 實驗 3：觀察第一個 user process

```bash
cd ~/xv6-public
grep -n 'userinit\|initcode\|initproc' proc.c | head -20
```

`userinit()` 手動建立第一個 process，塞入 `initcode.S` 的機器碼，它會 exec("/init")。
