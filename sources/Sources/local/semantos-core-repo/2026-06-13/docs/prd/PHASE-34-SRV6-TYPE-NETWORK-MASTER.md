---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-34-SRV6-TYPE-NETWORK-MASTER.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.699239+00:00
---

# Phase 34 — SRv6 Type-Routed Network Layer

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1–2 weeks (four sub-phases)
**Prerequisites**: Phase 26A–26D complete (four adapter interfaces), Phase 2 BCA derivation (Zig), esp32-hackkit functional
**Branch prefix**: `phase-34x-`

---

## Context

Semantos has a six-axis coordinate system (WHAT/HOW/WHY + WHERE/WHEN/WHO) and a composite type hash `SHA256(whatPath:howSlug:instPath)` that uniquely identifies every object type across every vertical. It also has BCA (Bitcoin Certified Address) — an IPv6 address deterministically derived from a Plexus cert's public key, already implemented in `cell-engine/src/bca.zig`.

Phase 34 maps the type system onto IPv6 address space, making the network layer itself type-aware. Multicast group addresses are derived from type hashes. SRv6 Segment IDs encode BCA device identity plus cell engine operations. The result is a general-purpose, vertical-agnostic network layer where routing, payment, provenance, and access control are all driven by the semantic type system.

This is the infrastructure phase that turns Semantos from a collection of verticals into a platform. Any vertical that defines a grammar (type paths + linearity assignments) automatically gets type-routed multicast, SRv6 provenance, per-hop micropayments, and cross-vertical dispatch — with zero network configuration.

### Why This Is a Separate Phase from DePIN (Phase 33)

Phase 33 builds DePIN on ESP32 with real adapters and a specific use case. Phase 34 generalises the network layer so that every vertical — trades, property, CDM, electroculture, cold chain, future verticals — gets the same routing infrastructure. Phase 33B (OpenThread network adapter) becomes "wire DePIN to the Phase 34 network layer" rather than building DePIN-specific networking.

### Prior Art in the Codebase

The shomee-era `civ-stack` packages (archived in the extraction audit) contained working implementations of several Phase 34 concepts:

| Concept | Shomee Source | Status |
|---------|---------------|--------|
| SRv6 router | `civ-stack-sr6-router/src/router/SRv6Router.ts` | Archived — design reference |
| Multicast addressing | `civ-stack-stream-network/src/services/MulticastAddressManagerImpl.ts` | Archived — design reference |
| Contract segments | `civ-stack-contract-segment/src/validators/PaymentValidator.ts` | Archived — design reference |
| Geo-aware routing | `civ-stack-overlaynet/src/geo/GeoHashUtils.ts` | Archived — design reference |
| Glow-weight routing | `civ-stack-overlaynet/src/weight/GlowWeightUtils.ts` | Archived — design reference |
| 6LoWPAN overlay | `civ-stack-lowpan-overlay/` | Archived — design reference |

These are **design references only** — the shomee implementations predate the cell engine, the four-adapter architecture, and the Plexus cert model. Phase 34 rebuilds on the current foundation. But the architectural thinking is validated.

### What Already Exists (Production)

| Component | Location | What it provides |
|-----------|----------|-----------------|
| BCA derivation | `cell-engine/src/bca.zig` | IPv6 address from public key, sec parameter encoding, collision handling |
| BCA conformance tests | `cell-engine/tests/bca_conformance.zig` | Deterministic derivation, u-bit/g-bit handling, performance (<1ms) |
| Type hash computation | `cell-ops/src/typeHashRegistry.ts` | `computeTypeHash()`, `computeWhatHash()`, `computeHowHash()`, `computeInstHash()` |
| Six-axis taxonomy | `docs/TAXONOMY-SEED-DESIGN.md` | WHAT/HOW/WHY + WHERE/WHEN/WHO, zero cell engine changes |
| NetworkAdapter interface | `protocol-types/src/network.ts` | `publish()`, `resolve()`, `subscribe()`, `resolveBCA()`, `sendToNode()` |
| Dispatch envelope model | `docs/prd/PLATFORM-ARCHITECTURE.md` | Cross-vertical facet-scoped semantic objects |
| Cell header format | `cell-ops/src/typeHashRegistry.ts` | 256 bytes, typeHash at offset 30, linearity at offset 16, ownerId at offset 62 |

---

## Architecture

### The Three Mappings

Phase 34 establishes three mappings from the Semantos type system to IPv6 address space:

