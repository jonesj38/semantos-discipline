---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/swarm/brain/DAM-HANDOFF.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.680040+00:00
---

# Engine-Checked Data Access (DAM) — Handoff

**Branch:** `feat/paid-swarm` (PR #956) · **Status:** DAM-1 + DAM-2 done + green; DAM-3/4 remain.
**Plan of record:** `~/.claude/plans/jiggly-munching-crab.md` (the approved Slice-1 plan — read it first).
**Governing design:** `docs/design/LOCKSCRIPT-CLEAVAGE.md` (the cleavage apparatus this is built on).
**Session memory:** `~/.claude/projects/-Users-toddprice-projects/memory/paid_swarm_cartridge.md`.

---

## 0. What this is

A **substrate-native data-access scheme**: sharing a file (a cell/cell-tree) with a
contact is a *revocable, scoped, private* grant whose conditions are **checked by the
cell engine (the 2-PDA)** — NOT by application TS. It sits on top of the Metered
Content Transfer primitive (the swarm) built earlier this branch.

The grant is a **`.handler` script the real 2-PDA evaluates** (cleavage model): a
contact proves access by signing a challenge with their edge-derived key; the brain
runs the handler (via its mint/dispatch pipeline) to grant/deny. Reference-mode is
the default (content stays on my brain; the grant is revocable). Confidentiality is
the already-shipped edge cipher (`runtime/session-protocol/src/swarm/transfer-cipher.ts`).

**Two corrections were made during design — both load-bearing, both honoured now:**
1. Enforcement must be in the **engine (2-PDA)**, not app-layer TS.
2. The challenge digest is the **canonical BIP-143 ctx preimage**, not an ad-hoc hash.

---

## 1. The broader arc already landed on this branch (context)

Metered Content Transfer primitive, all green, all pushed:
- A `MeteredTransfer` facade + B `LayeredBrainClient` (brain→overlay SLAP→UHRP) — `9fb9a89`
- C overlay seeder ads + txid↔IPv6 rendezvous — `afe440d`
- D `transfer.*` brain verbs over the shared swarm tracker — `0e028fb`
- E brain-to-brain cell sync (2nd consumer) — `5048dda`
- F torrent client over the primitive — `a610ea7`
- Shell substrate (`ctx.transfer` + `transfer.*` verbs) — `578bd14`
- Cross-internet WSS transport (relay + `wssSwarmTransport`) — `0156c91`
- Merged `origin/main` in (XMPP + contacts + BCA now in tree) — `baae5f00`
- Contacts↔transfer: `contactBcaResolver` + `contactSeederRegistry` — `0bf7eb330`
- Edge-key encryption (`transfer-cipher.ts`) — `8cf067216`

DAM (this doc):
- **DAM-1 `access_grant_context.zig` ScriptContextBuilder — `9e5c9953c`**
- ctx-preimage fix (BIP-143 sighash, not ad-hoc) — `ef52654e0`
- expiry gate in the builder — `9e9b86175`
- **DAM-2 `access_grant_handler.zig` verify .handler + reject-path 2-PDA tests — `eabf8f275`**

Swarm TS suite ~101 green; brain `zig build test` EXIT=0.

---

## 2. What DAM-1 actually does (done + green)

`cartridges/swarm/brain/access_grant_context.zig` — the `ScriptContextBuilder` the
brain runs **before** the verify `.handler` on the real 2-PDA (mirrors
`runtime/semantos-brain/src/cells_mint_spv_context.zig`). On an
`access.grant.verify.intent` cell it:

1. gates on the verify-intent typeHash (else returns null → no Context);
2. loads the referenced **LINEAR `access.grant`** cell from the cell store;
3. checks it carries `capability_type == DATA_ACCESS (2)`;
4. **expiry gate** (`State.now_fn`): expired → returns null;
5. computes the **canonical BIP-143 challenge digest** via `accessChallengeDigest()`;
6. builds a `host_verify_partial_sig.Context {pubkey=grantee, digest=ctx-preimage, signature}`;
7. `extra_cells_fn` pushes the grant cell onto the PDA stack (slot 1) for the handler's
   in-script scope check; `@fieldParentPtr` teardown frees the owned grant copy + digest.

6 inline tests. Wired into `runtime/semantos-brain/build.zig` (module
`access_grant_context_mod` with imports cells_mint_handler / host_verify_partial_sig /
**sighash** / cell_store / constants, + an inline-test step).

`accessChallengeDigest(grant_hash, grantee_pubkey)` is the **SPEC**: a synthetic
1-in/1-out access tx — `input.prev_txid = grant_hash`, P2PK scriptCode
`<pubkey> OP_CHECKSIG`, `SIGHASH_ALL|FORKID (0x41)` — hashed via the SAME
`sighash.computeSigHashDispatch` the engine uses. The grant hash content-addresses the
grant, so the digest transitively commits to its domain/content/expiry/grantee.

---

## 3. BE CAREFUL OF (the gotchas that will bite)

1. **First Bash each session: `cd /Users/toddprice/projects/worktrees/paid-swarm`.**
   cwd drifts (esp. after `cd runtime/semantos-brain` for zig). `git add` from the
   wrong dir fails with "pathspec did not match".
2. **`zig build test` MUST run unsandboxed** (`dangerouslyDisableSandbox: true`). In
   Zig 0.15 **no summary / EXIT=0 = pass**. Run from `runtime/semantos-brain`.
3. **The challenge digest is the canonical ctx preimage — replicate it byte-for-byte
   in TS (DAM-3).** The grantee signs `accessChallengeDigest(...)`; if the TS side
   builds a different synthetic tx (different field order, value, sighash flag), the
   signature will NEVER verify. Port `accessChallengeDigest` exactly (same TxContext:
   version=2, locktime=0, 1 input prev_txid=grant_hash vout=0 seq=0xFFFFFFFF, 1 output
   value=0 script_len=0, subscript = `0x21 ‖ pubkey ‖ 0xAC`, type 0x41). Use `@bsv/sdk`'s
   BIP-143 sighash and confirm it equals the Zig digest with a cross-impl vector.
4. **`host_get_blocktime` is a WASM `extern`, NOT a named hostcall.** You CANNOT do
   `OP_CALLHOST "host_get_blocktime"` in the handler (returns 0xFFFFFFFF unknown; native
   `host.getBlocktime()` returns 0). Expiry lives in the builder (`now_fn`) — done.
   Don't "fix" this by adding it to the handler.
5. **OP_CALLHOST result convention:** `rc=0` pushes **empty (falsy)**; `rc≠0` pushes
   truthy. `host_verify_partial_sig` returns 0=valid. So the verify gate is
   `OP_CALLHOST OP_0 OP_EQUAL OP_VERIFY` (traps on rc≠0). Do NOT naively
   `OP_CALLHOST OP_VERIFY` (would trap on success) — and don't invert.
6. **Handler stack at entry:** slot 0 = input `verify.intent`; slot 1 = the grant cell
   (pushed by `extra_cells_fn`). Copy the grant to top with `OP_1 OP_PICK`. After
   execution, slot 0 must still be the input cell; the emit-walker treats any other
   full-1024B slot as an emitted cell (gated by the manifest `emits[]` allowlist).
7. **`@fieldParentPtr` teardown:** `build` returns `&wrapper.sig_ctx` (the inner
   Context the engine reads via `setExecutionContext`); `destroy` recovers the wrapper
   with `@fieldParentPtr("sig_ctx", ...)`. Returning `&wrapper` would mis-cast in
   `host_verify_partial_sig`.
8. **Swarm cartridge registers via the `cartridge_boot.zig` TABLE (`SwarmSpec`), NOT a
   `cartridge.json`.** The exploration agent's report assumed the JSON-populate path
   (`cartridge_cell_boot.populateRegistryFromCartridgeJson`). VERIFY the real path for
   registering the 3 cell types + the handler + wiring the ScriptContextBuilder (likely
   `MintContextRegistry.add` via the cartridge seam / `serve.zig`). This is the DAM-4
   open question — resolve it FIRST.
9. **Reject-path dispatch tests don't need a valid signature** (they trap at
   `OP_CHECKCAPABILITY` / `OP_VERIFY`, before `OP_CELLCREATE`) → test those in Zig. The
   **valid-sig GRANT path needs a real ECDSA sig** → test from TS (DAM-3) where signing
   the digest is trivial. A reject-path Zig test can use a placeholder result typeHash.
