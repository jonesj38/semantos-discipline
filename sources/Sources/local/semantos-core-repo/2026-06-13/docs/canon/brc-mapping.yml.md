---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/brc-mapping.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.629706+00:00
---

# docs/canon/brc-mapping.yml

```yml
# BRC suite mapping. Schema: docs/canon/README.md#brc-mappingyml.
#
# Stage: scaffold → seeded. Imports the BRC mapping from the existing Plexus
# Technical Requirements §References + Plexus Client Requirements (BRC-42 /
# BRC-52 / BRC-53 / BRC-69 / BRC-85 / BRC-100 / BRC-103 / BRC-108) plus the
# standard Bitcoin Script BRCs.
#
# Derivation hierarchy (CW Lift L11, docs/prd/CW-LIFT-ROADMAP.md §2.2):
# the foundation primitive is Craig Wright's EP3259724B1 segment derivation
# (`child = parent + H(segment) mod n`). BRC-42 is NOT a separate primitive —
# it is the BILATERAL specialisation (`segment = HMAC(ECDH-shared, data)`).
# Node/DAG derivation is the UNILATERAL specialisation and uses the base
# primitive directly. See `derivation_hierarchy` below.

- id: EP3259724B1
  name: Segment key derivation (foundation primitive)
  domain: derivation
  status: implemented
  upstream_url: https://patents.google.com/patent/EP3259724B1
  semantos_paths:
    - core/plexus-vendor-sdk/src/crypto.ts        # deriveSegment / deriveScalar (+ pub-side)
  textbook_chapter: 4
  spec_section: "Tech Reqs §10 (Derivation Domain)"
  notes: |
    Craig Wright base primitive: child = parent + SHA-256(segment) mod n, with
    a pubkey-side mirror (child_pub = parent_pub + SHA-256(segment)*G). Both
    BRC-42 (bilateral) and node/DAG derivation (unilateral) compose off this.
    Promoted matrix Tier 2 → Tier 1 on 2026-06-02. KAT: __tests__/derive-segment.test.ts.

- id: BRC-42
  name: Client-side key derivation (bilateral specialisation of EP3259724B1)
  domain: identity
  status: implemented
  upstream_url: https://brc.dev/brc-0042
  semantos_paths:
    - core/plexus-vendor-sdk/src/crypto.ts        # deriveChildKey (delegates to @bsv/sdk deriveChild)
    - cartridges/wallet-headers/brain/src/ecdh42.ts
    - core/cell-engine/src/bca.zig
  textbook_chapter: 4
  spec_section: "v0.5 §4.1; Tech Reqs §12 (Edge Domain)"
  notes: |
    The bilateral case of EP3259724B1: segment = HMAC(ECDH-shared-secret, data).
    Load-bearing for the EDGE domain (two-party relationships, Flag 0x01). NOT
    the primitive for node/DAG derivation, which is unilateral — see
    derivation_hierarchy. Byte-equal composition asserted in derive-segment.test.ts.
    Root-seed reconstruction also uses PBKDF2 (100k) per Identity Domain §9.

- id: BRC-52
  name: Identity certificates (DAG nodes)
  domain: identity
  status: implemented
  upstream_url: https://brc.dev/brc-0052
  semantos_paths:
    - core/plexus-vendor-sdk/src/crypto.ts        # computeCertId, buildRootPreimage, buildChildPreimage
    - core/plexus-contracts/src/graph.ts          # PlexusNode
  textbook_chapter: 4
  spec_section: "Tech Reqs §9 (Identity), §15 (Identity Record)"
  notes: |
    cert_id = SHA-256 of canonical preimage. Only the 32-byte cert_id hash is
    stored server-side; variable certificate body stays client-side.

- id: BRC-69
  name: Edge backup recipes (key linkage revelation)
  domain: recovery
  status: partial
  upstream_url: https://brc.dev/brc-0069
  semantos_paths:
    - core/plexus-contracts/src/graph.ts          # PlexusEdge
  textbook_chapter: 4
  spec_section: "Tech Reqs §12 (Edge Domain)"
  notes: |
    Stored recipe (counterparty cert id + signing-key index + app context) lets
    a recovering device reconstruct an edge's shared secret. The ECDH shared
    secret itself is never persisted.

- id: BRC-85
  name: PIKE bilateral edge establishment
  domain: identity
  status: partial
  upstream_url: https://brc.dev/brc-0085
  semantos_paths:
    - core/plexus-vendor-sdk/src/VendorSDK.ts     # createEdge
  textbook_chapter: 4
  spec_section: "Tech Reqs §12 (Edge Domain)"
  notes: |
    Bilateral relationship establishment; composes with BRC-42 over the ECDH
    shared secret. Edge surface only — never the node-derivation path.

# Derivation hierarchy — the canonical relationship the matrix asserts (L11).
# This is the spine of "is the SDK built around Craig's methods, with BRC-42 an
# extension?": one foundation, two specialisations (not BRC-42-as-base).
derivation_hierarchy:
  foundation: EP3259724B1            # child = parent + H(segment) mod n
  specialisations:
    - id: node-derivation
      kind: unilateral
      primitive: EP3259724B1         # deriveSegment / deriveNodeKey
      surface: identity DAG (parent cert → child cert), monotonic childIndex
      kdf_versions:
        plexus-kdf-v2: canonical — deriveSegment (SHA-256(invoice))
        plexus-kdf-v1: legacy — BRC-42 self-derivation, retained for recovery
      semantos_paths:
        - core/plexus-vendor-sdk/src/crypto.ts    # deriveNodeKey
        - core/plexus-vendor-sdk/src/VendorSDK.ts # rederiveKey, deriveChild
    - id: edge-derivation
      kind: bilateral
      primitive: BRC-42              # EP3259724B1 with segment = HMAC(ECDH-shared, data)
      surface: two-party relationships (Edge Domain, Flag 0x01)
      semantos_paths:
        - core/plexus-vendor-sdk/src/VendorSDK.ts # createEdge
        - cartridges/wallet-headers/brain/src/ecdh42.ts

```
