---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/singularity-matrix.yml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.635134+00:00
---

# docs/canon/singularity-matrix.yml

```yml
# The Singularity Matrix — tracking artifact for the layer-collapse demo.
#
# Schema parallel to docs/canon/unification-matrix.yml.
# Rendered via docs/canon/render/singularity-to-roadmap.ts to
# docs/prd/SINGULARITY-ROADMAP.md.
#
# Each cell is `{ status: ✓|⚠|✗|n/a, deliverable: D-SG-..., note: "..." }`.
#
# Companion document: docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md.
#
# The demo's thesis: one 1024-byte canonical cell traverses every system
# layer (storage / memory / network / compute / identity / money) on three
# hardware classes (ESP32-C6 / Orange Pi Prime / MacBook), without ever
# being decoded into a different representation. This matrix tracks the
# 6 layers × 10 conformance axes; each ✓ cell is a verifiable claim that
# the layer-collapse thesis holds for that (layer, axis) pair.
#
# Status legend:
#   ✓   — implemented, tested, verifiable
#   ⚠   — partial / in progress / unverified
#   ✗   — not started
#   n/a — not applicable (e.g., a transport axis on a storage layer)
#
# Deliverable IDs use the D-SG-LN-X pattern (singularity, layer N, axis X).
# Existing deliverable IDs from other tracking matrices may be cross-referenced.

layers:
  - id: L1
    name: Storage
    note: |
      The cell as a persistent byte-string: NVS row on the ESP32-C6, LMDB
      row on the Orange Pi Prime, filesystem entry on the MacBook, and
      OP_DROP data carrier in a BSV pushdrop UTXO on-chain. The canonical
      claim: the same 1024 bytes serve as storage at every tier — no
      separate "serialized form".
    axes:
      A:
        status: "⚠"
        deliverable: D-SG-L1-A
        note: "C6 NVS partition holds cells; provisioning bakes broadcast secrets in. Cell-engine WASM (64 KB carve) can read NVS-stored cells per #525."
      B:
        status: "⚠"
        deliverable: D-SG-L1-B
        note: "Pi-side LMDB cell-store exists (V1 brain); not yet wired to receive mesh cells. Bridging the mesh-dispatcher → cell-store is Week 1 follow-up scope."
      C:
        status: "⚠"
        deliverable: D-SG-L1-C
        note: "Mac filesystem (mesh-node replay cache) holds cells. Replay tool (Week 6) will consume from this tier."
      D:
        status: "n/a"
        note: "Storage isn't a network transport."
      E:
        status: "n/a"
        note: "Storage isn't a radio transport."
      F:
        status: "✗"
        deliverable: D-SG-L1-F
        note: "Type-path source routing for stored cells (queries by typepath) — needs the routing region landed (Week 2)."
      G:
        status: "✗"
        deliverable: D-SG-L1-G
        note: "Paid pubsub overlay advertising stored-cell availability — needs the overlay topic landed (Week 5)."
      H:
        status: "✓"
        deliverable: D-SG-L1-H
        note: "Cell STORED on-chain as a pushdrop UTXO — the 1024-byte cell is the OP_DROP data carrier in tx a5277713…b2a78c (mainnet, 2026-05-22). The chain IS the cell store: same canonical bytes as NVS/LMDB/FS, now durably on BSV."
      I:
        status: "⚠"
        deliverable: D-SG-L1-I
        note: "Cell-journey dashboard (docs/demo/cell-journey.html) renders the cell's storage view — size + content-address (SHA-256) + the four storage tiers (NVS/LMDB/file/pushdrop). Live local-store/chain query is the remaining wiring."
      J:
        status: "⚠"
        deliverable: D-SG-L1-J
        note: "Content-addressing holds (cells hash deterministically); HMAC framing at rest still pending."

  - id: L2
    name: Memory
    note: |
      The cell as live bytes in RAM/SRAM. Same 1024 bytes whether the device
      is a 512 KB-SRAM RISC-V or a multi-GB Apple Silicon. The dispatcher,
      handlers, and cell-engine all operate on these in-memory cells via
      direct pointers — no parse/encode boundary inside the runtime.
    axes:
      A:
        status: "⚠"
        deliverable: D-SG-L2-A
        note: "C6 cell-engine WASM carved to 64 KB linear memory per #525; runs canonical cells in SRAM. MNCA-tile compute on C6 (Week 3) will exercise this end-to-end."
      B:
        status: "✓"
        deliverable: D-SG-L2-B
        note: "Pi-side mesh-node holds cells in process memory; cell-engine full instance available. Verified on 8-node cluster 2026-05-21."
      C:
        status: "✓"
        deliverable: D-SG-L2-C
        note: "Native macOS mesh-node holds cells in RAM. Same Mach-O binary as U.2 validation."
      D:
        status: "n/a"
        note: "Memory isn't a network transport."
      E:
        status: "n/a"
        note: "Memory isn't a radio transport."
      F:
        status: "⚠"
        deliverable: D-SG-L2-F
        note: "Routing-region typed accessors landed in protocol-types/src/cell-routing.ts (read/write + CRC-32). Dispatcher-side use is Week 2."
      G:
        status: "⚠"
        deliverable: D-SG-L2-G
        note: "Subscription state in memory — RelayAdvertisement type defined in protocol-types/src/overlay/. Per-node state tables still Week 5."
      H:
        status: "n/a"
        note: "Memory isn't on-chain durability."
      I:
        status: "⚠"
        deliverable: D-SG-L2-I
        note: "Cell-journey dashboard shows the in-memory view — the same 1024 bytes (same content-address as storage) the cell-engine reads/writes in place, no parse boundary. Live process-memory inspection hook pending."
      J:
        status: "✓"
        deliverable: D-SG-L2-J
        note: "Cells in memory carry HMAC + cellId + BCA — full cryptographic context preserved."

  - id: L3
    name: Network transport
    note: |
      The cell on the wire. Bytes 0..1023 are identical whether the frame
      crossed ESP-NOW radio between two C6s or IPv6 multicast between
      Orange Pis or a USB-C-to-Ethernet hop into a MacBook. Transport
      adapters wrap+unwrap; the cell never changes.
    axes:
      A:
        status: "✓"
        deliverable: D-SG-L3-A
        note: "C6 over ESP-NOW radio shipped in PR #501 (cell_frame + cell_sig + cell_radio). Real ECDSA-secp256k1 verified between two XIAO C6s."
      B:
        status: "✓"
        deliverable: D-SG-L3-B
        note: "Pi over IPv6 multicast: U.2 substrate (PR #528 MERGED 2026-05-21). 8-Pi cluster validated, 7 RX heartbeat lines per tick sustained."
      C:
        status: "✓"
        deliverable: D-SG-L3-C
        note: "MacBook over IPv6 multicast via USB-C-Ethernet adapter, en8 interface. Joined to ff15::5e:1, gossiping with cluster."
      D:
        status: "✓"
        deliverable: D-SG-L3-D
        note: "IPv6 multicast on ff15::5e:1 port 47100 carries cells with full HMAC framing. v6-only (IPV6_V6ONLY=1)."
      E:
        status: "✓"
        deliverable: D-SG-L3-E
        note: "ESP-NOW broadcast carries cells between C6s. Single canonical wire format across both transports."
      F:
        status: "✓"
        deliverable: D-SG-L3-F
        note: "A source-routed cell TRAVERSES the real mesh end-to-end: emit→forward→deliver over IPv6 multicast UDP (loopback), single-relay AND two-relay with segment rotation, payload bit-intact (routing_traversal conformance, 40/40 U.2 tests). routing.zig processHop runs on-device in the dispatcher cell_sync path; aarch64-buildable. 8-Pi field run is deployment of the same mechanism. UNIFIED as the Semantic Routing Substrate (unification-matrix U14, docs/design/SEMANTIC-ROUTING-SUBSTRATE.md): the SNS upgrade projects type-hash bits onto the IPv6 multicast address so native longest-prefix-match gives hierarchical semantic routing; D-SRS-sns-multicast-wire makes the (currently inert) header typeHash actually drive membership."
      G:
        status: "⚠"
        deliverable: D-SG-L3-G
        note: "Paid-pubsub MATCHING model complete: RelayServiceTable + emitAdvertisements (supply) + selectRelay cheapest-viable (demand), over the tm_mnca_relay_ads wire form. Only BRC-22 topic-manager submit/subscribe to real transport remains. Under the Semantic Routing Substrate (U14) this is the economic-pheromone layer: End.S.TICK per-hop payment drives Steiner/TSP convergence (Phase 34E), and coverage-guided type-path fuzzing (D-SRS-typepath-fuzzer) discovers the subscriber topology with MNCA state as the coverage signal."
      H:
        status: "n/a"
        note: "On-chain anchoring isn't a network transport."
      I:
        status: "⚠"
        deliverable: D-SG-L3-I
        note: "mesh-observer (PR #521) renders C6 mesh; Pi-cluster extension is Week 1-2 follow-up."
      J:
        status: "✓"
        deliverable: D-SG-L3-J
        note: "HMAC-SHA256 verified at every hop; per-sender broadcast secrets per schema u2-mesh-identity/v2."

  - id: L4
    name: Compute
    note: |
      The cell as input/output of cell-engine WASM. Same WASM module
      semantics across all three hardware classes — only the carve
      configuration differs (64 KB linear memory on C6, full on Pi/Mac).
      A cell computed-on at any tier produces a new cell that's
      indistinguishable from one computed at any other tier.
    axes:
      A:
        status: "⚠"
        deliverable: D-SG-L4-A
        note: "C6 cell-engine carved to 64 KB per PR #525, ON-device 2026-05-20. MNCA rule now PORTED to on-device Zig (mnca_tile.zig, 9 tests, oracle = tile.ts) — deterministic integer kernel, compiles for C6 (RV32, no FPU needed). Wiring stepTile into the cell path + on-C6 tick is next."
      B:
        status: "⚠"
        deliverable: D-SG-L4-B
        note: "Pi-side cell-engine WASM full instance available. MNCA rule ported to on-device Zig (mnca_tile.zig, oracle-checked, allocation-free double-buffer). Wiring the kernel into the node's tile-cell handler (run stepTile on delivered tile cells) flips this toward ✓."
      C:
        status: "⚠"
        deliverable: D-SG-L4-C
        note: "MacBook cell-engine full instance runs natively; the TS reference rule (mnca/tile.ts) IS the cross-hardware determinism oracle. MNCA dashboard-side rendering Week 1, dashboard compute Week 6."
      D:
        status: "✓"
        deliverable: D-SG-L4-D
        note: "A COMPUTED cell propagates via IPv6 multicast: relay runs stepTile → broadcasts the advanced tile → dest receives it (transform-on-hop conformance, real lo0 multicast). Same canonical cell in/out, never re-encoded."
      E:
        status: "⚠"
        deliverable: D-SG-L4-E
        note: "Compute results propagate via ESP-NOW — same canonical cells across radio. (Pi/multicast side proven; C6/ESP-NOW pending.)"
      F:
        status: "✓"
        deliverable: D-SG-L4-F
        note: "Transform-on-hop LIVE: a relay looks up a handler by the cell's type (cell_transform.zig registry, §13.4), runs the transform (stepTile, the MNCA kernel), rotates the type (tile.tick→snapshot), forwards the computed cell. Demonstrated over real multicast UDP (44/44 U.2 tests) — compute riding the routing. typeHash+payload sit outside the routing CRC window so the seal stays valid. This is the COMPUTE face of the Semantic Routing Substrate (U14): the MNCA tile IS the cell, the inner neighbourhood carries Knapsack queue-pressure (End.S.METER admission) and the outer neighbourhood carries Steiner/TSP pheromone trails — joint optimisation from the multi-neighbourhood rule. See docs/design/SEMANTIC-ROUTING-SUBSTRATE.md §3."
      G:
        status: "⚠"
        deliverable: D-SG-L4-G
        note: "Transform-capability supply table (RelayServiceTable keyed by input→output type) + emitAdvertisements turn a node's offered transforms into signed ads (injected signFn keeps crypto out of protocol-types). BRC-22 publish/subscribe pending. Under U14 the advertisement price (selectRelay cheapest-viable) is the Knapsack value-density signal; HRR/Pask retrieval (the chess-test operator) drives semantic nearest-neighbour selection over the type-path manifold (docs/design/SEMANTIC-ROUTING-SUBSTRATE.md §3.4)."
      H:
        status: "✓"
        deliverable: D-SG-L4-H
        note: "LIVE ON MAINNET — a computed MNCA snapshot is anchored as a pushdrop UTXO. tx a5277713454f17d746283f41158f39b26ac14debd11f7a719f866f872e23383c (1 output: 1 sat, ~1063B nonstandard = <1024B cell> OP_DROP <pubkey> OP_CHECKSIG), owner = recoverable BRC-42 edge[0] leaf (Plexus dispatch envelope). Built+signed by mesh-bsv-sink, Metanet :3321-funded, broadcast via ARC 2026-05-22. Verified on WhatsOnChain."
      I:
        status: "⚠"
        deliverable: D-SG-L4-I
        note: "MNCA grid visualizer live (docs/demo/mnca-grid.html + grid-viz.ts): a tile evolving in-browser under the canonical stepTile kernel (the on-chain oracle), state round-tripped through the cell payload codec each frame. Now wired to LIVE multi-tile mesh data — mesh-bridge.ts decodes real cell_sync tile broadcasts to SSE and the viz renders the composite N×M grid (6 real Orange Pi Prime tiles, 3×2, validated 2026-05-23; mcast-relay.py works around Bun's IPv6 addMembership bug; auto-falls-back to local sim). Next: multitenant scale to N≈100 (D-SRS-multitenant-spawn, two-tier ff15::5e:2↔5e:1 gateway) per docs/design/SEMANTIC-ROUTING-SUBSTRATE.md §2.2."
      J:
        status: "✓"
        deliverable: D-SG-L4-J
        note: "Compute is deterministic per cell-engine WASM contract — same input cell → same output cell on every tier."

  - id: L5
    name: Identity
    note: |
      The cell with embedded sender + BCA + ECDSA signature. Identity
      doesn't change across hardware classes — the same secp256k1 keys
      sign on C6 (via mbedTLS), on Pi (native crypto), and on macOS.
      BCAs derive deterministically per Ducroux (arXiv 2311.15842);
      BSV PoW secures the binding.
    axes:
      A:
        status: "✓"
        deliverable: D-SG-L5-A
        note: "C6 ECDSA-secp256k1 via mbedTLS shipped in PR #501. Real signature verify in radio mesh demo."
      B:
        status: "✓"
        deliverable: D-SG-L5-B
        note: "Pi-side cells carry sender_cell_id + HMAC. Per-sender broadcast secrets in U.2 schema v2."
      C:
        status: "✓"
        deliverable: D-SG-L5-C
        note: "MacBook mesh-node uses same crypto path. Validated 2026-05-21 on 8-node cluster."
      D:
        status: "✓"
        deliverable: D-SG-L5-D
        note: "BCAs work over IPv6 multicast — BCAs are 16-byte IPv6-shaped addresses derived from identity pubkey (Ducroux §IV)."
      E:
        status: "✓"
        deliverable: D-SG-L5-E
        note: "BCAs work over ESP-NOW — same address, looked up in contacts cell-DAG → MAC."
      F:
        status: "⚠"
        deliverable: D-SG-L5-F
        note: "Routing region carries NEXT_HOP_BCA + FINAL_DEST_BCA — typed accessors landed in cell-routing.ts. Dispatcher consumes them Week 2."
      G:
        status: "⚠"
        deliverable: D-SG-L5-G
        note: "RelayAdvertisement.relayBca + signature fields define identity-per-typepath schema. Advertise loop Week 5."
      H:
        status: "⚠"
        deliverable: D-SG-L5-H
        note: "BCA registration on BSV per Ducroux paper — paper provides foundation; impl is BCA registration tx + 32-modifier rotation. Needs Week 4."
      I:
        status: "⚠"
        deliverable: D-SG-L5-I
        note: "Cell-journey dashboard shows the identity view — type-hash @30, owner BCA @62, the secp256k1 + Ducroux-BCA note, and the on-chain anchor-tx link. Live per-cell sender resolution from mesh traffic pending."
      J:
        status: "✓"
        deliverable: D-SG-L5-J
        note: "secp256k1 ECDSA + HMAC + BCA derivation all present on every device class. Cryptographic invariants hold."

  - id: L6
    name: Money
    note: |
      The cell as a spendable economic object. Each cell can be wrapped as
      a BSV pushdrop UTXO (`<cell> OP_DROP <pubkey> OP_CHECKSIG`), making
      it directly spendable. Per-hop forwarding payments are pre-funded
      UTXOs the relay claims by spending. Channel-state commitments are
      cells that mint and consume sat-denominated value.
    axes:
      A:
        status: "✗"
        deliverable: D-SG-L6-A
        note: "C6 mints channel-state commitments + signs payment cells. Lightbulb-channel demo scope, not in current sequence."
      B:
        status: "⚠"
        deliverable: D-SG-L6-B
        note: "Pi-side wallet-headers cartridge broadcasts BSV txs via ARC. Bridging to mesh-cell-as-tx is Week 4."
      C:
        status: "⚠"
        deliverable: D-SG-L6-C
        note: "MacBook operator wallet signs pushdrop UTXOs for forwarding. Needs Week 4-5."
      D:
        status: "⚠"
        deliverable: D-SG-L6-D
        note: "Channel-state cells flow over IPv6 multicast like any other cell type. Just data transport at this layer."
      E:
        status: "⚠"
        deliverable: D-SG-L6-E
        note: "Channel-state cells flow over ESP-NOW radio. Same wire format."
      F:
        status: "⚠"
        deliverable: D-SG-L6-F
        note: "Per-hop payment plan now landed: buildPathPaymentPlans pre-builds one pushdrop funding output per hop (§4.1), index-aligned with processHop's spendSegmentIndex. Real tx build + broadcast (mesh-bsv-sink) Week 4."
      G:
        status: "⚠"
        deliverable: D-SG-L6-G
        note: "Pay-per-delivery market priced + matched: relays set pricePerCellSats per transform in RelayServiceTable; selectRelay returns cheapest valid + endpoint-matching. Real overlay query loop (BRC-22) pending."
      H:
        status: "✓"
        deliverable: D-SG-L6-H
        note: "Cell is a SPENDABLE economic object on mainnet — tx a5277713…b2a78c is a 1-sat pushdrop UTXO carrying the cell, owned by a recoverable BRC-42 leaf, built+signed by mesh-bsv-sink + broadcast via ARC (2026-05-22). Per-hop nLockTime refund (forwarding-payment.ts) remains plan-only — not yet exercised on-chain."
      I:
        status: "⚠"
        deliverable: D-SG-L6-I
        note: "Cell-journey dashboard shows the money view — the pushdrop locking-script size + shape + a live WhatsOnChain link to the mainnet anchor (a5277713…). Per-BCA sat balance + full UTXO-chain rollup pending."
      J:
        status: "✓"
        deliverable: D-SG-L6-J
        note: "Same secp256k1 crypto secures spendable UTXOs as secures cell signatures. Single keypair model."

```
