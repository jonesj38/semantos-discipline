---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/bsv-app/index.html
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.725782+00:00
---

# archive/apps-navigation_app/bsv-app/index.html

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>Navigator</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    :root {
      --bg: #0f0f23;
      --surface: rgba(255,255,255,0.05);
      --surface-hover: rgba(255,255,255,0.08);
      --surface-active: rgba(255,255,255,0.12);
      --text: rgba(255,255,255,0.92);
      --text-70: rgba(255,255,255,0.7);
      --text-50: rgba(255,255,255,0.5);
      --text-30: rgba(255,255,255,0.3);
      --text-10: rgba(255,255,255,0.1);
      --blue: #3b82f6;
      --purple: #8b5cf6;
      --red: #ef4444;
      --green: #4ade80;
      --amber: #f59e0b;
      --orange: #f97316;
      --radius: 16px;
      --radius-sm: 12px;
      --radius-pill: 20px;
    }
    html, body {
      height: 100%;
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', system-ui, sans-serif;
      -webkit-font-smoothing: antialiased;
      overflow: hidden;
    }

    /* ── Layout ── */
    .app {
      display: flex; flex-direction: column;
      height: 100%; max-width: 480px; margin: 0 auto;
    }

    /* ── Status Bar ── */
    .status-bar {
      display: flex; align-items: center; justify-content: space-between;
      padding: 8px 16px; font-size: 11px; color: var(--text-30);
    }
    .status-bar .dot { display: inline-block; width: 6px; height: 6px; border-radius: 50%; margin-right: 4px; }
    .dot.on { background: var(--green); }
    .dot.off { background: var(--text-30); }

    /* ── Views ── */
    .view { display: none; flex: 1; overflow-y: auto; overflow-x: hidden; }
    .view.active { display: flex; flex-direction: column; }
    .view::-webkit-scrollbar { width: 0; }

    /* ── Bottom Nav ── */
    .nav {
      display: flex; border-top: 1px solid var(--text-10);
      background: var(--bg); padding: 6px 0 env(safe-area-inset-bottom, 8px);
    }
    .nav-item {
      flex: 1; display: flex; flex-direction: column; align-items: center;
      padding: 8px 4px; font-size: 10px; color: var(--text-30);
      border: none; background: none; cursor: pointer; gap: 4px;
      transition: color 0.2s;
    }
    .nav-item.active { color: var(--blue); }
    .nav-item svg { width: 22px; height: 22px; }

    /* ── Dashboard ── */
    .dash-pad { padding: 0 16px 16px; gap: 0; }

    .card {
      background: var(--surface); border-radius: var(--radius);
      padding: 16px; margin-bottom: 12px;
    }
    .card-title {
      font-size: 13px; font-weight: 600; color: var(--text-50);
      text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 12px;
    }

    /* ── Command Bar ── */
    .command-bar {
      display: flex; align-items: flex-end; gap: 8px;
      padding: 12px 16px; background: var(--bg);
      position: sticky; top: 0; z-index: 10;
    }
    .command-bar textarea {
      flex: 1; background: var(--surface); color: var(--text);
      border: 1px solid var(--text-10); border-radius: 20px; padding: 10px 16px;
      font-size: 15px; font-family: inherit; resize: none;
      height: 42px; max-height: 120px; line-height: 1.4;
      outline: none; transition: border-color 0.2s;
    }
    .command-bar textarea:focus { border-color: var(--blue); }
    .command-bar textarea::placeholder { color: var(--text-30); }

    /* ── Lens Strip ── */
    .lens-strip {
      display: flex; gap: 6px; padding: 8px 16px 12px;
      overflow-x: auto; -webkit-overflow-scrolling: touch;
    }
    .lens-strip::-webkit-scrollbar { height: 0; }
    .lens-pill {
      display: flex; align-items: center; gap: 6px;
      padding: 8px 14px; border-radius: var(--radius-pill);
      border: 1px solid var(--text-10); background: none;
      color: var(--text-50); font-size: 13px; font-weight: 500;
      cursor: pointer; white-space: nowrap;
      transition: background 0.2s, border-color 0.2s, color 0.2s;
    }
    .lens-pill:active { background: var(--surface-active); }
    .lens-pill.active {
      background: var(--lens-color, var(--blue));
      border-color: var(--lens-color, var(--blue));
      color: #fff;
    }
    .lens-pill .lens-emoji { font-size: 16px; }
    .lens-pill.all-pill.active {
      background: var(--surface-active);
      border-color: var(--text-30);
      color: var(--text);
    }

    /* ── Filtered Objects ── */
    .objects-area { padding: 0 16px 16px; }
    .object-card {
      background: var(--surface); border-radius: var(--radius);
      padding: 14px 16px; margin-bottom: 10px;
      border-left: 3px solid var(--obj-color, var(--text-10));
      transition: background 0.2s;
    }
    .object-card:active { background: var(--surface-hover); }
    .obj-header {
      display: flex; align-items: center; gap: 8px; margin-bottom: 4px;
    }
    .obj-type {
      font-size: 11px; font-weight: 600; text-transform: uppercase;
      letter-spacing: 0.5px; color: var(--text-30);
    }
    .obj-time { font-size: 11px; color: var(--text-30); margin-left: auto; }
    .obj-content { font-size: 14px; line-height: 1.5; color: var(--text-70); }
    .obj-lens-tags { display: flex; gap: 4px; margin-top: 6px; flex-wrap: wrap; }
    .obj-lens-tag {
      font-size: 10px; padding: 2px 8px; border-radius: var(--radius-pill);
      background: var(--surface-hover); color: var(--text-30);
    }

    /* ── Chat / Shell ── */
    .chat-view { padding: 0; }
    .chat-history {
      flex: 1; overflow-y: auto; padding: 12px 16px; gap: 8px;
      display: flex; flex-direction: column;
    }
    .chat-history::-webkit-scrollbar { width: 0; }
    .msg { display: flex; margin-bottom: 4px; }
    .msg.user { justify-content: flex-end; }
    .msg-bubble {
      max-width: 85%; padding: 10px 14px; border-radius: 18px;
      font-size: 15px; line-height: 1.5; white-space: pre-wrap;
    }
    .msg.user .msg-bubble {
      background: var(--blue); color: #fff;
      border-bottom-right-radius: 4px;
    }
    .msg.assistant .msg-bubble {
      background: var(--surface); color: var(--text);
      border-bottom-left-radius: 4px;
    }
    .msg.system .msg-bubble {
      background: none; color: var(--text-50); font-size: 13px;
      padding: 6px 2px;
    }

    /* Object creation feedback — friendly, not technical */
    .object-tag {
      display: inline-flex; align-items: center; gap: 4px;
      font-size: 12px; padding: 4px 10px; border-radius: var(--radius-pill);
      margin-top: 6px;
    }
    .object-tag.released {
      background: rgba(239,68,68,0.12); color: var(--red);
    }
    .object-tag.kept {
      background: rgba(139,92,246,0.12); color: var(--purple);
    }
    .object-tag.set {
      background: rgba(59,130,246,0.12); color: var(--blue);
    }

    /* Chat input area */
    .chat-input-area {
      display: flex; align-items: flex-end; gap: 8px;
      padding: 8px 12px; border-top: 1px solid var(--text-10);
      background: var(--bg);
    }
    .chat-input-area textarea {
      flex: 1; background: var(--surface); color: var(--text);
      border: none; border-radius: 20px; padding: 10px 16px;
      font-size: 15px; font-family: inherit; resize: none;
      height: 42px; max-height: 120px; line-height: 1.4;
      outline: none;
    }
    .chat-input-area textarea::placeholder { color: var(--text-30); }
    .icon-btn {
      width: 42px; height: 42px; border-radius: 50%;
      border: none; background: var(--surface); color: var(--text-50);
      cursor: pointer; display: flex; align-items: center; justify-content: center;
      transition: background 0.2s, color 0.2s; flex-shrink: 0;
    }
    .icon-btn:active { background: var(--surface-active); }
    .icon-btn.primary { background: var(--blue); color: #fff; }
    .icon-btn.primary:disabled { opacity: 0.3; }
    .icon-btn.listening { background: var(--red); color: #fff; animation: pulse 1.5s infinite; }
    @keyframes pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.6; } }

    .time-ago { font-size: 11px; color: var(--text-30); }

    /* Empty state */
    .empty-state {
      display: flex; flex-direction: column; align-items: center;
      justify-content: center; padding: 40px 20px; color: var(--text-30);
      font-size: 14px; text-align: center; gap: 8px;
    }
    .empty-icon { font-size: 32px; opacity: 0.5; }

  </style>
