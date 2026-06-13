---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/OCTAVE-ESCALATION-UNIFICATION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.736345+00:00
---

# Octave Escalation Unification — one overflow primitive for data payloads and routing paths

> **Status:** design / proposal. No code in this doc; it pins the wire
> shape and the deliverable decomposition so the escalation primitive can
> be built coherently across `core/cell-engine` (octave/multicell),
> `core/protocol-types` (routing) and the layer-collapse wire format at
> once, rather than as three divergent overflow schemes.
>
> **Audience:** whoever implements the octave-escalated storage path and
> the routing-path-merkle-overload path. Read alongside
> `core/cell-engine/src/octave.zig`, `core/cell-engine/src/multicell.zig`,
> `core/cell-engine/src/routing.zig`,
> `core/protocol-types/src/cell-routing.ts`, and
> `docs/prd/MNCA-LAYER-COLLAPSE-BRIEF.md` §2.1 / §13.2 / line ~429.

---

## 1. The thesis

The cell substrate has **three** places where a fixed inline region runs
out of room and the system must spill into more cells:

1. **Data payloads.** A cell is 1024 bytes (256-byte header + 768-byte
   payload). Objects larger than 768 bytes spill into continuation cells
   (`multicell.zig`, `MAX_CONTINUATIONS = 64` → a flat ~65 KB ceiling) or
   commit a `domainPayloadRoot` (header offset 224, 32 bytes) — a merkle
   root over the full payload with per-chunk inclusion proofs.

2. **Routing paths.** Typed source-routes live inline in the payload at
   offset 256+ (`FLAG_PATH_IN_PAYLOAD`, 48 bytes per hop). At N=6 hops
   that already burns 292 of 768 payload bytes. The brief (line ~429)
   says deeper paths either use continuation cells **or** commit the path
   via a merkle root with per-hop inclusion proofs
   (`FLAG_PATH_MERKLE_OVERLOAD`, bit 4).

3. **Octave hierarchy.** `octave.zig` already describes
   "inline-until-full, then escalate to a larger cell class": octave 0 =
   1 KB, octave 1 = 1 MB, octave 2 = 1 GB, octave 3 = 1 TB, each level
   1024× the last, 1024 slots per level, addressed by `OctaveAddress`.

These are **the same primitive** written three times:

> **Inline until the fixed region is full; then escalate to a
> merkle-rooted hierarchy of child cells and carry per-consumer inclusion
> proofs.**

This doc unifies them into one escalation ladder, retires the flat
64-cap multicell, and pins *where* the escalation descriptor lives
(answer: the **payload side**, never the header — the 64-byte header
routing region 160–223 is fully claimed; see §3).

---

## 2. The escalation ladder

A producer writes a logical blob (a data payload, or a routing path) by
climbing rungs only as far as the blob forces:

| Rung | Name        | When                                   | Where it lives |
|------|-------------|----------------------------------------|----------------|
| 0    | **inline**  | blob ≤ the inline region               | the cell's own payload bytes |
| 1    | **octave-escalated** | blob > inline, ≤ one larger-octave cell | a single octave-N child cell (N = `minimumOctaveForSize`) |
| 2    | **merkle-rooted hierarchy** | blob spans many cells | a merkle root committed in a fixed 32-byte slot + N child cells; consumers carry inclusion proofs |

Rung 0→1 is the octave bump (`octave.zig::minimumOctaveForSize`). Rung
1→2 is the merkle overload (`domainPayloadRoot` for data;
`FLAG_PATH_MERKLE_OVERLOAD` for paths). The producer picks the lowest
rung that fits; the consumer reads the rung indicator and walks
accordingly.

The **MFP read cost** rides the octave: `1000^octave` sats per cell read
(`octave.zig::costSatsPerCell`) — so escalation is economically
self-throttling. A 1 TB blob is reachable but expensive to dereference,
exactly as intended.

---

## 3. Where the escalation descriptor lives — payload, NOT header

