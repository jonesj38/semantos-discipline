---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/bsv-app/navigator.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.723995+00:00
---

# archive/apps-navigation_app/bsv-app/navigator.js

```js
/**
 * Navigator — command seat for the Semantos semantic operating system.
 *
 * General-purpose object navigator. Renders any extension's types
 * through lenses (attention allocation dimensions), manages extensions,
 * and provides a command bar for shell commands or natural language.
 *
 * No extension-specific logic lives here — extensions register their
 * types via config, and the navigator presents them.
 */

// ── Navigation Lenses (attention allocation primitives) ─────────

const LENSES = [
  { id: 'mind',   label: 'Mind',   emoji: '🧠', color: '#818cf8', group: 'self' },
  { id: 'body',   label: 'Body',   emoji: '💪', color: '#f472b6', group: 'self' },
  { id: 'spirit', label: 'Spirit', emoji: '✨', color: '#c084fc', group: 'self' },
  { id: 'tribe',  label: 'Tribe',  emoji: '👥', color: '#fb923c', group: 'connection' },
  { id: 'home',   label: 'Home',   emoji: '🏠', color: '#4ade80', group: 'connection' },
  { id: 'craft',  label: 'Craft',  emoji: '🎨', color: '#facc15', group: 'creation' },
  { id: 'wealth', label: 'Wealth', emoji: '💎', color: '#38bdf8', group: 'creation' },
];

// Map dimension enum values to lens IDs
const DIM_TO_LENS = {
  'MENTAL': 'mind', 'PHYSICAL': 'body', 'SPIRITUAL': 'spirit',
  'SOCIAL': 'tribe', 'VOCATIONAL': 'craft', 'FINANCIAL': 'wealth',
  'FAMILIAL': 'home',
  'mental': 'mind', 'physical': 'body', 'spiritual': 'spirit',
  'social': 'tribe', 'vocational': 'craft', 'financial': 'wealth',
  'familial': 'home',
};

// ── App ─────────────────────────────────────────────────────────

const app = {
  history: [],
  objects: {},
  cwi: null,
  kernel: null,
  listening: false,
  recognition: null,
  activeLens: null,

  // ── Init ──

  init() {
    this.detectCWI();
    this.detectKernel();
    this.renderExtensions();
    this.renderLensStrip();
    this.renderObjects();

    const input = document.getElementById('input');
    input.addEventListener('input', () => {
      document.getElementById('send-btn').disabled = !input.value.trim();
    });
  },

  detectKernel() {
    if (typeof window !== 'undefined' && window.SemantosKernel) {
      this.kernel = window.SemantosKernel;
      document.getElementById('kernel-dot').className = 'dot on';
    }
  },

  detectCWI() {
    if (typeof window !== 'undefined' && typeof window.CWI !== 'undefined') {
      this.cwi = window.CWI;
      document.getElementById('cwi-dot').className = 'dot on';
    }
  },

  // ══════════════════════════════════════════════════════════════
  //  LENS STRIP + OBJECTS
  // ══════════════════════════════════════════════════════════════

  renderLensStrip() {
    const strip = document.getElementById('lens-strip');
    let html = `<button class="lens-pill all-pill${this.activeLens === null ? ' active' : ''}"
      onclick="app.setLens(null)">All</button>`;

    for (const lens of LENSES) {
      const active = this.activeLens === lens.id;
      html += `<button class="lens-pill${active ? ' active' : ''}"
        style="--lens-color:${lens.color}"
        onclick="app.setLens('${lens.id}')">
        <span class="lens-emoji">${lens.emoji}</span>${lens.label}
      </button>`;
    }
    strip.innerHTML = html;
  },

  setLens(lensId) {
    this.activeLens = lensId;
    this.renderLensStrip();
    this.renderObjects();
  },

  /** Get lens IDs for an object based on its dimension fields */
  objectLenses(obj) {
    const fields = obj.fields || obj.payload || {};
    const lenses = new Set();

    if (fields.dimension) {
      const l = DIM_TO_LENS[fields.dimension];
      if (l) lenses.add(l);
    }
    if (fields.dimensions) {
      const dims = typeof fields.dimensions === 'string'
        ? fields.dimensions.split(',').map(s => s.trim())
        : Array.isArray(fields.dimensions) ? fields.dimensions : [];
      for (const d of dims) {
        const l = DIM_TO_LENS[d];
        if (l) lenses.add(l);
      }
    }
    for (const f of ['win1Dimension', 'win2Dimension', 'win3Dimension', 'primaryDimension', 'secondaryDimension', 'tomorrowDimensionFocus', 'focusDimension']) {
      if (fields[f]) {
        const l = DIM_TO_LENS[fields[f]];
        if (l) lenses.add(l);
      }
    }

    return Array.from(lenses);
  },

  renderObjects() {
    const container = document.getElementById('objects-area');
    const allObjects = this.kernel ? this.kernel.listObjects() : Object.values(this.objects);

    let filtered;
    if (this.activeLens === null) {
      filtered = allObjects;
    } else {
      filtered = allObjects.filter(obj => this.objectLenses(obj).includes(this.activeLens));
    }

    filtered = filtered.slice().sort((a, b) => {
      const ta = typeof a.createdAt === 'number' ? a.createdAt : new Date(a.createdAt || 0).getTime();
      const tb = typeof b.createdAt === 'number' ? b.createdAt : new Date(b.createdAt || 0).getTime();
      return tb - ta;
    });

    if (filtered.length === 0) {
      const lens = this.activeLens ? LENSES.find(l => l.id === this.activeLens) : null;
      const hint = lens
        ? `No objects in ${lens.emoji} ${lens.label} yet.`
        : 'No objects yet. Use the command bar to create one.';
      container.innerHTML = `<div class="empty-state"><span class="empty-icon">~</span>${hint}</div>`;
      return;
    }

    let html = '';
    for (const obj of filtered.slice(0, 30)) {
      const type = obj.type || '';
      const fields = obj.fields || obj.payload || {};
      const icon = this.objectIcon(type);
      const label = this.objectSummary(type, fields);
      const ts = obj.createdAt;
      const time = typeof ts === 'number' ? this.timeAgoMs(ts) : this.timeAgo(ts);
      const lenses = this.objectLenses(obj);
      const typeColor = this.typeColor(type);

      let lensTagsHtml = '';
      if (lenses.length > 0) {
        lensTagsHtml = '<div class="obj-lens-tags">' +
          lenses.map(lid => {
            const l = LENSES.find(x => x.id === lid);
            return l ? `<span class="obj-lens-tag">${l.emoji} ${l.label}</span>` : '';
          }).join('') + '</div>';
      }

      html += `
        <div class="object-card" style="--obj-color:${typeColor}">
          <div class="obj-header">
            <span>${icon}</span>
            <span class="obj-type">${type}</span>
            <span class="obj-time">${time}</span>
          </div>
          <div class="obj-content">${this.esc(label)}</div>
          ${lensTagsHtml}
        </div>`;
    }
    container.innerHTML = html;
  },

  objectIcon(type) {
    const icons = {
      ConsumerBinding: '🔗',
    };
    return icons[type] || '•';
  },

  objectSummary(type, fields) {
    // Generic: show first string field value as summary
    for (const key of Object.keys(fields)) {
      const val = fields[key];
      if (typeof val === 'string' && val.length > 0) {
        const preview = val.length > 80 ? val.slice(0, 80) + '…' : val;
        return preview;
      }
    }
    return type;
  },

  typeColor(type) {
    // Hash type name to a color for visual variety
    let hash = 0;
    for (let i = 0; i < type.length; i++) hash = type.charCodeAt(i) + ((hash << 5) - hash);
    const hue = Math.abs(hash) % 360;
    return `hsl(${hue}, 60%, 55%)`;
  },

  // ══════════════════════════════════════════════════════════════
  //  EXTENSIONS
  // ══════════════════════════════════════════════════════════════

  renderExtensions() {
    const c = document.getElementById('extensions-content');

    let html = `
      <div style="font-size:20px;font-weight:700;margin-bottom:4px">Extensions</div>
      <div style="font-size:13px;color:var(--text-50);margin-bottom:16px">Installed extensions and their object types.</div>
    `;

    // Read live extension data from kernel bridge
    const exts = this.kernel?.listExtensions?.() || [];

    if (exts.length === 0) {
      html += '<div class="empty-state"><span class="empty-icon">~</span>No extensions loaded. Kernel not connected.</div>';
    } else {
      for (const ext of exts) {
        const color = ext.theme?.primaryColor || this.typeColor(ext.id);
        const icon = ext.id.includes('navigator') ? '🧭'
          : ext.id.includes('consciousness') ? '✨'
          : '📦';
        const flowNote = ext.flowCount > 0 ? `<span style="font-size:11px;color:var(--text-30);margin-left:8px">${ext.flowCount} flows</span>` : '';

        html += `
          <div class="card" style="border-left:3px solid ${color}">
            <div style="display:flex;align-items:center;gap:8px;margin-bottom:10px">
              <span style="font-size:20px">${icon}</span>
              <span style="font-size:16px;font-weight:600">${ext.name}</span>
              <span style="font-size:11px;color:var(--text-30);margin-left:auto">${ext.id}</span>
              ${flowNote}
            </div>
            <div style="display:flex;flex-wrap:wrap;gap:4px">
              ${ext.types.map(t => `<span style="font-size:11px;padding:3px 8px;border-radius:10px;background:var(--surface-hover);color:var(--text-50)">${t}</span>`).join('')}
            </div>
          </div>`;
      }
    }

    c.innerHTML = html;
  },

  // ══════════════════════════════════════════════════════════════
  //  ACTIVITY
  // ══════════════════════════════════════════════════════════════

  renderActivity() {
    const c = document.getElementById('activity-content');
    const allObjects = this.kernel ? this.kernel.listObjects() : Object.values(this.objects);

    let html = `
      <div style="font-size:20px;font-weight:700;margin-bottom:4px">Activity</div>
      <div style="font-size:13px;color:var(--text-50);margin-bottom:16px">Recent objects across all extensions.</div>
    `;

    const sorted = allObjects.slice().sort((a, b) => {
      const ta = typeof a.createdAt === 'number' ? a.createdAt : new Date(a.createdAt || 0).getTime();
      const tb = typeof b.createdAt === 'number' ? b.createdAt : new Date(b.createdAt || 0).getTime();
      return tb - ta;
    });

    if (sorted.length === 0) {
      html += '<div class="empty-state"><span class="empty-icon">~</span>Objects will appear here as you create them.</div>';
    } else {
      for (const obj of sorted.slice(0, 30)) {
        const type = obj.type || '';
        const fields = obj.fields || obj.payload || {};
        const icon = this.objectIcon(type);
        const label = this.objectSummary(type, fields);
        const ts = obj.createdAt;
        const time = typeof ts === 'number' ? this.timeAgoMs(ts) : this.timeAgo(ts);
        const typeColor = this.typeColor(type);

        html += `
          <div class="object-card" style="--obj-color:${typeColor}">
            <div class="obj-header">
              <span>${icon}</span>
              <span class="obj-type">${type}</span>
              <span class="obj-time">${time}</span>
            </div>
            <div class="obj-content">${this.esc(label)}</div>
          </div>`;
      }
    }

    c.innerHTML = html;
  },

  // ══════════════════════════════════════════════════════════════
  //  COMMAND BAR
  // ══════════════════════════════════════════════════════════════

  async send() {
    const input = document.getElementById('input');
    const text = input.value.trim();
    if (!text) return;
    input.value = '';
    input.style.height = '42px';
    document.getElementById('send-btn').disabled = true;

    this.addUserMsg(text);

    try {
      const result = await this.processCommand(text);
      this.addAssistantMsg(result);
      this.renderObjects();
    } catch (err) {
      this.addSystemMsg(`Error: ${err.message}`);
    }
  },

  async processCommand(text) {
    const lower = text.toLowerCase().trim();

    // Shell commands
    if (lower.startsWith('/')) {
      return this.handleShellCommand(lower, text);
    }

    // API key setup
    if (lower.startsWith('key:')) {
      const key = text.slice(4).trim();
      localStorage.setItem('openrouter_key', key);
      return { reply: 'API key saved.' };
    }

    // If LLM key is set, route to LLM
    const apiKey = localStorage.getItem('openrouter_key');
    if (apiKey) {
      return this.llmProcess(text, apiKey);
    }

    // Fallback: echo what's available
    return {
      reply: `Semantos Navigator. ${this.kernel ? 'Kernel connected.' : 'No kernel.'} ` +
        `${Object.keys(this.objects).length} objects in memory. ` +
        `Type /help for commands, or set an API key with key:<your-key> for natural language.`,
    };
  },

  handleShellCommand(lower, raw) {
    if (lower === '/help') {
      return {
        reply: [
          'Commands:',
          '  /extensions — list installed extensions',
          '  /objects — list all objects',
          '  /create <Type> — create an object',
          '  /lenses — show available lenses',
          '  /status — system status',
          '  key:<api-key> — set OpenRouter API key for natural language',
        ].join('\n'),
      };
    }

    if (lower === '/extensions') {
      this.switchView('extensions');
      return { reply: 'Switched to Extensions view.' };
    }

    if (lower === '/objects') {
      this.switchView('home');
      return { reply: 'Switched to Objects view.' };
    }

    if (lower === '/lenses') {
      const list = LENSES.map(l => `  ${l.emoji} ${l.label} (${l.id})`).join('\n');
      return { reply: `Navigation lenses:\n${list}` };
    }

    if (lower === '/status') {
      const objCount = this.kernel ? (this.kernel.listObjects?.()?.length || 0) : Object.keys(this.objects).length;
      return {
        reply: [
          `Kernel: ${this.kernel ? 'connected' : 'not connected'}`,
          `Wallet: ${this.cwi ? 'connected' : 'not connected'}`,
          `Objects: ${objCount}`,
          `Active lens: ${this.activeLens || 'all'}`,
        ].join('\n'),
      };
    }

    if (lower.startsWith('/create ')) {
      const typeName = raw.slice(8).trim();
      if (this.kernel) {
        const id = this.kernel.createObject(typeName, {});
        if (id) return { reply: `Created ${typeName} (${id})` };
        return { reply: `Failed to create ${typeName} — unknown type?` };
      }
      const id = `${typeName.toLowerCase()}-${Date.now()}`;
      this.objects[id] = {
        id, type: typeName, payload: {},
        createdAt: new Date().toISOString(),
      };
      return { reply: `Created ${typeName} (${id})` };
    }

    return { reply: `Unknown command: ${raw}. Type /help for available commands.` };
  },

  async llmProcess(text, apiKey) {
    const extTypes = this.kernel?.listTypes?.() || [];
    const objCount = this.kernel ? (this.kernel.listObjects?.()?.length || 0) : Object.keys(this.objects).length;

    const systemPrompt = `You are the Semantos Navigator — the command seat for a semantic operating system.
