---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/scg/brain/src/grammar.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.556869+00:00
---

# cartridges/scg/brain/src/grammar.ts

```ts
/**
 * SCG extension grammar (RM-021).
 *
 * Declares the entity mappings + capability requirements for the
 * conversation-graph layer. Two entity kinds:
 *   - `scg.cell` — a substrate cell participating in the graph
 *   - `scg.relation` — a typed edge between two cells
 *
 * Capabilities `RELATION_MINT` / `RELATION_REVOKE` (RM-004 / RM-022)
 * gate creation and soft-deletion of relation rows. Production
 * signing identity comes from RM-005 (deferred — no real RBS cert
 * yet); tests use `StubAuthorityVerifier` from
 * `@semantos/semantos-sir::authority`.
 *
 * The shape mirrors `ExtensionGrammar` from
 * `@semantos/protocol-types/extension-grammar` but is declared
 * structurally here so this extension stays free of a runtime dep on
 * protocol-types' full grammar interface. Any object satisfying the
 * shape registers cleanly with the extraction pipeline.
 */

import { ClientDomainFlags } from '@plexus/contracts';

/** Structural shape of an SCG entity mapping (mirrors
 *  `protocol-types::EntityMapping` minimally). */
export interface ScgEntityMapping {
  readonly entityId: 'scg.cell' | 'scg.relation';
  readonly displayName: string;
  readonly description: string;
}

/** Structural shape of a capability requirement (mirrors
 *  `protocol-types::CapabilityRequirement`). */
export interface ScgCapabilityRequirement {
  /** Numeric flag from `ClientDomainFlags`. */
  readonly capability: number;
  readonly name: 'RELATION_MINT' | 'RELATION_REVOKE';
  readonly reason: string;
  readonly required: boolean;
}

export interface ScgGrammar {
  readonly grammarId: 'com.semantos.scg';
  readonly grammarVersion: string;
  readonly displayName: string;
  readonly description: string;
  readonly entityMappings: ReadonlyArray<ScgEntityMapping>;
  readonly capabilities: ReadonlyArray<ScgCapabilityRequirement>;
  readonly taxonomyNamespace: 'scg';
}

export const scgGrammar: ScgGrammar = {
  grammarId: 'com.semantos.scg',
  grammarVersion: '0.1.0',
  displayName: 'Semantos Conversation Graph',
  description:
    'Typed conversation-graph substrate. Entities: scg.cell (a node), scg.relation (a typed edge). Twelve canonical relation kinds (REPLIES_TO, SUPPORTS, DISPUTES, …) per SCG §3.1.',
  entityMappings: [
    {
      entityId: 'scg.cell',
      displayName: 'SCG Cell',
      description: 'Substrate cell participating in the conversation graph.',
    },
    {
      entityId: 'scg.relation',
      displayName: 'SCG Relation',
      description:
        'Typed edge between two SCG cells. Payload = { kind, sourceId, targetId, attestation? }.',
    },
  ],
  capabilities: [
    {
      capability: ClientDomainFlags.RELATION_MINT,
      name: 'RELATION_MINT',
      reason:
        'Authority to create a new scg.relation row. Gates `createRelation` in @semantos/scg-relations.',
      required: true,
    },
    {
      capability: ClientDomainFlags.RELATION_REVOKE,
      name: 'RELATION_REVOKE',
      reason:
        'Authority to soft-delete (revoke via patch) an existing scg.relation row.',
      required: false,
    },
  ],
  taxonomyNamespace: 'scg',
};

```
