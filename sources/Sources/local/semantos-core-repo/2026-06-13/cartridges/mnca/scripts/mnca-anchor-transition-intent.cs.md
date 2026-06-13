---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/mnca/scripts/mnca-anchor-transition-intent.cs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.680468+00:00
---

# cartridges/mnca/scripts/mnca-anchor-transition-intent.cs

```cs
# mnca.anchor.transition.intent — handler script (PR-8b-iii)
#
# Third worked example of the cleavage apparatus per LOCKSCRIPT-CLEAVAGE
# §7.2 + §11 PR-8b. Drives the deterministic-verification half of the
# MNCA anchor state machine: reads a transition intent, invokes the
# host_mnca_verify_transition oracle (PR-8b-i), and emits a
# `mnca.anchor.transition.result` cell carrying the verdict.
#
# ── Scope (verify-only) ───────────────────────────────────────────────
#
# This PR ships ONLY the determinism-verification + result-cell emit
# arm of the transition handler. The follow-on PR-8b-v adds:
#   - Successor LINEAR `mnca.anchor` emission (status=Active, generation+1,
#     prev_anchor_hash linked) — requires brain Context construction
#     (PR-8b-iv) to load the predecessor's owner_pubkey.
#   - bsv.tx.sign.request emission for the spending tx that consumes the
#     predecessor's anchor UTXO + mints the successor's. Requires
#     host_compute_sighash + host_resolve_script_template + host_assemble_tx
#     (PR-3a/4/5b — already shipped; just need the .cs orchestration).
#
# Splitting like this keeps each PR reviewable: this one exercises the
# host_mnca_verify_transition path end-to-end (once PR-8b-iv lands the
# brain Context), without conflating the tx-build choreography.
#
# ── What this handler does ────────────────────────────────────────────
#
# When the brain's mint pipeline receives a `mnca.anchor.transition.
# intent` cell, it:
#
#   1. Decodes the variable-length intent payload (PR-8 wire format):
#        offset 0      VERSION = 1
#        offset 1..33  predecessor_anchor_hash
#        offset 33..65 next_snapshot_hash
#        offset 65..69 next_generation (LE u32)
#        offset 69..73 proof_len (LE u32)
#        offset 73+    computation_proof
#   2. PR-8b-iv builds the host_mnca_verify_transition.Context from
#      the intent + the predecessor anchor cell (loaded from
#      cell_store via predecessor_anchor_hash) + the (operator's)
#      MNCA rule params; calls host.setExecutionContext before
#      script execution.
#   3. Pushes the intent cell at slot 0 + runs this handler.
#
# The handler then:
#
#   1. Reads next_generation (4B at offset 65) and stashes it on the
#      altstack — it gets written into the result's confirmed_generation
#      field whether the verdict is Pending or Rejected.
#   2. Invokes OP_CALLHOST "host_mnca_verify_transition" — the hostcall
#      reads its pre-set Context (no script-side operands), re-derives
#      the successor tile via stepTilePayload, hashes it, compares to
#      the claimed next_snapshot_hash, returns a packed u32 rc:
#        bits 0..7   verdict   (Invalid=0 / Valid=1 / Error=2)
#        bits 8..15  error_tag (None=0 / BadPayloadLen=1 / HashMismatch=2)
#   3. Unpacks (verdict, error_tag) from the packed rc via OP_DUP + MOD
#      + DIV by 256 — same pattern as PR-7d's bsv-spv-verify handler.
#   4. Maps verdict → transition outcome:
#        Valid (1)        → Pending (0)  - verification passed; broker
#                                          asynchronously broadcasts
#        Invalid (0)      → Rejected (2) - determinism check failed
#        Error (2)        → Rejected (2) - hostcall couldn't run
#                                          (bad payload, no context, etc.)
#      OP_IF / OP_ELSE on the verdict byte.
#   5. Builds the result cell via OP_CELLCREATE with the
#      `mnca.anchor.transition.result` structured typeHash baked in.
#   6. Writes the result's payload (per PR-8 wire format, 39 bytes):
#        offset 0     VERSION    (0x01)
#        offset 1     OUTCOME    (Pending / Rejected)
#        offset 2..34 txid       (zeros — broker fills on broadcast in PR-8b-v)
#        offset 34    error_tag  (the unpacked tag from rc)
#        offset 35..39 confirmed_generation (LE u32; intent's next_generation)
#      OP_CELLCREATE zero-inits the payload, so the txid field comes
#      for free.
#   7. Leaves the result cell on top of stack — MAGIC-prefixed 1024B
#      → truthy → mint dispatcher's stack walker picks it up,
#      validates typeHash against emits=["mnca.anchor.transition.result"],
#      persists it.

