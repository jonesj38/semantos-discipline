---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/SEMANTIC-ROUTING-SUBSTRATE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.733371+00:00
---

# The Semantic Routing Substrate — MNCA on the SRv6 Type-Network, Learned by Paskian, Anchored on BSV

**Version:** 0.1 (unification draft)
**Date:** 2026-05-23
**Status:** Design — unifies shipped + planned work into one substrate
**Owners / prior art:**
- `docs/prd/PHASE-34-SRV6-TYPE-NETWORK-MASTER.md` (SRv6 type-routed network)
- `docs/prd/PHASE-34E-PASKIAN-MESH-LEARNING.md` (Paskian learning / TSP approximation)
- `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` + `docs/canon/singularity-matrix.yml` (the MNCA layer-collapse demo)
- `docs/demo/MNCA-MESH-DEMO.md` (the live 6-Pi mesh demo)

**Canon home:** unification-matrix row **U14**; singularity-matrix cells **L3-F/G**, **L4-F/G/I**.

---

## 0. Thesis

Three pieces of work that look separate are one system seen at three layers:

1. **The MNCA layer-collapse demo** (singularity matrix) — one 1024-byte canonical
   cell traverses storage / memory / network / compute / identity / money across
   three hardware classes without ever being re-encoded. It is *live*: an MNCA
   tile is computed on the Pi mesh, multicast as a `cell_sync`, rendered in the
   browser, and anchored on BSV mainnet (tx `a5277713…b2a78c`, 2026-05-22).

2. **The SRv6 type-routed network** (Phase 34) — the cell's `typeHash` *is* the
   network address. Type-hash projections map onto IPv6 multicast bits; BCA +
   segment-function maps onto SRv6 SIDs. Routing, payment, provenance, and access
   control are all driven by the semantic type system, with longest-prefix-match
   over type-hash bits giving hierarchical fan-out — no central registry.

3. **Paskian mesh learning** (Phase 34E) — the SRv6 provenance DAG is observed by
   the Paskian constraint-graph learner, which converges routing toward the
   Steiner/TSP optimum through economic pressure (per-hop ticks), constraint
   pruning, and semantic clustering.

The unification: **the MNCA mesh IS the SRv6 type-routed network computing on
itself, and Paskian/HRR learning IS the routing heuristic, with every decision
anchored on BSV.** The tiles are the cells. The cells carry their own semantic
address. The mesh learns its own routing from the traffic it carries. The chain
is the audit trail.

This document names that system — the **Semantic Routing Substrate (SRS)** — and
records the pieces that already exist, the pieces designed in Phase 34/34E, and
the new pieces this unification adds (multitenancy to N≈100, type-path fuzzing,
the SNS framing, jural namespace depth).

---

## 1. The Semantic Name System (SNS)

### 1.1 The problem with a flat type hash

Today `computeTypeHash` (`core/semantos-sir`/`semantic-fs/type-hasher.ts`) is
`SHA-256` of a dotted taxonomy path:

```
SHA-256("mnca.tile.tick") → 32-byte typeHash, header offset 30
```

A flat hash is opaque. A relay holding `a3f7…` cannot tell it is semantically
adjacent to `SHA-256("mnca.tile.injection")` without a side lookup table. All the
structure in the dotted path is destroyed by the hash. That is the thing that
made type-path routing inert: the `typeHash` is in the header but nothing routes
on it, because the hash carries no navigable structure.

### 1.2 The fix: hierarchy lives in the IPv6 address, not the hash

Phase 34's answer (which supersedes the "chain the hash" sketch) is cleaner:
keep the per-axis hashes *separate* and project them onto *different bit-ranges of
the IPv6 multicast address*. The taxonomy's six axes (`what` / `how` / `why` +
`where` / `who` / `when`, the `TaxonomyCoordinates` in `core/semantos-sir`) map to
address space:

```
IPv6 multicast: ff03:WWWW:WWWW:HHHH:HHHH:IIII:IIII:0000
  ff03        realm-local scope
  WWWW:WWWW   computeWhatHash(whatPath)[0:4]   (32 bits)
  HHHH:HHHH   computeHowHash(howSlug)[0:4]     (32 bits)
  IIII:IIII   computeInstHash(instPath)[0:4]   (32 bits)
```

