---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/scg-relations/src/capability.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.817575+00:00
---

# core/scg-relations/src/capability.ts

```ts
/**
 * Capability-port binding for SCG relation operations (RM-022).
 *
 * Provides a thunk factory that plugs into `createRelation`'s
 * `capabilityCheck` slot, consulting the `capabilityPort` from
 * `@semantos/identity-ports` to verify the active identity holds the
 * `RELATION_MINT` (or `RELATION_REVOKE`) capability.
 *
 * The numeric domain-flag values live in
 * `@plexus/contracts::ClientDomainFlags`:
 *   - `RELATION_MINT`   = 0x0001000c
 *   - `RELATION_REVOKE` = 0x0001000d
 *
 * Per Plexus §7 / `identityPort.CapabilityPort`, capability presentation
 * happens via a string capability-id keyed off a BRC-108 UTXO. The
 * numeric flag is the off-chain registry identifier; the on-chain UTXO
 * carries a stable capability-id string. By default we use the
 * canonical ids below; consumers can override.
 */
import { capabilityPort } from '@semantos/identity-ports';
import { ClientDomainFlags } from '@plexus/contracts';

export const RELATION_MINT_FLAG = ClientDomainFlags.RELATION_MINT;
export const RELATION_REVOKE_FLAG = ClientDomainFlags.RELATION_REVOKE;

/** Canonical capability-ids paired with the numeric flags above. */
export const CAPABILITY_ID_RELATION_MINT = 'cap.scg.relation_mint';
export const CAPABILITY_ID_RELATION_REVOKE = 'cap.scg.relation_revoke';

/**
 * Error thrown when a capability check refuses creation. `createRelation`
 * propagates this to callers.
 */
export class RelationCapabilityError extends Error {
  readonly code = 'RELATION_CAPABILITY_DENIED' as const;
  readonly certId: string;
  readonly capabilityId: string;
  readonly reason: string | undefined;
  constructor(input: {
    certId: string;
    capabilityId: string;
    reason?: string;
  }) {
    super(
      `Capability denied: certId=${input.certId} capability=${input.capabilityId}${
        input.reason ? ` (${input.reason})` : ''
      }`,
    );
    this.name = 'RelationCapabilityError';
    this.certId = input.certId;
    this.capabilityId = input.capabilityId;
    this.reason = input.reason;
  }
}

/**
 * Build a `capabilityCheck` thunk for `createRelation`. Returns a
 * function that, when invoked, consults the bound `capabilityPort` and
 * throws `RelationCapabilityError` on refusal.
 *
 * Defaults to checking `CAPABILITY_ID_RELATION_MINT`; pass a custom
 * `capabilityId` to check a different on-chain capability (e.g. a
 * delegated subset of `RELATION_MINT`).
 */
export function requireRelationMint(
  certId: string,
  capabilityId: string = CAPABILITY_ID_RELATION_MINT,
): () => void {
  return () => {
    const result = capabilityPort.get().present(certId, capabilityId);
    if (!result.valid) {
      throw new RelationCapabilityError({
        certId,
        capabilityId,
        ...(result.reason !== undefined ? { reason: result.reason } : {}),
      });
    }
  };
}

/**
 * Symmetric helper for revocation (soft-delete patches against an
 * `scg.relation` row). Used by future patch-authoring code paths.
 */
export function requireRelationRevoke(
  certId: string,
  capabilityId: string = CAPABILITY_ID_RELATION_REVOKE,
): () => void {
  return () => {
    const result = capabilityPort.get().present(certId, capabilityId);
    if (!result.valid) {
      throw new RelationCapabilityError({
        certId,
        capabilityId,
        ...(result.reason !== undefined ? { reason: result.reason } : {}),
      });
    }
  };
}

```
