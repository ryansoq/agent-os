# 🔧 Agent OS 客製化筆記

> 記錄怎麼改這個 OS 的各種設定。
> 改完要重新注入 rootfs 或重新 `make build`。

---

## 🚪 自動登入（免輸入 root）

### 問題
開機後要在 login 提示輸入 `root` 才能進 shell，麻煩。

### 原因
BusyBox 的 `getty` 負責顯示 login 提示。設定在 `/etc/inittab`：
```
console::respawn:/sbin/getty -L console 0 vt100
```

### 解法
把 `getty` 換成直接啟動 shell：
```
console::respawn:/bin/sh -l
```

`-l` = login shell，會載入 `/etc/profile` 和 `/etc/profile.d/*.sh`（歡迎訊息）。

### 怎麼改

**方法 A：直接改 rootfs（快速，但重新 build 會被覆蓋）**
```bash
sudo mount -o loop images/rootfs.ext2 /mnt
sudo sed -i 's|/sbin/getty.*|/bin/sh -l|' /mnt/etc/inittab
sudo umount /mnt
```

**方法 B：放在 overlay（永久，每次 build 自動套用）**
```bash
# 建立 overlay 裡的 inittab
mkdir -p overlay/etc
cp <buildroot>/output/target/etc/inittab overlay/etc/inittab
# 編輯 overlay/etc/inittab，把 getty 那行改掉
```

然後確保 Buildroot config 有設定 overlay 路徑：
```
BR2_ROOTFS_OVERLAY="$(TOPDIR)/../overlay"
```

### 流程對照

```
改之前：
  Kernel boot → init → inittab → getty → 「login:」 → 輸入 root → shell
                                          ↑ 卡在這裡

改之後：
  Kernel boot → init → inittab → /bin/sh -l → 直接進 shell ✅
```

### 延伸：想要自動登入但還是用 getty（保留登入紀錄）
```
console::respawn:/sbin/getty -n -l /bin/sh -L console 0 vt100
```
- `-n` = 不問帳號
- `-l /bin/sh` = 直接執行 sh

---

## 📂 注入檔案到 rootfs

如果要把程式放進 VM（不重新 build）：

```bash
# 掛載
sudo mount -o loop images/rootfs.ext2 /mnt

# 放檔案
sudo cp my-script.py /mnt/agent/
sudo chmod +x /mnt/agent/my-script.py

# 卸載
sudo umount /mnt
```

⚠️ **QEMU 跑的時候不能 mount！** 要先 `poweroff` VM 或 kill QEMU。

---

## 🔑 Kernel 命令列參數

在 QEMU 啟動時的 `-append` 可以加參數：

| 參數 | 說明 |
|------|------|
| `root=/dev/vda` | rootfs 在哪個裝置 |
| `console=ttyS0` | 輸出到 serial port（`-nographic` 必須） |
| `rw` | rootfs 可讀寫 |
| `quiet` | 減少開機訊息 |
| `loglevel=3` | 只顯示 error 以上的 log |
| `init=/bin/sh` | 跳過 init 直接進 shell（緊急救援用） |

### 最安靜的開機
```bash
-append "root=/dev/vda console=ttyS0 rw quiet loglevel=3"
```

### 緊急救援（init 壞了）
```bash
-append "root=/dev/vda console=ttyS0 rw init=/bin/sh"
```
直接進 shell，不經過 inittab，什麼都沒啟動。

---

## 🌐 VM 網路

QEMU 的 `-net user` 提供 NAT 網路：
- VM 可以連外網（curl、apt）
- 外面連不進 VM（除非設 port forwarding）

```bash
# 在 VM 裡測試網路
ping -c1 google.com

# DHCP（如果沒自動拿到 IP）
dhcpcd eth0
```

### Port Forwarding（讓外面連進 VM）
```bash
-net user,hostfwd=tcp::2222-:22
# 外面 ssh -p 2222 root@localhost → 連進 VM
```

---

*這份筆記會持續更新。有新的客製化方法就加進來。*