Hierarchical subscription falls out of **native IPv6 longest-prefix-match** — the
exact operation routers already perform on address prefixes:

```
ff03:WWWW:WWWW::                          all objects of this WHAT
ff03:WWWW:WWWW:HHHH:HHHH::                this WHAT + HOW
ff03:WWWW:WWWW:HHHH:HHHH:IIII:IIII:0000   exact composite type
ff03::HHHH:HHHH::                         all objects with this HOW (e.g. every "settle")
```

This is the **SNS — a Semantic Name System** rather than a Domain Name System.
DNS resolves `www.example.com` right-to-left through a hierarchy carried in the
name. SNS resolves a type by longest-prefix-match on type-hash bits carried in the
*address*. The taxonomy tree IS the multicast routing trie. No root servers, no
registrar — the type hash is the address, the grammar is the routing config.

> **Why this beats hash-chaining.** A chained hash (`H₁ = SHA-256(H₀‖seg)`) would
> embed ancestry but force a custom matching path. Per-axis projection reuses the
> FIB hardware/OS longest-prefix-match that exists in every IPv6 stack and every
> SRv6 router. Less to build, faster at runtime, and it generalises across the six
> axes instead of one linear chain.

### 1.3 Five of six axes routable without opening the cell

| Axis | Network representation | Visible at |
|---|---|---|
| WHAT | multicast bits [16:48] = `computeWhatHash`[0:4] | network layer |
| HOW  | multicast bits [48:80] = `computeHowHash`[0:4] | network layer |
| INST | multicast bits [80:112] = `computeInstHash`[0:4] | network layer |
| WHERE | BCA locator prefix (+ geohash in payload) | network + app |
| WHO  | BCA cert-hash in the SRv6 SID + `ownerId` (header offset 62) | network + transport |
| WHEN | header timestamp (offset 78) + In-situ OAM (RFC 9486) | transport + network |

Only **WHY** (business purpose) needs app-layer inspection — which is correct: the
network forwards on structure, the application decides intent.

---

## 2. The MNCA substrate — tiles ARE the cells

### 2.1 What's already live

`runtime/semantos-brain/tools/mesh-node` seeds an MNCA tile deterministically from
its `cellId`, steps the interior every `--tile-ms`, and broadcasts the 768-byte
tile payload as a `cell_sync` over IPv6 multicast (`ff15::5e:1`, port 47100). The
canonical kernel is `core/protocol-types/src/mnca/tile.ts` (`stepTile`, the
cross-hardware determinism oracle, ported to on-device Zig in `mnca_tile.zig`). The
Mac bridge (`docs/demo/mesh-bridge.ts`) decodes those to SSE; the browser
(`grid-viz.ts`) renders the composite grid; `mesh-snapshot-anchor.ts` packs a
1024-byte snapshot cell and anchors it on BSV (dry-run by default; one real
mainnet anchor exists).

The MNCA tile is not a parallel representation — it round-trips through the
canonical cell payload codec every frame. **The tile is a cell.** That is the
whole point of the layer-collapse thesis, and it is what lets MNCA tiles flow
through the SRv6 type-network as first-class typed cells: `mnca.tile.tick`,
`mnca.tile.injection`, `mnca.snapshot`, `mnca.perturb` (the four canonical types in
`core/protocol-types/src/mnca/cell-types.ts`).

### 2.2 Multitenancy — from N=6 to N≈100 on the same hardware

Today each Orange Pi Prime runs one `mesh-node` = one tile. The substrate scales
by stacking tenants per Pi, using a **two-tier multicast hierarchy** that mirrors
the SRv6 locator hierarchy in miniature:

```
Pi A (192.168.0.3)                         Pi B (192.168.0.4)
┌──────────────────────────┐               ┌──────────────────────────┐
│ brain-0  (tile 0,0)      │               │ brain-16 (tile 4,0)      │
│ brain-1  (tile 1,0)      │               │ ...                      │
│ ...        ↕ lo           │               │            ↕ lo           │
│ brain-15  ff15::5e:2      │               │ brain-31  ff15::5e:2      │
│            ↕              │               │            ↕              │
│        [gateway]──────────┼── end0 ───────┼──────[gateway]            │
└──────────────────────────┘   ff15::5e:1  └──────────────────────────┘
```

