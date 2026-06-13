---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-demo-wasm-threejs/src/__tests__/identity-ui.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.760817+00:00
---

# archive/apps-demo-wasm-threejs/src/__tests__/identity-ui.test.ts

```ts
/**
 * identity-ui.test.ts
 *
 * Tests for mountIdentityPanel(). Uses jsdom (via vitest environment: 'jsdom')
 * so DOM APIs are available. Ports are bound fresh for every test via
 * makeStubBindings / bindAllIdentityPorts, and unbound in afterEach.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import {
  bindAllIdentityPorts,
  unbindAllIdentityPorts,
} from '@semantos/identity-ports';
import {
  makeStubBindings,
  seedStubCapability,
} from '@semantos/identity-ports/stub';
import type { StubStore } from '@semantos/identity-ports/stub';
import { mountIdentityPanel } from '../identity-ui';

// ── helpers ──────────────────────────────────────────────────────────────

function setup(): { root: HTMLDivElement; store: StubStore } {
  const { bundle, store } = makeStubBindings();
  bindAllIdentityPorts(bundle);

  const root = document.createElement('div');
  document.body.appendChild(root);
  mountIdentityPanel(root, store, seedStubCapability);
  return { root, store };
}

function cleanup(root: HTMLDivElement): void {
  document.body.removeChild(root);
  unbindAllIdentityPorts();
}

function q<T extends HTMLElement = HTMLElement>(root: HTMLElement, sel: string): T {
  const el = root.querySelector<T>(sel);
  if (!el) throw new Error(`selector "${sel}" not found`);
  return el;
}

function click(el: HTMLElement): void {
  el.dispatchEvent(new MouseEvent('click', { bubbles: true }));
}

// ── tests ────────────────────────────────────────────────────────────────

describe('identity panel — Identity section', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    ({ root } = setup());
  });

  afterEach(() => cleanup(root));

  it('registers an identity and shows truncated certId in result', () => {
    const emailInput = q<HTMLInputElement>(root, '#ip-email');
    const registerBtn = q<HTMLButtonElement>(root, '#ip-register-btn');
    const result = q<HTMLDivElement>(root, '#ip-identity-result');

    emailInput.value = 'alice@example.com';
    click(registerBtn);

    expect(result.classList.contains('visible')).toBe(true);
    expect(result.classList.contains('ok')).toBe(true);
    const text = result.textContent ?? '';
    expect(text).toContain('certId');
    expect(text).toContain('publicKey');
    // certId should be truncated with '...'
    expect(text).toMatch(/\.{3}/);
  });

  it('repeated registration with same email is idempotent — same certId', () => {
    const emailInput = q<HTMLInputElement>(root, '#ip-email');
    const registerBtn = q<HTMLButtonElement>(root, '#ip-register-btn');
    const result = q<HTMLDivElement>(root, '#ip-identity-result');

    emailInput.value = 'bob@example.com';
    click(registerBtn);
    const first = result.textContent ?? '';

    click(registerBtn);
    const second = result.textContent ?? '';

    expect(first).toBe(second);
  });

  it('shows fail state when email is empty', () => {
    const emailInput = q<HTMLInputElement>(root, '#ip-email');
    const registerBtn = q<HTMLButtonElement>(root, '#ip-register-btn');
    const result = q<HTMLDivElement>(root, '#ip-identity-result');

    emailInput.value = '';
    click(registerBtn);

    expect(result.classList.contains('fail')).toBe(true);
  });
});

describe('identity panel — Recovery section', () => {
  let root: HTMLDivElement;

  beforeEach(() => {
    ({ root } = setup());
  });

  afterEach(() => cleanup(root));

  it('shows [stub: true] in result on correct answers', () => {
    const emailInput = q<HTMLInputElement>(root, '#ip-recovery-email');
    const initiateBtn = q<HTMLButtonElement>(root, '#ip-initiate-btn');
    const submitBtn = q<HTMLButtonElement>(root, '#ip-submit-recovery-btn');
    const result = q<HTMLDivElement>(root, '#ip-recovery-result');

    emailInput.value = 'alice@example.com';
    click(initiateBtn);

    // All answers pre-filled with 'yes' — do not change them
    click(submitBtn);

    expect(result.classList.contains('ok')).toBe(true);
    // The stub marker 'stub: true' should appear in the rendered HTML
    expect(result.innerHTML).toContain('stub');
    expect(result.innerHTML).toContain('true');
    // 'verified' span should be present
    expect(result.innerHTML).toContain('verified');
  });

  it('shows "not verified" message on wrong answers', () => {
    const emailInput = q<HTMLInputElement>(root, '#ip-recovery-email');
    const initiateBtn = q<HTMLButtonElement>(root, '#ip-initiate-btn');
    const submitBtn = q<HTMLButtonElement>(root, '#ip-submit-recovery-btn');
    const result = q<HTMLDivElement>(root, '#ip-recovery-result');

    emailInput.value = 'alice@example.com';
    click(initiateBtn);

    // Change all answers to wrong value
    const answerInputs = root.querySelectorAll<HTMLInputElement>('[data-challenge-id]');
    for (const input of answerInputs) {
      input.value = 'wrong-answer';
    }

    click(submitBtn);

    expect(result.classList.contains('fail')).toBe(true);
    expect(result.textContent).toContain('not verified');
  });

  it('shows error when submit clicked before initiate', () => {
    const submitBtn = q<HTMLButtonElement>(root, '#ip-submit-recovery-btn');
    const result = q<HTMLDivElement>(root, '#ip-recovery-result');

    // Open the details section so the button is accessible
    submitBtn.style.display = 'inline-block';
    click(submitBtn);

    expect(result.classList.contains('fail')).toBe(true);
  });
});

describe('identity panel — Capability section', () => {
  let root: HTMLDivElement;
  let store: StubStore;

  beforeEach(() => {
    ({ root, store } = setup());
    // Make store accessible in tests that need it
    void store;
  });

  afterEach(() => cleanup(root));

  it('mints and presents a capability, showing valid: true verifier: stub', () => {
    // First register an identity to get a real certId in the stub store
    const emailInput = q<HTMLInputElement>(root, '#ip-email');
    const registerBtn = q<HTMLButtonElement>(root, '#ip-register-btn');
    emailInput.value = 'carol@example.com';
    click(registerBtn);

    // Get the certId from the store directly (avoids parsing truncated display)
    const certId = store.certsByEmail.get('carol@example.com')!;
    expect(certId).toBeTruthy();

    // Fill capability section inputs
    const certIdInput = q<HTMLInputElement>(root, '#ip-cap-certid');
    const capIdInput = q<HTMLInputElement>(root, '#ip-cap-id');
    const mintBtn = q<HTMLButtonElement>(root, '#ip-mint-btn');
    const presentBtn = q<HTMLButtonElement>(root, '#ip-present-btn');
    const result = q<HTMLDivElement>(root, '#ip-cap-result');

    certIdInput.value = certId;
    capIdInput.value = 'test-cap-99';

    click(mintBtn);
    expect(result.classList.contains('ok')).toBe(true);
    expect(result.textContent).toContain('minted');

    click(presentBtn);
    expect(result.classList.contains('ok')).toBe(true);
    const text = result.textContent ?? '';
    expect(text).toContain('valid: true');
    expect(text).toContain('verifier: stub');
  });

  it('shows valid: false when presenting unknown capability', () => {
    const certIdInput = q<HTMLInputElement>(root, '#ip-cap-certid');
    const capIdInput = q<HTMLInputElement>(root, '#ip-cap-id');
    const presentBtn = q<HTMLButtonElement>(root, '#ip-present-btn');
    const result = q<HTMLDivElement>(root, '#ip-cap-result');

    certIdInput.value = 'nonexistent-cert';
    capIdInput.value = 'nonexistent-cap';

    click(presentBtn);

    expect(result.classList.contains('fail')).toBe(true);
    const text = result.textContent ?? '';
    expect(text).toContain('valid: false');
    expect(text).toContain('verifier: stub');
  });

  it('shows error when certId or capabilityId is empty', () => {
    const certIdInput = q<HTMLInputElement>(root, '#ip-cap-certid');
    const capIdInput = q<HTMLInputElement>(root, '#ip-cap-id');
    const mintBtn = q<HTMLButtonElement>(root, '#ip-mint-btn');
    const result = q<HTMLDivElement>(root, '#ip-cap-result');

    certIdInput.value = '';
    capIdInput.value = '';
    click(mintBtn);

    expect(result.classList.contains('fail')).toBe(true);
  });
});

```