</head>
<body>
<div class="app">

  <!-- Status bar -->
  <div class="status-bar">
    <span>Navigator</span>
    <span>
      <span class="dot off" id="kernel-dot"></span>kernel
      <span class="dot off" id="node-dot" style="margin-left:8px"></span>node
      <span class="dot off" id="cwi-dot" style="margin-left:8px"></span>wallet
    </span>
  </div>

  <!-- ═══ Objects View ═══ -->
  <div class="view" id="home-view" style="gap:0;">
    <!-- Command Bar -->
    <div class="command-bar">
      <button class="icon-btn" id="voice-btn" onclick="app.toggleVoice()" title="Voice">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 1a3 3 0 00-3 3v8a3 3 0 006 0V4a3 3 0 00-3-3z"/><path d="M19 10v2a7 7 0 01-14 0v-2"/><line x1="12" y1="19" x2="12" y2="23"/><line x1="8" y1="23" x2="16" y2="23"/></svg>
      </button>
      <textarea id="input" rows="1" placeholder="Say something or type a command..."
        oninput="app.autoGrow(this)"
        onkeydown="app.handleKey(event)"></textarea>
      <button class="icon-btn primary" id="send-btn" onclick="app.send()" disabled>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><line x1="22" y1="2" x2="11" y2="13"/><polygon points="22 2 15 22 11 13 2 9 22 2"/></svg>
      </button>
    </div>

    <!-- Lens Strip -->
    <div class="lens-strip" id="lens-strip">
      <!-- Filled by JS -->
    </div>

    <!-- Conversation + Objects -->
    <div id="conversation-area" style="padding:0 16px;">
      <div id="history" class="chat-history" style="padding:0;"></div>
    </div>
    <div class="objects-area" id="objects-area">
      <!-- Filtered objects by active lens -->
    </div>
  </div>

  <!-- ═══ Extensions View ═══ -->
  <div class="view active" id="extensions-view">
    <div style="padding:16px;" id="extensions-content"></div>
  </div>

  <!-- ═══ Activity View ═══ -->
  <div class="view" id="activity-view">
    <div style="padding:16px;" id="activity-content"></div>
  </div>

  <!-- ═══ Bottom Nav ═══ -->
  <nav class="nav">
    <button class="nav-item active" data-view="extensions" onclick="app.switchView('extensions')">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/><rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/></svg>
      Extensions
    </button>
    <button class="nav-item" data-view="home" onclick="app.switchView('home')">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>
      Objects
    </button>
    <button class="nav-item" data-view="activity" onclick="app.switchView('activity')">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg>
      Activity
    </button>
  </nav>


</div>

<script src="kernel-bridge.js"></script>
<script src="navigator.js"></script>
</body>
</html>

```