- **Intra-Pi:** `ff15::5e:2` on `lo` — the ~16 brains on one Pi gossip at loopback
  speed. This is one SRv6 *locator prefix* (same `WHERE`).
- **Inter-Pi:** `ff15::5e:1` on `end0` — the existing, validated LAN multicast,
  now between ~6 gateways instead of 6 nodes. Crossing it is a locator-prefix
  change.
- **Gateway:** one per Pi, bidirectionally relaying `ff15::5e:2 ↔ ff15::5e:1`. It
  is the `mcast-relay.py` pattern made two-way — the SRv6 PE (provider-edge)
  router. It is the enforcement point for which type paths cross the Pi boundary
  (`mnca.local.*` stays; `mnca.federated.*` crosses).

Resource budget (H5, 4×A53, 2 GB): a `mesh-node` is a mostly-idle Zig binary at
500 ms tick, ~3 MB RSS, ~0.5 % CPU. 16/Pi ≈ 50 MB + ~8 % CPU — comfortable; 30/Pi
is fine. **6 Pis × 16 = 96 ≈ N100.** Grid: a 4×4 block per Pi in a 2×3 macro-grid
→ 24×8 tiles × 12×12 interior = **23,040 cells** — a real CA, not a toy.

### 2.3 The community structure is the spatial prior

Because intra-Pi latency (loopback, µs) ≪ inter-Pi latency (LAN, ms), tiles on the
same Pi synchronise faster and develop coherent patches with phase-slip at Pi
boundaries. That is exactly the `proximity_weight = 1/(hop_count+1)` spatial prior
Phase 34E's Layer-2 correlation learner needs — the mesh discovers its own
topology from its own dynamics. Tight intra-Pi coherence = low-latency cluster =
route within it; phase boundary = inter-Pi hop cost.

---

## 3. Three coupled optimisations on one substrate

The substrate runs three problems *simultaneously* on the same MNCA tile state and
the same SRv6 provenance DAG. They are coupled in the routing domain, not bolted
together.

### 3.1 TSP / Steiner — "which route?"

Optimal multicast routing is the minimum Steiner tree (NP-hard, TSP-class).
Phase 34E does not solve it; it converges via three interlocking mechanisms,
structurally an ant-colony optimisation but with *real* economics:

| ACO | Semantic Routing Substrate |
|---|---|
| pheromone deposit | `End.S.TICK` BSV micropayment per hop |
| pheromone evaporation | Paskian pruning (`weight < threshold` → LINEAR `paskian.graph.pruned`) |
| ant memory | RELEVANT `paskian.graph.edge` cells in storage |
| colony convergence | Paskian stability (ΔH < ε) |
| solution quality | total tick cost across active paths |

In MNCA terms the outer-neighbourhood cells carry the pheromone trails: birth =
deposit on a good segment, survival = persistence, death = evaporation. The
approximation ratio (`tsp-metric.ts`, Phase 34E D34E.5) measures how close the
learned routing gets to the MST lower bound; converged ratio is typically 1.2–1.5.

### 3.2 Knapsack — "which packets, given capacity?"

Admission control under per-hop bandwidth constraints is a knapsack. It is already
a segment function: `End.S.METER` (`0x07`) consumes an **AFFINE** bandwidth slot;
no slot → drop (backpressure). The inner-neighbourhood MNCA cells carry queue
pressure; the relay-advertisement price (`selectRelay`, cheapest-viable by
`pricePerCellSats`) is the value-density signal. The inner/outer neighbourhood
interaction each tick is the Lagrangian coupling between knapsack and Steiner —
joint optimisation for free from the multi-neighbourhood rule structure.

### 3.3 Type-path fuzzing — "who subscribes, and where?" (NEW)

This is the new optimisation the unification adds. To discover the subscriber
topology without a registry, generate perturbations of the dotted type path,
derive their SNS multicast addresses, probe, and observe which nodes self-select.
The novel mechanism: **MNCA state is the coverage signal.**

- Fuzz a type path → derive its multicast group → probe the mesh.
- Response pattern (which gateways relay it, at what latency) maps to a tile-state
  change.
- Novel CA state region → this type path discovered new topology → keep + anchor.
- Already-explored CA state → redundant → deprioritise.

Standard coverage-guided fuzzers use code-branch coverage. Here the coverage
signal is the emergent state of a distributed cellular automaton running on the
network being probed — the fuzzer is steered by the substrate it is fuzzing. HRR
(below) makes the walk semantic rather than random.

