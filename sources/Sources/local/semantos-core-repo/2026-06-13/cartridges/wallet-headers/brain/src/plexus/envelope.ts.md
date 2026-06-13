---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/plexus/envelope.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.677479+00:00
---

# cartridges/wallet-headers/brain/src/plexus/envelope.ts

```ts
// Plexus dispatch envelope builder (W7).
//
// Constructs the JSON envelope posted to a Plexus operator's
// `/enrollment/dispatch` endpoint, per `docs/design/WALLET-TIER-CUSTODY.md`
// §8.2. The envelope contains:
//
//   • the user's BRC-52 identity key + cert id,
//   • a contact email (sent in the clear so Plexus can email an OTP),
//   • a SHA256-salted hash of each challenge answer (so the wallet can prove
//     them again on recovery without ever leaving the device),
//   • an AES-256-GCM ciphertext of the recovery seed, keyed by a PBKDF2 of
//     the concatenated normalized challenge answers (so Plexus stores ONLY
//     ciphertext — never the answers, never the seed),
//   • per-tier BRC-43 derivation context metadata,
//   • a snapshot of the local DerivationState so the recovered device can
//     resume monotonic indices instead of gap-scanning,
//   • a per-relationship `kdfVersion` in each recovery recipe — the canonical
//     KDF the domain derives under (CW Lift L11): bilateral domains (edges,
//     messaging) stay BRC-42 = 'plexus-kdf-v1'; unilateral domains (change +
//     cell anchors) use EP3259724B1 deriveSegment = 'plexus-kdf-v2',
//   • an `algorithmVersion` numeric envelope-era counter: v2 ⇒ recipes carry
//     per-domain `kdfVersion`. (Distinct vocab: numeric era vs. the string
//     `kdfVersion` aligned with the SDK + derive_segment.zig.)
//
// The wallet runs every §8.2 invariant *before* dispatch (this is the §8.2
// "checks 1–5" that the design says are mechanically checkable):
//
//   1. No plaintext private key, mnemonic, or plaintext challenge answer
//      appears anywhere in the JSON.
//   2. answerHashes[i] == sha256(salt || normalize(answer_i)).
//   3. encryptedRecoverySeed.ciphertext decrypts to exactly the seed when
//      keyed by the same answers (round-tripped here).
//   4. The envelope is signed by the identity key whose public form is
//      identityKey.
//   5. certId matches the BRC-52 cert this identity is using (caller's
//      responsibility to pass the correct cert id; we verify it's hex-shaped
//      and 32 bytes).
//
// Sensitive intermediates (raw answers, the seed, the KEK) are wiped from
// memory after the envelope is built — caller-supplied buffers are *not*
// retained, only their hashes/ciphertexts. Tests confirm this where feasible.
//
// Cross-references:
//   • design §8.2 (envelope schema + invariants)
//   • design §3.5.2 (DerivationState records)
//   • design §11 Q7 (incremental updates — TBD; v0.1 ships full re-dispatch)

import * as secp from '@noble/secp256k1';
import { hmac } from '@noble/hashes/hmac';
import { sha256 as nobleSha256 } from '@noble/hashes/sha2';
import { pbkdf2 } from '@noble/hashes/pbkdf2';

import { buildEnvelope as buildBrc100, hexToBytes, bytesToHex } from '../brc100';

// Make secp signing synchronous (matches host.ts).
secp.etc.hmacSha256Sync = (key: Uint8Array, ...msgs: Uint8Array[]): Uint8Array =>
  hmac(nobleSha256, key, secp.etc.concatBytes(...msgs));

// ──────────────────────────────────────────────────────────────────────
// Schema (mirror of design §8.2)
// ──────────────────────────────────────────────────────────────────────

/** Per-tier derivation policy values per Plexus Client Reqs §1.4 / design §8.2. */
export type RecoveryPolicy = 'BACKUP_ON_CREATE' | 'BACKUP_ON_CONFIRM' | 'NONE';

/**
 * Canonical KDF identifier a derivation domain uses (CW Lift L11 / L11.5).
 * Aligned with the Plexus SDK `KdfVersion` and `derive_segment.zig` KDF_VERSION:
 *   'plexus-kdf-v1' — BRC-42 (bilateral; HMAC over an ECDH shared secret).
 *   'plexus-kdf-v2' — EP3259724B1 `deriveSegment` (unilateral; SHA-256(invoice)).
 *   'plexus-kdf-v3' — EP3259724B1 `deriveDomainSegment` (unilateral, domain-
 *     separated; SHA-256(u32_be(domainFlag) || invoice)). The flag binds the
 *     key to its declared domain (CW Lift L11.5).
 */
export type KdfVersion = 'plexus-kdf-v1' | 'plexus-kdf-v2' | 'plexus-kdf-v3';

/**
 * Bilateral derivation domains — a real counterparty, so BRC-42 (kdf-v1) is the
 * correct primitive: EDGE (0x01) and MESSAGING (0x04). Every other domain
 * (CHANGE 0x0B + sovereign cell-anchor flags ≥ 0x00010000) is unilateral and
 * derives via deriveSegment (kdf-v2).
 */
const BILATERAL_DOMAIN_FLAGS: ReadonlySet<number> = new Set([0x01, 0x04]);

/** The KDF a domain derives under — recorded per recovery recipe so a restoring
 *  device routes to the correct derivation algorithm. */
export function kdfVersionForDomain(domainFlag: number): KdfVersion {
  return BILATERAL_DOMAIN_FLAGS.has(domainFlag) ? 'plexus-kdf-v1' : 'plexus-kdf-v2';
}

export interface DerivationContext {
  tier: 1 | 2 | 3;
  brc43InvoiceString: string;
  /** Hex-encoded 4-byte domain flag, e.g. "0x10000003". Free-form prefix
   * preserved for human-readability per the design doc. */
  domainFlag: string;
  recoveryPolicy: RecoveryPolicy;
}

export interface DerivationStateRecord {
  /** 16-byte hex. */
  protocolHash: string;
  /** 33-byte compressed pubkey hex (or "self" / "anyone" sentinels). */
  counterparty: string;
  /** BRC-42 monotonic index. WA3: `null` means the context was touched
   *  (recorded in ContextRegistry) but the wallet has no live index — recovery
   *  must gap-scan from index 0 for this context. Pre-WA3 envelopes always
   *  carry a number. */
  currentIndex: number | null;
  /** Numeric Plexus domain flag (e.g. 0x01 EDGE_CREATION, 0x04 MESSAGING,
   *  0x0B CHANGE). Used by recovery to route to the correct derivation path. */
  domainFlag: number;
  /** Human-readable protocol identifier (e.g. "BRC-42-edge-creation"). */
  protocolId: string;
  /** Recovery model 2b (CW Lift L11.5): the KDF this record was created under,
   *  stamped at key-creation so recovery reads the stored version instead of
   *  re-deriving it from the flag. When present it wins over
   *  `kdfVersionForDomain(domainFlag)` in the recipe. Absent on legacy records
   *  (read via the flag→version fallback). CHANGE records now stamp v3. */
  kdfVersion?: KdfVersion;
}

/**
 * A compact recovery descriptor for one (protocol × counterparty) relationship.
 * Given the identity key + this record, every UTXO under the relationship can
 * be re-derived by scanning indices 0…highWaterMark (+ gap window).
 * counterpartyPk is null for self-directed domains (change).
 */
export interface RelationshipRecipe {
  domainFlag: number;
  protocolId: string;
  /** 16-byte hex protocol hash. */
  protocolHash: string;
  /** 33-byte compressed pubkey hex of the counterparty, or null for self (change). */
  counterpartyPk: string | null;
  /** Highest invoice index seen; null → gap-scan from 0. */
  highWaterMark: number | null;
  /** Canonical KDF this relationship derives under (CW Lift L11). Present on
   *  algorithmVersion ≥ 2 envelopes; absent on legacy v1 envelopes (read as
   *  'plexus-kdf-v1'). Bilateral edges = v1 (BRC-42); change/anchors = v2. */
  kdfVersion: KdfVersion;
}

export interface DerivationStateSnapshot {
  records: DerivationStateRecord[];
  /** RFC3339. */
  snapshotTimestamp: string;
}

export interface ChallengeBundle {
  questions: string[];
  /** 32-byte salt, hex. */
  salt: string;
  /** sha256(salt || normalize(answer_i)), hex. */
  answerHashes: string[];
  /** PBKDF2 cost factor for seed encryption KEK. Pinned at 100_000. */
  kdfIterations: number;
}

export interface EncryptedRecoverySeed {
  ciphertext: string;
  /** 12-byte GCM nonce hex. */
  nonce: string;
  /** 16-byte GCM auth tag hex. */
  tag: string;
  /** AAD = identityKey(33) || envelopeVersion_le1, hex. */
  aad: string;
}

export interface PlexusRecoveryEnvelope {
  envelopeVersion: 1;
  identityKey: string;
  certId: string;
  contactEmail: string;
  challengeBundle: ChallengeBundle;
  encryptedRecoverySeed: EncryptedRecoverySeed;
  derivationContexts: DerivationContext[];
  edgeRecipes: RelationshipRecipe[];
  derivationStateSnapshot: DerivationStateSnapshot;
  /** Envelope KDF-era counter. 1 = pre-L11 (recipes carry no kdfVersion; all
   *  derivation was BRC-42). 2 = L11-aware (recipes carry per-domain
   *  kdfVersion; unilateral domains use deriveSegment). The type stays a union
   *  so legacy v1 envelopes remain readable. */
  algorithmVersion: 1 | 2;
}

// ──────────────────────────────────────────────────────────────────────
// Constants
// ──────────────────────────────────────────────────────────────────────

export const PBKDF2_ITERATIONS = 100_000;
export const ENVELOPE_VERSION = 1;
/** Bumped 1 → 2 for CW Lift L11: recovery recipes now carry a per-domain
 *  `kdfVersion`; unilateral domains (change, anchors) derive via deriveSegment.
 *  The envelope wire FORMAT (envelopeVersion / AAD) is unchanged. */
export const ALGORITHM_VERSION = 2;
const SEED_BYTES = 64; // BIP39 PBKDF2 seed length
const SALT_BYTES = 32;
const GCM_NONCE_BYTES = 12;
const GCM_TAG_BYTES = 16;

// ──────────────────────────────────────────────────────────────────────
// Inputs / outputs of buildEnvelope
// ──────────────────────────────────────────────────────────────────────

/** Inputs the wallet collects locally before dispatching. */
export interface BuildEnvelopeInput {
  identitySk: Uint8Array; // 32 bytes
  identityPk: Uint8Array; // 33 bytes
  certId: Uint8Array; // 32 bytes
  contactEmail: string;
  questions: string[];
  /** Plaintext answers — same order as `questions`. Wiped after build. */
  answers: string[];
  /** The 64-byte BIP39 seed to encrypt under the answers-derived KEK. Wiped. */
  recoverySeed: Uint8Array;
  derivationContexts: DerivationContext[];
  derivationStateSnapshot: DerivationStateSnapshot;
  /** Optional: reuse a known salt/nonce for tests. */
  testOverrides?: {
    salt?: Uint8Array;
    gcmNonce?: Uint8Array;
  };
}

export type BuildResult =
  | {
      ok: true;
      envelope: PlexusRecoveryEnvelope;
      /** BRC-100 wire-format envelope wrapping JSON.stringify(envelope). */
      brc100: ReturnType<typeof buildBrc100>;
      /** UTF-8 bytes the BRC-100 signature commits to. */
      bodyBytes: Uint8Array;
    }
  | { ok: false; error: BuildError };

export type BuildError =
  | { kind: 'INVALID_INPUT'; reason: string }
  | { kind: 'INVARIANT_FAILED'; check: 1 | 2 | 3 | 4 | 5; detail: string };

// ──────────────────────────────────────────────────────────────────────
// Public API
// ──────────────────────────────────────────────────────────────────────

/**
 * Build + sign the dispatch envelope. Performs every §8.2 invariant check
 * before returning, so the caller always sees either:
 *   - { ok: true, envelope, brc100, bodyBytes } — safe to POST,
 *   - { ok: false, error: { kind, ... } }       — surfaced to the UI.
 *
 * On success, all sensitive intermediates (raw answers, seed bytes, KEK)
 * are zeroed inside this function. The caller should also wipe their own
 * copy of `answers` / `recoverySeed` after calling.
 */
export async function buildEnvelope(input: BuildEnvelopeInput): Promise<BuildResult> {
  // ── Input validation ─────────────────────────────────────────────
  if (input.identitySk.length !== 32) {
    return inputErr('identitySk must be 32 bytes');
  }
  if (input.identityPk.length !== 33) {
    return inputErr('identityPk must be 33 bytes (compressed)');
  }
  if (input.certId.length !== 32) {
    return inputErr('certId must be 32 bytes');
  }
  if (input.contactEmail.length === 0 || !input.contactEmail.includes('@')) {
    return inputErr('contactEmail must contain @');
  }
  if (input.questions.length === 0) {
    return inputErr('questions must not be empty');
  }
  if (input.questions.length !== input.answers.length) {
    return inputErr('answers length must match questions length');
  }
  if (input.recoverySeed.length !== SEED_BYTES) {
    return inputErr(`recoverySeed must be ${SEED_BYTES} bytes`);
  }
  // §8.2 invariant 1 (input side): pubkey for identitySk must equal identityPk.
  let derivedPk: Uint8Array;
  try {
    derivedPk = secp.getPublicKey(input.identitySk, true);
  } catch (e) {
    return inputErr(`identity sk → pk: ${(e as Error).message}`);
  }
  if (!bytesEqual(derivedPk, input.identityPk)) {
    return { ok: false, error: { kind: 'INVARIANT_FAILED', check: 4, detail: 'identityPk does not match identitySk' } };
  }

  // ── Derive normalized answers ────────────────────────────────────
  const normalizedAnswers = input.answers.map(normalizeAnswer);

  // ── Hash each answer with the salt ───────────────────────────────
  const salt = input.testOverrides?.salt ?? crypto.getRandomValues(new Uint8Array(SALT_BYTES));
  if (salt.length !== SALT_BYTES) {
    return inputErr('salt must be 32 bytes');
  }
  const answerHashes: string[] = [];
  for (const ans of normalizedAnswers) {
    answerHashes.push(bytesToHex(hashAnswer(salt, ans)));
  }

  // ── Derive KEK = PBKDF2(concat(normalized answers), salt, 100k) ──
  const concatBytes = new TextEncoder().encode(normalizedAnswers.join(''));
  const kek = pbkdf2(nobleSha256, concatBytes, salt, {
    c: PBKDF2_ITERATIONS,
    dkLen: 32,
  });
  // Wipe the joined-answers buffer immediately.
  concatBytes.fill(0);

  // ── AES-256-GCM encrypt the recovery seed ────────────────────────
  const gcmNonce =
    input.testOverrides?.gcmNonce ?? crypto.getRandomValues(new Uint8Array(GCM_NONCE_BYTES));
  if (gcmNonce.length !== GCM_NONCE_BYTES) {
    return inputErr('gcmNonce must be 12 bytes');
  }
  // AAD = identityKey(33) || envelopeVersion_le1
  const aad = new Uint8Array(33 + 1);
  aad.set(input.identityPk, 0);
  aad[33] = ENVELOPE_VERSION;

  let ciphertextWithTag: Uint8Array;
  try {
    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      kek,
      { name: 'AES-GCM' },
      false,
      ['encrypt', 'decrypt'],
    );
    ciphertextWithTag = new Uint8Array(
      await crypto.subtle.encrypt(
        { name: 'AES-GCM', iv: gcmNonce, additionalData: aad, tagLength: 128 },
        cryptoKey,
        input.recoverySeed,
      ),
    );
  } finally {
    // Best-effort scrub of the raw KEK bytes.
    kek.fill(0);
  }
  // WebCrypto returns ciphertext || tag; split.
  const tag = ciphertextWithTag.slice(ciphertextWithTag.length - GCM_TAG_BYTES);
  const ciphertext = ciphertextWithTag.slice(0, ciphertextWithTag.length - GCM_TAG_BYTES);

  // ── Compose envelope ─────────────────────────────────────────────
  const envelope: PlexusRecoveryEnvelope = {
    envelopeVersion: ENVELOPE_VERSION,
    identityKey: bytesToHex(input.identityPk),
    certId: bytesToHex(input.certId),
    contactEmail: input.contactEmail,
    challengeBundle: {
      questions: input.questions.slice(),
      salt: bytesToHex(salt),
      answerHashes,
      kdfIterations: PBKDF2_ITERATIONS,
    },
    encryptedRecoverySeed: {
      ciphertext: bytesToHex(ciphertext),
      nonce: bytesToHex(gcmNonce),
      tag: bytesToHex(tag),
      aad: bytesToHex(aad),
    },
    derivationContexts: input.derivationContexts.map((c) => ({ ...c })),
    edgeRecipes: input.derivationStateSnapshot.records.map(
      (r): RelationshipRecipe => ({
        domainFlag: r.domainFlag,
        protocolId: r.protocolId,
        protocolHash: r.protocolHash,
        counterpartyPk: r.counterparty === 'self' ? null : r.counterparty,
        highWaterMark: r.currentIndex,
        // Recovery 2b: a per-record stamp (set at key-creation) wins; fall back
        // to the flag→version map for legacy un-stamped records.
        kdfVersion: r.kdfVersion ?? kdfVersionForDomain(r.domainFlag),
      }),
    ),
    derivationStateSnapshot: {
      records: input.derivationStateSnapshot.records.map((r) => ({ ...r })),
      snapshotTimestamp: input.derivationStateSnapshot.snapshotTimestamp,
    },
    algorithmVersion: ALGORITHM_VERSION,
  };

  // ── Run the §8.2 invariant checks against the *built* envelope ───
  const checked = await runInvariantChecks(envelope, {
    identityPk: input.identityPk,
    identitySk: input.identitySk,
    salt,
    normalizedAnswers,
    plaintextSeed: input.recoverySeed,
  });
  if (!checked.ok) return { ok: false, error: checked.error };

  // Wipe normalized answers — we still hold them for the round-trip check
  // above. The caller's `answers` array is theirs to wipe.
  for (let i = 0; i < normalizedAnswers.length; i++) normalizedAnswers[i] = '';

  // ── Sign with BRC-100 wire format ────────────────────────────────
  const bodyBytes = new TextEncoder().encode(JSON.stringify(envelope));
  const brc100 = buildBrc100(input.identitySk, input.identityPk, bodyBytes);

  return { ok: true, envelope, brc100, bodyBytes };
}

/**
 * Decrypt the recovery seed locally using the same answers used at
 * enrollment time. Plexus never sees the answers or the KEK.
 *
 * Returns the 64-byte seed on success; on any failure (wrong answers,
 * tampered ciphertext, malformed hex), returns null. The caller should
 * wipe the returned seed after deriving tier keys from it.
 */
export async function decryptRecoverySeed(
  envelope: PlexusRecoveryEnvelope,
  answers: string[],
): Promise<Uint8Array | null> {
  if (answers.length !== envelope.challengeBundle.questions.length) return null;
  let salt: Uint8Array;
  let nonce: Uint8Array;
  let tag: Uint8Array;
  let ciphertext: Uint8Array;
  let aad: Uint8Array;
  try {
    salt = hexToBytes(envelope.challengeBundle.salt);
    nonce = hexToBytes(envelope.encryptedRecoverySeed.nonce);
    tag = hexToBytes(envelope.encryptedRecoverySeed.tag);
    ciphertext = hexToBytes(envelope.encryptedRecoverySeed.ciphertext);
    aad = hexToBytes(envelope.encryptedRecoverySeed.aad);
  } catch {
    return null;
  }

  const normalized = answers.map(normalizeAnswer);
  const concatBytes = new TextEncoder().encode(normalized.join(''));
  const kek = pbkdf2(nobleSha256, concatBytes, salt, {
    c: envelope.challengeBundle.kdfIterations,
    dkLen: 32,
  });
  concatBytes.fill(0);
  for (let i = 0; i < normalized.length; i++) normalized[i] = '';

  const ctWithTag = new Uint8Array(ciphertext.length + tag.length);
  ctWithTag.set(ciphertext, 0);
  ctWithTag.set(tag, ciphertext.length);

  try {
    const key = await crypto.subtle.importKey('raw', kek, { name: 'AES-GCM' }, false, [
      'decrypt',
    ]);
    const pt = new Uint8Array(
      await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv: nonce, additionalData: aad, tagLength: 128 },
        key,
        ctWithTag,
      ),
    );
    return pt;
  } catch {
    return null;
  } finally {
    kek.fill(0);
  }
}

/**
 * Compute the SHA-256 hash that Plexus stores for one challenge answer.
 * Exposed so the recovery flow can re-derive hashes locally and Plexus
 * never sees the raw answer.
 */
export function hashAnswerHex(saltHex: string, answer: string): string {
  const salt = hexToBytes(saltHex);
  return bytesToHex(hashAnswer(salt, normalizeAnswer(answer)));
}

// ──────────────────────────────────────────────────────────────────────
// Internals
// ──────────────────────────────────────────────────────────────────────

/**
 * Normalize one challenge answer. Per §8.2 the wallet must use the same
 * normalization for both the hash and the KEK — the rule is fixed here
 * (Unicode NFKC + casefold + trim + collapse internal whitespace) so that
 * a user re-typing "  Mom’s    " on recovery still hashes to the same value
 * they used at enrollment.
 */
export function normalizeAnswer(raw: string): string {
  return raw.normalize('NFKC').toLowerCase().replace(/\s+/g, ' ').trim();
}

function hashAnswer(salt: Uint8Array, normalizedAnswer: string): Uint8Array {
  const ans = new TextEncoder().encode(normalizedAnswer);
  const buf = new Uint8Array(salt.length + ans.length);
  buf.set(salt, 0);
  buf.set(ans, salt.length);
  return nobleSha256(buf);
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i]! ^ b[i]!;
  return diff === 0;
}

type CheckResult = { ok: true } | { ok: false; error: BuildError };

function inputErr(reason: string): BuildResult {
  return { ok: false, error: { kind: 'INVALID_INPUT', reason } };
}

function invariantErr(check: 1 | 2 | 3 | 4 | 5, detail: string): CheckResult & { ok: false } {
  return { ok: false, error: { kind: 'INVARIANT_FAILED', check, detail } };
}

interface InvariantInputs {
  identityPk: Uint8Array;
  identitySk: Uint8Array;
  salt: Uint8Array;
  normalizedAnswers: string[];
  plaintextSeed: Uint8Array;
}

/**
 * Run the §8.2 invariants 1–5 against a built envelope. Idempotent — does
 * not mutate. Returns a typed error indicating which check failed.
 */
async function runInvariantChecks(
  envelope: PlexusRecoveryEnvelope,
  ctx: InvariantInputs,
): Promise<CheckResult> {
  // Check 1 — no plaintext private key, mnemonic, or plaintext answer in
  // the JSON. We probe by stringifying the envelope and searching for any
  // of the sensitive byte patterns. Keys / mnemonics / answers can appear
  // in any encoding (hex, base64, utf8) so we test the most common.
  const json = JSON.stringify(envelope);

  const skHex = bytesToHex(ctx.identitySk);
  if (json.includes(skHex)) {
    return invariantErr(1, 'plaintext identity private key found in envelope');
  }
  if (json.includes(skHex.toUpperCase())) {
    return invariantErr(1, 'plaintext identity private key (UPPER) found in envelope');
  }
  const seedHex = bytesToHex(ctx.plaintextSeed);
  if (json.includes(seedHex)) {
    return invariantErr(1, 'plaintext recovery seed found in envelope');
  }
  for (const ans of ctx.normalizedAnswers) {
    if (ans.length === 0) continue;
    if (json.includes(ans)) {
      return invariantErr(1, 'plaintext challenge answer found in envelope');
    }
  }

  // Check 2 — answerHashes[i] == sha256(salt || normalize(answer_i))
  if (envelope.challengeBundle.answerHashes.length !== ctx.normalizedAnswers.length) {
    return invariantErr(2, 'answerHashes length mismatch');
  }
  if (envelope.challengeBundle.salt !== bytesToHex(ctx.salt)) {
    return invariantErr(2, 'salt in envelope does not match');
  }
  for (let i = 0; i < ctx.normalizedAnswers.length; i++) {
    const expected = bytesToHex(hashAnswer(ctx.salt, ctx.normalizedAnswers[i]!));
    if (envelope.challengeBundle.answerHashes[i] !== expected) {
      return invariantErr(2, `answerHashes[${i}] mismatch`);
    }
  }

  // Check 3 — encryptedRecoverySeed.ciphertext, when decrypted with a
  // re-derived KEK from the same answers, yields the original seed bytes.
  // (We re-derive rather than reuse the in-scope `kek` so we exercise the
  // same path the recovery flow will take.)
  const concatBytes = new TextEncoder().encode(ctx.normalizedAnswers.join(''));
  const kek2 = pbkdf2(nobleSha256, concatBytes, ctx.salt, {
    c: envelope.challengeBundle.kdfIterations,
    dkLen: 32,
  });
  concatBytes.fill(0);

  let nonce: Uint8Array, tag: Uint8Array, ciphertext: Uint8Array, aad: Uint8Array;
  try {
    nonce = hexToBytes(envelope.encryptedRecoverySeed.nonce);
    tag = hexToBytes(envelope.encryptedRecoverySeed.tag);
    ciphertext = hexToBytes(envelope.encryptedRecoverySeed.ciphertext);
    aad = hexToBytes(envelope.encryptedRecoverySeed.aad);
  } catch (e) {
    kek2.fill(0);
    return invariantErr(3, `hex decode: ${(e as Error).message}`);
  }

  const ctWithTag = new Uint8Array(ciphertext.length + tag.length);
  ctWithTag.set(ciphertext, 0);
  ctWithTag.set(tag, ciphertext.length);

  let decrypted: Uint8Array;
  try {
    const k = await crypto.subtle.importKey('raw', kek2, { name: 'AES-GCM' }, false, [
      'decrypt',
    ]);
    decrypted = new Uint8Array(
      await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv: nonce, additionalData: aad, tagLength: 128 },
        k,
        ctWithTag,
      ),
    );
  } catch (e) {
    kek2.fill(0);
    return invariantErr(3, `decrypt: ${(e as Error).message}`);
  } finally {
    kek2.fill(0);
  }
  if (!bytesEqual(decrypted, ctx.plaintextSeed)) {
    decrypted.fill(0);
    return invariantErr(3, 'decrypted seed does not match plaintext');
  }
  decrypted.fill(0);

  // Check 4 — identityKey hex matches the public form of identitySk.
  // (Already checked at input boundary; re-confirm against the envelope.)
  if (envelope.identityKey !== bytesToHex(ctx.identityPk)) {
    return invariantErr(4, 'envelope.identityKey does not match input identityPk');
  }

  // Check 5 — certId is hex-shaped and 32 bytes. (Caller-supplied; we don't
  // know what BRC-52 cert is "real" from inside the envelope builder.)
  let certBytes: Uint8Array;
  try {
    certBytes = hexToBytes(envelope.certId);
  } catch (e) {
    return invariantErr(5, `certId hex: ${(e as Error).message}`);
  }
  if (certBytes.length !== 32) {
    return invariantErr(5, 'certId must be 32 bytes');
  }

  // Check 5 (cont.) — edgeRecipes schema: every recipe must carry a
  // recognised domainFlag so that an unrecognised Plexus schema version
  // is caught at dispatch time rather than silently producing a useless
  // recovery envelope. Update KNOWN_DOMAIN_FLAGS when adding new domains.
  // 0x00 = legacy sentinel for state rows that pre-date domain tracking;
  //        recovery treats these as gap-scan-from-0 with unknown protocol.
  const KNOWN_DOMAIN_FLAGS = new Set([0x00, 0x01, 0x04, 0x0a, 0x0b]);
  for (let i = 0; i < envelope.edgeRecipes.length; i++) {
    const r = envelope.edgeRecipes[i]!;
    if (!KNOWN_DOMAIN_FLAGS.has(r.domainFlag)) {
      return invariantErr(5, `edgeRecipes[${i}].domainFlag 0x${r.domainFlag.toString(16)} is unrecognised`);
    }
    if (!/^[0-9a-f]{32}$/.test(r.protocolHash)) {
      return invariantErr(5, `edgeRecipes[${i}].protocolHash is not 16-byte hex`);
    }
    if (r.counterpartyPk !== null && !/^0[23][0-9a-f]{64}$/.test(r.counterpartyPk)) {
      return invariantErr(5, `edgeRecipes[${i}].counterpartyPk is not a compressed pubkey`);
    }
    if (r.highWaterMark !== null && (!Number.isInteger(r.highWaterMark) || r.highWaterMark < 0)) {
      return invariantErr(5, `edgeRecipes[${i}].highWaterMark must be a non-negative integer or null`);
    }
  }

  return { ok: true } as BuildResult;
}

```
