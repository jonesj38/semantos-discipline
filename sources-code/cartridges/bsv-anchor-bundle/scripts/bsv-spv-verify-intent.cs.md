---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/bsv-anchor-bundle/scripts/bsv-spv-verify-intent.cs
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.441222+00:00
---

# cartridges/bsv-anchor-bundle/scripts/bsv-spv-verify-intent.cs

```cs
# bsv.spv.verify.intent — handler script
#
# PR-7b of LOCKSCRIPT-CLEAVAGE.md §11. First worked example using the
# PR-2 sectioned assembler. Demonstrates the assembler tooling +
# `host_verify_beef_spv` (PR-7a) + OP_WRITEPAYLOAD (this PR) +
# `cellTypes[i].handler.script` manifest wiring end-to-end.
#
# ── What this handler does ────────────────────────────────────────────
#
# When the brain's mint pipeline receives a `bsv.spv.verify.intent`
# cell, it:
#
#   1. Parses the intent payload via `core/protocol-types/src/bsv/
#      spv-verify.ts::decodeSpvVerifyIntent` to extract the txid +
#      inline BEEF bytes.
#   2. Builds the `host_verify_beef_spv` Context with
#      (beef_bytes, txid, trusted_roots, allocator). Trusted roots come
#      from the brain's headers tracker.
#   3. Pushes the intent cell at slot 0 (per PR-4b's script-execution
#      wiring) and runs this handler.
#
# The handler then:
#
#   1. Extracts the 32-byte txid from the intent cell's payload (offset
#      1..33 per spv-verify.ts wire layout) and stashes it on the
#      altstack.
#   2. Pushes the literal string "host_verify_beef_spv" and invokes
#      OP_CALLHOST. The hostcall pops the name, dispatches to the
#      registered handler (PR-7a's `host_verify_beef_spv.handle`), and
#      pushes the u32 return code back onto the stack.
#   3. Maps the return code to an outcome byte:
#        rc=0 (RC_OK)            → outcome=1 (Valid)
#        rc=1 (RC_INVALID)       → outcome=0 (Invalid)
#        rc=2 (RC_ERROR)         → outcome=2 (Error)
#        rc=3 (RC_INVALID_INPUT) → outcome=2 (Error)
#      Implemented via OP_GREATERTHANOREQUAL / OP_IF: rc>=2 ⇒ Error;
#      otherwise outcome = 1 - rc (yields 1 for Valid, 0 for Invalid).
#   4. Builds a `bsv.spv.verify.result` cell via OP_CELLCREATE with the
#      typeHash baked in (the structured |8|8|8|8| sha256 hash of
#      "bsv","spv","verify","result"). EPHEMERAL maps to cell-engine
#      linearity=RELEVANT per cartridge_cell_registry.zig §66-80.
#   5. Writes VERSION (1B at payload offset 0), OUTCOME (1B at offset
#      1), and txid (32B at offset 2) into the result cell's payload
#      via OP_WRITEPAYLOAD.
#   6. Leaves the result cell on top of stack — both the truthy signal
#      for script success (MAGIC-prefixed cell is non-zero) AND the
#      emission the mint dispatcher picks up via the emits[] allowlist.
#
# ── What this handler does NOT yet do ─────────────────────────────────
#
# It does NOT populate the result cell's `error_tag` field (payload
# offset 34, 1B). That value lives in `host_verify_beef_spv` Context's
# `last_error_tag` output field but the hostcall currently only pushes
# the return code onto the stack — not the error_tag. Closing this gap
# is a separate follow-on: either extend the hostcall to push (rc,
# outcome, error_tag) as three stack values, or pack outcome + error_tag
# into the rc's low bytes. Until then `error_tag` stays at the
# OP_CELLCREATE default of 0 (ERROR_TAG_NONE), which is wrong for
# rc!=0 outcomes. The Dart caller currently does not rely on
# error_tag for the v1 substrate flip.
#
# ── Sections ───────────────────────────────────────────────────────────
#
# This handler doesn't construct a Bitcoin transaction — there's no
# spending tx output for the brain to broadcast. So `.lockScript` and
# `.unlockScript` are empty. The assembler will emit empty hex strings
# for both regions; only `.handler` carries bytecode.

