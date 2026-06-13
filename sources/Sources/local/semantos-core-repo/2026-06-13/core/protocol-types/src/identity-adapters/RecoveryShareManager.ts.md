---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/RecoveryShareManager.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.887605+00:00
---

# core/protocol-types/src/identity-adapters/RecoveryShareManager.ts

```ts
/**
 * RecoveryShareManager — Shamir secret sharing for master key backup.
 *
 * Splits a master key into N shares with threshold M using GF(256)
 * polynomial evaluation. Shares are AES-256-GCM encrypted before storage.
 * HMAC integrity tags detect tampering.
 *
 * Storage: `identity/recovery/share/{shareId}`
 * Recovery sessions: `identity/recovery/session/{sessionId}`
 *
 * Cross-references:
 *   Phase 26B: LocalIdentityAdapter.initiateRecovery / submitChallengeAnswers
 */

import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes } from 'crypto';
import type { StorageAdapter } from '../storage';
import { makeIdentityError } from '../identity';

/** A single encrypted recovery share. */
export interface RecoveryShare {
  shareId: string;
  shareIndex: number;
  encryptedData: Uint8Array;
  iv: Uint8Array;
  authTag: Uint8Array;
  integrity: string; // HMAC-SHA-256 hex
}

/** Serializable form for storage. */
interface SerializedShare {
  shareId: string;
  shareIndex: number;
  encryptedData: string; // hex
  iv: string; // hex
  authTag: string; // hex
  integrity: string; // hex
}

/** Recovery session stored in storage. */
export interface RecoverySession {
  sessionId: string;
  email: string;
  challenges: Array<{ id: string; prompt: string; answerHash: string }>;
  threshold: number;
  verified: boolean;
  created: number;
}

const SHARE_PREFIX = 'identity/recovery/share/';
const SESSION_PREFIX = 'identity/recovery/session/';
const HMAC_KEY_LABEL = ':recovery-share-hmac';

export class RecoveryShareManager {
  private storage: StorageAdapter;

  constructor(storageAdapter: StorageAdapter) {
    this.storage = storageAdapter;
  }

  /**
   * Split masterKey into totalShares using Shamir's secret sharing over GF(256).
   * Each share is encrypted with AES-256-GCM and has an HMAC integrity tag.
   *
   * @param masterKey - 32-byte key to split
   * @param threshold - minimum shares required for reconstruction (M)
   * @param totalShares - total shares to generate (N)
   * @param encryptionKey - key used to encrypt shares (derived from recovery challenges in production)
   * @returns Array of encrypted shares (not yet stored)
   */
  generateRecoveryShares(
    masterKey: Uint8Array,
    threshold: number,
    totalShares: number,
    encryptionKey?: Uint8Array,
  ): RecoveryShare[] {
    if (threshold < 2) throw makeIdentityError('SHARE_RECONSTRUCTION_FAILED', 'Threshold must be at least 2', false);
    if (totalShares < threshold) throw makeIdentityError('SHARE_RECONSTRUCTION_FAILED', 'Total shares must be >= threshold', false);
    if (masterKey.length !== 32) throw makeIdentityError('SHARE_RECONSTRUCTION_FAILED', 'Master key must be 32 bytes', false);

    const shares: RecoveryShare[] = [];

    // For each byte position in the master key, create a random polynomial
    // of degree (threshold-1) where the constant term is the secret byte
    const rawShares: Uint8Array[] = [];
    for (let s = 0; s < totalShares; s++) {
      rawShares.push(new Uint8Array(masterKey.length));
    }

    for (let bytePos = 0; bytePos < masterKey.length; bytePos++) {
      // Generate random coefficients for this byte's polynomial
      const coefficients = new Uint8Array(threshold);
      coefficients[0] = masterKey[bytePos]; // constant term = secret byte
      const randCoeffs = randomBytes(threshold - 1);
      for (let i = 1; i < threshold; i++) {
        coefficients[i] = randCoeffs[i - 1];
      }

      // Evaluate polynomial at x = 1, 2, ..., totalShares
      for (let s = 0; s < totalShares; s++) {
        const x = s + 1; // x values are 1-indexed
        rawShares[s][bytePos] = gf256Eval(coefficients, x);
      }
    }

    // Use explicit encryption key or derive from master key
    const ekBytes = encryptionKey ?? masterKey;

    // Encrypt each raw share and add integrity
    for (let s = 0; s < totalShares; s++) {
      const shareIndex = s + 1;
      const shareId = sha256HexStr(`${toHex(ekBytes)}:share:${shareIndex}`).slice(0, 32);

      // Derive per-share encryption key
      const encKey = deriveShareEncKey(ekBytes, shareIndex);
      const iv = randomBytes(12);

      // AES-256-GCM encrypt
      const cipher = createCipheriv('aes-256-gcm', encKey, iv);
      const encrypted = Buffer.concat([cipher.update(rawShares[s]), cipher.final()]);
      const authTag = cipher.getAuthTag();

      // HMAC integrity over all share data
      const integrityData = Buffer.concat([
        Buffer.from(shareId),
        Buffer.from([shareIndex]),
        encrypted,
        iv,
        authTag,
      ]);
      const hmacKey = sha256Bytes(toHex(ekBytes) + HMAC_KEY_LABEL);
      const integrity = createHmac('sha256', hmacKey).update(integrityData).digest('hex');

      shares.push({
        shareId,
        shareIndex,
        encryptedData: new Uint8Array(encrypted),
        iv: new Uint8Array(iv),
        authTag: new Uint8Array(authTag),
        integrity,
      });
    }

    return shares;
  }

  /**
   * Store an encrypted recovery share in storage.
   */
  async storeRecoveryShare(share: RecoveryShare): Promise<void> {
    const serialized: SerializedShare = {
      shareId: share.shareId,
      shareIndex: share.shareIndex,
      encryptedData: toHex(share.encryptedData),
      iv: toHex(share.iv),
      authTag: toHex(share.authTag),
      integrity: share.integrity,
    };
    const key = SHARE_PREFIX + share.shareId;
    const data = new TextEncoder().encode(JSON.stringify(serialized));
    await this.storage.write(key, data);
  }

  /**
   * Load a recovery share from storage.
   */
  async loadRecoveryShare(shareId: string): Promise<RecoveryShare | null> {
    const key = SHARE_PREFIX + shareId;
    const raw = await this.storage.read(key);
    if (!raw) return null;
    const serialized: SerializedShare = JSON.parse(new TextDecoder().decode(raw));
    return {
      shareId: serialized.shareId,
      shareIndex: serialized.shareIndex,
      encryptedData: fromHex(serialized.encryptedData),
      iv: fromHex(serialized.iv),
      authTag: fromHex(serialized.authTag),
      integrity: serialized.integrity,
    };
  }

  /**
   * Reconstruct the master key from M-of-N shares.
   * Verifies integrity, decrypts, then uses Lagrange interpolation over GF(256).
   *
   * @param shares - at least threshold shares
   * @param encryptionKey - the key used to encrypt shares (derived from recovery challenges)
   */
  reconstructMasterKey(shares: RecoveryShare[], encryptionKey: Uint8Array): Uint8Array {
    if (shares.length < 2) {
      throw makeIdentityError('SHARE_RECONSTRUCTION_FAILED', 'Need at least 2 shares for reconstruction', false);
    }

    // Verify integrity of each share
    const hmacKey = sha256Bytes(toHex(encryptionKey) + HMAC_KEY_LABEL);
    for (const share of shares) {
      const integrityData = Buffer.concat([
        Buffer.from(share.shareId),
        Buffer.from([share.shareIndex]),
        Buffer.from(share.encryptedData),
        Buffer.from(share.iv),
        Buffer.from(share.authTag),
      ]);
      const expected = createHmac('sha256', hmacKey).update(integrityData).digest('hex');
      if (expected !== share.integrity) {
        throw makeIdentityError('SHARE_RECONSTRUCTION_FAILED', `Share ${share.shareId} failed integrity check`, false);
      }
    }

    // Decrypt each share
    const decryptedShares: Array<{ x: number; data: Uint8Array }> = [];
    for (const share of shares) {
      const encKey = deriveShareEncKey(encryptionKey, share.shareIndex);
      const decipher = createDecipheriv('aes-256-gcm', encKey, share.iv);
      decipher.setAuthTag(share.authTag);
      const decrypted = Buffer.concat([decipher.update(share.encryptedData), decipher.final()]);
      decryptedShares.push({ x: share.shareIndex, data: new Uint8Array(decrypted) });
    }

    // Lagrange interpolation over GF(256) for each byte position
    const keyLength = decryptedShares[0].data.length;
    const result = new Uint8Array(keyLength);

    for (let bytePos = 0; bytePos < keyLength; bytePos++) {
      const points: Array<{ x: number; y: number }> = decryptedShares.map(s => ({
        x: s.x,
        y: s.data[bytePos],
      }));
      result[bytePos] = gf256Interpolate(points, 0); // evaluate at x=0 to get secret
    }

    return result;
  }

  /**
   * Verify the HMAC integrity of a single share.
   */
  verifyShareIntegrity(share: RecoveryShare, encryptionKey: Uint8Array): boolean {
    const hmacKey = sha256Bytes(toHex(encryptionKey) + HMAC_KEY_LABEL);
    const integrityData = Buffer.concat([
      Buffer.from(share.shareId),
      Buffer.from([share.shareIndex]),
      Buffer.from(share.encryptedData),
      Buffer.from(share.iv),
      Buffer.from(share.authTag),
    ]);
    const expected = createHmac('sha256', hmacKey).update(integrityData).digest('hex');
    return expected === share.integrity;
  }

  /**
   * Rotate recovery shares: generate new ones, delete old, store new.
   */
  async rotateRecoveryShares(
    masterKey: Uint8Array,
    threshold: number,
    totalShares: number,
    oldShareIds: string[],
  ): Promise<RecoveryShare[]> {
    // Delete old shares
    for (const shareId of oldShareIds) {
      await this.storage.delete(SHARE_PREFIX + shareId);
    }

    // Generate and store new shares
    const newShares = this.generateRecoveryShares(masterKey, threshold, totalShares);
    for (const share of newShares) {
      await this.storeRecoveryShare(share);
    }
    return newShares;
  }

  /**
   * Store a recovery session.
   */
  async storeSession(session: RecoverySession): Promise<void> {
    const key = SESSION_PREFIX + session.sessionId;
    const data = new TextEncoder().encode(JSON.stringify(session));
    await this.storage.write(key, data);
  }

  /**
   * Load a recovery session.
   */
  async loadSession(sessionId: string): Promise<RecoverySession | null> {
    const key = SESSION_PREFIX + sessionId;
    const raw = await this.storage.read(key);
    if (!raw) return null;
    return JSON.parse(new TextDecoder().decode(raw)) as RecoverySession;
  }
}

// ── GF(256) arithmetic (irreducible polynomial: x^8 + x^4 + x^3 + x + 1 = 0x11B) ──

const GF256_EXP = new Uint8Array(512);
const GF256_LOG = new Uint8Array(256);

// Build lookup tables using generator 3 (standard for AES GF(256) with poly 0x11b)
(function initGF256Tables() {
  let x = 1;
  for (let i = 0; i < 255; i++) {
    GF256_EXP[i] = x;
    GF256_LOG[x] = i;
    // Multiply by generator 3: x*3 = x*2 XOR x
    let x2 = x << 1;
    if (x2 >= 256) x2 ^= 0x11b;
    x = (x2 ^ x) & 0xff;
  }
  // Duplicate for convenience (avoid modular reduction in mul)
  for (let i = 255; i < 512; i++) {
    GF256_EXP[i] = GF256_EXP[i - 255];
  }
})();

function gf256Mul(a: number, b: number): number {
  if (a === 0 || b === 0) return 0;
  return GF256_EXP[GF256_LOG[a] + GF256_LOG[b]];
}

function gf256Inv(a: number): number {
  if (a === 0) throw new Error('Cannot invert zero in GF(256)');
  return GF256_EXP[255 - GF256_LOG[a]];
}

/** Evaluate polynomial (coefficients[0] = constant) at x in GF(256). */
function gf256Eval(coefficients: Uint8Array, x: number): number {
  let result = 0;
  let xPower = 1;
  for (let i = 0; i < coefficients.length; i++) {
    result ^= gf256Mul(coefficients[i], xPower);
    xPower = gf256Mul(xPower, x);
  }
  return result;
}

/** Lagrange interpolation at targetX given points in GF(256). */
function gf256Interpolate(points: Array<{ x: number; y: number }>, targetX: number): number {
  let result = 0;
  for (let i = 0; i < points.length; i++) {
    let basis = points[i].y;
    for (let j = 0; j < points.length; j++) {
      if (i === j) continue;
      // basis *= (targetX - points[j].x) / (points[i].x - points[j].x)
      const num = targetX ^ points[j].x; // subtraction in GF(256) = XOR
      const den = points[i].x ^ points[j].x;
      basis = gf256Mul(basis, gf256Mul(num, gf256Inv(den)));
    }
    result ^= basis;
  }
  return result;
}

// ── Utility functions ──

function sha256Bytes(input: string): Uint8Array {
  const hash = createHash('sha256').update(input).digest();
  return new Uint8Array(hash.buffer, hash.byteOffset, hash.byteLength);
}

function sha256HexStr(input: string): string {
  return createHash('sha256').update(input).digest('hex');
}

function deriveShareEncKey(masterKey: Uint8Array, shareIndex: number): Uint8Array {
  const input = `${toHex(masterKey)}:enc:${shareIndex}`;
  return sha256Bytes(input);
}

function toHex(data: Uint8Array): string {
  return Array.from(data).map(b => b.toString(16).padStart(2, '0')).join('');
}

function fromHex(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  return bytes;
}

```
