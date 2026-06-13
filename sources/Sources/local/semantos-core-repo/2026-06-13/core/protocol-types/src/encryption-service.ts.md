---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/encryption-service.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.847025+00:00
---

# core/protocol-types/src/encryption-service.ts

```ts
/**
 * EncryptionService — AES-256-GCM message encryption for Phase 2 conversations.
 *
 * Builds on KeyDerivationService for shared secret derivation.
 * Provides encrypt/decrypt for messages and signature operations.
 *
 * Encryption tiers:
 *   SELF:       AES-256-GCM with local device key (no exchange)
 *   INDIVIDUAL: AES-256-GCM with BRC-85/86 ECDH shared secret
 *   GROUP:      AES-256-GCM with ZONE-derived key
 *   AI_AGENT:   Optional, local key
 *
 * @module @semantos/protocol-types/encryption-service
 */

import * as crypto from 'node:crypto';

const ALGORITHM = 'aes-256-gcm' as const;
const IV_LENGTH = 12; // 96 bits for GCM
const KEY_LENGTH = 32; // 256 bits
const TAG_LENGTH = 16; // 128 bits

export interface EncryptedPayload {
  /** Base64-encoded ciphertext. */
  ciphertext: string;
  /** Base64-encoded initialization vector. */
  iv: string;
  /** Base64-encoded authentication tag. */
  tag: string;
}

export class EncryptionService {
  /**
   * Derive a per-message encryption key from a shared secret and message context.
   *
   * Uses HKDF (HMAC-based Key Derivation Function) with SHA-256.
   * The messageId provides per-message uniqueness (salt).
   */
  static deriveMessageKey(sharedSecret: string, messageId: string): Buffer {
    const secretBytes = Buffer.from(sharedSecret, 'hex');
    const salt = Buffer.from(messageId, 'utf-8');
    const info = Buffer.from('semantos-messaging-v1', 'utf-8');

    // HKDF extract + expand
    const prk = crypto.createHmac('sha256', salt).update(secretBytes).digest();
    const okm = crypto.createHmac('sha256', prk)
      .update(Buffer.concat([info, Buffer.from([1])]))
      .digest();

    return okm.subarray(0, KEY_LENGTH);
  }

  /**
   * Encrypt plaintext with AES-256-GCM.
   *
   * @param plaintext — UTF-8 message content
   * @param key — 32-byte encryption key (from deriveMessageKey)
   * @returns EncryptedPayload with Base64-encoded ciphertext, IV, and tag
   */
  static encrypt(plaintext: string, key: Buffer): EncryptedPayload {
    const iv = crypto.randomBytes(IV_LENGTH);
    const cipher = crypto.createCipheriv(ALGORITHM, key, iv, { authTagLength: TAG_LENGTH });

    const encrypted = Buffer.concat([
      cipher.update(plaintext, 'utf-8'),
      cipher.final(),
    ]);

    const tag = cipher.getAuthTag();

    return {
      ciphertext: encrypted.toString('base64'),
      iv: iv.toString('base64'),
      tag: tag.toString('base64'),
    };
  }

  /**
   * Decrypt AES-256-GCM ciphertext.
   *
   * @param payload — EncryptedPayload with Base64-encoded fields
   * @param key — 32-byte decryption key (same key used for encryption)
   * @returns Decrypted UTF-8 plaintext
   * @throws Error if authentication tag verification fails
   */
  static decrypt(payload: EncryptedPayload, key: Buffer): string {
    const ciphertext = Buffer.from(payload.ciphertext, 'base64');
    const iv = Buffer.from(payload.iv, 'base64');
    const tag = Buffer.from(payload.tag, 'base64');

    const decipher = crypto.createDecipheriv(ALGORITHM, key, iv, { authTagLength: TAG_LENGTH });
    decipher.setAuthTag(tag);

    const decrypted = Buffer.concat([
      decipher.update(ciphertext),
      decipher.final(),
    ]);

    return decrypted.toString('utf-8');
  }

  /**
   * Sign message content using HMAC-SHA-256.
   *
   * @param privateKey — Hex-encoded signing key
   * @param messageContent — UTF-8 message content to sign
   * @returns Hex-encoded signature
   */
  static signMessage(privateKey: string, messageContent: string): string {
    const keyBytes = Buffer.from(privateKey, 'hex');
    return crypto.createHmac('sha256', keyBytes)
      .update(messageContent, 'utf-8')
      .digest('hex');
  }

  /**
   * Verify a message signature.
   *
   * Uses constant-time comparison to prevent timing attacks.
   */
  static verifySignature(privateKey: string, messageContent: string, signature: string): boolean {
    const expected = EncryptionService.signMessage(privateKey, messageContent);
    if (expected.length !== signature.length) return false;
    const a = Buffer.from(expected, 'hex');
    const b = Buffer.from(signature, 'hex');
    return crypto.timingSafeEqual(a, b);
  }

  /**
   * Generate a random local device key for SELF/AI_AGENT context encryption.
   */
  static generateLocalKey(): string {
    return crypto.randomBytes(KEY_LENGTH).toString('hex');
  }

  /**
   * Derive a shared secret between two parties using their cert IDs.
   *
   * This is a simplified version matching KeyDerivationService.deriveSharedSecret().
   * In production, this would use actual ECDH key agreement (BRC-85/86).
   */
  static deriveSharedSecret(localCertId: string, remoteCertId: string, context: string = 'messaging-v1'): string {
    return crypto.createHash('sha256')
      .update(`${localCertId}:${remoteCertId}:${context}`)
      .digest('hex');
  }
}

```
