# 📚 09 — 檔案系統：從磁碟到 inode

> 「檔案系統 = 圖書館。superblock 是總目錄、inode 是書卡（記錄書放在哪個書架）、data block 是書架上的書。你不需要知道書架在幾樓幾排，只要查書卡就能找到書。」

---

## 📚 比喻：圖書館

```
圖書館 = 整顆磁碟

┌─────────────────────────────────────────────────────┐
│ 門口公告欄    │ 圖書館有多大、幾本書、幾個書架      │ → superblock
├───────────────┼────────────────────────────────────────┤
│ 修改日誌      │ 誰借了什麼、還了什麼（防斷電遺失）   │ → log
├───────────────┼────────────────────────────────────────┤
│ 書卡櫃        │ 每張書卡記錄一本書放在哪些書架       │ → inodes
├───────────────┼────────────────────────────────────────┤
│ 書架使用表    │ 哪些書架空的、哪些在用               │ → bitmap
├───────────────┼────────────────────────────────────────┤
│ 書架區        │ 書的實際內容                         │ → data blocks
└───────────────┴────────────────────────────────────────┘
```

---

## 💾 磁碟 Layout

```
xv6 磁碟佈局（block 大小 = 512 bytes）：

block 0       block 1       block 2...     block N...      block M...     block K...
┌────────┐   ┌────────┐   ┌────────────┐  ┌────────────┐  ┌──────────┐  ┌──────────┐
│  boot  │   │ super  │   │    log     │  │   inode    │  │  bitmap  │  │   data   │
│ block  │   │ block  │   │  blocks    │  │  blocks    │  │  blocks  │  │  blocks  │
│(不用)  │   │(metadata)│ │(journaling)│  │(檔案元資料)│  │(使用狀態)│  │(檔案內容)│
└────────┘   └────────┘   └────────────┘  └────────────┘  └──────────┘  └──────────┘

superblock 記錄各區的起始位置和大小：
  sb.size       → 整個磁碟的 block 數
  sb.nblocks    → data block 數
  sb.ninodes    → inode 數
  sb.nlog       → log block 數
  sb.logstart   → log 區起始 block
  sb.inodestart → inode 區起始 block
  sb.bmapstart  → bitmap 區起始 block
```

---

## 🏗️ 檔案系統層次架構

```
          使用者看到的                kernel 內部
          ─────────                ─────────────

          fd (0,1,2...)
              │
              ↓
          file 結構（file.c）
          記錄 offset、inode 指標、讀寫權限
              │
              ↓
          inode（fs.c）
          記錄檔案類型、大小、data block 位置
              │
              ↓
          log（log.c）
          保證 crash recovery（寫入的原子性）
              │
              ↓
          buffer cache（bio.c）
          記憶體裡的 block 快取（避免重複讀磁碟）
              │
              ↓
          IDE driver（ide.c）
          真正的磁碟 I/O
```

---

## 📄 `fs.h`：磁碟上的資料結構

```c
// fs.h — On-disk 檔案系統格式

#define ROOTINO 1      // root 目錄的 inode 號碼
#define BSIZE 512      // 每個 block 512 bytes

// Superblock：描述整個檔案系統的 metadata
struct superblock {
  uint size;           // 磁碟總 block 數
  uint nblocks;        // data block 數
  uint ninodes;        // inode 數
  uint nlog;           // log block 數
  uint logstart;       // log 區起始 block
  uint inodestart;     // inode 區起始 block
  uint bmapstart;      // bitmap 區起始 block
};

#define NDIRECT 12                      // 12 個直接指標
#define NINDIRECT (BSIZE / sizeof(uint))  // 128 個間接指標
#define MAXFILE (NDIRECT + NINDIRECT)    // 最大 12+128 = 140 個 block
                                          // = 140 * 512 = 71680 bytes

// 磁碟上的 inode 結構（dinode = disk inode）
struct dinode {
  short type;              // 檔案類型：0=空、T_FILE、T_DIR、T_DEV
  short major;             // 裝置的 major 號（T_DEV 才用）
  short minor;             // 裝置的 minor 號
  short nlink;             // 有多少個目錄 entry 指向我
  uint size;               // 檔案大小（bytes）
  uint addrs[NDIRECT+1];   // data block 位址
  //  addrs[0..11] → 直接指標（直接指向 data block）
  //  addrs[12]    → 間接指標（指向一個 block，裡面存 128 個 block 地址）
};

// 目錄 entry
#define DIRSIZ 14
struct dirent {
  ushort inum;             // inode 號碼
  char name[DIRSIZ];      // 檔案名稱（最多 14 字元）
};
```

