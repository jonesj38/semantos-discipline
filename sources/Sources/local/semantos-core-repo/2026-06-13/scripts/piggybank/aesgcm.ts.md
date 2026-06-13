---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/piggybank/aesgcm.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.385684+00:00
---

# scripts/piggybank/aesgcm.ts

```ts
/**
 * AES-256-GCM helpers for the provisioning channel.
 *
 * The shared AES key is the ECDH output from computeSharedSecret (64-char
 * lowercase hex). GCM nonce + auth tag are returned separately so the
 * ProvisioningPayload wire format stays readable.
 */

import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';

export interface SealedPayload {
  /** Ciphertext, hex-encoded. */
  ciphertext: string;
  /** 12-byte GCM nonce, hex-encoded. */
  nonce: string;
  /** 16-byte GCM auth tag, hex-encoded. */
  authTag: string;
}

export function seal(sharedSecretHex: string, plaintext: string): SealedPayload {
  const key = Buffer.from(sharedSecretHex, 'hex');
  if (key.length !== 32) {
    throw new Error(`AES-GCM key must be 32 bytes; got ${key.length}`);
  }
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  const enc = Buffer.concat([cipher.update(plaintext, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return {
    ciphertext: enc.toString('hex'),
    nonce: nonce.toString('hex'),
    authTag: tag.toString('hex'),
  };
}

export function open(sharedSecretHex: string, sealed: SealedPayload): string {
  const key = Buffer.from(sharedSecretHex, 'hex');
  if (key.length !== 32) {
    throw new Error(`AES-GCM key must be 32 bytes; got ${key.length}`);
  }
  const decipher = createDecipheriv(
    'aes-256-gcm',
    key,
    Buffer.from(sealed.nonce, 'hex'),
  );
  decipher.setAuthTag(Buffer.from(sealed.authTag, 'hex'));
  const dec = Buffer.concat([
    decipher.update(Buffer.from(sealed.ciphertext, 'hex')),
    decipher.final(),
  ]);
  return dec.toString('utf8');
}

```
