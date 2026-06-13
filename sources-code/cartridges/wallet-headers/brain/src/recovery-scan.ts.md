---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/recovery-scan.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.662338+00:00
---

# cartridges/wallet-headers/brain/src/recovery-scan.ts

```ts
// WA4 — Recovery sync via indexer scan.
//
// After a fresh-device recovery (`recoverWallet` ingested the dispatch
// envelope), the wallet has its identity seed but an empty OutputStore.
// This module bridges the gap by scanning a *bounded* address space —
// the (protocolHash, counterparty) contexts the recovery envelope
// carries — over a pluggable on-chain indexer (WhatsOnChain by default,
// ARC / GorillaPool as alternates) and rebuilding the OutputStore from
// every unspent UTXO it finds.
//
// Spec: docs/design/WALLET-ACTIVE-USE-ROADMAP.md §2 / WA4.
//
// Indexer-pluggability is the key seam. Tests inject a synthetic
// `MockIndexer`; production wallet wires `WhatsOnChainIndexer`. The
// scan loop, gap-window logic, and resume support are independent of
// indexer choice.
//
// Counterparty-push (BSV overlay) recovery is the right long-term
// answer — peer notifies wallet at payment time, no chain scan needed.
// That's WO (v0.3); WA4's indexer-scan is the v0.1 answer.

import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';

import {
  deriveLeafSync,
} from './host';
import {
  buildP2pkhScript,
  getIdentitySnapshot,
  recordContext,
  listContextRegistry,
  snapshotDerivationContexts,
  KV_KEYS,
} from './wallet-ops';
import {
  outputStore,
  type OutputRecord,
} from './output-store';
import { kvGet, kvPut } from './storage';
import type { DerivationStateRecord } from './plexus/envelope';

secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// ──────────────────────────────────────────────────────────────────────
// Indexer interface
// ──────────────────────────────────────────────────────────────────────

export interface IndexedUtxo {
  txid: Uint8Array; // 32 bytes
  vout: number;
  satoshis: bigint;
  /** Hex of the locking script (P2PKH for BRC-29 wallet payments). */
  lockingScriptHex: string;
  confirmations: number;
}

/** Trust model the indexer adapter operates under.
 *
 *  • `centralized` — wallet trusts a single third-party endpoint (WoC,
 *    GorillaPool). Convenient, low-latency, but the operator can lie
 *    about UTXO state. v0.1 default.
 *  • `multi-source` — wallet queries several centralized indexers and
 *    cross-checks. Reduces single-operator risk; v0.2 stub.
 *  • `spv` — UTXOs are validated against a locally-held header chain via
 *    the WH headers verifier. Trustless. The target end state.
 *  • `mock` — deterministic fixture (tests, dev). */
export type IndexerTrustModel = 'centralized' | 'multi-source' | 'spv' | 'mock';

export interface Indexer {
  /** What trust assumptions this adapter requires. Surfaced to the user
   *  in the popup-recovery progress UI so they know what they're trusting. */
  trustModel: IndexerTrustModel;
  /** Return UTXOs at a given address. WoC `/v1/bsv/{network}/address/{addr}/unspent`. */
  getUnspent(addressHex20: Uint8Array): Promise<IndexedUtxo[]>;
  /** Return the BEEF blob for a given txid. WoC: `/v1/bsv/{net}/tx/{txid}/beef`. */
  getBeef(txid: Uint8Array): Promise<Uint8Array | null>;
}

// ──────────────────────────────────────────────────────────────────────
// Scan options + progress
// ──────────────────────────────────────────────────────────────────────

export interface RecoverySyncOptions {
  indexer: Indexer;
  /** Gap window — stop scanning a context after N consecutive empty indices.
   *  Spec default = 100. */
  gapWindow?: number;
  /** Bound the per-context scan even when the indexer keeps returning hits.
   *  Defensive — prevents runaway scans on hostile / misconfigured indexers. */
  maxIndexPerContext?: number;
  /** Caller can pause/cancel the scan; the loop checks this between calls. */
  abortSignal?: AbortSignal;
  /** Called with progress every N addresses; the popup uses this to update
   *  the bar + persist resume state. */
  onProgress?: (p: ScanProgress) => void;
  /** Hook for BEEF verification. v0.1 ships a no-op (structural-only) check
   *  since `kernel_verify_beef_spv` isn't bound; v0.2 plugs in the real
   *  cell-engine SPV verifier. Returns true if the BEEF is valid for the
   *  supplied txid. */
  verifyBeef?: (beef: Uint8Array, txid: Uint8Array) => Promise<boolean>;
}

export interface ScanProgress {
  contextsTotal: number;
  contextsCompleted: number;
  contextLabel: string;
  utxosFound: number;
  satsRecovered: bigint;
  /** Estimated remaining contexts; a heuristic for time. */
  contextsRemaining: number;
}

// ──────────────────────────────────────────────────────────────────────
// Result + resume state
// ──────────────────────────────────────────────────────────────────────

export interface RecoverySyncResult {
  status: 'COMPLETE' | 'INCOMPLETE' | 'FAILED';
  utxosRecovered: number;
  satsRecovered: bigint;
  /** Per-context max index found (next stateNextIndex returns this + 1). */
  contextsAdvanced: Record<string, number>;
  /** If status != COMPLETE, why. */
  diagnostic: string | null;
}

export interface RecoveryScanState {
  /** Hex `protocolHash:counterparty` keys this scan has finished. */
  completedContexts: string[];
  utxosRecovered: number;
  satsRecoveredDec: string;
  /** Unix seconds when persisted last. */
  updatedAt: number;
  status: 'IN_PROGRESS' | 'COMPLETE' | 'INCOMPLETE' | 'FAILED';
  /** Diagnostic string when status === FAILED / INCOMPLETE. */
  diagnostic: string | null;
}

const DEFAULT_GAP_WINDOW = 100;
const DEFAULT_MAX_INDEX = 10_000;
/** Persist progress every N addresses scanned — keeps resume cheap. */
const PROGRESS_PERSIST_EVERY = 10;

// ──────────────────────────────────────────────────────────────────────
// recoverySync — the scan loop
// ──────────────────────────────────────────────────────────────────────

export async function recoverySync(
  opts: RecoverySyncOptions,
): Promise<RecoverySyncResult> {
  const gapWindow = opts.gapWindow ?? DEFAULT_GAP_WINDOW;
  const maxIndex = opts.maxIndexPerContext ?? DEFAULT_MAX_INDEX;
  const verifyBeef = opts.verifyBeef ?? defaultVerifyBeef;

  // Identity sk is required — every leaf derivation uses (identitySk,
  // protocolHash, counterparty, index). recoverWallet stashes it in
  // runtime state, so this throws if the caller hasn't recovered.
  const id = getIdentitySnapshot();

  // Build the context list the scan will iterate. Prefer the live
  // registry (recoverWallet repopulates from envelope) since it's the
  // exhaustive set per WA3. Fall back to snapshotDerivationContexts so
  // pre-WA3 envelopes still produce *something*.
  const registry = await listContextRegistry();
  const fromSnapshot = await snapshotDerivationContexts();
  const allContexts = mergeContextLists(registry, fromSnapshot);

  if (allContexts.length === 0) {
    return {
      status: 'COMPLETE',
      utxosRecovered: 0,
      satsRecovered: 0n,
      contextsAdvanced: {},
      diagnostic: 'no contexts to scan',
    };
  }

  // Resume support — start from whatever state was previously persisted.
  const persisted = await loadResumeState();
  const completedSet = new Set(persisted?.completedContexts ?? []);
  let utxosRecovered = persisted?.utxosRecovered ?? 0;
  let satsRecovered = persisted ? BigInt(persisted.satsRecoveredDec) : 0n;

  const contextsAdvanced: Record<string, number> = {};
  let consecutiveAbortChecks = 0;

  try {
    for (let ctxIdx = 0; ctxIdx < allContexts.length; ctxIdx++) {
      const ctx = allContexts[ctxIdx]!;
      const ctxKey = `${ctx.protocolHashHex}:${ctx.counterpartyHex}`;
      if (completedSet.has(ctxKey)) continue;

      let consecutiveEmpty = 0;
      let lastFound = ctx.startIndex - 1;
      let scanIndex = ctx.startIndex;

      while (consecutiveEmpty < gapWindow && scanIndex <= maxIndex) {
        if (opts.abortSignal?.aborted) {
          throw new RecoveryAbortedError('aborted by caller');
        }

        // Derive the leaf key + its hash160 (P2PKH address).
        const childSk = deriveLeafSync(
          id.identitySk,
          ctx.protocolHash,
          ctx.counterparty,
          BigInt(scanIndex),
        );
        if (!childSk) {
          // Bad index (1-in-2^256 chance) — skip but treat as empty.
          consecutiveEmpty++;
          scanIndex++;
          continue;
        }
        const childPk = secp.getPublicKey(childSk, true);
        const lockingScript = buildP2pkhScript(childPk);
        const addressH160 = lockingScript.slice(3, 23);

        let unspent: IndexedUtxo[];
        try {
          unspent = await opts.indexer.getUnspent(addressH160);
        } catch (e) {
          childSk.fill(0);
          throw new RecoveryIndexerError(`getUnspent failed at index ${scanIndex}: ${(e as Error).message}`);
        }

        if (unspent.length > 0) {
          for (const utxo of unspent) {
            const beef = await opts.indexer.getBeef(utxo.txid);
            if (!beef) continue;
            const valid = await verifyBeef(beef, utxo.txid);
            if (!valid) continue;
            const record: OutputRecord = {
              outpoint: { txid: utxo.txid, vout: utxo.vout },
              satoshis: utxo.satoshis,
              lockingScript,
              derivedKeyHash: nobleSha256(childPk),
              derivationContext: {
                protocolHash: ctx.protocolHash,
                counterparty: ctx.counterparty,
                index: BigInt(scanIndex),
              },
              beef,
              basket: 'default',
              tags: [],
              customInstructions: new Uint8Array(0),
              confirmations: utxo.confirmations,
              status: 'unspent',
              spendingTxid: null,
            };
            const insert = await outputStore.addOutput(record);
            if (insert.inserted) {
              utxosRecovered++;
              satsRecovered += utxo.satoshis;
            }
          }
          lastFound = scanIndex;
          consecutiveEmpty = 0;
        } else {
          consecutiveEmpty++;
        }

        childSk.fill(0);
        scanIndex++;
        consecutiveAbortChecks++;
        if (consecutiveAbortChecks % PROGRESS_PERSIST_EVERY === 0) {
          opts.onProgress?.({
            contextsTotal: allContexts.length,
            contextsCompleted: ctxIdx,
            contextLabel: contextLabelFor(ctx),
            utxosFound: utxosRecovered,
            satsRecovered,
            contextsRemaining: allContexts.length - ctxIdx,
          });
          await persistResumeState({
            completedContexts: [...completedSet],
            utxosRecovered,
            satsRecoveredDec: satsRecovered.toString(),
            updatedAt: Math.floor(Date.now() / 1000),
            status: 'IN_PROGRESS',
            diagnostic: null,
          });
        }
      }

      if (lastFound >= 0) {
        contextsAdvanced[ctxKey] = lastFound;
      }
      // Record the context even if the scan found nothing — WA3 gap-scan
      // semantics rely on the registry being populated.
      await recordContext(ctx.protocolHash, ctx.counterparty);
      completedSet.add(ctxKey);

      opts.onProgress?.({
        contextsTotal: allContexts.length,
        contextsCompleted: ctxIdx + 1,
        contextLabel: contextLabelFor(ctx),
        utxosFound: utxosRecovered,
        satsRecovered,
        contextsRemaining: allContexts.length - ctxIdx - 1,
      });
    }

    const result: RecoverySyncResult = {
      status: 'COMPLETE',
      utxosRecovered,
      satsRecovered,
      contextsAdvanced,
      diagnostic: null,
    };
    await persistResumeState({
      completedContexts: [...completedSet],
      utxosRecovered,
      satsRecoveredDec: satsRecovered.toString(),
      updatedAt: Math.floor(Date.now() / 1000),
      status: 'COMPLETE',
      diagnostic: null,
    });
    return result;
  } catch (e) {
    const isAbort = e instanceof RecoveryAbortedError;
    const status: 'INCOMPLETE' | 'FAILED' = isAbort ? 'INCOMPLETE' : 'FAILED';
    const result: RecoverySyncResult = {
      status,
      utxosRecovered,
      satsRecovered,
      contextsAdvanced,
      diagnostic: (e as Error).message,
    };
    await persistResumeState({
      completedContexts: [...completedSet],
      utxosRecovered,
      satsRecoveredDec: satsRecovered.toString(),
      updatedAt: Math.floor(Date.now() / 1000),
      status,
      diagnostic: (e as Error).message,
    });
    return result;
  }
}

// ──────────────────────────────────────────────────────────────────────
// Resume state persistence
// ──────────────────────────────────────────────────────────────────────

const RECOVERY_SCAN_STATE_KEY = 'recovery-scan-state';
// Defensive — if KV_KEYS doesn't already export the slot, fall back to a
// literal here. The popup status panel reads this same key.
const _RESUME_KEY = (KV_KEYS as Record<string, string>).RECOVERY_SCAN_STATE ?? RECOVERY_SCAN_STATE_KEY;

export async function loadResumeState(): Promise<RecoveryScanState | null> {
  return await kvGet<RecoveryScanState>(_RESUME_KEY);
}

export async function persistResumeState(state: RecoveryScanState): Promise<void> {
  await kvPut(_RESUME_KEY, state);
}

export async function clearResumeState(): Promise<void> {
  await kvPut(_RESUME_KEY, null);
}

// ──────────────────────────────────────────────────────────────────────
// Errors
// ──────────────────────────────────────────────────────────────────────

export class RecoveryAbortedError extends Error {
  constructor(msg: string) {
    super(msg);
    this.name = 'RecoveryAbortedError';
  }
}

export class RecoveryIndexerError extends Error {
  constructor(msg: string) {
    super(msg);
    this.name = 'RecoveryIndexerError';
  }
}

// ──────────────────────────────────────────────────────────────────────
// Default BEEF verifier (structural until kernel_verify_beef_spv binds).
// Mirrors the one in wallet-ops.ts; kept local so recovery-scan is
// importable in isolation.
// ──────────────────────────────────────────────────────────────────────

async function defaultVerifyBeef(beef: Uint8Array, txid: Uint8Array): Promise<boolean> {
  if (beef.length < 32) return false;
  // Synthetic test vectors (no magic) carry the txid in the first 32 bytes.
  // BEEF v1/v2/atomic carry it after a 4-byte magic. Both pass a structural
  // check that there's enough body to hold the txid.
  const magic = new DataView(beef.buffer, beef.byteOffset, 4).getUint32(0, true);
  const knownMagics = [0x0100beef, 0x0200beef, 0x01010101];
  if (knownMagics.includes(magic)) {
    if (beef.length < 4 + 32) return false;
    return bytesEqual(beef.slice(4, 4 + 32), txid);
  }
  return bytesEqual(beef.slice(0, 32), txid);
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i]! ^ b[i]!;
  return diff === 0;
}

// ──────────────────────────────────────────────────────────────────────
// Context list assembly
// ──────────────────────────────────────────────────────────────────────

interface ScanContext {
  protocolHashHex: string;
  counterpartyHex: string;
  protocolHash: Uint8Array; // 16
  counterparty: Uint8Array; // 33
  /** Where to start scanning from. Pre-existing currentIndex+1 if known,
   *  else 0. */
  startIndex: number;
}

function mergeContextLists(
  registry: Array<{ protocolHash: string; counterparty: string }>,
  snapshot: DerivationStateRecord[],
): ScanContext[] {
  const map = new Map<string, ScanContext>();

  for (const e of registry) {
    const key = `${e.protocolHash}:${e.counterparty}`;
    if (!map.has(key)) {
      map.set(key, {
        protocolHashHex: e.protocolHash,
        counterpartyHex: e.counterparty,
        protocolHash: hexToBytes(e.protocolHash),
        counterparty: hexToBytes(e.counterparty),
        startIndex: 0,
      });
    }
  }

  for (const r of snapshot) {
    const key = `${r.protocolHash}:${r.counterparty}`;
    const existing = map.get(key);
    const startIndex = r.currentIndex !== null ? r.currentIndex + 1 : 0;
    if (existing) {
      // Always start scan from 0 (the scan is meant to find ALL utxos
      // including those at older indices); but for the "pure resume"
      // flow we'd start at currentIndex+1. v0.1 starts at 0 to be safe.
      existing.startIndex = 0;
    } else {
      map.set(key, {
        protocolHashHex: r.protocolHash,
        counterpartyHex: r.counterparty,
        protocolHash: hexToBytes(r.protocolHash),
        counterparty: hexToBytes(r.counterparty),
        startIndex: 0,
      });
    }
    void startIndex;
  }

  return Array.from(map.values());
}

function contextLabelFor(ctx: ScanContext): string {
  const cpShort = ctx.counterpartyHex.slice(0, 8);
  return `${ctx.protocolHashHex.slice(0, 8)} → ${cpShort}…`;
}

function hexToBytes(hex: string): Uint8Array {
  if (hex.length === 0) return new Uint8Array(0);
  if (hex.length % 2 !== 0) throw new Error('hex: odd length');
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

// ──────────────────────────────────────────────────────────────────────
// Indexer adapters
// ──────────────────────────────────────────────────────────────────────

/** WhatsOnChain (v0.1 default). Free tier: ~3 req/sec. Wallet config can
 *  override the network and supply an API key for higher rate. */
export interface WhatsOnChainOptions {
  network?: 'main' | 'test';
  /** Optional API key for higher rate-limit. */
  apiKey?: string;
  /** Override fetch for tests. */
  fetchImpl?: typeof fetch;
}

export function createWhatsOnChainIndexer(opts: WhatsOnChainOptions = {}): Indexer {
  const network = opts.network ?? 'main';
  const fetchImpl = opts.fetchImpl ?? fetch;
  const headers: Record<string, string> = { Accept: 'application/json' };
  if (opts.apiKey) headers['Authorization'] = `Bearer ${opts.apiKey}`;
  const base = `https://api.whatsonchain.com/v1/bsv/${network}`;

  return {
    trustModel: 'centralized',
    async getUnspent(addressH160) {
      // WoC accepts P2PKH addresses; the wallet stores hash160s. Wrap in a
      // base58check P2PKH address for the lookup. v0.1 ships the wrap
      // inline; v0.2 may use a paymail-aware indexer instead.
      const address = base58CheckP2pkh(addressH160, network === 'main' ? 0x00 : 0x6f);
      const r = await fetchImpl(`${base}/address/${address}/unspent`, { headers });
      if (!r.ok) {
        if (r.status === 404) return [];
        throw new Error(`WoC ${r.status}`);
      }
      const j = (await r.json()) as Array<{
        tx_hash: string;
        tx_pos: number;
        value: number;
        height: number;
      }>;
      return j.map((u) => ({
        txid: hexToBytes(u.tx_hash),
        vout: u.tx_pos,
        satoshis: BigInt(u.value),
        // P2PKH address script — WoC doesn't include the script in the
        // unspent response; recompute from the address.
        lockingScriptHex: '', // populated by the scan from the derived key
        confirmations: Math.max(0, u.height ? 0 : 0),
      }));
    },
    async getBeef(txid) {
      const txidHex = bytesToHex(txid);
      const r = await fetchImpl(`${base}/tx/${txidHex}/beef`, { headers });
      if (!r.ok) {
        if (r.status === 404) return null;
        throw new Error(`WoC beef ${r.status}`);
      }
      const j = (await r.json()) as { beef?: string };
      if (!j.beef) return null;
      return hexToBytes(j.beef);
    },
  };
}

