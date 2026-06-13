---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/TAXONOMY-SEED-DESIGN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.333334+00:00
---

# Semantic Coordinate System Design

## Principle

Type space is a coordinate system, not a single hierarchy. Three required semantic axes plus three optional context axes.

### Required Axes (semantic placement — every object must have these)

- **WHAT** — what the thing is
- **HOW** — how it operates / is performed / is realised
- **WHY** — what function / purpose / end it serves

### Optional Axes (context — enriches but not always needed)

- **WHERE** — geolocation (lat/lng, region path, or jurisdiction coordinate)
- **WHEN** — blockheight + tx index (provably ordered, chain-anchored proof of existence)
- **WHO** — CertID of the publishing identity (provenance — and recursively, who published the type definitions themselves)

Object types bind coordinates across all axes:

```typescript
interface TypeCoordinate {
  // Required: semantic placement
  what: string;          // "what.service.fabrication.carpentry"
  how: string[];         // ["how.physical.manual", "how.technical.joinery"]
  why: string[];         // ["why.production", "why.maintenance"]

  // Optional: context
  where?: GeoCoordinate; // geolocation or jurisdiction path
  when?: ChainAnchor;    // blockheight + tx index
  who?: string;          // CertID of publishing identity
}

interface GeoCoordinate {
  lat?: number;
  lng?: number;
  region?: string;       // LTREE path: "au.qld.brisbane.northside"
  jurisdiction?: string; // governance jurisdiction path
}

interface ChainAnchor {
  blockHeight: number;
  txIndex: number;       // position within block — gives total ordering
  txid?: string;         // optional txid for direct lookup
}
```

### Why These Axes

WHERE makes objects spatially addressable. A carpentry service in Brisbane is not the same listing as one in Melbourne. It also determines jurisdiction (which governance rules apply), enables proximity discovery, and eventually feeds the SRv6 routing parked in Domain 4.

WHEN as blockheight + tx index is better than wall-clock time because it is provably ordered and immutable. You can answer "did this object exist before that dispute?" without trusting anyone's clock. It composes with linearity: a LINEAR object consumed at block N cannot exist at block N+1.

WHO as CertID makes provenance a first-class coordinate. Every object carries the identity that published it. But taxonomy nodes are themselves objects — so they also carry WHO. This means the type space has an auditable governance chain: you can trace any coordinate back through its ballot, proposer reputation, and the votes that approved it.

## Authority Model

- **Symbolic LTREE** = authoritative. Taxonomy nodes are semantic objects with patches and governance.
- **Embeddings** = assistive. Synonym discovery, candidate classification, merge suggestions. Never the source of truth.
- **Wiki ontology** = seed material. Compressed through a civilisational production lens, not preserved as a neutral encyclopedia.

Seed first. Govern later. Assist with embeddings. Preserve symbolic authority.

## Compression Lens

The seed is not "Wikipedia on chain." It is Wikipedia digested into a production ontology. Each node is re-grounded in its role in sustaining, enabling, reproducing, coordinating, or degrading human productive capacity across time.

This includes reproductive/generative functions (parenting, care work, education) as first-class economic realities — not invisible "non-economic" leftovers. A mother creates another productive individual of unbounded capacity. That is high-order generative function with massive downstream externalities.

### Node Metadata Fields

```typescript
interface TaxonomySeedNode {
  path: string;                    // e.g. "what.person.parent.mother"
  axis: "what" | "how" | "why";
  label: string;
  description: string;
  function_type?: string;          // generative, maintenance, coordination, etc.
  primary_outputs?: string[];
  required_inputs?: string[];
  enables?: string[];              // paths this node enables
  depends_on?: string[];           // paths this node depends on
  positive_externalities?: string[];
  negative_externalities?: string[];
  time_horizon?: "immediate" | "short" | "medium" | "long" | "generational";
  beneficiary_scope?: "individual" | "household" | "community" | "regional" | "civilisational";
  substitutability?: "none" | "low" | "medium" | "high";
}
```

## Seed: WHAT Axis

Root concepts for what things are.