.lockScript {
}

.unlockScript {
}

.handler {
    # ── Step 1: extract txid from intent cell payload (offset 1..33) ──
    # OP_READPAYLOAD stack: [cell, offset, size] → [cell, field_bytes].
    # The intent cell stays on stack; the field bytes are pushed above it.
    PUSH 1
    PUSH 32
    OP_READPAYLOAD
    # Stack: [intent, txid]
    OP_TOALTSTACK
    # Stack: [intent] | alt: [txid]

    # ── Step 2: invoke host_verify_beef_spv ──
    PUSH "host_verify_beef_spv"
    OP_CALLHOST
    # Stack: [intent, rc]

    # ── Step 3 (PR-7d): unpack (outcome, error_tag) from the packed rc ──
    # The hostcall now packs both values into a single u32 so the
    # script can populate the result cell's verdict fields without a
    # separate stack-push mechanism:
    #
    #     bits 0..7  : outcome     (0=Invalid, 1=Valid, 2=Error)
    #     bits 8..15 : error_tag   (0..7 per SpvVerifyErrorTag)
    #
    # Extract via standard arithmetic:
    OP_DUP
    PUSH 256
    OP_MOD
    # Stack: [intent, rc, outcome]
    OP_SWAP
    # Stack: [intent, outcome, rc]
    PUSH 256
    OP_DIV
    # Stack: [intent, outcome, error_tag]
    OP_TOALTSTACK
    # Stack: [intent, outcome] | alt: [txid, error_tag]
    OP_TOALTSTACK
    # Stack: [intent] | alt: [txid, error_tag, outcome]

    # ── Step 4: build result cell via OP_CELLCREATE ──
    # OP_CELLCREATE stack: [linearity, domain_flag, typeHash, owner_id] → [cell].
    # typeHash for ("bsv","spv","verify","result") under the structured
    # 8 by 8 by 8 by 8 construction (core/protocol-types/src/type-hash.ts):
    #   sha256("bsv")[0..8]    = 136523b9fea2b732
    #   sha256("spv")[0..8]    = db1b9104389b7cc6
    #   sha256("verify")[0..8] = a12dd3a7fd3203a4
    #   sha256("result")[0..8] = f6a214f7a5fcda0c
    PUSH 3
    PUSH 0
    PUSH 0x136523b9fea2b732db1b9104389b7cc6a12dd3a7fd3203a4f6a214f7a5fcda0c
    PUSH 0x00000000000000000000000000000000
    OP_CELLCREATE
    # Stack: [intent, result_cell]

    # ── Step 5: write VERSION (1B = 0x01) at payload offset 0 ──
    PUSH 0x01
    PUSH 0
    OP_WRITEPAYLOAD

    # ── Step 6: write OUTCOME (1B) at payload offset 1 ──
    # Pop the most-recently-pushed altstack item (outcome).
    # Note: when outcome equals 0 (Invalid), the stack item is empty
    # bytes and OP_WRITEPAYLOAD writes nothing — the result cell's
    # OUTCOME byte stays at its OP_CELLCREATE default of 0, which is
    # exactly the Invalid encoding. So the no-op is semantically correct.
    OP_FROMALTSTACK
    PUSH 1
    OP_WRITEPAYLOAD

    # ── Step 7 (PR-7d): write error_tag (1B) at payload offset 34 ──
    # Pop error_tag from altstack. Same no-op-for-zero semantics as
    # OUTCOME above: error_tag=None (0) leaves the cell's offset-34
    # byte at OP_CELLCREATE's zero default.
    OP_FROMALTSTACK
    PUSH 34
    OP_WRITEPAYLOAD

    # ── Step 8: write txid (32B) at payload offset 2 ──
    OP_FROMALTSTACK
    PUSH 2
    OP_WRITEPAYLOAD

    # Top of stack = result_cell. MAGIC-prefixed 1024B → truthy →
    # executor.execute returns true → mint dispatcher's stack walk
    # picks up the result_cell, matches its typeHash against
    # emits[] = ["bsv.spv.verify.result"], and emits it to the Dart
    # caller. The original intent cell at slot 0 is skipped by the
    # dispatcher (byte-equal to input_cell).
}

```
