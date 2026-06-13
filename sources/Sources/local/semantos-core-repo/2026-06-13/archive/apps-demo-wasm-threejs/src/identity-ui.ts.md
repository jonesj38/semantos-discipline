---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-demo-wasm-threejs/src/identity-ui.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.759892+00:00
---

# archive/apps-demo-wasm-threejs/src/identity-ui.ts

```ts
/**
 * Identity panel — mounts three collapsible <details> sections into the
 * #identity-panel <aside> added by index.html.
 *
 * Reads from the four port singletons (identityPort, recoveryPort,
 * capabilityPort) which must be bound before this module is first called.
 * seedStubCapability is passed in from main.ts to avoid a circular dep on the
 * stub-binding module (which lives outside the browser bundle boundary).
 */

import {
  identityPort,
  recoveryPort,
  capabilityPort,
} from '@semantos/identity-ports';
import type { StubStore } from '@semantos/identity-ports/stub';
import type { ChallengeSpec } from '@plexus/contracts';

// ── tiny DOM helpers ──────────────────────────────────────────────────────

function el<K extends keyof HTMLElementTagNameMap>(
  tag: K,
  attrs: Partial<Record<string, string>> = {},
  ...children: (string | HTMLElement)[]
): HTMLElementTagNameMap[K] {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v !== undefined) e.setAttribute(k, v);
  }
  for (const c of children) {
    if (typeof c === 'string') e.append(document.createTextNode(c));
    else e.append(c);
  }
  return e;
}

function trunc(s: string, head = 8, tail = 4): string {
  if (s.length <= head + tail + 3) return s;
  return `${s.slice(0, head)}...${s.slice(-tail)}`;
}

// ── result display ────────────────────────────────────────────────────────

function showResult(
  div: HTMLDivElement,
  text: string,
  kind: 'ok' | 'fail' | 'none',
  html?: boolean,
): void {
  div.classList.toggle('visible', kind !== 'none');
  div.classList.toggle('ok', kind === 'ok');
  div.classList.toggle('fail', kind === 'fail');
  if (html) {
    div.innerHTML = text;
  } else {
    div.textContent = text;
  }
}

// ── Section 1: Identity ───────────────────────────────────────────────────

function buildIdentitySection(): HTMLElement {
  const section = el('div', { class: 'ip-section' });

  const emailInput = el('input', {
    type: 'email',
    placeholder: 'user@example.com',
    id: 'ip-email',
  }) as HTMLInputElement;
  const registerBtn = el('button', { class: 'ip-btn', id: 'ip-register-btn' }, 'Register');
  const row = el('div', { class: 'ip-row' }, emailInput, registerBtn);
  const result = el('div', { class: 'ip-result', id: 'ip-identity-result' }) as HTMLDivElement;

  registerBtn.addEventListener('click', () => {
    const email = emailInput.value.trim();
    if (!email) {
      showResult(result, 'enter an email address', 'fail');
      return;
    }
    try {
      const reg = identityPort.get().registerIdentity(email);
      showResult(
        result,
        `certId:    ${trunc(reg.certId)}\npublicKey: ${trunc(reg.publicKey)}`,
        'ok',
      );
    } catch (err) {
      showResult(result, `error: ${err instanceof Error ? err.message : String(err)}`, 'fail');
    }
  });

  section.append(row, result);
  return section;
}

// ── Section 2: Recovery ───────────────────────────────────────────────────

function buildRecoverySection(): HTMLElement {
  const section = el('div', { class: 'ip-section' });

  // initiate row
  const emailInput = el('input', {
    type: 'email',
    placeholder: 'user@example.com (same as above)',
    id: 'ip-recovery-email',
  }) as HTMLInputElement;
  const initiateBtn = el('button', { class: 'ip-btn', id: 'ip-initiate-btn' }, 'Initiate');
  const initiateRow = el('div', { class: 'ip-row' }, emailInput, initiateBtn);

  // challenge area (hidden until initiation)
  const challengeList = el('div', { class: 'ip-challenge-list', id: 'ip-challenge-list' });
  challengeList.style.display = 'none';

  const submitBtn = el('button', {
    class: 'ip-btn',
    id: 'ip-submit-recovery-btn',
    style: 'display:none',
  }, 'Submit answers');

  const result = el('div', { class: 'ip-result', id: 'ip-recovery-result' }) as HTMLDivElement;

  let currentSessionId: string | null = null;
  let currentChallenges: ChallengeSpec[] = [];
  const answerInputs: Map<string, HTMLInputElement> = new Map();

  initiateBtn.addEventListener('click', () => {
    const email = emailInput.value.trim();
    if (!email) {
      showResult(result, 'enter an email address', 'fail');
      return;
    }
    try {
      const init = recoveryPort.get().initiateRecovery(email);
      currentSessionId = init.sessionId;
      currentChallenges = [...init.challenges];
      answerInputs.clear();
      challengeList.innerHTML = '';

      for (const ch of currentChallenges) {
        const label = el('span', { class: 'ip-challenge-label' }, ch.prompt);
        const input = el('input', {
          type: 'text',
          placeholder: 'yes',
          value: 'yes',
          'data-challenge-id': ch.id,
        }) as HTMLInputElement;
        answerInputs.set(ch.id, input);
        challengeList.append(el('div', { class: 'ip-challenge-item' }, label, input));
      }

      challengeList.style.display = 'flex';
      submitBtn.style.display = 'inline-block';
      showResult(result, `session started — ${init.challengeCount} challenge(s)`, 'ok');
    } catch (err) {
      showResult(result, `error: ${err instanceof Error ? err.message : String(err)}`, 'fail');
    }
  });

  submitBtn.addEventListener('click', () => {
    if (!currentSessionId) {
      showResult(result, 'initiate recovery first', 'fail');
      return;
    }
    const answers = currentChallenges.map((ch) => ({
      challengeId: ch.id,
      answer: answerInputs.get(ch.id)?.value ?? '',
    }));
    try {
      const verdict = recoveryPort.get().submitChallengeAnswers(currentSessionId, answers);
      if (!verdict.verified) {
        showResult(result, 'not verified — wrong answers', 'fail');
        return;
      }
      // Decode the export payload and display with stub marker highlighted
      const raw = atob(verdict.exportPayload ?? '');
      const parsed = JSON.parse(raw) as Record<string, unknown>;
      const stubVal = parsed['stub'];
      const stubMarker = stubVal === true
        ? '<span class="stub-marker">stub: true</span>'
        : String(stubVal);
      const body = JSON.stringify(parsed, null, 2)
        .replace(/"stub": true/, `"stub": ${stubMarker}`);
      showResult(
        result,
        `<span class="hi">verified</span>\n\nexportPayload (decoded):\n${body}`,
        'ok',
        true,
      );
    } catch (err) {
      showResult(result, `error: ${err instanceof Error ? err.message : String(err)}`, 'fail');
    }
  });

  section.append(initiateRow, challengeList, submitBtn, result);
  return section;
}

// ── Section 3: Capability ─────────────────────────────────────────────────

function buildCapabilitySection(
  seedCapability: (capabilityId: string, certId: string) => void,
): HTMLElement {
  const section = el('div', { class: 'ip-section' });

  const certIdInput = el('input', {
    type: 'text',
    placeholder: 'certId from Identity section',
    id: 'ip-cap-certid',
  }) as HTMLInputElement;
  const capIdInput = el('input', {
    type: 'text',
    placeholder: 'capability id (any string)',
    id: 'ip-cap-id',
    value: 'demo-cap-1',
  }) as HTMLInputElement;

  const mintBtn = el('button', { class: 'ip-btn', id: 'ip-mint-btn' }, 'Mint capability');
  const presentBtn = el('button', { class: 'ip-btn', id: 'ip-present-btn' }, 'Present capability');

  const row1 = el('div', { class: 'ip-row' }, certIdInput);
  const row2 = el('div', { class: 'ip-row' }, capIdInput);
  const row3 = el('div', { class: 'ip-row' }, mintBtn, presentBtn);
  const result = el('div', { class: 'ip-result', id: 'ip-cap-result' }) as HTMLDivElement;

  mintBtn.addEventListener('click', () => {
    const certId = certIdInput.value.trim();
    const capabilityId = capIdInput.value.trim();
    if (!certId || !capabilityId) {
      showResult(result, 'enter certId and capability id', 'fail');
      return;
    }
    seedCapability(capabilityId, certId);
    showResult(result, `capability "${capabilityId}" minted for cert ${trunc(certId)}`, 'ok');
  });

  presentBtn.addEventListener('click', () => {
    const certId = certIdInput.value.trim();
    const capabilityId = capIdInput.value.trim();
    if (!certId || !capabilityId) {
      showResult(result, 'enter certId and capability id', 'fail');
      return;
    }
    const check = capabilityPort.get().present(certId, capabilityId);
    if (check.valid) {
      showResult(
        result,
        `valid: true\nverifier: ${check.verifier}`,
        'ok',
      );
    } else {
      showResult(
        result,
        `valid: false\nreason: ${check.reason ?? 'unknown'}\nverifier: ${check.verifier}`,
        'fail',
      );
    }
  });

  section.append(row1, row2, row3, result);
  return section;
}

// ── Public mount function ─────────────────────────────────────────────────

/**
 * Mount the identity panel into `panelEl`.
 *
 * `store` is the stub store returned by `makeStubBindings()` — it is held
 * here so the Mint button can call `seedStubCapability` without re-importing
 * stub-binding (which keeps the prod bundle clean).
 */
export function mountIdentityPanel(
  panelEl: HTMLElement,
  store: StubStore,
  seedStubCapability: (store: StubStore, capabilityId: string, certId: string, capType: 'data_access') => void,
): void {
  // Section 1 — Identity
  const idDetails = el('details', { open: '' });
  const idSummary = el('summary', {}, 'Identity');
  idDetails.append(idSummary, buildIdentitySection());

  // Section 2 — Recovery
  const recDetails = el('details');
  const recSummary = el('summary', {}, 'Recovery');
  recDetails.append(recSummary, buildRecoverySection());

  // Section 3 — Capability
  const capDetails = el('details');
  const capSummary = el('summary', {}, 'Capability');
  const capSection = buildCapabilitySection((capabilityId, certId) => {
    seedStubCapability(store, capabilityId, certId, 'data_access');
  });
  capDetails.append(capSummary, capSection);

  panelEl.append(idDetails, recDetails, capDetails);
}

```