```
what
├── person
│   ├── parent
│   ├── worker
│   ├── learner
│   └── caregiver
├── group
│   ├── household
│   ├── team
│   ├── organisation
│   └── community
├── institution
│   ├── family
│   ├── firm
│   ├── school
│   ├── court
│   └── government
├── object
│   ├── artifact
│   ├── material
│   └── structure
├── resource
│   ├── natural
│   ├── financial
│   ├── informational
│   └── social
├── place
│   ├── dwelling
│   ├── workspace
│   ├── commons
│   └── territory
├── event
│   ├── transaction
│   ├── agreement
│   ├── dispute
│   └── transition
├── process
│   ├── manufacturing
│   ├── cultivation
│   ├── extraction
│   └── transformation
├── service
│   ├── fabrication
│   ├── repair
│   ├── transport
│   ├── care
│   ├── instruction
│   └── mediation
├── claim
│   ├── assertion
│   ├── credential
│   ├── entitlement
│   └── obligation
├── rule
│   ├── norm
│   ├── law
│   ├── protocol
│   └── standard
├── record
│   ├── evidence
│   ├── ledger
│   ├── certificate
│   └── log
├── asset
│   ├── token
│   ├── deed
│   ├── license
│   └── stake
├── tool
│   ├── instrument
│   ├── software
│   ├── machine
│   └── pattern
└── system
    ├── network
    ├── infrastructure
    ├── ecosystem
    └── protocol
```

## Seed: HOW Axis

Root concepts for how things operate.

```
how
├── biological
│   ├── reproduction
│   ├── growth
│   ├── metabolism
│   └── healing
├── physical
│   ├── manual
│   ├── mechanical
│   ├── chemical
│   └── electrical
├── cognitive
│   ├── analysis
│   ├── design
│   ├── decision
│   └── invention
├── social
│   ├── care
│   ├── negotiation
│   ├── cooperation
│   └── delegation
├── economic
│   ├── exchange
│   ├── allocation
│   ├── investment
│   └── insurance
├── legal
│   ├── adjudication
│   ├── enforcement
│   ├── legislation
│   └── arbitration
├── technical
│   ├── engineering
│   ├── joinery
│   ├── welding
│   └── programming
├── communicative
│   ├── teaching
│   ├── persuasion
│   ├── documentation
│   └── translation
├── computational
│   ├── calculation
│   ├── simulation
│   ├── optimisation
│   └── verification
├── logistical
│   ├── transport
│   ├── storage
│   ├── scheduling
│   └── routing
├── educational
│   ├── instruction
│   ├── mentorship
│   ├── assessment
│   └── apprenticeship
└── governance
    ├── voting
    ├── staking
    ├── moderation
    └── auditing
```

## Seed: WHY Axis

Root concepts for what function things serve.

```
why
├── survival
│   ├── nutrition
│   ├── shelter
│   └── protection
├── safety
│   ├── prevention
│   ├── mitigation
│   └── recovery
├── maintenance
│   ├── repair
│   ├── preservation
│   └── renewal
├── production
│   ├── creation
│   ├── extraction
│   └── synthesis
├── reproduction
│   ├── biological
│   ├── cultural
│   └── institutional
├── coordination
│   ├── planning
│   ├── synchronisation
│   └── conflict_resolution
├── exchange
│   ├── trade
│   ├── gift
│   └── redistribution
├── knowledge
│   ├── discovery
│   ├── preservation
│   └── transmission
├── healing
│   ├── medical
│   ├── psychological
│   └── social
├── mobility
│   ├── physical
│   ├── social
│   └── informational
├── security
│   ├── personal
│   ├── property
│   └── systemic
├── play
│   ├── recreation
│   ├── art
│   └── exploration
└── meaning
    ├── identity
    ├── purpose
    └── belonging
```

## Cross-Axis Binding Examples

### Carpentry Service Listing (all six axes)
```json
{
  "what": "what.service.fabrication",
  "how": ["how.physical.manual", "how.technical.joinery"],
  "why": ["why.production.creation", "why.maintenance.repair"],
  "where": { "region": "au.qld.brisbane.northside", "jurisdiction": "au.qld" },
  "when": { "blockHeight": 891234, "txIndex": 42 },
  "who": "certid:provider:abc123"
}
```

### Motherhood (semantic only — no spatial/temporal context needed)
```json
{
  "what": "what.person.parent",
  "how": ["how.biological.reproduction", "how.social.care", "how.communicative.teaching"],
  "why": ["why.reproduction.biological", "why.reproduction.cultural", "why.knowledge.transmission"]
}
```

### Dispute Resolution (with WHO for provenance chain)
```json
{
  "what": "what.event.dispute",
  "how": ["how.legal.arbitration", "how.governance.moderation"],
  "why": ["why.coordination.conflict_resolution", "why.security.systemic"],
  "when": { "blockHeight": 891500, "txIndex": 7 },
  "who": "certid:consumer:def456"
}
```