The user can browse objects through lenses, manage extensions, and interact with the system.

Available lenses: ${LENSES.map(l => `${l.emoji} ${l.label}`).join(', ')}
Loaded types: ${extTypes.length > 0 ? extTypes.join(', ') : 'unknown'}
Object count: ${objCount}

Respond briefly and helpfully. If the user wants to create an object, include an action.
Response format (JSON):
{
  "reply": "Your response",
  "actions": [{ "type": "create", "objectType": "TypeName", "fields": {} }]
}`;

    const messages = [
      { role: 'system', content: systemPrompt },
      ...this.history.slice(-10),
      { role: 'user', content: text },
    ];
    this.history.push({ role: 'user', content: text });

    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://semantos.dev',
        'X-Title': 'Semantos Navigator',
      },
      body: JSON.stringify({
        model: 'anthropic/claude-sonnet-4',
        messages,
        temperature: 0.3,
        response_format: { type: 'json_object' },
      }),
    });

    if (!response.ok) throw new Error(`LLM ${response.status}`);
    const data = await response.json();
    let content = data.choices?.[0]?.message?.content;
    if (!content) throw new Error('No response');

    content = content.replace(/^```(?:json)?\n?/, '').replace(/\n?```$/, '').trim();
    const parsed = JSON.parse(content);
    this.history.push({ role: 'assistant', content: parsed.reply || content });

    if (parsed.actions) {
      for (const action of parsed.actions) this.executeAction(action);
    }
    return parsed;
  },

  executeAction(action) {
    if (action.type === 'create' && action.objectType) {
      if (this.kernel) {
        this.kernel.createObject(action.objectType, action.fields || {});
      } else {
        const id = `${action.objectType.toLowerCase()}-${Date.now()}`;
        this.objects[id] = {
          id, type: action.objectType,
          payload: action.fields || {},
          createdAt: new Date().toISOString(),
        };
      }
    }
  },

  // ── Chat UI ──

  addUserMsg(text) {
    const el = document.createElement('div');
    el.className = 'msg user';
    el.innerHTML = `<div class="msg-bubble">${this.esc(text)}</div>`;
    document.getElementById('history').appendChild(el);
    this.scrollChat();
  },

  addAssistantMsg(result) {
    const el = document.createElement('div');
    el.className = 'msg assistant';
    el.innerHTML = `<div class="msg-bubble">${this.esc(result.reply || '')}</div>`;
    document.getElementById('history').appendChild(el);
    this.scrollChat();
  },

  addSystemMsg(text) {
    const el = document.createElement('div');
    el.className = 'msg system';
    el.innerHTML = `<div class="msg-bubble">${text}</div>`;
    document.getElementById('history').appendChild(el);
    this.scrollChat();
  },

  scrollChat() {
    const h = document.getElementById('history');
    requestAnimationFrame(() => h.scrollTop = h.scrollHeight);
  },

  // ══════════════════════════════════════════════════════════════
  //  VIEW SWITCHING
  // ══════════════════════════════════════════════════════════════

  switchView(name) {
    document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
    document.getElementById(`${name}-view`).classList.add('active');
    document.querySelector(`[data-view="${name}"]`).classList.add('active');

    if (name === 'extensions') this.renderExtensions();
    if (name === 'activity') this.renderActivity();
    if (name === 'home') { this.renderLensStrip(); this.renderObjects(); }
  },

  // ══════════════════════════════════════════════════════════════
  //  VOICE
  // ══════════════════════════════════════════════════════════════

  toggleVoice() {
    if (!('webkitSpeechRecognition' in window || 'SpeechRecognition' in window)) {
      this.addSystemMsg('Voice not available in this browser.');
      return;
    }
    const btn = document.getElementById('voice-btn');
    if (this.listening) {
      this.recognition?.stop();
      this.listening = false;
      btn.classList.remove('listening');
      return;
    }
    const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
    this.recognition = new SR();
    this.recognition.continuous = true;
    this.recognition.interimResults = true;
    const input = document.getElementById('input');
    this.recognition.onresult = (e) => {
      let t = '';
      for (let i = e.resultIndex; i < e.results.length; i++) t += e.results[i][0].transcript;
      input.value = t;
      input.dispatchEvent(new Event('input'));
    };
    this.recognition.onend = () => { this.listening = false; btn.classList.remove('listening'); };
    this.recognition.start();
    this.listening = true;
    btn.classList.add('listening');
  },

  // ── Helpers ──

  handleKey(e) {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      this.send();
    }
  },

  autoGrow(el) {
    el.style.height = '42px';
    el.style.height = Math.min(el.scrollHeight, 120) + 'px';
  },

  timeAgoMs(ts) {
    const diff = Date.now() - ts;
    const mins = Math.floor(diff / 60000);
    if (mins < 1) return 'just now';
    if (mins < 60) return `${mins}m ago`;
    const hrs = Math.floor(mins / 60);
    if (hrs < 24) return `${hrs}h ago`;
    return `${Math.floor(hrs / 24)}d ago`;
  },

  timeAgo(iso) {
    if (!iso) return '';
    const diff = Date.now() - new Date(iso).getTime();
    const mins = Math.floor(diff / 60000);
    if (mins < 1) return 'just now';
    if (mins < 60) return `${mins}m ago`;
    const hrs = Math.floor(mins / 60);
    if (hrs < 24) return `${hrs}h ago`;
    return `${Math.floor(hrs / 24)}d ago`;
  },

  esc(str) {
    return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  },
};

// Boot
document.addEventListener('DOMContentLoaded', () => app.init());

```
