// app.js — Agent OS Builder 前端邏輯

// ===== 套件大小資料 =====
const packageSizes = {
  busybox: 2.1, coreutils: 8.5, 'util-linux': 5.2,
  curl: 3.8, wget: 2.9, openssl: 12.1, dhcpcd: 0.8, openssh: 4.5, iptables: 1.2,
  python3: 45.2, nodejs: 32.8, ruby: 28.4, lua: 0.5,
  vim: 11.3, nano: 2.1,
  htop: 0.4, strace: 1.8, lsof: 0.3,
  'agent-runtime': 5.6
};
const KERNEL_SIZE = 4.2; // bzImage 基本大小

// ===== xterm.js 初始化 =====
const buildTerm = new Terminal({
  theme: {
    background: '#000000',
    foreground: '#c8d6e5',
    cursor: '#00e5a0',
    green: '#00e5a0',
    yellow: '#ffa502',
    cyan: '#00b8d4',
    red: '#ff4757',
    magenta: '#a29bfe',
    brightGreen: '#00e5a0',
    brightCyan: '#00b8d4',
  },
  fontSize: 13,
  fontFamily: "'SF Mono', 'Fira Code', 'Consolas', monospace",
  cursorBlink: false,
  disableStdin: true,
  scrollback: 5000,
});
buildTerm.open(document.getElementById('buildTerminal'));
buildTerm.writeln('\x1b[36m[Agent OS Builder] 準備就緒。選擇套件後點擊「🔨 編譯」\x1b[0m');

// ===== WebSocket =====
let ws = null;
let building = false;

function connectWS() {
  // 自動判斷 ws/wss
  const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
  ws = new WebSocket(`${proto}//${location.host}`);
  
  ws.onopen = () => console.log('WebSocket 已連線');
  
  ws.onmessage = (event) => {
    const msg = JSON.parse(event.data);
    if (msg.type === 'log') {
      buildTerm.writeln(msg.text);
    }
    if (msg.type === 'done' || (msg.text && msg.text.includes('建構完成'))) {
      buildDone();
    }
  };
  
  ws.onclose = () => {
    console.log('WebSocket 斷線，3 秒後重連...');
    setTimeout(connectWS, 3000);
  };
}
connectWS();

// ===== 取得勾選的套件 =====
function getSelectedPackages() {
  const checkboxes = document.querySelectorAll('.category input[type="checkbox"]:checked');
  return Array.from(checkboxes).map(cb => cb.value);
}

// ===== 計算並更新大小 =====
function updateSize() {
  const packages = getSelectedPackages();
  let total = KERNEL_SIZE;
  packages.forEach(pkg => { total += packageSizes[pkg] || 1.0; });
  
  document.getElementById('totalSize').textContent = total.toFixed(1);
  
  // 更新進度條（最大 200MB 為滿）
  const pct = Math.min(100, (total / 200) * 100);
  document.getElementById('sizeFill').style.width = pct + '%';
  
  // 顏色變化
  const fill = document.getElementById('sizeFill');
  if (total > 150) {
    fill.style.background = 'linear-gradient(90deg, #ffa502, #ff4757)';
  } else if (total > 80) {
    fill.style.background = 'linear-gradient(90deg, #00e5a0, #ffa502)';
  } else {
    fill.style.background = 'linear-gradient(90deg, #00e5a0, #00b8d4)';
  }
}

// 監聽所有 checkbox
document.querySelectorAll('.category input[type="checkbox"]').forEach(cb => {
  cb.addEventListener('change', updateSize);
});
updateSize(); // 初始計算

// ===== 開始編譯 =====
function startBuild() {
  if (building) return;
  building = true;
  
  const btn = document.getElementById('btnBuild');
  btn.textContent = '⏳ 編譯中...';
  btn.classList.add('building');
  document.getElementById('btnBoot').disabled = true;
  
  buildTerm.clear();
  buildTerm.writeln('\x1b[36m[Agent OS Builder] 開始編譯...\x1b[0m\r\n');
  
  const packages = getSelectedPackages();
  
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify({ type: 'build', packages }));
  }
  
  // 模擬完成的 timeout（依套件數量算）
  const estimatedTime = packages.length * 1500 + 5000;
  setTimeout(() => {
    if (building) buildDone();
  }, estimatedTime);
}

function buildDone() {
  building = false;
  const btn = document.getElementById('btnBuild');
  btn.textContent = '🔨 重新編譯';
  btn.classList.remove('building');
  document.getElementById('btnBoot').disabled = false;
}

// ===== 啟動 VM =====
function bootVM() {
  const vmPlaceholder = document.getElementById('vmPlaceholder');
  const vmScreen = document.getElementById('vmScreen');
  
  vmPlaceholder.style.display = 'none';
  vmScreen.style.display = 'block';
  
  // 用 iframe 載入 copy.sh/v86 作為 demo
  // 未來可以替換成本地 v86 + 自己編譯的 image
  vmScreen.innerHTML = `
    <iframe 
      src="https://copy.sh/v86/?profile=linux26" 
      style="width:100%; height:100%; border:none; border-radius:6px;"
      allow="cross-origin-isolated"
    ></iframe>
  `;
  
  document.getElementById('btnBoot').textContent = '🔄 重新啟動';
}
