---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/bridge.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.659583+00:00
---

# cartridges/wallet-headers/brain/src/bridge.ts

```ts
// Hidden-iframe entry point — the browser wallet's `wallet.semantos.{tld}/bridge`
// (per WALLET-TIER-CUSTODY.md §10.1).
//
// Responsibilities:
//   1. Load `cell-engine-embedded.wasm` and instantiate it with the host
//      import object built by host.ts.
//   2. Listen for postMessage envelopes from a parent dApp tab — initial
//      message exchanges a MessageChannel port for higher-throughput RPC.
//   3. Validate every request as a BRC-100 signed envelope (brc100.ts).
//   4. For requests that need a UI prompt, open the popup and forward.
//   5. Marshal request → engine call → response (also BRC-100-signed).
//
// v0.1 surface: smoke-level handshake + a `getPublicKey` and `createSignature`
// shim that proves the round-trip. The full BRC-100 RPC catalog lands in W9.

import { createHost, beginRequest, endRequest, primeSlot, primeUnlockTier, flushRequest } from './host';
import { parseEnvelope, buildEnvelope, bytesToHex } from './brc100';
import { dispatch, dispatchStatus, METHOD_COVERAGE, type DispatcherDeps } from './dispatcher';
import { loadWallet, getIdentitySnapshot } from './wallet-ops';

interface BridgeState {
  wasm: WebAssembly.Instance | null;
  memory: WebAssembly.Memory | null;
  channel: MessagePort | null;
  // dApp-supplied origin allowlist. v0.1 trusts any parent — W9 hooks the
  // configured allowlist into `dispatcherDeps` below; the bridge accepts
  // any origin during handshake but BRC-100 envelope verification still
  // rejects forged identities.
  parentOrigin: string | null;
  /** Active dispatcher dependencies — built lazily so tests can inject. */
  dispatcherDeps: DispatcherDeps | null;
  /** Pending tier-N factor prompts, keyed by request nonce. The popup
   *  resolves these via `factor-response` postMessages. */
  pendingFactorPrompts: Map<string, (factor: Uint8Array | null) => void>;
}

const state: BridgeState = {
  wasm: null,
  memory: null,
  channel: null,
  parentOrigin: null,
  dispatcherDeps: null,
  pendingFactorPrompts: new Map(),
};

// W9: bundle version is published in `package.json` — pinned here so the
// dispatcher can return it without a runtime import. Bumped manually per
// release.
const WALLET_BUNDLE_VERSION = '0.1.0';

/**
 * Lazily build (or reuse) the dispatcher's dependency object.  The
 * `promptFactor` callback opens the popup window and waits for the user's
 * `factor-response` postMessage. v0.1 returns null (cancel) outside a real
 * browser — tests inject their own deps via `setDispatcherDeps`.
 */
function buildDispatcherDeps(network: 'main' | 'test' | 'stn' = 'main'): DispatcherDeps {
  return {
    network,
    version: WALLET_BUNDLE_VERSION,
    promptFactor: async ({ tier }) => {
      if (typeof window === 'undefined') return null;
      const nonce = bytesToHex(crypto.getRandomValues(new Uint8Array(16)));
      const popup = window.open('./popup.html', 'semantos-factor', 'popup=true,width=400,height=560');
      if (!popup) return null;
      const kind: 'pin' | 'passphrase' | 'webauthn' = tier === 1 ? 'pin' : tier === 2 ? 'webauthn' : 'passphrase';
      const ready = new Promise<void>((resolve) => {
        const onReady = (ev: MessageEvent): void => {
          if (ev.source === popup && (ev.data as { type?: string })?.type === 'popup-ready') {
            window.removeEventListener('message', onReady);
            resolve();
          }
        };
        window.addEventListener('message', onReady);
      });
      await ready;
      popup.postMessage({ type: 'factor-request', kind, nonce }, window.location.origin);
      return await new Promise<Uint8Array | null>((resolve) => {
        const timer = setTimeout(() => {
          state.pendingFactorPrompts.delete(nonce);
          resolve(null);
        }, 5 * 60 * 1000);
        const wrapped = (factor: Uint8Array | null): void => {
          clearTimeout(timer);
          state.pendingFactorPrompts.delete(nonce);
          resolve(factor);
        };
        state.pendingFactorPrompts.set(nonce, wrapped);
      });
    },
  };
}

/** Tests-only: install a custom dispatcher deps object. */
export function setDispatcherDeps(deps: DispatcherDeps): void {
  state.dispatcherDeps = deps;
}

/** Tests-only: clear dispatcher deps (forces a rebuild on next dispatch). */
export function clearDispatcherDeps(): void {
  state.dispatcherDeps = null;
}

/**
 * Boot the WASM engine. Resolves once the embedded engine is ready.
 *
 * `wasmUrl` defaults to a sibling file `./cell-engine-embedded.wasm` so the
 * bundle stays runnable from `file://` (per design §0). The HTML shell is
 * expected to pass an explicit URL when running off a CDN.
 */