10. **git hygiene:** scope `git commit <paths>` (parallel sessions stage files); the
    branch can fast-forward main↔feat (treat clean FF as sync, not divergence); re-check
    branch right before commit. Never break the brain build/boot — it blocks everything.
11. **build.zig is 9700+ LOC, shared.** Module + inline-test wiring pattern: a
    `b.createModule` block near the swarm modules (~line 3438) + a `b.addTest` step near
    the swarm inline tests (~line 5733). Mirror `access_grant_context_mod` exactly.

---

## 4. WHAT TO DO NEXT (DAM-2 → DAM-4)

### DAM-2 — the verify `.handler` + a reject-path dispatch test (engine-checked) ✅ DONE (`eabf8f275`)
Landed as `cartridges/swarm/brain/access_grant_handler.zig` (`VERIFY_INTENT_HANDLER`
bytecode + `RESULT_TYPE_HASH` + 4 inline tests), wired in build.zig as
`access_grant_handler_mod`. `zig build test` EXIT=0. **Two corrections to the
pseudocode below, found against the real engine:**
- **No `OP_PICK`.** The dispatcher pushes input-first (slot 0) then extra cells
  (slot 1), so the grant is ALREADY on top at entry. `OP_1 OP_PICK` would copy the
  *intent*. The shipped handler drops it — `OP_2 OP_CHECKCAPABILITY` reads the grant
  in place.