### Taxonomy Node (WHO traces governance provenance)
```json
{
  "what": "what.rule.standard",
  "how": ["how.governance.voting"],
  "why": ["why.coordination.planning"],
  "when": { "blockHeight": 890000, "txIndex": 1 },
  "who": "certid:proposer:ghi789"
}
```
Note: this is a taxonomy node *as an object*. The WHO tells you which CertID proposed this category. The ballot that approved it carries its own WHO chain — every voter's CertID is stamped on their vote patch. The type space has full governance provenance.

### Teaching
```json
{
  "what": "what.service.instruction",
  "how": ["how.educational.instruction", "how.communicative.teaching"],
  "why": ["why.knowledge.transmission", "why.reproduction.cultural"]
}
```

## Branch Growth Pattern

Once seeded, taxonomy coordinates grow through governed patches:

- **add node** — append child under existing parent
- **rename node** — alias update with provenance
- **merge aliases** — combine near-duplicates (embeddings assist discovery)
- **split overloaded** — decompose a node that covers too many meanings
- **attach schema** — structural expectations at this coordinate
- **attach policy** — governance/moderation rules
- **attach flow** — conversational/behavioral actions
- **attach view** — UI/render hints

Each branch becomes a **semantic jurisdiction** where meaning, structure, governance, and affordances converge.

## Seeding Pipeline

