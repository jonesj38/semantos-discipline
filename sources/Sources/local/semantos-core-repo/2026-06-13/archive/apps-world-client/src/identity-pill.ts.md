---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/identity-pill.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.819934+00:00
---

# archive/apps-world-client/src/identity-pill.ts

```ts
/**
 * Identity pill — a small DOM component displayed top-left, above the log
 * panel, showing the session's stub certId and a "View recovery" button.
 *
 * Matches log.ts style: plain DOM, no framework, dark theme consistent with
 * the rest of the world-client UI.
 */

import { recoveryPort } from "@semantos/identity-ports";

// ─── styles ──────────────────────────────────────────────────────────────────

const PILL_STYLE = `
  position: absolute;
  top: 12px;
  right: 12px;
  width: 360px;
  padding: 10px 12px;
  background: rgba(10, 10, 12, 0.78);
  border: 1px solid #2a2a30;
  border-radius: 6px;
  font: 12px/1.45 ui-monospace, SFMono-Regular, Menlo, monospace;
  color: #c8c8cc;
  z-index: 10;
`;

const MODAL_OVERLAY_STYLE = `
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.72);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 100;
`;

const MODAL_BOX_STYLE = `
  background: #0e0e12;
  border: 1px solid #2a2a30;
  border-radius: 8px;
  padding: 20px 24px;
  max-width: 520px;
  width: 90vw;
  max-height: 80vh;
  overflow: auto;
  font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace;
  color: #c8c8cc;
`;

const MODAL_TITLE_STYLE = `
  font-size: 13px;
  font-weight: 600;
  color: #f0f0f3;
  margin: 0 0 12px;
`;

const PRE_STYLE = `
  white-space: pre-wrap;
  word-break: break-all;
  font: inherit;
  color: #89bbff;
  background: #0a0a0b;
  border: 1px solid #1e1e28;
  border-radius: 4px;
  padding: 10px;
  margin: 0 0 12px;
`;

const CLOSE_BTN_STYLE = `
  background: #1a1a1e;
  color: #c8c8cc;
  border: 1px solid #444;
  border-radius: 3px;
  padding: 3px 10px;
  font: inherit;
  cursor: pointer;
`;

const RECOVERY_BTN_STYLE = `
  background: #1a1a1e;
  color: #c8c8cc;
  border: 1px solid #444;
  border-radius: 3px;
  padding: 3px 10px;
  font: inherit;
  cursor: pointer;
  margin-top: 6px;
  display: block;
`;

// ─── helpers ─────────────────────────────────────────────────────────────────

/** Truncate a certId to `prefix...suffix` display form. */
function truncateCertId(certId: string): string {
  if (certId.length <= 16) return certId;
  return `${certId.slice(0, 8)}...${certId.slice(-4)}`;
}

function applyStyles(el: HTMLElement, styles: string): void {
  el.style.cssText = styles.replace(/\n/g, " ").trim();
}

// ─── modal ───────────────────────────────────────────────────────────────────

function showRecoveryModal(payload: object): void {
  const overlay = document.createElement("div");
  applyStyles(overlay, MODAL_OVERLAY_STYLE);

  const box = document.createElement("div");
  applyStyles(box, MODAL_BOX_STYLE);

  const title = document.createElement("p");
  applyStyles(title, MODAL_TITLE_STYLE);
  title.textContent = "Recovery export payload";

  const pre = document.createElement("pre");
  applyStyles(pre, PRE_STYLE);
  pre.textContent = JSON.stringify(payload, null, 2);

  const closeBtn = document.createElement("button");
  applyStyles(closeBtn, CLOSE_BTN_STYLE);
  closeBtn.type = "button";
  closeBtn.textContent = "Close";
  closeBtn.addEventListener("click", () => overlay.remove());

  box.appendChild(title);
  box.appendChild(pre);
  box.appendChild(closeBtn);
  overlay.appendChild(box);

  // Close on backdrop click.
  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) overlay.remove();
  });

  document.body.appendChild(overlay);
}

function showErrorModal(message: string): void {
  showRecoveryModal({ error: message });
}

// ─── public API ──────────────────────────────────────────────────────────────

export interface IdentityPillOptions {
  /** The certId minted for this session (may be null if identity port not bound). */
  certId: string | null;
  /** The session's email used for registration, e.g. `<sessionId>@stub.local`. */
  email: string;
}

/**
 * Mount the identity pill into the scene container. Returns the root element
 * so callers can update it later (e.g. after a reconnect that changes certId).
 */
export function mountIdentityPill(opts: IdentityPillOptions): HTMLElement {
  const pill = document.createElement("div");
  pill.id = "identity-pill";
  applyStyles(pill, PILL_STYLE);

  render(pill, opts);
  document.body.appendChild(pill);
  return pill;
}

/**
 * Update an already-mounted pill with a new certId (e.g. after reconnect).
 */
export function updateIdentityPill(pill: HTMLElement, opts: IdentityPillOptions): void {
  render(pill, opts);
}

function render(pill: HTMLElement, opts: IdentityPillOptions): void {
  pill.innerHTML = "";

  const label = document.createElement("div");
  label.style.color = "#8a9";
  label.style.marginBottom = "4px";
  const certDisplay = opts.certId ? truncateCertId(opts.certId) : "—";
  label.innerHTML = `<span style="color:#89a">Identity:</span> <b style="color:#ccc">${certDisplay}</b>`;

  const btn = document.createElement("button");
  btn.type = "button";
  btn.textContent = "View recovery";
  applyStyles(btn, RECOVERY_BTN_STYLE);
  btn.addEventListener("click", () => handleRecovery(opts));

  pill.appendChild(label);
  pill.appendChild(btn);
}

async function handleRecovery(opts: IdentityPillOptions): Promise<void> {
  try {
    const port = recoveryPort.get();

    // Phase 1: initiate
    const initiation = port.initiateRecovery(opts.email);

    // Phase 2: submit stub answers (all "yes" — matches stub defaults)
    const answers = initiation.challenges.map((c) => ({
      challengeId: c.id,
      answer: "yes",
    }));
    const verdict = port.submitChallengeAnswers(initiation.sessionId, answers);

    if (!verdict.verified || !verdict.exportPayload) {
      showErrorModal("Recovery verification failed — check stub binding.");
      return;
    }

    // Decode base64 → JSON and display.
    const decoded: unknown = JSON.parse(atob(verdict.exportPayload));
    showRecoveryModal(decoded as object);
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    showErrorModal(`Recovery error: ${msg}`);
  }
}

```