The header's bytes 160–223 (the 64 bytes once "freed" by RM-032b/RM-042)
are **fully claimed** by `cell-routing-v1` (`routing.zig`):

```
 94  routing_mode    u8        160  routing_version   u32
 95  priority        u8        164  routing_flags     u32
                              168  segments_left     u32
                              172  hop_count_budget  u32
                              176  flow_label        u64
                              184  next_hop_bca      16B
                              200  final_dest_bca    16B
                              216  routing_checksum  u32 (CRC-32 over 160..216)
                              220  routing_reserved  4B
```

`comptime` asserts `ROUTING_REGION_END == 224`, i.e. the routing region
ends exactly where `domainPayloadRoot` begins. **There is no free header
byte for an `octave_level` field.** An earlier proposal to put
`octave_level: u8` at offset 160 collided with this region; it is
rejected.

The escalation descriptor therefore lives in the **payload**, co-located
with the structure it describes:

- **Routing path** escalation descriptor sits next to the existing typed
  -segments header (payload offset 256, `[u16 N ‖ u16 payloadStartsAt]`).
  When `FLAG_PATH_MERKLE_OVERLOAD` is set, the inline tuples are replaced
  by a 32-byte path-merkle-root + a small octave descriptor (see §5).
- **Data payload** escalation descriptor sits at the front of the
  payload region too (or, for the merkle case, is committed in the
  header's existing `domainPayloadRoot` 32-byte slot at 224 and elaborated
  in the payload). `octave_level` is a field of *this* descriptor.

This keeps the header's hot routing path untouched and lets the
escalation metadata grow without contending for the 64-byte budget.

---

## 4. Sizes: ×1024 binary, not ×1000 (and what 1000 *is* for)

There are two different "1000-ish" factors in `octave.zig` and they must
not be conflated:

- **Cell size per octave is ×1024 (binary).** The code is
  `CELL_SIZE << (octave * 10)` — octave 0 = 1024 B, octave 1 = 1024² =
  1,048,576 B (1 MiB), octave 2 = 1024³ (1 GiB), octave 3 = 1024⁴ (1 TiB).
  Slots per octave is also 1024. So the addressing is clean binary
  shifts. **The wire format uses ×1024.** (Todd's "c2s are 1 MB, 1000 of
  them" is the right *shape* — a thousand-ish fan-out per level — and the
  exact factor is the binary 1024 the engine already ships.)
- **MFP read cost per octave is ×1000 (decimal).** `costSatsPerCell` =
  `1000^octave`. This is a pricing knob, deliberately round decimal, and
  is independent of the byte math. Keep it ×1000.

**Open item (O-1):** the header's `total_size` / `payload_total` field is
`u32` at offset 90 — a 4 GiB ceiling. That cannot express an octave-2
blob (1 GiB cells × 1024 slots = 1 TiB) or above. Escalated blobs need a
**u64 total-bytes** count. Since the header has no room, the u64
total-bytes belongs in the payload-side escalation descriptor (§5), with
the header `total_size` either clamped/saturated or repurposed to "bytes
in *this* cell." This needs a decision before octave-2 is wired; octave-0
and octave-1 (≤ 1 GiB, fits u32) are unaffected and can ship first.

---

## 5. Proposed payload-side escalation descriptor

