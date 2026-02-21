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

// ===== v0.2 三層編譯 log =====
function getBuildLogsV2(kernel, system, agent) {
  const logs = [];
  const p = (text, delay=100) => logs.push({ text, delay });
  
  p('\x1b[1;36m╔══════════════════════════════════════════╗\x1b[0m', 0);
  p('\x1b[1;36m║     Agent OS Builder v0.2               ║\x1b[0m', 50);
  p('\x1b[1;36m╚══════════════════════════════════════════╝\x1b[0m', 50);
  p('');
  p('\x1b[33m[*] 初始化交叉編譯工具鏈 (x86_64-linux-musl)...\x1b[0m', 300);
  p('\x1b[32m[✓] Toolchain ready\x1b[0m', 500);
  p('');

  // ── Layer 1: Kernel ──
  p('\x1b[1;31m━━━ Layer 1: Kernel 核心 ━━━\x1b[0m', 400);
  p('\x1b[33m[*] 下載 linux-6.6.10.tar.xz...\x1b[0m', 200);
  p('    ████████████████████ 100% (136MB)', 800);
  p('\x1b[33m[*] make x86_64_defconfig\x1b[0m', 200);
  
  const kernelNames = {
    'k:tcp': 'TCP/IP Stack', 'k:dns': 'DNS Resolver', 'k:ipv6': 'IPv6',
    'k:netfilter': 'Netfilter', 'k:wifi': 'WiFi cfg80211', 'k:bluetooth': 'Bluetooth',
    'k:ext4': 'ext4 filesystem', 'k:tmpfs': 'tmpfs/procfs/sysfs',
    'k:fat': 'FAT/vFAT', 'k:ntfs': 'NTFS', 'k:nfs': 'NFS Client', 'k:fuse': 'FUSE',
    'k:vga': 'VGA Console', 'k:fb': 'Framebuffer', 'k:drm': 'DRM/GPU',
    'k:tty': 'TTY/Serial', 'k:virtio': 'VirtIO', 'k:usb': 'USB',
    'k:input': 'Input Devices', 'k:sound': 'ALSA Sound', 'k:camera': 'V4L2 Camera',
    'k:gpio': 'GPIO', 'k:i2c': 'I2C/SPI',
    'k:seccomp': 'Seccomp', 'k:namespaces': 'Namespaces', 'k:cgroups': 'Cgroups',
    'k:selinux': 'SELinux', 'k:crypto': 'Crypto API',
    'k:smp': 'SMP Multi-core', 'k:hugepages': 'Huge Pages'
  };
  
  p('\x1b[33m[*] 配置 Kernel 驅動:\x1b[0m', 200);
  kernel.forEach(k => {
    const name = kernelNames[k] || k;
    const enabled = !['k:bluetooth','k:wifi','k:ntfs','k:selinux','k:drm'].includes(k);
    p(`    CONFIG_${k.replace('k:','').toUpperCase()}=y  \x1b[36m# ${name}\x1b[0m`, 80);
  });
  
  p('');
  p('\x1b[33m[*] make -j16 bzImage\x1b[0m', 200);
  const kernelFiles = ['kernel/sched/core.c','mm/memory.c','fs/ext4/super.c','net/ipv4/tcp.c',
    'drivers/tty/vt/vt.c','kernel/fork.c','net/core/dev.c','crypto/sha256.c'];
  kernelFiles.forEach(f => p(`    CC      ${f}`, 100 + Math.random()*150));
  p('    LD      vmlinux', 300);
  p('    OBJCOPY arch/x86/boot/bzImage', 200);
  p('\x1b[32m[✓] Kernel 編譯完成 (bzImage: 4.2MB)\x1b[0m', 200);
  p('');

  // ── Layer 2: System ──
  p('\x1b[1;33m━━━ Layer 2: System 使用者空間 ━━━\x1b[0m', 400);
  
  const sysInfo = {
    'busybox': { name: 'BusyBox 1.36.1', size: '2.1MB', time: 600 },
    'coreutils': { name: 'GNU coreutils 9.4', size: '8.5MB', time: 800 },
    'util-linux': { name: 'util-linux 2.39', size: '5.2MB', time: 700 },
    'bash': { name: 'Bash 5.2', size: '1.2MB', time: 400 },
    'curl': { name: 'curl 8.5.0 + libcurl', size: '3.8MB', time: 500 },
    'wget': { name: 'GNU Wget 1.21', size: '2.9MB', time: 400 },
    'openssl': { name: 'OpenSSL 3.2.0', size: '12.1MB', time: 1000 },
    'ca-certs': { name: 'CA Certificates', size: '0.2MB', time: 100 },
    'dhcpcd': { name: 'dhcpcd 10.0.4', size: '0.8MB', time: 300 },
    'openssh': { name: 'OpenSSH 9.6p1', size: '4.5MB', time: 600 },
    'iptables': { name: 'iptables 1.8.10', size: '1.2MB', time: 400 },
    'wireguard': { name: 'WireGuard tools', size: '0.5MB', time: 200 },
    'python3': { name: 'Python 3.12.1', size: '45.2MB', time: 1500 },
    'nodejs': { name: 'Node.js 20.11', size: '32.8MB', time: 1200 },
    'ruby': { name: 'Ruby 3.3.0', size: '28.4MB', time: 1100 },
    'lua': { name: 'Lua 5.4.6', size: '0.5MB', time: 200 },
    'go': { name: 'Go 1.22', size: '55.0MB', time: 1500 },
    'vim': { name: 'Vim 9.1', size: '11.3MB', time: 700 },
    'nano': { name: 'GNU nano 7.2', size: '2.1MB', time: 300 },
    'htop': { name: 'htop 3.3.0', size: '0.4MB', time: 200 },
    'strace': { name: 'strace 6.7', size: '1.8MB', time: 300 },
    'lsof': { name: 'lsof 4.99.3', size: '0.3MB', time: 200 },
    'tmux': { name: 'tmux 3.4', size: '0.8MB', time: 300 },
    'git': { name: 'Git 2.43', size: '15.2MB', time: 800 },
    'pip': { name: 'pip 24.0', size: '3.5MB', time: 200 },
  };
  
  let idx = 1;
  system.forEach(pkg => {
    const info = sysInfo[pkg] || { name: pkg, size: '1.0MB', time: 400 };
    p(`\x1b[33m[${idx}/${system.length}] 編譯 ${info.name}...\x1b[0m`, 150);
    p(`    ./configure --host=x86_64-linux-musl`, 100);
    p(`    make -j16`, info.time * 0.5);
    p(`    make install DESTDIR=rootfs`, info.time * 0.3);
    p(`\x1b[32m    ✓ ${info.name} (${info.size})\x1b[0m`, 80);
    idx++;
  });
  p('');

  // ── Layer 3: Agent ──
  p('\x1b[1;32m━━━ Layer 3: Agent 智能層 ━━━\x1b[0m', 400);
  
  const agentNames = {
    'agent-core': '安裝 Agent Core (LLM client)',
    'agent-tools': '安裝 Tool Calling engine',
    'agent-session': '安裝 Session 持久化',
    'agent-compact': '安裝 Context Compact',
    'llm-claude': '配置 Claude (Anthropic) provider',
    'llm-openai': '配置 GPT (OpenAI) provider',
    'llm-gemini': '配置 Gemini (Google) provider',
    'llm-local': '配置 Local LLM (Ollama) provider',
    'agent-http': '安裝 HTTP Server',
    'agent-cron': '安裝 Cron 排程器',
    'agent-ipc': '安裝 Agent IPC 通訊',
    'agent-kaspa': '安裝 Kaspa 錢包',
    'agent-sandbox': '配置 Sandbox 安全模式',
    'agent-audit': '配置 Audit Log',
  };
  
  agent.forEach(a => {
    const name = agentNames[a] || a;
    p(`\x1b[32m    ✓ ${name}\x1b[0m`, 200);
  });
  
  p('');
  p('\x1b[33m[*] 寫入 /agent/main.py\x1b[0m', 200);
  p('\x1b[33m[*] 寫入 /etc/init.d/S99agent\x1b[0m', 150);
  p('');

  // ── 打包 ──
  p('\x1b[1;35m━━━ 產生磁碟映像 ━━━\x1b[0m', 400);
  p('\x1b[33m[*] 複製 overlay 檔案...\x1b[0m', 200);
  p('\x1b[33m[*] 建立 ext4 rootfs...\x1b[0m', 300);
  p('    mke2fs -t ext4 -d rootfs rootfs.ext4', 500);
  p('\x1b[33m[*] 建立 cpio initramfs...\x1b[0m', 200);
  p('    Compressing... ████████████████████ 100%', 800);
  p('');
  p('\x1b[1;32m╔══════════════════════════════════════════╗\x1b[0m', 200);
  p('\x1b[1;32m║  ✅ Agent OS 建構完成！                  ║\x1b[0m', 100);
  p('\x1b[1;32m╚══════════════════════════════════════════╝\x1b[0m', 100);
  p('');
  p(`\x1b[36m  Kernel 驅動:  ${kernel.length} 項\x1b[0m`, 100);
  p(`\x1b[36m  System 工具:  ${system.length} 項\x1b[0m`, 100);
  p(`\x1b[36m  Agent 元件:   ${agent.length} 項\x1b[0m`, 100);
  p('');
  p('\x1b[36m  output/images/bzImage       — Kernel\x1b[0m', 100);
  p('\x1b[36m  output/images/rootfs.ext4   — Disk image\x1b[0m', 100);
  p('\x1b[36m  output/images/rootfs.cpio.gz — RAM image\x1b[0m', 100);
  p('');
  p('\x1b[33m  啟動: qemu-system-x86_64 -kernel bzImage -initrd rootfs.cpio.gz -nographic -m 512M\x1b[0m', 100);

  return logs;
}

// ===== v0.1 舊版（保留相容）=====
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
        const kernel = msg.kernel || [];
        const system = msg.system || [];
        const agent = msg.agent || [];
        const logs = getBuildLogsV2(kernel, system, agent);
        
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
