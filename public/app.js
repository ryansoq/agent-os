// app.js — Agent OS Builder v0.2
// 三層架構：Kernel → System → Agent

// ===== Profiles（快速選擇預設值）=====
const PROFILES = {
  vm: {
    name: '🤖 VM Agent',
    desc: '最小 VM 配置，跑在 QEMU/v86',
    kernel: ['k:tcp','k:dns','k:ext4','k:tmpfs','k:tty','k:virtio','k:seccomp','k:namespaces','k:crypto','k:smp'],
    system: ['busybox','curl','openssl','ca-certs','dhcpcd','python3'],
    agent: ['agent-core','agent-tools','llm-claude','agent-sandbox']
  },
  pi: {
    name: '🏠 Pi Agent',
    desc: 'Raspberry Pi 實體機',
    kernel: ['k:tcp','k:dns','k:ipv6','k:ext4','k:tmpfs','k:tty','k:wifi','k:usb','k:input','k:gpio','k:i2c','k:seccomp','k:namespaces','k:crypto','k:smp'],
    system: ['busybox','curl','openssl','ca-certs','dhcpcd','openssh','python3','pip','nano','htop'],
    agent: ['agent-core','agent-tools','agent-session','agent-cron','llm-claude','agent-sandbox','agent-audit']
  },
  full: {
    name: '🖥️ 完整版',
    desc: '完整開發環境',
    kernel: ['k:tcp','k:dns','k:ipv6','k:netfilter','k:ext4','k:tmpfs','k:fat','k:fuse','k:vga','k:fb','k:tty','k:virtio','k:usb','k:input','k:sound','k:seccomp','k:namespaces','k:cgroups','k:crypto','k:smp'],
    system: ['busybox','coreutils','bash','curl','wget','openssl','ca-certs','dhcpcd','openssh','python3','pip','nodejs','vim','htop','strace','lsof','tmux','git'],
    agent: ['agent-core','agent-tools','agent-session','agent-compact','llm-claude','llm-openai','llm-gemini','agent-http','agent-cron','agent-ipc','agent-kaspa','agent-sandbox','agent-audit']
  },
  minimal: {
    name: '💀 極簡',
    desc: '能跑就好（~10MB）',
    kernel: ['k:tcp','k:dns','k:ext4','k:tmpfs','k:tty','k:crypto','k:smp'],
    system: ['busybox','openssl','ca-certs','dhcpcd'],
    agent: ['agent-core','llm-claude']
  }
};

const KERNEL_BASE = 4.2; // bzImage 最小大小

// ===== Layer 切換 =====
function switchLayer(layer) {
  document.querySelectorAll('.layer-content').forEach(el => el.classList.remove('active'));
  document.querySelectorAll('.tab').forEach(el => el.classList.remove('active'));
  document.getElementById(`layer-${layer}`).classList.add('active');
  // 找對應 tab
  const tabs = document.querySelectorAll('.tab');
  const idx = {kernel:0, system:1, agent:2}[layer];
  tabs[idx].classList.add('active');
}

// ===== Profile 載入 =====
function loadProfile(name) {
  const profile = PROFILES[name];
  if (!profile) return;
  
  // 更新 button 狀態
  document.querySelectorAll('.profile-btn').forEach(btn => btn.classList.remove('active'));
  event.target.classList.add('active');
  
  // 取消所有非必要的 checkbox
  document.querySelectorAll('input[data-id]').forEach(cb => {
    if (!cb.disabled) cb.checked = false;
  });
  
  // 勾選 profile 指定的
  const allIds = [...profile.kernel, ...profile.system, ...profile.agent];
  allIds.forEach(id => {
    const cb = document.querySelector(`input[data-id="${id}"]`);
    if (cb && !cb.disabled) cb.checked = true;
  });
  
  updateSize();
}

// ===== 計算大小 =====
function updateSize() {
  let kernelSize = KERNEL_BASE;
  let systemSize = 0;
  let agentSize = 0;
  
  document.querySelectorAll('input[data-id]:checked').forEach(cb => {
    const size = parseFloat(cb.dataset.size) || 0;
    const layer = cb.dataset.layer;
    if (layer === 'kernel') kernelSize += size;
    else if (layer === 'system') systemSize += size;
    else if (layer === 'agent') agentSize += size;
  });
  
  const total = kernelSize + systemSize + agentSize;
  document.getElementById('totalSize').textContent = total.toFixed(1);
  document.getElementById('sizeDetail').textContent = 
    `Kernel: ${kernelSize.toFixed(1)}MB | System: ${systemSize.toFixed(1)}MB | Agent: ${agentSize.toFixed(1)}MB`;
  
  const pct = Math.min(100, (total / 200) * 100);
  const fill = document.getElementById('sizeFill');
  fill.style.width = pct + '%';
  
  if (total > 150) fill.style.background = 'linear-gradient(90deg, #ff6b6b, #ffa502, #ff4757)';
  else if (total > 80) fill.style.background = 'linear-gradient(90deg, #ff6b6b, #ffa502, #00e5a0)';
  else fill.style.background = 'linear-gradient(90deg, #ff6b6b, #ffa502, #00e5a0)';
}

// 監聽 checkbox 變化
document.querySelectorAll('input[data-id]').forEach(cb => {
  cb.addEventListener('change', () => {
    // 清除 active profile
    document.querySelectorAll('.profile-btn').forEach(btn => btn.classList.remove('active'));
    updateSize();
  });
});
updateSize();

// ===== xterm.js =====
const buildTerm = new Terminal({
  theme: { background: '#000', foreground: '#c8d6e5', cursor: '#00e5a0' },
  fontSize: 13,
  fontFamily: "'SF Mono', 'Fira Code', 'Consolas', monospace",
  cursorBlink: false,
  disableStdin: true,
  scrollback: 5000,
});
buildTerm.open(document.getElementById('buildTerminal'));
buildTerm.writeln('\x1b[36m[Agent OS Builder] 選好三層套件後點擊「🔨 編譯」\x1b[0m');

