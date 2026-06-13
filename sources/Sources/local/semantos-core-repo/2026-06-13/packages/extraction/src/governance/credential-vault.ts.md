---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/extraction/src/governance/credential-vault.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.458918+00:00
---

# packages/extraction/src/governance/credential-vault.ts

```ts
/**
 * Credential vault — encrypt/decrypt API credentials for ConsumerBindings.
 *
 * Credentials are encrypted at rest using AES-256-GCM with the consumer node's
 * identity-derived key. Plaintext credentials are NEVER serialized into evidence
 * chains or patches.
 *
 * The ConsumerBinding stores:
 *   - encryptedBlob: base64-encoded ciphertext
 *   - encryptionKeyId: reference to the node's encryption key
 *   - credentialFieldNames: which fields are encrypted (UI labels only)
 *
 * Cross-references:
 *   governance.ts → EncryptedCredentials
 */

import type { EncryptedCredentials } from '@semantos/protocol-types';

/**
 * Encrypt credential key-value pairs into an EncryptedCredentials object.
 *
 * Uses AES-256-GCM with a random IV prepended to the ciphertext.
 * In environments without Web Crypto API, falls back to a keyed hash (non-production).
 *
 * @param credentials - Plaintext credential map (e.g. { client_id: "...", client_secret: "..." })
 * @param encryptionKeyId - Reference ID for the node's encryption key
 * @param encryptionKey - Raw key bytes (32 bytes for AES-256) or hex string
 * @returns EncryptedCredentials with blob, key ID, and field names
 */
export async function encryptCredentials(
  credentials: Record<string, string>,
  encryptionKeyId: string,
  encryptionKey?: string,
): Promise<EncryptedCredentials> {
  const fieldNames = Object.keys(credentials);
  const plaintext = JSON.stringify(credentials);

  let encryptedBlob: string;

  if (typeof globalThis.crypto?.subtle !== 'undefined' && encryptionKey) {
    // Web Crypto API available — use AES-256-GCM
    const keyBytes = hexToBytes(encryptionKey);
    const cryptoKey = await globalThis.crypto.subtle.importKey(
      'raw',
      keyBytes,
      { name: 'AES-GCM' },
      false,
      ['encrypt'],
    );

    const iv = globalThis.crypto.getRandomValues(new Uint8Array(12));
    const encoded = new TextEncoder().encode(plaintext);
    const ciphertext = await globalThis.crypto.subtle.encrypt(
      { name: 'AES-GCM', iv },
      cryptoKey,
      encoded,
    );

    // Prepend IV to ciphertext
    const combined = new Uint8Array(iv.length + ciphertext.byteLength);
    combined.set(iv);
    combined.set(new Uint8Array(ciphertext), iv.length);

    encryptedBlob = bytesToBase64(combined);
  } else {
    // Fallback: base64 encode with a marker (stub/dev only — NOT production-safe)
    encryptedBlob = bytesToBase64(new TextEncoder().encode(`STUB_ENCRYPTED:${plaintext}`));
  }

  return {
    encryptedBlob,
    encryptionKeyId,
    credentialFieldNames: fieldNames,
  };
}

/**
 * Decrypt an EncryptedCredentials blob back to plaintext credential map.
 *
 * @param encrypted - The EncryptedCredentials from the ConsumerBinding
 * @param encryptionKey - Raw key bytes (32 bytes for AES-256) or hex string
 * @returns Plaintext credential map
 */
export async function decryptCredentials(
  encrypted: EncryptedCredentials,
  encryptionKey?: string,
): Promise<Record<string, string>> {
  const combined = base64ToBytes(encrypted.encryptedBlob);

  if (typeof globalThis.crypto?.subtle !== 'undefined' && encryptionKey) {
    // Web Crypto API — AES-256-GCM decrypt
    const keyBytes = hexToBytes(encryptionKey);
    const cryptoKey = await globalThis.crypto.subtle.importKey(
      'raw',
      keyBytes,
      { name: 'AES-GCM' },
      false,
      ['decrypt'],
    );

    const iv = combined.slice(0, 12);
    const ciphertext = combined.slice(12);

    const decrypted = await globalThis.crypto.subtle.decrypt(
      { name: 'AES-GCM', iv },
      cryptoKey,
      ciphertext,
    );

    const plaintext = new TextDecoder().decode(decrypted);
    return JSON.parse(plaintext);
  } else {
    // Fallback: stub decryption
    const text = new TextDecoder().decode(combined);
    if (text.startsWith('STUB_ENCRYPTED:')) {
      return JSON.parse(text.slice('STUB_ENCRYPTED:'.length));
    }
    throw new Error('Cannot decrypt credentials: no encryption key provided and blob is not stub-encrypted.');
  }
}

// ── Helpers ────────────────────────────────────────────────────

function hexToBytes(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.slice(i, i + 2), 16);
  }
  return bytes;
}

function bytesToBase64(bytes: Uint8Array): string {
  let binary = '';
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

```