### inode 的位址結構

```
inode.addrs[] 的示意圖：

addrs[0]  → block 50   ← 直接指標：前 12 個 block
addrs[1]  → block 51      直接存 block 地址
addrs[2]  → block 80      最多 12 個 block = 6KB
...
addrs[11] → block 200

addrs[12] → block 300  ← 間接指標：指向一個「索引 block」
              │
              ↓
            block 300 的內容（128 個 uint）：
            ┌────────────────────────────┐
            │ block 400                   │  ← 第 13 個 data block
            │ block 401                   │  ← 第 14 個
            │ block 500                   │
            │ ...                         │
            │ block 999                   │  ← 最多第 140 個
            └────────────────────────────┘

小檔案（< 6KB）：只用直接指標，快速
大檔案（6KB ~ 70KB）：用間接指標，多讀一次磁碟
```

---

## 📄 `bio.c`：Buffer Cache

Buffer cache 是磁碟 block 在記憶體中的快取，避免每次都讀磁碟。

```c
// bio.c — Buffer Cache（中文註解版精選）

struct {
  struct spinlock lock;       // 保護 cache 結構的 spinlock
  struct buf buf[NBUF];       // NBUF = 30 個 buffer
  struct buf head;            // LRU 鏈表的 head（dummy node）
} bcache;

// bget：取得一個 block 的 buffer（已快取或新分配）
static struct buf*
bget(uint dev, uint blockno)
{
  struct buf *b;

  acquire(&bcache.lock);

  // 1. 在快取裡找有沒有這個 block
  for(b = bcache.head.next; b != &bcache.head; b = b->next){
    if(b->dev == dev && b->blockno == blockno){
      b->refcnt++;               // 找到了！增加引用計數
      release(&bcache.lock);
      acquiresleep(&b->lock);    // 用 sleeplock（可能要等 I/O）
      return b;
    }
  }

  // 2. 沒找到 → 回收一個最久沒用的 buffer（LRU）
  //    從鏈表尾部開始找（尾部 = 最久沒用的）
  for(b = bcache.head.prev; b != &bcache.head; b = b->prev){
    if(b->refcnt == 0 && (b->flags & B_DIRTY) == 0) {
      b->dev = dev;
      b->blockno = blockno;
      b->flags = 0;              // 清除 valid → 之後會從磁碟讀
      b->refcnt = 1;
      release(&bcache.lock);
      acquiresleep(&b->lock);
      return b;
    }
  }
  panic("bget: no buffers");     // 所有 buffer 都在用 → 沒空間了
}

// bread：讀一個 block 到記憶體
struct buf*
bread(uint dev, uint blockno)
{
  struct buf *b;
  b = bget(dev, blockno);        // 取得 buffer
  if((b->flags & B_VALID) == 0) {
    iderw(b);                    // 不在快取裡 → 從磁碟讀
  }
  return b;                      // 回傳已鎖定的 buffer
}

// bwrite：把 buffer 寫回磁碟
void
bwrite(struct buf *b)
{
  if(!holdingsleep(&b->lock))
    panic("bwrite");
  b->flags |= B_DIRTY;
  iderw(b);                      // 送出磁碟寫入
}

// brelse：釋放 buffer（用完了）
void
brelse(struct buf *b)
{
  if(!holdingsleep(&b->lock))
    panic("brelse");

  releasesleep(&b->lock);        // 放 sleeplock

  acquire(&bcache.lock);
  b->refcnt--;
  if (b->refcnt == 0) {
    // 沒人用了 → 移到 LRU 鏈表頭部（最近使用的）
    b->next->prev = b->prev;
    b->prev->next = b->next;
    b->next = bcache.head.next;
    b->prev = &bcache.head;
    bcache.head.next->prev = b;
    bcache.head.next = b;
  }
  release(&bcache.lock);
}
```

