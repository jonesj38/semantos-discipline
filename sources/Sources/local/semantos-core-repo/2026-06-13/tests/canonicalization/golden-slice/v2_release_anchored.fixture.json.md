---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/canonicalization/golden-slice/v2_release_anchored.fixture.json
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.590762+00:00
---

# tests/canonicalization/golden-slice/v2_release_anchored.fixture.json

```json
{
  "_meta": {
    "slice": "v2_release_anchored",
    "version": "0.1.0",
    "createdAt": "2026-05-28",
    "spec": "docs/canon/canonicalization-golden-slice.md §2 layer 9 + §4",
    "supersedes": "v1_release.fixture.json (V1 is layer 1-8 only; V2 adds layer 9 anchor)",
    "purpose": "C7 V2 acceptance fixture. Same as V1 (operator types release → brain mints cell) PLUS the cell is anchored to BSV mainnet via the brain's wallet-headers pipeline. cell carries anchorTxid; helm card renders anchored badge."
  },

  "v1_inheritance": "All of layer 1-8 from v1_release.fixture.json applies unchanged. V2 only ADDS layer 9 + extends layer 8 to render the anchored state.",

  "v2_request_diff": {
    "request_change": "PWA-side caller adds `anchor: true` to the cells_mint_handler request body (TBD: confirm parameter name from cells_mint_http.zig — possibly `anchor`, `anchorOnChain`, or a wrapping `policy: {anchor: true}` block).",
    "wire_body_shape_v2": {
      "typeHashHex": "06d0a049e88a982bada750e3f8464e9ea4d451ec23463726e3b0c44298fc1c14",
      "payload": {
        "rawText": "<utterance>",
        "source": "keyboard",
        "prompt": "freeform",
        "elevation": 5
      },
      "anchor": true
    },
    "_note": "Per Q5 (default local-only), the explicit `anchor: true` flag is required to trigger chain commit. Cartridge manifest's per-verb `anchor: required` could also force this without operator flag — V2 slice exercises the operator-opt-in path."
  },

  "layer9_chain_anchor": {
    "trigger": "brain receives mint request with anchor:true",
    "brain_pipeline": [
      "1. cells_mint_handler executes the standard mint pipeline (validate, encode, persist) — layers 5+7 from V1",
      "2. After persistence, brain calls into wallet-headers anchor path (cartridges/wallet-headers/brain/src/cell-anchor.ts or equivalent)",
      "3. wallet-headers constructs a BSV pushdrop transaction: pushdrop script = OP_FALSE OP_RETURN <cell_id_32B> (or pushdrop variant per cartridges/wallet-headers/brain/src/* convention)",
      "4. wallet-headers signs with operator key + broadcasts via ARC (cartridges/wallet-headers uses arc-broadcast.ts)",
      "5. ARC returns txid",
      "6. brain stores anchorTxid against the cell (either in cell-store metadata or a separate anchor-log)",
      "7. brain pushes helm-event-broker notification: cells.<cartridgeId>.anchored"
    ],
    "expected_response": {
      "status": 201,
      "body_shape": {
        "cellId": "<64-hex cell-id>",
        "cartridgeId": "betterment",
        "cellType": "betterment.practice.release",
        "persistedAt": "<unix-ms number>",
        "anchorTxid": "<64-hex BSV txid>",
        "anchorState": "broadcast"
      }
    },
    "subsequent_state_transitions": {
      "anchorState=broadcast": "ARC accepted the tx, broadcast to BSV mempool. Subject to reorg.",
      "anchorState=mined": "Tx included in a block. Brain may update this via SPV reactor (see C6 chain-broadcast / header-validator pipeline).",
      "anchorState=confirmed": "N confirmations deep (TBD threshold)."
    },
    "acceptance": "POST /api/v1/cells with anchor:true returns 2xx with anchorTxid in the body. Subsequent GET /api/v1/cell/<cellId> returns the cell with anchor metadata. WhatsOnChain shows the tx within ~30s of broadcast."
  },

  "layer8_helm_render_v2": {
    "v1_card_shape": "title + preview + 'just now · cellType · cellId-prefix'",
    "v2_additions": {
      "anchor_badge": "Icons.link icon next to title when anchorTxid is present",
      "txid_chip": "Tappable chip showing first 8 chars of txid + 'on chain' — taps to WhatsOnChain mainnet URL",
      "anchor_state_color": "broadcast = amber, mined = blue, confirmed = green",
      "fallback": "If anchor request was made but no txid returned within 30s, show 'pending' badge with retry option"
    },
    "acceptance": "Card shows anchor badge + tappable txid chip when cell.anchorTxid is present."
  },

  "v2_slice_acceptance": {
    "definition": "All V1 layers (1-8) pass unchanged + layer 9 anchor + helm card V2 additions render correctly.",
    "rerun_rule": "Both v1_release tests AND v2_release_anchored tests must pass. V2 builds on V1 — V1 regression means V2 is also broken."
  },

  "open_questions_before_v2_starts": [
    "Q-V2-1: Does cells_mint_handler ALREADY accept an anchor parameter, or do we need to add it? (Tick 2: survey runtime/semantos-brain/src/cells_mint_http.zig + cells_mint_handler.zig RequestEnvelope shape.)",
    "Q-V2-2: Is the brain's anchor pipeline (cartridges/wallet-headers/brain/src/cell-anchor.ts or arc-broadcast.ts) actually wired to fire on demand from cells_mint_handler, or is it a separate periodic job?",
    "Q-V2-3: Where does brain store anchorTxid? Cell-store metadata? Separate anchor-log? cell-store doesn't have anchor fields per cell-engine constants today.",
    "Q-V2-4: Does ARC need real BSV funding on the brain's wallet? Q4 said wallet doesn't own custody — so what's the funding model for chain anchors?",
    "Q-V2-5: Per-anchor cost ≈ $0.0001. For betterment.practice.release where operator opts in via flag, that's fine. But Q5 default-local-only + manifest per-verb `anchor: optional` should make this opt-in. Confirm the policy hasn't drifted."
  ]
}

```
