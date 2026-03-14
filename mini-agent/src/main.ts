import "@mariozechner/mini-lit/dist/ThemeToggle.js";
import { Agent, type AgentMessage } from "@mariozechner/pi-agent-core";
import { getModel } from "@mariozechner/pi-ai";
import {
	type AgentState,
	ApiKeyPromptDialog,
	AppStorage,
	ChatPanel,
	CustomProvidersStore,
	createJavaScriptReplTool,
	IndexedDBStorageBackend,
	ProviderKeysStore,
	ProvidersModelsTab,
	ProxyTab,
	SessionListDialog,
	SessionsStore,
	SettingsDialog,
	SettingsStore,
	setAppStorage,
} from "@mariozechner/pi-web-ui";
import { html, render } from "lit";
import { History, Plus, Settings } from "lucide";
import "./app.css";
import { icon } from "@mariozechner/mini-lit";
import { Button } from "@mariozechner/mini-lit/dist/Button.js";

// ============================================================================
// STORAGE SETUP
// ============================================================================
const settings = new SettingsStore();
const providerKeys = new ProviderKeysStore();
const sessions = new SessionsStore();
const customProviders = new CustomProvidersStore();

const backend = new IndexedDBStorageBackend({
	dbName: "mini-agent",
	version: 3,
	stores: [
		settings.getConfig(),
		SessionsStore.getMetadataConfig(),
		providerKeys.getConfig(),
		customProviders.getConfig(),
		sessions.getConfig(),
	],
});

settings.setBackend(backend);
providerKeys.setBackend(backend);
customProviders.setBackend(backend);
sessions.setBackend(backend);

const storage = new AppStorage(settings, providerKeys, sessions, customProviders, backend);
setAppStorage(storage);

// Force DB init eagerly & pre-fill Groq key
(async () => {
	try {
		// Trigger getDB to ensure stores are created
		const db = await (backend as any).getDB();
		console.log("[mini-agent] DB ready, stores:", Array.from(db.objectStoreNames));
		
		// Pre-fill Groq API key if not set
		// Pre-fill API key from URL param ?groq_key=xxx (for convenience)
		const existingKey = await providerKeys.get("groq");
		if (!existingKey) {
			const urlKey = new URLSearchParams(window.location.search).get("groq_key");
			if (urlKey) {
				await providerKeys.set("groq", urlKey);
				console.log("[mini-agent] Groq API key set from URL param");
				// Remove key from URL for security
				const url = new URL(window.location.href);
				url.searchParams.delete("groq_key");
				window.history.replaceState({}, "", url);
			}
		}
	} catch (e) {
		console.error("[mini-agent] DB init error:", e);
	}
})();

// ============================================================================
// STATE
// ============================================================================
let currentSessionId: string | undefined;
let currentTitle = "";
let agent: Agent;
let chatPanel: ChatPanel;
let agentUnsubscribe: (() => void) | undefined;

const SYSTEM_PROMPT = `You are Mini-Agent, a helpful AI assistant running on Agent OS. Be concise and helpful.`;

// ============================================================================
// HELPERS
// ============================================================================
const generateTitle = (messages: AgentMessage[]): string => {
	const firstUserMsg = messages.find((m) => m.role === "user" || m.role === "user-with-attachments");
	if (!firstUserMsg || (firstUserMsg.role !== "user" && firstUserMsg.role !== "user-with-attachments")) return "";
	const content = firstUserMsg.content;
	const text = typeof content === "string" ? content : content.filter((c: any) => c.type === "text").map((c: any) => c.text || "").join(" ");
	const trimmed = text.trim();
	if (!trimmed) return "";
	const end = trimmed.search(/[.!?]/);
	if (end > 0 && end <= 50) return trimmed.substring(0, end + 1);
	return trimmed.length <= 50 ? trimmed : `${trimmed.substring(0, 47)}...`;
};

const shouldSave = (msgs: AgentMessage[]) =>
	msgs.some((m: any) => m.role === "user" || m.role === "user-with-attachments") &&
	msgs.some((m: any) => m.role === "assistant");

const saveSession = async () => {
	if (!storage.sessions || !currentSessionId || !agent || !currentTitle) return;
	const state = agent.state;
	if (!shouldSave(state.messages)) return;
	const now = new Date().toISOString();
	await storage.sessions.save(
		{ id: currentSessionId, title: currentTitle, model: state.model!, thinkingLevel: state.thinkingLevel, messages: state.messages, createdAt: now, lastModified: now },
		{ id: currentSessionId, title: currentTitle, createdAt: now, lastModified: now, messageCount: state.messages.length, usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 } }, modelId: state.model?.id || null, thinkingLevel: state.thinkingLevel, preview: generateTitle(state.messages) },
	);
};

const updateUrl = (id: string) => {
	const url = new URL(window.location.href);
	url.searchParams.set("session", id);
	window.history.replaceState({}, "", url);
};

