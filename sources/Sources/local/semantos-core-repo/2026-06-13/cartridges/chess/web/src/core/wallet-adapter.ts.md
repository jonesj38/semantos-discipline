---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/chess/web/src/core/wallet-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.430063+00:00
---

# cartridges/chess/web/src/core/wallet-adapter.ts

```ts
/**
 * Wallet adapter chain — connects doublemate.app to whatever BRC-100
 * wallet the player has available.
 *
 * Detection order (first responder wins):
 *   1. Semantos wasm iframe at wallet.semantos.me (if VITE_WALLET_ENABLED
 *      or localStorage.chess.walletEnabled === '1', and the iframe
 *      handshakes)
 *   2. Metanet Desktop on http://localhost:3321 (BRC-56 HTTP wallet
 *      surface; the de-facto BSV reference wallet)
 *   3. None — chess SPA falls back to lobby-pasted bearer + a
 *      random `p-xxxxxx` handle.
 *
 * Adapters expose a minimal BRC-100 surface:
 *   - `available()` — fast probe (≤1s)
 *   - `getIdentityKey()` — 33-byte compressed pubkey, hex
 *
 * Future: `signMessage` / `createSignature` for BRC-100 envelope auth
 * (lands with the T7 brain-auth alignment).
 */

import { WalletBridge, defaultWalletOrigin } from './wallet-bridge.js';

export type WalletKind = 'wasm-iframe' | 'metanet-desktop';

// ── Minimal crypto helpers (no extra deps) ────────────────────────────

function hexToBytes(hex: string): Uint8Array {
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2)
    out[i >> 1] = parseInt(hex.slice(i, i + 2), 16);
  return out;
}

/** Double-SHA256 via Web Crypto (best-effort txid fallback). */
async function sha256d(data: Uint8Array): Promise<Uint8Array> {
  const h1 = await crypto.subtle.digest('SHA-256', data);
  const h2 = await crypto.subtle.digest('SHA-256', h1);
  return new Uint8Array(h2);
}

// ── createAction types ───────────────────────────────────────────────

export interface WalletActionOutput {
  /** Hex-encoded locking script. */
  lockingScript: string;
  satoshis: number;
  outputDescription?: string;
}

export interface WalletActionParams {
  description: string;
  outputs: WalletActionOutput[];
}

export interface WalletActionResult {
  /** Big-endian (display-order) txid hex. */
  txidHex: string;
}

// ── Adapter interface ─────────────────────────────────────────────────

export interface WalletAdapter {
  /** Stable human-readable name shown in the UI. */
  readonly name: string;
  /** Discriminator for adapter-specific UI / logging. */
  readonly kind: WalletKind;
  /** Returns the wallet's identity pubkey (33-byte compressed, hex). */
  getIdentityKey(): Promise<string>;
  /**
   * Build, sign, and broadcast a transaction with the specified outputs.
   * Corresponds to BRC-100 createAction / BRC-56 POST /createAction.
   * Prompts the user for spend approval in the wallet UI.
   */
  createAction(params: WalletActionParams): Promise<WalletActionResult>;
}

// ─── Metanet Desktop adapter ─────────────────────────────────────────

const METANET_DEFAULT_BASE = 'http://localhost:3321';

export class MetanetDesktopAdapter implements WalletAdapter {
  readonly name = 'Metanet Desktop';
  readonly kind = 'metanet-desktop';
  constructor(private readonly base: string = METANET_DEFAULT_BASE) {}

  async getIdentityKey(): Promise<string> {
    const res = await fetch(`${this.base}/getPublicKey`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ identityKey: true }),
    });
    if (!res.ok) throw new Error(`metanet getPublicKey ${res.status}: ${await res.text()}`);
    const body = await res.json() as { publicKey?: string };
    if (!body.publicKey) throw new Error('metanet getPublicKey: missing publicKey');
    return body.publicKey;
  }

  async createAction(params: WalletActionParams): Promise<WalletActionResult> {
    // Metanet Desktop (BRC-56 HTTPWalletJSON) requires `tags:[]` on each
    // output — it calls Array.from() on the field and throws if it's absent.
    const body = {
      description: params.description,
      outputs: params.outputs.map((o) => ({ ...o, tags: [] as string[] })),
      labels: [] as string[],
    };
    const res = await fetch(`${this.base}/createAction`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`metanet createAction ${res.status}: ${await res.text()}`);

    const data = await res.json() as {
      txid?: string;
      tx?: number[];
      beef?: string;
      rawTx?: string;
      signedTransaction?: string;
    };

    // Prefer the explicit txid field (display-order BE hex).
    if (data.txid) return { txidHex: data.txid };

    // Fall back: extract txid from the BEEF / rawTx byte arrays.
    // We do a minimal parse: find the last 32-byte txid without pulling in
    // heavy BEEF codec. The txid is the LE double-SHA256 of the serialized
    // tx — reversing gives the display-order hex the caller expects.
    const txBytes = Array.isArray(data.tx)
      ? new Uint8Array(data.tx)
      : data.beef
        ? hexToBytes(data.beef)
        : data.rawTx
          ? hexToBytes(data.rawTx)
          : data.signedTransaction
            ? hexToBytes(data.signedTransaction)
            : null;
    if (!txBytes) throw new Error('metanet createAction: no txid or tx bytes in response');

    // Compute SHA256d of the raw tx portion. For a BEEF we skip the header
    // and use the last tx in the list; for a rawTx we use the whole buffer.
    // This is best-effort — the txid field is normally present.
    const txidLeBytes = await sha256d(txBytes);
    const txidHex = Array.from(txidLeBytes).reverse().map((b) => b.toString(16).padStart(2, '0')).join('');
    return { txidHex };
  }

  /**
   * Availability probe — checks if something is listening on :3321.
   *
   * Uses `mode: 'no-cors'` so the browser does NOT send a CORS preflight
   * OPTIONS request. When doublemate.app is served over HTTPS and Metanet
   * Desktop runs over HTTP on localhost, the preflight adds a full
   * round-trip and may time out or be rejected — making the wallet appear
   * absent even when it is running. With no-cors the browser treats it as
   * a simple request; the response is opaque but the fetch resolves iff
   * the port is open.
   *
   * The actual `getIdentityKey` / `createAction` calls use full CORS mode
   * to read the response; Metanet Desktop sends `Access-Control-Allow-Origin: *`
   * so those work fine. The probe just needs to know the port is open.
   */
  static async probe(base: string = METANET_DEFAULT_BASE, timeoutMs = 3000): Promise<boolean> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
      await fetch(`${base}/getPublicKey`, {
        method: 'POST',
        mode: 'no-cors',   // avoids preflight; opaque response is fine for a presence check
        signal: controller.signal,
      });
      return true; // something responded on this port
    } catch {
      return false;
    } finally {
      clearTimeout(timer);
    }
  }
}

// ─── Wasm-iframe adapter ─────────────────────────────────────────────

export class WasmIframeAdapter implements WalletAdapter {
  readonly name: string;
  readonly kind = 'wasm-iframe';
  private bridge: WalletBridge | null = null;

  constructor(private readonly origin: string = defaultWalletOrigin()) {
    this.name = `Semantos Wallet (${new URL(origin).host})`;
  }

  private async ensureBridge(): Promise<WalletBridge> {
    if (this.bridge) return this.bridge;
    const b = new WalletBridge(this.origin);
    await b.connect();
    this.bridge = b;
    return b;
  }

  async getIdentityKey(): Promise<string> {
    const b = await this.ensureBridge();
    const out = await b.call('getPublicKey', { identityKey: true }) as { publicKey?: string };
    if (!out.publicKey) throw new Error('wasm-iframe getPublicKey: missing publicKey');
    return out.publicKey;
  }

  async createAction(params: WalletActionParams): Promise<WalletActionResult> {
    const b = await this.ensureBridge();
    const out = await b.call('createAction', params as unknown as Record<string, unknown>) as { txid?: string };
    if (!out.txid) throw new Error('wasm-iframe createAction: missing txid in response');
    return { txidHex: out.txid };
  }

  /**
   * Probe by trying to load the bridge iframe and complete a
   * handshake. Slow on the failure case (waits for the iframe load
   * timeout) — only run when wasm mode is explicitly opted into.
   */
  static async probe(origin: string, timeoutMs = 5_000): Promise<boolean> {
    try {
      const b = new WalletBridge(origin, { timeoutMs });
      await b.connect();
      b.disconnect();
      return true;
    } catch {
      return false;
    }
  }
}

// ─── Detection chain ─────────────────────────────────────────────────

export interface DetectOptions {
  /** Skip the wasm-iframe probe (used until wallet.semantos.me is publicly deployed). */
  readonly tryWasmIframe?: boolean;
  /** Override the wasm-iframe origin. */
  readonly wasmOrigin?: string;
  /** Override the Metanet Desktop base URL. */
  readonly metanetBase?: string;
}

/**
 * Try the wasm-iframe first (if enabled), then Metanet Desktop. Returns
 * the first adapter whose probe succeeds, or null if no wallet found.
 */
export async function detectWallet(opts: DetectOptions = {}): Promise<WalletAdapter | null> {
  if (opts.tryWasmIframe) {
    const origin = opts.wasmOrigin ?? defaultWalletOrigin();
    if (await WasmIframeAdapter.probe(origin)) {
      return new WasmIframeAdapter(origin);
    }
  }
  const base = opts.metanetBase ?? METANET_DEFAULT_BASE;
  if (await MetanetDesktopAdapter.probe(base)) {
    return new MetanetDesktopAdapter(base);
  }
  return null;
}

```