```
Buffer Cache 的 LRU 策略：

  head ↔ [最近用] ↔ [次近] ↔ ... ↔ [最久沒用] ↔ head

  bread → 用到 → brelse → 放到頭部
  bget 需要新 buffer → 從尾部找 refcnt==0 的回收

  → 最近用過的留在前面（可能馬上又要用）
  → 最久沒用的先被回收
```

---

## 📄 `log.c`：Crash Recovery（Journaling）

如果寫到一半斷電怎麼辦？

```
問題場景：刪除檔案需要多步驟
  1. 從目錄移除 entry
  2. 釋放 inode
  3. 釋放 data blocks
  4. 更新 bitmap

如果在步驟 2 和 3 之間斷電：
  → inode 被釋放了，但 data blocks 還佔著
  → 磁碟空間泄漏（不一致！）

解法：WAL（Write-Ahead Log）
  不直接修改原始位置，先寫到 log 區
  全部寫完後，再一次性「commit」
  斷電後重開機，看 log：
    log 完整 → 重新執行（install）
    log 不完整 → 丟棄（當作沒發生）
```

```c
// log.c 核心流程（精簡中文註解）

// 開始一個 transaction
void begin_op(void)
{
  acquire(&log.lock);
  while(1){
    if(log.committing){
      sleep(&log, &log.lock);       // 正在 commit → 等
    } else if(log.lh.n + (log.outstanding+1)*MAXOPBLOCKS > LOGSIZE){
      sleep(&log, &log.lock);       // log 空間不夠 → 等
    } else {
      log.outstanding += 1;         // 記錄有人在操作
      release(&log.lock);
      break;
    }
  }
}

// 結束一個 transaction
void end_op(void)
{
  int do_commit = 0;
  acquire(&log.lock);
  log.outstanding -= 1;
  if(log.outstanding == 0){
    do_commit = 1;                 // 最後一個 → 執行 commit！
    log.committing = 1;
  } else {
    wakeup(&log);                  // 還有人在操作 → 喚醒等待者
  }
  release(&log.lock);

  if(do_commit){
    commit();                      // 真正執行 commit
    acquire(&log.lock);
    log.committing = 0;
    wakeup(&log);
    release(&log.lock);
  }
}

// commit 的四步驟
static void commit()
{
  if (log.lh.n > 0) {
    write_log();       // 1. 把修改過的 block 寫到 log 區
    write_head();      // 2. 寫 log header → 🔑 真正的 commit 點！
    install_trans();   // 3. 把 log 的內容複製到原始位置
    log.lh.n = 0;
    write_head();      // 4. 清除 log（n=0）
  }
}
```

```
Commit 的四步驟視覺化：

步驟 1：write_log
  原始區: [ A ][ B ][ C ]（舊的）
  log 區: [ A'][ B'][ C']（新的修改）

步驟 2：write_head（🔑 commit 點！）
  log header: n=3, blocks=[A, B, C]
  → 寫到磁碟 → 如果之後斷電，重開機看到 n=3 → 重新執行

步驟 3：install_trans
  原始區: [ A'][ B'][ C']（更新為新的）

步驟 4：write_head（清除 log）
  log header: n=0
  → 如果現在斷電，重開機看到 n=0 → 不需要恢復

斷電分析：
  步驟 1 之前斷電 → n=0 → 沒事
  步驟 1~2 之間斷電 → n=0（header 還沒寫）→ 丟棄修改
  步驟 2~3 之間斷電 → n=3 → 重新 install → 正確恢復！
  步驟 3~4 之間斷電 → n=3 → 重新 install → 冪等（idempotent）
```

---

## 📄 `fs.c` 精選：inode 操作

### ialloc：分配 inode

