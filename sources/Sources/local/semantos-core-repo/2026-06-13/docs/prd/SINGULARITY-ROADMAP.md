---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/SINGULARITY-ROADMAP.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.694420+00:00
---

# Singularity Roadmap — the layer-collapse demo matrix

> Rendered from `docs/canon/singularity-matrix.yml`. Do not edit this
> document directly — edit the YAML and re-run
> `bun docs/canon/render/singularity-to-roadmap.ts > docs/prd/SINGULARITY-ROADMAP.md`.

Companion document: [`docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md`](./MNCA-LAYER-COLLAPSE-BRIEF.md).

## §1. The thesis

One 1024-byte canonical cell traverses every system layer — storage,
memory, network transport, compute, identity, money — on three hardware
classes (ESP32-C6, Orange Pi Prime H5, MacBook), without ever being
decoded into a different representation. The matrix below tracks the
**6 layers × 10 conformance axes**; each ✓ cell is a verifiable claim
that the layer-collapse thesis holds for that (layer, axis) pair.

## §2. The matrix

| Layer | A. C6 | B. Pi | C. Mac | D. IPv6mc | E. ESP-NOW | F. Routing | G. PubSub | H. BSV | I. Dash | J. Crypto |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **L1 Storage** | ⚠ D-SG-L1-A | ⚠ D-SG-L1-B | ⚠ D-SG-L1-C | n/a | n/a | ✗ D-SG-L1-F | ✗ D-SG-L1-G | ✓ D-SG-L1-H | ⚠ D-SG-L1-I | ⚠ D-SG-L1-J |
| **L2 Memory** | ⚠ D-SG-L2-A | ✓ D-SG-L2-B | ✓ D-SG-L2-C | n/a | n/a | ⚠ D-SG-L2-F | ⚠ D-SG-L2-G | n/a | ⚠ D-SG-L2-I | ✓ D-SG-L2-J |
| **L3 Network transport** | ✓ D-SG-L3-A | ✓ D-SG-L3-B | ✓ D-SG-L3-C | ✓ D-SG-L3-D | ✓ D-SG-L3-E | ✓ D-SG-L3-F | ⚠ D-SG-L3-G | n/a | ⚠ D-SG-L3-I | ✓ D-SG-L3-J |
| **L4 Compute** | ⚠ D-SG-L4-A | ⚠ D-SG-L4-B | ⚠ D-SG-L4-C | ✓ D-SG-L4-D | ⚠ D-SG-L4-E | ✓ D-SG-L4-F | ⚠ D-SG-L4-G | ✓ D-SG-L4-H | ⚠ D-SG-L4-I | ✓ D-SG-L4-J |
| **L5 Identity** | ✓ D-SG-L5-A | ✓ D-SG-L5-B | ✓ D-SG-L5-C | ✓ D-SG-L5-D | ✓ D-SG-L5-E | ⚠ D-SG-L5-F | ⚠ D-SG-L5-G | ⚠ D-SG-L5-H | ⚠ D-SG-L5-I | ✓ D-SG-L5-J |
| **L6 Money** | ✗ D-SG-L6-A | ⚠ D-SG-L6-B | ⚠ D-SG-L6-C | ⚠ D-SG-L6-D | ⚠ D-SG-L6-E | ⚠ D-SG-L6-F | ⚠ D-SG-L6-G | ✓ D-SG-L6-H | ⚠ D-SG-L6-I | ✓ D-SG-L6-J |

_6 layers, 10 axes — 23 ✓ / 28 ⚠ / 3 ✗ / 6 n/a._

## §3. Legend

### Axis legend

- **A. C6** — ESP32-C6 ($4, 160 MHz RISC-V, 512 KB SRAM, ESP-NOW radio)
- **B. Pi** — Orange Pi Prime H5 ($5, 1 GHz Cortex-A53 quad, 2 GB RAM)
- **C. Mac** — MacBook (M-series Apple Silicon, operator-class)
- **D. IPv6mc** — IPv6 multicast transport (ff15::5e:1, U.2 substrate)
- **E. ESP-NOW** — ESP-NOW radio broadcast between C6s
- **F. Routing** — Type-path source routing via routing region in cell header
- **G. PubSub** — Paid publish/subscribe overlay (relays advertise subscriber sets)
- **H. BSV** — Pushdrop UTXO + on-chain anchoring + nLockTime refund txs
- **I. Dash** — Dashboard / observability surface
- **J. Crypto** — Crypto invariants (secp256k1, HMAC, BCA derivation)

### Status legend

- ✓ implemented, tested, verifiable
- ⚠ partial / in progress / unverified
- ✗ not started
- n/a not applicable for this (layer, axis) pair

## §4. Layer notes

### L1 Storage

The cell as a persistent byte-string: NVS row on the ESP32-C6, LMDB
row on the Orange Pi Prime, filesystem entry on the MacBook, and
OP_DROP data carrier in a BSV pushdrop UTXO on-chain. The canonical
claim: the same 1024 bytes serve as storage at every tier — no
separate "serialized form".

### L2 Memory

The cell as live bytes in RAM/SRAM. Same 1024 bytes whether the device
is a 512 KB-SRAM RISC-V or a multi-GB Apple Silicon. The dispatcher,
handlers, and cell-engine all operate on these in-memory cells via
direct pointers — no parse/encode boundary inside the runtime.

### L3 Network transport

The cell on the wire. Bytes 0..1023 are identical whether the frame
crossed ESP-NOW radio between two C6s or IPv6 multicast between
Orange Pis or a USB-C-to-Ethernet hop into a MacBook. Transport
adapters wrap+unwrap; the cell never changes.

### L4 Compute

The cell as input/output of cell-engine WASM. Same WASM module
semantics across all three hardware classes — only the carve
configuration differs (64 KB linear memory on C6, full on Pi/Mac).
A cell computed-on at any tier produces a new cell that's
indistinguishable from one computed at any other tier.

### L5 Identity

The cell with embedded sender + BCA + ECDSA signature. Identity
doesn't change across hardware classes — the same secp256k1 keys
sign on C6 (via mbedTLS), on Pi (native crypto), and on macOS.
BCAs derive deterministically per Ducroux (arXiv 2311.15842);
BSV PoW secures the binding.

### L6 Money

The cell as a spendable economic object. Each cell can be wrapped as
a BSV pushdrop UTXO (`<cell> OP_DROP <pubkey> OP_CHECKSIG`), making
it directly spendable. Per-hop forwarding payments are pre-funded
UTXOs the relay claims by spending. Channel-state commitments are
cells that mint and consume sat-denominated value.

