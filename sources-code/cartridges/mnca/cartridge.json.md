---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/mnca/cartridge.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.416293+00:00
---

# cartridges/mnca/cartridge.json

```json
{
  "_notes": "Substrate cartridge — Multi-Neighborhood Cellular Automaton compute primitive. Per decision record §4 (D6/D7): MNCA is a substrate-level cartridge that domain cartridges may opt into. The 5 cell types declared here are the STANDALONE-MNCA shape (segment2='standalone'). Domain-bound MNCA invocations (e.g. oddjobz running MNCA over Job data) would mint cells with segment1=<domain> instead — but those don't need separate manifest entries because the typeHash is computed dynamically from the triple by the source-cartridge code path. Created by T3.b (2026-05-25).",
  "id": "mnca",
  "name": "MNCA",
  "version": "0.1.0",
  "description": "Multi-Neighborhood Cellular Automaton — substrate-level compute primitive. Layer-collapse demo target. Tiles emit propagation cells; perturbations mint injection events; tick advances each tile one step; snapshot is the durable grid state. Source code split: wire-format primitives (tile codec, cell-journey, hop-processing, snapshot-anchor, srv6, path-merkle, relay-table) stay in core/protocol-types/src/mnca/; cell-type identities (this manifest) own the typeHashes.",
  "role": "substrate",
  "brain": {
    "handlers": [
      {
        "module": "registration"
      }
    ]
  },
  "cellTypes": [
    {
      "name": "mnca.snapshot",
      "triple": {
        "segment1": "mnca",
        "segment2": "standalone",
        "segment3": "snapshot",
        "segment4": ""
      },
      "linearity": "PERSISTENT",
      "description": "A full grid snapshot at a given tick — the durable state cell. Multiple snapshots accumulate as a prevStateHash-chained history; never consumed."
    },
    {
      "name": "mnca.perturb",
      "triple": {
        "segment1": "mnca",
        "segment2": "standalone",
        "segment3": "perturb",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "description": "An external perturbation request (e.g. from a C6 button press). Consumed exactly once when resolved into a tile-local injection event."
    },
    {
      "name": "mnca.tile.injection",
      "triple": {
        "segment1": "mnca",
        "segment2": "standalone",
        "segment3": "tile",
        "segment4": "injection"
      },
      "linearity": "LINEAR",
      "description": "A perturbation resolved into a concrete tile-local injection event. Consumed by the tile owner when applied."
    },
    {
      "name": "mnca.tile.tick",
      "triple": {
        "segment1": "mnca",
        "segment2": "standalone",
        "segment3": "tile",
        "segment4": "tick"
      },
      "linearity": "LINEAR",
      "description": "A single tile's advance-one-step result. Consumed when folded into the next snapshot."
    },
    {
      "name": "mnca.tile",
      "triple": {
        "segment1": "mnca",
        "segment2": "standalone",
        "segment3": "tile",
        "segment4": ""
      },
      "linearity": "RELEVANT",
      "description": "On-device tile propagation cell — emitted by C6 firmware after each MNCA rule application. Carries the full tile state as inner payload of a forward.v1 cell so each hop pays a routing fee. 2-of-3 device quorum on the tile hash (x, y, generation, SHA-256(state_bytes)) fires a cellmesh.channel_settle.v0 cell. Renamed from `mnca.tile.v0` under D12 (no version suffixes); Q13-A resolution: base-tile shape with operations (injection, tick) in segment4. Payload layout — bytes 0-1 u16 LE x, 2-3 u16 LE y, 4-7 u32 LE generation, 8-11 u8[4] rule_id, 12-15 u32 LE state_len, 16+ u8[N] state_bytes."
    },
    {
      "name": "mnca.anchor.create.intent",
      "triple": {
        "segment1": "mnca",
        "segment2": "anchor",
        "segment3": "create",
        "segment4": "intent"
      },
      "linearity": "EPHEMERAL",
      "description": "PR-8 / LOCKSCRIPT-CLEAVAGE.md §7.2. Operator's request to bring a fresh MNCA computation on-chain. Carries (initial_snapshot_hash, initiator_pubkey, workflow_id). Handler (PR-8b-ii) validates + emits the initial `mnca.anchor` LINEAR cell with current_snapshot_hash = intent's initial_snapshot_hash, prev_anchor_hash = zeros, generation = 0, owner_pubkey = initiator_pubkey, status = Active. Wire format: `core/protocol-types/src/mnca/anchor.ts::encodeMncaAnchorCreateIntent`.",
      "handler": {
        "script": "510120cc6b01210121cc6b51002009e9fe981010c9b479bfb0e2ba76b9d4e3b0c44298fc1c14e3b0c44298fc1c141000000000000000000000000000000000ca5100d16c0145d16c51d1",
        "scriptHash": "69136a75a8a168e7d9b6b2b05086e8389b5a2f88cfc847a9ef95775a98969b19",
        "capabilities": [],
        "emits": ["mnca.anchor"],
        "opcountBudget": 1000
      }
    },
    {
      "name": "mnca.anchor",
      "triple": {
        "segment1": "mnca",
        "segment2": "anchor",
        "segment3": "",
        "segment4": ""
      },
      "linearity": "LINEAR",
      "description": "PR-8 / LOCKSCRIPT-CLEAVAGE.md §7.2. Durable on-chain anchor state. Carries (current_snapshot_hash, prev_anchor_hash, generation, owner_pubkey, status, anchor_txid, anchor_vout). One-shot destructor: consumed by a successor anchor minted from the next transition. PR-8b-vi-1 extended the wire format with anchor_utxo_ref (anchor_txid + anchor_vout) so the cell carries its own on-chain identity — zero when uncommitted; broker writes the real values after ARC accepts the spending tx. Wire format: `core/protocol-types/src/mnca/anchor.ts::encodeMncaAnchor` (139 bytes; legacy 103-byte v1 cells decode with zero utxo_ref)."
    },
    {
      "name": "mnca.anchor.transition.intent",
      "triple": {
        "segment1": "mnca",
        "segment2": "anchor",
        "segment3": "transition",
        "segment4": "intent"
      },
      "linearity": "EPHEMERAL",
      "description": "PR-8 / LOCKSCRIPT-CLEAVAGE.md §7.2. Operator's request to advance the anchor chain by one tick. Carries (predecessor_anchor_hash, next_snapshot_hash, next_generation, computation_proof). Handler (PR-8b-iii) invokes host_mnca_verify_transition + emits mnca.anchor.transition.result with outcome Pending (verify passed; broker drives broadcast) or Rejected (determinism check failed). PR-8b-v: brain Context builder pre-verifies + pre-builds the successor LINEAR mnca.anchor cell on Valid verdict + pushes it via ScriptContextBuilder.extra_cells_fn. PR-8b-vi-2: when the predecessor anchor has a committed on-chain UTXO ref (PR-8b-vi-1 fields), the brain ALSO pre-computes the BIP-143 sighash for the spending tx (predecessor anchor UTXO → successor anchor UTXO with PushDrop) and pre-builds a bsv.tx.sign.request cell with the digest. Wallet signs → broker assembles + broadcasts via ARC → real mainnet txid. Wire format: `core/protocol-types/src/mnca/anchor.ts::encodeMncaAnchorTransitionIntent`.",
      "handler": {
        "script": "014154cc6b1b686f73745f6d6e63615f7665726966795f7472616e736974696f6ed076020001977c020001966b518763006752686b53002009e9fe981010c9b479bfb0e2ba76b9d470dd37c11434d9c5f6a214f7a5fcda0c1000000000000000000000000000000000ca5100d16c51d16c0122d16c0123d1",
        "scriptHash": "66c51a67729932d4046d0a15fcba5c02f5b78cc89ec1d0a71797b7473ef67b86",
        "capabilities": ["cap.mnca.verify"],
        "emits": ["mnca.anchor.transition.result", "mnca.anchor", "bsv.tx.sign.request"],
        "opcountBudget": 2000
      }
    },
    {
      "name": "mnca.anchor.transition.result",
      "triple": {
        "segment1": "mnca",
        "segment2": "anchor",
        "segment3": "transition",
        "segment4": "result"
      },
      "linearity": "EPHEMERAL",
      "description": "PR-8 / LOCKSCRIPT-CLEAVAGE.md §7.2. Handler-emitted outcome of a transition attempt: { outcome (Pending/Accepted/Rejected), txid, error_tag, confirmed_generation }. Wire format: `core/protocol-types/src/mnca/anchor.ts::encodeMncaAnchorTransitionResult`."
    }
  ]
}

```