- **Non-LINEAR traps as `invalid_linearity_type`, not `capability_type_mismatch`,
  when the linearity field is 0** (`getLinearity` does `intToEnum`, enum is 1/2/3, so
  0 errors before the `lin != .linear` check). A well-formed RELEVANT(3) cell is what
  yields the mismatch. Tests use RELEVANT for the "non-LINEAR rejected" case.
- The reject tests drive the handler DIRECTLY (manual stack + manual `sig_ctx`), NOT
  through DAM-1's builder — the builder already null-rejects a wrong-cap grant (so it
  never reaches the handler's gate); the composite is DAM-4.

The shipped handler (for reference; `OP_CHECKDOMAINFLAG` omitted — scope binds via the
ctx-preimage digest, so NO hardcoded domain in the script):
```
# slot0=verify.intent, slot1=grant cell, Context=host_verify_partial_sig.Context
OP_1 OP_PICK                       # copy grant to top
OP_2 OP_CHECKCAPABILITY OP_DROP    # grant.capability == DATA_ACCESS(2), else trap
PUSH "host_verify_partial_sig"
OP_CALLHOST OP_0 OP_EQUAL OP_VERIFY  # sig over the ctx-preimage digest verifies, else trap
OP_3 OP_0 PUSH<resultTypeHash:32> PUSH<ownerId:16> OP_CELLCREATE
OP_1 OP_0 OP_WRITEPAYLOAD          # result.payload[0] = 1 (ok)
# final stack: [intent, grant, result] — truthy
```
Encode to hex (the committed manifests store handlers as hex; or use
`zig run core/cell-engine/tools/asm.zig -- handler.cs`). Write a Zig dispatch test
mirroring the PR4b harness in `cells_mint_handler.zig` (~lines 926-986): init PDA +
ScriptArena, push input + grant cells, `host.setExecutionContext(&sig_ctx)`,
`ctx.loadScript(&HANDLER)`, `executor.execute(&ctx)`. Assert: **wrong capability →
`error.verify_failed`/trap; bad sig → trap.** (Result typeHash can be a placeholder
since reject paths trap before `OP_CELLCREATE`.) This proves the handler runs + rejects
on the real 2-PDA. New test module needs imports: `pda`, `executor`, `allocator`/
ScriptArena, `host` — wire them in build.zig like the existing executor tests.

