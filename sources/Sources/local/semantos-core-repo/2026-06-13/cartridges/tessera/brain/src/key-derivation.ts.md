---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/src/key-derivation.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.639952+00:00
---

# cartridges/tessera/brain/src/key-derivation.ts

```ts
/**
 * Tessera key-derivation — first consumer of the substrate-side L11
 * port (`IdentityAdapter.deriveSegmentPublicKey`).
 *
 * Reference:
 *   docs/canon/cw-lift-matrix.yml L11 (substrate-side adapter port).
 *   docs/prd/TESSERA-CARTRIDGE.md §0.1 #2 (greenfield discipline).
 *   tests/gates/tessera-adapter-consumption.test.ts (the gate this
 *     module passes by going through @semantos/protocol-types only).
 *
 * What this does:
 *   Given an operator-root pubkey + a tessera cell id/type, derives a
 *   per-cell owner pubkey deterministically — without registering it
 *   as a hat / cert, and without the cartridge importing @bsv/sdk or
 *   @plexus/vendor-sdk (both forbidden by the consumption gate).
 *
 *   The derivation flows entirely through the substrate seam:
 *     1. tessera builds a deterministic segment string (e.g.
 *        `"tessera/bottle/<bottleId>/owner"`)
 *     2. tessera calls `identityAdapter.deriveDomainSegmentPublicKey(
 *           operatorRootPubKeyHex, TESSERA_DERIVATION_DOMAIN_FLAG, segment)`
 *     3. the IdentityAdapter implementation runs L11.5
 *        (`child_pub = parent_pub + SHA-256(u32_be(domainFlag) ‖ segment) * G`)
 *        and returns the 66-char hex child pubkey
 *
 *   Cartridges that hold the matching parent PRIVATE key (operators
 *   running through LocalIdentityAdapter) can independently verify
 *   any derivation via `deriveSegment(parentPriv, segment).toPublicKey()`
 *   — byte-equal by the L11 priv↔pub symmetry property.
 *
 * Cell-type segment scheme:
 *   tessera/<cellType>/<cellId>/<role>
 *
 * The `<role>` partition makes it possible for ONE cell to have
 * MULTIPLE derived pubkeys (owner, handler, witness) under the same
 * operator root — each role hashes to a different leaf.
 *
 * What's NOT in scope here:
 *   - Registered hats / certs — tessera caps + cert mints are
 *     orthogonal; this module is for non-registered per-cell keys
 *   - Brain-side Zig equivalent — when tessera's Zig surface needs
 *     the same derivation, the brain-side IdentityAdapter equivalent
 *     would grow a deriveSegmentPublicKey method too (separate lift)
 *   - Private-key side derivation — only the operator (holder of the
 *     operator root private key) can derive the matching child private
 *     keys. Greenfield cartridges only need the pubkey side
 */

import type { IdentityAdapter } from '@semantos/protocol-types';
import type { TesseraCellType } from './store-adapter.js';
import { TESSERA_DOMAIN_FLAG_RANGE } from './capabilities.js';

/**
 * L11.5 (kdf-v3) — every tessera per-cell key derivation binds the
 * cartridge-wide tessera domain flag (the 0x000104xx page base). The
 * segment string `<cellType>/<cellId>/<role>` separates derivations
 * WITHIN the tessera domain, so one flag suffices (one-flag-per-domain).
 * Binding it means a tessera-derived key is scoped to the tessera domain
 * and can't be replayed against a cell flagged for a different domain.
 * See docs/canon/domainflag-tag-unification.md.
 */
export const TESSERA_DERIVATION_DOMAIN_FLAG: number = TESSERA_DOMAIN_FLAG_RANGE.low;

/**
 * Predefined per-cell-type roles. Adding a new role here is the
 * cartridge-side way to introduce a new derived-key axis. Roles are
 * canonical strings — changing one invalidates every pubkey derived
 * under it (treat as wire-format bump).
 *
 * Bottle: owner (producer's signing key for transfers), retailer (the
 *   current retailer's signing key once distributed).
 * Care-event: handler (who recorded the event), witness (signature
 *   chain).
 * Pallet/case/shipment: owner (current custodian).
 * Scan-event: scanner (the consumer-app device that produced the scan).
 * Tamper-event: reporter (whoever logged the tamper claim).
 * Tasting-note: author.
 */
export type TesseraRole =
  | 'owner'
  | 'retailer'
  | 'handler'
  | 'witness'
  | 'scanner'
  | 'reporter'
  | 'author';

/**
 * Compose the canonical segment string for a (cellType, cellId, role).
 * Deterministic per the components — same triple always produces the
 * same segment.
 *
 *   tessera/<cellType>/<cellId>/<role>
 */
export function tesseraDerivationSegment(
  cellType: TesseraCellType,
  cellId: string,
  role: TesseraRole,
): string {
  assertNonEmpty('cellId', cellId);
  return `${cellType}/${cellId}/${role}`;
}

/**
 * A bound key-derivation helper. Holds the operator-root pubkey + the
 * IdentityAdapter; exposes one-call methods for the common (cellType,
 * role) pairs tessera uses. The cartridge constructs this once at
 * boot (after receiving the operator root via the standard identity
 * provisioning flow) and reuses it for all per-cell derivations.
 */
export class TesseraKeyDerivation {
  constructor(
    private readonly identityAdapter: IdentityAdapter,
    private readonly operatorRootPubKeyHex: string,
  ) {
    assertNonEmpty('operatorRootPubKeyHex', operatorRootPubKeyHex);
    if (!/^[0-9a-f]{66}$/.test(operatorRootPubKeyHex)) {
      throw new Error(
        `TesseraKeyDerivation: operatorRootPubKeyHex must be 66-char lowercase hex SEC1 compressed`,
      );
    }
  }

  /**
   * Derive an owner pubkey for any tessera cell. The owner segment is
   * the canonical `tessera/<cellType>/<cellId>/owner` triple.
   */
  async deriveOwner(
    cellType: TesseraCellType,
    cellId: string,
  ): Promise<{ pubKeyHex: string; segment: string }> {
    return this.derive(cellType, cellId, 'owner');
  }

  /**
   * Derive a handler pubkey for a care-event / tamper-event cell.
   */
  async deriveHandler(
    cellType: TesseraCellType,
    cellId: string,
  ): Promise<{ pubKeyHex: string; segment: string }> {
    return this.derive(cellType, cellId, 'handler');
  }

  /**
   * Derive a scanner pubkey for a scan-event cell. Conventionally
   * bound to the device-id of the consumer-app that produced the scan;
   * cellId here is the scan-event cell id.
   */
  async deriveScanner(
    cellType: TesseraCellType,
    cellId: string,
  ): Promise<{ pubKeyHex: string; segment: string }> {
    return this.derive(cellType, cellId, 'scanner');
  }

  /**
   * Generic — for roles that don't yet have a typed helper (e.g.
   * future roles, reporter / witness / author).
   */
  async deriveForRole(
    cellType: TesseraCellType,
    cellId: string,
    role: TesseraRole,
  ): Promise<{ pubKeyHex: string; segment: string }> {
    return this.derive(cellType, cellId, role);
  }

  /** Internal: route every method through one substrate call. */
  private async derive(
    cellType: TesseraCellType,
    cellId: string,
    role: TesseraRole,
  ): Promise<{ pubKeyHex: string; segment: string }> {
    const segment = tesseraDerivationSegment(cellType, cellId, role);
    // L11.5: bind the tessera domain flag into the derivation tweak (kdf-v3).
    const result = await this.identityAdapter.deriveDomainSegmentPublicKey(
      this.operatorRootPubKeyHex,
      TESSERA_DERIVATION_DOMAIN_FLAG,
      segment,
    );
    return { pubKeyHex: result.childPubKeyHex, segment };
  }
}

// ── Internal helpers ──────────────────────────────────────────────

function assertNonEmpty(field: string, value: string): void {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`tessera key-derivation: ${field} must be non-empty string`);
  }
}

```
