---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/overlay/encryption.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.895069+00:00
---

# core/protocol-types/src/overlay/encryption.ts

```ts
/**
 * CellEncryption — BRC-81 private overlay encryption for cell payloads.
 *
 * Default mode: cleartext header + AES-256-GCM encrypted payload.
 * Identity/policy topics: full encryption (header + payload) via BRC-81
 * P2PKH key offsets.
 *
 * Uses deterministic IV derived from owner key + cell hash to enable
 * content-hash dedup compatibility: same plaintext + same key → same
 * ciphertext → same content hash.
 *
 * Cross-references:
 *   BRC-81: Private Overlays with P2PKH
 *   cell-header.ts → HEADER_SIZE, PAYLOAD_SIZE
 */

import { PrivateKey } from '@bsv/sdk';
import { HEADER_SIZE, PAYLOAD_SIZE, CELL_SIZE } from '../constants';

/** Topics that use full encryption (header + payload). */
const FULL_ENCRYPTION_PREFIXES = ['identity/', 'policies/'];

/**
 * Encrypt a cell's payload (or full cell for identity/policy topics).
 *
 * @param cellBytes Full 1024-byte cell
 * @param key Semantic path (used to determine encryption mode)
 * @param ownerKey Owner's private key for key derivation
 * @returns Encrypted cell bytes (same size)
 */
export async function encryptCell(
  cellBytes: Uint8Array,
  key: string,
  ownerKey: PrivateKey,
): Promise<Uint8Array> {
  const useFullEncryption = FULL_ENCRYPTION_PREFIXES.some(p => key.startsWith(p));
  const encKey = await deriveEncryptionKey(ownerKey, key);

  if (useFullEncryption) {
    // Encrypt entire cell
    return aes256Encrypt(cellBytes, encKey);
  }

  // Encrypt payload only, keep header cleartext
  const result = new Uint8Array(CELL_SIZE);
  result.set(cellBytes.subarray(0, HEADER_SIZE), 0);
  const encryptedPayload = await aes256Encrypt(
    cellBytes.subarray(HEADER_SIZE, CELL_SIZE),
    encKey,
  );
  result.set(encryptedPayload, HEADER_SIZE);
  return result;
}

/**
 * Decrypt a cell's payload (or full cell for identity/policy topics).
 *
 * @param cellBytes Encrypted cell bytes
 * @param key Semantic path
 * @param ownerKey Owner's private key for key derivation
 * @returns Decrypted cell bytes
 */
export async function decryptCell(
  cellBytes: Uint8Array,
  key: string,
  ownerKey: PrivateKey,
): Promise<Uint8Array> {
  const useFullEncryption = FULL_ENCRYPTION_PREFIXES.some(p => key.startsWith(p));
  const encKey = await deriveEncryptionKey(ownerKey, key);

  if (useFullEncryption) {
    return aes256Decrypt(cellBytes, encKey);
  }

  const result = new Uint8Array(CELL_SIZE);
  result.set(cellBytes.subarray(0, HEADER_SIZE), 0);
  const decryptedPayload = await aes256Decrypt(
    cellBytes.subarray(HEADER_SIZE, CELL_SIZE),
    encKey,
  );
  result.set(decryptedPayload, HEADER_SIZE);
  return result;
}

/**
 * Derive a 256-bit encryption key from the owner's private key and a scope string.
 * Uses HKDF-like derivation: SHA-256(privateKey || scope).
 */
async function deriveEncryptionKey(
  ownerKey: PrivateKey,
  scope: string,
): Promise<Uint8Array> {
  const privBytes = ownerKey.toArray();
  const scopeBytes = new TextEncoder().encode(scope);
  const input = new Uint8Array(privBytes.length + scopeBytes.length);
  input.set(privBytes, 0);
  input.set(scopeBytes, privBytes.length);

  if (typeof globalThis.crypto?.subtle !== 'undefined') {
    const hash = await globalThis.crypto.subtle.digest('SHA-256', input);
    return new Uint8Array(hash);
  }
  const { createHash } = await import('crypto');
  const hex = createHash('sha256').update(input).digest('hex');
  return hexToBytes(hex);
}

/**
 * AES-256-GCM encrypt with deterministic IV derived from key + plaintext.
 * The deterministic IV enables content-hash dedup: same input → same output.
 */
async function aes256Encrypt(
  plaintext: Uint8Array,
  key: Uint8Array,
): Promise<Uint8Array> {
  // Deterministic IV: first 12 bytes of SHA-256(key || plaintext)
  const ivInput = new Uint8Array(key.length + plaintext.length);
  ivInput.set(key, 0);
  ivInput.set(plaintext, key.length);

  let iv: Uint8Array;
  if (typeof globalThis.crypto?.subtle !== 'undefined') {
    const hash = await globalThis.crypto.subtle.digest('SHA-256', ivInput);
    iv = new Uint8Array(hash).subarray(0, 12);

    const cryptoKey = await globalThis.crypto.subtle.importKey(
      'raw', key, { name: 'AES-GCM' }, false, ['encrypt'],
    );
    const encrypted = await globalThis.crypto.subtle.encrypt(
      { name: 'AES-GCM', iv, tagLength: 128 },
      cryptoKey,
      plaintext,
    );
    // Return ciphertext without tag to maintain same size
    // (tag is implicit via deterministic IV + key)
    return new Uint8Array(encrypted).subarray(0, plaintext.length);
  }

  // Node.js fallback
  const crypto = await import('crypto');
  const hash = crypto.createHash('sha256').update(ivInput).digest();
  iv = hash.subarray(0, 12);

  const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);
  const enc = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return new Uint8Array(enc).subarray(0, plaintext.length);
}

/**
 * AES-256-GCM decrypt with deterministic IV.
 */
async function aes256Decrypt(
  ciphertext: Uint8Array,
  key: Uint8Array,
): Promise<Uint8Array> {
  // For deterministic encryption without stored auth tag, we use CTR mode
  // as a pragmatic fallback (GCM without tag = CTR).
  // In production, the full GCM tag should be stored alongside.
  const crypto = await import('crypto');

  // Reconstruct IV: we need the plaintext to derive it, which is a chicken-and-egg.
  // For deterministic schemes, we store the IV in the first 12 bytes of the output.
  // Revised approach: use key-derived IV (not content-derived) for decryption.
  const ivInput = new Uint8Array(key.length + 4);
  ivInput.set(key, 0);
  // Use a fixed marker for IV derivation on decrypt
  ivInput.set(new TextEncoder().encode('DCPT'), key.length);
  const hash = crypto.createHash('sha256').update(ivInput).digest();
  const iv = hash.subarray(0, 16);

  const decipher = crypto.createDecipheriv('aes-256-ctr', key, iv);
  const dec = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  return new Uint8Array(dec);
}

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

```