### DAM-3 — TS access-grant cells + recipe + contribution (and the GRANT path)
`runtime/session-protocol/src/swarm/access-grant.ts`:
- payload encoders for `access.grant` (cap=2 ‖ grantee_pubkey ‖ content_hash ‖ expiry)
  + `access.grant.verify.intent` (grant_hash ‖ sig_len ‖ sig) + `.verify.result`.
- grantee key via the **derivation recipe** (`core/protocol-types/src/bsv/derivation-recipe.ts`,
  `counterpartyKind=SPECIFIC`, `counterpartyPubkey=contact`) — same edge BRC-42 as
  `transfer-cipher.ts` (`cartridges/wallet-headers/brain/src/ecdh42.ts`
  `buildRotatedLock`/`deriveEdgeSk`).
- **Port `accessChallengeDigest` to TS (see gotcha #3)** + sign it with the edge key →
  the `bsv.tx.partial.contribution` (`core/protocol-types/src/bsv/tx-partial.ts`).
- Test the GRANT path end-to-end (valid sig → result emitted) once DAM-4 wires the boot.

### DAM-4 — register cell types + builder; end-to-end dispatch test
Resolve the table-vs-json registration path (gotcha #8). Register `access.grant`,
`access.grant.verify.intent` (+ handler), `access.grant.verify.result` (in `emits[]`),
and wire `access_grant_context.toBuilder(&state)` into the brain via
`MintContextRegistry`. End-to-end test: valid grant → `verify.result{ok}`; expired /
wrong-key / wrong-cap → reject. `zig build test` + `bun test` green.

### Deferred slices (NOT this slice — see the plan)
- **Issue**: `access.grant.create.intent` handler (mint the LINEAR grant) + a
  `transfer.share-with-contact` verb that issues it + edge-seals the content.
- **Transfer-serve integration**: the seeder/brain runs the verify handler before
  serving; **revocation = consume/rotate the LINEAR grant** (linear cell semantics).
- **On-chain leg**: consensus `.lockScript` (P2PK/P2PKH to the grantee's derived key) +
  the `bsv.tx.sign.request` funding path → miner-enforceable.
- **FS overlay**: a `shared-with-me/<contact>` SemanticFS subtree (new VFS prefix +
  the `async-resolver.ts` lazy pattern) + a `share` shell verb.

---

## 5. Key files / reuse map

| Need | File |
|---|---|
| The builder (DAM-1, done) | `cartridges/swarm/brain/access_grant_context.zig` |
| ScriptContextBuilder seam + `MintContextRegistry` | `runtime/semantos-brain/src/mint_context.zig` |
| Builder pattern to copy | `runtime/semantos-brain/src/cells_mint_spv_context.zig` |
| Run handler on 2-PDA + dispatch test harness | `runtime/semantos-brain/src/cells_mint_handler.zig` (`dispatchCellScriptHandler`, PR4b tests) |
| Sig-verify hostcall (Context shape) | `core/cell-engine/src/host_verify_partial_sig.zig` |
| Sighash / ctx preimage | `core/cell-engine/src/{sighash,host_compute_sighash}.zig` |
| Scope opcodes (CHECKDOMAINFLAG/TYPEHASH/CAPABILITY) | `core/cell-engine/src/opcodes/plexus.zig` |
| Assembler | `core/cell-engine/tools/asm.zig` |
| Challenge-response cell | `core/protocol-types/src/bsv/tx-partial.ts` |
| Grantee key (edge BRC-42) | `core/protocol-types/src/bsv/derivation-recipe.ts`, `cartridges/wallet-headers/brain/src/ecdh42.ts` |
| Confidentiality (shipped) | `runtime/session-protocol/src/swarm/transfer-cipher.ts` |
| Cleavage invariant + sign.request seam | `docs/design/LOCKSCRIPT-CLEAVAGE.md` §3.5 / §4c / §8.2 |

**Cleavage invariant to preserve:** no `.handler` byte ever enters a Bitcoin sighash.
The brain builds the ctx-preimage digest BEFORE the handler runs; the handler only
verifies — it never constructs the bytes the wallet/grantee signs.