#### 1. Type Hash → Multicast Group Address

```
IPv6 multicast: ff03:WWWW:WWWW:HHHH:HHHH:IIII:IIII:0000

ff03            — realm-local scope (mesh/site)
WWWW:WWWW       — computeWhatHash(whatPath)[0:4]     (32 bits)
HHHH:HHHH       — computeHowHash(howSlug)[0:4]       (32 bits)
IIII:IIII       — computeInstHash(instPath)[0:4]     (32 bits)
0000            — reserved (future: version/flags)
```

Hierarchical subscription via prefix matching:

```
ff03:WWWW:WWWW::                          → all objects of this WHAT type
ff03:WWWW:WWWW:HHHH:HHHH::               → specific WHAT + HOW
ff03:WWWW:WWWW:HHHH:HHHH:IIII:IIII:0000  → exact composite type
ff03::HHHH:HHHH::                         → all objects with this HOW
                                             (e.g., all "settle" events)
```

The taxonomy tree maps to multicast routing trie. Longest-prefix matching on the WHAT bits gives automatic fan-out from leaf types to parent categories.

#### 2. BCA + Operation → SRv6 Segment ID

```
SRv6 SID: PPPP:PPPP:CCCC:CCCC:FF:AA:AAAA:AAAA

PPPP:PPPP       — routing prefix (network-specific, e.g. 2602:f9f8)
CCCC:CCCC       — BCA interface identifier (from bca.zig derivation)
FF              — segment function code (Semantos operation)
AA:AAAA:AAAA    — function arguments (operation-specific)
```

The BCA portion (CCCC:CCCC) is the 8-byte interface identifier from `bca.zig`'s `deriveBCA()`. It's cryptographically bound to the device's Plexus cert. The segment function code and arguments encode what the cell engine does at this hop.

#### 3. Segment Functions (Operations at Each Hop)

| Code | Name | Cell Engine Operation | Arguments |
|------|------|-----------------------|-----------|
| `0x01` | End.S.CREATE | Source device creates cell | Type hash prefix (4 bytes) |
| `0x02` | End.S.VALIDATE | Run `OP_CHECKLINEARTYPE` on in-transit cell | Expected linearity (1 byte) |
| `0x03` | End.S.TICK | Increment MFP tick, earn micropayment | Satoshis per tick (4 bytes LE) |
| `0x04` | End.S.ANCHOR | Submit state hash to BSV | Batch flag (1 byte) |
| `0x05` | End.S.ATTEST | Sign cell hash with this device's cert | Domain flag (4 bytes LE) |
| `0x06` | End.S.FILTER | Drop cell if type hash prefix ≠ ARGS | Type hash prefix (4 bytes) |
| `0x07` | End.S.METER | Consume AFFINE bandwidth slot | Slot ID (4 bytes) |
| `0x08` | End.S.DISPATCH | Cross-vertical forward (dispatch envelope) | Target WHAT prefix (4 bytes) |
| `0x09` | End.S.LICENSE | Verify grammar license (RELEVANT capability token) | WHAT prefix to check (3 bytes) |

### The Six Axes in the Network

```
Axis     Network Representation                    Visibility
────     ──────────────────────────────────────     ──────────
WHAT     Multicast group bits [16:48]               Network layer
         computeWhatHash(whatPath)[0:4]

HOW      Multicast group bits [48:80]               Network layer
         computeHowHash(howSlug)[0:4]

INST     Multicast group bits [80:112]              Network layer
         computeInstHash(instPath)[0:4]

WHERE    BCA locator prefix (network-routable)      Network layer
         + geohash in cell payload                  + App layer

WHEN     Cell header timestamp (offset 78, 8B)      Transport layer
         + SRH In-situ OAM timestamp (RFC 9486)    + Network layer

WHO      BCA cert-hash in SRv6 SID (CCCC:CCCC)     Network layer
         + ownerId in cell header (offset 62, 16B)  + Transport layer
```

Five of six axes are visible at the network layer without opening the cell. Routers can make forwarding, filtering, payment, and provenance decisions based on type hash bits and BCA identity alone. Only WHY (business purpose) requires application-layer inspection — which is architecturally correct.

### Cross-Vertical Routing

The dispatch envelope from `PLATFORM-ARCHITECTURE.md` maps to SRv6 as follows:

A property maintenance request dispatches a tradie. The SRH encodes:

