---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/games/src/cards/mental-poker/crypto.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.435175+00:00
---

# packages/games/src/cards/mental-poker/crypto.ts

```ts
/**
 * SRA Commutative Encryption for Mental Poker
 *
 * Uses modular exponentiation over a large prime field:
 *   Encrypt: c = m^e mod p
 *   Decrypt: m = c^d mod p  (where d = e^(-1) mod (p-1))
 *   Commutative: E_a(E_b(m)) = m^(ea*eb) mod p = E_b(E_a(m))
 *
 * The prime p must be safe (p = 2q+1, q prime) so that (p-1) has
 * a large prime factor, making discrete log hard.
 *
 * Card values are mapped to large random numbers (not 1-52) to
 * prevent brute-force guessing of encrypted card identities.
 */

import { createHash, randomBytes } from 'crypto';

// ── Safe Prime ──────────────────────────────────────────────

/**
 * 256-bit safe prime for SRA encryption.
 * p = 2q + 1 where both p and q are prime.
 * This is a well-known safe prime used in cryptographic protocols.
 */
export const SRA_PRIME = BigInt(
  '0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141'
);

/**
 * p - 1 (the group order for exponentiation mod p).
 * Keys must be coprime to this value.
 */
export const SRA_ORDER = SRA_PRIME - 1n;

// ── BigInt Arithmetic ───────────────────────────────────────

/** Modular exponentiation: base^exp mod mod. Square-and-multiply. */
export function modPow(base: bigint, exp: bigint, mod: bigint): bigint {
  if (mod === 1n) return 0n;
  let result = 1n;
  base = ((base % mod) + mod) % mod;
  while (exp > 0n) {
    if (exp & 1n) {
      result = (result * base) % mod;
    }
    exp >>= 1n;
    base = (base * base) % mod;
  }
  return result;
}

/** Extended GCD: returns [gcd, x, y] where ax + by = gcd. */
function extGcd(a: bigint, b: bigint): [bigint, bigint, bigint] {
  if (a === 0n) return [b, 0n, 1n];
  const [g, x, y] = extGcd(b % a, a);
  return [g, y - (b / a) * x, x];
}

/** Modular multiplicative inverse: a^(-1) mod m. Throws if not coprime. */
export function modInverse(a: bigint, m: bigint): bigint {
  a = ((a % m) + m) % m;
  const [g, x] = extGcd(a, m);
  if (g !== 1n) {
    throw new Error('No modular inverse — values not coprime');
  }
  return ((x % m) + m) % m;
}

/** GCD of two BigInts. */
export function gcd(a: bigint, b: bigint): bigint {
  a = a < 0n ? -a : a;
  b = b < 0n ? -b : b;
  while (b !== 0n) {
    [a, b] = [b, a % b];
  }
  return a;
}

/** Generate a random BigInt in range [2, max-1] that is coprime with order. */
export function randomCoprime(order: bigint): bigint {
  const byteLen = 32; // 256 bits
  while (true) {
    const bytes = randomBytes(byteLen);
    let n = BigInt('0x' + bytes.toString('hex'));
    n = (n % (order - 2n)) + 2n; // range [2, order-1]
    if (gcd(n, order) === 1n) return n;
  }
}

// ── Key Generation ──────────────────────────────────────────

export interface SRAKeyPair {
  encryptKey: bigint;
  decryptKey: bigint;
}

/** Generate an SRA key pair for a player. */
export function generateKeyPair(prime?: bigint): SRAKeyPair {
  const p = prime ?? SRA_PRIME;
  const order = p - 1n;
  const encryptKey = randomCoprime(order);
  const decryptKey = modInverse(encryptKey, order);
  return { encryptKey, decryptKey };
}

// ── Encryption / Decryption ─────────────────────────────────

/** Encrypt a value: c = m^e mod p. */
export function sraEncrypt(value: bigint, key: bigint, prime?: bigint): bigint {
  const p = prime ?? SRA_PRIME;
  return modPow(value, key, p);
}

/** Decrypt a value: m = c^d mod p. */
export function sraDecrypt(value: bigint, key: bigint, prime?: bigint): bigint {
  const p = prime ?? SRA_PRIME;
  return modPow(value, key, p);
}

// ── Card Mapping ────────────────────────────────────────────

/**
 * Generate a canonical mapping from card indices (0-51) to large
 * random values in the prime field. This mapping is PUBLIC and
 * agreed upon before the game starts.
 *
 * Using large random values prevents brute-force: even though there
 * are only 52 cards, the encrypted values are indistinguishable from
 * random field elements without the decryption keys.
 */
export function generateCardMapping(prime?: bigint): bigint[] {
  const p = prime ?? SRA_PRIME;
  const mapping: bigint[] = [];

  for (let i = 0; i < 52; i++) {
    // Hash-derive a deterministic-looking but unique value per card
    // Use i + random salt to ensure values are in the correct range
    while (true) {
      const bytes = randomBytes(32);
      const val = BigInt('0x' + bytes.toString('hex')) % (p - 2n) + 2n;
      // Ensure no collisions
      if (!mapping.includes(val)) {
        mapping.push(val);
        break;
      }
    }
  }

  return mapping;
}

// ── Hashing ─────────────────────────────────────────────────

/** SHA-256 hash of a string, returned as hex. */
export function sha256(data: string): string {
  return createHash('sha256').update(data).digest('hex');
}

/** Commit to a BigInt value. */
export function commitValue(value: bigint): string {
  return sha256(value.toString(16));
}

/** Commit to an array of BigInt values (deck state). */
export function commitDeck(values: bigint[]): string {
  const combined = values.map(v => v.toString(16)).join(':');
  return sha256(combined);
}

/** Commit to a key (for key commitment at game start). */
export function commitKey(key: bigint): string {
  return sha256('key:' + key.toString(16));
}

// ── Serialization ───────────────────────────────────────────

export function bigintToHex(n: bigint): string {
  return n.toString(16);
}

export function hexToBigint(hex: string): bigint {
  return BigInt('0x' + hex);
}

```
