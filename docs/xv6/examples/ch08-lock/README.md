# Ch08 實作：移除 lock 觀察 race condition

## 實驗 1：移除 tickslock

### 步驟

1. 修改 `trap.c`，在 `T_IRQ0 + IRQ_TIMER` 分支移除 tickslock：

```c
// 原本：
case T_IRQ0 + IRQ_TIMER:
    if(cpuid() == 0){
      acquire(&tickslock);
      ticks++;
      wakeup(&ticks);
      release(&tickslock);
    }

// 改成（移除鎖）：
case T_IRQ0 + IRQ_TIMER:
    if(cpuid() == 0){
      // acquire(&tickslock);  // 故意移除
      ticks++;
      wakeup(&ticks);
      // release(&tickslock);  // 故意移除
    }
```

2. 用 4 個 CPU 編譯執行：

```bash
cd ~/xv6-public
make clean && make && make qemu-nox CPUS=4
```

3. 在 xv6 shell 裡測試 sleep 的準確性：

```
$ sleep 10
# 觀察是否真的等了 10 個 tick
# 可能會不準確或偶爾 hang
```

### 觀察
- 多 CPU 同時讀寫 `ticks` 但沒有鎖保護
- 可能出現 lost update（兩個 CPU 同時 ticks++，結果只加了 1）
- `sleep` 等待的 tick 數可能不準確

## 實驗 2：移除 ptable.lock（危險！）

⚠️ 這個實驗很可能導致 kernel panic，僅供觀察。

修改 `proc.c` 的 `scheduler()`，移除 `acquire(&ptable.lock)` 和 `release(&ptable.lock)`。

用 CPUS=4 啟動，觀察：
- 可能多個 CPU 同時 switch 到同一個行程
- 隨機 panic
- 記憶體損壞

**結論：鎖是不可或缺的！**
