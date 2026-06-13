---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.675708+00:00
---

# MNCA Layer-Collapse Demo — implementation brief

**Status**: paste-ready brief for the post-U.2 demo build-out.
**Target**: 6 weeks, with weekly demoable milestones.
**Depends on**: U.2 mesh (PR #528) merged or rebased onto.
**Companion**: `U2-PI-FEDERATION-TESTBED-RUNBOOK.md` (the substrate this builds on).

---

## §1 — The thesis, said precisely

One 1024-byte canonical cell traverses **every system layer** (storage, memory, network transport, compute, identity, money) on **three hardware classes** (ESP32-C6 RISC-V, Allwinner H5 ARM, Apple Silicon), with **source routing** baked into spare header bytes, **per-hop payment** via pushdrop UTXO spends, and **permanent anchoring** to BSV. The cell is never decoded into a different representation at any boundary — it's always the same 1024 bytes.

The demonstrable artifact: a MNCA (Multi-Neighborhood Cellular Automaton) running distributed across all three hardware tiers, with every state transition visible in a unified dashboard that shows the cell as it actually exists in storage, memory, transport, compute, identity, and money simultaneously.

The IPv6 Forum + BSV Blockchain pairing (Ladid 2026) is made physically true: IPv6 multicast (+ SRv6 segment routing) at the wire, BSV at the persistence layer, canonical cells as the lingua franca, $0 commodity hardware as the substrate.

---

## §2 — The cell header reservations

Layout from `core/cell-engine/src/constants.zig` (256-byte header, 768-byte payload):

```
Offset  Size   Field                       Status
------  ----   -----                       ------
0       16     MAGIC                       used
16      4      LINEARITY                   used
20      4      VERSION                     used
24      4      FLAGS (domain flags)        used
28      2      REF_COUNT                   used
30      32     TYPE_HASH                   used
62      16     OWNER_ID                    used
78      8      TIMESTAMP                   used
86      4      CELL_COUNT                  used
90      4      PAYLOAD_TOTAL               used
94      2      *** RESERVED ***            available
96      32     PARENT_HASH                 used
128     32     PREV_STATE_HASH             used
160     64     *** RESERVED ***            available  ← this is the SRv6 region
224     32     DOMAIN_PAYLOAD_ROOT         used
256     768    PAYLOAD                     used
```

### §2.1 — The 64-byte routing region (offset 160–223)

Proposed sub-layout (call it `cell-routing-v1`):

```
Offset (in header)  Size   Field                       Purpose
------              ----   -----                       -------
160                 4      ROUTING_VERSION             u32 = 1 currently; sentinel = 0 means "unrouted/legacy"
164                 4      ROUTING_FLAGS               bit 0 = priority; bit 1 = anchor-on-arrival;
                                                       bit 2 = batchable; bit 3 = uses-pushdrop-payment
168                 4      SEGMENTS_LEFT               u32 — hops remaining
172                 4      HOP_COUNT_BUDGET            u32 — initial TTL; for loop detection
176                 8      FLOW_LABEL                  u64 — for ECMP / dashboard correlation; matches IPv6 flow-label semantics
184                 16     NEXT_HOP_BCA                16-byte Bitcoin Cell Address (BCA) of next hop — the substrate's
                                                       equivalent of "next IPv6 address". A node's BCA derives from
                                                       its identity pubkey per Plexus canon.
200                 16     FINAL_DEST_BCA              16-byte BCA of final destination
216                 4      ROUTING_CHECKSUM            CRC-32 over bytes 160..215 (detect in-flight tampering of
                                                       routing fields; HMAC at framing layer also covers this)
220                 4      RESERVED                    zero-padded for future expansion
```

### §2.2 — The 2-byte gap (offset 94–95)

Smaller, used for: `ROUTING_MODE` (u8) + `PRIORITY` (u8). Routing mode = {0 = unrouted, 1 = source-routed via the 64-byte region above, 2 = anycast, 3 = multicast-with-pruning, etc.}. Priority is a 0–255 traffic-class value (think DiffCode / DSCP analogue).

Two-byte semantics matter for fast classification at the dispatcher — before even parsing the 64-byte routing region, a hop can decide whether this cell needs SRv6-style processing at all.

### §2.3 — The merkle-path-root question

Todd's intuition: bake the merkle root of the full segments list into the header, so any hop can verify "yes, this segment-list matches what the originator signed", with cheap per-hop proof.

We could put a 32-byte path merkle root in the routing region, but that consumes half our 64 bytes. **Better option**: the path merkle root lives at offset 224 (DOMAIN_PAYLOAD_ROOT) when ROUTING_FLAGS bit 4 is set, overloading the existing field. Each hop, when popping its segment, presents a Merkle inclusion proof of (its segment, all later segments) against this root. The originator's signature (in the HMAC framing layer) covers this root + all routing fields, so the path itself is cryptographically committed.

This pattern: **the cell IS the source route, and the route IS the path proof.**

### §2.4 — IPv6 subnet hint (Todd's 16-bit suggestion)

The `NEXT_HOP_BCA` field (16 bytes) and `FINAL_DEST_BCA` field (16 bytes) ALREADY ARE 128-bit IPv6-like addresses in BCA form. We can use the first 64 bits of each as the IPv6 /64 subnet prefix and the second 64 bits as the interface identifier. So **the routing fields are already shaped as IPv6 addresses** and existing IPv6 routing tables / SRv6 segment lists naturally compose.

Bottom line: when the cell crosses the Pi cluster (IPv6 multicast), the `NEXT_HOP_BCA` /64 prefix is a hint to the kernel about which interface to send out (or which segment in an SRv6 SRH to pop). When the cell crosses ESP-NOW radio, the `NEXT_HOP_BCA` is a hint about which MAC to forward to (we maintain BCA→MAC mapping in each C6's contacts cell-DAG). Same field, different transport.

---

## §3 — PushDrop pattern: cells as spendable UTXOs

### §3.1 — The mapping

A pushdrop UTXO is a BSV transaction output whose locking script pushes data onto the stack and then drops it, leaving a normal signature-verify script as the spending condition. Pattern: `<data> OP_DROP <pubkey> OP_CHECKSIG`.

For our cells: the 1024-byte cell becomes the `<data>` push. Anyone who controls the corresponding pubkey can spend the UTXO, but the cell bytes remain forever in the blockchain (in the transaction history).

```
locking script:  <cell_bytes_1024> OP_DROP <owner_pubkey> OP_CHECKSIG
```

So each spendable cell carries:
- The cell's 1024 bytes (the canonical payload)
- An owner pubkey that controls future spends
- A satoshi amount (dust = 1 sat or anchor amount = whatever value the originator put in)

### §3.2 — What this unlocks

1. **Cells as money**. Channel-state commitments, per-hop forwarding payments, ad-hoc micropayments — they're all just cells, but the spendable-UTXO property makes them *economic objects on the chain*. No off-chain ledger required.

2. **Path payment via UTXO chain**. When a cell traverses N hops with per-hop payment, the originator pre-builds N pushdrop outputs (one per hop). Each hop's "payment" is the spend of one of these outputs that's locked to its own pubkey. The cell's `NEXT_HOP_BCA` field tells each hop which UTXO is theirs.

3. **Audit trail**. Every cell that became a UTXO is permanently in the blockchain's tx history. You can reconstruct the substrate's full state at any past moment by replaying these txs.

4. **Federation across networks**. Two skyminers in different cities don't need a shared cluster or a federation protocol — they share BSV. Cells minted on one cluster are visible to the other through the chain.

### §3.3 — Cost analysis (BSV fees = 100 sats/KB, per Todd 2026-05-21)

| Cell category | Volume | On-chain cost/day |
|---|---|---|
| Snapshots (~0.4/sec × 1 KB each) | ~34560 cells/day × 100 sats | ~$0.70/day |
| Rule changes / perturbations | Sporadic | < $0.10/day |
| Channel commitments (~5/sec per channel) | depends on channel count | $0.10–$1/channel/day |
| All MNCA traffic on-chain (~30/sec) | 2.6M cells × 100 sats | ~$50/day |
| Merkle-rolled high-volume cells (1 root/min) | 1440 roots × 100 sats | <$0.05/day |

At these rates, **cells are genuinely affordable as first-class blockchain objects**. The architecture flips from "blockchain is expensive durability tier we batch into" to "the chain IS the cell store, full stop."

---

## §4 — Per-hop payment protocol (the IXP / cell-routed bandwidth pattern)

Borrowed from the conversation about port-forwarding-priority bandwidth, made concrete:

### §4.1 — Originator builds the routing

When a cell needs to traverse N hops with per-hop payment, the originator:

1. Generates the segments list = [BCA_1, BCA_2, ..., BCA_N, BCA_final]
2. Computes the path merkle root over the segments
3. For each hop i, constructs a pushdrop UTXO output locked to BCA_i's pubkey, with the cell's payment for that hop as the satoshi value
4. Builds a BSV transaction with N+1 outputs (N hops + 1 change-or-final-destination)
5. Sets the cell's routing region: NEXT_HOP_BCA = BCA_1, FINAL_DEST_BCA = BCA_final, SEGMENTS_LEFT = N, FLOW_LABEL = a random 64-bit identifier, ROUTING_FLAGS = uses-pushdrop-payment + priority-as-configured
6. Sets DOMAIN_PAYLOAD_ROOT = path_merkle_root (when ROUTING_FLAGS bit 4 is set per §2.3)
7. Signs the cell at the HMAC framing layer (covers all routing fields)
8. Broadcasts to the first hop

### §4.2 — Each hop processes

1. Receives cell on its inbound interface
2. Verifies HMAC (proves originator signed this exact routing payload)
3. Verifies ROUTING_CHECKSUM (proves routing region untampered in-flight)
4. Verifies NEXT_HOP_BCA matches own BCA (proves this hop is the intended recipient)
5. Verifies the pre-funded pushdrop UTXO exists in the blockchain and is unspent (via local SPV with anchored headers, or via ARC query)
6. Spends the pushdrop UTXO with own pubkey (the "payment" — atomic, on-chain proof of forwarding-service-rendered)
7. Pops own segment from the merkle path (provides inclusion proof, updates DOMAIN_PAYLOAD_ROOT to merkle root of remaining segments)
8. Sets NEXT_HOP_BCA = BCA_{i+1}, decrements SEGMENTS_LEFT
9. Decrements HOP_COUNT_BUDGET (loop detection)
10. Re-signs (new HMAC over updated routing region)
11. Forwards to next hop

### §4.3 — Final destination

Receives cell with SEGMENTS_LEFT = 0 and NEXT_HOP_BCA = own BCA. Verifies everything, processes payload (whatever the cell was actually for — MNCA snapshot delivery, conversation message, channel close, etc.).

### §4.4 — What this gives you

- **Each forwarded packet is paid for, on-chain, at the time of forwarding.** No subsequent reconciliation, no off-chain ledger, no trust required.
- **Forwarding service is a UTXO spend** — an SPV verifier can audit "did Pi 3 actually receive payment for forwarding cell X" by checking BSV's tx history.
- **Linearity at the substrate layer**: the cell is consumed (spent UTXO) at each hop; only the unspent forward is valid.
- **No central coordinator**: routing is fully baked into the cell. Any node can verify the cell's history independently.

---

## §5 — Hardware roles (per-device-class)

### §5.1 — ESP32-C6 (≈$4, 160 MHz RISC-V, 512 KB SRAM)

**Role**: edge sensors, actuators, micro-tile MNCA nodes, radio gateway.

- Hardware: button (input), light sensor (input), NeoPixel ring (output), USB-C for power + optional UART to Pi gateway
- Cells: signs/verifies via mbedTLS ECDSA-secp256k1 (proven in PR #501); cell-engine WASM (64 KB carve, per #525) runs the same canonical-cell verification
- Network: ESP-NOW broadcast for C6-to-C6, optional UART bridge to Pi for cross-fabric reach
- Workload examples:
  - Button → mint `mnca.perturb` cell → routes via radio + Pi-gateway + IPv6 multicast → arrives at MNCA tile owner Pi
  - Light sensor → mint `mnca.rule_param` cell → broadcast to all Pi tile owners
  - NeoPixel → subscribe to one Pi's tile snapshots, render as 8-bit pixel ring
  - Lightbulb-channel terminal: LED stays on while channel commitment cell is current — money moves while light is on

### §5.2 — Orange Pi Prime (≈$5, 1 GHz Cortex-A53 quad, 2 GB RAM, Gigabit Ethernet)

**Role**: MNCA tile compute, SRv6-routed forwarding hops, cell-store cache, BSV submitter, Pi-side radio gateway.

- Hardware: existing skyminer chassis (8 SBCs + PL-DGMK300 switch)
- Cells: cell-engine WASM full instance; multiple tile workers per Pi if compute allows
- Network: IPv6 multicast on `ff15::5e:1` (already shipped in U.2); UART bridge to attached C6 if Pi is a gateway
- Workload examples:
  - Owns a 32×32 (or larger) MNCA tile; computes next-state every tick; broadcasts edges + snapshots
  - Forwards SRv6-routed cells; verifies pushdrop payment to its BCA; spends the UTXO; updates routing region; emits
  - Maintains local LMDB cell-store cache of seen cells (for replay + SPV)
  - Acts as BSV submitter via wallet-headers cartridge + ARC for cells flagged for on-chain anchoring

### §5.3 — MacBook (M-series, big compute, big RAM)

**Role**: dashboard renderer, mesh-observer aggregator, operator wallet, replay UI, BSV broadcaster.

- Hardware: existing dev machine
- Cells: cell-engine WASM full instance
- Network: USB-C ethernet (`en8`) onto the skyminer LAN; static IP `192.168.0.50/24` (no default route via en8 — keeps Wi-Fi for internet)
- Workload examples:
  - mesh-observer collects telemetry from all nodes; renders unified live dashboard
  - Operator's wallet signs pushdrop UTXOs that fund forwarding; tracks UTXO state
  - BSV broadcasting endpoint via ARC adapter (already wired in wallet-headers cartridge)
  - Replay / time-travel UI: queries BSV by topic or txid, reconstructs cell stream, optionally re-broadcasts to multicast
  - Anchor-proof view: for any rendered MNCA state, shows the BSV tx + block height that anchors it

---

## §6 — The MNCA workload itself

### §6.1 — Tile geometry

8 Orange Pi Primes × 32×32 cells per tile = 256×256 grid total (8 tiles arranged 2×4). 64K cells × 8-bit state = 64KB of state distributed across the cluster. Each tile snapshot = 1024 bytes (exactly one cell's payload size — clean mapping).

Optionally: M C6s × 8×8 cells each get sub-tiles on the perimeter. Heterogeneous-compute version (Phase 2B from the previous scope).

### §6.2 — Rule

Slackermanz-style MNCA rule, parameterized via `mnca.rule_param` cells. Initial parameters: 3 concentric neighborhoods (r=1, r=3, r=7) with weighted sums and threshold transitions. Probably ~200 lines of WASM (compiled from C or Zig via the cell-engine toolchain).

### §6.3 — Tick + sync protocol

Every 100 ms:
1. Each tile owner computes next-state for its tile (~30 µs on Cortex-A53, ~10 ms on RISC-V C6)
2. Edge cells (outer 1-cell border, or wider if rule radius > 1) get broadcast as `mnca.edge` cell — payload = (tile_id, edge_direction, edge_cells_bytes)
3. Every 5 ticks (500 ms): full tile snapshot broadcast as `mnca.snapshot` cell — payload = (tile_id, tick_number, 1024-byte tile state)

### §6.4 — Visualization

Laptop dashboard subscribes to `mnca.snapshot` cells, renders a 256×256 grid on canvas/WebGL with the tile owner's BCA color-coded at each pixel's border. Optionally subscribes to `mnca.edge` for higher-frequency partial updates between snapshots.

### §6.5 — Why MNCA specifically

Right balance of compute / bandwidth / visual appeal. Slackermanz-style MNCAs produce beautiful emergent patterns that look unmistakably alive. Real distributed-compute workload (not toy). Naturally maps to multicast edge-sync. Generalizes — once MNCA cell shapes work, HRR vector cleanup messages and Pask conversation messages are the same shape with different payload. **MNCA is the warm-up for the broader vector-symbolic + cognitive substrate work.**

---

## §7 — Sequencing (6 weeks)

### Week 1 — MNCA on Pi cluster (substrate foundation)

**Goal**: 8 Pis running distributed MNCA, dashboard shows the grid evolving.

- `runtime/semantos-brain/tools/mnca-node/` — compute kernel + edge-sync + snapshot broadcast (~500 LOC)
- `core/protocol-types/src/mnca/` — cell type definitions for `mnca.edge`, `mnca.snapshot`, `mnca.perturb`, `mnca.rule_param` (~200 LOC)
- Extend `mesh-observer` (PR #521 already landed) with MNCA grid renderer (~300 LOC)
- Tests: tile next-state determinism, edge-sync correctness under packet loss
- Demo: power on, watch noise stabilize into pattern, manually inject `mnca.perturb` via CLI tool, watch ripples

### Week 2 — Cell routing region (header reservation + protocol)

**Goal**: cells carry SRv6-like source routing in their header bytes. Verified by routed cells flowing through pre-defined paths.

- `core/cell-engine/src/constants.zig` — add `HEADER_OFFSET_ROUTING_REGION`, `HEADER_SIZE_ROUTING_REGION` etc. per §2.1
- `core/cell-engine/src/routing.zig` (new) — parse/build/checksum/validate the routing region
- `core/protocol-types/src/cell-routing.ts` — TS mirror for tooling
- Update `udp_dispatcher.zig` to invoke routing logic when `ROUTING_MODE` byte at offset 94 indicates source-routed
- Tests: round-trip routing region; checksum tampering detected; merkle inclusion proof verifies
- Demo: route a cell A→B→C→D explicitly via routing region; each hop logs "I processed this cell"

### Week 3 — ESP32-C6 fold-in (heterogeneous compute)

**Goal**: C6 swarm participates in the mesh. Same cells, same crypto, three orders of magnitude of compute coexisting.

- `esp32-hackkit/components/mnca-gateway/` — Pi-attached C6 acts as ESP-NOW ↔ UDP-multicast bridge over UART (~300 LOC)
- `esp32-hackkit/examples/mnca_c6_edge/` — button + light-sensor + NeoPixel C6 firmware that mints/consumes MNCA cells (~400 LOC)
- Bake all relevant broadcast secrets into C6 partition at flash time so any C6 can verify any node's cells
- Phase 2B (optional): C6 owns a small (8×8) MNCA sub-tile, contributes compute alongside Pis
- Tests: cell round-trips between C6 and Pi (radio ↔ multicast); HMAC verified in both directions
- Demo: press a C6 button → MNCA grid shows a ripple at the corresponding tile

### Week 4 — BSV anchoring via pushdrop

**Goal**: selected cells become spendable UTXOs on BSV. Dashboard shows the anchor txid for any cell.

- `runtime/semantos-brain/tools/mesh-bsv-sink/` — subscribes to multicast, classifies cells (snapshot / commitment / rule_change → on-chain direct; edges → merkle-rolled), submits via wallet-headers cartridge ARC path (~400 LOC)
- Pushdrop locking script template + cell-to-pushdrop codec (~150 LOC)
- Merkle-roll worker for high-volume cells (~200 LOC)
- BSV overlay topic registration: `mesh.cells.mnca.*` for external indexer subscription (~100 LOC)
- Tests: round-trip cell → pushdrop tx → re-derive cell from tx; merkle inclusion proof verifies against on-chain root
- Demo: click any tile on the dashboard, see the BSV tx that anchors that tile's last 5 snapshots; click the txid, browser opens block explorer

### Week 5 — SRv6 segment routing on the IPv6 wire

**Goal**: cells with source routing get steered across the network via SRv6, not just multicast flood. Per-hop payment proofs visible.

- Pi-side: configure Linux kernel SRv6 (sysctl `net.ipv6.conf.all.seg6_enabled=1`) and wire the cell's routing region to SRv6 SRH on outbound
- Linux kernel SRv6 + user-space SRv6 control plane (lightweight; no full BGP needed for an 8-node testbed)
- `mnca-node` reads ROUTING_FLAGS at offset 95; when source-routed-via-IPv6, emits cell with appropriate SRH; when not, falls back to multicast
- Per-hop pushdrop UTXO spend at each forwarding step (consumes the originator's pre-built UTXO output, broadcasts the spend)
- Tests: route MNCA cell A→C→F→H explicitly; each hop's BSV-spent UTXO is visible on-chain
- Demo: route a perturbation cell through 5 specific Pis in a specific order; dashboard shows the path; block explorer shows the 5 UTXO spends as separate txs

### Week 6 — Polish + recording

**Goal**: recordable polished demo. Documentation. Brief and runbook updated.

- Dashboard "all 6 layers" view per cell: storage / memory / network / compute / identity / money — each cell rendered with its current location at each layer
- Recordable demo storyboard (script): boot cluster, watch MNCA stabilize, button-press perturbation, light-sensor rule change, route a cell explicitly via SRv6, watch its UTXO spend chain on-chain, replay last 5 minutes from blockchain alone
- `docs/prd/MNCA-LAYER-COLLAPSE-RUNBOOK.md` — operator-facing runbook
- Final brief update with lessons learned

---

## §8 — File-level plan

| Phase | New / modified files | LOC | Notes |
|---|---|---|---|
| Week 1 | `runtime/semantos-brain/tools/mnca-node/{main,kernel,sync}.zig` | ~500 | MNCA worker per Pi |
| Week 1 | `core/protocol-types/src/mnca/{edge,snapshot,perturb,rule_param}.ts` | ~200 | Cell type definitions |
| Week 1 | `runtime/mesh-observer/` (extend) | ~300 | MNCA grid renderer |
| Week 2 | `core/cell-engine/src/{constants.zig,routing.zig}` | ~250 | Routing region parse/build/checksum |
| Week 2 | `core/protocol-types/src/cell-routing.ts` | ~150 | TS mirror |
| Week 2 | `runtime/semantos-brain/src/udp_dispatcher.zig` (extend) | ~80 | Source-routed dispatch path |
| Week 3 | `esp32-hackkit/components/mnca-gateway/{cell_uart_bridge,esp_now_glue}.c` | ~300 | Radio↔UDP gateway |
| Week 3 | `esp32-hackkit/examples/mnca_c6_edge/main.c` | ~400 | Sensor/actuator firmware |
| Week 4 | `runtime/semantos-brain/tools/mesh-bsv-sink/{main,classifier,pushdrop_codec}.zig` | ~500 | BSV anchor service |
| Week 4 | `cartridges/bsv-anchor-bundle/brain/zig/src/pushdrop_template.zig` (new) | ~150 | Locking script builder |
| Week 5 | Pi-side SRv6 kernel config + Linux netlink glue (Zig wrapper) | ~300 | SRv6 SRH emission |
| Week 5 | Per-hop pushdrop spend logic | ~200 | UTXO spend at each hop |
| Week 6 | Dashboard six-layer view | ~400 | Frontend |
| Week 6 | `docs/prd/MNCA-LAYER-COLLAPSE-RUNBOOK.md` | docs | Operator runbook |

**Total: ~3700 LOC + docs. ~6 working weeks for one engineer at a sustained pace.**

---

## §9 — Open architectural questions to resolve in week 1

1. **BCA derivation for non-brain nodes** (C6, laptop). The existing BCA model derives from an operator's identity pubkey. For C6s and laptops participating in routing, we need a per-device BCA mapping. Option A: each device gets its own BCA derived from its broadcast secret + device serial. Option B: devices act under a delegated BCA (the operator delegates a sub-identity for the device). **Recommendation: Option A for simplicity in v1; revisit when Plexus identity layer lands.**

2. **Linux kernel SRv6 vs cell-level routing only**. SRv6 is an IPv6 kernel feature that requires sysctl + iproute2 setup. For the 8-Pi testbed, configuring it is one-time. For C6s (no full Linux), SRv6 isn't an option — they rely on cell-level routing in the header. **Recommendation: cell-level routing is mandatory (works on all transports); SRv6 is opportunistic gravy on Pi-to-Pi paths.**

3. **PushDrop spendability lifetime**. Once a hop spends its UTXO for forwarding, the cell-as-money for that hop is gone. But the cell-as-data persists in the tx history. We need a policy for "how long does the cell stay queryable" — probably indefinitely via BSV nodes / overlay indexers, but a local cache on the laptop / Pi cluster gives faster query. **Recommendation: 24-hour local cache, indefinite chain availability.**

4. **Multicast group vs source-routed dispatch**. When both are in play (cell has ROUTING_FLAGS source-routed bit set AND is broadcast on multicast), receivers should NOT process the cell if they're not the NEXT_HOP_BCA. **Recommendation: dispatcher filters by NEXT_HOP_BCA at receive time; non-target receivers drop silently. This adds a small CPU cost but enables source-routed unicast over multicast wire (useful for resilience: if SRv6 isn't set up, multicast still works).**

5. **Merkle proof storage**. The path merkle root is stored in DOMAIN_PAYLOAD_ROOT (when bit 4 of ROUTING_FLAGS is set), but the sibling proofs aren't in the header. Where? **Recommendation: in payload bytes 0–N at the start of PAYLOAD region, with an offset field somewhere indicating where the actual payload starts.**

---

## §10 — Connection to the broader Semantos roadmap

This brief doesn't introduce new canon — it composes existing canon in a single demoable artifact:

- **U.2 mesh** (PR #528) — provides the transport layer (IPv6 multicast on the Pi cluster)
- **Cell-engine WASM** (carved to 64KB per #525) — provides the compute substrate on C6
- **Wallet-headers cartridge** (V1, per `brain_reactor_v1_recovery_complete.md`) — provides the BSV broadcast path
- **Plexus identity** (70% Todd, per `plexus_ownership.md`) — provides the BCA-as-identity model
- **BCA-cert identity work** (parked, per `semantos_parked_identity_phase1b.md`) — the BRC-52 cert binding work that gives devices economic identities
- **Pushdrop pattern** — standard BSV idiom; no new crypto needed
- **SRv6** — standard IPv6 kernel feature; no new transport protocol needed

It also lights up future canon:
- HRR distributed memory becomes "same MNCA cell shapes with bigger payloads" — the warm-up is finished
- Pask-of-Pasks becomes "MNCA-style conversation cells, sourced-routed between Pask kernels"
- A future jam-room cartridge that uses cells-as-bandwidth-payments lands directly on this substrate
- Bitcoin-shard-proxy (lightwebinc) becomes the BSV data-plane cousin of this work — both running on the same Pis, different namespaces

---

## §11 — Why this matters publicly

For the BSV community: this is the first concrete demonstration of "the chain as the substrate's persistent memory, with cells as spendable economic objects, on hardware that costs nothing."

For the IPv6 Forum (Ladid): this is the Ladid thesis (IPv6-only + BSV Blockchain) embodied. Not slides. Actual SRv6, actual multicast, actual on-chain anchoring.

For the maker / SBC community: this is what an 8-Pi cluster + an ESP32 swarm can do when treated as one substrate instead of as separate gadgets.

For agentic-AI infrastructure: the substrate solves the "agents need identity, money, and bandwidth without permission" problem from first principles. The cell IS the agent's representation; the chain IS the agent's economic identity; the routing region IS the agent's path-priority.

For Semantos: this is the demo that proves the architecture's "layer collapse" claim with running hardware. Once it's recorded, every subsequent piece of the roadmap (HRR, Pask-federation, jam-room, oddjobz scaling) has a substrate to land on.

---

## §12 — Auto-merge authority + PR shape

Each weekly milestone lands as its own PR, branching off main:

| PR # (proposed) | Title | Reviewer focus |
|---|---|---|
| n+1 | feat(mnca): distributed MNCA on Pi cluster | Compute correctness, tile sync, dashboard render |
| n+2 | feat(cell): 64-byte routing region in header | Header layout compat, routing region parse/build, merkle proof |
| n+3 | feat(c6): ESP32-C6 fold-in to mesh | Radio gateway, sensor/actuator firmware, cross-fabric cells |
| n+4 | feat(bsv): pushdrop anchoring for mesh cells | Locking script template, tx submission, merkle-roll worker |
| n+5 | feat(routing): SRv6 + per-hop pushdrop payment | Kernel SRv6 wiring, UTXO spend logic, anchor-proof view |
| n+6 | docs + polish: layer-collapse runbook + demo storyboard | Documentation completeness, recordability |

Each PR builds on the previous. Each is independently demoable (per §7). Total ~6 weeks at a sustained working pace.

---

## §13 — Type-path source routing (BCA + typepath + sats = local-optimal route discovery)

A late-binding insight: combining the BCA identity mechanism (Ducroux 2023, arXiv 2311.15842 — what makes a BCA usable as a permanent IPv6-routable identity) with our cell's `TYPE_HASH` field at offset 30 and the per-hop pushdrop payment from §4 transforms the routing region from "where" into "where + what shape + what price". This is **type-path source routing**, and it collapses the centralized-routing problem into a distributed market.

### §13.1 — What's in the paper vs what's the extension

**From Ducroux (the foundation, §IV of the paper):**

A BCA's interface identifier is `Hash1(modifier || blockHeader || subnetPrefix || collisionCount || transaction)` where the transaction registers the host's public key on the BSV blockchain. The Bitcoin PoW secures the binding (~89 bits of security at current BSV difficulty). 32 modifiers per registration → 32 rotatable addresses per host per registration tx. Verification is just two Merkle proof checks + one hash — no live Bitcoin network connection required. **Every BCA in our routing region is a permanent, Bitcoin-anchored identity.**

**The extension we're proposing (not in the paper):**

The segments-list in the cell's payload carries `(BCA_i, TYPE_HASH_i)` pairs rather than bare BCAs. Each segment commits not just to "this hop is node BCA_i" but also "the cell arriving at BCA_i has type-hash TYPE_HASH_i". Combined with the pushdrop-per-hop payment from §4, each segment becomes a **contract**: BCA_i has been pre-paid in sats S_i to accept a cell of type TYPE_HASH_{i-1} and emit a cell of type TYPE_HASH_i.

### §13.2 — Layout of typed segments in the payload

When `ROUTING_FLAGS` bit 4 (path-in-payload) is set, the first portion of PAYLOAD (offset 256+) is structured as:

```
payload[0..1]                u16   number_of_segments N
payload[2..3]                u16   payload_starts_at (offset into payload where real cell payload begins)
payload[4..(4 + N*48 - 1)]   per-segment 48-byte tuples:
                                 - 16 bytes: BCA of the hop
                                 - 32 bytes: TYPE_HASH the cell should HAVE when arriving at this hop
payload[payload_starts_at..]  actual cell payload data
```

At N=3 hops that's 4 + 144 + 2 = 150 bytes of payload metadata, leaving 618 bytes for actual cell data. At N=6 hops we burn 292 bytes; still 476 bytes for payload. For deeper paths, the originator either uses continuation cells (8-byte continuation header per CONTINUATION_HEADER_SIZE constant) OR commits the longer path via merkle root and provides inclusion proofs per-hop.

### §13.3 — How a hop processes a typed segment

Building on §3's hop processing:

```
8b. After popping the segment, validate:
    expected_inbound_type = TYPE_HASH committed at this segment
    if cell.TYPE_HASH (offset 30) != expected_inbound_type:
        drop with "type mismatch" log
        forfeit the pushdrop UTXO (or trigger originator refund per §13.5)
    
9b. Look up local cell-engine handler for (expected_inbound_type → next_segment_type)
    if no handler:
        drop with "uncapable transform" log
        forfeit UTXO or trigger refund
    
10b. Execute the transform via the cell-engine WASM
     new_cell = transform(cell)
     new_cell.TYPE_HASH = next_segment_type
     // payload may be modified per the transform's logic
     // routing region is updated per §3 step 10
     
11b. Spend the pushdrop UTXO addressed to BCA_i (the payment for the transform)
12b. Emit the new cell on the outbound transport addressed to BCA_{i+1}
```

The transform is the unit of work being paid for. A hop that can't perform the transform doesn't accept the payment — the originator's UTXO remains unspent and becomes reclaimable after timeout (§13.5).

### §13.4 — The market for paid delivery

This is not "speculative routing through unknown nodes." It's **paid publish/subscribe with relays that self-select based on knowing what subscribers exist downstream.**

A type path implicitly defines a multicast group — the subscriber set is every node that has registered handlers for the transforms in that path. Relays know which subscriber sets they can reach (via their own peering / routing tables, established out-of-band or via cell-DAG contact entries).

Each potential forwarding node:

- **Advertises which type paths it can serve** (e.g., "I can deliver `mnca.snapshot → tile.injection` to the subscriber set reachable through me, for 50 sats per cell") via a published cell on a well-known overlay topic
- **Has a public history** of successful deliveries visible on-chain (every spend of a delivery-payment UTXO is recorded)
- **Sets its own prices** per (input_type, output_type) pair
- **Only accepts cells when it knows it can deliver to a downstream consumer** — no blasting packets speculatively, no "hoping the next hop is there"

Each potential originator:

- **Knows the type-path subscriber set it wants to reach** (e.g., "all nodes with `tile.injection` handlers")
- **Queries the overlay** for relays advertising delivery into that subscriber set
- **Selects** based on price + reputation + latency
- **Funds the path** by building a tx with N pushdrop outputs (one per hop, each locked to the hop's BCA)
- **Broadcasts the cell** with the typed segments list

Because relays only accept cells when they have a confirmed downstream consumer, **there's no "blasting packets for no reason"**. Forwarding capacity is allocated by knowing where the cells will land, not by speculation.

### §13.5 — Refund path via pre-signed nLockTime'd transactions (BSV-correct)

BSV restored the original Bitcoin protocol in Genesis; **OP_CHECKLOCKTIMEVERIFY is not available**. The refund path uses transaction-level `nLockTime` with pre-built signed refund transactions, the original pre-CLTV pattern.

**Funding tx (broadcast immediately, locks payment to the hop)**:
```
locking script:
  <cell_bytes_or_hash> OP_DROP
  <hop_pubkey> OP_CHECKSIG
```

A plain pushdrop pattern. The hop can spend with its pubkey whenever it's ready to claim payment for the forwarding it just performed. No timeout logic in this script.

**Refund tx (pre-built and signed offline at funding time, held by originator)**:
- Spends the funding UTXO back to the originator
- Has `nLockTime = T` set at the tx level
- Signed by the hop AND the originator BOTH as part of the funding handshake — the hop pre-authorizes the refund as part of accepting the offer

If the hop delivers within time T, it spends the funding UTXO first (with its own pubkey signature on a normal tx with `nLockTime = 0`). The refund tx becomes worthless because the UTXO is already spent.

If the hop fails to deliver by time T, the originator broadcasts the pre-built refund tx. Miners won't include it in a block until height/time ≥ T, but after that the refund is valid and the funds return.

**Result**: identical economic semantics to a CLTV-IF/ELSE script, but achieved via BSV-correct tx-level mechanisms. Works on BSV without needing protocol-incompatible opcodes.

For most paths in practice this refund mechanism never fires — because per §13.4, relays only accept when they're confident of delivery, and the market filters out unreliable relays via reputation. The nLockTime refund is the edge-case safety net, not the primary protection.

### §13.6 — Why this eliminates the routing-search problem entirely

The earlier framing of "TSP collapsed under economic forces" was conceptually off. **The right framing: subscription topology IS the routing.** There's no path search problem to solve, because relays already know which subscriber sets they can reach.

Classical packet routing (and TSP) assumes you need to find an optimal path through arbitrary nodes — NP-hard search, central solver needed, doesn't scale to N.

Paid-pubsub type-path routing inverts this:

1. **No path search exists at all** — relays advertise reachable subscriber sets per type path. Originator queries the advertised set and picks one. The "route" is just "follow the subscription tree from advertiser to subscriber".

2. **No central solver** — subscription state is distributed across relays who maintain it for their own peering reasons. Each relay knows only its own neighborhood.

3. **No speculative forwarding** — relays accept only cells whose type path matches subscriber sets they confirm they can reach. No "blasting packets and hoping someone consumes them."

4. **Scales linearly with N** — adding a new node adds new subscriber-set advertisements. Adding new type paths adds new market segments. No exponential search.

5. **Self-organizes via reputation + pricing** — popular subscriber sets attract more relays competing to serve them; pricing converges via market clearing. New type paths emerge as nodes register novel transform handlers.

The closest existing analogies:

- **BGP peering** — ISPs peer because they know their subscribers consume content from each other's networks. Routes aren't searched; they're advertised between peering AS's. Same shape.
- **CDN edge caching** — edge nodes cache what their users want. Discovery happens via subscription, not search. Same shape.
- **IP multicast at scale** — multicast group membership state defines who receives a stream. Routers maintain group membership; senders don't search for receivers. Same shape, except in our case the group identifier IS a type path.
- **NATS JetStream subjects** — publishers send to subjects; subscribers receive without sender needing to know who they are. Same shape.

**The substantive claim**: this isn't "TSP made tractable via market dynamics" — it's "TSP doesn't apply because subscription topology eliminates the search problem." The cell finds its destination not by exploring paths but by following the advertised subscription tree. Payment incentivizes relays to maintain accurate subscription state and to actually deliver what they've advertised.

The framing: **the cell rides a pre-existing subscription graph; the originator just pays the right relays to carry it down the graph.** Routes don't need to be discovered — they were declared in advance by relays announcing what they could deliver.

### §13.7 — What this means for the demo

For the MNCA demo specifically:
- A perturbation cell minted on a C6 doesn't need to know the full path to its destination tile
- Originator specifies the target tile owner BCA + target transform type ("turn this `mnca.perturb` into a `tile.injection` event")
- Network nodes advertise their transform capabilities (which tile owners can accept what perturbation types, at what prices)
- The cell finds its route through local decisions at each hop
- The on-chain trace of UTXO spends documents the actual path taken — visible in the dashboard

For the broader Semantos roadmap:
- HRR vector cleanup becomes a type-transform that any sufficiently-equipped node can offer
- Pask conversation moves become typed cell paths between conversation kernels
- Cartridge handlers in the brain are just transform offers in the market
- The agentic-AI Internet-of-Agents (per Ladid) becomes literal: each agent advertises what it can do, in what sats, with what reliability, and clients route by these terms

### §13.8 — Implementation impact on the brief

Adds to Week 2 (cell-level routing region):
- The 48-byte typed-segment structure in payload (~40 LOC for parse/build)
- Transform handler registry per node (~80 LOC, maps `(input_type, output_type) → wasm_handler`)
- Mismatch + capability check at receive time (~50 LOC)

Adds to Week 4 (BSV anchoring):
- Pushdrop with IF/ELSE timeout/refund logic (~30 LOC template)
- Refund worker for stale UTXOs (~150 LOC)

Adds to Week 5 (SRv6 + per-hop payment):
- Overlay topic for transform advertisements (~100 LOC)
- Originator-side route discovery (query overlay, select cheapest viable path) (~200 LOC)
- Dashboard visualization showing UTXO spends per cell, route taken, reputation per node

Total addition: ~650 LOC across the existing weeks. No new weeks needed; type-path source routing composes into the existing schedule without expanding it.

---

## §14 — Risks + mitigations

- **C6 verify throughput** (~100 secp256k1 verifies/sec per device): caps the effective tick rate when cells route through C6s. Mitigation: bundle multiple state updates per cell; reserve C6s for edge / actuator roles; let Pis handle the high-frequency compute.

- **Multicast loss under load**: UDP multicast is unreliable. For MNCA edge sync, missing one tick's edges = visible artifacts. Mitigation: heartbeat-driven NACK + retransmit OR accept the artifacts (they're aesthetically interesting, like a CA exhibiting natural decoherence).

- **PL-DGMK300 router quirks** (we hit HTTP MITM during U.2 bring-up): no impact at the L2 multicast layer, but if any tooling needs internet from a Pi, prefer HTTPS or skip apt entirely.

- **BSV fee volatility**: 100 sats/KB is the current rate; if fees rise, batching becomes more important. The merkle-roll pattern scales gracefully — just increase batch size.

- **ssh-key + agent gotchas** (from U.2 bring-up): `ssh-add` once per session; remember `BatchMode=yes` blocks passphrase prompts; the recovery dance for stuck Armbian first-boot dialogs is documented in `skyminer_first_pi_bringup.md`.

- **macOS pty exhaustion** (from U.2 bring-up): `sudo sysctl -w kern.tty.ptmx_max=999` if running many parallel ssh / expect.

---

## §15 — Locked design decisions (2026-05-22)

Decided after walking pros/cons/constraints, with the purity test *"the same 1024 bytes stay the thing at every layer, never re-encoded."* All four are the purity-maximal **and** lowest-risk-first choice.

### §15.1 — MNCA payload encoding

1. **Tile = cell.** The MNCA grid is domain-decomposed into tiles; each tile is one Semantos cell. Pis own many tiles, a C6 owns 1–2. (Matches the `mnca.tile.*` cell types.) Whole-grid-in-one-cell is kept only as a C6's tiny local grid.
2. **1 byte per grid-cell, raw in the payload.** State sits raw in the 768-byte payload — the bytes in SRAM **are** the tile **are** the wire bytes **are** the pushdrop UTXO data. No marshalling at any layer. (Bit-packed binary rejected — reintroduces encode/decode on the C6.)
3. **Integer / fixed-point arithmetic, not float.** Protects the determinism claim (same cell-engine WASM → bit-identical output on C6/Pi/Mac). The C6 is RV32 and may lack hardware FP; float would force FPU emulation + risk per-architecture drift.
4. **Baked-in halo + full-tile gossip for v1.** Each tile carries an R-wide border copied from neighbours; the whole tile is gossiped each tick on the validated U.2 multicast. Neighbourhood radius R trades against interior area in the fixed payload: `(I+2R)² ≤ 752`. The *typed-border-cells* alternative (halo exchange becomes routing + pubsub + paid traffic) is the **phase-2 flex** — it depends on transport + pubsub being wired first.

Tile payload layout (`core/protocol-types/src/mnca/tile.ts`):

```
0   u16 LE  tileX
2   u16 LE  tileY
4   u64 LE  tick
12  u8      width  W   (includes halo ring)
13  u8      height H   (includes halo ring)
14  u8      haloRadius R
15  u8      flags
16  W*H     state  (row-major, 1 byte/cell, 0..255)
```

`16 + W*H ≤ 768` → max ~27×27 incl. halo. Interior = `(W-2R)×(H-2R)`. Snapshot and tile.tick share this layout.

### §15.2 — Transport binding

1. **Multicast-and-filter, not SRv6 (yet).** Routed cells ride the validated `ff15::5e:1` multicast. On RX the dispatcher runs `processHop(cell, ownBca)`: `not-my-hop` → drop silently (§11.4), `forward` → re-transmit, `final-destination` → hand to the local cell-engine. Source-routed-unicast rides multicast wire; fine for 8 Pis. Real SRv6/routing tables = high-risk overkill for v1.
2. **Port `processHop` + routing-region accessors to Zig.** They're pure byte ops; run them the way the cell-engine already does (Zig on-device). The TypeScript implementations (`cell-routing.ts`, `mnca/hop-processing.ts`) become the **reference oracle** for the port — exactly the `bca.zig` ↔ TS-mirror pattern.
3. **ESP-NOW BCA→MAC deferred.** Pi-side multicast-and-filter needs no address resolution; the BCA→MAC table (contacts cell-DAG) is only needed when folding the C6 into routing.

**The cell is never reframed by transport.** ESP-NOW/UDP wrap-and-carry the 1024 bytes; the only mutation is the routing-region update `processHop` already performs.

### §15.3 — Implied sequencing

(a) MNCA tile codec + reference rule [pure types — landed]. (b) Zig port of routing + `processHop`. (c) Wire into `udp_dispatcher.zig` (multicast-and-filter) → flips **L3-F to ✓** and gives the demo its heartbeat: *MNCA runs distributed, real cells on the real mesh.* Money (`mesh-bsv-sink`) + dashboard + typed-border-cells follow.

---

End of brief. Auto-merge authority on each weekly PR contingent on green tests + reviewer approval. Report back with PR URL after each phase lands.
