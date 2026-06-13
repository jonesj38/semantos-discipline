---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-legacy-cli/src/kek-from-passphrase.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.697982+00:00
---

# archive/apps-legacy-cli/src/kek-from-passphrase.ts

```ts
/**
 * Passphrase-derived KEK for the Phase 1 CLI.
 *
 * Reference: docs/design/WALLET-LEGACY-INGEST.md §3 LI1 — credentials
 * encrypted at rest under operator's wallet KEK. Phase 1 stands in a
 * passphrase-derived KEK because the wallet bootstrap on rbs isn't
 * wired yet; Phase 2 swaps this for `brain broker.host_derive_kek`.
 *
 * Bit-identical envelope parameters to cartridges/wallet-headers/brain/src/host.ts
 * `deriveKek(0, factor)`:
 *   - PBKDF2-HMAC-SHA256
 *   - 4096 iterations
 *   - 16-byte salt = "semantos:tier=" || tier_le16   (tier=0)
 *   - 32-byte derived key, AES-GCM
 *
 * The unlocked key is cached for the duration of the CLI process. The
 * passphrase itself is read once via `read-password` (Bun-native TTY
 * helper); never persisted.
 */

import { pbkdf2Sync } from 'node:crypto';

const SLOT_KEK_BYTES = 32;
const PBKDF2_ITERS = 4096;
const TIER_LEGACY_INGEST = 0; // tier-0 KEK; wallet-browser uses tier-0 for the same envelope

let cached: CryptoKey | null = null;

/**
 * Derive a tier-0 KEK from a passphrase. Bit-identical to
 * cartridges/wallet-headers/brain/src/host.ts deriveKek so an operator who later
 * migrates from CLI to wallet-browser can decrypt the same files.
 */
export async function deriveKekFromPassphrase(passphrase: string): Promise<CryptoKey> {
  const factor = new TextEncoder().encode(passphrase);
  const salt = new Uint8Array(16);
  const prefix = new TextEncoder().encode('semantos:tier=');
  salt.set(prefix, 0);
  new DataView(salt.buffer).setUint16(prefix.length, TIER_LEGACY_INGEST, true);

  // Use node:crypto's pbkdf2Sync for parity with @noble/hashes' pbkdf2 +
  // HmacSha256 (which is what the wallet-browser uses). Output bytes
  // are the same.
  const raw = pbkdf2Sync(factor, salt, PBKDF2_ITERS, SLOT_KEK_BYTES, 'sha256');
  // crypto.subtle is the same WebCrypto interface available in Bun and
  // in the wallet-browser; the resulting CryptoKey is interchangeable.
  return crypto.subtle.importKey('raw', raw, { name: 'AES-GCM' }, false, [
    'encrypt',
    'decrypt',
  ]);
}

/**
 * Get the cached KEK, prompting for a passphrase on first call.
 * The KEK provider passed into legacy-ingest stores wraps this:
 *   `kekProvider: () => unlockedKek()`
 *
 * On the first call this prints a passphrase prompt to stderr and
 * reads from stdin (TTY). Subsequent calls within the same process
 * return the cached key without re-prompting.
 */
export async function unlockedKek(): Promise<CryptoKey> {
  if (cached) return cached;
  const passphrase = await readPassphraseFromTty();
  cached = await deriveKekFromPassphrase(passphrase);
  return cached;
}

/**
 * Test seam — let tests inject a passphrase directly without going
 * through the TTY.
 */
export async function unlockWithPassphrase(passphrase: string): Promise<CryptoKey> {
  cached = await deriveKekFromPassphrase(passphrase);
  return cached;
}

/** Drop the cached KEK. Tests + REPL `lock` verb. */
export function lockKek(): void {
  cached = null;
}

async function readPassphraseFromTty(): Promise<string> {
  const envPassphrase = process.env.SEMANTOS_LEGACY_PASSPHRASE;
  if (envPassphrase) return envPassphrase;

  // No TTY → fail loudly. The operator must run the CLI interactively
  // for the passphrase. Phase 2 swaps this for the Semantos Brain broker which
  // holds the KEK across requests.
  if (!process.stdin.isTTY) {
    throw new Error(
      'legacy-cli: passphrase required but no TTY available. ' +
      'Run interactively, or set SEMANTOS_LEGACY_PASSPHRASE for non-interactive use ' +
      '(only safe in restricted-access environments — never in shared shell history).',
    );
  }

  process.stderr.write('Wallet passphrase: ');
  // Disable echo while reading.
  const stdin = process.stdin;
  stdin.setRawMode?.(true);
  let buffer = '';
  return new Promise<string>((resolve, reject) => {
    const onData = (chunk: Buffer): void => {
      const ch = chunk.toString('utf8');
      for (const c of ch) {
        const code = c.charCodeAt(0);
        if (code === 13 || code === 10) { // \r or \n
          stdin.setRawMode?.(false);
          stdin.removeListener('data', onData);
          process.stderr.write('\n');
          resolve(buffer);
          return;
        }
        if (code === 3) { // ctrl-c
          stdin.setRawMode?.(false);
          stdin.removeListener('data', onData);
          process.stderr.write('\n');
          reject(new Error('passphrase entry cancelled'));
          return;
        }
        if (code === 127 || code === 8) { // backspace
          buffer = buffer.slice(0, -1);
          continue;
        }
        buffer += c;
      }
    };
    stdin.on('data', onData);
    stdin.resume();
  });
}

```