function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

/** Minimal base58check encoder for P2PKH addresses. Kept inline so the
 *  module is self-contained. */
function base58CheckP2pkh(hash160: Uint8Array, version: number): string {
  const payload = new Uint8Array(1 + 20);
  payload[0] = version;
  payload.set(hash160, 1);
  const c1 = nobleSha256(payload);
  const c2 = nobleSha256(c1);
  const checksum = c2.slice(0, 4);
  const buf = new Uint8Array(payload.length + 4);
  buf.set(payload, 0);
  buf.set(checksum, payload.length);
  return base58Encode(buf);
}

const B58_ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

function base58Encode(bytes: Uint8Array): string {
  let n = 0n;
  for (const b of bytes) n = (n << 8n) | BigInt(b);
  let out = '';
  while (n > 0n) {
    const r = Number(n % 58n);
    n /= 58n;
    out = B58_ALPHABET[r]! + out;
  }
  // Leading zero-bytes → leading '1's.
  for (const b of bytes) {
    if (b === 0) out = '1' + out;
    else break;
  }
  return out;
}

// ──────────────────────────────────────────────────────────────────────
// MockIndexer — for tests + offline wallet setups.
// ──────────────────────────────────────────────────────────────────────

export interface MockIndexerSeed {
  /** Pre-populated address → utxo[] map. Address keyed by hash160 hex. */
  unspent: Record<string, IndexedUtxo[]>;
  /** Pre-populated txid hex → BEEF blob. */
  beefs: Record<string, Uint8Array>;
}

export function createMockIndexer(seed: MockIndexerSeed): Indexer {
  return {
    trustModel: 'mock',
    async getUnspent(addressH160) {
      const key = bytesToHex(addressH160);
      return seed.unspent[key] ?? [];
    },
    async getBeef(txid) {
      return seed.beefs[bytesToHex(txid)] ?? null;
    },
  };
}

```