1. Scrape/import wiki-scale ontology as raw source (Wikidata, Wikipedia categories)
2. Compress through civilisational production lens — re-ground in contribution, utility, coordination, externalities
3. Map concepts into three trunks: WHAT / HOW / WHY
4. Deduplicate aliases with embeddings assistance
5. Produce governed LTREE seed (this document's trees are the initial pass)
6. Attach schema/policy only where needed for Phase 10 extensions
7. Let governance refine from there

## Relationship to Existing Type System

The existing `computeTypeHash()` produces SHA256 hashes from WHAT/HOW/INSTRUMENT triples. TypeCoordinate replaces the flat triple with governed LTREE paths:

- WHAT → `taxonomy.what.*` (what the object is)
- HOW → `taxonomy.how.*` (how it operates)
- INSTRUMENT → subsumes into HOW or becomes a relation link to a `what.tool.*` coordinate

The type hash continues to provide identity — but its inputs are now governed coordinate paths rather than ad hoc strings.

### CRITICAL: Zero Cell Engine Changes

The six-axis coordinate system requires **no modifications** to the 256-byte cell header or the Zig/WASM cell engine. Every axis maps to something that already exists or lives outside the header:

| Axis | Storage Layer | Cell Header Field | Engine Change? |
|------|--------------|-------------------|---------------|
| WHAT | typeHash (32 bytes) | Existing — computed by `computeTypeHash()` | **No** |
| HOW | typeHash (32 bytes) | Existing — same hash | **No** |
| WHY | typeHash (32 bytes) | Existing — same hash | **No** |
| WHERE | Payload fields | None — payload is typed content | **No** |
| WHEN | Transaction context | None — comes from the chain | **No** |
| WHO | ownerId | Existing — derived from active facet CertID | **No** |

The coordinate system is an **interpretation layer** over what's already in the header, enriched by payload fields and chain context.

**WHERE** lives in the object payload alongside other content fields (description, pricing, etc.). Geolocation is content, not type metadata. Jurisdiction is derived from the region path through a governance lookup at query time. If hot-path spatial queries ever become a bottleneck, a compact geohash could be packed into existing reserved/extension bytes in the header — but that would be a future optimisation using existing space, not a header restructure.

**WHEN** comes from the transaction that anchors the cell. Blockheight + tx index are properties of the commitment, not the cell. The cell can optionally store a `ChainAnchor` reference in its payload if it needs to prove its own existence timestamp, but the chain is the source of truth.

**WHO** maps directly to the existing `ownerId` field in the cell header, which is already populated from the active facet's CertID at creation time. Every patch already carries facet provenance. WHO is the recursive application of existing identity mechanics to the type space itself — not a new field.

**WHERE as constitutional boundaries and abstract jurisdictions**: Region paths (`au.qld.brisbane`) define physical constraints. Jurisdiction paths define governance scopes — which tribunal hears disputes, which policies apply, which ballots have standing. These are governance lookups keyed by the WHERE coordinate, not cell engine concepts. A jurisdiction is an abstract realm anchored in physical geography but governed by its own policy objects. The cell engine doesn't care about any of this — it just packs and verifies bytes.

### The Recursive Provenance Chain

Because taxonomy nodes are objects, and objects carry WHO, the entire type space has an auditable provenance graph:

```
taxonomy.what.service.solar-installation
  ├── proposed by: certid:alice:xyz    (WHO on the proposal object)
  ├── ballot: governance.ballot:001     (WHO on each vote patch)
  │   ├── vote: certid:bob:abc         (approve)
  │   ├── vote: certid:carol:def       (approve)
  │   └── vote: certid:dave:ghi        (abstain)
  ├── approved at: block 891234, tx 7   (WHEN — chain anchor)
  └── jurisdiction: au.qld              (WHERE — governance scope)
```

This means you can ask: "Who approved this category? When? Under what jurisdiction's governance rules?" And the answers are all on-chain, all verifiable, all traceable through the same object/patch/facet mechanics that govern everything else.

## GIP (Genealogical Identity Protocol) Integration

### What GIP Is

GIP is a certificate-based identity protocol from Shomee-alpha that derives cryptographic identity from genealogical traits. The core schema (`gip.heraldic.v0.0.1`) uses hierarchical field numbering:

- `1.x` = self (givenName, familyName, dateOfBirth, placeOfBirth, gender, nationality, citizenship)
- `2.1.x` = father (givenName, middleName, familyName)
- `2.2.x` = mother (givenName, middleName, maidenName)
- `4.x` = contact (email, phone, address)
- `8.x` = recovery (secret questions/answers)

### Key Mechanics That Map to Semantos

**Selective Disclosure**: GIPTraits split into `disclosed` (public) and `hashed` (verifiable only with preimage), with an optional `merkle_root` for efficient subset proofs. This is the 402 challenge pattern applied to identity fields — the object doesn't reveal everything, it exposes what the jurisdiction/context requires.

**Delta Graph Reconstruction**: Certificate versions are not snapshots. They store reflection sequences (semantic deltas) and reconstruct any version by replaying from root. This IS the ObjectPatch evidence chain model already in the loom. GIP's `deltaGraphService.reconstructVersion()` is the same pattern as replaying patches on a LoomObject.

**Key Derivation from Traits**: The identity derives cryptographic keys (via PBKDF2, 100K iterations) from the genealogical traits themselves — name, parents' names, DOB, secret answers. WHO is not a random keypair — it is a function of genealogical position. The CertID is deterministically derived from who you are and where you come from.

**ZK Predicates** (stubbed in Shomee, architecturally present): Prove facts about identity without revealing traits. "Over 18" without DOB. "Australian citizen" without address. Connects to reputation — prove you meet a threshold without revealing the evidence graph.

### How GIP Maps to the Six Axes

| GIP Concept | Axis | Mapping |
|---|---|---|
| Schema fields (1.x, 2.x) | WHAT | `what.person.*` with genealogical sub-tree |
| Verification methods (document, biometric, video-call) | HOW | `how.social.verification.*` |
| Disclosure requirements vary by context | WHERE | Jurisdiction determines which traits must be disclosed |
| Certificate version history | WHEN | Each version anchored to chain or timestamped |
| CertID / public key | WHO | Derived from traits — identity as function of genealogical position |
| Selective disclosure | Access model | 402-style challenge on identity fields |
| Delta graph | Evidence chain | Already the patch model in loom |

### What GIP Adds Beyond Phase 8.5

Phase 8.5 identity is flat: a root AFFINE object with facets. GIP says identity has **genealogical depth** — you are the product of your parents, who are products of theirs. The heraldic schema makes this explicit.

In the coordinate system, this means:

1. **Genealogical tree on identity objects** — parent→child typed connections between identity objects, with the same patch/evidence mechanics. Add trait fields with hierarchical numbering to the identity type definition in extension config.

2. **Selective disclosure as access policy** — add a `disclosure` field to identity objects: which traits are public, which are hashed, which require ZK proof. Disclosure rules are keyed by jurisdiction (WHERE).

3. **Trait-derived key generation** — CertID as a function of genealogical traits, not random. This is a cryptographic design decision for when BRC-42/PIKE integration happens. Does not affect the cell engine.

4. **ZK predicates over identity** — prove statements about identity/reputation without revealing underlying traits or evidence graph. Future concern, but the architecture accommodates it.

### Cell Engine Impact: Zero

All of this is extension config additions, object type definitions, typed connections, and conversation flows. The genealogical tree is a graph of identity objects linked by typed patches. Selective disclosure is a payload-level access policy. Key derivation is a cryptographic function outside the cell engine. ZK proofs are an external verification layer.

### Phase Placement

Items 1-2 (genealogical tree structure, selective disclosure) fit in Phase 10 or a dedicated Phase 10.5 identity extension. Item 3 (trait-derived keys) activates when BRC-42/PIKE integration happens (Phase 11+). Item 4 (ZK predicates) is future research — the stub exists, the architecture supports it, but implementation waits for a real ZK proving system.