.lockScript {
}

.unlockScript {
}

.handler {
    # ── Step 1: stash next_generation from intent for the result cell ──
    # OP_READPAYLOAD stack: [cell, offset, size] → [cell, field_bytes].
    PUSH 65
    PUSH 4
    OP_READPAYLOAD
    OP_TOALTSTACK
    # Stack: [intent] | alt: [next_gen]

    # ── Step 2: invoke host_mnca_verify_transition ──
    # The hostcall reads its pre-set Context (no script-side operands)
    # and pushes the packed u32 rc onto the stack.
    PUSH "host_mnca_verify_transition"
    OP_CALLHOST
    # Stack: [intent, rc]

    # ── Step 3: unpack (verdict, error_tag) from packed rc ──
    # Same DIV/MOD-by-256 arithmetic as PR-7d:
    #   verdict   = rc & 0xFF       = rc % 256
    #   error_tag = (rc >> 8) & 0xFF = rc / 256
    OP_DUP
    PUSH 256
    OP_MOD
    # Stack: [intent, rc, verdict]
    OP_SWAP
    PUSH 256
    OP_DIV
    # Stack: [intent, verdict, error_tag]
    OP_TOALTSTACK
    # Stack: [intent, verdict] | alt: [next_gen, error_tag]

    # ── Step 4: map verdict → transition outcome ──
    # verdict=1 (Valid)   → outcome=0 (Pending)
    # verdict=0 (Invalid) → outcome=2 (Rejected)
    # verdict=2 (Error)   → outcome=2 (Rejected)
    PUSH 1
    OP_EQUAL
    OP_IF
        PUSH 0
    OP_ELSE
        PUSH 2
    OP_ENDIF
    # Stack: [intent, outcome]
    OP_TOALTSTACK
    # Stack: [intent] | alt: [next_gen, error_tag, outcome]

    # ── Step 5: build transition.result cell via OP_CELLCREATE ──
    # typeHash for ("mnca","anchor","transition","result") =
    #   sha256("mnca")[0..8]      = 09e9fe981010c9b4
    #   sha256("anchor")[0..8]    = 79bfb0e2ba76b9d4
    #   sha256("transition")[0..8] = 70dd37c11434d9c5
    #   sha256("result")[0..8]     = f6a214f7a5fcda0c
    PUSH 3
    PUSH 0
    PUSH 0x09e9fe981010c9b479bfb0e2ba76b9d470dd37c11434d9c5f6a214f7a5fcda0c
    PUSH 0x00000000000000000000000000000000
    OP_CELLCREATE
    # Stack: [intent, result_cell]

    # ── Step 6: write VERSION (1B = 0x01) at payload offset 0 ──
    PUSH 0x01
    PUSH 0
    OP_WRITEPAYLOAD

    # ── Step 7: write outcome (1B) at payload offset 1 ──
    # Pop outcome from altstack (top of altstack = most recently pushed).
    OP_FROMALTSTACK
    PUSH 1
    OP_WRITEPAYLOAD

    # ── Step 8: write error_tag (1B) at payload offset 34 ──
    OP_FROMALTSTACK
    PUSH 34
    OP_WRITEPAYLOAD

    # ── Step 9: write confirmed_generation (4B LE) at payload offset 35 ──
    # next_gen was the FIRST thing we pushed to altstack — it's the
    # bottom item; OP_FROMALTSTACK pulls it after outcome + error_tag.
    OP_FROMALTSTACK
    PUSH 35
    OP_WRITEPAYLOAD

    # Stack: [intent, result_cell_fully_populated]
    # MAGIC-prefixed → truthy → dispatcher's stack walker picks up the
    # result cell, matches its typeHash against emits, persists it.
    # The intent at slot 0 is skipped (byte-equal to input_cell).
}

```
