---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/scripts/piggybank/pin-wrap.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.384908+00:00
---

# scripts/piggybank/pin-wrap.ts

```ts
/**
 * PIN-wrap: AES-256-GCM wrapping of the device private key with a
 * PIN-derived key. Matches the format defined in
 * `apps/piggybank/src/device.ts` (`DeviceProfile.encryptedPrivateKey`).
 *
 * Key = PBKDF2(PIN, salt, 10000 iterations, 32 bytes, SHA-256)
 *
 * We never carry a real PIN in the dry-run — the provisioning protocol
 * defers PIN capture to the on-device button flow. This module exists so
 * the DeviceProfile produced by the dry-run has the exact shape the
 * firmware expects.
 */

import { pbkdf2Sync, randomBytes, createCipheriv, createDecipheriv } from 'node:crypto';

export interface PinWrap {
  encryptedPrivateKey: string; // hex
  pinSalt: string;             // hex, 16 bytes
  pinNonce: string;            // hex, 12 bytes
  pinAuthTag: string;          // hex, 16 bytes
}

const PBKDF2_ITERATIONS = 10_000;

export function wrapPrivateKeyWithPin(privKeyHex: string, pin: string): PinWrap {
  const salt = randomBytes(16);
  const key = pbkdf2Sync(pin, salt, PBKDF2_ITERATIONS, 32, 'sha256');
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  const plaintext = Buffer.from(privKeyHex, 'hex');
  const enc = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  const tag = cipher.getAuthTag();
  return {
    encryptedPrivateKey: enc.toString('hex'),
    pinSalt: salt.toString('hex'),
    pinNonce: nonce.toString('hex'),
    pinAuthTag: tag.toString('hex'),
  };
}

export function unwrapPrivateKeyWithPin(wrap: PinWrap, pin: string): string {
  const key = pbkdf2Sync(
    pin,
    Buffer.from(wrap.pinSalt, 'hex'),
    PBKDF2_ITERATIONS,
    32,
    'sha256',
  );
  const decipher = createDecipheriv(
    'aes-256-gcm',
    key,
    Buffer.from(wrap.pinNonce, 'hex'),
  );
  decipher.setAuthTag(Buffer.from(wrap.pinAuthTag, 'hex'));
  const dec = Buffer.concat([
    decipher.update(Buffer.from(wrap.encryptedPrivateKey, 'hex')),
    decipher.final(),
  ]);
  return dec.toString('hex');
}

```