### 3.4 HRR / Pask as the semantic distance metric

The chess test proved Pask evaluates structured states and retrieves analogues.
Routing is the same shape: `[network-state] × [route] × [type-path] → outcome`.
HRR binding superimposes the three so similar network states retrieve good (route,
admission, type-path) tuples jointly; partial unbinding gives prefix retrieval
(`mnca.tile.??? `). HRR dot-product distance replaces arbitrary XOR distance in the
DHT, so "nearest handler" means *semantically* nearest. Type-path fuzzing is then
HRR nearest-neighbour search — navigate by distance, don't enumerate.

---

## 4. Jural namespace depth

The `who` axis is not just an identifier — it carries jural standing. The SIR
layer defines Hohfeldian `JuralCategory` (`declaration`, `obligation`,
`permission`, `prohibition`, `power`, `condition`, `transfer`). A jurally-typed
cell extends its path by one segment:

```
mnca.tile.tick                      → base transform
mnca.tile.tick:obligation           → an obligation-typed instance
```

Nodes that can act on obligations are a sub-namespace one hop deeper in the SNS
tree. Grammar licensing (Phase 34 §"Grammar Licensing") makes this concrete: a
RELEVANT `plexus.capability.grammar_license` token gates `End.S.LICENSE` (`0x09`).
A cell typed `who:asic-licensed` physically cannot reach a non-credentialled node
because `OP_CHECKIDENTITY` rejects it — **routing IS compliance**, enforced in
script, not policy. The BSV anchor is the enforcement mechanism, not decoration.

