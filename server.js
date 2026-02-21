// server.js - Agent OS Builder 後端伺服器
const express = require('express');
const http = require('http');
const { WebSocketServer } = require('ws');
const path = require('path');

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

// 靜態檔案服務
app.use(express.static(path.join(__dirname, 'public')));

// 模擬編譯的假 log 資料
function getBuildLogs(packages) {
  const logs = [];
  
  // 初始化階段
  logs.push({ text: '\x1b[1;36m╔══════════════════════════════════════════╗\x1b[0m', delay: 0 });
  logs.push({ text: '\x1b[1;36m║     Agent OS Builder v0.1.0              ║\x1b[0m', delay: 50 });
  logs.push({ text: '\x1b[1;36m╚══════════════════════════════════════════╝\x1b[0m', delay: 50 });
  logs.push({ text: '', delay: 100 });
  logs.push({ text: '\x1b[33m[*] 初始化建構環境...\x1b[0m', delay: 300 });
  logs.push({ text: '\x1b[32m[✓] 交叉編譯工具鏈就緒 (x86_64-linux-musl)\x1b[0m', delay: 500 });
  logs.push({ text: '\x1b[32m[✓] 建構根目錄已建立: /tmp/agentos-rootfs\x1b[0m', delay: 200 });
  logs.push({ text: '', delay: 100 });

  // Linux 核心
  logs.push({ text: '\x1b[1;35m━━━ 階段 1/3: 編譯 Linux 核心 ━━━\x1b[0m', delay: 400 });
  logs.push({ text: '\x1b[33m[*] 下載 linux-6.6.10.tar.xz...\x1b[0m', delay: 300 });
  logs.push({ text: '    Downloading... ████████████████████ 100% (136MB)', delay: 800 });
  logs.push({ text: '\x1b[33m[*] 解壓縮核心原始碼...\x1b[0m', delay: 400 });
  logs.push({ text: '\x1b[33m[*] make defconfig\x1b[0m', delay: 300 });
  logs.push({ text: '    HOSTCC  scripts/basic/fixdep', delay: 100 });
  logs.push({ text: '    HOSTCC  scripts/kconfig/conf.o', delay: 100 });
  logs.push({ text: '    HOSTLD  scripts/kconfig/conf', delay: 100 });
  logs.push({ text: '\x1b[33m[*] make -j$(nproc) bzImage\x1b[0m', delay: 200 });
  for (let i = 0; i < 8; i++) {
    const modules = ['kernel/sched/core.c', 'mm/memory.c', 'fs/ext4/super.c', 'net/ipv4/tcp.c', 
                      'drivers/tty/vt/vt.c', 'kernel/fork.c', 'fs/proc/base.c', 'net/core/dev.c'];
    logs.push({ text: `    CC      ${modules[i]}`, delay: 150 + Math.random() * 200 });
  }
  logs.push({ text: '    LD      vmlinux', delay: 300 });
  logs.push({ text: '    OBJCOPY arch/x86/boot/bzImage', delay: 200 });
  logs.push({ text: '\x1b[32m[✓] 核心編譯完成 (bzImage: 4.2MB)\x1b[0m', delay: 300 });
  logs.push({ text: '', delay: 100 });

  // 套件編譯
  logs.push({ text: '\x1b[1;35m━━━ 階段 2/3: 編譯使用者空間套件 ━━━\x1b[0m', delay: 400 });
  
  const packageInfo = {
    'busybox': { name: 'BusyBox 1.36.1', size: '2.1MB', time: 600 },
    'coreutils': { name: 'GNU coreutils 9.4', size: '8.5MB', time: 800 },
    'util-linux': { name: 'util-linux 2.39', size: '5.2MB', time: 700 },
    'curl': { name: 'curl 8.5.0', size: '3.8MB', time: 500 },
    'wget': { name: 'GNU Wget 1.21', size: '2.9MB', time: 400 },
    'openssl': { name: 'OpenSSL 3.2.0', size: '12.1MB', time: 1000 },
    'dhcpcd': { name: 'dhcpcd 10.0.4', size: '0.8MB', time: 300 },
    'openssh': { name: 'OpenSSH 9.6p1', size: '4.5MB', time: 600 },
    'iptables': { name: 'iptables 1.8.10', size: '1.2MB', time: 400 },
    'python3': { name: 'Python 3.12.1', size: '45.2MB', time: 1500 },
    'nodejs': { name: 'Node.js 20.11 (slim)', size: '32.8MB', time: 1200 },
    'ruby': { name: 'Ruby 3.3.0', size: '28.4MB', time: 1100 },
    'lua': { name: 'Lua 5.4.6', size: '0.5MB', time: 200 },
    'vim': { name: 'Vim 9.1', size: '11.3MB', time: 700 },
    'nano': { name: 'GNU nano 7.2', size: '2.1MB', time: 300 },
    'htop': { name: 'htop 3.3.0', size: '0.4MB', time: 200 },
    'strace': { name: 'strace 6.7', size: '1.8MB', time: 300 },
    'lsof': { name: 'lsof 4.99.3', size: '0.3MB', time: 200 },
    'agent-runtime': { name: 'Agent Runtime (LLM client)', size: '5.6MB', time: 500 },
  };

  let idx = 1;
  const total = packages.length;
  for (const pkg of packages) {
    const info = packageInfo[pkg] || { name: pkg, size: '1.0MB', time: 400 };
    logs.push({ text: `\x1b[33m[${idx}/${total}] 編譯 ${info.name}...\x1b[0m`, delay: 200 });
    logs.push({ text: `    ./configure --prefix=/usr --host=x86_64-linux-musl`, delay: 150 });
    logs.push({ text: `    make -j4`, delay: info.time * 0.6 });
    logs.push({ text: `    make install DESTDIR=/tmp/agentos-rootfs`, delay: info.time * 0.3 });
    logs.push({ text: `\x1b[32m    ✓ ${info.name} 安裝完成 (${info.size})\x1b[0m`, delay: 100 });
    idx++;
  }
  logs.push({ text: '', delay: 100 });

  // 映像檔產生
  logs.push({ text: '\x1b[1;35m━━━ 階段 3/3: 產生磁碟映像 ━━━\x1b[0m', delay: 400 });
  logs.push({ text: '\x1b[33m[*] 建立 ext4 檔案系統...\x1b[0m', delay: 300 });
  logs.push({ text: '    mke2fs -t ext4 -d /tmp/agentos-rootfs rootfs.ext4', delay: 500 });
  logs.push({ text: '\x1b[33m[*] 壓縮映像檔...\x1b[0m', delay: 300 });
  logs.push({ text: '    Compressing... ████████████████████ 100%', delay: 800 });
  logs.push({ text: '', delay: 100 });
  logs.push({ text: '\x1b[1;32m╔══════════════════════════════════════════╗\x1b[0m', delay: 200 });
  logs.push({ text: '\x1b[1;32m║  ✅ Agent OS 建構完成！                  ║\x1b[0m', delay: 100 });
  logs.push({ text: '\x1b[1;32m╚══════════════════════════════════════════╝\x1b[0m', delay: 100 });
  logs.push({ text: '', delay: 100 });
  logs.push({ text: '\x1b[36m映像檔: agentos.img (可用 v86 模擬器啟動)\x1b[0m', delay: 200 });

  return logs;
}

// WebSocket 連線處理
wss.on('connection', (ws) => {
  console.log('WebSocket 用戶端已連線');

  ws.on('message', (data) => {
    try {
      const msg = JSON.parse(data);
      
      if (msg.type === 'build') {
        // 開始模擬編譯
        const packages = msg.packages || ['busybox'];
        const logs = getBuildLogs(packages);
        
        let i = 0;
        function sendNext() {
          if (i >= logs.length || ws.readyState !== 1) return;
          ws.send(JSON.stringify({ type: 'log', text: logs[i].text }));
          const delay = logs[i].delay;
          i++;
          setTimeout(sendNext, delay);
        }
        sendNext();
      }
    } catch (e) {
      console.error('訊息解析錯誤:', e);
    }
  });

  ws.on('close', () => console.log('用戶端已斷線'));
});

// 啟動伺服器
const PORT = 3001;
server.listen(PORT, () => {
  console.log(`🚀 Agent OS Builder 啟動於 http://localhost:${PORT}`);
});
