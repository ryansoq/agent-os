# Ch02 實驗：Entry — 觀察分頁啟動

## 實驗 1：移除 identity mapping → Crash！

`entrypgdir` 有兩個 mapping：
- `[0]` = identity map（0x00000000 → 0x00000000）
- `[KERNBASE>>22]` = 高位 map（0x80000000 → 0x00000000）

如果把 identity map 拿掉，開啟分頁的瞬間 CPU 就找不到下一條指令了。

### 操作步驟

```bash
cd ~/xv6-public

# 備份
cp main.c main.c.bak

# 套 patch
patch -p1 < ~/agentos-builder/docs/xv6/examples/ch02-entry/no-identity-map.patch

# 編譯 + 跑（會 crash！）
make clean && make qemu-nox CPUS=1

# 還原
cp main.c.bak main.c
```

你會看到 QEMU 直接卡住或 triple fault 重啟 → 因為 CPU 在低位地址執行，但分頁表沒有低位映射了。

## 實驗 2：觀察 V2P / P2V 巨集

```bash
cd ~/xv6-public
grep -n 'define V2P\|define P2V\|define KERNBASE' memlayout.h
```

**思考題：** 如果 KERNBASE 改成 0x40000000，哪些東西要跟著改？
