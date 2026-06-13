---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/mfp/iframe-wallet-port.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.867988+00:00
---

# core/protocol-types/src/mfp/iframe-wallet-port.ts

```ts
/**
 * IframeWalletPort — binds the MFP `WalletPort` to the Semantos browser
 * **iframe wallet** (the `wallet-headers` BRC-100 dispatcher) over a
 * postMessage MessagePort.
 *
 * The iframe dispatcher speaks a specific dialect
 * (cartridges/wallet-headers/brain/src/dispatcher.ts):
 *
 *   createSignature  { digestHex, protocolID:<string>, counterparty:<33B hex>,
 *                      derivationIndex:<decimal>, amountSats } → { signatureDer, tier }
 *   createAction     { outputs:[{ scriptHex, satoshis:<dec str> }], amountSats,
 *                      arcUrl? } → { txid, rawTxHex }
 *
 * This port maps the MFP BRC-43 tuple (protocolID:[level,string], keyID,
 * counterparty, data) onto that dialect, classifies dispatcher errors
 * into the MFP exhaustion signals (`cap_exceeded` / `tier_locked`), and
 * is parameterized so the SAME `WalletPort` surface drops onto Metanet
 * Desktop later by swapping only the `Brc100Transport`.
 *
 * No keys live here — all signing crosses the transport into the wallet
 * (Craig's stance). The host page supplies the BRC-100 request-envelope
 * signer via `buildEnvelope`; this module never assumes an identity.
 *
 * Cross-refs: cartridges/wallet-headers/brain/src/bridge.ts (MessagePort
 * framing), core/protocol-types/src/mfp/flow-adapter.ts (the WalletPort),
 * docs/design/WALLET-TIER-CUSTODY.md (Tier-0 budget grant).
 */

import { Hash, Signature, PublicKey, P2PKH } from '@bsv/sdk';
import type { WalletProtocol } from '@bsv/sdk';
import type {
  WalletPort,
  WalletCreateActionArgs,
  WalletCreateActionResult,
  WalletCreateSignatureArgs,
  WalletCreateSignatureResult,
} from './flow-adapter.js';

// ── BRC-100 transport seam ───────────────────────────────────────────

/** A dispatcher error surfaced by the wallet (mirrors `DispatchResult.error`). */
export class Brc100Error extends Error {
  constructor(
    readonly code: number,
    message: string,
    readonly detail?: Record<string, unknown>,
  ) {
    super(message);
    this.name = 'Brc100Error';
  }
}

/**
 * The minimal seam to a BRC-100 wallet backend. `request` resolves with
 * the dispatcher's inner `result` object (the wallet's `ok(method,
 * result)` payload), or rejects with a {@link Brc100Error}.
 *
 * The iframe MessagePort transport implements this; a Metanet-Desktop
 * HTTP transport can implement the same interface — that's the drop-in
 * backend swap.
 */
export interface Brc100Transport {
  request(method: string, params: Record<string, unknown>): Promise<Record<string, unknown>>;
}

// ── Port config ──────────────────────────────────────────────────────

export interface IframeWalletPortConfig {
  /**
   * Hash the MFP commitment/grant bytes → the 32-byte digest the wallet
   * signs. Default: SHA-256. (The C6 device's `cm_sig_verify` defines the
   * real contract; swap this if it expects double-SHA256.)
   */
  digest?: (data: Uint8Array) => Uint8Array;
  /**
   * Build the funding-output locking script (hex) for a channel/grant
   * draw. Default: P2PKH to the counterparty pubkey — a simple prepaid
   * funding output. A real bidirectional channel injects its 2-of-2 /
   * channel script here. Nothing about the channel shape is hardcoded.
   */
  buildFundingScriptHex?: (args: {
    counterparty: string;
    amountSats: bigint;
    keyID: string;
    protocolID: WalletProtocol;
  }) => string;
  /**
   * Signature wire format handed back in the result:
   *   'der' — wallet-native DER (default)
   *   'raw' — 64-byte r||s, what the C6 `cm_sig_verify` path consumes
   */
  signatureFormat?: 'der' | 'raw';
  /** Optional ARC endpoint override forwarded to createAction. */
  arcUrl?: string;
}

// ── The port ─────────────────────────────────────────────────────────

export class IframeWalletPort implements WalletPort {
  private readonly digest: (d: Uint8Array) => Uint8Array;
  private readonly buildFundingScriptHex: NonNullable<IframeWalletPortConfig['buildFundingScriptHex']>;
  private readonly signatureFormat: 'der' | 'raw';
  private readonly arcUrl?: string;

  constructor(
    private readonly transport: Brc100Transport,
    cfg: IframeWalletPortConfig = {},
  ) {
    this.digest = cfg.digest ?? defaultDigest;
    this.buildFundingScriptHex = cfg.buildFundingScriptHex ?? defaultFundingScriptHex;
    this.signatureFormat = cfg.signatureFormat ?? 'der';
    this.arcUrl = cfg.arcUrl;
  }

  async createAction(args: WalletCreateActionArgs): Promise<WalletCreateActionResult> {
    const scriptHex = this.buildFundingScriptHex({
      counterparty: args.counterparty,
      amountSats: args.amountSats,
      keyID: args.keyID,
      protocolID: args.protocolID,
    });
    const params: Record<string, unknown> = {
      outputs: [{ scriptHex, satoshis: args.amountSats.toString() }],
      amountSats: args.amountSats.toString(),
      description: args.description,
    };
    if (this.arcUrl) params.arcUrl = this.arcUrl;
    try {
      const res = await this.transport.request('createAction', params);
      const txid = typeof res.txid === 'string' ? res.txid : '';
      // The wallet funds exactly the requested output value.
      return { ok: true, txid, committedSats: args.amountSats };
    } catch (e) {
      return { ok: false, reason: classifyError(e) };
    }
  }

  async createSignature(args: WalletCreateSignatureArgs): Promise<WalletCreateSignatureResult> {
    const digest = this.digest(args.data);
    const params: Record<string, unknown> = {
      digestHex: bytesToHex(digest),
      protocolID: args.protocolID[1], // the BRC-43 protocol string
      counterparty: args.counterparty,
      derivationIndex: keyIdToDerivationIndex(args.keyID).toString(),
      amountSats: '0', // a commitment signature is not a spend → Tier-0, no prompt
    };
    try {
      const res = await this.transport.request('createSignature', params);
      const der = typeof res.signatureDer === 'string' ? hexToBytes(res.signatureDer) : new Uint8Array(0);
      if (der.length === 0) return { ok: false, reason: 'empty signature' };
      const signature = this.signatureFormat === 'raw' ? derToRaw(der) : der;
      return { ok: true, signature };
    } catch (e) {
      return { ok: false, reason: classifyError(e) };
    }
  }
}

/** Convenience: wire a MessagePort + envelope signer into an IframeWalletPort. */
export function createIframeWalletPort(
  port: PortLike,
  envelope: MessagePortTransportConfig,
  cfg: IframeWalletPortConfig = {},
): IframeWalletPort {
  return new IframeWalletPort(new MessagePortBrc100Transport(port, envelope), cfg);
}

// ── BRC-43 keyID → BRC-42 derivation index ───────────────────────────

/**
 * Map an opaque BRC-43 keyID string to a deterministic, non-negative
 * BRC-42 derivation index. The iframe dispatcher derives the leaf key
 * from (sha256(protocolID-string)[:16], counterparty, index); since the
 * MFP keyID is a string ("flow <id>") not a numeric index, we fold it
 * into a stable 31-bit index. The provider derives the same way.
 */
export function keyIdToDerivationIndex(keyID: string): number {
  const h = Hash.sha256(Array.from(new TextEncoder().encode(keyID)));
  const v = ((h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3]) >>> 0;
  return v & 0x7fffffff;
}

// ── default crypto / script builders ─────────────────────────────────

function defaultDigest(data: Uint8Array): Uint8Array {
  return new Uint8Array(Hash.sha256(Array.from(data)));
}

function defaultFundingScriptHex(args: { counterparty: string }): string {
  const pub = PublicKey.fromString(args.counterparty);
  return new P2PKH().lock(pub.toAddress()).toHex();
}

/** DER signature → 64-byte r||s (big-endian, zero-padded). */
function derToRaw(der: Uint8Array): Uint8Array {
  const sig = Signature.fromDER(Array.from(der));
  const r = sig.r.toArray('be', 32);
  const s = sig.s.toArray('be', 32);
  return new Uint8Array([...r, ...s]);
}

// ── dispatcher error → MFP exhaustion signal ─────────────────────────

function classifyError(e: unknown): 'cap_exceeded' | 'tier_locked' | string {
  if (e instanceof Brc100Error) {
    // 401 = factor prompt cancelled / wrong factor → a higher tier is
    // required to authorize this draw → tier-locked.
    if (e.code === 401) return 'tier_locked';
    if (e.code === 403) {
      const m = e.message.toLowerCase();
      if (m.includes('tier') || m.includes('cooldown')) return 'tier_locked';
      return `${e.code}: ${e.message}`;
    }
    // Insufficient funds → the funding source is empty → exhaustion.
    if (e.code === 400 && e.message.toLowerCase().includes('insufficient')) return 'cap_exceeded';
    return `${e.code}: ${e.message}`;
  }
  return e instanceof Error ? e.message : String(e);
}

// ── MessagePort transport (the real iframe binding) ──────────────────

/**
 * Builds the BRC-100 request envelope (host-identity-signed). Injected so
 * this module never holds or assumes an identity-signing implementation —
 * the host page supplies one (e.g. wrapping `buildEnvelope` from the
 * wallet-headers bridge, or a WalletClient identity).
 */
export type EnvelopeBuilder = (
  body: { method: string; params: Record<string, unknown> },
) => Promise<unknown> | unknown;

export interface MessagePortTransportConfig {
  buildEnvelope: EnvelopeBuilder;
  /** Per-request timeout (ms). Default 30_000. */
  timeoutMs?: number;
}

/** Structural subset of a `MessagePort` — keeps the transport testable. */
export interface PortLike {
  postMessage(msg: unknown): void;
  onmessage: ((ev: { data: unknown }) => void) | null;
  start?: () => void;
}

interface PendingEntry {
  resolve: (v: Record<string, unknown>) => void;
  reject: (e: unknown) => void;
  timer: ReturnType<typeof setTimeout>;
}

/**
 * BRC-100 over a MessagePort, matching the wallet-headers bridge wire:
 *   → { id, type:'request', envelope }
 *   ← { id, type:'ok', envelope, body:{ method, result } }
 *   ← { id, type:'error', error:{ code, message, detail } }   (or { reason })
 */
export class MessagePortBrc100Transport implements Brc100Transport {
  private seq = 0;
  private readonly pending = new Map<string, PendingEntry>();
  private readonly timeoutMs: number;

  constructor(
    private readonly port: PortLike,
    private readonly cfg: MessagePortTransportConfig,
  ) {
    this.timeoutMs = cfg.timeoutMs ?? 30_000;
    this.port.onmessage = (ev) => this.onMessage(ev.data);
    this.port.start?.();
  }

  async request(method: string, params: Record<string, unknown>): Promise<Record<string, unknown>> {
    const id = `mfp-${++this.seq}`;
    const envelope = await this.cfg.buildEnvelope({ method, params });
    return new Promise<Record<string, unknown>>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Brc100Error(504, `BRC-100 ${method} timed out after ${this.timeoutMs}ms`));
      }, this.timeoutMs);
      this.pending.set(id, { resolve, reject, timer });
      this.port.postMessage({ id, type: 'request', envelope });
    });
  }

  private onMessage(data: unknown): void {
    if (!data || typeof data !== 'object') return;
    const msg = data as {
      id?: string;
      type?: string;
      body?: { result?: Record<string, unknown> };
      error?: { code: number; message: string; detail?: Record<string, unknown> };
      reason?: string;
    };
    if (typeof msg.id !== 'string') return;
    const entry = this.pending.get(msg.id);
    if (!entry) return;
    clearTimeout(entry.timer);
    this.pending.delete(msg.id);
    if (msg.type === 'ok') {
      entry.resolve(msg.body?.result ?? {});
    } else if (msg.error) {
      entry.reject(new Brc100Error(msg.error.code, msg.error.message, msg.error.detail));
    } else {
      // Envelope-parse failures reply with { reason } and no error object.
      entry.reject(new Brc100Error(400, msg.reason ?? 'unknown wallet error'));
    }
  }

  /** Reject all in-flight requests (e.g. the iframe was torn down). */
  dispose(): void {
    for (const [, p] of this.pending) {
      clearTimeout(p.timer);
      p.reject(new Brc100Error(503, 'transport disposed'));
    }
    this.pending.clear();
  }
}

// ── hex helpers ──────────────────────────────────────────────────────

function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (let i = 0; i < b.length; i++) s += b[i].toString(16).padStart(2, '0');
  return s;
}

function hexToBytes(hex: string): Uint8Array {
  const clean = hex.startsWith('0x') ? hex.slice(2) : hex;
  if (clean.length % 2 !== 0) throw new Error('hex: odd length');
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(clean.substr(i * 2, 2), 16);
  return out;
}

```