A single, shared 16-byte descriptor used by both the data-payload and the
routing-path overflow, placed at a known payload offset (data: payload
start; path: immediately after the typed-segments `[N ‖ payloadStartsAt]`
header). Layout (little-endian, mirrors the routing module's conventions):

```
off  size  field              meaning
 0   1     rung               0=inline, 1=octave, 2=merkle-hierarchy
 1   1     octave_level       0..3 (base/kilo/mega/giga); 0 when rung=0
 2   2     child_count        number of child cells (rung ≥ 1)
 4   8     total_bytes        u64 logical blob size (resolves O-1)
12   4     reserved           0 (alignment / future flags)
```

When `rung == 2`, the 32-byte merkle root lives in its canonical fixed
slot:
- **data:** header `domainPayloadRoot` (offset 224).
- **path:** the 32 bytes that replace the inline tuples in the payload
  when `FLAG_PATH_MERKLE_OVERLOAD` is set.

`flow_label` (routing header offset 176, u64) is the **fragment-correlation
key**: all child cells / fragments of one escalated blob carry the same
`flow_label`, so a relay or a reassembler can gather a distributed blob
without a central index. This is the one field the routing header already
provides that the data-payload path should also reuse for multi-cell
reassembly correlation.

---

## 6. What this retires

- **`multicell.zig` `MAX_CONTINUATIONS = 64`** (the flat ~65 KB ceiling)
  and the 8-byte `ContinuationHeader` scheme become rung-1/rung-2 of the
  ladder. The flat continuation packing stays as the *transport* for a
  single octave step (it is the byte-identical mirror of
  `cellPacker.ts`), but the **64-cap** is replaced by octave escalation:
  past 64 base-cells you bump to octave 1 rather than erroring
  `too_many_continuations`. The merkle hierarchy (rung 2) is what
  actually removes the hard cap.
- **Two divergent "what do I do when full" code paths** (one in
  multicell/octave for data, one in routing for paths) collapse to one
  descriptor + one merkle-inclusion-proof verifier.

---

## 7. Deliverable decomposition (proposed)

Sequence so each rung is independently shippable and testable. Octave-0/1
data already works end-to-end (it is what the Oddjobz sem_objects sink
writes today), so the data side can start without blocking on routing.

1. **D-OCT-escalation-descriptor** — define the 16-byte payload-side
   descriptor (§5) in `core/protocol-types` with a TS oracle + tests;
   mirror in `core/cell-engine` Zig (same pattern as `routing.zig` ↔ its
   TS mirror). No behaviour change yet — just the shape + accessors.
2. **D-OCT-data-octave-bump** — wire rung 0→1 for data payloads:
   `minimumOctaveForSize` selects the octave; producer/consumer read the
   descriptor; retire the `too_many_continuations` hard error in favour of
   an octave bump. u64 `total_bytes` lands here (resolves O-1 for the
   data side). Octave-0/1 only.
3. **D-OCT-merkle-hierarchy** — rung 1→2 for data: `domainPayloadRoot`
   commit + inclusion-proof verifier shared with routing. Removes the
   hard cap entirely.
4. **D-OCT-path-merkle-unify** — point `FLAG_PATH_MERKLE_OVERLOAD` at the
   *same* descriptor + verifier as data, with the path-merkle root in the
   payload and `flow_label` as the fragment key. Brief line ~429 becomes
   real.
5. **D-OCT-octave-2-plus** (gated on O-1 decision) — mega/giga octaves;
   pricing already exists (`costSatsPerCell`). Needs the u64 total-bytes
   decision finalised and the header `total_size` semantics pinned.

---

## 8. Open questions for Todd

- **O-1 (u64 total-bytes / header `total_size`):** confirm the
  payload-side `total_bytes: u64` is the source of truth and decide what
  the header's `total_size` u32 (offset 90) means for escalated blobs
  ("this cell only" vs saturated). Blocks octave-2+, not octave-0/1.
- **O-2 (descriptor offset for data):** for the data path, does the
  descriptor sit at payload offset 0, or behind the same
  `payloadStartsAt` indirection the routing typed-segments use? Leaning
  payload offset 0 for data (no routing on a pure data cell), `after the
  typed-segments header` for routed cells.
- **O-3 (merkle leaf size):** what is one merkle leaf — a full child cell
  (1024 B) or the 768/1016 payload bytes? Affects proof size and the
  inclusion-proof verifier shared in D-OCT-merkle-hierarchy.
- **O-4 (does flow_label move?):** `flow_label` is in the routing header
  (176). A pure data cell that's escalated but *not* routed has no
  routing region populated. Confirm reusing offset 176 as the fragment
  key even when `routing_mode == unrouted`, vs duplicating an 8-byte key
  in the payload descriptor.
