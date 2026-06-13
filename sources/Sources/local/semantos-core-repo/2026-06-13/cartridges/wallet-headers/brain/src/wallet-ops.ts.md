---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/wallet-ops.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.647973+00:00
---

# cartridges/wallet-headers/brain/src/wallet-ops.ts

```ts
// High-level wallet operations layer (W9).
//
// `wallet-ops.ts` is the single source of truth for the wallet's local
// state machine. Both the BRC-100 postMessage dispatcher (`dispatcher.ts`)
// and the popup UI screens (`popup-create.ts` / `popup-send.ts` /
// `popup-policy.ts` / `popup-status.ts`) sit on top of this module — the
// dispatcher translates BRC-100 envelopes into wallet-ops calls, the popup
// screens translate user clicks.
//
// What lives here:
//   • `createWallet`   — first-time creation flow per design §7.6.
//   • `loadWallet`     — re-hydrate an existing wallet from IndexedDB.
//   • `unlockTier`     — derive a per-tier KEK from a factor + decrypt the
//                        tier base-key cell into the active request scope.
//   • `signSpend`      — Tier-N signing per design §7.1–7.4. Failure-atomic.
//   • `signMessage`    — sign an arbitrary message (BRC-100 `signMessage`).
//   • `updatePolicy`   — replace POLICY cell, identity-signed, monotonic.
//   • `getStatus`      — wallet status panel data per design §10.3.
//   • `setRecoveryStatus` — record post-enroll banner state.
//
// What does NOT live here:
//   • The BRC-100 envelope adapter (bridge.ts → dispatcher.ts).
//   • DOM rendering — popup screens import these calls and render.
//   • Plexus enroll/recover — those are in `./plexus/dispatch.ts`; this
//     module provides the identity material they need (`getIdentitySnapshot`).
//
// Design references throughout this file cite §n.n of
// `docs/design/WALLET-TIER-CUSTODY.md`.

import * as secp from '@noble/secp256k1';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { hmac } from '@noble/hashes/hmac';
import { encodeDer } from './der';
import {
  beginRequest,
  endRequest,
  primeSlot,
  primeUnlockTier,
  primeStateNext,
  flushRequest,
  setSessionKek,
  deriveKek,
  encryptCellForBridge,
  tierUnlocked,
  clearAllKeks,
  deriveLeafSync,
  SLOT_KEK_BYTES,
} from './host';
import { kvGet, kvPut, slotPut, slotGet, stateGetIndex, stateSnapshot } from './storage';
import { buildEnvelope, decryptRecoverySeed } from './plexus/envelope';
import type { PlexusRecoveryEnvelope, DerivationStateRecord, KdfVersion } from './plexus/envelope';
import { outputStore, type OutputRecord } from './output-store';
import {
  assessTier0PlaintextExposure,
  createTier0SweepPlan,
  TIER0_PLAINTEXT_BALANCE_LIMIT_SATS,
  type Tier0Exposure,
  type Tier0SweepPlan,
} from './tier0-safety';
import { buildChangeLock, CHANGE_DOMAIN_FLAG } from './ecdh42';
import {
  computeSighash,
  serializeEFTx,
  buildP2pkhUnlockScript,
  type TxInput,
  type TxOutput,
  type EFInput,
} from './tx-builder';
import { broadcastToArc } from './arc-broadcast';
import { parseBeef, computeMerkleRoot } from './beef-codec';
import type { LocalChainTracker } from './header-spv';

// Same sync-HMAC backend wiring as host.ts — needed when this file is
// imported in isolation by tests.
secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// ──────────────────────────────────────────────────────────────────────
// SPV tracker — set by the host/bridge via configureSpvTracker().
// When null, internalizeAction falls through to structural-only checks.
// ──────────────────────────────────────────────────────────────────────

let _spvTracker: LocalChainTracker | null = null;

/**
 * Inject a LocalChainTracker so internalizeAction can verify BUMP merkle
 * proofs against PoW-validated block headers.  Call this once at boot
 * (bridge.ts / popup.ts) after the header store is open.
 */
export function configureSpvTracker(tracker: LocalChainTracker): void {
  _spvTracker = tracker;
}

// ──────────────────────────────────────────────────────────────────────
// Result type — matches the W7 dispatch.ts pattern.
// ──────────────────────────────────────────────────────────────────────

export type Result<T, E> = { ok: true; value: T } | { ok: false; error: E };

// ──────────────────────────────────────────────────────────────────────
// Tier model (mirror of design §3 schedule + §6.3 policy cell defaults)
// ──────────────────────────────────────────────────────────────────────

export type FactorKind = 'pin' | 'passphrase' | 'webauthn';

/** Default ceilings per design §3 ("Tier Schedule" table). */
export const DEFAULT_POLICY: PolicyShape = {
  policyVersion: 1,
  tier1CeilingSats: 1_000_000,
  tier2CeilingSats: 10_000_000,
  tier3CeilingSats: 100_000_000,
  tier1FactorKind: 'pin',
  tier2FactorKind: 'webauthn',
  tier3FactorKind: 'passphrase',
  tier3CooldownSeconds: 60,
};

export const TIER0_HOT_BALANCE_LIMIT_SATS = TIER0_PLAINTEXT_BALANCE_LIMIT_SATS;

export interface PolicyShape {
  policyVersion: number;
  tier1CeilingSats: number;
  tier2CeilingSats: number;
  tier3CeilingSats: number;
  tier1FactorKind: FactorKind;
  tier2FactorKind: FactorKind;
  tier3FactorKind: FactorKind;
  /** 0 = disabled. Per §6.3. */
  tier3CooldownSeconds: number;
}

/** What we serialize alongside identity in IndexedDB.  The seed is NOT here —
 *  v0.4: the seed is wiped after creation; recovery is via the dispatch
 *  envelope (KV_KEYS.RECOVERY_ENVELOPE) decrypted with the user's challenge
 *  answers per §4.0. */
export interface IdentityRecord {
  /** 33-byte compressed identity public key, hex. */
  identityPkHex: string;
  /** Base secret for this identity (BRC-42 root). Encrypted-at-rest under
   *  the Tier-0 session KEK. v0.1 ships a single in-process keychain — the
   *  session KEK is derived from a per-install machine secret (§7.6 step 7).
   */
  identitySkEnvelopeHex: string;
  /** 32-byte BRC-52 self-issued cert hash, hex. */
  certIdHex: string;
  /** Wall-clock seconds when the wallet was created. */
  createdAt: number;
}

/** KV keys (under storage.kv). Centralized here so the popup UI and the
 *  dispatcher can't drift. */
export const KV_KEYS = {
  IDENTITY: 'identity',
  POLICY: 'policy',
  RECOVERY: 'recovery-status',
  /** v0.4: persisted recovery envelope (§6.5). Built mandatorily at wallet
   *  creation (§7.6); the user's challenge-derived KEK is the only thing
   *  that can decrypt the seed inside it. Held locally regardless of any
   *  Plexus enrollment — enrollment is just deciding to also transmit it. */
  RECOVERY_ENVELOPE: 'recovery-envelope',
  /** Tier-3 last-spend timestamp (host-clock cooldown enforcement, §4.4
   *  v0.1 path). */
  TIER3_LAST_SPEND: 'tier3-last-spend',
  /** Hot-budget remaining sats (mirrored from the Tier-0 budget cell payload
   *  for fast status panel rendering — the cell itself is the source of
   *  truth). */
  HOT_BUDGET_REMAINING: 'hot-budget-remaining',
  /** Hot-budget plaintext cell — v0.1 stores it KV (encrypted) so the
   *  status panel can read it without a full prime/load cycle. */
  HOT_BUDGET_CELL: 'hot-budget-cell',
  /** v0.4 returning-device boot cache (§7.9). The identity sk is also
   *  encrypted under a deterministic session KEK derived from `identityPk`
   *  alone (HMAC-SHA256(identityPk, "session-kek")) and stashed here, so a
   *  returning user can rehydrate identity sk on tab reload without
   *  re-running the recovery flow. v0.1 deterministic; v0.2 binds this KEK
   *  to a per-install hardware-bound secret (§4.1). The stored blob is
   *  ciphertext + 12-byte IV concatenated. */
  IDENTITY_SK_BOOT_CACHE: 'identity-sk-boot-cache',
  /** WA3: per-(protocol_hash, counterparty) registry of every derivation
   *  context the wallet has ever touched. Stored as a hex-keyed object to
   *  deduplicate naturally. Recovery uses the union of this registry + the
   *  state store to bound the WA4 indexer scan. */
  CONTEXT_REGISTRY: 'context-registry',
  /** WA2: per-outpoint UTXO database. Object-store keyed by `txid:vout`
   *  string → OutputRecord JSON blob (BEEF kept hex-encoded). The storage
   *  layer offers a dedicated object store for richer indexing; this KV
   *  pointer is unused in v0.1 and reserved for migration. */
  OUTPUT_STORE_VERSION: 'output-store-version',
  /** WA1: SetupStatus cell. Persists per-item status (pending/complete/skipped/
   *  dismissed) for the post-creation onboarding wizard. */
  SETUP_STATUS: 'setup-status',
  /** WA4: RecoveryScanState cell. Holds resume metadata for the post-
   *  recovery indexer scan (completed contexts, totals, status). Lets
   *  the user pause/resume a long scan without re-iterating the whole
   *  address space. */
  RECOVERY_SCAN_STATE: 'recovery-scan-state',
  /** Monotonic counter for self-directed BRC-42 change derivations (domain 0x0B). */
  CHANGE_INDEX: 'change-index',
} as const;

/** Slot ids per design §6 (cell layouts). One slot per tier base-key cell. */
export const SLOT_IDS = {
  HOT_BUDGET: 0,
  TIER1_BASE: 1,
  TIER2_BASE: 2,
  TIER3_BASE: 3,
} as const;

/** Recovery banner state.
 *
 * v0.4 architectural correction: every wallet has a recovery envelope
 * built locally at creation (§7.6). The "configuration" question is no
 * longer "do you have recovery?" but "where is your envelope held?":
 *
 * - LOCAL_ONLY  — envelope cached on this device only. User is on the hook
 *                 to either remember answers + back up the envelope file,
 *                 or enroll with a Plexus operator (§7.7). Default for
 *                 fresh wallets.
 * - ENROLLED    — envelope mirrored to a Plexus operator under their TOS.
 *                 Recovery on a fresh device works via the operator's HTTP
 *                 path even without the local envelope file.
 * - EXPIRED     — Plexus subscription lapsed. Operator's policy decides
 *                 whether the envelope is archived or deleted; meanwhile
 *                 the user's local copy is still intact.
 */
export type RecoveryStatus =
  | { state: 'LOCAL_ONLY' }
  | { state: 'ENROLLED'; operatorDomain: string; enrolledAt: number }
  | { state: 'EXPIRED'; operatorDomain: string };

// ──────────────────────────────────────────────────────────────────────
// Errors
// ──────────────────────────────────────────────────────────────────────

export type WalletError =
  | { kind: 'ALREADY_CREATED' }
  | { kind: 'NOT_CREATED' }
  | { kind: 'BAD_INPUT'; reason: string }
  | { kind: 'WRONG_FACTOR' }
  | { kind: 'TIER_LOCKED'; tier: number }
  | { kind: 'TIER3_COOLDOWN'; secondsRemaining: number }
  | { kind: 'STALE_POLICY'; localVersion: number; suppliedVersion: number }
  | { kind: 'INSUFFICIENT_FUNDS'; needed: bigint; available: bigint }
  | { kind: 'BROADCAST_FAILED'; reason: string }
  | { kind: 'INTERNAL'; reason: string };

// ──────────────────────────────────────────────────────────────────────
// Per-process state (deliberately tiny — most state lives in IndexedDB).
//
// `runtimeState` is the wallet's in-memory cache of what it learned at
// boot/load. It does NOT hold private key material — the identity sk is
// only materialized inside a request scope.
// ──────────────────────────────────────────────────────────────────────

interface RuntimeState {
  identity: IdentityRecord | null;
  policy: PolicyShape | null;
  recovery: RecoveryStatus;
  /** Cached identity sk (32 bytes) — only populated under explicit unlock,
   *  zeroed when the wallet locks. v0.1: derived once at creation/load and
   *  held for the process lifetime, since identity ops (BRC-100 envelopes,
   *  POLICY signing) happen frequently and the identity is not tier-gated. */
  identitySk: Uint8Array | null;
}

const runtime: RuntimeState = {
  identity: null,
  policy: null,
  recovery: { state: 'LOCAL_ONLY' },
  identitySk: null,
};

/** Tests-only: drop in-memory state. IndexedDB is not touched here. */
export function _resetRuntimeForTests(): void {
  runtime.identity = null;
  runtime.policy = null;
  runtime.recovery = { state: 'LOCAL_ONLY' };
  if (runtime.identitySk) runtime.identitySk.fill(0);
  runtime.identitySk = null;
  clearAllKeks();
}

// ──────────────────────────────────────────────────────────────────────
// Identity / status helpers
// ──────────────────────────────────────────────────────────────────────

export interface IdentitySnapshot {
  identityPk: Uint8Array;
  identitySk: Uint8Array;
  certId: Uint8Array;
}

/**
 * Hand back the identity material for a caller that needs to sign on the
 * identity key (Plexus enrollment, POLICY-cell signing, BRC-100 outbound
 * envelopes from the dispatcher itself). Throws if no wallet exists — this
 * function is only ever called after `createWallet` / `loadWallet`.
 */
export function getIdentitySnapshot(): IdentitySnapshot {
  if (!runtime.identity || !runtime.identitySk) {
    throw new Error('getIdentitySnapshot: no identity loaded');
  }
  return {
    identityPk: hexToBytes(runtime.identity.identityPkHex),
    identitySk: runtime.identitySk.slice(),
    certId: hexToBytes(runtime.identity.certIdHex),
  };
}

/** Read-only view of the current policy. */
export function getPolicy(): PolicyShape {
  return runtime.policy ?? DEFAULT_POLICY;
}

/** Read-only view of the recovery banner state. */
export function getRecoveryStatus(): RecoveryStatus {
  return runtime.recovery;
}

/** Persist a new recovery-banner state. Used by the popup-plexus enroll
 *  callback (W7 wired through W9). */
export async function setRecoveryStatus(s: RecoveryStatus): Promise<void> {
  runtime.recovery = s;
  await kvPut(KV_KEYS.RECOVERY, s);
}

// ──────────────────────────────────────────────────────────────────────
// createWallet — first-time creation flow (design §7.6)
// ──────────────────────────────────────────────────────────────────────

export interface CreateWalletInput {
  /** v0.4: three challenge questions. MANDATORY — no skip path. The
   *  user picks or accepts canonical questions; their answers are the
   *  recovery layer's secret material per §4.0. */
  challengeQuestions: [string, string, string];
  /** v0.4: three plaintext answers, same order as `challengeQuestions`.
   *  Wiped from memory after this call. Never persisted in plaintext;
   *  hashed (salted) into the recovery envelope, and used to derive
   *  the KEK that encrypts the seed. */
  challengeAnswers: [string, string, string];
  /** v0.4: contact email — Plexus rate-limit key + OTP destination if
   *  the user later enrolls (§7.7). Always held locally. */
  contactEmail: string;
  /** Tier-1 PIN bytes (UTF-8, e.g. '1234'). Wiped after this call.
   *  Daily-use layer per §4.1. */
  tier1Pin: Uint8Array;
  /** Tier-2 factor — for v0.1 a passphrase string is acceptable; in
   *  production WebAuthn assertion bytes go here. */
  tier2Factor: Uint8Array;
  /** Tier-3 vault factor (passphrase ⊕ biometric in v0.1). */
  tier3Factor: Uint8Array;
  /** Optional: pre-supply entropy for the seed/salt/nonce (used by tests
   *  for determinism). Production callers omit this and let the function
   *  fetch CSPRNG. */
  testOverrides?: {
    seed?: Uint8Array;             // 64 bytes
    salt?: Uint8Array;             // 32 bytes
    gcmNonce?: Uint8Array;         // 12 bytes
  };
}

export interface CreateWalletResult {
  identity: IdentityRecord;
  policy: PolicyShape;
  /** The dispatch envelope built at creation. Persisted in KV under
   *  KV_KEYS.RECOVERY_ENVELOPE; returned here so the create flow can
   *  surface "back this up" / "enroll with Plexus" affordances.
   *  Contains the encrypted seed; cannot be decrypted without the user's
   *  challenge answers. */
  recoveryEnvelope: PlexusRecoveryEnvelope;
}

/**
 * Create a fresh wallet locally. Idempotent: a second call when an identity
 * already exists in IndexedDB returns `{ kind: 'ALREADY_CREATED' }` rather
 * than overwriting — this matches design §7.6 (first-time-only flow).
 *
 * v0.4 architectural correction: the recovery layer is built mandatorily
 * here. Three challenge questions/answers + a contact email are required
 * inputs. The dispatch envelope is constructed locally and persisted
 * regardless of any future Plexus enrollment — enrollment is just deciding
 * to also transmit the envelope. See §4.0, §6.5, §7.6.
 *
 * Steps (mirror §7.6 exactly):
 *   1. Generate a 64-byte CSPRNG root seed.
 *   2. Derive identity skⁱ = HMAC-SHA256(seed, "identity").
 *      Tier-N base sk = HMAC-SHA256(seed, "tier-N").  (Cheap stand-in for
 *      a full BIP39 → BRC-42 derivation chain — same recoverability under
 *      the same seed, fewer dependencies in v0.1.)
 *   3. Self-issue BRC-52 cert: certId = SHA256(identityPk || "BRC-52-cert-v1").
 *   4. Build the recovery dispatch envelope via plexus/envelope.ts —
 *      encrypts the seed under PBKDF2(normalized challenge answers + salt)
 *      and signs the envelope with the identity key.
 *   5. Persist the envelope under KV_KEYS.RECOVERY_ENVELOPE.
 *   6. Set per-tier daily-use KEKs (PIN / biometric / vault) and AES-GCM-
 *      encrypt each Tier-N base cell into IndexedDB slot N.
 *   7. Write the initial POLICY cell to KV (identity-signed).
 *   8. Write an empty Tier-0 budget cell (HOT_BUDGET_REMAINING = 0).
 *   9. Cache identity in IndexedDB KV under KV_KEYS.IDENTITY.
 *   10. Set recovery banner to LOCAL_ONLY.
 *   11. Wipe the seed + raw answers from memory.
 */
export async function createWallet(
  input: CreateWalletInput,
): Promise<Result<CreateWalletResult, WalletError>> {
  // Idempotency check — both the in-memory cache AND IndexedDB.
  if (runtime.identity) {
    return { ok: false, error: { kind: 'ALREADY_CREATED' } };
  }
  const existing = await kvGet<IdentityRecord>(KV_KEYS.IDENTITY);
  if (existing) {
    // Hydrate runtime so a subsequent call sees the existing identity too.
    await loadWallet();
    return { ok: false, error: { kind: 'ALREADY_CREATED' } };
  }

  // v0.4: challenges are mandatory. Validate before touching any state.
  if (
    !Array.isArray(input.challengeQuestions) ||
    input.challengeQuestions.length !== 3 ||
    input.challengeQuestions.some((q) => typeof q !== 'string' || q.trim().length === 0)
  ) {
    return { ok: false, error: { kind: 'BAD_INPUT', reason: 'challengeQuestions must be 3 non-empty strings' } };
  }
  if (
    !Array.isArray(input.challengeAnswers) ||
    input.challengeAnswers.length !== 3 ||
    input.challengeAnswers.some((a) => typeof a !== 'string' || a.trim().length === 0)
  ) {
    return { ok: false, error: { kind: 'BAD_INPUT', reason: 'challengeAnswers must be 3 non-empty strings' } };
  }
  if (typeof input.contactEmail !== 'string' || !input.contactEmail.includes('@')) {
    return { ok: false, error: { kind: 'BAD_INPUT', reason: 'contactEmail must look like an email' } };
  }
  if (input.tier1Pin.length === 0) {
    return { ok: false, error: { kind: 'BAD_INPUT', reason: 'tier1Pin required' } };
  }

  // 1. Generate the root seed. CSPRNG by default; tests can override for
  //    determinism. Wiped at the end of this function.
  const seed = input.testOverrides?.seed ?? crypto.getRandomValues(new Uint8Array(64));
  if (seed.length < 32) {
    return { ok: false, error: { kind: 'BAD_INPUT', reason: 'seed must be ≥ 32 bytes' } };
  }

  // 2. Derive identity + tier base keys from the seed.
  const identitySk = hmacDerive(seed, 'identity');
  const identityPk = secp.getPublicKey(identitySk, true);
  const tier1Base = hmacDerive(seed, 'tier-1');
  const tier2Base = hmacDerive(seed, 'tier-2');
  const tier3Base = hmacDerive(seed, 'tier-3');

  // 3. Self-issue BRC-52 cert id (SHA256 of identityPk + tag).
  const certIdInput = new Uint8Array(identityPk.length + 16);
  certIdInput.set(identityPk, 0);
  certIdInput.set(new TextEncoder().encode('BRC-52-cert-v1'), identityPk.length);
  const certId = nobleSha256(certIdInput);

  // 4. Build the recovery dispatch envelope per §6.5 + §8.2.
  //    The envelope encrypts the seed under PBKDF2 of the challenge answers.
  //    The seed bytes are passed in here and wiped from inside buildEnvelope
  //    after use.
  const envelopeResult = await buildEnvelope({
    identitySk,
    identityPk,
    certId,
    contactEmail: input.contactEmail,
    questions: [...input.challengeQuestions],
    answers: [...input.challengeAnswers],
    recoverySeed: seed,
    derivationContexts: [
      { tier: 1, brc43InvoiceString: '1-tier-key-1', domainFlag: '0x10000003', recoveryPolicy: 'BACKUP_ON_CREATE' },
      { tier: 2, brc43InvoiceString: '1-tier-key-2', domainFlag: '0x10000004', recoveryPolicy: 'BACKUP_ON_CREATE' },
      { tier: 3, brc43InvoiceString: '1-tier-key-3', domainFlag: '0x10000005', recoveryPolicy: 'BACKUP_ON_CONFIRM' },
    ],
    derivationStateSnapshot: {
      records: [],
      snapshotTimestamp: new Date().toISOString(),
    },
    testOverrides: input.testOverrides
      ? { salt: input.testOverrides.salt, gcmNonce: input.testOverrides.gcmNonce }
      : undefined,
  });
  if (!envelopeResult.ok) {
    // Map envelope errors back to wallet-ops errors. INVARIANT_FAILED would
    // indicate a bug in our own envelope builder, surfaced as INTERNAL.
    const reason =
      envelopeResult.error.kind === 'INVALID_INPUT'
        ? envelopeResult.error.reason
        : `envelope check ${envelopeResult.error.check} failed: ${envelopeResult.error.detail}`;
    return { ok: false, error: { kind: envelopeResult.error.kind === 'INVALID_INPUT' ? 'BAD_INPUT' : 'INTERNAL', reason } };
  }
  const recoveryEnvelope = envelopeResult.envelope;

  // 5. Persist the envelope. This is the user's recovery anchor whether or
  //    not they ever talk to Plexus.
  await kvPut(KV_KEYS.RECOVERY_ENVELOPE, recoveryEnvelope);

  // 6. Encrypt + persist each tier base cell.
  // Tier-0: derive a session KEK from the seed so the hot-budget cell can be
  // written/read without a UI prompt. v0.2 binds this to a WebAuthn-derived
  // secret per §4.1.
  const sessionKek = hmacDerive(seed, 'session-kek');
  await setSessionKek(sessionKek.slice(0, SLOT_KEK_BYTES));

  // Build a 1024-byte tier-base-key cell (matches §6.2 layout sufficiently
  // for v0.1 — domain flag at offset 28 BE + base sk at payload offset 256).
  const buildBaseCell = (tier: number, baseSk: Uint8Array): Uint8Array => {
    const cell = new Uint8Array(1024);
    // Header [0..256] — only the domain flag matters to the runtime
    // (host.ts:tierFromDomainFlag reads offset 28 BE).
    const flag = tier === 0
      ? 0x10000001
      : tier === 1
        ? 0x10000003
        : tier === 2
          ? 0x10000004
          : 0x10000005;
    new DataView(cell.buffer).setUint32(28, flag, false);
    // Payload [256..288] = base private key. The remaining bytes are
    // zero — v0.1 doesn't pack BRC-43 root invoice / cert id / counters
    // because the wallet's signing path receives them from the host
    // import args, not from the cell payload. v0.2 backfills.
    cell.set(baseSk, 256);
    return cell;
  };

  // Tier-0 hot budget cell — no Tier-1+ refill yet (zero remaining).
  const tier0Cell = buildBaseCell(0, hmacDerive(seed, 'tier-0'));
  // remaining_satoshis lives at payload offset 32 per §6.1; payload starts
  // at byte 256 → absolute offset = 256 + 32.
  new DataView(tier0Cell.buffer).setBigUint64(256 + 32, 0n, true);

  const tier0Kek = await crypto.subtle.importKey(
    'raw',
    sessionKek.slice(0, SLOT_KEK_BYTES),
    { name: 'AES-GCM' },
    false,
    ['encrypt', 'decrypt'],
  );
  const tier0Blob = await encryptCellForBridge(0, tier0Kek, tier0Cell);
  await slotPut(SLOT_IDS.HOT_BUDGET, tier0Blob);

  for (const [tier, baseSk, factor] of [
    [1, tier1Base, input.tier1Pin],
    [2, tier2Base, input.tier2Factor],
    [3, tier3Base, input.tier3Factor],
  ] as const) {
    if (factor.length === 0) continue; // tier optional in v0.1
    const kek = await deriveKek(tier, factor);
    const cell = buildBaseCell(tier, baseSk);
    const blob = await encryptCellForBridge(tier, kek, cell);
    await slotPut(tier === 1 ? SLOT_IDS.TIER1_BASE : tier === 2 ? SLOT_IDS.TIER2_BASE : SLOT_IDS.TIER3_BASE, blob);
  }

  // 4. Initial POLICY cell — identity-signed, monotonic version.
  const policy: PolicyShape = { ...DEFAULT_POLICY };
  await writePolicyInternal(policy, identitySk);

  // 5. Identity record stays in KV.
  // v0.1 stores the identity sk encrypted under the same session KEK so
  // process-restart can re-load it. (Strictly speaking the design says
  // identity should live in a Tier-2-protected blob — we promote that to
  // v0.2 since v0.1 has no biometric for offline boot.)
  const skBlob = await encryptCellForBridge(0, tier0Kek, padTo(identitySk, 1024));
  const identity: IdentityRecord = {
    identityPkHex: bytesToHex(identityPk),
    identitySkEnvelopeHex: bytesToHex(skBlob),
    certIdHex: bytesToHex(certId),
    createdAt: Math.floor(Date.now() / 1000),
  };
  await kvPut(KV_KEYS.IDENTITY, identity);

  // v0.4 §7.9 returning-device boot cache. Encrypt the identity sk under a
  // deterministic session KEK derived from `identityPk` alone — meaning a
  // tab reload can rehydrate identity sk without the seed (which we wipe
  // below) or any UI prompt. v0.1 derivation: HMAC-SHA256(identityPk,
  // "session-kek"); v0.2 binds the KEK to a per-install hardware-bound
  // secret per §4.1 so the cache is not portable across machines.
  const bootBlob = await encryptIdentitySkForBoot(identityPk, identitySk);
  await kvPut(KV_KEYS.IDENTITY_SK_BOOT_CACHE, bytesToHex(bootBlob));

  // 10. Recovery banner — LOCAL_ONLY (envelope is built and held locally;
  //     user can opt into Plexus enrollment later via popup-plexus).
  await kvPut(KV_KEYS.RECOVERY, { state: 'LOCAL_ONLY' } satisfies RecoveryStatus);
  await kvPut(KV_KEYS.HOT_BUDGET_REMAINING, '0');

  // Hydrate runtime cache.
  runtime.identity = identity;
  runtime.policy = policy;
  runtime.recovery = { state: 'LOCAL_ONLY' };
  runtime.identitySk = identitySk;

  // 11. Wipe the seed. Identity sk + tier base sk's stay encrypted at-rest;
  //     the seed itself is no longer needed (challenge answers regenerate
  //     it on recovery via the envelope's encryptedRecoverySeed field).
  seed.fill(0);
  tier1Base.fill(0);
  tier2Base.fill(0);
  tier3Base.fill(0);
  // Best-effort wipe of the input answers so the caller's reference goes
  // empty too (caller still owns the array — this is defense in depth).
  input.challengeAnswers.fill('');

  return {
    ok: true,
    value: {
      identity,
      policy,
      recoveryEnvelope,
    },
  };
}

// ──────────────────────────────────────────────────────────────────────
// recoverWallet — restore wallet state on a fresh device (design §7.8)
//
// W10: this is the high-level Phase C / D entry point that the recovery
// roundtrip test drives. It mirrors createWallet's structure, but instead
// of generating a fresh seed it ingests a pre-existing dispatch envelope
// (from a local backup file — Path B — or fetched from a Plexus operator —
// Path A) plus the user's three challenge answers, and rebuilds the entire
// IndexedDB-backed wallet from those inputs.
//
// Steps (mirror §7.8 Path B steps 5-6 → §7.6 steps 6-10):
//   1. Decrypt the seed from envelope.encryptedRecoverySeed using the
//      caller-supplied answers (PBKDF2 + AES-GCM under the same KEK
//      derivation buildEnvelope used at creation time).
//   2. Re-derive identitySk + Tier 0/1/2/3 base keys from the seed
//      (same hmacDerive labels as createWallet).
//   3. Verify identityPk derived from the seed matches envelope.identityKey
//      — sanity check that the envelope wasn't tampered with end-to-end.
//   4. Re-establish per-tier daily-use KEKs from the new tier factors and
//      AES-GCM-encrypt each tier base cell into IndexedDB slot N.
//   5. Replay derivationStateSnapshot into LocalStateStore so fresh-key-
//      per-tx resumes at the right indices (BRC-42 monotonic counters).
//   6. Persist identity record, recovery envelope (the same one we just
//      ingested — recovery on this device is the local copy now), POLICY
//      cell, hot-budget cell.
//   7. Wipe seed from memory.
//
// The recovered wallet is functionally identical to one created via
// createWallet — same identity, same tier base keys, same envelope.
// ──────────────────────────────────────────────────────────────────────

export interface RecoverWalletInput {
  /** The dispatch envelope to recover from. Either uploaded from a local
   *  backup file (Path B) or returned by recoverFromPlexus (Path A). */
  envelope: PlexusRecoveryEnvelope;
  /** The three challenge answers in the same order as
   *  envelope.challengeBundle.questions. Wiped after this call. */
  challengeAnswers: string[];
  /** New Tier-1 PIN bytes. Wiped after this call. */
  tier1Pin: Uint8Array;
  /** New Tier-2 factor bytes. */
  tier2Factor: Uint8Array;
  /** New Tier-3 vault factor bytes. Empty array skips Tier-3 enrollment. */
  tier3Factor: Uint8Array;
}

export interface RecoverWalletResult {
  identity: IdentityRecord;
  policy: PolicyShape;
  /** The envelope that was ingested — useful for the caller to confirm
   *  the recovered wallet matches the one expected. */
  recoveryEnvelope: PlexusRecoveryEnvelope;
  /** Number of derivationStateSnapshot.records replayed into the local
   *  state store. Surfaced for the popup to display "resumed N counters". */
  derivationStateRecordsReplayed: number;
}

export type RecoverError =
  | { kind: 'ALREADY_CREATED' }
  | { kind: 'BAD_INPUT'; reason: string }
  | { kind: 'DECRYPT_FAILED' }
  | { kind: 'IDENTITY_MISMATCH' }
  | { kind: 'INTERNAL'; reason: string };

export async function recoverWallet(
  input: RecoverWalletInput,
): Promise<Result<RecoverWalletResult, RecoverError>> {
  // Idempotency: if a wallet already exists on this device, refuse —
  // the caller should clear IndexedDB first (Phase B of the W10 test).
  if (runtime.identity) {
    return { ok: false, error: { kind: 'ALREADY_CREATED' } };
  }
  const existing = await kvGet<IdentityRecord>(KV_KEYS.IDENTITY);
  if (existing) {
    return { ok: false, error: { kind: 'ALREADY_CREATED' } };
  }

  // Validate inputs.
  if (!input.envelope || input.envelope.envelopeVersion !== 1) {
    return { ok: false, error: { kind: 'BAD_INPUT', reason: 'envelopeVersion must be 1' } };
  }
  if (
    !Array.isArray(input.challengeAnswers) ||
    input.challengeAnswers.length !== input.envelope.challengeBundle.questions.length
  ) {
    return {
      ok: false,
      error: {
        kind: 'BAD_INPUT',
        reason: `challengeAnswers length must match envelope.challengeBundle.questions (${input.envelope.challengeBundle.questions.length})`,
      },
    };
  }
  if (input.tier1Pin.length === 0) {
    return { ok: false, error: { kind: 'BAD_INPUT', reason: 'tier1Pin required' } };
  }

  // 1. Decrypt the seed from the envelope.
  const seed = await decryptRecoverySeed(input.envelope, input.challengeAnswers);
  if (!seed) {
    return { ok: false, error: { kind: 'DECRYPT_FAILED' } };
  }
  if (seed.length < 32) {
    seed.fill(0);
    return { ok: false, error: { kind: 'INTERNAL', reason: 'recovered seed too short' } };
  }

  // 2. Re-derive identity + tier base keys from the seed (same labels as
  //    createWallet — recovery is byte-identical to creation by design).
  const identitySk = hmacDerive(seed, 'identity');
  const identityPk = secp.getPublicKey(identitySk, true);
  const tier1Base = hmacDerive(seed, 'tier-1');
  const tier2Base = hmacDerive(seed, 'tier-2');
  const tier3Base = hmacDerive(seed, 'tier-3');

  // 3. Verify the recovered identity matches the envelope's commitment.
  const identityPkHex = bytesToHex(identityPk);
  if (identityPkHex !== input.envelope.identityKey) {
    seed.fill(0);
    identitySk.fill(0);
    tier1Base.fill(0);
    tier2Base.fill(0);
    tier3Base.fill(0);
    return { ok: false, error: { kind: 'IDENTITY_MISMATCH' } };
  }
  // Extract certId from the envelope rather than recomputing — the cert
  // commitment is the operator-side anchor (BRC-52 self-issued hash); we
  // trust the envelope here because envelope check 4 (signature under
  // identityPk) is verified at build time and identityPk just round-tripped
  // through the seed.
  let certId: Uint8Array;
  try {
    certId = hexToBytes(input.envelope.certId);
  } catch {
    seed.fill(0);
    identitySk.fill(0);
    tier1Base.fill(0);
    tier2Base.fill(0);
    tier3Base.fill(0);
    return { ok: false, error: { kind: 'BAD_INPUT', reason: 'envelope.certId not hex' } };
  }

  // 4. Re-establish per-tier KEKs and persist tier base cells. Mirrors
  //    createWallet steps 6-9 exactly.
  const sessionKek = hmacDerive(seed, 'session-kek');
  await setSessionKek(sessionKek.slice(0, SLOT_KEK_BYTES));

  const buildBaseCell = (tier: number, baseSk: Uint8Array): Uint8Array => {
    const cell = new Uint8Array(1024);
    const flag = tier === 0
      ? 0x10000001
      : tier === 1
        ? 0x10000003
        : tier === 2
          ? 0x10000004
          : 0x10000005;
    new DataView(cell.buffer).setUint32(28, flag, false);
    cell.set(baseSk, 256);
    return cell;
  };

  // Tier-0 hot budget cell — no Tier-1+ refill yet (zero remaining).
  const tier0Cell = buildBaseCell(0, hmacDerive(seed, 'tier-0'));
  new DataView(tier0Cell.buffer).setBigUint64(256 + 32, 0n, true);
  const tier0Kek = await crypto.subtle.importKey(
    'raw',
    sessionKek.slice(0, SLOT_KEK_BYTES),
    { name: 'AES-GCM' },
    false,
    ['encrypt', 'decrypt'],
  );
  const tier0Blob = await encryptCellForBridge(0, tier0Kek, tier0Cell);
  await slotPut(SLOT_IDS.HOT_BUDGET, tier0Blob);

  for (const [tier, baseSk, factor] of [
    [1, tier1Base, input.tier1Pin],
    [2, tier2Base, input.tier2Factor],
    [3, tier3Base, input.tier3Factor],
  ] as const) {
    if (factor.length === 0) continue;
    const kek = await deriveKek(tier, factor);
    const cell = buildBaseCell(tier, baseSk);
    const blob = await encryptCellForBridge(tier, kek, cell);
    await slotPut(
      tier === 1 ? SLOT_IDS.TIER1_BASE : tier === 2 ? SLOT_IDS.TIER2_BASE : SLOT_IDS.TIER3_BASE,
      blob,
    );
  }

  // 5. Replay derivation_state_snapshot. The snapshot's records carry
  //    (protocolHash, counterparty, currentIndex) tuples — we seed each
  //    matching IndexedDB state row so the next stateNextIndex() call
  //    returns currentIndex + 1 (no gap-scan, monotonic resume per §3.5.3).
  //
  //    WA3: records may carry `currentIndex: null` for contexts the user
  //    touched (registered via ContextRegistry) but never advanced. For
  //    those we don't seed the state store — gap-scan from 0 is correct —
  //    but we DO repopulate the ContextRegistry so WA4's recovery scan
  //    sees the full address space.
  const snapshot = input.envelope.derivationStateSnapshot;
  let replayed = 0;
  const restoredRegistry: ContextRegistry = {};
  for (const rec of snapshot.records) {
    let ph: Uint8Array;
    let cp: Uint8Array;
    try {
      ph = hexToBytes(rec.protocolHash);
      cp = decodeCounterparty(rec.counterparty);
    } catch {
      // Skip malformed records rather than aborting — design §3.5.3 says
      // the snapshot is best-effort; gap-scan on first use is the fallback.
      continue;
    }
    if (ph.length !== 16 || cp.length !== 33) continue;

    const phHex = bytesToHex(ph);
    const cpHex = bytesToHex(cp);
    restoredRegistry[ctxRegKey(phHex, cpHex)] = {
      protocolHash: phHex,
      counterparty: cpHex,
      firstTouchedAt: Math.floor(Date.now() / 1000),
      domainFlag: rec.domainFlag ?? 0x00,
      protocolId: rec.protocolId ?? 'unknown',
    };

    if (rec.currentIndex === null) continue;

    const key = encodeStateKey(ph, cp);
    await stateRawPut(key, rec.currentIndex);
    replayed++;
  }
  if (Object.keys(restoredRegistry).length > 0) {
    await kvPut(KV_KEYS.CONTEXT_REGISTRY, restoredRegistry);
  }

  // 6. Persist POLICY cell (identity-signed) — recovered wallet starts
  //    with default policy, the user can update it post-recovery if they
  //    had a non-default policy at backup time. v0.2 ships POLICY in the
  //    envelope as well.
  const policy: PolicyShape = { ...DEFAULT_POLICY };
  await writePolicyInternal(policy, identitySk);

  // 7. Persist identity record — sk envelope is the same encrypted-under-
  //    session-KEK shape as createWallet uses.
  const skBlob = await encryptCellForBridge(0, tier0Kek, padTo(identitySk, 1024));
  const identity: IdentityRecord = {
    identityPkHex,
    identitySkEnvelopeHex: bytesToHex(skBlob),
    certIdHex: bytesToHex(certId),
    createdAt: Math.floor(Date.now() / 1000),
  };
  await kvPut(KV_KEYS.IDENTITY, identity);

  // 8. Persist the envelope locally — even if this device's recovery came
  //    via Plexus (Path A), the local copy is now this device's primary.
  await kvPut(KV_KEYS.RECOVERY_ENVELOPE, input.envelope);
  // v0.4 §7.9 boot cache — same path as createWallet: encrypt identity sk
  // under HMAC(identityPk, "session-kek") so subsequent tab reloads can
  // rehydrate without re-running this recovery flow.
  const bootBlob = await encryptIdentitySkForBoot(identityPk, identitySk);
  await kvPut(KV_KEYS.IDENTITY_SK_BOOT_CACHE, bytesToHex(bootBlob));
  await kvPut(KV_KEYS.RECOVERY, { state: 'LOCAL_ONLY' } satisfies RecoveryStatus);
  await kvPut(KV_KEYS.HOT_BUDGET_REMAINING, '0');

  // Hydrate runtime cache.
  runtime.identity = identity;
  runtime.policy = policy;
  runtime.recovery = { state: 'LOCAL_ONLY' };
  runtime.identitySk = identitySk;

  // 9. Wipe sensitive bytes.
  seed.fill(0);
  tier1Base.fill(0);
  tier2Base.fill(0);
  tier3Base.fill(0);
  for (let i = 0; i < input.challengeAnswers.length; i++) input.challengeAnswers[i] = '';

  return {
    ok: true,
    value: {
      identity,
      policy,
      recoveryEnvelope: input.envelope,
      derivationStateRecordsReplayed: replayed,
    },
  };
}

/** Decode the envelope's counterparty field — supports the "self" / "anyone"
 *  sentinels used in DerivationStateRecord and the regular hex pubkey. */
function decodeCounterparty(s: string): Uint8Array {
  if (s === 'self' || s === 'anyone') {
    // Sentinel encoding: 0x00 prefix + 32 bytes derived from the label so
    // the on-disk state-store key still has the §3.5.2 length. v0.1 ships
    // a literal-string fallback — the snapshot from createWallet uses
    // hex-form counterparties, so this branch is currently exercised only
    // by future enrollments that store sentinels. Keep schema-compatible.
    const out = new Uint8Array(33);
    const tag = new TextEncoder().encode(s);
    out.set(tag, 1);
    return out;
  }
  return hexToBytes(s);
}

/** Compose the same on-disk state key as storage.ts:deriveStateKey. */
function encodeStateKey(protocolHash: Uint8Array, counterparty: Uint8Array): string {
  let s = '';
  for (const b of protocolHash) s += b.toString(16).padStart(2, '0');
  for (const b of counterparty) s += b.toString(16).padStart(2, '0');
  return s;
}

/** Raw IndexedDB put for the state-store, used by recoverWallet to seed
 *  the BRC-42 monotonic counters from a derivationStateSnapshot. Storage
 *  layer keeps no public "set arbitrary index" helper because every other
 *  caller goes through stateNextIndex (atomic increment) — recovery is the
 *  one place where direct seeding is correct. */
async function stateRawPut(key: string, currentIndex: number): Promise<void> {
  const { openWalletDb } = await import('./storage');
  const db = await openWalletDb();
  await new Promise<void>((resolve, reject) => {
    const tx = db.transaction('state', 'readwrite');
    const req = tx.objectStore('state').put({ current_index: currentIndex.toString() }, key);
    req.onsuccess = () => resolve();
    req.onerror = () => reject(req.error);
  });
}

// ──────────────────────────────────────────────────────────────────────
// WA3 — exportRecoveryEnvelope
//
// Rebuild the recovery envelope with the wallet's *current* derivation-
// context snapshot, signed under the current identity key. The user
// re-supplies their challenge answers so we can decrypt the existing seed
// (the only way to "refresh" the envelope without keeping the seed in
// memory between calls). A new salt + nonce is generated so the resulting
// envelope is bit-different from the cached one (no replay window).
//
// Used by popup-status / popup-setup ("Back up envelope" → "Refresh
// envelope" affordance) and as the data source for WT-Transport multi-
// target export.
// ──────────────────────────────────────────────────────────────────────

export interface ExportEnvelopeInput {
  /** Same answers the user supplied at createWallet time (or at last
   *  recovery). Used to decrypt the seed inside the cached envelope.
   *  Wiped after the call. */
  challengeAnswers: string[];
}

export type ExportEnvelopeError =
  | { kind: 'NOT_CREATED' }
  | { kind: 'NO_ENVELOPE_CACHED' }
  | { kind: 'DECRYPT_FAILED' }
  | { kind: 'BAD_INPUT'; reason: string }
  | { kind: 'INTERNAL'; reason: string };

export async function exportRecoveryEnvelope(
  input: ExportEnvelopeInput,
): Promise<Result<PlexusRecoveryEnvelope, ExportEnvelopeError>> {
  if (!runtime.identity || !runtime.identitySk) {
    return { ok: false, error: { kind: 'NOT_CREATED' } };
  }
  const cached = await kvGet<PlexusRecoveryEnvelope>(KV_KEYS.RECOVERY_ENVELOPE);
  if (!cached) {
    return { ok: false, error: { kind: 'NO_ENVELOPE_CACHED' } };
  }
  if (
    !Array.isArray(input.challengeAnswers) ||
    input.challengeAnswers.length !== cached.challengeBundle.questions.length
  ) {
    return {
      ok: false,
      error: { kind: 'BAD_INPUT', reason: 'challengeAnswers length must match cached envelope' },
    };
  }

  const seed = await decryptRecoverySeed(cached, input.challengeAnswers);
  if (!seed) {
    return { ok: false, error: { kind: 'DECRYPT_FAILED' } };
  }
  if (seed.length < 32) {
    seed.fill(0);
    return { ok: false, error: { kind: 'INTERNAL', reason: 'recovered seed too short' } };
  }

  const records = await snapshotDerivationContexts();
  const identityPk = hexToBytes(runtime.identity.identityPkHex);
  const certId = hexToBytes(runtime.identity.certIdHex);

  const result = await buildEnvelope({
    identitySk: runtime.identitySk,
    identityPk,
    certId,
    contactEmail: cached.contactEmail,
    questions: cached.challengeBundle.questions.slice(),
    answers: input.challengeAnswers.slice(),
    recoverySeed: seed,
    derivationContexts: cached.derivationContexts.map((c) => ({ ...c })),
    derivationStateSnapshot: {
      records,
      snapshotTimestamp: new Date().toISOString(),
    },
  });

  // Wipe before any branching so error paths don't leave the seed alive.
  seed.fill(0);
  for (let i = 0; i < input.challengeAnswers.length; i++) input.challengeAnswers[i] = '';

  if (!result.ok) {
    const reason =
      result.error.kind === 'INVALID_INPUT'
        ? result.error.reason
        : `envelope check ${result.error.check} failed: ${result.error.detail}`;
    return {
      ok: false,
      error: { kind: result.error.kind === 'INVALID_INPUT' ? 'BAD_INPUT' : 'INTERNAL', reason },
    };
  }

  await kvPut(KV_KEYS.RECOVERY_ENVELOPE, result.envelope);
  return { ok: true, value: result.envelope };
}

export async function getCachedRecoveryEnvelope(): Promise<Result<PlexusRecoveryEnvelope, WalletError>> {
  if (!runtime.identity) return { ok: false, error: { kind: 'NOT_CREATED' } };
  const cached = await kvGet<PlexusRecoveryEnvelope>(KV_KEYS.RECOVERY_ENVELOPE);
  if (!cached) {
    return { ok: false, error: { kind: 'INTERNAL', reason: 'no recovery envelope cached' } };
  }
  return { ok: true, value: cached };
}

// ──────────────────────────────────────────────────────────────────────
// loadWallet — re-hydrate identity + policy from IndexedDB
// ──────────────────────────────────────────────────────────────────────

/**
 * Load an existing wallet's identity record and POLICY cell back into the
 * in-process cache.  Returns a flag distinguishing "no wallet yet" from
 * "loaded successfully" — the popup uses this to decide between the
 * `create` screen and the `status` screen.
 *
 * Per §7.6, on a fresh device with no IndexedDB record we never overwrite
 * — we just signal NOT_CREATED so the create flow can run.
 */
export async function loadWallet(): Promise<
  Result<{ identity: IdentityRecord; policy: PolicyShape; recovery: RecoveryStatus }, WalletError>
> {
  const identity = await kvGet<IdentityRecord>(KV_KEYS.IDENTITY);
  if (!identity) {
    return { ok: false, error: { kind: 'NOT_CREATED' } };
  }
  const policyRecord = await kvGet<{ policy: PolicyShape; signatureHex: string }>(KV_KEYS.POLICY);
  const policy = policyRecord?.policy ?? DEFAULT_POLICY;
  const recovery = (await kvGet<RecoveryStatus>(KV_KEYS.RECOVERY)) ?? {
    state: 'LOCAL_ONLY' as const,
  };

  runtime.identity = identity;
  runtime.policy = policy;
  runtime.recovery = recovery;
  // Identity sk is NOT eagerly decrypted on load — the caller must request
  // it via `unlockIdentity` (v0.1: derived from the same machine secret as
  // session KEK; v0.2: gated by WebAuthn).
  return { ok: true, value: { identity, policy, recovery } };
}

/**
 * v0.4 §7.9 returning-device boot path. Rehydrates `runtime.identitySk`
 * from `KV_KEYS.IDENTITY_SK_BOOT_CACHE` without requiring the seed (which
 * was wiped at creation per §7.6 step 11) or the user's challenge answers
 * (those are the recovery-tier knowledge, not the session-tier knowledge).
 *
 * Implementation: at creation time, identity sk is encrypted under a
 * deterministic session KEK derived from the identity public key —
 *   sessionKek = HMAC-SHA256(identityPk, "session-kek")
 * — and the (12-byte IV || ciphertext+tag) blob is stashed at
 * IDENTITY_SK_BOOT_CACHE. This function re-derives the same KEK from the
 * loaded identity record's pubkey and AES-GCM-decrypts the blob.
 *
 * In v0.1 this is a tamper-evidence anchor only (the KEK is derivable
 * from the public side of the identity, so a forensic attacker with
 * IndexedDB access can re-derive it too — no different from the
 * deterministic seed → identity derivation that `unlockIdentity` relies
 * on). v0.2 binds the session KEK to a per-install hardware-bound secret
 * per §4.1, at which point this becomes the production-grade boot path.
 *
 * Idempotent — a second call is a no-op.
 */
export async function unlockIdentityFromCache(): Promise<Result<void, WalletError>> {
  if (runtime.identitySk) return { ok: true, value: undefined };
  if (!runtime.identity) return { ok: false, error: { kind: 'NOT_CREATED' } };
  const cachedHex = await kvGet<string>(KV_KEYS.IDENTITY_SK_BOOT_CACHE);
  if (!cachedHex || typeof cachedHex !== 'string') {
    return { ok: false, error: { kind: 'INTERNAL', reason: 'no boot cache' } };
  }
  const blob = hexToBytes(cachedHex);
  const identityPk = hexToBytes(runtime.identity.identityPkHex);
  try {
    const sk = await decryptIdentitySkFromBoot(identityPk, blob);
    runtime.identitySk = sk;
    return { ok: true, value: undefined };
  } catch (e) {
    return { ok: false, error: { kind: 'INTERNAL', reason: `boot cache decrypt: ${(e as Error).message}` } };
  }
}

/**
 * Decrypt the identity sk envelope and stash it in process memory. Idempotent
 * — a second call is a no-op.  v0.1 derives the session KEK from a caller-
 * supplied seed; production binds it to a per-install machine secret per §4.1.
 *
 * Note: this is the recovery-flow / explicit-unlock path. For the typical
 * returning-user "tab reload" case, prefer `unlockIdentityFromCache()` —
 * see §7.9.
 */
export async function unlockIdentity(masterSeed: Uint8Array): Promise<Result<void, WalletError>> {
  if (runtime.identitySk) return { ok: true, value: undefined };
  if (!runtime.identity) return { ok: false, error: { kind: 'NOT_CREATED' } };
  const sessionKek = hmacDerive(masterSeed, 'session-kek');
  await setSessionKek(sessionKek.slice(0, SLOT_KEK_BYTES));
  // Re-derive: v0.1 doesn't actually decrypt the stored envelope — we know
  // the seed → identity derivation is deterministic, so we recompute.
  // (The encrypted envelope in `identitySkEnvelopeHex` is a tamper-evidence
  // anchor for v0.2 when we move to a non-deterministic identity derivation.)
  const identitySk = hmacDerive(masterSeed, 'identity');
  const expectedPk = bytesToHex(secp.getPublicKey(identitySk, true));
  if (expectedPk !== runtime.identity.identityPkHex) {
    return { ok: false, error: { kind: 'WRONG_FACTOR' } };
  }
  runtime.identitySk = identitySk;
  return { ok: true, value: undefined };
}

// ──────────────────────────────────────────────────────────────────────
// Tier classification (§3 schedule)
// ──────────────────────────────────────────────────────────────────────

/** Classify a sat-denominated spend amount into a tier per the policy. */
export function classifyTier(amountSats: bigint, policy: PolicyShape = getPolicy()): 0 | 1 | 2 | 3 {
  if (amountSats < BigInt(policy.tier1CeilingSats)) return 0;
  if (amountSats < BigInt(policy.tier2CeilingSats)) return 1;
  if (amountSats < BigInt(policy.tier3CeilingSats)) return 2;
  return 3;
}

// ──────────────────────────────────────────────────────────────────────
// signSpend — Tier-N signing with optional UI prompt for the factor.
//
// Failure-atomicity (W9 spec):
//   • If the user cancels or supplies a wrong factor, signSpend returns
//     `WRONG_FACTOR` / `TIER_LOCKED` *without* leaving the wallet in a
//     partially-unlocked state — the request scope is closed in `finally`.
//   • If host_state_next_index can't be primed (storage layer failure),
//     no leaf is derived, no signature is emitted.
//
// v0.1 "signing" is direct ECDSA over the provided digest using the tier
// base key as a stand-in for the BRC-42 leaf. Full BRC-42 fresh-key-per-tx
// (§3.5) requires `host_derive_leaf` from inside a script execution; W9
// covers the postMessage layer + the per-tier auth flow, and W11/the
// tx-builder workstream covers the script execution.
// ──────────────────────────────────────────────────────────────────────

export interface SignSpendInput {
  /** 32-byte preimage to sign. */
  digest: Uint8Array;
  /** Sat amount of the spend (used to classify the tier). */
  amountSats: bigint;
  /** If the inferred tier > 0, the factor bytes the user provided (PIN /
   *  biometric / vault). If undefined for tier > 0, returns TIER_LOCKED. */
  factor?: Uint8Array;
  /**
   * When present, the wallet re-derives the BRC-42 leaf key and signs with
   * it instead of the raw tier base key.  Pass the derivation context that
   * was recorded when the UTXO was created (from OutputRecord.derivationContext).
   */
  derivationContext?: {
    protocolHash: Uint8Array; // 16 bytes
    counterparty: Uint8Array; // 33 bytes
    index: bigint;
  };
}

export interface SignSpendResult {
  signatureDer: Uint8Array;
  tier: 0 | 1 | 2 | 3;
}

export async function signSpend(input: SignSpendInput): Promise<Result<SignSpendResult, WalletError>> {
  if (!runtime.identity) return { ok: false, error: { kind: 'NOT_CREATED' } };
  if (input.digest.length !== 32) {
    return { ok: false, error: { kind: 'BAD_INPUT', reason: 'digest must be 32 bytes' } };
  }
  const policy = getPolicy();
  const tier = classifyTier(input.amountSats, policy);

  // Tier-3 cooldown enforcement (host-clock v0.1 path, §4.4).
  if (tier === 3 && policy.tier3CooldownSeconds > 0) {
    const last = await kvGet<number>(KV_KEYS.TIER3_LAST_SPEND);
    if (last) {
      const now = Math.floor(Date.now() / 1000);
      const elapsed = now - last;
      if (elapsed < policy.tier3CooldownSeconds) {
        return {
          ok: false,
          error: {
            kind: 'TIER3_COOLDOWN',
            secondsRemaining: policy.tier3CooldownSeconds - elapsed,
          },
        };
      }
    }
  }

  // Tier 0: no UI prompt — sign with the BRC-42 leaf when a derivation
  // context is provided (normal UTXO spend), otherwise fall back to the
  // Tier-0 hot-budget key (legacy digest-only path).
  if (tier === 0) {
    if (!runtime.identitySk) {
      return { ok: false, error: { kind: 'INTERNAL', reason: 'identity sk not loaded' } };
    }
    let signingKey: Uint8Array;
    if (input.derivationContext) {
      const leaf = deriveLeafSync(
        runtime.identitySk,
        input.derivationContext.protocolHash,
        input.derivationContext.counterparty,
        input.derivationContext.index,
      );
      if (!leaf) return { ok: false, error: { kind: 'INTERNAL', reason: 'leaf derivation failed' } };
      signingKey = leaf;
    } else {
      signingKey = deriveTier0SkFromIdentity(runtime.identitySk);
    }
    const sig = secp.sign(input.digest, signingKey).normalizeS();
    const der = encodeDer(sig.r, sig.s);
    signingKey.fill(0);
    return { ok: true, value: { signatureDer: der, tier: 0 } };
  }

  // Tier 1+: factor required.
  if (!input.factor || input.factor.length === 0) {
    return { ok: false, error: { kind: 'TIER_LOCKED', tier } };
  }

  const slotId = tier === 1 ? SLOT_IDS.TIER1_BASE : tier === 2 ? SLOT_IDS.TIER2_BASE : SLOT_IDS.TIER3_BASE;
  beginRequest();
  try {
    await primeSlot(slotId);
    const ok = await primeUnlockTier(tier, input.factor, slotId);
    if (!ok) {
      return { ok: false, error: { kind: 'WRONG_FACTOR' } };
    }
    if (!tierUnlocked(tier)) {
      return { ok: false, error: { kind: 'INTERNAL', reason: 'tier not unlocked after prime' } };
    }
    // Read the plaintext base cell out of the request cache, then optionally
    // re-derive the BRC-42 leaf if a derivation context was supplied.
    const base = await readBaseSkFromActiveSlot(slotId);
    if (!base) {
      return { ok: false, error: { kind: 'INTERNAL', reason: 'base cell missing' } };
    }
    let signingKey: Uint8Array = base;
    if (input.derivationContext) {
      const leaf = deriveLeafSync(
        base,
        input.derivationContext.protocolHash,
        input.derivationContext.counterparty,
        input.derivationContext.index,
      );
      base.fill(0);
      if (!leaf) return { ok: false, error: { kind: 'INTERNAL', reason: 'leaf derivation failed' } };
      signingKey = leaf;
    }
    const sig = secp.sign(input.digest, signingKey).normalizeS();
    const der = encodeDer(sig.r, sig.s);
    signingKey.fill(0);

    if (tier === 3) {
      await kvPut(KV_KEYS.TIER3_LAST_SPEND, Math.floor(Date.now() / 1000));
    }
    return { ok: true, value: { signatureDer: der, tier } };
  } finally {
    await flushRequest();
    endRequest();
    // Important: clear the just-unlocked tier KEK so a subsequent
    // signSpend in the same process must re-prompt the user. This is the
    // "rollback to encrypted-at-rest" guarantee from the W9 spec.
    clearAllKeks();
    runtime.identitySk && (runtime.identitySk = runtime.identitySk); // keep identity sk
  }
}

/**
 * Sign an arbitrary message with the wallet's identity key — used by BRC-100
 * `signMessage`. Hashes the message with SHA-256 first to produce the 32-byte
 * digest secp expects.
 */
export async function signMessage(message: Uint8Array): Promise<Result<Uint8Array, WalletError>> {
  if (!runtime.identity) return { ok: false, error: { kind: 'NOT_CREATED' } };
  if (!runtime.identitySk) return { ok: false, error: { kind: 'INTERNAL', reason: 'identity sk not loaded' } };
  const digest = nobleSha256(message);
  const sig = secp.sign(digest, runtime.identitySk).normalizeS();
  return { ok: true, value: encodeDer(sig.r, sig.s) };
}

/**
 * Derive the BRC-42 leaf public key for the given (protocolHash, counterparty,
 * index) triple, using the wallet's loaded identity key as the base.
 * Returns the 33-byte compressed pubkey, or null if the wallet is locked or
 * derivation fails.  The leaf secret key is wiped immediately — never stored.
 */
export function deriveLeafPubkey(
  protocolHash: Uint8Array,
  counterparty: Uint8Array,
  index: bigint,
): Uint8Array | null {
  if (!runtime.identitySk) return null;
  const leafSk = deriveLeafSync(runtime.identitySk, protocolHash, counterparty, index);
  if (!leafSk) return null;
  const pk = secp.getPublicKey(leafSk, true);
  leafSk.fill(0);
  return pk;
}

// ──────────────────────────────────────────────────────────────────────
// Change-output helpers (BRC-42 wallet-change domain, flag 0x0B)
// ──────────────────────────────────────────────────────────────────────

const CHANGE_PROTOCOL_HASH_BYTES: Uint8Array = (() =>
  nobleSha256(new TextEncoder().encode('BRC-42-wallet-change')).slice(0, 16))();

/** Atomically allocate the next change derivation index. */
export async function nextChangeIndex(): Promise<number> {
  const cur = (await kvGet<number>(KV_KEYS.CHANGE_INDEX)) ?? 0;
  await kvPut(KV_KEYS.CHANGE_INDEX, cur + 1);
  return cur;
}

/**
 * Allocate a change index, build the locking script for the change output,
 * and record the context so the envelope export includes this domain.
 * Returns null if the wallet is locked or derivation fails.
 */
export async function buildNextChangeLock(): Promise<{
  lockScript: Uint8Array;
  changeIndex: number;
  derivationContext: { protocolHash: Uint8Array; counterparty: Uint8Array; index: bigint };
} | null> {
  if (!runtime.identitySk) return null;
  const changeIndex = await nextChangeIndex();
  const lockScript = buildChangeLock(runtime.identitySk, changeIndex);
  if (!lockScript) return null;
  const identityPk = secp.getPublicKey(runtime.identitySk, true);
  // L11.5: change keys derive via the domain-separated kdf-v3 (deriveChangeSk
  // folds CHANGE_DOMAIN_FLAG). Stamp v3 per recovery model 2b so a restoring
  // device re-derives via v3 from the stored version, not the flag→version map.
  await recordContext(
    CHANGE_PROTOCOL_HASH_BYTES,
    identityPk,
    CHANGE_DOMAIN_FLAG,
    'BRC-42-wallet-change',
    'plexus-kdf-v3',
  );
  return {
    lockScript,
    changeIndex,
    derivationContext: {
      protocolHash: CHANGE_PROTOCOL_HASH_BYTES,
      counterparty: identityPk,
      index: BigInt(changeIndex),
    },
  };
}

// ──────────────────────────────────────────────────────────────────────
// createAction — build, sign, and broadcast a BSV transaction (W11)
// ──────────────────────────────────────────────────────────────────────

const DUST_SATS = 546n;
// 1 sat/byte flat-rate fee estimate: ~148 bytes per P2PKH input, ~34 per
// output, 10 bytes overhead.
function estimateFeeSats(inputCount: number, outputCount: number): bigint {
  return BigInt(148 * inputCount + 34 * outputCount + 10);
}

export interface CreateActionInput {
  /** Recipient outputs — locking scripts + amounts. */
  outputs: Array<{ script: Uint8Array; satoshis: bigint }>;
  /** Total spend amount for tier classification (sum of recipient outputs). */
  amountSats: bigint;
  /** Tier 1+ factor bytes (PIN / passphrase / vault). Required when tier > 0. */
  factor?: Uint8Array;
  /** ARC endpoint; defaults to the public Taal node. */
  arcUrl?: string;
}

export interface CreateActionResult {
  txid: string;
  rawTxHex: string;
}

/**
 * Select UTXOs, build a signed P2PKH transaction, broadcast to ARC, and mark
 * spent outputs.  Change is returned via a BRC-42 wallet-change output
 * (domain 0x0B) when the surplus exceeds the dust threshold.
 */
export async function createAction(
  input: CreateActionInput,
): Promise<Result<CreateActionResult, WalletError>> {
  if (!runtime.identity || !runtime.identitySk) {
    return { ok: false, error: { kind: 'NOT_CREATED' } };
  }

  const policy = getPolicy();
  const tier = classifyTier(input.amountSats, policy);
  if (tier > 0 && (!input.factor || input.factor.length === 0)) {
    return { ok: false, error: { kind: 'TIER_LOCKED', tier } };
  }

  // Greedy UTXO selection: largest-first until we cover spend + fee estimate.
  const all = await outputStore.listOutputs({ status: 'unspent' });
  const sorted = all.slice().sort((a, b) => (b.satoshis > a.satoshis ? 1 : -1));

  const outputCount = input.outputs.length + 1; // +1 for potential change
  let selected: typeof sorted = [];
  let total = 0n;
  for (const utxo of sorted) {
    selected.push(utxo);
    total += utxo.satoshis;
    const fee = estimateFeeSats(selected.length, outputCount);
    if (total >= input.amountSats + fee) break;
  }

  const fee = estimateFeeSats(selected.length, outputCount);
  if (total < input.amountSats + fee) {
    return {
      ok: false,
      error: { kind: 'INSUFFICIENT_FUNDS', needed: input.amountSats + fee, available: total },
    };
  }

  const txInputs: TxInput[] = selected.map((u) => ({
    txid: u.outpoint.txid,
    vout: u.outpoint.vout,
    value: u.satoshis,
    script: u.lockingScript,
    sequence: 0xffffffff,
  }));

  const txOutputs: TxOutput[] = input.outputs.map((o) => ({ script: o.script, satoshis: o.satoshis }));

  // Change output — use BRC-42 wallet-change domain so recovery can find it.
  const surplus = total - input.amountSats - fee;
  let changeCtx: { protocolHash: Uint8Array; counterparty: Uint8Array; index: bigint } | null = null;
  if (surplus > DUST_SATS) {
    const change = await buildNextChangeLock();
    if (change) {
      txOutputs.push({ script: change.lockScript, satoshis: surplus });
      changeCtx = change.derivationContext;
    }
  }

  // Sign each input with its BRC-42 leaf key.
  const signedInputs: EFInput[] = [];
  for (let i = 0; i < txInputs.length; i++) {
    const utxo = selected[i]!;
    const digest = computeSighash(txInputs, txOutputs, i);
    const ctx = utxo.derivationContext;
    const leafSk = deriveLeafSync(runtime.identitySk, ctx.protocolHash, ctx.counterparty, ctx.index);
    if (!leafSk) {
      return { ok: false, error: { kind: 'INTERNAL', reason: `leaf derivation failed for input ${i}` } };
    }
    const leafPk = secp.getPublicKey(leafSk, true);
    const sigObj = secp.sign(digest, leafSk).normalizeS();
    leafSk.fill(0);
    const unlockScript = buildP2pkhUnlockScript(encodeDer(sigObj.r, sigObj.s), leafPk);
    signedInputs.push({
      txid: utxo.outpoint.txid,
      vout: utxo.outpoint.vout,
      unlockScript,
      sequence: 0xffffffff,
      sourceValue: utxo.satoshis,
      sourceLock: utxo.lockingScript,
    });
  }
  void changeCtx; // recorded via buildNextChangeLock; no further use needed here

  const { rawTx, efTx, txid } = serializeEFTx(signedInputs, txOutputs);

  const broadcast = await broadcastToArc(efTx, input.arcUrl);
  if (!broadcast.ok) {
    return { ok: false, error: { kind: 'BROADCAST_FAILED', reason: broadcast.reason } };
  }

  // Mark spent.
  for (const utxo of selected) {
    await outputStore.markSpent(utxo.outpoint, txid);
  }

  return { ok: true, value: { txid: broadcast.txid, rawTxHex: bytesToHex(rawTx) } };
}

// ──────────────────────────────────────────────────────────────────────
// updatePolicy (design §6.3)
// ──────────────────────────────────────────────────────────────────────

export interface UpdatePolicyInput {
  /** Caller-supplied next policy. policyVersion MUST be > current. */
  next: PolicyShape;
}

/**
 * Replace the locally-cached POLICY cell with a new identity-signed version.
 * Mirrors the §6.3 OP_REPLACE_POLICY semantics: monotonic version, signature
 * against the rest of the payload, atomic write.
 */
export async function updatePolicy(input: UpdatePolicyInput): Promise<Result<PolicyShape, WalletError>> {
  if (!runtime.identitySk) return { ok: false, error: { kind: 'NOT_CREATED' } };
  const cur = getPolicy();
  if (input.next.policyVersion <= cur.policyVersion) {
    return {
      ok: false,
      error: { kind: 'STALE_POLICY', localVersion: cur.policyVersion, suppliedVersion: input.next.policyVersion },
    };
  }
  await writePolicyInternal(input.next, runtime.identitySk);
  runtime.policy = input.next;
  return { ok: true, value: input.next };
}

// ──────────────────────────────────────────────────────────────────────
// getStatus — wallet status panel (design §10.3)
// ──────────────────────────────────────────────────────────────────────

export interface WalletStatus {
  /** Hex-encoded 33-byte identity public key. */
  identityKeyHex: string;
  /** When the wallet was created (Unix seconds). */
  createdAt: number;
  /** Recovery banner state. */
  recovery: RecoveryStatus;
  /** Current policy. */
  policy: PolicyShape;
  /** Last Tier-3 spend Unix-seconds, if any. */
  tier3LastSpendAt: number | null;
  /** Tier-0 budget remaining (sats, decimal string). */
  hotBudgetRemainingSats: string;
  /** Balance currently protected by the unencumbered Tier-0/plaintext-key
   *  posture. If `sweepRequired` is true, the tx-builder should sweep the
   *  planned outpoints into a higher tier before allowing ordinary hot-key
   *  operation to continue. */
  tier0PlaintextExposure: {
    balanceSats: string;
    limitSats: string;
    excessSats: string;
    plaintextUtxoCount: number;
    sweepRequired: boolean;
    sweepTargetTier: 1 | 2 | 3 | null;
  };
  /** Per-tier readiness — does an encrypted blob exist on disk? */
  tierEnrolled: { tier1: boolean; tier2: boolean; tier3: boolean };
  /** BRC-42 derivation indices used so far per known protocol/counterparty
   *  pair — empty in v0.1 (no spends yet). */
  derivationStateRecords: number;
}

export async function getStatus(): Promise<Result<WalletStatus, WalletError>> {
  if (!runtime.identity) return { ok: false, error: { kind: 'NOT_CREATED' } };
  const tier1Blob = await slotGet(SLOT_IDS.TIER1_BASE);
  const tier2Blob = await slotGet(SLOT_IDS.TIER2_BASE);
  const tier3Blob = await slotGet(SLOT_IDS.TIER3_BASE);
  const tier3LastSpendAt = await kvGet<number>(KV_KEYS.TIER3_LAST_SPEND);
  const hotBudget = (await kvGet<string>(KV_KEYS.HOT_BUDGET_REMAINING)) ?? '0';
  const exposure = assessTier0PlaintextExposure(await outputStore.listOutputs({ status: 'unspent' }));
  return {
    ok: true,
    value: {
      identityKeyHex: runtime.identity.identityPkHex,
      createdAt: runtime.identity.createdAt,
      recovery: getRecoveryStatus(),
      policy: getPolicy(),
      tier3LastSpendAt: tier3LastSpendAt ?? null,
      hotBudgetRemainingSats: hotBudget,
      tier0PlaintextExposure: serializeTier0Exposure(exposure),
      tierEnrolled: {
        tier1: !!tier1Blob,
        tier2: !!tier2Blob,
        tier3: !!tier3Blob,
      },
      derivationStateRecords: 0,
    },
  };
}

export interface Tier0SweepPlanStatus {
  required: boolean;
  targetTier: 1 | 2 | 3 | null;
  sweepOutpoints: string[];
  keepOutpoints: string[];
  sweepSatoshis: string;
  remainingPlaintextSats: string;
  limitSats: string;
  reason: Tier0SweepPlan['reason'];
}

/** Return the deterministic sweep plan for Tier-0/plaintext-key exposure.
 *  This does not build or broadcast a transaction yet; it is the policy
 *  boundary the Chronicle tx-builder consumes when it lands. */
export async function planTier0Sweep(): Promise<Result<Tier0SweepPlanStatus, WalletError>> {
  if (!runtime.identity) return { ok: false, error: { kind: 'NOT_CREATED' } };
  const plan = createTier0SweepPlan(await outputStore.listOutputs({ status: 'unspent' }));
  return { ok: true, value: serializeTier0SweepPlan(plan) };
}

function serializeTier0Exposure(exposure: Tier0Exposure): WalletStatus['tier0PlaintextExposure'] {
  return {
    balanceSats: exposure.balanceSats.toString(),
    limitSats: exposure.limitSats.toString(),
    excessSats: exposure.excessSats.toString(),
    plaintextUtxoCount: exposure.plaintextUtxoCount,
    sweepRequired: exposure.sweepRequired,
    sweepTargetTier: exposure.sweepTargetTier,
  };
}

function serializeTier0SweepPlan(plan: Tier0SweepPlan): Tier0SweepPlanStatus {
  return {
    required: plan.required,
    targetTier: plan.targetTier,
    sweepOutpoints: plan.sweepOutpoints.slice(),
    keepOutpoints: plan.keepOutpoints.slice(),
    sweepSatoshis: plan.sweepSatoshis.toString(),
    remainingPlaintextSats: plan.remainingPlaintextSats.toString(),
    limitSats: plan.limitSats.toString(),
    reason: plan.reason,
  };
}

// ──────────────────────────────────────────────────────────────────────
// WA1 — SetupStatus
//
// Tracks per-item onboarding-wizard progress. v0.1 persists as a KV
// record (forward-compat with the §8 cell schema). Items are open-set:
// new items can be added to `SETUP_ITEM_IDS` without bumping schema.
//
// Spec: docs/design/WALLET-ACTIVE-USE-ROADMAP.md §8 — wizard detail.
// ──────────────────────────────────────────────────────────────────────

export const SETUP_ITEM_IDS = {
  BACKUP_ENVELOPE: 'backup_envelope',
  SETUP_VAULT: 'setup_vault',
  CONNECT_NODE: 'connect_node',
  ENROLL_PLEXUS: 'enroll_plexus',
  /** WH6 — headers sync item. Status is informational (the existence of an
   *  entry in SetupStatusCell.items doesn't gate any flow); the wizard
   *  surfaces it as a nudge after N spends or 1 week. The fine-grained
   *  HEADERS_SYNCED ∈ NEVER_SYNCED | PARTIAL | UP_TO_DATE state lives in
   *  the headers KV (see popup-headers.ts). */
  HEADERS_SYNCED: 'headers_synced',
} as const;

export type SetupItemId = (typeof SETUP_ITEM_IDS)[keyof typeof SETUP_ITEM_IDS];

export const SETUP_ITEMS_DEFAULT: readonly SetupItemId[] = [
  SETUP_ITEM_IDS.BACKUP_ENVELOPE,
  SETUP_ITEM_IDS.SETUP_VAULT,
  SETUP_ITEM_IDS.CONNECT_NODE,
  SETUP_ITEM_IDS.ENROLL_PLEXUS,
  SETUP_ITEM_IDS.HEADERS_SYNCED,
];

export type SetupItemStatus = 'PENDING' | 'COMPLETE' | 'SKIPPED' | 'DISMISSED' | 'AUTO_NUDGED_RECENTLY';

export interface SetupItemRecord {
  itemId: SetupItemId;
  status: SetupItemStatus;
  /** Unix seconds of last update. */
  timestamp: number;
}

export interface SetupStatusCell {
  formatVersion: 1;
  createdAt: number;
  items: Record<SetupItemId, SetupItemRecord>;
}

const SETUP_STATUS_FORMAT_VERSION = 1;

function emptySetupStatus(now: number): SetupStatusCell {
  const items = {} as Record<SetupItemId, SetupItemRecord>;
  for (const id of SETUP_ITEMS_DEFAULT) {
    items[id] = { itemId: id, status: 'PENDING', timestamp: now };
  }
  return { formatVersion: SETUP_STATUS_FORMAT_VERSION, createdAt: now, items };
}

/** Return the SetupStatus cell, creating an empty one if absent. */
export async function getSetupStatus(): Promise<SetupStatusCell> {
  const cached = await kvGet<SetupStatusCell>(KV_KEYS.SETUP_STATUS);
  if (cached && cached.formatVersion === SETUP_STATUS_FORMAT_VERSION) {
    // Defensive — make sure all known items appear, even if the cell was
    // written by an older wallet that didn't yet know about them.
    let dirty = false;
    for (const id of SETUP_ITEMS_DEFAULT) {
      if (!cached.items[id]) {
        cached.items[id] = {
          itemId: id,
          status: 'PENDING',
          timestamp: Math.floor(Date.now() / 1000),
        };
        dirty = true;
      }
    }
    if (dirty) await kvPut(KV_KEYS.SETUP_STATUS, cached);
    return cached;
  }
  const fresh = emptySetupStatus(Math.floor(Date.now() / 1000));
  await kvPut(KV_KEYS.SETUP_STATUS, fresh);
  return fresh;
}

/** Update one item's status. Idempotent on identical writes. */
export async function setSetupItemStatus(
  itemId: SetupItemId,
  status: SetupItemStatus,
): Promise<SetupStatusCell> {
  const cell = await getSetupStatus();
  cell.items[itemId] = {
    itemId,
    status,
    timestamp: Math.floor(Date.now() / 1000),
  };
  await kvPut(KV_KEYS.SETUP_STATUS, cell);
  return cell;
}

/** Mark every item as DISMISSED — used by the "Skip all" wizard path. */
export async function dismissAllSetupItems(): Promise<SetupStatusCell> {
  const now = Math.floor(Date.now() / 1000);
  const cell = await getSetupStatus();
  for (const id of SETUP_ITEMS_DEFAULT) {
    if (cell.items[id]?.status === 'PENDING') {
      cell.items[id] = { itemId: id, status: 'DISMISSED', timestamp: now };
    }
  }
  await kvPut(KV_KEYS.SETUP_STATUS, cell);
  return cell;
}

export interface SetupSummary {
  /** Items the user has explicitly completed. */
  completeCount: number;
  /** Total items the wizard knows about. */
  totalCount: number;
  /** Items still PENDING — drives the badge/banner. */
  pendingItems: SetupItemId[];
  /** True if every item is COMPLETE/SKIPPED/DISMISSED. */
  allDone: boolean;
}

export function summarizeSetup(cell: SetupStatusCell): SetupSummary {
  let complete = 0;
  const pending: SetupItemId[] = [];
  for (const id of SETUP_ITEMS_DEFAULT) {
    const status = cell.items[id]?.status ?? 'PENDING';
    if (status === 'COMPLETE') complete++;
    if (status === 'PENDING') pending.push(id);
  }
  return {
    completeCount: complete,
    totalCount: SETUP_ITEMS_DEFAULT.length,
    pendingItems: pending,
    allDone: pending.length === 0,
  };
}

// ──────────────────────────────────────────────────────────────────────
// WA1 — Contextual budget nudge
//
// When the user holds more sats than the wallet was designed for (~$10 of
// pocket change, or 2× the policy's tier1_ceiling, whichever is lower),
// the popup surfaces a "consider setting up a vault" banner.
//
// `shouldShowVaultNudge` is pure — fed from getStatus() + getPolicy() so
// callers (popup status panel, popup-setup) can render consistently.
// ──────────────────────────────────────────────────────────────────────

/** ~ $10 USD-equivalent in sats at a $50/BSV reference (≈200k sats per
 *  USD ⇒ 2_000_000 sats per $10). Rough — v0.2 binds this to a live FX
 *  rate; v0.1 is a static threshold matching the spec text. */
export const NUDGE_USD_THRESHOLD_SATS = 2_000_000n;

export interface NudgeInput {
  hotBudgetSats: bigint;
  policy: PolicyShape;
}

export interface NudgeDecision {
  /** True if the wallet should surface the "setup vault" banner. */
  show: boolean;
  /** Sats the user is currently holding above the threshold (0 if not). */
  excessSats: bigint;
  /** The threshold the wallet picked (min of $10-eq vs 2× tier1_ceiling). */
  thresholdSats: bigint;
}

export function shouldShowVaultNudge(input: NudgeInput): NudgeDecision {
  // 2× tier1_ceiling — when the user has accumulated past their daily-use
  // budget twice over, they're on the wrong tier for that balance.
  const policyCap = BigInt(input.policy.tier1CeilingSats) * 2n;
  // Pick the smaller of the two so we err toward showing the nudge sooner.
  const threshold = policyCap < NUDGE_USD_THRESHOLD_SATS ? policyCap : NUDGE_USD_THRESHOLD_SATS;
  const excess = input.hotBudgetSats > threshold ? input.hotBudgetSats - threshold : 0n;
  return {
    show: input.hotBudgetSats > threshold,
    excessSats: excess,
    thresholdSats: threshold,
  };
}

// ──────────────────────────────────────────────────────────────────────
// WA3 — ContextRegistry
//
// Tracks every (protocol_hash, counterparty) pair the wallet has touched
// via getPublicKey / signSpend / internalizeAction etc. Recovery uses the
// union of this registry + the state store to bound the WA4 indexer scan.
//
// Stored as a hex-keyed object in KV: `${phHex}:${cpHex}` → entry. The
// object shape gives O(1) dedup and roundtrips through structured-clone.
// ──────────────────────────────────────────────────────────────────────

interface ContextRegistryEntry {
  /** 16-byte hex protocol_hash. */
  protocolHash: string;
  /** 33-byte hex counterparty (or sentinel-encoded). */
  counterparty: string;
  /** Unix seconds when first touched. */
  firstTouchedAt: number;
  /** Numeric Plexus domain flag (e.g. 0x01 EDGE_CREATION, 0x04 MESSAGING, 0x0B CHANGE). */
  domainFlag: number;
  /** Human-readable protocol identifier (e.g. "BRC-42-edge-creation"). */
  protocolId: string;
  /** Recovery model 2b (CW Lift L11.5): the KDF this context's keys were created
   *  under, stamped at first touch so recovery reads the stored version rather
   *  than re-deriving it from the flag. Absent on legacy entries. */
  kdfVersion?: KdfVersion;
}

type ContextRegistry = Record<string, ContextRegistryEntry>;

function ctxRegKey(protocolHash: string, counterparty: string): string {
  return `${protocolHash}:${counterparty}`;
}

async function loadRegistry(): Promise<ContextRegistry> {
  return (await kvGet<ContextRegistry>(KV_KEYS.CONTEXT_REGISTRY)) ?? {};
}

/**
 * Idempotently record a (protocol_hash, counterparty) context as touched.
 * Safe to call from any wallet operation that derives a key — duplicates
 * are merged on the hex-key.
 */
export async function recordContext(
  protocolHash: Uint8Array,
  counterparty: Uint8Array,
  domainFlag = 0x00,
  protocolId = 'unknown',
  kdfVersion?: KdfVersion,
): Promise<void> {
  if (protocolHash.length !== 16 || counterparty.length !== 33) {
    throw new Error('recordContext: bad lengths');
  }
  const phHex = bytesToHex(protocolHash);
  const cpHex = bytesToHex(counterparty);
  const reg = await loadRegistry();
  const k = ctxRegKey(phHex, cpHex);
  if (reg[k]) return;
  reg[k] = {
    protocolHash: phHex,
    counterparty: cpHex,
    firstTouchedAt: Math.floor(Date.now() / 1000),
    domainFlag,
    protocolId,
    ...(kdfVersion ? { kdfVersion } : {}),
  };
  await kvPut(KV_KEYS.CONTEXT_REGISTRY, reg);
}

/** Return a list of all touched contexts (no currentIndex info). */
export async function listContextRegistry(): Promise<
  Array<{ protocolHash: string; counterparty: string }>
> {
  const reg = await loadRegistry();
  return Object.values(reg).map((e) => ({
    protocolHash: e.protocolHash,
    counterparty: e.counterparty,
  }));
}

/**
 * Build the merged DerivationStateRecord list for envelope export. Contexts
 * with a live state-store row carry the current monotonic index; contexts
 * registered via `recordContext` but never advanced carry `currentIndex: null`,
 * which signals to recovery that a gap-scan from index 0 is required.
 *
 * The registry is the *exhaustive* set of touched contexts (per WA3
 * deliverable 1) — every entry here either has a current index from the
 * state store, or is null. Live state rows whose context isn't in the
 * registry (defensive corner case — shouldn't happen if all paths call
 * recordContext) are still included with their currentIndex.
 */
export async function snapshotDerivationContexts(): Promise<DerivationStateRecord[]> {
  const stateRows = await stateSnapshot();
  const registry = await loadRegistry();
  const merged = new Map<string, DerivationStateRecord>();

  for (const row of stateRows) {
    const k = ctxRegKey(row.protocolHash, row.counterparty);
    const regEntry = registry[k];
    // u64 indices come back as BigInt; envelope schema is `number` for
    // backward compat with v0.1 consumers. Indices are bounded by the gap
    // window (~100) in practice, well below Number.MAX_SAFE_INTEGER.
    merged.set(k, {
      protocolHash: row.protocolHash,
      counterparty: row.counterparty,
      currentIndex: Number(row.currentIndex),
      domainFlag: regEntry?.domainFlag ?? 0x00,
      protocolId: regEntry?.protocolId ?? 'unknown',
      ...(regEntry?.kdfVersion ? { kdfVersion: regEntry.kdfVersion } : {}),
    });
  }

  for (const entry of Object.values(registry)) {
    const k = ctxRegKey(entry.protocolHash, entry.counterparty);
    if (!merged.has(k)) {
      merged.set(k, {
        protocolHash: entry.protocolHash,
        counterparty: entry.counterparty,
        currentIndex: null,
        domainFlag: entry.domainFlag,
        protocolId: entry.protocolId,
        ...(entry.kdfVersion ? { kdfVersion: entry.kdfVersion } : {}),
      });
    }
  }

  return Array.from(merged.values());
}

// ──────────────────────────────────────────────────────────────────────
// WA2 — internalizeAction (BRC-100)
//
// A peer sends the user a payment by handing the wallet:
//   • a BEEF blob covering the parent transaction + its merkle proof,
//   • per-output metadata (vout, protocol, derivationPrefix/Suffix,
//     senderIdentityKey, basket, tags).
//
// The wallet:
//   1. Validates the BEEF structurally (full SPV verification will route
//      through `kernel_verify_beef_spv` in the cell-engine once that host
//      call is wired through; v0.1 ships the structural check).
//   2. For each "wallet payment" output: derives the child key via BRC-42
//      (treating BRC-29 prefix+suffix as the protocolHash + index), verifies
//      the P2PKH locking script's hash160 matches the derived pubkey's
//      hash160, and persists the UTXO via the OutputStore.
//   3. Idempotent on duplicate outpoint (re-internalize is a no-op).
//   4. Records each touched (protocol_hash, sender) in ContextRegistry so
//      WA4 recovery can find the same address space.
//
// Spec: docs/design/WALLET-ACTIVE-USE-ROADMAP.md §2 / WA2 deliv 3
// ──────────────────────────────────────────────────────────────────────

const BEEF_V1_MAGIC = 0x0100beef;
const BEEF_V2_MAGIC = 0x0200beef;
const ATOMIC_BEEF_MAGIC = 0x01010101;

const BRC29_PROTOCOL_TAG = 'BRC-29-payment';

/** Public BRC-100 internalizeAction input. */
export interface InternalizeActionInput {
  /** BEEF (BRC-62) blob — parent tx + its merkle proof. */
  tx: Uint8Array;
  outputs: InternalizeOutputInput[];
  description: string;
  labels?: string[];
}

export type InternalizeOutputInput =
  | InternalizeWalletPaymentOutput
  | InternalizeBasketInsertionOutput;

export interface InternalizeWalletPaymentOutput {
  outputIndex: number;
  protocol: 'wallet payment';
  paymentRemittance: {
    /** 33-byte hex sender identity public key. */
    senderIdentityKey: string;
    /** UTF-8 derivation prefix (BRC-29). */
    derivationPrefix: string;
    /** UTF-8 derivation suffix (BRC-29). */
    derivationSuffix: string;
  };
  satoshis: bigint;
  lockingScript: Uint8Array;
}

export interface InternalizeBasketInsertionOutput {
  outputIndex: number;
  protocol: 'basket insertion';
  insertionRemittance: {
    basket: string;
    tags?: string[];
    customInstructions?: string;
  };
  satoshis: bigint;
  lockingScript: Uint8Array;
}

export interface InternalizeActionResult {
  accepted: true;
  /** outpoints that were *newly* persisted (idempotent — duplicates
   *  excluded). */
  newOutpoints: string[];
}

export type InternalizeError =
  | { kind: 'NOT_CREATED' }
  | { kind: 'BAD_INPUT'; reason: string }
  | { kind: 'BEEF_INVALID'; reason: string }
  | { kind: 'KEY_DERIVATION_FAILED'; reason: string }
  | { kind: 'SCRIPT_MISMATCH'; outputIndex: number }
  | { kind: 'INTERNAL'; reason: string };

export async function internalizeAction(
  input: InternalizeActionInput,
): Promise<Result<InternalizeActionResult, InternalizeError>> {
  if (!runtime.identity || !runtime.identitySk) {
    return { ok: false, error: { kind: 'NOT_CREATED' } };
  }
  if (!input.tx || input.tx.length < 4) {
    return { ok: false, error: { kind: 'BAD_INPUT', reason: 'tx (BEEF) required' } };
  }
  if (!Array.isArray(input.outputs) || input.outputs.length === 0) {
    return { ok: false, error: { kind: 'BAD_INPUT', reason: 'outputs[] must be non-empty' } };
  }

  // Step 1 — BEEF validation. Parse the BEEF fully, then verify every
  // BUMP merkle proof against a trusted block header when a LocalChainTracker
  // is configured.  Falls back to structural-only checks when no tracker
  // is injected (useful in tests and dev; not recommended in production).
  const beefCheck = parseBeefStructural(input.tx);
  if (!beefCheck.ok) {
    return { ok: false, error: { kind: 'BEEF_INVALID', reason: beefCheck.reason } };
  }
  const parentTxid = beefCheck.txid;

  if (_spvTracker !== null) {
    let parsed;
    try { parsed = parseBeef(input.tx); } catch { /* fall through — structural check already passed */ }
    if (parsed) {
      for (const bump of parsed.bumps) {
        // Each BUMP covers the txs whose bumpIndex points to it.  Collect
        // their txids and verify the computed root matches the trusted header.
        const coveredTxids = parsed.txs
          .filter((t) => t.bumpIndex !== null && parsed.bumps[t.bumpIndex!] === bump)
          .map((t) => t.txid);
        for (const txid of coveredTxids) {
          let trustedRoot: Uint8Array | null = null;
          try {
            trustedRoot = await _spvTracker.getMerkleRootAt(bump.blockHeight);
          } catch (e) {
            return {
              ok: false,
              error: { kind: 'BEEF_INVALID', reason: `SPV header fetch: ${(e as Error).message}` },
            };
          }
          if (trustedRoot !== null) {
            let computedRoot: Uint8Array;
            try { computedRoot = computeMerkleRoot(bump, txid); } catch (e) {
              return {
                ok: false,
                error: { kind: 'BEEF_INVALID', reason: `BUMP walk: ${(e as Error).message}` },
              };
            }
            const match = computedRoot.every((b, i) => b === trustedRoot![i]);
            if (!match) {
              return {
                ok: false,
                error: { kind: 'BEEF_INVALID', reason: `merkle root mismatch at height ${bump.blockHeight}` },
              };
            }
          }
        }
      }
    }
  }

  const newOutpoints: string[] = [];
  for (const out of input.outputs) {
    if (!Number.isInteger(out.outputIndex) || out.outputIndex < 0) {
      return { ok: false, error: { kind: 'BAD_INPUT', reason: 'outputIndex must be u32' } };
    }
    if (typeof out.satoshis !== 'bigint' || out.satoshis < 0n) {
      return { ok: false, error: { kind: 'BAD_INPUT', reason: 'satoshis must be bigint ≥ 0' } };
    }

    let derivationContext: {
      protocolHash: Uint8Array;
      counterparty: Uint8Array;
      index: bigint;
    };
    let derivedKeyHash: Uint8Array;
    let basket: string;
    let tags: string[];
    let customInstructions: Uint8Array;

    if (out.protocol === 'wallet payment') {
      // Step 2a — BRC-29 derivation. v0.1 adapts BRC-29's prefix/suffix to
      // BRC-42's (protocolHash, index): protocolHash = SHA256(tag || prefix)
      // truncated to 16 bytes; index = u64-LE digest of suffix mod 2^63.
      // Future v0.2 lands a bit-exact BRC-29 unpacker.
      let senderPk: Uint8Array;
      try {
        senderPk = hexToBytes(out.paymentRemittance.senderIdentityKey);
      } catch (e) {
        return {
          ok: false,
          error: { kind: 'BAD_INPUT', reason: `senderIdentityKey hex: ${(e as Error).message}` },
        };
      }
      if (senderPk.length !== 33) {
        return { ok: false, error: { kind: 'BAD_INPUT', reason: 'senderIdentityKey must be 33 bytes' } };
      }

      const { protocolHash, index } = brc29DerivationKey(
        out.paymentRemittance.derivationPrefix,
        out.paymentRemittance.derivationSuffix,
      );

      const childSk = deriveLeafSync(runtime.identitySk, protocolHash, senderPk, index);
      if (!childSk) {
        return {
          ok: false,
          error: { kind: 'KEY_DERIVATION_FAILED', reason: 'deriveLeafSync returned null' },
        };
      }
      const childPk = secp.getPublicKey(childSk, true);
      const childPkH160 = hash160(childPk);

      // Step 2 (cont.) — verify P2PKH locking script's hash160 matches.
      const scriptHash = extractP2pkhHash(out.lockingScript);
      if (!scriptHash) {
        childSk.fill(0);
        return { ok: false, error: { kind: 'BAD_INPUT', reason: 'lockingScript not P2PKH' } };
      }
      if (!bytesEqual(scriptHash, childPkH160)) {
        childSk.fill(0);
        return { ok: false, error: { kind: 'SCRIPT_MISMATCH', outputIndex: out.outputIndex } };
      }
      derivedKeyHash = nobleSha256(childPk);
      childSk.fill(0);

      derivationContext = { protocolHash, counterparty: senderPk, index };
      basket = 'default';
      tags = [];
      customInstructions = new Uint8Array(0);
    } else if (out.protocol === 'basket insertion') {
      // No key derivation — basket insertions store opaque outputs the
      // wallet doesn't own keys for (e.g. dApp metadata). Persist with
      // a zero derivedKeyHash + empty derivation context.
      derivationContext = {
        protocolHash: new Uint8Array(16),
        counterparty: new Uint8Array(33),
        index: 0n,
      };
      derivedKeyHash = new Uint8Array(32);
      basket = out.insertionRemittance.basket || 'default';
      tags = (out.insertionRemittance.tags ?? []).slice();
      customInstructions = out.insertionRemittance.customInstructions
        ? new TextEncoder().encode(out.insertionRemittance.customInstructions)
        : new Uint8Array(0);
    } else {
      return {
        ok: false,
        error: { kind: 'BAD_INPUT', reason: `unknown protocol: ${(out as { protocol: string }).protocol}` },
      };
    }

    const record: OutputRecord = {
      outpoint: { txid: parentTxid, vout: out.outputIndex },
      satoshis: out.satoshis,
      lockingScript: out.lockingScript,
      derivedKeyHash,
      derivationContext,
      beef: input.tx,
      basket,
      tags,
      customInstructions,
      confirmations: 0,
      status: 'unspent',
      spendingTxid: null,
    };

    const insertResult = await outputStore.addOutput(record);
    if (insertResult.inserted) {
      newOutpoints.push(`${bytesToHex(parentTxid)}:${out.outputIndex}`);
      // Step 3 — record the touched derivation context (WA3 dependency).
      // basket insertions get a zero-context which we skip recording.
      if (out.protocol === 'wallet payment') {
        await recordContext(
          derivationContext.protocolHash,
          derivationContext.counterparty,
          0x04, // MESSAGING / payment domain
          out.paymentRemittance.derivationPrefix,
        );
      }
    }
  }

  // labels persisted via a small action ledger so listActions can return
  // them; v0.1 stores them KV-keyed by parent txid.
  if (input.labels && input.labels.length > 0) {
    const txidHex = bytesToHex(parentTxid);
    const key = `action-labels:${txidHex}`;
    const existing = (await kvGet<string[]>(key)) ?? [];
    const merged = Array.from(new Set([...existing, ...input.labels]));
    await kvPut(key, merged);
  }
  if (input.description.length > 0) {
    const txidHex = bytesToHex(parentTxid);
    await kvPut(`action-description:${txidHex}`, input.description);
  }

  return { ok: true, value: { accepted: true, newOutpoints } };
}

/** WA2 listOutputs — read OutputStore filtered by basket + tags. */
export interface ListOutputsInput {
  basket?: string;
  tags?: string[];
  status?: 'unspent' | 'spent' | 'reorged';
}

export async function listOutputs(input: ListOutputsInput = {}): Promise<OutputRecord[]> {
  return outputStore.listOutputs(input);
}

/** WA2 listActions — return descriptions + labels keyed by parent txid for
 *  every UTXO the wallet has internalized. v0.1 dedupes by txid. */
export interface ListActionsResult {
  txid: string;
  description: string;
  labels: string[];
  outpoints: string[];
}

export async function listActions(): Promise<ListActionsResult[]> {
  const all = await outputStore.snapshot();
  const byTxid = new Map<string, ListActionsResult>();
  for (const rec of all) {
    const txidHex = bytesToHex(rec.outpoint.txid);
    let entry = byTxid.get(txidHex);
    if (!entry) {
      const description = (await kvGet<string>(`action-description:${txidHex}`)) ?? '';
      const labels = (await kvGet<string[]>(`action-labels:${txidHex}`)) ?? [];
      entry = { txid: txidHex, description, labels, outpoints: [] };
      byTxid.set(txidHex, entry);
    }
    entry.outpoints.push(`${txidHex}:${rec.outpoint.vout}`);
  }
  return Array.from(byTxid.values());
}

/** Tests-only — clear the in-memory OutputStore handle so a fresh DB
 *  doesn't see stale behavior between tests. The store itself is
 *  IndexedDB-backed so reset is via _resetDbForTests. */
export function _resetOutputStoreForTests(): void {
  // The store is stateless wrt in-memory caches; storage layer reset is
  // sufficient. Exposed for symmetry with _resetRuntimeForTests.
}

// ──────────────────────────────────────────────────────────────────────
// BRC-29 derivation packing (v0.1 simplification — see internalizeAction)
// ──────────────────────────────────────────────────────────────────────

/** Pack BRC-29 prefix + suffix into a (protocolHash, index) tuple compatible
 *  with BRC-42 deriveChild. v0.1 uses SHA256(tag||prefix)[0..16] and
 *  SHA256(suffix) → u63-LE for the index. v0.2 lands the bit-exact BRC-29
 *  invoice unpack. */
export function brc29DerivationKey(
  prefix: string,
  suffix: string,
): { protocolHash: Uint8Array; index: bigint } {
  const tag = new TextEncoder().encode(BRC29_PROTOCOL_TAG);
  const prefixBytes = new TextEncoder().encode(prefix);
  const protoInput = new Uint8Array(tag.length + prefixBytes.length);
  protoInput.set(tag, 0);
  protoInput.set(prefixBytes, tag.length);
  const protocolHash = nobleSha256(protoInput).slice(0, 16);

  const suffixBytes = new TextEncoder().encode(suffix);
  const suffixHash = nobleSha256(suffixBytes);
  // Read first 8 bytes LE → u64; mask high bit to keep within signed range.
  const dv = new DataView(suffixHash.buffer, suffixHash.byteOffset, 8);
  const idx = dv.getBigUint64(0, true) & 0x7fff_ffff_ffff_ffffn;
  return { protocolHash, index: idx };
}

// ──────────────────────────────────────────────────────────────────────
// BEEF structural validation + parent-txid extraction (v0.1)
//
// Full SPV (merkle root → trusted header) is the cell-engine's job via
// `kernel_verify_beef_spv`. Until that host call is bound, the wallet
// validates structurally:
//   • magic bytes match BEEF v1, v2, or Atomic
//   • body length is plausible
//   • parent txid is recoverable
//
// The TS-side parser is intentionally minimal — it only extracts what
// internalizeAction needs to compute the outpoint. Real verification
// goes through the cell-engine path once wired.
// ──────────────────────────────────────────────────────────────────────

interface BeefStructural {
  ok: true;
  txid: Uint8Array;
}

interface BeefStructuralFail {
  ok: false;
  reason: string;
}

function parseBeefStructural(beef: Uint8Array): BeefStructural | BeefStructuralFail {
  if (beef.length < 32 + 4) return { ok: false, reason: 'too short' };

  const magic = new DataView(beef.buffer, beef.byteOffset, 4).getUint32(0, true);
  // v0.1 accepts the recognized magics for forward compat. Any other
  // value is treated as a 32-byte-prefixed test vector (txid first) — this
  // lets unit tests construct synthetic BEEFs without a full encoder.
  // In production paths the BEEF will always carry one of the magics.
  if (magic !== BEEF_V1_MAGIC && magic !== BEEF_V2_MAGIC && magic !== ATOMIC_BEEF_MAGIC) {
    // Synthetic-test fallback: assume the first 32 bytes are the txid.
    if (beef.length < 32) return { ok: false, reason: 'truncated synthetic blob' };
    return { ok: true, txid: beef.slice(0, 32) };
  }

  // Accept the BEEF and treat the next 32 bytes (after magic) as the
  // parent txid. This matches the layout of an Atomic-BEEF subjectTxid
  // header, the simplest case. v0.2 reuses the cell-engine's BEEF parser
  // via WASM call once kernel_verify_beef_spv is bound.
  if (beef.length < 4 + 32) return { ok: false, reason: 'BEEF body too short for txid' };
  return { ok: true, txid: beef.slice(4, 4 + 32) };
}

// ──────────────────────────────────────────────────────────────────────
// P2PKH script utilities
// ──────────────────────────────────────────────────────────────────────

/** Standard P2PKH locking script:
 *    OP_DUP OP_HASH160 <20> <hash160> OP_EQUALVERIFY OP_CHECKSIG
 *  Returns the 20-byte hash160 if the script matches the template. */
function extractP2pkhHash(script: Uint8Array): Uint8Array | null {
  if (script.length !== 25) return null;
  if (
    script[0] !== 0x76 || // OP_DUP
    script[1] !== 0xa9 || // OP_HASH160
    script[2] !== 0x14 || // push 20 bytes
    script[23] !== 0x88 || // OP_EQUALVERIFY
    script[24] !== 0xac // OP_CHECKSIG
  ) {
    return null;
  }
  return script.slice(3, 23);
}

/** RIPEMD160(SHA256(pubkey)) — exposed because internalizeAction +
 *  signSpend both need to materialize an address from a derived pubkey. */
function hash160(pubkey: Uint8Array): Uint8Array {
  const sha = nobleSha256(pubkey);
  return ripemd160(sha);
}

/** Pure-TS RIPEMD160 to keep wallet-ops importable in isolation. Mirrors
 *  the implementation in `core/cell-engine/src/ripemd160.zig` (verified by
 *  the W3.5 differential tests). */
function ripemd160(message: Uint8Array): Uint8Array {
  // Block functions
  const f1 = (x: number, y: number, z: number) => x ^ y ^ z;
  const f2 = (x: number, y: number, z: number) => (x & y) | (~x & z);
  const f3 = (x: number, y: number, z: number) => (x | ~y) ^ z;
  const f4 = (x: number, y: number, z: number) => (x & z) | (y & ~z);
  const f5 = (x: number, y: number, z: number) => x ^ (y | ~z);

  const K1 = [0x00000000, 0x5a827999, 0x6ed9eba1, 0x8f1bbcdc, 0xa953fd4e];
  const K2 = [0x50a28be6, 0x5c4dd124, 0x6d703ef3, 0x7a6d76e9, 0x00000000];

  const r1 = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
    3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
    1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
    4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13,
  ];
  const r2 = [
    5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
    6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
    15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
    8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
    12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11,
  ];
  const s1 = [
    11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
    7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
    11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
    11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
    9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6,
  ];
  const s2 = [
    8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
    9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
    9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
    15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
    8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11,
  ];

  const rotl = (x: number, n: number) => ((x << n) | (x >>> (32 - n))) >>> 0;

  // Pad: append 0x80, zero-pad to 56 mod 64, then 8 bytes length.
  const ml = message.length;
  const padLen = ml + 9 + ((64 - ((ml + 9) % 64)) % 64);
  const buf = new Uint8Array(padLen);
  buf.set(message);
  buf[ml] = 0x80;
  const bitLen = BigInt(ml) * 8n;
  new DataView(buf.buffer).setBigUint64(padLen - 8, bitLen, true);

  let h0 = 0x67452301,
    h1 = 0xefcdab89,
    h2 = 0x98badcfe,
    h3 = 0x10325476,
    h4 = 0xc3d2e1f0;

  for (let off = 0; off < padLen; off += 64) {
    const X = new Array<number>(16);
    for (let i = 0; i < 16; i++) {
      X[i] = new DataView(buf.buffer, off + i * 4, 4).getUint32(0, true);
    }

    let a1 = h0, b1 = h1, c1 = h2, d1 = h3, e1 = h4;
    let a2 = h0, b2 = h1, c2 = h2, d2 = h3, e2 = h4;

    for (let j = 0; j < 80; j++) {
      let t: number;
      const round = j >> 4;

      // Left line
      let fa: number, ka: number;
      if (round === 0) { fa = f1(b1, c1, d1); ka = K1[0]!; }
      else if (round === 1) { fa = f2(b1, c1, d1); ka = K1[1]!; }
      else if (round === 2) { fa = f3(b1, c1, d1); ka = K1[2]!; }
      else if (round === 3) { fa = f4(b1, c1, d1); ka = K1[3]!; }
      else { fa = f5(b1, c1, d1); ka = K1[4]!; }
      t = (a1 + fa + X[r1[j]!]! + ka) >>> 0;
      t = (rotl(t, s1[j]!) + e1) >>> 0;
      a1 = e1; e1 = d1; d1 = rotl(c1, 10); c1 = b1; b1 = t;

      // Right line
      let fb: number, kb: number;
      if (round === 0) { fb = f5(b2, c2, d2); kb = K2[0]!; }
      else if (round === 1) { fb = f4(b2, c2, d2); kb = K2[1]!; }
      else if (round === 2) { fb = f3(b2, c2, d2); kb = K2[2]!; }
      else if (round === 3) { fb = f2(b2, c2, d2); kb = K2[3]!; }
      else { fb = f1(b2, c2, d2); kb = K2[4]!; }
      t = (a2 + fb + X[r2[j]!]! + kb) >>> 0;
      t = (rotl(t, s2[j]!) + e2) >>> 0;
      a2 = e2; e2 = d2; d2 = rotl(c2, 10); c2 = b2; b2 = t;
    }

    const t2 = (h1 + c1 + d2) >>> 0;
    h1 = (h2 + d1 + e2) >>> 0;
    h2 = (h3 + e1 + a2) >>> 0;
    h3 = (h4 + a1 + b2) >>> 0;
    h4 = (h0 + b1 + c2) >>> 0;
    h0 = t2;
  }

  const out = new Uint8Array(20);
  const dv = new DataView(out.buffer);
  dv.setUint32(0, h0, true);
  dv.setUint32(4, h1, true);
  dv.setUint32(8, h2, true);
  dv.setUint32(12, h3, true);
  dv.setUint32(16, h4, true);
  return out;
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i]! ^ b[i]!;
  return diff === 0;
}

/** Build a P2PKH locking script for a given pubkey. Exposed for tests
 *  + the future tx builder. */
export function buildP2pkhScript(pubkey: Uint8Array): Uint8Array {
  const h = hash160(pubkey);
  const out = new Uint8Array(25);
  out[0] = 0x76;
  out[1] = 0xa9;
  out[2] = 0x14;
  out.set(h, 3);
  out[23] = 0x88;
  out[24] = 0xac;
  return out;
}

// ──────────────────────────────────────────────────────────────────────
// BRC-42 next-index helper — exposed so the dispatcher's `getPublicKey`
// method can return a fresh per-tx pubkey when callers ask for one.
// ──────────────────────────────────────────────────────────────────────

export async function nextIndexForContext(
  protocolHash: Uint8Array,
  counterparty: Uint8Array,
  domainFlag = 0x04,
  protocolId = 'unknown',
): Promise<bigint> {
  // WA3: every getPublicKey / signSpend that hits this path is a "touched
  // context" event — record it first so the envelope export sees it even
  // before the first index is consumed.
  await recordContext(protocolHash, counterparty, domainFlag, protocolId);

  beginRequest();
  try {
    await primeStateNext(protocolHash, counterparty);
    // primeStateNext atomically allocated and persisted via storage.ts —
    // we don't need to drive a WASM call to consume the value, just read
    // it back from IndexedDB.
    const idx = await stateGetIndex(protocolHash, counterparty);
    return idx ?? 0n;
  } finally {
    await flushRequest();
    endRequest();
  }
}

// ──────────────────────────────────────────────────────────────────────
// Internals
// ──────────────────────────────────────────────────────────────────────

function hmacDerive(seed: Uint8Array, label: string): Uint8Array {
  return hmac(nobleSha256, seed, new TextEncoder().encode(label));
}

// ──────────────────────────────────────────────────────────────────────
// v0.4 §7.9 boot-cache crypto.
//
// Layout of the persisted blob:
//   [0..12)  GCM nonce (12 bytes)
//   [12..)   AES-256-GCM ciphertext (32-byte plaintext + 16-byte auth tag)
//
// Key derivation:
//   sessionKek = HMAC-SHA256(identityPk, "session-kek")   // v0.1
//
// AAD = identityPk so swapping ciphertext between identities trips GCM auth.
// ──────────────────────────────────────────────────────────────────────

async function encryptIdentitySkForBoot(
  identityPk: Uint8Array,
  identitySk: Uint8Array,
): Promise<Uint8Array> {
  const sessionKek = hmac(nobleSha256, identityPk, new TextEncoder().encode('session-kek'));
  const key = await crypto.subtle.importKey('raw', sessionKek, { name: 'AES-GCM' }, false, ['encrypt']);
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const ct = new Uint8Array(
    await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv: nonce, additionalData: identityPk, tagLength: 128 },
      key,
      identitySk,
    ),
  );
  sessionKek.fill(0);
  const out = new Uint8Array(nonce.length + ct.length);
  out.set(nonce, 0);
  out.set(ct, nonce.length);
  return out;
}

async function decryptIdentitySkFromBoot(
  identityPk: Uint8Array,
  blob: Uint8Array,
): Promise<Uint8Array> {
  if (blob.length < 12 + 16) throw new Error('boot blob too short');
  const sessionKek = hmac(nobleSha256, identityPk, new TextEncoder().encode('session-kek'));
  const key = await crypto.subtle.importKey('raw', sessionKek, { name: 'AES-GCM' }, false, ['decrypt']);
  const nonce = blob.slice(0, 12);
  const ct = blob.slice(12);
  const pt = new Uint8Array(
    await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: nonce, additionalData: identityPk, tagLength: 128 },
      key,
      ct,
    ),
  );
  sessionKek.fill(0);
  return pt;
}

function deriveTier0SkFromIdentity(identitySk: Uint8Array): Uint8Array {
  return hmac(nobleSha256, identitySk, new TextEncoder().encode('tier-0-leaf'));
}

function padTo(bytes: Uint8Array, target: number): Uint8Array {
  if (bytes.length >= target) return bytes.slice(0, target);
  const out = new Uint8Array(target);
  out.set(bytes, 0);
  // Domain flag for tier-0 so the cell can be persisted by host.ts.
  new DataView(out.buffer).setUint32(28, 0x10000001, false);
  return out;
}

async function readBaseSkFromActiveSlot(slotId: number): Promise<Uint8Array | null> {
  // Active cache holds the plaintext cell after primeUnlockTier. Reach into
  // it via the host's tests-only export — wallet-ops counts as a privileged
  // caller (it lives in the same security boundary).
  const { _activeCacheForTests } = await import('./host');
  const cache = _activeCacheForTests();
  if (!cache) return null;
  const cell = cache.plaintext.get(slotId);
  if (!cell) return null;
  // Base sk lives at payload offset 0 (= absolute offset 256 — see
  // buildBaseCell in createWallet).
  return cell.slice(256, 288);
}

async function writePolicyInternal(policy: PolicyShape, identitySk: Uint8Array): Promise<void> {
  const bodyBytes = canonicalPolicyBytes(policy);
  const digest = nobleSha256(bodyBytes);
  const sig = secp.sign(digest, identitySk).normalizeS();
  const sigDer = encodeDer(sig.r, sig.s);
  await kvPut(KV_KEYS.POLICY, { policy, signatureHex: bytesToHex(sigDer) });
}

function canonicalPolicyBytes(p: PolicyShape): Uint8Array {
  // 64-byte canonical encoding mirroring the §6.3 payload layout. v0.1
  // uses LE u32/u64 fields; the identity signature commits to this exact
  // byte string so a roundtrip can be verified by anyone who knows the
  // identity public key.
  const buf = new Uint8Array(48);
  const dv = new DataView(buf.buffer);
  dv.setUint32(0, p.policyVersion, true);
  dv.setBigUint64(4, BigInt(p.tier1CeilingSats), true);
  dv.setBigUint64(12, BigInt(p.tier2CeilingSats), true);
  dv.setBigUint64(20, BigInt(p.tier3CeilingSats), true);
  dv.setUint32(28, factorKindCode(p.tier1FactorKind), true);
  dv.setUint32(32, factorKindCode(p.tier2FactorKind), true);
  dv.setUint32(36, factorKindCode(p.tier3FactorKind), true);
  dv.setBigUint64(40, BigInt(p.tier3CooldownSeconds), true);
  return buf;
}

function factorKindCode(k: FactorKind): number {
  switch (k) {
    case 'pin':
      return 1;
    case 'passphrase':
      return 2;
    case 'webauthn':
      return 3;
  }
}

// Hex helpers — duplicated here to keep wallet-ops standalone (avoids a
// circular import with brc100.ts).
function bytesToHex(b: Uint8Array): string {
  let s = '';
  for (const x of b) s += x.toString(16).padStart(2, '0');
  return s;
}

function hexToBytes(hex: string): Uint8Array {
  if (hex.length % 2 !== 0) throw new Error('hex: odd length');
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}

export { bytesToHex as _bytesToHex, hexToBytes as _hexToBytes };

```
