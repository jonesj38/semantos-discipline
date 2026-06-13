---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/dispatcher.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.649866+00:00
---

# cartridges/wallet-headers/brain/src/dispatcher.ts

```ts
// BRC-100 method dispatcher (W9).
//
// Stateless logical layer between `bridge.ts` (postMessage adapter) and
// `wallet-ops.ts` (wallet state machine). Takes a parsed BRC-100 envelope,
// resolves the requested method, dispatches to wallet-ops, returns a
// response shape that `bridge.ts` re-envelopes as BRC-100 outbound.
//
// Why a separate file:
//   • The dispatcher is testable without postMessage / DOM.
//   • The same dispatcher backs the W6 sovereign-node WSS endpoint (TS in
//     v0.1; ported to Zig in `runtime/node/src/main.zig` for parity).
//   • Per-method handlers cite §n.n of `WALLET-TIER-CUSTODY.md` for any
//     non-obvious decision.
//
// Method coverage (v0.1):
//   getPublicKey            ✓ — returns identity key, or fresh leaf via
//                              BRC-42 next-index when (protocolID, keyID,
//                              counterparty) supplied.
//   createSignature         ✓ — signs a 32-byte digest at the inferred tier.
//   verifySignature         ✓ — verifies a DER signature against a pubkey.
//   signMessage             ✓ — sha256(message) then sign with identity key.
//   verifyMessage           ✓ — sha256(message) then verify with given pubkey.
//   getNetwork              ✓ — returns "main" (configured at boot).
//   getVersion              ✓ — returns wallet bundle version.
//   createAction            ✓ — select UTXOs, sign, broadcast to ARC (W11).
//
// Failure modes are surfaced as a typed Result so the bridge can decide
// whether to wrap them as 4xx vs 5xx, and so the popup-side dispatcher
// callbacks can render distinct messages.

import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { decodeDer } from './der';
import {
  signSpend,
  signMessage as walletSignMessage,
  getStatus,
  getPolicy,
  classifyTier,
  nextIndexForContext,
  deriveLeafPubkey,
  createAction,
  getIdentitySnapshot,
  type PolicyShape,
  type SignSpendInput,
} from './wallet-ops';
import type { Brc100Envelope } from './brc100';
import { hexToBytes, bytesToHex } from './brc100';
import {
  dispatchChessVerb,
  validateDispatchParams,
  type ChessDispatchParams,
} from './chess-brain-proxy';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// ──────────────────────────────────────────────────────────────────────
// Types
// ──────────────────────────────────────────────────────────────────────

export type Result<T, E> = { ok: true; value: T } | { ok: false; error: E };

export type Brc100Method =
  | 'getPublicKey'
  | 'createSignature'
  | 'verifySignature'
  | 'signMessage'
  | 'verifyMessage'
  | 'getNetwork'
  | 'getVersion'
  | 'createAction'
  /** Non-BRC-100 Semantos extension. Proxies a chess cartridge verb to
   *  the brain so the embedding SPA doesn't hold the operator bearer. */
  | 'chess.dispatch';

/** A dispatcher request body (post-envelope-validation). */
export interface DispatchRequest {
  method: Brc100Method | string;
  /** Free-form per-method params. Each handler validates this. */
  params?: Record<string, unknown>;
}

/** Standardized rejection codes. The numeric values are inspired by HTTP
 *  status codes so the bridge can map them straight into 4xx/5xx without
 *  a translation table. */
export type DispatchErrorCode =
  | 400 /* BAD_REQUEST */
  | 401 /* UNAUTHENTICATED — wrong factor */
  | 403 /* FORBIDDEN — tier locked / cooldown / policy stale */
  | 404 /* NOT_FOUND — wallet not created */
  | 405 /* METHOD_NOT_ALLOWED */
  | 500 /* INTERNAL */
  | 502 /* BAD_GATEWAY — ARC broadcast failure */;

export interface DispatchError {
  code: DispatchErrorCode;
  message: string;
  /** Optional structured detail (e.g. tier number for TIER_LOCKED). */
  detail?: Record<string, unknown>;
}

/** A successful dispatcher response — rendered into the BRC-100 envelope
 *  body by bridge.ts. */
export interface DispatchResponse {
  method: string;
  result: unknown;
}

export type DispatchResult = Result<DispatchResponse, DispatchError>;

// ──────────────────────────────────────────────────────────────────────
// Capability advertisement — what the dispatcher implements (W9 README
// table is generated from this list).
// ──────────────────────────────────────────────────────────────────────

export const METHOD_COVERAGE: ReadonlyArray<{
  method: Brc100Method;
  status: 'implemented' | 'not_implemented';
  note: string;
}> = [
  { method: 'getPublicKey', status: 'implemented', note: 'identity key, or BRC-42 leaf when (protocolID, keyID, counterparty) supplied' },
  { method: 'createSignature', status: 'implemented', note: '32-byte digest input; tier inferred from amountSats param' },
  { method: 'verifySignature', status: 'implemented', note: 'DER signature, lowS-tolerant' },
  { method: 'signMessage', status: 'implemented', note: 'sha256(message) || identity-signed' },
  { method: 'verifyMessage', status: 'implemented', note: 'sha256(message) || verify against caller-supplied pubkey' },
  { method: 'getNetwork', status: 'implemented', note: 'configured at bridge boot — defaults to "main"' },
  { method: 'getVersion', status: 'implemented', note: 'wallet-browser package version' },
  { method: 'createAction', status: 'implemented', note: 'greedy UTXO selection, BRC-42 leaf signing, ARC broadcast' },
  { method: 'chess.dispatch', status: 'implemented', note: 'Semantos extension; proxies chess cartridge verbs to a Semantos brain WSS, bearer per call' },
];

// ──────────────────────────────────────────────────────────────────────
// Caller hooks
// ──────────────────────────────────────────────────────────────────────

/**
 * The dispatcher is stateless except for the wallet's IndexedDB-backed
 * state. Anything that needs an out-of-band UI prompt (e.g. PIN entry for
 * a Tier-1 spend) is delegated via a caller-supplied callback. v0.1 wires
 * this through `bridge.ts` → popup; tests inject a mock that returns a
 * canned factor.
 */
export interface DispatcherDeps {
  /** Network advertisement — typically "main" in production, "testnet" in dev. */
  network: 'main' | 'test' | 'stn';
  /** Wallet bundle version (for getVersion). */
  version: string;
  /**
   * Resolve a tier-N auth factor from the user. Returns null if the user
   * cancelled the prompt. The dispatcher classifies the spend tier
   * before calling — the callback must NOT re-classify.
   */
  promptFactor: (
    ctx: { tier: 1 | 2 | 3; method: string; amountSats: bigint; envelope: Brc100Envelope },
  ) => Promise<Uint8Array | null>;
}

// ──────────────────────────────────────────────────────────────────────
// Top-level dispatch
// ──────────────────────────────────────────────────────────────────────

/**
 * Decode the envelope's body as a BRC-100 RPC request and dispatch. Pure
 * function modulo IndexedDB / WebCrypto — no postMessage in here.
 *
 * Body wire format (v0.1 — pinned to mirror `Plexus dispatch`'s JSON
 * shape so the W6 sovereign-node TS path can share the same parser):
 *   `JSON.stringify({ method: "getPublicKey", params: { ... } })`
 */
export async function dispatch(
  envelope: Brc100Envelope,
  deps: DispatcherDeps,
): Promise<DispatchResult> {
  // Decode body.
  let body: DispatchRequest;
  try {
    const text = new TextDecoder().decode(envelope.body);
    body = JSON.parse(text) as DispatchRequest;
  } catch (e) {
    return reject(400, `body: not JSON — ${(e as Error).message}`);
  }
  if (typeof body?.method !== 'string') {
    return reject(400, 'body: missing `method`');
  }

  switch (body.method) {
    case 'getPublicKey':
      return await methodGetPublicKey(envelope, body.params ?? {});
    case 'createSignature':
      return await methodCreateSignature(envelope, body.params ?? {}, deps);
    case 'verifySignature':
      return methodVerifySignature(body.params ?? {});
    case 'signMessage':
      return await methodSignMessage(body.params ?? {});
    case 'verifyMessage':
      return methodVerifyMessage(body.params ?? {});
    case 'getNetwork':
      return ok('getNetwork', { network: deps.network });
    case 'getVersion':
      return ok('getVersion', { version: deps.version });
    case 'createAction':
      return await methodCreateAction(envelope, body.params ?? {}, deps);
    case 'chess.dispatch':
      return await methodChessDispatch(body.params ?? {});
    default:
      return reject(405, `method not allowed: ${body.method}`);
  }
}

/**
 * Wallet-side proxy for chess cartridge verbs (doublemate.app SPA →
 * iframe wallet → brain). The wallet runs the WSS connection so the
 * bearer never crosses to the SPA process. v0.1 takes bearer as a
 * call-time param; future iteration moves bearer storage into the
 * wallet's PIN-encrypted IndexedDB with a setter UI in the popup.
 */
async function methodChessDispatch(params: Record<string, unknown>): Promise<DispatchResult> {
  const validation = validateDispatchParams(params as Partial<ChessDispatchParams>);
  if (validation !== null) {
    return reject(400, `chess.dispatch: ${validation}`);
  }
  const p = params as unknown as ChessDispatchParams;
  const out = await dispatchChessVerb(p);
  if (out.error) {
    // Map JSON-RPC error codes onto our dispatch codes — -32601 (method
    // not found) → 405, -32602 (invalid params) → 400, else 502 (the
    // brain rejected at transport).
    const code = out.error.code === -32601 ? 405
              : out.error.code === -32602 ? 400
              : 502;
    return reject(code, `brain: ${out.error.message}`);
  }
  return ok('chess.dispatch', { brainResult: out.result });
}

// ──────────────────────────────────────────────────────────────────────
// Per-method handlers
// ──────────────────────────────────────────────────────────────────────

/**
 * `getPublicKey` — returns the identity key by default, or a fresh BRC-42
 * leaf pubkey when the caller passes `protocolID`, `keyID`, and
 * `counterparty`. Mirrors BRC-100's parameterization (§3.5.1).
 *
 * params:
 *   identityKey?: boolean         — return identity key directly (default true if no protocol/counterparty)
 *   protocolID?: string           — BRC-43 protocol ID (UTF-8) → 16-byte hash
 *   counterparty?: string         — 33-byte compressed pubkey hex
 *   forceFresh?: boolean          — allocate a fresh BRC-42 index
 */
async function methodGetPublicKey(
  _env: Brc100Envelope,
  params: Record<string, unknown>,
): Promise<DispatchResult> {
  let identity;
  try {
    identity = getIdentitySnapshot();
  } catch (e) {
    return reject(404, `wallet not created: ${(e as Error).message}`);
  }
  // No protocol context → return identity key (BRC-100 default, §3.5.1).
  if (params.identityKey === true || (params.protocolID === undefined && params.counterparty === undefined)) {
    return ok('getPublicKey', { publicKey: bytesToHex(identity.identityPk) });
  }
  if (typeof params.protocolID !== 'string' || typeof params.counterparty !== 'string') {
    return reject(400, 'getPublicKey: protocolID + counterparty must be strings');
  }
  let counterpartyBytes: Uint8Array;
  try {
    counterpartyBytes = hexToBytes(params.counterparty);
  } catch (e) {
    return reject(400, `getPublicKey: bad counterparty hex — ${(e as Error).message}`);
  }
  if (counterpartyBytes.length !== 33) {
    return reject(400, 'getPublicKey: counterparty must be 33 bytes');
  }
  const protocolHash = nobleSha256(new TextEncoder().encode(params.protocolID)).slice(0, 16);
  const idx = await nextIndexForContext(protocolHash, counterpartyBytes, 0x04, params.protocolID);
  const leafPk = deriveLeafPubkey(protocolHash, counterpartyBytes, idx);
  if (!leafPk) {
    return reject(500, 'getPublicKey: leaf derivation failed — wallet may be locked');
  }
  return ok('getPublicKey', {
    publicKey: bytesToHex(leafPk),
    derivationIndex: idx.toString(),
  });
}

/**
 * `createSignature` — signs a 32-byte digest at the tier inferred from
 * `amountSats`. Tier 1+ goes through the popup factor prompt callback.
 *
 * params:
 *   digestHex: string             — 32-byte preimage, hex
 *   amountSats?: string           — decimal sats (default "0" → tier 0)
 *   protocolID?: string           — BRC-43 protocol ID; when combined with
 *   counterparty?: string         — 33-byte counterparty pubkey hex, and
 *   derivationIndex?: string      — decimal index, the wallet re-derives the
 *                                   BRC-42 leaf key and signs with it instead
 *                                   of the raw tier base.
 */
async function methodCreateSignature(
  envelope: Brc100Envelope,
  params: Record<string, unknown>,
  deps: DispatcherDeps,
): Promise<DispatchResult> {
  if (typeof params.digestHex !== 'string') {
    return reject(400, 'createSignature: digestHex required');
  }
  let digest: Uint8Array;
  try {
    digest = hexToBytes(params.digestHex);
  } catch (e) {
    return reject(400, `createSignature: bad digest hex — ${(e as Error).message}`);
  }
  if (digest.length !== 32) {
    return reject(400, 'createSignature: digest must be 32 bytes');
  }
  const amountSats = parseAmountSats(params.amountSats);
  const policy: PolicyShape = getPolicy();
  const tier = classifyTier(amountSats, policy);

  let factor: Uint8Array | undefined;
  if (tier > 0) {
    // Per W9 spec: the unlock prompt fires exactly once per outer request
    // scope.  The dispatcher does not cache unlocked KEKs across method
    // calls — wallet-ops.signSpend re-locks via clearAllKeks() in `finally`.
    const supplied = await deps.promptFactor({ tier: tier as 1 | 2 | 3, method: 'createSignature', amountSats, envelope });
    if (!supplied) {
      return reject(401, 'createSignature: factor prompt cancelled', { tier });
    }
    factor = supplied;
  }

  // Optional BRC-42 leaf derivation context.
  let derivationContext: SignSpendInput['derivationContext'];
  if (
    typeof params.protocolID === 'string' &&
    typeof params.counterparty === 'string' &&
    typeof params.derivationIndex === 'string'
  ) {
    let cpBytes: Uint8Array;
    try { cpBytes = hexToBytes(params.counterparty); } catch {
      return reject(400, 'createSignature: bad counterparty hex');
    }
    if (cpBytes.length !== 33) return reject(400, 'createSignature: counterparty must be 33 bytes');
    derivationContext = {
      protocolHash: nobleSha256(new TextEncoder().encode(params.protocolID)).slice(0, 16),
      counterparty: cpBytes,
      index: BigInt(params.derivationIndex),
    };
  }

  const result = await signSpend({ digest, amountSats, factor, derivationContext });
  if (!result.ok) {
    return mapWalletError(result.error);
  }
  return ok('createSignature', {
    signatureDer: bytesToHex(result.value.signatureDer),
    tier: result.value.tier,
  });
}

/**
 * `verifySignature` — verifies a DER signature against a pubkey + digest.
 * No state mutation — pure crypto. Mirrors host_checksig but exposed at
 * the BRC-100 layer for dApps that want to verify an envelope-signed blob
 * without the full envelope.
 *
 * params:
 *   publicKey: string             — 33-byte compressed pubkey hex
 *   digestHex: string             — 32-byte digest
 *   signatureDer: string          — DER bytes hex
 */
function methodVerifySignature(params: Record<string, unknown>): DispatchResult {
  const pkHex = params.publicKey;
  const digestHex = params.digestHex;
  const sigHex = params.signatureDer;
  if (typeof pkHex !== 'string' || typeof digestHex !== 'string' || typeof sigHex !== 'string') {
    return reject(400, 'verifySignature: publicKey + digestHex + signatureDer required');
  }
  let pk: Uint8Array, digest: Uint8Array, sig: Uint8Array;
  try {
    pk = hexToBytes(pkHex);
    digest = hexToBytes(digestHex);
    sig = hexToBytes(sigHex);
  } catch (e) {
    return reject(400, `verifySignature: hex decode — ${(e as Error).message}`);
  }
  if (pk.length !== 33) return reject(400, 'verifySignature: publicKey must be 33 bytes');
  if (digest.length !== 32) return reject(400, 'verifySignature: digestHex must be 32 bytes');
  let verified = false;
  try {
    const { r, s } = decodeDer(sig);
    const sigObj = new secp.Signature(r, s);
    verified = secp.verify(sigObj, digest, pk, { lowS: false });
  } catch (e) {
    return ok('verifySignature', { verified: false, error: (e as Error).message });
  }
  return ok('verifySignature', { verified });
}

/**
 * `signMessage` — sha256(message) then sign with identity key.
 *
 * params:
 *   messageHex: string            — message bytes, hex (caller may
 *                                   supply text via TextEncoder upstream)
 */
async function methodSignMessage(params: Record<string, unknown>): Promise<DispatchResult> {
  if (typeof params.messageHex !== 'string') {
    return reject(400, 'signMessage: messageHex required');
  }
  let msg: Uint8Array;
  try {
    msg = hexToBytes(params.messageHex);
  } catch (e) {
    return reject(400, `signMessage: bad message hex — ${(e as Error).message}`);
  }
  const r = await walletSignMessage(msg);
  if (!r.ok) {
    return mapWalletError(r.error);
  }
  let identity;
  try {
    identity = getIdentitySnapshot();
  } catch (e) {
    return reject(404, `wallet not created: ${(e as Error).message}`);
  }
  return ok('signMessage', {
    signatureDer: bytesToHex(r.value),
    publicKey: bytesToHex(identity.identityPk),
  });
}

/**
 * `verifyMessage` — sha256(message) then verify against caller-supplied pk.
 */
function methodVerifyMessage(params: Record<string, unknown>): DispatchResult {
  if (typeof params.messageHex !== 'string' || typeof params.publicKey !== 'string' || typeof params.signatureDer !== 'string') {
    return reject(400, 'verifyMessage: messageHex + publicKey + signatureDer required');
  }
  let msg: Uint8Array, pk: Uint8Array, sig: Uint8Array;
  try {
    msg = hexToBytes(params.messageHex);
    pk = hexToBytes(params.publicKey);
    sig = hexToBytes(params.signatureDer);
  } catch (e) {
    return reject(400, `verifyMessage: hex decode — ${(e as Error).message}`);
  }
  if (pk.length !== 33) return reject(400, 'verifyMessage: publicKey must be 33 bytes');
  let verified = false;
  try {
    const digest = nobleSha256(msg);
    const { r, s } = decodeDer(sig);
    const sigObj = new secp.Signature(r, s);
    verified = secp.verify(sigObj, digest, pk, { lowS: false });
  } catch (e) {
    return ok('verifyMessage', { verified: false, error: (e as Error).message });
  }
  return ok('verifyMessage', { verified });
}

/**
 * `createAction` — select UTXOs, build + sign a P2PKH tx, broadcast to ARC.
 *
 * params:
 *   outputs: Array<{ scriptHex: string; satoshis: string }>
 *   amountSats?: string   — total spend for tier classification (sum of outputs)
 *   arcUrl?: string       — ARC endpoint override
 */
async function methodCreateAction(
  envelope: Brc100Envelope,
  params: Record<string, unknown>,
  deps: DispatcherDeps,
): Promise<DispatchResult> {
  if (!Array.isArray(params.outputs)) {
    return reject(400, 'createAction: outputs must be an array');
  }
  const outputs: Array<{ script: Uint8Array; satoshis: bigint }> = [];
  for (const o of params.outputs as Array<Record<string, unknown>>) {
    if (typeof o.scriptHex !== 'string' || typeof o.satoshis !== 'string') {
      return reject(400, 'createAction: each output needs scriptHex and satoshis');
    }
    let script: Uint8Array;
    try { script = hexToBytes(o.scriptHex); } catch {
      return reject(400, 'createAction: bad scriptHex in output');
    }
    outputs.push({ script, satoshis: BigInt(o.satoshis) });
  }
  const amountSats = parseAmountSats(params.amountSats) ||
    outputs.reduce((s, o) => s + o.satoshis, 0n);
  const arcUrl = typeof params.arcUrl === 'string' ? params.arcUrl : undefined;

  const policy = getPolicy();
  const tier = classifyTier(amountSats, policy);
  let factor: Uint8Array | undefined;
  if (tier > 0) {
    const supplied = await deps.promptFactor({ tier: tier as 1 | 2 | 3, method: 'createAction', amountSats, envelope });
    if (!supplied) return reject(401, 'createAction: factor prompt cancelled', { tier });
    factor = supplied;
  }

  const result = await createAction({ outputs, amountSats, factor, arcUrl });
  if (!result.ok) return mapWalletError(result.error);
  return ok('createAction', { txid: result.value.txid, rawTxHex: result.value.rawTxHex });
}

// Status endpoint — non-BRC-100, but useful for the popup dispatch path
// to render the same data the browser-internal status panel does.
export async function dispatchStatus(): Promise<DispatchResult> {
  const r = await getStatus();
  if (!r.ok) return mapWalletError(r.error);
  return ok('status', r.value);
}

// ──────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────

function ok(method: string, result: unknown): DispatchResult {
  return { ok: true, value: { method, result } };
}

function reject(
  code: DispatchErrorCode,
  message: string,
  detail?: Record<string, unknown>,
): DispatchResult {
  return { ok: false, error: { code, message, detail } };
}

function parseAmountSats(raw: unknown): bigint {
  if (raw === undefined || raw === null) return 0n;
  if (typeof raw === 'number') {
    if (!Number.isFinite(raw) || raw < 0) return 0n;
    return BigInt(Math.floor(raw));
  }
  if (typeof raw === 'string') {
    if (!/^\d+$/.test(raw)) return 0n;
    return BigInt(raw);
  }
  return 0n;
}

function mapWalletError(err: { kind: string; [k: string]: unknown }): DispatchResult {
  switch (err.kind) {
    case 'NOT_CREATED':
      return reject(404, 'wallet not created');
    case 'ALREADY_CREATED':
      return reject(403, 'wallet already created');
    case 'BAD_INPUT':
      return reject(400, `bad input: ${String(err.reason ?? '')}`);
    case 'WRONG_FACTOR':
      return reject(401, 'wrong factor');
    case 'TIER_LOCKED':
      return reject(403, 'tier locked', { tier: err.tier });
    case 'TIER3_COOLDOWN':
      return reject(403, 'tier 3 cooldown active', { secondsRemaining: err.secondsRemaining });
    case 'STALE_POLICY':
      return reject(403, 'policy update is not monotonic', {
        localVersion: err.localVersion,
        suppliedVersion: err.suppliedVersion,
      });
    case 'INSUFFICIENT_FUNDS':
      return reject(400, 'insufficient funds', { needed: String(err.needed), available: String(err.available) });
    case 'BROADCAST_FAILED':
      return reject(502, `broadcast failed: ${String(err.reason ?? '')}`);
    case 'INTERNAL':
      return reject(500, `internal: ${String(err.reason ?? '')}`);
    default:
      return reject(500, `unknown wallet error: ${err.kind}`);
  }
}

```