export async function bootEngine(wasmUrl: string = './cell-engine-embedded.wasm'): Promise<void> {
  // streaming instantiate is preferred when the response Content-Type is
  // application/wasm; fall back to ArrayBuffer otherwise (file:// MIME
  // detection is patchy).
  const memory = new WebAssembly.Memory({ initial: 128, maximum: 256 });
  const host = createHost(memory);
  let mod: WebAssembly.WebAssemblyInstantiatedSource;
  try {
    const resp = await fetch(wasmUrl);
    if (!resp.ok) throw new Error(`fetch ${wasmUrl}: ${resp.status}`);
    if (typeof WebAssembly.instantiateStreaming === 'function') {
      try {
        mod = await WebAssembly.instantiateStreaming(resp, { host, env: { memory } });
      } catch {
        const buf = await (await fetch(wasmUrl)).arrayBuffer();
        mod = await WebAssembly.instantiate(buf, { host, env: { memory } });
      }
    } else {
      const buf = await resp.arrayBuffer();
      mod = await WebAssembly.instantiate(buf, { host, env: { memory } });
    }
  } catch (e) {
    throw new Error(`bootEngine: ${(e as Error).message}`);
  }
  state.wasm = mod.instance;
  // The engine exports its own memory — prefer that for memory ops.
  const exportedMem = (state.wasm.exports.memory as WebAssembly.Memory | undefined);
  state.memory = exportedMem ?? memory;
  // Re-bind host functions to the engine-exported memory if it differs.
  if (exportedMem && exportedMem !== memory) {
    // No-op: the host closure captures `memory` at import time. For a v0.1
    // stub we accept the tiny redundancy. W9 wires a single shared memory
    // before instantiation.
  }
}

interface IncomingMessage {
  type: string;
  envelope?: unknown;
  port?: MessagePort;
  // Echoed back on responses so dApps can correlate.
  id?: string;
}

/**
 * Install the postMessage listener on `window`. The parent frame is
 * expected to send an initial `{ type: 'handshake', port: MessagePort }`;
 * subsequent BRC-100 envelopes flow over the dedicated channel.
 */
export function installListener(): void {
  if (typeof window === 'undefined') return; // tests run in node
  window.addEventListener('message', (ev: MessageEvent) => {
    if (typeof ev.data === 'object' && ev.data !== null && 'type' in ev.data) {
      const t = (ev.data as { type: string }).type;
      if (t === 'factor-response' || t === 'factor-cancel' || t === 'factor-error') {
        handleFactorResponse(ev);
        return;
      }
    }
    handleParentMessage(ev);
  });
}

function handleParentMessage(ev: MessageEvent): void {
  const data = ev.data as IncomingMessage | null;
  if (!data || typeof data !== 'object') return;
  if (data.type === 'handshake') {
    state.parentOrigin = ev.origin;
    if (data.port instanceof MessagePort) {
      state.channel = data.port;
      state.channel.onmessage = (e: MessageEvent) => handleChannelMessage(e);
      state.channel.start();
    }
    // Acknowledge readiness.
    ev.source?.postMessage({ type: 'handshake-ack', ready: state.wasm !== null }, {
      targetOrigin: ev.origin,
    });
  }
}