```c
// 掃描所有 inode，找到 type==0（空的），分配它
struct inode*
ialloc(uint dev, short type)
{
  int inum;
  struct buf *bp;
  struct dinode *dip;

  for(inum = 1; inum < sb.ninodes; inum++){
    bp = bread(dev, IBLOCK(inum, sb));     // 讀包含此 inode 的 block
    dip = (struct dinode*)bp->data + inum%IPB;  // 定位到具體的 dinode
    if(dip->type == 0){                    // 空的！
      memset(dip, 0, sizeof(*dip));
      dip->type = type;                    // 標記為使用中
      log_write(bp);                       // 透過 log 寫入
      brelse(bp);
      return iget(dev, inum);              // 回傳記憶體中的 inode
    }
    brelse(bp);
  }
  panic("ialloc: no inodes");
}
```

### iget / ilock / iput：記憶體中的 inode cache

```c
// iget：取得 inode 的記憶體引用（不讀磁碟、不鎖定）
static struct inode*
iget(uint dev, uint inum)
{
  struct inode *ip, *empty;
  acquire(&icache.lock);

  // 已經在快取裡？
  empty = 0;
  for(ip = &icache.inode[0]; ip < &icache.inode[NINODE]; ip++){
    if(ip->ref > 0 && ip->dev == dev && ip->inum == inum){
      ip->ref++;              // 找到了，增加引用計數
      release(&icache.lock);
      return ip;
    }
    if(empty == 0 && ip->ref == 0)
      empty = ip;             // 記住一個空 slot
  }

  // 不在快取 → 用空 slot
  ip = empty;
  ip->dev = dev;
  ip->inum = inum;
  ip->ref = 1;
  ip->valid = 0;              // 還沒從磁碟讀（lazy！）
  release(&icache.lock);
  return ip;
}

// ilock：鎖定 inode + 從磁碟讀取（如果還沒讀）
void ilock(struct inode *ip)
{
  acquiresleep(&ip->lock);    // 用 sleeplock（可能要等）

  if(ip->valid == 0){         // 還沒從磁碟讀？
    // 讀磁碟上的 dinode → 填入記憶體的 inode
    struct buf *bp = bread(ip->dev, IBLOCK(ip->inum, sb));
    struct dinode *dip = (struct dinode*)bp->data + ip->inum%IPB;
    ip->type = dip->type;
    ip->major = dip->major;
    ip->minor = dip->minor;
    ip->nlink = dip->nlink;
    ip->size = dip->size;
    memmove(ip->addrs, dip->addrs, sizeof(ip->addrs));
    brelse(bp);
    ip->valid = 1;
  }
}

// iput：減少引用計數，如果歸零且 nlink==0 → 釋放
void iput(struct inode *ip)
{
  acquiresleep(&ip->lock);
  if(ip->valid && ip->nlink == 0){
    // 沒有目錄指向我 + 沒有其他引用 → 可以釋放
    acquire(&icache.lock);
    int r = ip->ref;
    release(&icache.lock);
    if(r == 1){
      itrunc(ip);             // 釋放所有 data blocks
      ip->type = 0;           // 標記為空
      iupdate(ip);            // 寫回磁碟
      ip->valid = 0;
    }
  }
  releasesleep(&ip->lock);

  acquire(&icache.lock);
  ip->ref--;
  release(&icache.lock);
}
```

```
inode 的典型使用模式：

  ip = iget(dev, inum);     // 取得引用（ref++）
  ilock(ip);                // 鎖定 + 從磁碟讀
  ... 讀寫 ip->xxx ...
  iunlock(ip);              // 解鎖
  iput(ip);                 // 釋放引用（ref--）

為什麼 iget 和 ilock 分開？
  → open() 需要長期持有 inode 引用（ref），但不能一直鎖著
  → read() 時才短暫 ilock → 讀完 → iunlock
  → 分離避免 deadlock（如 pathname lookup 時需要鎖兩個 inode）
```

### readi / writei：讀寫 inode 的資料