```
Segment[0]: BCA(PM_node) + End.S.CREATE      — PM creates dispatch envelope
Segment[1]: BCA(PM_node) + End.S.DISPATCH     — cross-vertical: WHAT(property) → WHAT(trades)
Segment[2]: BCA(router)  + End.S.FILTER       — enforce: only WHAT(trades.*) proceed
Segment[3]: BCA(tradie)  + End.S.VALIDATE     — tradie's node validates capability
Segment[4]: BCA(tradie)  + End.S.TICK         — tradie earns dispatch fee
```

The `End.S.DISPATCH` segment function changes the cell's active multicast group from the property vertical to the trades vertical. The dispatch envelope is a RELEVANT cell visible to both verticals via facet-scoped patches — the SRH records the cross-vertical transition as a provenance event.

### Grammar Licensing via RELEVANT Capability Tokens

Grammar licenses are RELEVANT Plexus capability tokens — permanent proof of purchase, presentable many times, never consumed. The license cell contains:

- Type: `plexus.capability.grammar_license` (RELEVANT)
- Owner: licensee's Plexus cert ID (offset 62)
- Payload: licensed WHAT prefix, marketplace signature, expiry block height (0xFFFFFFFF = perpetual)
- Signed by: Semantos marketplace cert

Verification is entirely local — no network call:

1. Device stores license token in NVS on purchase
2. `End.S.LICENSE` segment function reads WHAT prefix from in-transit cell
3. Looks up license token from NVS by WHAT prefix
4. Verifies device cert is in the license owner's cert tree (`OP_CHECKIDENTITY`)
5. Verifies marketplace signature (`OP_CHECKSIG` against embedded marketplace public key)
6. Checks expiry against current block height
7. Forward if valid, drop if not

**Why RELEVANT, not LINEAR:**

The business model is one-time purchase, own it outright. A LINEAR token would be consumed on first presentation — forcing re-purchase. RELEVANT means the license is permanent, presentable at every boot, on every mesh, as many times as needed. The anti-cloning protection comes from the Plexus cert chain, not from linearity: copying the license bytes to another device fails because that device has a different cert and `OP_CHECKIDENTITY` rejects it.

**Revocation** is a separate concern handled by a LINEAR cell:

```
plexus.capability.grammar_license  — RELEVANT (permanent proof of purchase)
plexus.capability.revocation       — LINEAR   (one-time irrevocable revocation event)
```

