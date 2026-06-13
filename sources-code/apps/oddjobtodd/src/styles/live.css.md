---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/oddjobtodd/src/styles/live.css
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.052901+00:00
---

# apps/oddjobtodd/src/styles/live.css

```css
/* LiveApp — brain-connected operator interface
   Uses the same CSS vars from base.css (--void, --shell, --ink, --activation, etc.)
*/

/* ── App shell ──────────────────────────────────────────────────────────── */

.la-app {
  display: flex;
  flex-direction: column;
  height: 100dvh;
  max-width: 480px;
  margin: 0 auto;
  background: var(--void);
}

/* ── Header ─────────────────────────────────────────────────────────────── */

.la-header {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px 16px;
  background: var(--shell);
  border-bottom: 1px solid var(--rule);
  flex-shrink: 0;
}

.la-header-title {
  flex: 1;
  font-family: var(--mono);
  font-size: 13px;
  color: var(--ink);
  letter-spacing: 0.06em;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.la-header-actions {
  display: flex;
  gap: 4px;
}

.la-back {
  background: none;
  border: none;
  color: var(--activation);
  font-family: var(--mono);
  font-size: 12px;
  cursor: pointer;
  padding: 4px 8px 4px 0;
  white-space: nowrap;
}

/* ── Body scroll container ──────────────────────────────────────────────── */

.la-body {
  flex: 1;
  overflow-y: auto;
  padding: 12px 16px 80px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

/* ── Login ──────────────────────────────────────────────────────────────── */

.la-login {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100dvh;
  background: var(--void);
}

.la-login-card {
  display: flex;
  flex-direction: column;
  gap: 14px;
  padding: 28px 24px;
  background: var(--shell);
  border: 1px solid var(--rule);
  border-radius: 8px;
  width: min(340px, 90vw);
}

.la-logo {
  font-family: var(--mono);
  font-size: 18px;
  color: var(--activation);
  letter-spacing: 0.12em;
  text-align: center;
}

.la-login-hint {
  font-size: 13px;
  color: var(--ink-soft);
  text-align: center;
}

.la-input {
  background: var(--shell-2);
  border: 1px solid var(--rule);
  border-radius: 4px;
  color: var(--ink);
  font-family: var(--mono);
  font-size: 12px;
  padding: 10px 12px;
  outline: none;
  width: 100%;
}

.la-input:focus {
  border-color: var(--activation);
  box-shadow: 0 0 0 2px var(--activation-soft);
}

/* ── Buttons ────────────────────────────────────────────────────────────── */

.la-btn-primary {
  background: var(--activation);
  border: none;
  border-radius: 4px;
  color: var(--void);
  font-family: var(--mono);
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 0.08em;
  padding: 10px;
  cursor: pointer;
  width: 100%;
  transition: opacity 0.15s;
}

.la-btn-primary:disabled { opacity: 0.4; cursor: default; }

.la-btn-ghost {
  background: none;
  border: 1px solid var(--rule);
  border-radius: 4px;
  color: var(--ink-soft);
  font-family: var(--mono);
  font-size: 12px;
  padding: 5px 9px;
  cursor: pointer;
  transition: color 0.15s, border-color 0.15s;
}

.la-btn-ghost:hover { color: var(--ink); border-color: var(--rule-bright); }

.la-btn-sm { padding: 3px 7px; font-size: 11px; }

.la-btn-action {
  background: none;
  border: 1px solid var(--activation);
  border-radius: 4px;
  color: var(--activation);
  font-family: var(--mono);
  font-size: 11px;
  padding: 7px 14px;
  cursor: pointer;
  letter-spacing: 0.06em;
}

.la-btn-action:disabled { opacity: 0.4; cursor: default; }

.la-btn-approve {
  background: var(--hold);
  border: none;
  border-radius: 4px;
  color: var(--void);
  font-family: var(--mono);
  font-size: 11px;
  font-weight: 700;
  padding: 7px 14px;
  cursor: pointer;
  margin-top: 8px;
  letter-spacing: 0.06em;
}

.la-btn-approve:disabled { opacity: 0.5; cursor: default; }

/* ── State labels ───────────────────────────────────────────────────────── */

.la-stage {
  font-family: var(--mono);
  font-size: 9px;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--activation);
  flex-shrink: 0;
}

.la-stage.done { color: var(--hold); }
.la-stage-header { margin-left: auto; }

/* ── Job list ───────────────────────────────────────────────────────────── */

.la-jobs-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.la-job-row {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 12px 14px;
  background: var(--shell);
  border: 1px solid var(--rule);
  border-radius: 5px;
  cursor: pointer;
  transition: border-color 0.12s, background 0.12s;
}

.la-job-row:hover {
  border-color: var(--activation);
  background: linear-gradient(180deg, rgba(127,217,255,0.04), transparent), var(--shell);
}

.la-job-row-main {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 3px;
  min-width: 0;
}

.la-job-name {
  font-size: 14px;
  color: var(--ink);
  font-weight: 400;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.la-job-addr, .la-job-services {
  font-family: var(--mono);
  font-size: 10px;
  color: var(--ink-faint);
  letter-spacing: 0.04em;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* ── Job detail meta ────────────────────────────────────────────────────── */

.la-job-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  padding: 8px 0;
}

.la-meta-chip {
  font-family: var(--mono);
  font-size: 10px;
  color: var(--ink-soft);
  background: var(--shell-2);
  border: 1px solid var(--rule);
  border-radius: 3px;
  padding: 3px 8px;
  letter-spacing: 0.04em;
}

.la-meta-dim { color: var(--ink-dim); }

.la-actions {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
}

.la-pending-badge {
  font-family: var(--mono);
  font-size: 10px;
  color: var(--linear);
  background: var(--linear-soft);
  border: 1px solid rgba(255,178,74,0.25);
  border-radius: 3px;
  padding: 4px 8px;
  letter-spacing: 0.06em;
}

.la-quote-result {
  background: var(--shell-2);
  border: 1px solid var(--rule);
  border-radius: 4px;
  padding: 10px 12px;
}

.la-quote-result pre {
  font-family: var(--mono);
  font-size: 11px;
  color: var(--ink-soft);
  margin: 0;
  white-space: pre-wrap;
  word-break: break-word;
}

/* ── Conversation thread ────────────────────────────────────────────────── */

.la-thread-header {
  display: flex;
  align-items: center;
  gap: 8px;
  font-family: var(--mono);
  font-size: 10px;
  color: var(--ink-faint);
  letter-spacing: 0.12em;
  text-transform: uppercase;
  padding-top: 4px;
  border-top: 1px solid var(--rule);
}

.la-thread {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.la-turn {
  padding: 11px 13px;
  border-radius: 6px;
  border: 1px solid var(--rule);
  background: var(--shell);
}

.la-turn-in {
  border-left: 3px solid var(--ink-dim);
  background: var(--shell-2);
}

.la-turn-out {
  border-left: 3px solid var(--activation);
}

.la-turn-proposed {
  border-color: var(--linear);
  border-left-color: var(--linear);
  background: linear-gradient(180deg, var(--linear-soft), transparent), var(--shell);
}

.la-turn-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 6px;
  flex-wrap: wrap;
}

.la-turn-surface {
  font-family: var(--mono);
  font-size: 9px;
  color: var(--ink-faint);
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.la-turn-ts {
  font-family: var(--mono);
  font-size: 9px;
  color: var(--ink-dim);
  margin-left: auto;
}

.la-turn-state {
  font-family: var(--mono);
  font-size: 9px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  padding: 2px 5px;
  border-radius: 2px;
  background: var(--shell-3);
}

.la-turn-state-proposed { color: var(--linear); }
.la-turn-state-sent, .la-turn-state-delivered { color: var(--hold); }
.la-turn-state-failed, .la-turn-state-rejected { color: #ff6b6b; }
.la-turn-state-approved { color: var(--activation); }

.la-turn-identity {
  font-family: var(--mono);
  font-size: 9px;
  color: var(--ink-soft);
}

.la-turn-body {
  font-size: 13px;
  color: var(--ink);
  line-height: 1.5;
  white-space: pre-wrap;
  word-break: break-word;
}

/* ── Status / error messages ────────────────────────────────────────────── */

.la-status {
  font-family: var(--mono);
  font-size: 11px;
  color: var(--ink-faint);
  letter-spacing: 0.06em;
  text-align: center;
  padding: 16px 0;
}

.la-empty { color: var(--ink-dim); }
.la-warn { color: var(--linear); }

.la-error {
  font-family: var(--mono);
  font-size: 11px;
  color: #ff6b6b;
  background: rgba(255,107,107,0.08);
  border: 1px solid rgba(255,107,107,0.25);
  border-radius: 4px;
  padding: 10px 12px;
}

```