```c
// readi：從 inode 讀 n bytes（從 offset off 開始）
int readi(struct inode *ip, char *dst, uint off, uint n)
{
  uint tot, m;
  struct buf *bp;

  // 裝置檔？→ 呼叫裝置的 read 函數
  if(ip->type == T_DEV){
    return devsw[ip->major].read(ip, dst, n);
  }

  // 範圍檢查
  if(off > ip->size || off + n < off) return -1;
  if(off + n > ip->size) n = ip->size - off;

  // 一個 block 一個 block 地讀
  for(tot=0; tot<n; tot+=m, off+=m, dst+=m){
    bp = bread(ip->dev, bmap(ip, off/BSIZE));  // bmap → 找到第 N 個 block
    m = min(n - tot, BSIZE - off%BSIZE);       // 這次讀多少
    memmove(dst, bp->data + off%BSIZE, m);     // 複製到 dst
    brelse(bp);
  }
  return n;
}
```

---

## 📁 目錄結構

目錄就是一個特殊的檔案，內容是 `struct dirent` 的陣列：

```
目錄 "/" 的 inode 內容：

offset  │ inum │ name
────────┼──────┼──────────
   0    │  1   │ "."        ← 自己
  16    │  1   │ ".."       ← 父目錄
  32    │  2   │ "console"
  48    │  3   │ "init"
  64    │  4   │ "sh"
  80    │  0   │ ""         ← inum=0 表示空 entry
```

`namei("/init")` 的過程：
1. 從 root inode（inum=1）開始
2. 掃描目錄內容，找到 name="init"
3. 回傳 inum=3 的 inode

---

## 💻【實作】在 xv6 裡觀察 inode

```bash
# 啟動 xv6
cd ~/xv6-public
make && make qemu-nox

# 在 xv6 shell 裡：
$ echo hello > testfile
$ ls
.              1 1 512
..             1 1 512
README         2 2 2286
cat            2 3 13612
...
testfile       2 17 6     ← type=2(file), inum=17, size=6

# 用 cat 確認：
$ cat testfile
hello
```

也可以修改 `ls.c`，印出更多 inode 資訊：

```c
// 在 ls.c 的 printf 加上 nlink 和 addrs[0]
// 就能看到每個檔案的 inode 細節
```

### 用 xxd 觀察磁碟上的 superblock

```bash
# 在 host（不是 xv6 裡），xv6 make 後會產生 fs.img
xxd fs.img | head -10

# block 1 (offset 512) 是 superblock
xxd -s 512 -l 28 fs.img
# 會看到 size, nblocks, ninodes, nlog 等欄位
```

---

## 🧠 本章小結

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  磁碟佈局：                                                  │
│    [boot] [super] [log] [inode] [bitmap] [data]             │
│                                                              │
│  層次架構（由上到下）：                                       │
│    fd → file → inode → log → buffer cache → disk            │
│                                                              │
│  Buffer Cache（bio.c）：                                     │
│    bread/bwrite/brelse                                       │
│    LRU 回收策略                                              │
│    用 sleeplock 保護每個 buffer                               │
│                                                              │
│  Log（log.c）：                                              │
│    begin_op → ... log_write ... → end_op → commit           │
│    WAL：先寫 log，再寫原始位置                                │
│    commit 點 = write_head（n > 0 寫入磁碟的那一刻）          │
│    斷電恢復：看 log header → install 或丟棄                  │
│                                                              │
│  Inode（fs.c）：                                             │
│    dinode（磁碟）↔ inode（記憶體 cache）                     │
│    iget / ilock / iunlock / iput                             │
│    12 個直接指標 + 1 個間接指標 → 最大 ~70KB                 │
│    readi / writei：一個 block 一個 block 地讀寫               │
│                                                              │
│  目錄 = 特殊的 inode，內容是 dirent 陣列                     │
│    dirlookup / dirlink：查找和新增 entry                     │
│    namei / namex：pathname → inode                           │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

**一句話：** 檔案系統把磁碟上的 block 組織成 inode → 目錄 → pathname 的層次結構，用 buffer cache 加速、用 log 保證一致性。

---

## ⏭️ 下一步

有了檔案系統、行程、syscall、排程——現在把這一切串起來：Shell。

→ [10_SHELL.md — Shell：一切串起來](10_SHELL.md)