Worked example (Mac Konts' construction-analytics use case):

```
what:cre.commercial.los-angeles
how:logistics-analytics
why:grant-compliance
who:fema-certified
where:pacific-palisades
when:2026-rebuild
```

Only FEMA-certified nodes route it; the MNCA mesh discovers the certified-node
topology; the anchor proves each hop was compliant.

---

## 5. On-chain anchoring as proof-of-routing

Every interesting event becomes a verifiable BSV-anchored proof, reusing the
proven pushdrop path (`mesh-bsv-sink.ts`, mainnet tx `a5277713…b2a78c`):

- **Routing decision:** `(network-state, SID-list-chosen, admission-decision)`.
- **Stable finding:** `paskian.graph.stable` (a converged route or sensor
  correlation) anchored when ΔH < ε.
- **Pruning event:** `paskian.graph.pruned` (LINEAR — consumed once).
- **Type-path discovery:** a fuzzed path that hit a novel CA state and found a new
  subscriber cluster.

The result is a tamper-evident semantic map of the network — who holds what jural
standing for what instrument types, discovered continuously, with cryptographic
proof that each discovery came from observed behaviour, not fabricated telemetry.

> **HARD SAFETY (unchanged):** anchoring is BUILD + DRY-RUN by default. No
> autonomous mainnet broadcast; the live broadcast stays operator-gated via the
> browser wallet. Anchors use a throwaway key + synthetic UTXO. No private keys
> printed or committed.

### 5.1 Economics — what a budget buys

At ~100 sats/KB and a ~1.3 KB pushdrop anchor (~130 sats):

| Anchor cadence | Ticks/anchor (2 Hz) | 1 BSV (100M sats) buys |
|---|---|---|
| every tick | 1 | ~769k anchors ≈ 4.5 days continuous |
| every 30 s (current) | 60 | ~46k anchored ticks/snapshot run, ~267 days |

A proof-of-concept run (~10k meaningful anchors) costs ~0.013 BSV. The compute
(MNCA ticks on hardware) is free; sats price only the on-chain *proof* density.

---

## 6. Layered view (one stack)

```
┌─────────────────────────────────────────────────────────────────────┐
│ PROOF      BSV pushdrop anchors: routing decisions, stable findings,  │
│            pruning, type-path discoveries  (mesh-bsv-sink, mainnet)   │
├─────────────────────────────────────────────────────────────────────┤
│ LEARN      Paskian/HRR over SRv6 provenance DAG: TSP (Layer 1),       │
│            correlation (Layer 2), type-path fuzzing (coverage=MNCA)   │
├─────────────────────────────────────────────────────────────────────┤
│ ROUTE      SNS: typeHash→IPv6 multicast bits (longest-prefix-match);  │
│            SRv6 SID = prefix:BCA:func:args; segment functions         │
│            (CREATE/VALIDATE/TICK/METER/FILTER/DISPATCH/LICENSE…)       │
├─────────────────────────────────────────────────────────────────────┤
│ COMPUTE    MNCA tiles = cells; stepTile kernel (TS oracle = Zig =     │
│            on-chain); inner nbhd=knapsack, outer nbhd=Steiner trails  │
├─────────────────────────────────────────────────────────────────────┤
│ MESH       Two-tier multicast: intra-Pi ff15::5e:2 (lo) ↔ inter-Pi    │
│            ff15::5e:1 (end0) via per-Pi gateway; N≈100 brains         │
└─────────────────────────────────────────────────────────────────────┘
   identity (BCA, secp256k1, Ducroux) threads every layer; the 1024-byte
   cell is the single representation throughout (layer-collapse thesis).
```

---

## 7. What exists / what's designed / what's new

| Capability | State | Source |
|---|---|---|
| MNCA tile = cell, stepTile kernel, oracle = Zig = on-chain | **live** | `mnca/tile.ts`, `mnca_tile.zig` |
| 6-Pi mesh, multicast gossip, SSE bridge, browser viz | **live** | `docs/demo/MNCA-MESH-DEMO.md` |
| Cell anchored + spendable on BSV mainnet | **live** | tx `a5277713…b2a78c` |
| Transform-on-hop (stepTile rides routing, type rotates) | **live** | L4-F, `cell_transform.zig` |
| Source-routed cell traverses real mesh (1- and 2-relay) | **live** | L3-F, `routing.zig` |
| typeHash→multicast derivation, SRv6 SID encode, seg-funcs | **designed** | Phase 34A |
| Paskian Layer 1/2, routing feedback, TSP metric | **designed** | Phase 34E |
| Grammar licensing via RELEVANT cap token + `End.S.LICENSE` | **designed** | Phase 34 §licensing |
| **SNS framing** (type-hash hierarchy = IPv6 prefix trie) | **new (this doc)** | §1 |
| **Multitenancy to N≈100** (two-tier multicast, per-Pi gateway) | **new (this doc)** | §2.2 |
| **Type-path fuzzing** (coverage-guided, MNCA state = coverage) | **new (this doc)** | §3.3 |
| **MNCA-as-routing-substrate** (tiles carry pheromone/queue rows) | **new (this doc)** | §3.1–3.2 |
| **Jural namespace depth** (`who`/Hohfeld as routing constraint) | **new (this doc)** | §4 |
| **Routing state as continuation cell** (forward.v2 shape — C6 finding) | **open (this doc)** | §10.5 |

---

## 8. New deliverables this unification adds

Tracked in `docs/canon/deliverables.yml`:

- **`D-SRS-tenant-gateway`** — bidirectional per-Pi gateway relaying
  `ff15::5e:2 ↔ ff15::5e:1` (extend `mcast-relay.py`); the SRv6 PE in miniature.
- **`D-SRS-multitenant-spawn`** — `run-multitenant-pi.sh`: spawn ~16 `mesh-node`
  tenants per Pi on loopback with a global tile-coord scheme
  (`tileX = piIndex*4 + localX`); orchestrate from `run-real-mesh.ts`.
- **`D-SRS-mnca-cell-source`** — replace the random tile seed with a real input
  window (network stats / sensor / data) so the MNCA rule is a filter over real
  data; map tile rows to {what, who, where, when density, pheromone, queue}.
- **`D-SRS-typepath-fuzzer`** — coverage-guided semantic fuzzer: perturb dotted
  type paths, derive SNS multicast addresses, probe, read MNCA novelty as the
  coverage signal; anchor novel discoveries.
- **`D-SRS-sns-multicast-wire`** — wire `deriveMulticastGroup` (Phase 34A) into
  the live mesh so type paths actually drive multicast membership (closes the
  "typeHash is in the header but inert" gap).

Existing Phase-34 deliverables (`D34A.1…D34E.6`) remain the canonical
implementation tickets; the D-SRS set is the unification-specific glue that binds
them to the live MNCA mesh.

---

## 9. Relationship to the matrices

- **Singularity matrix** (`docs/canon/singularity-matrix.yml`): SRS advances the
  routing/overlay axes — **L3-F** (network routing), **L3-G** (paid-pubsub),
  **L4-F** (compute-on-hop routing), **L4-G** (transform-capability market),
  **L4-I** (visualiser → live multi-tile mesh). Those cell notes now reference
  this substrate as the active path.
- **Unification matrix** (`docs/canon/unification-matrix.yml`): SRS is a new
  substrate row **U14 — Semantic Routing (SNS / SRv6 type-network)**, sitting on
  U6 (Mesh) the way SCG (U12) sits on U8. It consumes U6 transport, U3 identity
  (BCA), U10 metering (`End.S.TICK`), and U8 SIR/lexicons (jural categories), and
  it is the substrate the MNCA layer-collapse demo exercises end-to-end.

---

## 10. Open questions

1. **SNS scope bits.** Phase 34 uses `ff03` (realm-local). The two-tier
   multitenant mesh wants intra-Pi (`ff15::5e:2`) vs inter-Pi (`ff15::5e:1`)
   distinguishable at the address level — reconcile the demo's `ff15` groups with
   Phase 34's `ff03:WHAT:HOW:INST` derivation (likely: keep `ff15` link/realm
   scope, fold WHAT/HOW/INST into the group-ID bits below the scope).
