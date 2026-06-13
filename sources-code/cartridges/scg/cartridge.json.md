---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/scg/cartridge.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.412885+00:00
---

# cartridges/scg/cartridge.json

```json
{
  "id": "scg",
  "name": "Semantos Conversation Graph",
  "version": "0.1.0",
  "role": "infra",
  "description": "Substrate cartridge: typed conversation-graph entities and capabilities. Declares the two canonical object types (scg.cell, scg.relation) and the relation mint/revoke verbs that gate edge creation across the substrate. Projection demos (Reddit/Discourse/stream) ship as separate dependent cartridges per D-SCG-reddit-projection / D-SCG-stream-projection. PWA-part intentionally empty — SCG is substrate-shaped (see project memory: semantos_streams_shell_native).",
  "taxonomyPath": "brain/src/grammar.ts",
  "capabilitiesPath": "brain/src/grammar.ts",
  "provides": [
    "@semantos/scg#scgGrammar",
    "@semantos/scg#scgManifest"
  ],
  "consumes": {
    "StorageAdapter": "required — for sem_objects (cells + relations live here; relation payloads in jsonb today, schema-registered under SCG_RELATION = 0x0001FE03)",
    "IdentityAdapter": "deferred — RM-005 will pair a real BRC-52 LexiconAuthority cert + grammar signature with this manifest. Tests use StubAuthorityVerifier."
  },
  "wssSubprotocols": [],
  "verbs": [
    {
      "name": "scg.relation.mint",
      "capability_required": "cap.scg.relation.mint",
      "description": "Create a new scg.relation row (typed edge between two scg.cells). Authority required.",
      "capability_flag": "0x0001000c"
    },
    {
      "name": "scg.relation.revoke",
      "capability_required": "cap.scg.relation.revoke",
      "description": "Soft-delete (revoke via patch) an existing scg.relation row. Authority optional in the grammar; gated at the cartridge boundary.",
      "capability_flag": "0x0001000d"
    }
  ],
  "objectTypes": [
    {
      "typePath": "scg.cell",
      "primaryAnchor": true,
      "displayName": "SCG Cell",
      "description": "A substrate cell participating in the conversation graph. Lives in sem_objects; identified by 32B id; participates in typed edges via scg.relation rows.",
      "linearity": "AFFINE",
      "phases": ["active"],
      "initialPhase": "active",
      "payloadSchema": {},
      "capabilities": {}
    },
    {
      "typePath": "scg.relation",
      "displayName": "SCG Relation",
      "description": "Typed edge between two scg.cells. Payload = { kind, sourceId, targetId, amount?, currency?, txAnchor?, attestation? }. Canonical relation kinds per SCG §3.1 + RM-010/060/080 additions: REPLIES_TO, SUPPORTS, DISPUTES, SUPERSEDES, CITES, FORKS, REQUESTS_ACTION, FULFILLS, PAYS, ATTESTS, GRANTS_ACCESS, APPROVES, ESCROW_LOCKS, ESCROW_RELEASES, MERGES, SUBSCRIBES_TO. Byte-level schema lives at core/plexus-schema-registry/src/schemas/scg-relation.ts under domainFlag 0x0001FE03.",
      "linearity": "LINEAR",
      "phases": ["active", "revoked"],
      "initialPhase": "active",
      "payloadSchema": {
        "kind": {
          "type": "string",
          "tier": "core",
          "description": "Relation kind name (REPLIES_TO, SUPPORTS, DISPUTES, …). Encoded byte-wise via SCG_RELATION_KIND_BYTES."
        },
        "sourceId": {
          "type": "string",
          "tier": "core",
          "description": "32B hex-encoded sem_objects.id of the source cell."
        },
        "targetId": {
          "type": "string",
          "tier": "core",
          "description": "32B hex-encoded sem_objects.id of the target cell."
        },
        "amount": {
          "type": "number",
          "tier": "operator-extensible",
          "description": "Smallest-unit amount for money-bearing kinds (PAYS, ESCROW_LOCKS, ESCROW_RELEASES); 0 otherwise."
        },
        "currency": {
          "type": "string",
          "tier": "operator-extensible",
          "description": "4-byte ASCII currency tag for money-bearing kinds (e.g. 'sats', 'USD '); empty otherwise."
        },
        "txAnchor": {
          "type": "string",
          "tier": "operator-extensible",
          "description": "32B on-chain anchor; absent for unanchored relations."
        },
        "attestation": {
          "type": "string",
          "tier": "operator-extensible",
          "description": "First 4 bytes of the attestation digest (full attestation in jsonb)."
        }
      },
      "capabilities": {
        "mint": "cap.scg.relation.mint",
        "revoke": "cap.scg.relation.revoke"
      }
    }
  ],
  "conversationHooks": "auto-emit-reply-relation",
  "_notes": {
    "manifest_format": "Phase 36A ExtensionManifest (cartridge.json) shape per core/protocol-types/src/extension-manifest.ts. role=infra ⇒ exempt from FSM flows/prompts/state-machines; SCG is substrate-shaped, not operational.",
    "role_choice": "role=infra mirrors wallet-headers + bsv-anchor-bundle (substrate-providing cartridges). Discussed in D-SCG-cartridge-shape — SCG is not 'experience' (no flutter package, no PWA part); 'infra' is the closest existing value. If a future 'substrate' role value is introduced, this should switch.",
    "verb_capability_flags": "capability_flag fields carry the numeric ClientDomainFlags values (RELATION_MINT=0x0001000c, RELATION_REVOKE=0x0001000d) per core/plexus-contracts/src/domain-flags.ts. Verb names follow the deliverables.yml convention (scg.relation.mint / scg.relation.revoke). The capability_required string IDs are cartridge-local (cap.scg.relation.*); cap.scg.* page allocation TBD per the broader capability-string canonicalisation (see oddjobz/brain/src/capabilities.ts).",
    "objectTypes_derivation": "Both object types are derived views over the grammar declared in brain/src/grammar.ts (scgGrammar.entityMappings). The payloadSchema for scg.relation mirrors core/plexus-schema-registry/src/schemas/scg-relation.ts. scg.cell carries an empty payloadSchema because the grammar treats it as a pure substrate-cell handle — its concrete payload depends on the projecting application (Reddit post, Discourse topic, oddjobz job, etc.).",
    "pwa_empty": "No 'experience' block — SCG ships no PWA part. Projection cartridges (D-SCG-reddit-projection, D-SCG-stream-projection) are independent cartridges that consume @semantos/scg + @semantos/scg-relations.",
    "package_name": "The npm-package name remains @semantos/scg (preserved across the packages/scg → cartridges/scg/brain relocation). The package's `repository.directory` now points to cartridges/scg/brain.",
    "deliverable": "D-SCG-cartridge-shape — see docs/canon/deliverables.yml."
  }
}

```
