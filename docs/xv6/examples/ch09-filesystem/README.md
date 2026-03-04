# Ch09 實作：觀察 xv6 檔案系統結構

## 實驗 1：在 xv6 裡建檔案觀察

```bash
cd ~/xv6-public
make && make qemu-nox
```

在 xv6 shell 裡：

```
$ echo hello world > test.txt
$ ls
.              1 1 512
..             1 1 512
README         2 2 2286
...
test.txt       2 17 12

# 格式：名稱  type  inum  size
# type 1 = 目錄, type 2 = 一般檔案
# inum = inode 號碼
# size = 檔案大小(bytes)

$ cat test.txt
hello world

$ mkdir mydir
$ ls mydir
.              1 18 32
..             1 1 512
```

## 實驗 2：用 xxd 觀察 fs.img 的 superblock

在 host 上（不是 xv6 裡）：

```bash
cd ~/xv6-public
make fs.img

# 看 superblock（block 1, offset 512）
xxd -s 512 -l 28 fs.img
```

你會看到 7 個 uint32（每個 4 bytes）：
- size: 磁碟總 block 數
- nblocks: data block 數
- ninodes: inode 數
- nlog: log block 數
- logstart: log 起始 block
- inodestart: inode 起始 block
- bmapstart: bitmap 起始 block

## 實驗 3：觀察 inode 結構

```bash
# inode 區從 inodestart 開始
# 假設 inodestart = 32，每個 dinode = 64 bytes
# root inode (inum=1) 在 offset = 32*512 + 1*64

python3 -c "
import struct
with open('fs.img', 'rb') as f:
    # 讀 superblock
    f.seek(512)
    sb = struct.unpack('7I', f.read(28))
    print(f'size={sb[0]}, nblocks={sb[1]}, ninodes={sb[2]}')
    print(f'nlog={sb[3]}, logstart={sb[4]}, inodestart={sb[5]}, bmapstart={sb[6]}')
    
    # 讀 root inode (inum=1)
    inode_offset = sb[5] * 512 + 1 * 64  # dinode size = 64
    f.seek(inode_offset)
    inode = struct.unpack('4h I 13I', f.read(64))
    print(f'\\nRoot inode:')
    print(f'  type={inode[0]}, major={inode[1]}, minor={inode[2]}, nlink={inode[3]}')
    print(f'  size={inode[4]}')
    print(f'  addrs={inode[5:17]}')
    print(f'  indirect={inode[17]}')
"
```