2. **HRR ↔ DHT binding.** Phase 34E uses a Paskian constraint graph; HRR as the
   distance metric (§3.4) is a refinement, not yet a deliverable. Decide whether
   HRR replaces or augments the Paskian edge-weight graph for type-path proximity.
3. **Fuzzer safety.** Coverage-guided type-path fuzzing emits probe cells; gate it
   to dry-run/test type paths (`*.fuzz.*`) so it never perturbs production
   subscriber state.
4. **Anchor cadence policy.** Make the snapshot/finding anchor interval a CLI flag
   so proof density vs cost is operator-tunable (§5.1).

5. **Routing state as continuation cell (forward.v2).** The C6 demo exposed a
   concrete constraint: `forward.v1` embeds its routing header (segment list +
   4×68-byte hop commitment slots) directly in the primary cell's payload region,
   consuming 320 of the 768 available bytes and leaving only 448 bytes for
   application content. Every field added to the commitment array (e.g. the
   BRC-108 `cert_hash[32]`) shrinks application headroom directly.

   The fix has the same structure as BEEF/BUMP: make routing state a
   *continuation cell* rather than an embedded prefix. The multicell packer
   already defines a continuation taxonomy in `core/cell-engine/src/multicell.zig`
   (`0x01 BUMP`, `0x02 ATOMIC_BEEF`, `0x03 ENVELOPE`, `0x04 DATA`,
   `0x05 STATE`, `0x06 POINTER`). Routing state would be a new type in that
   series. The primary cell becomes a clean full-budget application cell;
   the routing/payment continuation travels alongside, is processed at each
   relay hop, and is stripped at the destination. This mirrors exactly how
   BEEF/BUMP proofs already ride alongside their transactions without consuming
   transaction payload.

   Decision needed before forward.v2 is specified:
   - Continuation type byte (`0x07 ROUTING`?)
   - Whether `hop_commitments` (payment) and the segment list (routing) share
     one continuation or split into two (`0x07 ROUTING` + `0x08 PAYMENT`)
   - Whether the continuation model is portable to the C6 (the embedded side
     currently only parses the flat 1024-byte format; the multicell packer
     lives in the Zig kernel, not in the C cell-mesh component)

6. **Routable vs identity-only BCA (identity-transport hinge).** The
   `docs/design/SRS-XMPP-IDENTITY-TRANSPORT.md` binding makes a JID's domain the
   BCA, so "the domain *is* the route" (serverless, DNS-free federation) iff the
   BCA's subnet prefix is a real allocation on the SRv6 locator plane. Today the
   BCA is identity-only (the mesh is `ff15::` realm/link-local; SRv6 locators are
   designed in Phase 34, not deployed), so `resolveBCA` must ride the existing
   peer-locator and `XmppNetworkAdapter` delegates it. This is the same
   unresolved scope/locator question as §10.1 above, viewed from the transport
   side: settling the `ff15`/`ff03`/locator-prefix scheme also settles whether
   XMPP rides over the locator or replaces it.
