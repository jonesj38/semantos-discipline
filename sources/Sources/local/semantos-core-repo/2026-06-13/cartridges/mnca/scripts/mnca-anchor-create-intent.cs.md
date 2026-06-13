---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/mnca/scripts/mnca-anchor-create-intent.cs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.680772+00:00
---

# cartridges/mnca/scripts/mnca-anchor-create-intent.cs

```cs
# mnca.anchor.create.intent — handler script (PR-8b-ii)
#
# Second worked example of the cleavage apparatus per LOCKSCRIPT-CLEAVAGE
# §7.2 + §11 PR-8. Companion to PR-7b's bsv-spv-verify handler: this one
# starts the MNCA anchor state machine by minting the initial LINEAR
# anchor cell from an EPHEMERAL create.intent.
#
# ── What this handler does ────────────────────────────────────────────
#
# When the brain's mint pipeline receives a `mnca.anchor.create.intent`
# cell, it:
#
#   1. Decodes the 82-byte intent payload (PR-8 wire format):
#        offset 0     VERSION = 1
#        offset 1..33 initial_snapshot_hash
#        offset 33..66 initiator_pubkey  (compressed-secp256k1)
#        offset 66..82 workflow_id
#   2. Pushes the intent cell at slot 0 (per PR-4b's script-execution
#      wiring) and runs this handler.
#
# The handler then:
#
#   1. Extracts initial_snapshot_hash via OP_READPAYLOAD at offset 1.
#   2. Extracts initiator_pubkey via OP_READPAYLOAD at offset 33.
#   3. Builds the LINEAR `mnca.anchor` cell via OP_CELLCREATE with
#      typeHash = sha256-prefix-product for ("mnca", "anchor", "", "")
#      baked into the bytecode. owner_id = 16 zero bytes
#      (placeholder until PR-8b-iv wires hat-context).
#   4. Writes the result cell's payload (per PR-8 wire format for
#      `mnca.anchor`, 103 bytes total):
#        offset 0     VERSION    (0x01)
#        offset 1..33 current_snapshot_hash = initial_snapshot_hash
#        offset 33..65 prev_anchor_hash       = ALL ZEROS
#                                              (initial anchor in chain)
#        offset 65..69 generation (LE u32)    = 0
#        offset 69..102 owner_pubkey          = initiator_pubkey
#        offset 102   status                  = Active (0)
#      The zero fields (prev_anchor_hash, generation, status) come for
#      free from OP_CELLCREATE's payload init. Only three writes are
#      needed: VERSION + snapshot_hash + initiator_pubkey.
#   5. Leaves the result cell on top of stack — MAGIC-prefixed 1024B
#      → truthy → executor.execute returns true → dispatcher's stack
#      walker picks up the anchor cell, validates typeHash against
#      emits = ["mnca.anchor"], persists it.
#
# ── What this handler does NOT yet do ─────────────────────────────────
#
# It does NOT broadcast a BSV tx. The mnca.anchor cell minted here is
# off-chain only — it represents the operator's intent to start an
# anchor chain. The on-chain anchor commitment happens via the upcoming
# PR-8b-iii transition handler, which emits a bsv.tx.sign.request
# that the wallet signs + the broker broadcasts via ARC. That's the
# path to a real mainnet txid (mnca_anchor_onchain_mainnet recipe via
# the cleavage apparatus).
#
# Also: PR-8b-iv will wire the brain's owner_id context so this cell's
# owner_id field carries the real authenticating-hat identity instead
# of placeholder zeros.

.lockScript {
}

.unlockScript {
}

.handler {
    # ── Step 1: extract initial_snapshot_hash from intent payload ──
    # OP_READPAYLOAD stack: [cell, offset, size] → [cell, field_bytes].
    PUSH 1
    PUSH 32
    OP_READPAYLOAD
    OP_TOALTSTACK
    # Stack: [intent] | alt: [snapshot_hash]

    # ── Step 2: extract initiator_pubkey from intent payload ──
    PUSH 33
    PUSH 33
    OP_READPAYLOAD
    OP_TOALTSTACK
    # Stack: [intent] | alt: [snapshot_hash, initiator_pubkey]

    # ── Step 3: build mnca.anchor cell via OP_CELLCREATE ──
    # OP_CELLCREATE stack: [linearity, domain_flag, typeHash, owner_id]
    # → [cell with header populated, payload zero].
    # typeHash for ("mnca","anchor","","") under the structured |8|8|8|8|
    # construction (sha256(seg)[0..8] per segment):
    #   sha256("mnca")[0..8]   = 09e9fe981010c9b4
    #   sha256("anchor")[0..8] = 79bfb0e2ba76b9d4
    #   sha256("")[0..8]       = e3b0c44298fc1c14   (the empty-string sha256)
    #   sha256("")[0..8]       = e3b0c44298fc1c14
    PUSH 1
    PUSH 0
    PUSH 0x09e9fe981010c9b479bfb0e2ba76b9d4e3b0c44298fc1c14e3b0c44298fc1c14
    PUSH 0x00000000000000000000000000000000
    OP_CELLCREATE
    # Stack: [intent, anchor_cell]

    # ── Step 4: write VERSION (1B = 0x01) at payload offset 0 ──
    PUSH 0x01
    PUSH 0
    OP_WRITEPAYLOAD
    # Stack: [intent, anchor_cell']

    # ── Step 5: write initiator_pubkey (33B) at payload offset 69 ──
    # Pop from altstack — LIFO order means initiator_pubkey is on top.
    OP_FROMALTSTACK
    PUSH 69
    OP_WRITEPAYLOAD
    # Stack: [intent, anchor_cell'']

    # ── Step 6: write initial_snapshot_hash (32B) at payload offset 1 ──
    OP_FROMALTSTACK
    PUSH 1
    OP_WRITEPAYLOAD
    # Stack: [intent, anchor_cell''']

    # Top of stack = anchor_cell with full payload. MAGIC-prefixed 1024B
    # → truthy → mint dispatcher's stack walk picks it up, matches its
    # typeHash against emits = ["mnca.anchor"], persists it. The
    # original intent cell at slot 0 is skipped (byte-equal to input).
}

```