// ============================================================================
// AGENT
// ============================================================================
const createAgent = async (initialState?: Partial<AgentState>) => {
	agentUnsubscribe?.();

	agent = new Agent({
		initialState: initialState || {
			systemPrompt: SYSTEM_PROMPT,
			model: getModel("groq", "llama-3.3-70b-versatile"),
			thinkingLevel: "off",
			messages: [],
			tools: [],
		},
	});

	agentUnsubscribe = agent.subscribe((event: any) => {
		// Workaround: Lit light-DOM mode doesn't re-set child element properties
		// on re-render when the template structure hasn't changed, so message-list
		// never sees its .messages property update. Force it manually.
		if (chatPanel) {
			const ai = chatPanel.querySelector("agent-interface") as any;
			const ml = ai?.querySelector("message-list") as any;
			if (ml && agent) {
				ml.messages = [...agent.state.messages];
				ml.requestUpdate();
			}
		}
		if (event.type === "state-update") {
			const msgs = event.state.messages;
			if (!currentTitle && shouldSave(msgs)) currentTitle = generateTitle(msgs);
			if (!currentSessionId && shouldSave(msgs)) {
				currentSessionId = crypto.randomUUID();
				updateUrl(currentSessionId);
			}
			if (currentSessionId) saveSession();
			renderApp();
		}
	});

	await chatPanel.setAgent(agent, {
		onApiKeyRequired: async (provider: string) => ApiKeyPromptDialog.prompt(provider),
		toolsFactory: () => [],
	});

	// Fix: Lit @query decorator doesn't find elements when createRenderRoot returns this
	// Patch _messageEditor after render completes
	requestAnimationFrame(() => {
		const ai = document.querySelector("agent-interface") as any;
		if (ai && !ai._messageEditor) {
			const me = (ai.renderRoot || ai).querySelector("message-editor");
			if (me) {
				ai._messageEditor = me;
				console.log("[mini-agent] Patched _messageEditor");
			}
		}
	});
};

const loadSession = async (sessionId: string): Promise<boolean> => {
	if (!storage.sessions) return false;
	const data = await storage.sessions.get(sessionId);
	if (!data) return false;
	currentSessionId = sessionId;
	const meta = await storage.sessions.getMetadata(sessionId);
	currentTitle = meta?.title || "";
	await createAgent({ model: data.model, thinkingLevel: data.thinkingLevel, messages: data.messages, tools: [] });
	updateUrl(sessionId);
	renderApp();
	return true;
};

const newSession = () => {
	const url = new URL(window.location.href);
	url.search = "";
	window.location.href = url.toString();
};

// ============================================================================
// RENDER
// ============================================================================
const renderApp = () => {
	const app = document.getElementById("app");
	if (!app) return;

	render(html`
		<div class="w-full h-screen flex flex-col bg-background text-foreground overflow-hidden">
			<div class="flex items-center justify-between border-b border-border shrink-0">
				<div class="flex items-center gap-2 px-4 py-2">
					${Button({ variant: "ghost", size: "sm", children: icon(History, "sm"), onClick: () => SessionListDialog.open(async (id) => loadSession(id), (id) => { if (id === currentSessionId) newSession(); }), title: "Sessions" })}
					${Button({ variant: "ghost", size: "sm", children: icon(Plus, "sm"), onClick: newSession, title: "New Session" })}
					${currentTitle
						? html`<span class="text-sm text-muted-foreground">${currentTitle}</span>`
						: html`<span class="text-base font-semibold text-foreground">Mini-Agent</span>`}
				</div>
				<div class="flex items-center gap-1 px-2">
					<theme-toggle></theme-toggle>
					${Button({ variant: "ghost", size: "sm", children: icon(Settings, "sm"), onClick: () => SettingsDialog.open([new ProvidersModelsTab(), new ProxyTab()]), title: "Settings" })}
				</div>
			</div>
			${chatPanel}
		</div>
	`, app);
};

// ============================================================================
// INIT
// ============================================================================
async function initApp() {
	const app = document.getElementById("app");
	if (!app) throw new Error("App container not found");

	render(html`<div class="w-full h-screen flex items-center justify-center bg-background text-foreground"><div class="text-muted-foreground">Loading...</div></div>`, app);

	chatPanel = new ChatPanel();
	chatPanel.style.flex = "1";
	chatPanel.style.minHeight = "0";
	chatPanel.style.display = "flex";
	chatPanel.style.flexDirection = "column";

	// IMPORTANT: render first so ChatPanel is in the DOM before setAgent()
	renderApp();

	// Small delay to let Web Components initialize their Shadow DOM
	await new Promise(r => setTimeout(r, 100));

	const sessionId = new URLSearchParams(window.location.search).get("session");
	if (sessionId) {
		if (!await loadSession(sessionId)) { newSession(); return; }
	} else {
		await createAgent();
	}
	renderApp();
}

initApp();
