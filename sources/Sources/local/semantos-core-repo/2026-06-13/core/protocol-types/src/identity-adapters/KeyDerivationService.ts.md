---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/KeyDerivationService.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.888179+00:00
---

# core/protocol-types/src/identity-adapters/KeyDerivationService.ts

```ts
/**
 * KeyDerivationService — BRC-42 deterministic key derivation for local identity.
 *
 * All derivations are deterministic: same inputs always produce the same output.
 * Uses HMAC-SHA-512 for child key derivation and SHA-256 for hashing.
 * No external dependencies — Node.js crypto module only.
 *
 * Cross-references:
 *   Phase 26B: LocalIdentityAdapter uses this for all key operations
 *   BRC-42: BIP-32-style hierarchical key derivation
 */

import { createHash, createHmac } from 'crypto';

const LOCAL_IDENTITY_SALT = ':local-identity';

export class KeyDerivationService {
  /**
   * Generate a deterministic root key from an email address.
   * Same email always produces the same 32-byte key.
   */
  generateRootKey(email: string): Uint8Array {
    return sha256Bytes(email + LOCAL_IDENTITY_SALT);
  }

  /**
   * Generate a deterministic certId from a root key.
   * Returns `cert:` prefixed hex string (first 32 hex chars).
   */
  generateCertId(key: Uint8Array): string {
    const hash = sha256Hex(key);
    return 'cert:' + hash.slice(0, 32);
  }

  /**
   * Derive a child key deterministically from parent key + index + domainFlag.
   * Uses HMAC-SHA-512; returns left 32 bytes as child private key.
   * Same inputs always produce the same output.
   */
  deriveChildKey(parentKey: Uint8Array, index: number, domainFlag: number): Uint8Array {
    const message = new Uint8Array(8);
    const view = new DataView(message.buffer);
    view.setUint32(0, index, false); // big-endian
    view.setUint32(4, domainFlag, false);

    const hmac = createHmac('sha512', parentKey);
    hmac.update(message);
    const digest = hmac.digest();
    // Return left 32 bytes
    return new Uint8Array(digest.buffer, digest.byteOffset, 32);
  }

  /**
   * Generate a deterministic public key (PEM format) from a private key.
   * Structurally valid PEM, derived from key hash — not cryptographically real
   * (same pattern as StubIdentityAdapter for interface compatibility).
   */
  generatePublicKey(privateKey: Uint8Array): string {
    const hash = sha256Hex(privateKey);
    const b64 = hexToBase64(hash);
    return `-----BEGIN PUBLIC KEY-----\n${b64}\n-----END PUBLIC KEY-----`;
  }

  /**
   * Build a BRC-42-style derivation path string.
   */
  derivePath(parentCertId: string, indices: number[], domainFlag: number): string {
    const indexPath = indices.map(i => `${i}'`).join('/');
    return `m/${domainFlag}'/${indexPath}`;
  }

  /**
   * Derive a shared secret between two cert IDs with a context string.
   * Deterministic: SHA-256(localCertId + remoteCertId + context).
   */
  deriveSharedSecret(localCertId: string, remoteCertId: string, context: string): string {
    const input = localCertId + ':' + remoteCertId + ':' + context;
    return sha256HexStr(input);
  }

  /**
   * Rotate a domain key using a rotation index.
   * Deterministic: SHA-256(certId + domainFlag + rotationIndex).
   */
  rotateDomainKey(certId: string, domainFlag: number, rotationIndex: number): Uint8Array {
    const input = `${certId}:${domainFlag}:${rotationIndex}`;
    return sha256Bytes(input);
  }

  /**
   * Sign data with a private key using HMAC-SHA-256.
   * Returns the signature as a hex string.
   */
  sign(privateKey: Uint8Array, data: Uint8Array): string {
    const hmac = createHmac('sha256', privateKey);
    hmac.update(data);
    return hmac.digest('hex');
  }

  /**
   * Verify an HMAC-SHA-256 signature.
   */
  verify(privateKey: Uint8Array, data: Uint8Array, signature: string): boolean {
    const expected = this.sign(privateKey, data);
    // Constant-time comparison
    if (expected.length !== signature.length) return false;
    let mismatch = 0;
    for (let i = 0; i < expected.length; i++) {
      mismatch |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
    }
    return mismatch === 0;
  }
}

// ── Utility functions ──

function sha256Bytes(input: string | Uint8Array): Uint8Array {
  const hash = createHash('sha256').update(input).digest();
  return new Uint8Array(hash.buffer, hash.byteOffset, hash.byteLength);
}

function sha256Hex(input: Uint8Array): string {
  return createHash('sha256').update(input).digest('hex');
}

function sha256HexStr(input: string): string {
  return createHash('sha256').update(input).digest('hex');
}

function hexToBase64(hex: string): string {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  // Use Buffer in Node.js / Bun
  return Buffer.from(bytes).toString('base64');
}

```
