# Mini-Agent 🤖

輕量級 AI 聊天介面，基於 [pi-mono](https://github.com/nicepkg/pi-mono) 的 Web UI 套件。

🔗 **線上體驗**: https://agentos.openclaw-alpha.com/mini-agent/

## 功能

- 💬 即時 AI 聊天（預設 Groq Llama 3.3 70B，免費）
- 📝 Session 管理（自動儲存對話到 IndexedDB）
- 🔑 API Key 管理（支援多家 LLM Provider）
- 🌓 深色/淺色主題切換
- 🔄 可切換不同模型

## 技術架構

- **前端**: Vite + TypeScript + Lit Web Components
- **UI 套件**: `@mariozechner/pi-web-ui`（ChatPanel, SessionList, Settings）
- **AI 核心**: `@mariozechner/pi-agent-core` + `@mariozechner/pi-ai`
- **LLM**: Groq API（免費額度）
- **部署**: Express 靜態檔 + Cloudflare Tunnel

## 開發

```bash
cd mini-agent
npm install
npx vite build
```

Build 完成後 `dist/` 資料夾由 Express server 靜態服務。

## 設定

點右上角 ⚙️ 可以：
- 設定不同 Provider 的 API Key
- 切換模型
- 設定 Proxy

## 已知限制

- Groq 免費版有 rate limit（12,000 TPM）
- pi-web-ui light DOM 模式有渲染 bug，已在 `main.ts` 加 workaround
