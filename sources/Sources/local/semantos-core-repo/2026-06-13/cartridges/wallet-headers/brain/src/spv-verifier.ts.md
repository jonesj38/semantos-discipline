---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/wallet-headers/brain/src/spv-verifier.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.651928+00:00
---

# cartridges/wallet-headers/brain/src/spv-verifier.ts

```ts
/**
 * HeadersSpvVerifier — the concrete `SpvVerifier` the wallet/headers
 * **infra cartridge** `provides` (Wave Canonical-Cartridge CC1, the
 * keystone).
 *
 * Ref: docs/design/CANONICAL-CARTRIDGE-MODEL.md (role: infra);
 * docs/canon/commissions/wave-canonical-cartridge.md CC1.
 *
 * This retires the documented SpvContext stub-debt across SW2 /
 * cartridge-license / NL-1: those all reach for a real `SpvVerifier`
 * (core/protocol-types `ports/spv-port`) but had only stubs / a
 * fail-closed default. The wallet/headers cartridge owns the real one:
 *
 *   BEEF parse (local `beef-codec`) → compute the BUMP merkle root →
 *   accept iff that root is trusted by the **headers** half (a
 *   PoW-verified header source, injected as `isTrustedRoot`).
 *
 * Dependency direction stays clean: core/protocol-types defines the
 * PORT; this cartridge provides the IMPL. The headers source is
 * injected (not a hard dep) so the verifier is unit-testable and the
 * cartridge composes the wallet half + the headers half via the
 * single `isTrustedRoot` seam.
 *
 * Fail-closed at every branch (unparseable / txid-absent / no BUMP /
 * untrusted root ⇒ `false`) — never assume verified.
 */

import type { SpvVerifier } from '../../../core/protocol-types/src/ports/spv-port';
import {
  parseBeef,
  parseBump,
  computeMerkleRoot,
  hexFromBytes,
  bytesFromHex,
  reverseTxid,
  type ParsedBump,
} from './beef-codec';

/** The headers half: returns true iff `rootHexInternal` is a merkle
 *  root of a PoW-verified block this node trusts (e.g. backed by
 *  `header-spv.ts` `LocalChainTracker`). Root bytes are in internal
 *  order — `hexFromBytes(computeMerkleRoot(...))`. */
export type TrustedRootPredicate = (rootHexInternal: string) => boolean;

export class HeadersSpvVerifier implements SpvVerifier {
  constructor(private readonly isTrustedRoot: TrustedRootPredicate) {}

  /** Verify a BEEF tx's merkle proof: the txid's BUMP root must be a
   *  trusted PoW-verified root. `txid` is accepted in either display
   *  or internal hex orientation. */
  async verifyBeef(beef: string | number[], txid: string): Promise<boolean> {
    try {
      const bytes =
        typeof beef === 'string' ? bytesFromHex(beef) : Uint8Array.from(beef);
      const parsed = parseBeef(bytes);
      const want = txid.toLowerCase();
      const tx = parsed.txs.find((t) => {
        const internal = hexFromBytes(t.txid).toLowerCase();
        const display = hexFromBytes(reverseTxid(t.txid)).toLowerCase();
        return internal === want || display === want;
      });
      if (!tx || tx.bumpIndex === null) return false;
      const bump = parsed.bumps[tx.bumpIndex];
      if (!bump) return false;
      const root = computeMerkleRoot(bump, tx.txid);
      return this.isTrustedRoot(hexFromBytes(root));
    } catch {
      return false; // fail-closed
    }
  }

  /** Verify a standalone BUMP proof for `txid` (internal-order hex). */
  async verifyBump(bump: string, txid: string): Promise<boolean> {
    try {
      const buf = bytesFromHex(bump);
      let parsed: ParsedBump;
      [parsed] = parseBump(buf, 0);
      const root = computeMerkleRoot(parsed, bytesFromHex(txid));
      return this.isTrustedRoot(hexFromBytes(root));
    } catch {
      return false; // fail-closed
    }
  }
}

```