async function handleChannelMessage(ev: MessageEvent): Promise<void> {
  const data = ev.data as IncomingMessage | null;
  if (!data || !state.channel) return;
  const reply = (msg: unknown): void => state.channel!.postMessage({ id: data.id, ...(msg as object) });

  // Special-case: status pings + capabilities don't need a BRC-100 envelope
  // — useful for dApps that just want to discover wallet state before
  // committing to a full BRC-100 handshake.
  if (data.type === 'status') {
    const r = await dispatchStatus();
    reply({ type: r.ok ? 'ok' : 'error', ...r });
    return;
  }
  if (data.type === 'capabilities') {
    reply({ type: 'ok', capabilities: METHOD_COVERAGE });
    return;
  }

  const parsed = parseEnvelope(data.envelope);
  if (!parsed.ok) {
    reply({ type: 'error', reason: parsed.reason });
    return;
  }
  if (!state.dispatcherDeps) state.dispatcherDeps = buildDispatcherDeps();
  const result = await dispatch(parsed.envelope, state.dispatcherDeps);
  if (result.ok) {
    let outbound: ReturnType<typeof buildEnvelope> | null = null;
    try {
      const id = getIdentitySnapshot();
      const bodyBytes = new TextEncoder().encode(JSON.stringify(result.value));
      outbound = buildEnvelope(id.identitySk, id.identityPk, bodyBytes);
    } catch {
      /* no identity yet — capability-style methods only */
    }
    reply({ type: 'ok', envelope: outbound, body: result.value });
  } else {
    reply({ type: 'error', error: result.error });
  }
}

// Wire factor-response postMessages from the popup back to the pending
// promise registered in `promptFactor`.
function handleFactorResponse(ev: MessageEvent): void {
  const data = ev.data as
    | { type?: string; nonce?: string; kind?: string; factor?: Uint8Array; signature?: ArrayBuffer }
    | null;
  if (!data || typeof data !== 'object') return;
  if (data.type !== 'factor-response' && data.type !== 'factor-cancel' && data.type !== 'factor-error') return;
  if (typeof data.nonce !== 'string') return;
  const resolver = state.pendingFactorPrompts.get(data.nonce);
  if (!resolver) return;
  if (data.type === 'factor-cancel' || data.type === 'factor-error') {
    resolver(null);
    return;
  }
  if (data.factor instanceof Uint8Array) {
    resolver(data.factor);
    return;
  }
  if (data.signature instanceof ArrayBuffer) {
    resolver(new Uint8Array(data.signature));
    return;
  }
  resolver(null);
}

// ──────────────────────────────────────────────────────────────────────
// Programmatic API — used by tests and future Wallet UI shell. Not exposed
// to the dApp directly; the dApp talks BRC-100 over the channel.
// ──────────────────────────────────────────────────────────────────────

/**
 * Dispatch a logical wallet request. Steps:
 *   1. begin the host-side request scope (in-memory slot/state cache)
 *   2. let the caller prime any slots / KEKs / next-indices the engine needs
 *   3. invoke the engine entry point synchronously
 *   4. flush any dirty slot writes back to IndexedDB
 *   5. clear the request scope
 *
 * `engineCall` receives the engine's exports and must return a value that
 * is forwarded to the caller. Errors thrown from inside `engineCall`
 * propagate after the cache is cleaned up.
 */
export async function dispatchRequest<T>(
  prime: (h: typeof import('./host')) => Promise<void>,
  engineCall: (exports: WebAssembly.Exports) => T,
): Promise<T> {
  if (!state.wasm) throw new Error('engine not booted');
  const hostMod = await import('./host');
  beginRequest();
  try {
    await prime(hostMod);
    const result = engineCall(state.wasm.exports);
    return result;
  } finally {
    await flushRequest();
    endRequest();
  }
}

export {
  parseEnvelope,
  buildEnvelope,
  primeSlot,
  primeUnlockTier,
  dispatch,
  dispatchStatus,
  METHOD_COVERAGE,
  state as _bridgeStateForTests,
};
export type { DispatcherDeps };

// ── Auto-boot when running inside a real browser ──
if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  installListener();
  // Boot eagerly. The handshake-ack signals readiness.
  bootEngine().catch((e) => {
    // Surface the error to anyone listening; otherwise it stays in the console.
    console.error('[wallet-bridge] boot failed:', e);
  });
  // W9: re-hydrate the wallet's identity / policy from IndexedDB if present.
  // Errors are non-fatal — the popup's create flow handles a fresh device,
  // and dApp methods return 404 if the wallet is missing.
  loadWallet().catch(() => {
    /* fresh device */
  });
}

```
