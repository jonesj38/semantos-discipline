---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/bsv-app/navigation.js
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.726433+00:00
---

# archive/apps-navigation_app/bsv-app/navigation.js

```js
/**
 * Navigation — consciousness development shell.
 *
 * Runs inside BSV Browser. Primary UI is conversation + structured flows.
 * LLM extracts structured objects from natural language.
 * BRC-100 (window.CWI) handles all payments.
 * Kernel enforces consumption semantics (hidden from user).
 */

// ── Process Map Data (from Quantum Movement diagram) ──────────

const PROCESS_CYCLES = [
  {
    id: 'foundation', label: 'Foundation', color: '#3b82f6',
    inquiry: 'WHO am I?',
    description: 'Build the base: willingness to grow, command of attention, finding ease.',
    steps: [
      { id: 'growth', label: 'Growth', release: false, receive: false, desc: 'The willingness to grow. Everything begins here.' },
      { id: 'attention', label: 'Attention', release: false, receive: false, desc: 'Master the command of your attention.' },
      { id: 'ease', label: 'Ease', release: false, receive: false, desc: 'Find ease in the process.' },
    ],
  },
  {
    id: 'energetic_release', label: 'Energetic Release', color: '#ef4444',
    inquiry: 'WHAT am I holding?',
    description: 'Clear what doesn\'t serve you. Meet resistance, accept, integrate, seal.',
    steps: [
      { id: 'qse_vacuum', label: 'QSE Vacuum', release: true, receive: false, desc: 'Invoke quantum source energy. Release everything except your highest.' },
      { id: 'resistance', label: 'Resistance', release: false, receive: false, desc: 'Meet what resists the release.' },
      { id: 'acceptance', label: 'Acceptance', release: false, receive: false, desc: 'Accept what is.' },
      { id: 'qse_integrate', label: 'QSE Integrate', release: false, receive: true, desc: 'Integrate your highest expression.' },
      { id: 'gold', label: 'Gold', release: false, receive: false, desc: 'Seal with gold. Permanence.' },
    ],
  },
  {
    id: 'conscious_release', label: 'Conscious Release', color: '#8b5cf6',
    inquiry: 'WHEN do I release?',
    description: 'Deeper release through writing and awareness. Connect, release, receive.',
    recursive: true,
    steps: [
      { id: 'release_1', label: 'Release', release: true, receive: false, desc: 'Write, speak, move — let it flow out.' },
      { id: 'awareness', label: 'Awareness', release: false, receive: false, desc: 'What patterns emerge from what you released?' },
      { id: 'connection', label: 'Connection', release: false, receive: false, desc: 'Connect to highest expression, inner child, future self.' },
      { id: 'release_2', label: 'Release', release: true, receive: false, desc: 'Deeper release — informed by awareness.' },
      { id: 'receive', label: 'Receive', release: false, receive: true, desc: 'What intelligence is available?' },
    ],
  },
  {
    id: 'discernment', label: 'Discernment', color: '#f59e0b',
    inquiry: 'WHY do I believe this?',
    description: 'Distinguish ego from soul. Belief vs knowledge. Discernment vs wisdom.',
    steps: [
      { id: 'degrees_auth', label: 'Degrees of Authenticity', release: false, receive: false, desc: 'How authentic are you being right now?' },
      { id: 'ego', label: 'Ego: Belief ↔ Knowledge', release: false, receive: false, desc: 'Which is driving you?' },
      { id: 'soul', label: 'Soul: Discernment ↔ Wisdom', release: false, receive: false, desc: 'Trust the difference.' },
    ],
  },
  {
    id: 'application', label: 'Application', color: '#4ade80',
    inquiry: 'WHERE & HOW do I create?',
    description: 'Apply understanding across all seven dimensions. Create. Complete.',
    steps: [
      { id: 'understanding', label: 'Understanding', release: false, receive: true, desc: 'Integrate across all cycles.' },
      { id: 'creation', label: 'Creation', release: false, receive: false, desc: 'Create across 7 dimensions.' },
      { id: 'completion', label: 'Completion', release: false, receive: false, desc: 'Manifest and release into the world.' },
    ],
  },
];

// ── Object type definitions (for LLM, hidden from user) ──────

const OBJECT_TYPES = `
Release (LINEAR): rawText, themes[], emotionalValence(-1..1), processStepId, durationSeconds
Insight (RELEVANT): content, source(writing|connection|vacuum|meditation|llm), tags[], dimension?
Pattern (RELEVANT): description, occurrences, strength(0..1), sourceReleaseIds[]
Intention (AFFINE): statement, dimension?, deadline?
DailyReview (LINEAR): wins[], improvements[], tomorrowIntention, energyLevel(1-10), moodLevel(1-10), dimensionScores{}
MorningIntention (LINEAR): focusDimension, intention, concreteAction
DimensionPulse (AFFINE): dimension, score(1-10), note?
Session (LINEAR): sessionType, durationSeconds, processStepId?
`.trim();

const DIMENSIONS = [
  { id: 'mental',     emoji: '🧠', label: 'Mental' },
  { id: 'physical',   emoji: '💪', label: 'Physical' },
  { id: 'spiritual',  emoji: '🙏', label: 'Spiritual' },
  { id: 'social',     emoji: '🤝', label: 'Social' },
  { id: 'vocational', emoji: '🎯', label: 'Vocational' },
  { id: 'financial',  emoji: '💰', label: 'Financial' },
  { id: 'familial',   emoji: '❤️', label: 'Family' },
];

// ── App State ─────────────────────────────────────────────────

const app = {
  history: [],
  objects: {},
  cwi: null,
  nodeWs: null,
  listening: false,
  recognition: null,
  releaseTimer: null,
  releaseSeconds: 0,
  streak: 0,
  dimensionScores: { mental: 5, physical: 4, spiritual: 6, social: 5, vocational: 7, financial: 4, familial: 6 },

  kernel: null,
  cardManager: null,
  cards: {},

  // ── Init ──

  init() {
    this.detectCWI();
    this.detectKernel();
    this.renderDashboard();
    this.renderProcessMap();
    this.renderInsights();
    this.initChat();

    const input = document.getElementById('input');
    input.addEventListener('input', () => {
      document.getElementById('send-btn').disabled = !input.value.trim();
    });
  },

  detectKernel() {
    if (typeof window !== 'undefined' && window.SemantosKernel) {
      this.kernel = window.SemantosKernel;
      document.getElementById('kernel-dot').className = 'dot on';

      // Initialize card data manager
      if (window.CardDataManager) {
        this.cardManager = new CardDataManager();
        this.cardManager.connect();
        this.cardManager.subscribe(() => this.renderDimensionCards());
      }
    }
  },

  // ── BRC-100 / BSV Browser ──

  detectCWI() {
    if (typeof window !== 'undefined' && typeof window.CWI !== 'undefined') {
      this.cwi = window.CWI;
      document.getElementById('cwi-dot').className = 'dot on';
    }
  },

  async requestDeposit(satoshis, description) {
    if (!this.cwi) return { error: 'Not in BSV Browser' };
    try {
      return await this.cwi.createAction({
        description: description || `Navigation: ${satoshis} sats`,
        outputs: [{ satoshis }],
      });
    } catch (e) { return { error: e.message }; }
  },

  // ══════════════════════════════════════════════════════════════
  //  DASHBOARD
  // ══════════════════════════════════════════════════════════════

  renderDashboard() {
    const c = document.getElementById('dashboard-content');
    const hour = new Date().getHours();
    const greeting = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';

    let html = `
      <div class="greeting">${greeting}</div>
      <div class="greeting-sub">What would you like to focus on today?</div>
      <div style="margin-top:12px">
        <div class="streak-badge">🔥 ${this.streak} day streak</div>
      </div>
    `;

    // Quick actions
    html += `
      <div class="quick-actions" style="margin-top:16px">
        <button class="quick-btn" onclick="app.openOverlay('release')">
          <span class="q-icon">✍️</span> Release
        </button>
        <button class="quick-btn" onclick="app.openOverlay('intention')">
          <span class="q-icon">🌅</span> Intention
        </button>
        <button class="quick-btn" onclick="app.openOverlay('review')">
          <span class="q-icon">🌙</span> Review
        </button>
        <button class="quick-btn" onclick="app.switchView('chat')">
          <span class="q-icon">💬</span> Talk
        </button>
      </div>
    `;

    // Spinning dimension cards (grouped by Self / Connection / Creation)
    html += '<div id="dimension-cards-container"></div>';

    // Fallback: simple dimension bars when kernel not loaded
    if (!this.cardManager) {
      html += '<div class="card" style="margin-top:16px">';
      html += '<div class="card-title">Life Dimensions</div>';
      for (const dim of DIMENSIONS) {
        const score = this.dimensionScores[dim.id] || 5;
        const pct = score * 10;
        const color = this.scoreColor(score);
        html += `
          <div class="dim-row">
            <span class="dim-emoji">${dim.emoji}</span>
            <span class="dim-label">${dim.label}</span>
            <div class="dim-bar-wrap"><div class="dim-bar" style="width:${pct}%;background:${color}"></div></div>
            <span class="dim-score" style="color:${color}">${score}</span>
          </div>`;
      }
      html += '</div>';
    }

    // Recent activity
    const recentSource = this.kernel ? this.kernel.listObjects() : Object.values(this.objects);
    const recent = recentSource.slice(-5).reverse();
    if (recent.length > 0) {
      html += '<div class="card" style="margin-top:4px">';
      html += '<div class="card-title">Recent</div>';
      for (const obj of recent) {
        const type = obj.type || obj.type;
        const fields = obj.fields || obj.payload || {};
        const icon = this.objectIcon(type);
        const label = this.objectLabel({ type, payload: fields });
        const ts = obj.createdAt;
        const time = typeof ts === 'number' ? this.timeAgoMs(ts) : this.timeAgo(ts);
        html += `<div style="display:flex;align-items:center;gap:10px;padding:6px 0">
          <span style="font-size:16px">${icon}</span>
          <span style="flex:1;font-size:13px;color:var(--text-70)">${label}</span>
          <span class="time-ago">${time}</span>
        </div>`;
      }
      html += '</div>';
    }

    c.innerHTML = html;

    // Render spinning cards after DOM is ready
    if (this.cardManager && window.SpinningCard) {
      this.renderDimensionCards();
    }
  },

  renderDimensionCards() {
    const container = document.getElementById('dimension-cards-container');
    if (!container || !this.cardManager || !window.SpinningCard) return;

    container.innerHTML = '';
    const grouped = this.cardManager.getGrouped();

    for (const [groupName, dims] of Object.entries(grouped)) {
      const groupEl = document.createElement('div');
      groupEl.className = 'dimension-group';

      const label = document.createElement('div');
      label.className = 'group-label';
      label.textContent = groupName;
      groupEl.appendChild(label);

      const grid = document.createElement('div');
      grid.className = 'card-grid';

      for (const dim of dims) {
        const cardWrapper = document.createElement('div');
        new SpinningCard(cardWrapper, dim.dimId, {
          score: dim.score,
          recentEntries: dim.recentEntries,
          faces: ['profile', 'reflection'],
        });
        // Move the rendered element into the grid
        const rendered = cardWrapper.firstElementChild;
        if (rendered) grid.appendChild(rendered);
      }

      groupEl.appendChild(grid);
      container.appendChild(groupEl);
    }
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

  scoreColor(score) {
    if (score <= 3) return '#ef4444';
    if (score <= 5) return '#f59e0b';
    if (score <= 7) return '#3b82f6';
    return '#4ade80';
  },

  objectIcon(type) {
    const icons = {
      Release: '↗', Insight: '✦', Pattern: '🔄', Intention: '🎯',
      DailyReview: '🌙', MorningIntention: '🌅', DimensionPulse: '📊', Session: '⏱',
    };
    return icons[type] || '•';
  },

  objectLabel(obj) {
    if (obj.type === 'Release') {
      const text = obj.payload?.rawText || '';
      return 'Released: ' + (text.length > 50 ? text.slice(0, 50) + '…' : text || 'written release');
    }
    if (obj.type === 'Insight') return obj.payload?.content?.slice(0, 60) || 'New insight';
    if (obj.type === 'Intention') return obj.payload?.statement?.slice(0, 60) || 'New intention';
    if (obj.type === 'DailyReview') return 'Evening review completed';
    if (obj.type === 'MorningIntention') return `Focus: ${obj.payload?.focusDimension || 'set'}`;
    return obj.type;
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

  // ══════════════════════════════════════════════════════════════
  //  CHAT / CONVERSATION SHELL
  // ══════════════════════════════════════════════════════════════

  initChat() {
    this.addSystemMsg(
      'Talk to me about your day, what you\'re working through, or what you\'d like to release. ' +
      'I\'ll listen and help you grow.'
    );
  },

  async send() {
    const input = document.getElementById('input');
    const text = input.value.trim();
    if (!text) return;
    input.value = '';
    input.style.height = '42px';
    document.getElementById('send-btn').disabled = true;

    this.addUserMsg(text);

    try {
      const result = await this.processMessage(text);
      this.addAssistantMsg(result);
      this.renderDashboard(); // refresh dashboard with new objects
    } catch (err) {
      this.addSystemMsg(`Something went wrong: ${err.message}`);
    }
  },

  async processMessage(message) {
    const systemPrompt = this.buildSystemPrompt();
    const messages = [
      { role: 'system', content: systemPrompt },
      ...this.history.slice(-20),
      { role: 'user', content: message },
    ];
    this.history.push({ role: 'user', content: message });

    const apiKey = localStorage.getItem('openrouter_key');
    if (!apiKey) return this.localProcess(message);

    const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://semantos.dev',
        'X-Title': 'Navigation Shell',
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

  buildSystemPrompt() {
    const objectSummary = Object.entries(this.objects)
      .map(([id, obj]) => `  ${id}: ${obj.type} — ${JSON.stringify(obj.payload).slice(0, 200)}`)
      .join('\n') || '  (none yet)';

    const dimSummary = DIMENSIONS.map(d =>
      `${d.emoji} ${d.label}: ${this.dimensionScores[d.id]}/10`
    ).join(', ');

    return `You are the Navigation shell — a warm, genuine conversational partner for consciousness development.

