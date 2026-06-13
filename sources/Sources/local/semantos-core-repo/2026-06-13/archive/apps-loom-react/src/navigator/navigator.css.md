---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/navigator/navigator.css
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.942451+00:00
---

# archive/apps-loom-react/src/navigator/navigator.css

```css
/* ── Navigator Theme (coexists with Tailwind) ── */
:root {
  --nav-bg: #0f0f23;
  --nav-surface: rgba(255,255,255,0.05);
  --nav-surface-hover: rgba(255,255,255,0.08);
  --nav-surface-active: rgba(255,255,255,0.12);
  --nav-text: rgba(255,255,255,0.92);
  --nav-text-70: rgba(255,255,255,0.7);
  --nav-text-50: rgba(255,255,255,0.5);
  --nav-text-30: rgba(255,255,255,0.3);
  --nav-text-10: rgba(255,255,255,0.1);
  --nav-blue: #3b82f6;
  --nav-purple: #8b5cf6;
  --nav-red: #ef4444;
  --nav-green: #4ade80;
  --nav-amber: #f59e0b;
  --nav-radius: 16px;
  --nav-radius-sm: 12px;
  --nav-radius-pill: 20px;
}

/* ── Status Bar ── */
.nav-status-bar {
  display: flex; align-items: center; justify-content: space-between;
  padding: 8px 16px; font-size: 11px; color: var(--nav-text-30);
}
.nav-dot {
  display: inline-block; width: 6px; height: 6px; border-radius: 50%; margin-right: 4px;
  background: var(--nav-text-30);
}
.nav-dot.on { background: var(--nav-green); }

/* ── Bottom Nav ── */
.bottom-nav {
  display: flex; border-top: 1px solid var(--nav-text-10);
  background: var(--nav-bg); padding: 6px 0 env(safe-area-inset-bottom, 8px);
}
.bottom-nav-item {
  flex: 1; display: flex; flex-direction: column; align-items: center;
  padding: 8px 4px; font-size: 10px; color: var(--nav-text-30);
  border: none; background: none; cursor: pointer; gap: 4px;
  transition: color 0.2s;
}
.bottom-nav-item.active { color: var(--nav-blue); }
.bottom-nav-item svg { width: 22px; height: 22px; }

/* ── Cards ── */
.nav-card {
  background: var(--nav-surface); border-radius: var(--nav-radius);
  padding: 16px; margin-bottom: 12px;
}
.nav-card-title {
  font-size: 13px; font-weight: 600; color: var(--nav-text-50);
  text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 12px;
}

/* ── Greeting ── */
.nav-greeting { font-size: 24px; font-weight: 700; color: var(--nav-text); }
.nav-greeting-sub { font-size: 14px; color: var(--nav-text-50); margin-top: 4px; }
.nav-streak { display: inline-block; font-size: 13px; color: var(--nav-amber); padding: 4px 12px; border-radius: var(--nav-radius-pill); background: rgba(245,158,11,0.12); }

/* ── Quick Actions ── */
.nav-quick-actions { display: flex; gap: 8px; margin-top: 16px; flex-wrap: wrap; }
.nav-quick-btn {
  display: flex; align-items: center; gap: 6px;
  padding: 10px 16px; border-radius: var(--nav-radius-pill);
  border: 1px solid var(--nav-text-10); background: none;
  color: var(--nav-text-70); font-size: 13px; font-weight: 500;
  cursor: pointer; transition: background 0.2s;
}
.nav-quick-btn:active { background: var(--nav-surface-active); }

/* ── Dimension Bars ── */
.nav-dim-row { display: flex; align-items: center; gap: 8px; padding: 6px 0; }
.nav-dim-emoji { font-size: 16px; }
.nav-dim-label { font-size: 13px; color: var(--nav-text-70); width: 50px; }
.nav-dim-bar-wrap { flex: 1; height: 6px; background: var(--nav-surface); border-radius: 3px; overflow: hidden; }
.nav-dim-bar { height: 100%; border-radius: 3px; transition: width 0.3s; }
.nav-dim-score { font-size: 13px; font-weight: 600; width: 24px; text-align: right; }

/* ── Spinning Cards ── */
.dimension-group { margin: 16px 0; }
.group-label { font-size: 12px; font-weight: 600; color: var(--nav-text-30); text-transform: uppercase; letter-spacing: 1px; margin-bottom: 8px; }
.card-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap: 10px; }

.spinning-card {
  background: var(--nav-surface); border-radius: var(--nav-radius);
  padding: 14px; cursor: pointer; min-height: 120px;
  transition: transform 0.3s;
  border: 1px solid var(--nav-text-10);
}
.spinning-card:active { transform: scale(0.97); }
.spinning-card.spin { animation: card-spin 0.6s ease; }
@keyframes card-spin {
  0% { transform: rotateY(0deg); }
  50% { transform: rotateY(90deg); }
  100% { transform: rotateY(0deg); }
}

.card-header { display: flex; align-items: center; gap: 8px; margin-bottom: 10px; }
.card-emoji { font-size: 20px; }
.card-label { font-size: 13px; font-weight: 600; color: var(--nav-text-70); }
.card-score-bar { height: 4px; background: var(--nav-surface-active); border-radius: 2px; overflow: hidden; margin-bottom: 6px; }
.card-score-fill { height: 100%; border-radius: 2px; }
.card-score-text { font-size: 22px; font-weight: 700; color: var(--nav-text); }
.card-score-max { font-size: 13px; color: var(--nav-text-30); }
.card-stat { font-size: 11px; color: var(--nav-text-30); margin-top: 4px; }
.card-entry { display: flex; flex-direction: column; gap: 2px; padding: 6px 0; border-bottom: 1px solid var(--nav-text-10); }
.card-entry:last-child { border-bottom: none; }
.card-entry-tag { font-size: 10px; color: var(--nav-text-50); }
.card-entry-text { font-size: 12px; color: var(--nav-text-70); line-height: 1.4; }
.card-entry-time { font-size: 10px; color: var(--nav-text-30); }
.card-empty { font-size: 12px; color: var(--nav-text-30); padding: 12px 0; }

.card-tab-bar { display: flex; gap: 4px; margin-bottom: 8px; }
.card-tab { font-size: 11px; padding: 4px 8px; border-radius: var(--nav-radius-pill); border: none; background: none; color: var(--nav-text-30); cursor: pointer; }
.card-tab.active { background: var(--nav-surface-active); color: var(--nav-text-70); }

/* ── Chat Bubbles ── */
.nav-msg { display: flex; margin-bottom: 4px; }
.nav-msg.user { justify-content: flex-end; }
.nav-msg-bubble {
  max-width: 85%; padding: 10px 14px; border-radius: 18px;
  font-size: 15px; line-height: 1.5; white-space: pre-wrap;
}
.nav-msg.user .nav-msg-bubble {
  background: var(--nav-blue); color: #fff;
  border-bottom-right-radius: 4px;
}
.nav-msg.assistant .nav-msg-bubble {
  background: var(--nav-surface); color: var(--nav-text);
  border-bottom-left-radius: 4px;
}
.nav-msg.system .nav-msg-bubble {
  background: none; color: var(--nav-text-50); font-size: 13px;
  padding: 6px 2px;
}

.nav-object-tag {
  display: inline-flex; align-items: center; gap: 4px;
  font-size: 12px; padding: 4px 10px; border-radius: var(--nav-radius-pill);
  margin-top: 6px;
}
.nav-object-tag.released { background: rgba(239,68,68,0.12); color: var(--nav-red); }
.nav-object-tag.kept { background: rgba(139,92,246,0.12); color: var(--nav-purple); }
.nav-object-tag.set { background: rgba(59,130,246,0.12); color: var(--nav-blue); }

/* ── Chat Input ── */
.nav-chat-input-area {
  display: flex; align-items: flex-end; gap: 8px;
  padding: 8px 12px; border-top: 1px solid var(--nav-text-10);
  background: var(--nav-bg);
}
.nav-chat-textarea {
  flex: 1; background: var(--nav-surface); color: var(--nav-text);
  border: none; border-radius: 20px; padding: 10px 16px;
  font-size: 15px; font-family: inherit; resize: none;
  height: 42px; max-height: 120px; line-height: 1.4;
  outline: none;
}
.nav-chat-textarea::placeholder { color: var(--nav-text-30); }

.nav-icon-btn {
  width: 42px; height: 42px; border-radius: 50%;
  border: none; background: var(--nav-surface); color: var(--nav-text-50);
  cursor: pointer; display: flex; align-items: center; justify-content: center;
  transition: background 0.2s, color 0.2s; flex-shrink: 0;
}
.nav-icon-btn:active { background: var(--nav-surface-active); }
.nav-icon-btn.primary { background: var(--nav-blue); color: #fff; }
.nav-icon-btn.primary:disabled { opacity: 0.3; }
.nav-icon-btn.listening { background: var(--nav-red); color: #fff; animation: nav-pulse 1.5s infinite; }
@keyframes nav-pulse { 0%,100% { opacity: 1; } 50% { opacity: 0.6; } }

/* ── Process Map ── */
.cycle-card {
  border-radius: var(--nav-radius); padding: 16px; margin-bottom: 12px;
  border-left: 4px solid; cursor: pointer;
  transition: background 0.2s;
}
.cycle-card:active { background: var(--nav-surface-active); }
.cycle-title { font-size: 16px; font-weight: 700; margin-bottom: 4px; }
.cycle-inquiry { font-size: 14px; font-style: italic; color: var(--nav-text-50); margin-bottom: 6px; }
.cycle-desc { font-size: 13px; color: var(--nav-text-50); margin-bottom: 10px; line-height: 1.5; }
.cycle-flow { display: flex; flex-wrap: wrap; gap: 4px; align-items: center; }
.step-chip {
  font-size: 11px; padding: 4px 10px; border-radius: var(--nav-radius-pill);
  background: var(--nav-surface); color: var(--nav-text-50);
}
.step-chip.release { background: rgba(239,68,68,0.15); color: var(--nav-red); }
.step-chip.receive { background: rgba(74,222,128,0.15); color: var(--nav-green); }
.flow-arrow { color: var(--nav-text-30); font-size: 12px; }

/* ── Insights ── */
.insight-tabs { display: flex; gap: 4px; margin-bottom: 16px; }
.insight-tab {
  font-size: 13px; padding: 8px 16px; border-radius: var(--nav-radius-pill);
  border: 1px solid var(--nav-text-10); background: none;
  color: var(--nav-text-50); cursor: pointer; transition: all 0.2s;
}
.insight-tab.active { background: var(--nav-surface-active); border-color: var(--nav-text-30); color: var(--nav-text); }

.insight-card {
  background: var(--nav-surface); border-radius: var(--nav-radius);
  padding: 14px 16px; margin-bottom: 10px;
}
.insight-content { font-size: 14px; line-height: 1.5; color: var(--nav-text-70); }
.insight-meta { display: flex; align-items: center; gap: 8px; margin-top: 8px; }
.source-chip {
  font-size: 10px; padding: 2px 8px; border-radius: var(--nav-radius-pill);
  background: var(--nav-surface-hover); color: var(--nav-text-30);
}
.pattern-bar-wrap { height: 4px; background: var(--nav-surface-active); border-radius: 2px; margin-top: 8px; overflow: hidden; }
.pattern-bar { height: 100%; background: var(--nav-purple); border-radius: 2px; }
.pattern-count { font-size: 11px; color: var(--nav-text-30); margin-top: 4px; }

.nav-empty-state {
  display: flex; flex-direction: column; align-items: center;
  justify-content: center; padding: 40px 20px; color: var(--nav-text-30);
  font-size: 14px; text-align: center; gap: 8px;
}
.nav-empty-icon { font-size: 32px; opacity: 0.5; }

/* ── Overlays ── */
.nav-overlay {
  position: fixed; inset: 0; z-index: 100;
  background: var(--nav-bg); color: var(--nav-text);
  display: flex; flex-direction: column;
  max-width: 480px; margin: 0 auto;
  transform: translateY(100%);
  transition: transform 0.3s ease;
}
.nav-overlay.open { transform: translateY(0); }
.nav-overlay-header {
  display: flex; align-items: center; justify-content: space-between;
  padding: 16px; border-bottom: 1px solid var(--nav-text-10);
}
.nav-overlay-title { font-size: 18px; font-weight: 700; }
.nav-overlay-close {
  width: 32px; height: 32px; border-radius: 50%;
  border: none; background: var(--nav-surface); color: var(--nav-text-50);
  cursor: pointer; font-size: 18px; display: flex; align-items: center; justify-content: center;
}
.nav-overlay-body { flex: 1; overflow-y: auto; padding: 16px; }

/* ── Form Elements ── */
.nav-form-label { font-size: 16px; font-weight: 600; color: var(--nav-text); margin-bottom: 6px; }
.nav-form-hint { font-size: 13px; color: var(--nav-text-50); margin-bottom: 12px; }
.nav-form-input {
  width: 100%; background: var(--nav-surface); color: var(--nav-text);
  border: 1px solid var(--nav-text-10); border-radius: var(--nav-radius-sm);
  padding: 10px 14px; font-size: 15px; font-family: inherit;
  resize: none; outline: none; margin-bottom: 12px;
  transition: border-color 0.2s;
}
.nav-form-input:focus { border-color: var(--nav-blue); }

.nav-btn {
  display: inline-flex; align-items: center; justify-content: center;
  padding: 12px 24px; border-radius: var(--nav-radius-pill);
  font-size: 15px; font-weight: 600; border: none; cursor: pointer;
  transition: background 0.2s; width: 100%;
}
.nav-btn-primary { background: var(--nav-blue); color: #fff; }
.nav-btn-primary:disabled { opacity: 0.3; }
.nav-btn-subtle { background: var(--nav-surface); color: var(--nav-text-70); }

/* ── Progress Bar ── */
.nav-progress { display: flex; gap: 4px; margin-bottom: 16px; }
.nav-progress-seg { flex: 1; height: 3px; border-radius: 2px; background: var(--nav-text-10); }
.nav-progress-seg.done { background: var(--nav-blue); }

/* ── Dimension Picker ── */
.nav-dim-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 8px; margin: 12px 0; }
.nav-dim-pick {
  display: flex; align-items: center; gap: 8px;
  padding: 12px 16px; border-radius: var(--nav-radius);
  border: 1px solid var(--nav-text-10); background: none;
  color: var(--nav-text-70); cursor: pointer; transition: all 0.2s;
}
.nav-dim-pick:active { background: var(--nav-surface-active); }
.nav-dim-pick.selected { border-color: var(--nav-blue); background: rgba(59,130,246,0.1); color: var(--nav-blue); }

/* ── Slider ── */
.nav-slider-row { display: flex; align-items: center; gap: 8px; }
.nav-slider-wrap { flex: 1; }
.nav-slider-wrap input[type=range] {
  width: 100%; height: 4px; -webkit-appearance: none; appearance: none;
  background: var(--nav-surface-active); border-radius: 2px; outline: none;
}
.nav-slider-wrap input[type=range]::-webkit-slider-thumb {
  -webkit-appearance: none; width: 18px; height: 18px; border-radius: 50%;
  background: var(--nav-blue); cursor: pointer;
}
.nav-slider-val { font-size: 16px; font-weight: 600; width: 24px; text-align: center; color: var(--nav-text); }

/* ── Prompt Chips (Release) ── */
.nav-prompt-chips { display: flex; gap: 6px; flex-wrap: wrap; margin: 12px 0; }
.nav-prompt-chip {
  font-size: 12px; padding: 6px 12px; border-radius: var(--nav-radius-pill);
  border: 1px solid var(--nav-text-10); background: none;
  color: var(--nav-text-50); cursor: pointer; transition: background 0.2s;
}
.nav-prompt-chip:active { background: var(--nav-surface-active); }

/* ── Time Ago ── */
.nav-time-ago { font-size: 11px; color: var(--nav-text-30); }

/* ── Loading ── */
.nav-loading {
  display: flex; align-items: center; justify-content: center;
  height: 100%; color: var(--nav-text-50); font-size: 14px;
}

```