// ===== WebSocket =====
let ws = null;
let building = false;

function connectWS() {
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  ws = new WebSocket(`${proto}//${location.host}`);
  ws.onopen = () => console.log('WS connected');
  ws.onmessage = (e) => {
    const msg = JSON.parse(e.data);
    if (msg.type === 'log') buildTerm.writeln(msg.text);
    if (msg.text && msg.text.includes('建構完成')) buildDone();
    // VM output → vmTerm
    if (msg.type === 'vm-output' && vmTerm) vmTerm.write(msg.text);
    if (msg.type === 'vm-exit') {
      if (vmTerm) vmTerm.writeln('\r\n\x1b[31m[VM 已關機]\x1b[0m');
      vmRunning = false;
      document.getElementById('btnBoot').textContent = '🚀 啟動 VM';
    }
  };
  ws.onclose = () => setTimeout(connectWS, 3000);
}
connectWS();

// ===== 取得所有選擇 =====
function getSelections() {
  const result = { kernel: [], system: [], agent: [] };
  document.querySelectorAll('input[data-id]:checked').forEach(cb => {
    result[cb.dataset.layer].push(cb.dataset.id);
  });
  return result;
}

// ===== 編譯 =====
function startBuild() {
  if (building) return;
  building = true;
  
  const btn = document.getElementById('btnBuild');
  btn.textContent = '⏳ 編譯中...';
  btn.classList.add('building');
  document.getElementById('btnBoot').disabled = true;
  
  buildTerm.clear();
  
  const sel = getSelections();
  buildTerm.writeln('\x1b[1;36m╔══════════════════════════════════════════╗\x1b[0m');
  buildTerm.writeln('\x1b[1;36m║     Agent OS Builder v0.2               ║\x1b[0m');
  buildTerm.writeln('\x1b[1;36m╚══════════════════════════════════════════╝\x1b[0m');
  buildTerm.writeln('');
  buildTerm.writeln(`\x1b[33m[*] Kernel 驅動: ${sel.kernel.length} 項\x1b[0m`);
  buildTerm.writeln(`\x1b[33m[*] System 工具: ${sel.system.length} 項\x1b[0m`);
  buildTerm.writeln(`\x1b[33m[*] Agent 元件:  ${sel.agent.length} 項\x1b[0m`);
  buildTerm.writeln('');
  
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'build', ...sel }));
  }
  
  const totalPkgs = sel.kernel.length + sel.system.length + sel.agent.length;
  setTimeout(() => { if (building) buildDone(); }, totalPkgs * 1200 + 8000);
}

function buildDone() {
  building = false;
  const btn = document.getElementById('btnBuild');
  btn.textContent = '🔨 重新編譯';
  btn.classList.remove('building');
  document.getElementById('btnBoot').disabled = false;
}

// ===== VM Terminal (QEMU via WebSocket) =====
let vmTerm = null;
let vmRunning = false;

function bootVM() {
  const ph = document.getElementById('vmPlaceholder');
  const vs = document.getElementById('vmScreen');
  ph.style.display = 'none';
  vs.style.display = 'block';
  
  if (!vmTerm) {
    vs.innerHTML = '<div id="vmTerminal" style="width:100%;height:100%"></div>';
    vmTerm = new Terminal({
      theme: { background: '#1a1a2e', foreground: '#e0e0e0', cursor: '#00e5a0' },
      fontSize: 13,
      fontFamily: "'SF Mono', 'Fira Code', 'Consolas', monospace",
      cursorBlink: true,
      scrollback: 5000,
    });
    vmTerm.open(document.getElementById('vmTerminal'));
    
    // 鍵盤輸入 → WebSocket → QEMU stdin
    vmTerm.onData((data) => {
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: 'vm-input', text: data }));
      }
    });
  } else {
    vmTerm.clear();
  }
  
  // 如果已經在跑，先停
  if (vmRunning && ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'vm-stop' }));
    setTimeout(() => {
      ws.send(JSON.stringify({ type: 'vm-start' }));
    }, 1000);
  } else if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'vm-start' }));
  }
  
  vmRunning = true;
  document.getElementById('btnBoot').textContent = '🔄 重新啟動';
  document.getElementById('vmInputBar').style.display = 'flex';
}

// 手機輸入框 → QEMU
function sendVmInput() {
  const input = document.getElementById('vmInput');
  const text = input.value;
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'vm-input', text: text + '\n' }));
  }
  if (vmTerm) vmTerm.write(text + '\r\n');
  input.value = '';
  input.focus();
}

// ===== 匯出設定 =====
function exportConfig() {
  const sel = getSelections();
  let config = `# Agent OS defconfig\n# Generated by Agent OS Builder\n# ${new Date().toISOString()}\n\n`;
  
  config += `# ═══ Layer 1: Kernel ═══\n`;
  sel.kernel.forEach(k => config += `# ${k}\n`);
  config += `\n# ═══ Layer 2: System ═══\n`;
  sel.system.forEach(s => config += `BR2_PACKAGE_${s.toUpperCase().replace(/-/g,'_')}=y\n`);
  config += `\n# ═══ Layer 3: Agent ═══\n`;
  sel.agent.forEach(a => config += `# ${a}\n`);
  
  // 複製到剪貼簿
  navigator.clipboard.writeText(config).then(() => {
    alert('✅ 設定已複製到剪貼簿！');
  }).catch(() => {
    // fallback: 顯示在 terminal
    buildTerm.clear();
    config.split('\n').forEach(line => buildTerm.writeln(line));
  });
}