The user talks naturally. You:
1. Have a real conversation. Be brief, warm, honest. Not therapist-speak. Not technical.
2. Extract structured fields from what they say and create semantic objects (the user never sees these labels).
3. Reference their dimension scores and patterns when relevant.

OBJECT TYPES (internal — never show these labels to the user):
${OBJECT_TYPES}

DIMENSIONS: ${dimSummary}

PROCESS CYCLES:
${PROCESS_CYCLES.map(c => `${c.label} (${c.inquiry}): ${c.steps.map(s => s.label).join(' → ')}`).join('\n')}

CURRENT OBJECTS:
${objectSummary}

RESPONSE FORMAT — always valid JSON:
{
  "reply": "Your conversational response — warm, human, no jargon",
  "extracted": { "field": "value" },
  "actions": [
    { "type": "create", "objectType": "Release", "fields": { "rawText": "...", "themes": ["..."] } }
  ]
}

RULES:
- When the user is venting/releasing, create a Release. Extract themes and emotional valence.
- When wisdom emerges, create an Insight.
- When the user sets a goal, create an Intention.
- When patterns repeat, create or update a Pattern.
- NEVER mention LINEAR, RELEVANT, AFFINE, kernel, or consumption semantics to the user.
- NEVER show shell commands or LISP policies in your reply.
- Be honest. If they're avoiding something, gently note it.`;
  },

  localProcess(message) {
    const lower = message.toLowerCase();

    if (lower.includes('release') || lower.includes('let go') || lower.includes('i feel') || lower.includes('frustrated') || lower.includes('anxious') || lower.includes('stressed')) {
      const fields = { rawText: message, source: 'keyboard', prompt: 'freeform', valence: 0 };
      this.executeAction({ type: 'create', objectType: 'Release', fields });
      return {
        reply: 'I hear you. That\'s been released — it\'s out of you now. What themes were in there for you?',
        actions: [{ type: 'create', objectType: 'Release', fields }],
      };
    }

    if (lower.includes('intention') || lower.includes('tomorrow') || lower.includes('i will') || lower.includes('i want to')) {
      return {
        reply: 'That sounds like a clear intention. Which area of your life does it touch most? Mental, physical, spiritual, social, vocational, financial, or family?',
        actions: [],
        extracted: { possibleIntention: message },
      };
    }

    if (lower.includes('insight') || lower.includes('realised') || lower.includes('realized') || lower.includes('i see that') || lower.includes('it hit me')) {
      const fields = { content: message, source: 'writing' };
      this.executeAction({ type: 'create', objectType: 'Insight', fields });
      return {
        reply: 'That\'s a real insight. I\'ll keep that one — it might connect with patterns down the track.',
        actions: [{ type: 'create', objectType: 'Insight', fields }],
      };
    }

    if (lower.startsWith('key:')) {
      const key = message.slice(4).trim();
      localStorage.setItem('openrouter_key', key);
      return { reply: 'API key saved. I can have deeper conversations with you now.', actions: [] };
    }

    return {
      reply: 'I\'m here. Tell me more — what\'s present for you right now?',
      actions: [],
    };
  },

  executeAction(action) {
    if (action.type === 'create' && action.objectType) {
      // Route through kernel bridge if available
      if (this.kernel) {
        const objectId = this.kernel.createObject(action.objectType, action.fields || {});
        if (objectId) {
          // Sync card data
          if (this.cardManager) this.cardManager.sync();
        }
      } else {
        // Fallback: in-memory storage
        const id = `${action.objectType.toLowerCase()}-${Date.now()}`;
        const linearity = ['Release', 'Session', 'DailyReview', 'MorningIntention'].includes(action.objectType)
          ? 'LINEAR'
          : ['Intention', 'DimensionPulse'].includes(action.objectType) ? 'AFFINE' : 'RELEVANT';

        this.objects[id] = {
          id, type: action.objectType, linearity,
          payload: action.fields || {},
          createdAt: new Date().toISOString(),
          consumed: linearity === 'LINEAR',
        };
      }

      // Update dimension scores if relevant
      if (action.fields?.dimensionScores) {
        Object.assign(this.dimensionScores, action.fields.dimensionScores);
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
    let html = `<div class="msg-bubble">${this.esc(result.reply || '')}</div>`;

    // Show friendly object creation tags (no jargon)
    if (result.actions) {
      for (const action of result.actions) {
        if (action.type === 'create') {
          const { cls, icon, label } = this.friendlyTag(action.objectType);
          html += `<div class="object-tag ${cls}">${icon} ${label}</div>`;
        }
      }
    }

    el.innerHTML = html;
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

  friendlyTag(type) {
    const map = {
      Release:          { cls: 'released', icon: '↗', label: 'Released' },
      Insight:          { cls: 'kept',     icon: '✦', label: 'Insight saved' },
      Pattern:          { cls: 'kept',     icon: '🔄', label: 'Pattern noted' },
      Intention:        { cls: 'set',      icon: '🎯', label: 'Intention set' },
      DailyReview:      { cls: 'released', icon: '🌙', label: 'Review captured' },
      MorningIntention: { cls: 'set',      icon: '🌅', label: 'Intention set' },
      DimensionPulse:   { cls: 'set',      icon: '📊', label: 'Pulse recorded' },
      Session:          { cls: 'released', icon: '⏱', label: 'Session logged' },
    };
    return map[type] || { cls: 'set', icon: '•', label: type };
  },

  scrollChat() {
    const h = document.getElementById('history');
    requestAnimationFrame(() => h.scrollTop = h.scrollHeight);
  },

  // ══════════════════════════════════════════════════════════════
  //  RELEASE WRITING
  // ══════════════════════════════════════════════════════════════

  onReleaseType() {
    const text = document.getElementById('release-text').value;
    const words = text.trim() ? text.trim().split(/\s+/).length : 0;
    document.getElementById('release-wc').textContent = `${words} word${words !== 1 ? 's' : ''}`;

    // Start timer on first keystroke
    if (!this.releaseTimer && text.length > 0) {
      this.releaseSeconds = 0;
      this.releaseTimer = setInterval(() => {
        this.releaseSeconds++;
        const m = String(Math.floor(this.releaseSeconds / 60)).padStart(2, '0');
        const s = String(this.releaseSeconds % 60).padStart(2, '0');
        document.getElementById('release-timer').textContent = `${m}:${s}`;
      }, 1000);
    }
  },

  insertPrompt(text) {
    const ta = document.getElementById('release-text');
    ta.value += (ta.value ? '\n\n' : '') + text + ' ';
    ta.focus();
    this.onReleaseType();
  },

  commitRelease() {
    const text = document.getElementById('release-text').value.trim();
    if (!text) return;

    clearInterval(this.releaseTimer);
    this.releaseTimer = null;

    const fields = {
      rawText: text,
      source: 'keyboard',
      prompt: 'freeform',
      valence: 0,
    };

    if (this.kernel) {
      this.kernel.createObject('Release', fields);
      if (this.cardManager) this.cardManager.sync();
    } else {
      const id = `rel-${Date.now()}`;
      this.objects[id] = {
        id, type: 'Release', linearity: 'LINEAR',
        payload: fields,
        createdAt: new Date().toISOString(),
        consumed: true,
      };
    }

    // Reset
    document.getElementById('release-text').value = '';
    document.getElementById('release-wc').textContent = '0 words';
    document.getElementById('release-timer').textContent = '00:00';
    this.releaseSeconds = 0;

    this.closeOverlay('release');
    this.renderDashboard();

    // Send to chat for LLM processing if key is set
    if (localStorage.getItem('openrouter_key')) {
      this.history.push({ role: 'user', content: `[Release writing]: ${text}` });
      this.processMessage(`[Release writing]: ${text}`).then(result => {
        this.addAssistantMsg(result);
      });
    }
  },

  // ══════════════════════════════════════════════════════════════
  //  EVENING REVIEW
  // ══════════════════════════════════════════════════════════════

  reviewStep: 0,
  reviewData: {},

  openReview() {
    this.reviewStep = 0;
    this.reviewData = { wins: ['', '', ''], improvements: ['', '', ''], intention: '', energy: 5, mood: 5, dimensions: {} };
    this.renderReviewStep();
  },

  renderReviewStep() {
    const body = document.getElementById('review-body');
    const progress = document.getElementById('review-progress');
    const steps = 5;

    progress.innerHTML = Array.from({ length: steps }, (_, i) =>
      `<div class="progress-seg${i <= this.reviewStep ? ' done' : ''}"></div>`
    ).join('');

    switch (this.reviewStep) {
      case 0: // Wins
        body.innerHTML = `
          <div class="form-label">What went well today?</div>
          <div class="form-hint">Three things you did well, no matter how small.</div>
          ${[0,1,2].map(i => `
            <div style="display:flex;align-items:center;gap:8px">
              <span style="font-size:12px;color:var(--text-30);width:16px">${i+1}</span>
              <textarea class="form-input" rows="2" placeholder="Something that went well..."
                oninput="app.reviewData.wins[${i}]=this.value">${this.reviewData.wins[i]}</textarea>
            </div>`).join('')}
          <button class="btn btn-primary" onclick="app.nextReviewStep()">Next</button>`;
        break;

      case 1: // Improvements
        body.innerHTML = `
          <div class="form-label">What could be better?</div>
          <div class="form-hint">Three things to improve — honest, not harsh.</div>
          ${[0,1,2].map(i => `
            <div style="display:flex;align-items:center;gap:8px">
              <span style="font-size:12px;color:var(--text-30);width:16px">${i+1}</span>
              <textarea class="form-input" rows="2" placeholder="Something to improve..."
                oninput="app.reviewData.improvements[${i}]=this.value">${this.reviewData.improvements[i]}</textarea>
            </div>`).join('')}
          <div style="display:flex;gap:8px">
            <button class="btn btn-subtle" style="flex:1" onclick="app.prevReviewStep()">Back</button>
            <button class="btn btn-primary" style="flex:2" onclick="app.nextReviewStep()">Next</button>
          </div>`;
        break;

      case 2: // Energy + Mood
        body.innerHTML = `
          <div class="form-label">How are you feeling?</div>
          <div class="form-hint">Check in with your body and mind.</div>
          <div style="margin:16px 0">
            <div style="font-size:13px;color:var(--text-50);margin-bottom:8px">Energy</div>
            <div class="slider-row">
              <span class="slider-emoji">😴</span>
              <div class="slider-wrap">
                <input type="range" min="1" max="10" value="${this.reviewData.energy}"
                  oninput="app.reviewData.energy=+this.value;document.getElementById('e-val').textContent=this.value">
              </div>
              <span class="slider-val" id="e-val">${this.reviewData.energy}</span>
              <span class="slider-emoji">⚡</span>
            </div>
          </div>
          <div style="margin:16px 0">
            <div style="font-size:13px;color:var(--text-50);margin-bottom:8px">Mood</div>
            <div class="slider-row">
              <span class="slider-emoji">😔</span>
              <div class="slider-wrap">
                <input type="range" min="1" max="10" value="${this.reviewData.mood}"
                  oninput="app.reviewData.mood=+this.value;document.getElementById('m-val').textContent=this.value">
              </div>
              <span class="slider-val" id="m-val">${this.reviewData.mood}</span>
              <span class="slider-emoji">😊</span>
            </div>
          </div>
          <div style="display:flex;gap:8px">
            <button class="btn btn-subtle" style="flex:1" onclick="app.prevReviewStep()">Back</button>
            <button class="btn btn-primary" style="flex:2" onclick="app.nextReviewStep()">Next</button>
          </div>`;
        break;

      case 3: // Dimensions
        body.innerHTML = `
          <div class="form-label">Rate your dimensions</div>
          <div class="form-hint">How did each area of life go today?</div>
          ${DIMENSIONS.map(d => {
            const val = this.reviewData.dimensions[d.id] || this.dimensionScores[d.id] || 5;
            return `<div style="margin-bottom:12px">
              <div style="display:flex;align-items:center;gap:8px;margin-bottom:4px">
                <span style="font-size:16px">${d.emoji}</span>
                <span style="font-size:13px;color:var(--text-70)">${d.label}</span>
              </div>
              <div class="slider-row">
                <div class="slider-wrap">
                  <input type="range" min="1" max="10" value="${val}"
                    oninput="app.reviewData.dimensions['${d.id}']=+this.value;this.nextElementSibling.textContent=this.value">
                  <span style="display:none"></span>
                </div>
                <span class="slider-val" id="dim-${d.id}-val">${val}</span>
              </div>
            </div>`;
          }).join('')}
          <div style="display:flex;gap:8px">
            <button class="btn btn-subtle" style="flex:1" onclick="app.prevReviewStep()">Back</button>
            <button class="btn btn-primary" style="flex:2" onclick="app.nextReviewStep()">Next</button>
          </div>`;

        // Fix slider value display
        setTimeout(() => {
          DIMENSIONS.forEach(d => {
            const slider = document.querySelector(`#dim-${d.id}-val`)?.parentElement?.querySelector('input[type=range]');
            if (slider) {
              slider.oninput = function() {
                app.reviewData.dimensions[d.id] = +this.value;
                document.getElementById(`dim-${d.id}-val`).textContent = this.value;
              };
            }
          });
        }, 50);
        break;

      case 4: // Tomorrow intention
        body.innerHTML = `
          <div class="form-label">What about tomorrow?</div>
          <div class="form-hint">One intention to carry forward.</div>
          <textarea class="form-input" rows="3" placeholder="Tomorrow I will..."
            oninput="app.reviewData.intention=this.value">${this.reviewData.intention}</textarea>
          <div style="display:flex;gap:8px">
            <button class="btn btn-subtle" style="flex:1" onclick="app.prevReviewStep()">Back</button>
            <button class="btn btn-primary" style="flex:2" onclick="app.saveReview()">Save Review</button>
          </div>`;
        break;
    }
  },

  nextReviewStep() { this.reviewStep++; this.renderReviewStep(); },
  prevReviewStep() { this.reviewStep--; this.renderReviewStep(); },

  saveReview() {
    // Update dimension scores
    if (Object.keys(this.reviewData.dimensions).length > 0) {
      Object.assign(this.dimensionScores, this.reviewData.dimensions);
    }

    const fields = {
      date: new Date().toISOString().split('T')[0],
      win1: (this.reviewData.wins[0] || '').trim(),
      win2: (this.reviewData.wins[1] || '').trim(),
      win3: (this.reviewData.wins[2] || '').trim(),
      improve1: (this.reviewData.improvements[0] || '').trim(),
      improve2: (this.reviewData.improvements[1] || '').trim(),
      improve3: (this.reviewData.improvements[2] || '').trim(),
      tomorrowIntention: this.reviewData.intention,
      energyLevel: this.reviewData.energy,
      moodLevel: this.reviewData.mood,
    };

    if (this.kernel) {
      this.kernel.createObject('DailyReview', fields);
      if (this.cardManager) this.cardManager.sync();
    } else {
      const id = `review-${Date.now()}`;
      this.objects[id] = {
        id, type: 'DailyReview', linearity: 'LINEAR',
        payload: fields,
        createdAt: new Date().toISOString(),
        consumed: true,
      };
    }

    this.streak++;
    this.closeOverlay('review');
    this.renderDashboard();
  },

  // ══════════════════════════════════════════════════════════════
  //  MORNING INTENTION
  // ══════════════════════════════════════════════════════════════

  intentionStep: 0,
  intentionData: {},

  openIntention() {
    this.intentionStep = 0;
    this.intentionData = { dimension: null, intention: '', action: '' };
    this.renderIntentionStep();
  },

  renderIntentionStep() {
    const body = document.getElementById('intention-body');

    if (this.intentionStep === 0) {
      body.innerHTML = `
        <div class="form-label">Pick your focus</div>
        <div class="form-hint">Which dimension calls for attention today?</div>
        <div class="dim-grid">
          ${DIMENSIONS.map(d => `
            <div class="dim-pick${this.intentionData.dimension === d.id ? ' selected' : ''}"
              onclick="app.pickDimension('${d.id}')">
              <span class="dp-emoji">${d.emoji}</span>
              <span class="dp-label">${d.label}</span>
            </div>`).join('')}
        </div>
        <button class="btn btn-primary" style="margin-top:16px"
          ${this.intentionData.dimension ? '' : 'disabled'}
          onclick="app.intentionStep=1;app.renderIntentionStep()">Next</button>`;
    } else {
      const dim = DIMENSIONS.find(d => d.id === this.intentionData.dimension);
      body.innerHTML = `
        <div style="display:inline-flex;align-items:center;gap:6px;padding:6px 14px;border-radius:var(--radius-pill);border:1px solid var(--blue);color:var(--blue);font-size:13px;margin-bottom:16px">
          ${dim.emoji} ${dim.label}
        </div>
        <div class="form-label">Your intention</div>
        <div class="form-hint">What do you intend to bring to ${dim.label.toLowerCase()} today?</div>
        <textarea class="form-input" rows="3" placeholder="Today I intend to..."
          oninput="app.intentionData.intention=this.value">${this.intentionData.intention}</textarea>
        <div class="form-label" style="margin-top:8px">Concrete action</div>
        <div class="form-hint">One specific thing you'll do.</div>
        <textarea class="form-input" rows="2" placeholder="I will..."
          oninput="app.intentionData.action=this.value">${this.intentionData.action}</textarea>
        <div style="display:flex;gap:8px">
          <button class="btn btn-subtle" style="flex:1" onclick="app.intentionStep=0;app.renderIntentionStep()">Back</button>
          <button class="btn btn-primary" style="flex:2" onclick="app.saveIntention()">Set Intention</button>
        </div>`;
    }
  },

  pickDimension(id) {
    this.intentionData.dimension = id;
    this.renderIntentionStep();
  },

  saveIntention() {
    // Map old dimension IDs to Navigation enum format
    const dimMap = {
      mental: 'MENTAL', physical: 'PHYSICAL', spiritual: 'SPIRITUAL',
      social: 'SOCIAL', vocational: 'VOCATIONAL', financial: 'FINANCIAL', familial: 'FAMILIAL',
    };

    const fields = {
      date: new Date().toISOString().split('T')[0],
      todayIntention: this.intentionData.intention,
      concreteAction: this.intentionData.action,
      primaryDimension: dimMap[this.intentionData.dimension] || this.intentionData.dimension,
    };

    if (this.kernel) {
      this.kernel.createObject('MorningIntention', fields);
      if (this.cardManager) this.cardManager.sync();
    } else {
      const id = `intention-${Date.now()}`;
      this.objects[id] = {
        id, type: 'MorningIntention', linearity: 'LINEAR',
        payload: fields,
        createdAt: new Date().toISOString(),
        consumed: true,
      };
    }

    this.closeOverlay('intention');
    this.renderDashboard();
  },

  // ══════════════════════════════════════════════════════════════
  //  OVERLAYS
  // ══════════════════════════════════════════════════════════════

  openOverlay(name) {
    if (name === 'review') this.openReview();
    if (name === 'intention') this.openIntention();
    document.getElementById(`${name}-overlay`).classList.add('open');
  },

  closeOverlay(name) {
    document.getElementById(`${name}-overlay`).classList.remove('open');
    if (name === 'release') {
      clearInterval(this.releaseTimer);
      this.releaseTimer = null;
    }
  },

  // ══════════════════════════════════════════════════════════════
  //  PROCESS MAP
  // ══════════════════════════════════════════════════════════════

  renderProcessMap() {
    const c = document.getElementById('process-content');
    let html = `
      <div class="process-header">The Process</div>
      <div class="process-sub">Five cycles that build on each other. Release and receive at every depth.</div>
    `;

    for (const cycle of PROCESS_CYCLES) {
      const stepsHtml = cycle.steps.map((s, i) => {
        const cls = s.release ? 'release' : s.receive ? 'receive' : 'neutral';
        const arrow = i < cycle.steps.length - 1 ? '<span class="flow-arrow"> → </span>' : '';
        return `<span class="step-chip ${cls}">${s.label}</span>${arrow}`;
      }).join('') + (cycle.recursive ? '<span class="flow-arrow"> ↻</span>' : '');

      html += `
        <div class="cycle-card" style="background:${cycle.color}08;border-left-color:${cycle.color}"
          onclick="app.startCycleChat('${cycle.id}')">
          <div class="cycle-title" style="color:${cycle.color}">${cycle.label}</div>
          <div class="cycle-inquiry">${cycle.inquiry}</div>
          <div class="cycle-desc">${cycle.description}</div>
          <div class="cycle-flow">${stepsHtml}</div>
        </div>`;
    }

    c.innerHTML = html;
  },

  startCycleChat(cycleId) {
    const cycle = PROCESS_CYCLES.find(c => c.id === cycleId);
    if (!cycle) return;
    const input = document.getElementById('input');
    input.value = `I want to work on the ${cycle.label} process`;
    input.dispatchEvent(new Event('input'));
    this.switchView('chat');
    input.focus();
  },

  // ══════════════════════════════════════════════════════════════
  //  INSIGHTS
  // ══════════════════════════════════════════════════════════════

  insightTab: 'insights',

  renderInsights() {
    const c = document.getElementById('insights-content');
    const allObjects = this.kernel ? this.kernel.listObjects() : Object.values(this.objects);
    const insights = allObjects.filter(o => (o.type || o.type) === 'Insight');
    const patterns = allObjects.filter(o => (o.type || o.type) === 'Pattern');

    let html = `
      <div class="insight-tabs">
        <button class="insight-tab${this.insightTab === 'insights' ? ' active' : ''}" onclick="app.insightTab='insights';app.renderInsights()">Insights</button>
        <button class="insight-tab${this.insightTab === 'patterns' ? ' active' : ''}" onclick="app.insightTab='patterns';app.renderInsights()">Patterns</button>
        <button class="insight-tab${this.insightTab === 'connections' ? ' active' : ''}" onclick="app.insightTab='connections';app.renderInsights()">Connections</button>
      </div>
    `;

    if (this.insightTab === 'insights') {
      if (insights.length === 0) {
        html += '<div class="empty-state"><span class="empty-icon">✦</span>Insights will appear here as you talk, release, and reflect.</div>';
      } else {
        for (const ins of insights.reverse()) {
          const data = ins.fields || ins.payload || {};
          const source = data.source || 'writing';
          const ts = ins.createdAt;
          const time = typeof ts === 'number' ? this.timeAgoMs(ts) : this.timeAgo(ts);
          html += `
            <div class="insight-card">
              <div class="insight-content">${this.esc(data.content || '')}</div>
              <div class="insight-meta">
                <span class="source-chip ${source}">${source}</span>
                <span class="time-ago">${time}</span>
              </div>
            </div>`;
        }
      }
    } else if (this.insightTab === 'patterns') {
      if (patterns.length === 0) {
        html += '<div class="empty-state"><span class="empty-icon">🔄</span>Patterns emerge from repeated releases and conversations over time.</div>';
      } else {
        for (const pat of patterns) {
          const data = pat.fields || pat.payload || {};
          const strength = (data.strength || 0) * 100;
          html += `
            <div class="insight-card">
              <div class="insight-content">${this.esc(data.description || '')}</div>
              <div class="pattern-bar-wrap"><div class="pattern-bar" style="width:${strength}%"></div></div>
              <div class="pattern-count">${data.occurrenceCount || data.occurrences || 0}× observed</div>
            </div>`;
        }
      }
    } else {
      // Connections (Paskian graph) — will populate from node
      html += '<div class="empty-state"><span class="empty-icon">🔗</span>Connections between your dimensions will surface as the Paskian graph learns from your activity.</div>';
    }

    c.innerHTML = html;
  },

  // ══════════════════════════════════════════════════════════════
  //  VIEW SWITCHING
  // ══════════════════════════════════════════════════════════════

  switchView(name) {
    document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
    document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
    document.getElementById(`${name}-view`).classList.add('active');
    document.querySelector(`[data-view="${name}"]`).classList.add('active');

    if (name === 'insights') this.renderInsights();
    if (name === 'home') this.renderDashboard();
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

  // ── Input Helpers ──

  handleKey(e) {
    const input = document.getElementById('input');
    if (input.value.startsWith('key:') && e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      this.send();
      return;
    }
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      this.send();
    }
  },

  autoGrow(el) {
    el.style.height = '42px';
    el.style.height = Math.min(el.scrollHeight, 120) + 'px';
  },

  esc(str) {
    return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  },
};

// Boot
document.addEventListener('DOMContentLoaded', () => app.init());

```