The license exists forever (it was issued, that's a fact). Revocation is a one-time event that consumes the right to use the license. `End.S.LICENSE` checks for both: license present AND no revocation consumed against it.

**Edge-cached attestation** for relay performance:

The full license check (NVS read + OP_CHECKSIG) runs once per device per mesh join. The entry node issues a RELEVANT attestation cell: "device BCA X holds a valid license for WHAT prefix Y, verified at time T, signed by entry node cert." Relay nodes cache this attestation and skip the full check for subsequent cells from the same device. Attestation TTL is configurable (default: 1 hour or 1000 cells).

### Multicast-Driven Vertical Installation

Adding a vertical to a node is:

1. `semantos install extension electroculture` — drops grammar + config
2. Node reads grammar, computes type hashes for each WHAT/HOW/INST triple
3. Node derives multicast group addresses from type hashes
4. Node joins those multicast groups on the mesh
5. Network layer routes matching traffic to the node automatically

No routing table changes. No infrastructure deployment. No coordinator. The type hash *is* the network address. The grammar *is* the routing configuration.

---

## Deliverables

### D34A.1 — Type-Hash Multicast Address Derivation (TypeScript + C)

**TypeScript**: New file `packages/protocol-types/src/multicast.ts`

```typescript
/**
 * Derive an IPv6 multicast group address from a WHAT/HOW/INST type triple.
 *
 * The address encodes type-hash projections in the group ID:
 *   ff03:WHAT[0:4]:HOW[0:4]:INST[0:4]:0000
 *
 * Supports hierarchical subscription via prefix:
 *   deriveMulticastGroup({ what: "depin.sensor" })          → ff03:WWWW:WWWW::
 *   deriveMulticastGroup({ what: "depin.sensor", how: "measure" }) → ff03:WWWW:WWWW:HHHH:HHHH::
 */
export function deriveMulticastGroup(axes: {
  what?: string;
  how?: string;
  inst?: string;
  scope?: number;  // RFC 4291 scope: 3=realm-local (default), 5=site-local, 8=org-local
}): string;  // returns IPv6 address string

/**
 * Parse a multicast group address back to type-hash prefix components.
 */
export function parseMulticastGroup(address: string): {
  whatPrefix: Buffer;  // 4 bytes (or zero if wildcard)
  howPrefix: Buffer;   // 4 bytes (or zero if wildcard)
  instPrefix: Buffer;  // 4 bytes (or zero if wildcard)
  scope: number;
};

/**
 * Check if a cell's type hash matches a multicast group (prefix match).
 */
export function cellMatchesGroup(
  cellTypeHash: Buffer,       // 32 bytes from cell header offset 30
  whatPath: string,
  howSlug: string,
  instPath: string,
  groupAddress: string,
): boolean;
```

**C** (ESP32): New file `esp32-hackkit/components/semantos/src/multicast_types.c`

Identical derivation using `host_sha256()`. Must produce the same multicast addresses as the TypeScript implementation for the same inputs.

### D34A.2 — BCA-SRv6 SID Encoding (TypeScript + C)

**TypeScript**: New file `packages/protocol-types/src/srv6.ts`

```typescript
/**
 * Encode a BCA + segment function + arguments into an SRv6 Segment ID.
 *
 * SID format: PREFIX:PREFIX:BCA:BCA:FUNC:ARGS:ARGS:ARGS
 */
export function encodeSRv6SID(opts: {
  prefix: Buffer;        // 4 bytes — routing prefix (network-specific)
  bca: Buffer;           // 8 bytes — BCA interface identifier
  func: SegmentFunction; // 1 byte — segment function code
  args: Buffer;          // 5 bytes — function arguments
}): string;  // returns IPv6 address string

/**
 * Decode an SRv6 SID back to components.
 */
export function decodeSRv6SID(sid: string): {
  prefix: Buffer;
  bca: Buffer;
  func: SegmentFunction;
  args: Buffer;
};

/**
 * Build an SRv6 Segment Routing Header from an ordered segment list.
 */
export function buildSRH(segments: SRv6Segment[]): Buffer;

export enum SegmentFunction {
  CREATE   = 0x01,
  VALIDATE = 0x02,
  TICK     = 0x03,
  ANCHOR   = 0x04,
  ATTEST   = 0x05,
  FILTER   = 0x06,
  METER    = 0x07,
  DISPATCH = 0x08,
}

export interface SRv6Segment {
  sid: string;           // IPv6 SID
  func: SegmentFunction;
  args: Buffer;
  certId?: string;       // resolved Plexus cert for this BCA
}
```

**C** (ESP32): New file `esp32-hackkit/components/semantos/src/srv6_sid.c`

Identical encoding. SID construction uses the existing `bca.zig` derivation (called via WASM host import or precomputed at boot).

### D34A.3 — Segment Function Dispatch (C, ESP32)

New file: `esp32-hackkit/components/semantos/src/srv6_functions.c`
New header: `esp32-hackkit/components/semantos/include/srv6_functions.h`

Registers segment functions in the `host_call_by_name` dispatch table:

```c
// Dispatch table for SRv6 segment functions
static const srv6_func_entry_t srv6_dispatch[] = {
    { "srv6.validate",  srv6_func_validate  },  // OP_CHECKLINEARTYPE
    { "srv6.tick",      srv6_func_tick      },  // MFP channel tick
    { "srv6.anchor",    srv6_func_anchor    },  // anchor_submit()
    { "srv6.attest",    srv6_func_attest    },  // sign with device cert
    { "srv6.filter",    srv6_func_filter    },  // type hash prefix match
    { "srv6.meter",     srv6_func_meter     },  // AFFINE bandwidth slot
    { "srv6.dispatch",  srv6_func_dispatch  },  // cross-vertical forward
};
```

Each function receives the in-transit cell (1024 bytes) and operates on it using the cell engine kernel functions (`semantos_kernel_load_script`, `semantos_kernel_execute`, etc.).

`srv6_func_validate`: loads `OP_CHECKLINEARTYPE` script, executes against cell header, returns pass/fail.

`srv6_func_tick`: calls `depin_channel_tick()` from Phase 33A, attaches tick proof to cell metadata.

`srv6_func_anchor`: calls the anchor adapter's `anchor_submit()` with the cell's state hash.

`srv6_func_attest`: computes `SHA256(cell_bytes)`, signs with device cert (via identity adapter), appends attestation to cell metadata.

`srv6_func_filter`: reads cell type hash at offset 30, compares first 4 bytes against the ARGS prefix. Returns pass (forward) or drop.

`srv6_func_meter`: consumes an AFFINE bandwidth slot cell. If no slot available, returns drop (backpressure).

`srv6_func_dispatch`: changes the active multicast group by rewriting the destination address from source WHAT prefix to target WHAT prefix in ARGS.

### D34A.4 — SRH Construction from Mesh Topology (C, ESP32)

New file: `esp32-hackkit/components/semantos/src/srv6_srh.c`
New header: `esp32-hackkit/components/semantos/include/srv6_srh.h`

When a source device creates a cell and publishes, it builds the SRH:

1. Query the Thread mesh routing table for the path to the border router
2. For each hop, look up the device's BCA (from mesh neighbor table + cert cache)
3. Assign segment functions per hop based on node role:
   - Source node: `End.S.CREATE`
   - Relay nodes: `End.S.VALIDATE` + optionally `End.S.TICK`
   - Border router: `End.S.ANCHOR`
4. Encode each hop as an SRv6 SID
5. Pack into Segment Routing Header (SRH, IPv6 extension header type 43)

The SRH is attached to the 6LoWPAN packet carrying the cell. Each hop processes its segment, decrements Segments Left, and forwards.

### D34B.1 — Multicast Group Manager (TypeScript)

New file: `packages/protocol-types/src/multicast-manager.ts`

Manages multicast group memberships for a node based on installed verticals:

```typescript
export class MulticastGroupManager {
  /**
   * Derive and join multicast groups for a vertical grammar.
   * Called when a vertical extension is installed.
   */
  joinVertical(grammar: PaskianGrammar, networkAdapter: NetworkAdapter): void;

  /**
   * Leave all multicast groups for a vertical.
   * Called when a vertical extension is uninstalled.
   */
  leaveVertical(verticalId: string): void;

  /**
   * Get all active multicast group memberships.
   */
  getGroups(): MulticastMembership[];

  /**
   * Check if this node receives a given type.
   */
  receivesType(whatPath: string, howSlug?: string, instPath?: string): boolean;
}
```

### D34B.2 — SRH Provenance Extractor (TypeScript)

New file: `packages/protocol-types/src/srv6-provenance.ts`

Extracts provenance information from an SRH:

```typescript
export interface SRv6Provenance {
  /** Ordered list of hops from source to destination. */
  hops: SRv6Hop[];
  /** Source device BCA and cert. */
  source: { bca: string; certId: string };
  /** Destination device BCA and cert. */
  destination: { bca: string; certId: string };
  /** Total hop count. */
  hopCount: number;
  /** Operations performed at each hop. */
  operations: { func: SegmentFunction; hop: number; certId: string }[];
  /** Payment ticks accumulated along the path. */
  totalTickSatoshis: number;
}

export interface SRv6Hop {
  sid: string;
  bca: string;
  certId: string;
  func: SegmentFunction;
  args: Buffer;
  /** Timestamp if In-situ OAM was present. */
  timestamp?: number;
}

/**
 * Extract provenance from an SRH buffer.
 * Resolves BCAs to cert IDs via the identity adapter.
 */
export async function extractProvenance(
  srh: Buffer,
  identityAdapter: IdentityAdapter,
): Promise<SRv6Provenance>;

/**
 * Anchor provenance to BSV alongside cell data.
 */
export async function anchorProvenance(
  provenance: SRv6Provenance,
  cellStateHash: Buffer,
  anchorAdapter: AnchorAdapter,
): Promise<AnchorProof>;
```

### D34C.1 — Cross-Vertical Dispatch (TypeScript)

New file: `packages/protocol-types/src/dispatch.ts`

Implements the dispatch envelope as a cell that crosses vertical boundaries:

```typescript
export interface DispatchEnvelope {
  /** Source vertical (e.g. "property"). */
  sourceVertical: string;
  /** Target vertical (e.g. "trades"). */
  targetVertical: string;
  /** Source WHAT prefix (multicast group). */
  sourceGroup: string;
  /** Target WHAT prefix (multicast group). */
  targetGroup: string;
  /** The cell being dispatched (1024 bytes). */
  cellBytes: Uint8Array;
  /** SRH with End.S.DISPATCH segment at the boundary. */
  srh: Buffer;
  /** Facet-scoped patches visible to source vertical. */
  sourcePatches: string[];
  /** Facet-scoped patches visible to target vertical. */
  targetPatches: string[];
}

/**
 * Create a dispatch envelope that routes a cell from one vertical to another.
 * Builds the SRH with End.S.DISPATCH at the boundary router.
 */
export function createDispatchEnvelope(opts: {
  cell: Uint8Array;
  sourceVertical: string;
  targetVertical: string;
  boundaryRouter: string;  // BCA of the node that handles the dispatch
  sourceFacets: string[];
  targetFacets: string[];
}): DispatchEnvelope;
```

### D34C.2 — Vertical Extension Network Wiring

Modify: `packages/protocol-types/src/adapters/create-network-adapter.ts` (or create)

When a vertical extension is installed, the network adapter automatically:
1. Computes multicast group addresses for all types in the grammar
2. Joins those groups on the local mesh / overlay
3. Registers `End.S.FILTER` rules for type-hash prefix matching
4. Announces vertical availability to the mesh (RELEVANT `sovereignty.node.vertical` cell)

### D34D.1 — Generalised Grammar-to-Network Mapping (TypeScript)

New file: `packages/protocol-types/src/grammar-network.ts`

The function that makes any grammar network-routable:

```typescript
/**
 * Given a vertical grammar, derive all network configuration:
 * - Multicast group addresses for each type
 * - SRv6 filter rules for type-hash prefixes
 * - Default segment function chains per linearity class
 * - Payment rates per segment function (from anchor policy)
 */
export function deriveNetworkConfig(grammar: PaskianGrammar): VerticalNetworkConfig;

export interface VerticalNetworkConfig {
  verticalId: string;
  /** Multicast groups to join (one per type in grammar). */
  groups: { typePath: string; address: string; linearity: Linearity }[];
  /** SRv6 filter rules (one per WHAT prefix). */
  filters: { whatPrefix: Buffer; action: 'accept' | 'drop' }[];
  /** Default segment function chains by linearity class. */
  defaultChains: Record<Linearity, SegmentFunction[]>;
  /** Payment config from anchor policy. */
  paymentConfig: {
    tickSatoshisPerHop: number;
    anchorBatchInterval: number;
    requireAnchorOn: string[];
  };
}
```

Default segment function chains by linearity:

```
LINEAR cells:   CREATE → VALIDATE → TICK → ANCHOR
                (must prove consumption, must pay, must anchor)

AFFINE cells:   CREATE → VALIDATE → METER
                (can be dropped, bandwidth-gated)

RELEVANT cells: CREATE → ATTEST
                (duplicable, just needs witness signature)
```

These defaults can be overridden per-type in the grammar config.

### D34D.2 — Integration Tests: Grammar → Multicast → SRv6 → Provenance

End-to-end test that:
1. Loads the DePIN grammar (Phase 33A)
2. Derives multicast group addresses for all 10 DePIN types
3. Simulates a sensor reading cell publication
4. Builds SRH with three hops (sensor → relay → gateway)
5. Processes segment functions at each hop
6. Extracts provenance from the SRH
7. Verifies: type hash in cell matches multicast group, BCAs in SRH resolve to certs, tick proofs are valid, provenance chain is complete

Also test with the Paskian grammar and a hypothetical trades grammar to prove generalisation.

---

## Phase Decomposition

```
Phase 34A: D34A.1–D34A.4  (multicast derivation + SRv6 SID encoding + segment
                            functions + SRH construction — the core primitives)

Phase 34B: D34B.1–D34B.2  (multicast group manager + SRH provenance extractor
                            — the TypeScript management layer)

Phase 34C: D34C.1–D34C.2  (cross-vertical dispatch + vertical network wiring
                            — the dispatch envelope pattern)

Phase 34D: D34D.1–D34D.2  (grammar-to-network mapping + integration tests
                            — the generalisation proof)

Phase 34E: D34E.1–D34E.6  (Paskian learning over mesh DAG — topology learning,
                            sensor correlation, routing feedback, TSP approximation)
```

34A is the foundation — can't start anything else without it.
34B depends on 34A (uses multicast derivation + SID encoding).
34C depends on 34B (dispatch uses multicast group manager).
34D depends on all three (integration tests exercise the full stack).
34E depends on 34B (needs provenance extractor) + Paskian core.

34A and Phase 33A can run in parallel (33A is adapters + grammar, 34A is network primitives).

```
Phase 33A ──────────┐
(DePIN grammar +    │
 ESP32 adapters)    ├──→ Phase 33B (wire DePIN to Phase 34 network)
                    │
Phase 34A ──→ 34B ──→ 34C ──→ 34D
(SRv6 +      (mgr +  (cross-  (grammar→
 multicast +  prove-   vertical  network     ──→ 34E
 seg funcs)   nance)   dispatch) general)       (Paskian mesh
                 │                               learning + TSP
                 └───────────────────────────→    approximation)
```

---

## Generalisation Proof

Phase 34D must demonstrate that the following verticals can derive network configuration from grammar alone:

| Vertical | Grammar Source | Types | Expected Behaviour |
|----------|---------------|-------|--------------------|
| **DePIN** | `paskian/src/depin-grammar.ts` (Phase 33A) | 10 | LINEAR readings → VALIDATE+TICK+ANCHOR chain |
| **Paskian** | `paskian/src/grammar.ts` (existing) | 9 | LINEAR pruning → VALIDATE+ANCHOR; RELEVANT nodes → ATTEST |
| **Trades** | `configs/extensions/trades-services.json` | 7 | LINEAR job intake → VALIDATE+TICK; RELEVANT profile → ATTEST |
| **Electroculture** | (defined in test) | 12 | LINEAR readings → VALIDATE+TICK+ANCHOR; RELEVANT trial config → ATTEST |

If `deriveNetworkConfig()` produces correct multicast groups, filter rules, and segment function chains for all four grammars — with no grammar-specific code — the generalisation is proved.

---

## Relationship to Existing Architecture

### NetworkAdapter Interface (Phase 26D)

Phase 34 does not replace the NetworkAdapter interface. It extends it:

- `NetworkAdapter.publish()` now builds an SRH and publishes to the type-derived multicast group
- `NetworkAdapter.subscribe()` now joins multicast groups derived from type hashes
- `NetworkAdapter.resolve()` now queries by multicast group membership
- `NetworkAdapter.resolveBCA()` now decodes SRv6 SIDs to cert IDs

A `StubNetworkAdapter` ignores SRv6 entirely (in-memory pub/sub, no SRH). A `BsvOverlayNetworkAdapter` doesn't use SRv6 (overlay topics, not multicast). An `OpenThreadNetworkAdapter` (Phase 33B) uses SRv6 natively.

The adapter interface remains the boundary. Phase 34 adds capabilities; it doesn't break the abstraction.

### Cell Header (Unchanged)

Zero changes to the 256-byte cell header. The type hash at offset 30 already contains the composite hash. The multicast group address is derived from it, not stored in it. The SRH is an IPv6 extension header, not a cell header field.

### Taxonomy (Unchanged)

Zero changes to the six-axis taxonomy. WHAT/HOW/WHY are already encoded in the type hash. WHERE/WHEN/WHO are already in the cell header and payload. Phase 34 just makes five of the six axes visible at the network layer.

---

## Commercial Context

Phase 34 is the infrastructure that makes the extension marketplace a network:

```
Without Phase 34:
  Extension = grammar + local type validation
  Network = manual overlay topic subscription
  Cross-vertical = application-layer routing

With Phase 34:
  Extension = grammar → automatic multicast groups + SRv6 routing + payments
  Network = type-routed mesh with per-hop provenance
  Cross-vertical = SRv6 dispatch envelope with facet-scoped visibility
```

Revenue impact:
- **Extension marketplace**: every extension automatically gets network routing. The $29-$79 extension price now includes "plug into the global type-routed mesh" — not just local type validation.
- **MFP micropayments**: `End.S.TICK` means every relay hop earns BSV. Node operators running relay infrastructure earn per-cell, per-hop. This is the DePIN model generalised to all verticals.
- **Gateway operators**: border routers that anchor to BSV and handle cross-vertical dispatch earn settlement fees. Same model as Plexus Node but for mesh infrastructure.
- **Data consumers**: subscribe to multicast groups by type hash. Pay per-cell via MFP channel to the publishing node. The type system is the access control — if you can compute the multicast group address, you can subscribe.

---

## Next Phase

Phase 35 (future): Geo-aware routing. The WHERE axis (geohash in cell payload) influences multicast tree construction — cells from nearby devices route through local subtrees before reaching the backbone. Uses the shomee-era `GeoHashUtils.ts` as design reference. Enables "show me all sensor readings within 5km" as a network-layer query.
