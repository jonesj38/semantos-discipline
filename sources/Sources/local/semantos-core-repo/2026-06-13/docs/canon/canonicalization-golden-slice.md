---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/canon/canonicalization-golden-slice.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.630248+00:00
---

# Canonicalization Golden Slice

**Status**: the ONE operator action that gates the canonicalization. C7's fixture. Red on day 1; green is the done-line.
**Companion glossary**: `docs/canon/canonicalization-glossary.md`
**Companion matrix**: `docs/canon/canonicalization-matrix.yml`
**Companion brief**: `docs/prd/CANONICALIZATION-BRIEF.md`

---

## §1. Choosing the slice

The slice must:
- Exercise **every layer** the canonicalization touches: voice → STT → SIR → OIR → opcode → kernel cell → unified wallet → brain dispatch → cell persistence → helm render. Optional anchor on-chain.
- Be **specific** — concrete utterance, concrete expected bytes at every stage, no "or equivalent."
- Be **operator-natural** — something Todd would actually say on a job site, not a contrived test phrase.
- Be **small in scope but full in depth** — one verb, one cartridge, one principal — but every layer touched end-to-end.
- Be **independently re-runnable** — given a fresh canonical PWA + fresh canonical brain + a Root Operator identity, the test executes and the fixture matches.

### Chosen slice (V1 — confirm with user before locking)

**Utterance** (operator speaks into the helm mic):
> "release: I'm letting go of the pressure to make every interaction perfect."

**Why this one**:
- Uses the **self** cartridge — exercises the canonical PWA's default helm surface (oddjobz hat would be the alternative; self is chosen because it has fewer accreted dependencies, smaller blast radius for C1+C2 slice scope, and the self cartridge.json already declares the `daily-release` flow at `triggerIntents: ["release"]`).
- Resolves to `do | self | release` — the `do` modal, the most consequential of the three because it mutates state and (optionally) signs a cell.
- The substrate sub-verb is `new` — creates a new `betterment.practice.release` cell, the simplest of the 5 do-subverbs to exercise.
- Doesn't require chain anchor on the first pass (`anchor: optional` in the manifest). Anchoring becomes a follow-up axis once unanchored persistence works.
- Doesn't require external counterparty (no customer to dereference, no contact PKI lookup) — keeps the surface small.

---

## §2. Expected trace, layer by layer

### Layer 1 — Voice capture
- Operator presses mic button on helm.
- PWA captures audio via the canonical voice subsystem (forklifted in C1 from monolith `lib/src/voice/`).
- Audio uploaded to brain `POST /api/v1/voice-extract` (or processed via on-device whisper.cpp if that path lands first — decided in C0 decisions doc).
- **Acceptance**: brain or local STT returns a transcript matching the utterance verbatim (modulo casing/punctuation).

### Layer 2 — SIR (Semantic Intent Representation)
Per WALLET-VOICE-SHELL-GRAMMAR.md, the LLM-aided parser converts transcript → SIR:

```json
{
  "modal": "do",
  "who": "betterment",
  "what": "release",
  "why": null,
  "payload": {
    "rawText": "I'm letting go of the pressure to make every interaction perfect."
  }
}
```

- **Acceptance**: parser output matches this SIR. Test runs the parser against the transcript string and asserts JSON equality (modal/who/what + payload.rawText).

### Layer 3 — OIR (Operational Intent Representation)
The gradient pipeline (forklifted from monolith `lib/src/gradient/`) resolves SIR against the active cartridge's grammar:

- Cartridge: `self` (manifest at `cartridges/betterment/cartridge.json`)
- Triggered flow: `daily-release` (the flow with `triggerIntents: ["release"]`)
- Steps in the flow: `source`, `prompt-choice`, `write` — the parser uses LLM-aided inference to map the single utterance into the `write` step's `rawText` field (other steps remain unset for this short-form utterance; they'd be filled by follow-up turns in a multi-turn capture).
- `onComplete` action: `{ type: "create", objectType: "betterment.practice.release" }`

OIR:

```json
{
  "verb": "do.new",
  "cellType": "betterment.practice.release",
  "cartridge": "betterment",
  "hat": "betterment",
  "payload": {
    "rawText": "I'm letting go of the pressure to make every interaction perfect."
  },
  "anchor": "optional"
}
```

- **Acceptance**: gradient pipeline output matches this OIR. Test runs the SIR→OIR resolver against the SIR fixture and asserts JSON equality.

### Layer 4 — Opcode
The opcode layer (forklifted from monolith `lib/src/gradient/oir_to_bytes.dart`) renders OIR into the kernel's cell-mutation opcode sequence.

Expected opcode form (illustrative — exact bytes locked in canonicalization-decisions.md):
```
OP_NEW_CELL   typehash=betterment.practice.release (32B)
OP_SET_FIELD  rawText, "I'm letting go..."
OP_SIGN       hat=self
OP_PERSIST
```

- **Acceptance**: opcode bytes are deterministic given the OIR. Test asserts byte-equality against a recorded fixture.

### Layer 5 — Kernel cell
The cell-engine constructs the 1024-byte canonical cell:

- Header: `MAGIC` + `LINEARITY=LINEAR` (betterment.practice.release is LINEAR per the manifest) + `VERSION=1` + `TYPE_HASH=sha256("betterment.practice.release")` + `OWNER_ID=hat:self pubkey` + `TIMESTAMP` + `PAYLOAD_TOTAL=rawText length` + `PARENT_HASH=0x00...` (root cell) + `DOMAIN_PAYLOAD_ROOT=sha256(payload)`.
- Payload: serialized `rawText` field per cell-engine canonical encoding.
- Cell hash: `sha256(canonical-cell-bytes)`.

- **Acceptance**: cell bytes match a recorded fixture except for `TIMESTAMP` (which is per-run) and `OWNER_ID` (which is per-Root-Operator). Hash is computed and recorded.

### Layer 6 — Unified wallet sign
The unified wallet module (C6a) signs the cell-hash with the Root Operator's hat-derived key:

- Signature: `secp256k1.sign(hash, hat:self privkey)` → 64-byte sig.
- Pubkey: hat:self derived pubkey (33-byte compressed).

- **Acceptance**: signature verifies against `(cell-hash, hat:self pubkey)`. The wallet module surface in the test is identical whether called from the PWA's `WalletService` or the brain's HTTP surface (this is C6a's whole point).

### Layer 7 — Brain dispatch
PWA POSTs the signed cell to the brain's REPL:

```http
POST /api/v1/repl HTTP/1.1
Authorization: Bearer <token>
Content-Type: application/json

{"cmd": "do.new", "cell": "<base64-canonical-cell>", "sig": "<hex-sig>", "pubkey": "<hex-pubkey>"}
```

Brain:
- Verifies signature.
- Routes to the self cartridge's brain-side handler (registered via the C5 extension-loader seam, sourced from `cartridges/betterment/brain/zig/`).
- Handler invokes the `release-consumption` enforcement hook (declared in the manifest) — since this is a `new` cell, the hook is a no-op for now; it'd fire on subsequent consume operations.
- Persists the cell to the brain's cell-store.
- Returns success.

- **Acceptance**: brain returns 200 with `{"result": "<cell-id-hex>", "persisted": true}`. The cell-id matches the SHA-256 of the canonical cell bytes.

### Layer 8 — Helm render
PWA, on success response, refreshes the helm's attention surface. The new release cell appears as a card on the right panel — title from `displayName: "Release"` in the manifest, snippet from `rawText` first 80 chars, timestamp from cell header.

- **Acceptance**: attention surface query returns the new cell as one of its items; renderer produces a card matching the manifest's `displayName` + first 80 chars of `rawText`. Tested via the attention surface's deterministic ordering against a known input set.

### Layer 9 — Optional anchor (deferred for V1 slice)
For V1, `anchor: optional` and we skip the chain step. V2 of the slice exercises:
- Brain calls unified wallet to construct a pushdrop anchoring `cell-hash`.
- Wallet submits via ARC to BSV mainnet.
- Brain stores `anchorTxid` against the cell.
- Helm card displays an "anchored" badge.

This is recorded as a follow-on slice (`slice-v2-anchored.md`) once V1 is green.

---

## §3. Running the test

The test lives at:
```
tests/canonicalization/golden-slice/
  v1_release.dart            # PWA-side test (Flutter test harness)
  v1_release.zig             # brain-side test (zig build test)
  v1_release.fixture.json    # the expected SIR + OIR + opcode bytes + cell bytes (sans timestamp/owner) + sig structure
  README.md                  # how to run, what passing means
```

Runners:

```bash
# PWA side — runs in the canonical Flutter app's test harness
cd apps/semantos && flutter test test/canonicalization/golden-slice/v1_release.dart

# Brain side — runs in the brain's zig test harness
cd runtime/semantos-brain && zig build test -j1 --summary all -- canonicalization/golden-slice

# End-to-end — boots an in-process brain + Flutter test harness with a mock STT + mock wallet keys
cd apps/semantos && flutter test integration_test/golden_slice_v1_release.dart
```

**Test passing means**: every acceptance bullet in §2 (layers 1–8) holds, byte-exact where stated, semantically-equal where stated. The brain receives, signs-verifies, persists. The helm card renders.

**Test failing means**: the canonicalization is not done, regardless of what the matrix says. No track may claim ✓ on its `C` (tests) axis without re-running this test and reporting the new state.

---

## §4. What this slice deliberately does NOT cover

- **Multi-turn capture** (the `daily-release` flow actually has 3 steps: source / prompt-choice / write — the slice short-circuits into a single utterance hitting `write`. Multi-turn is V3.)
- **Other cartridges** (oddjobz, jam-room, etc — those exercise their own slices once their critical paths green).
- **Other modal verbs** (slice exercises `do`; `find` and `talk` get their own slices: `slice-v1-find.md` and `slice-v1-talk.md` track them.)
- **Anchoring** (V2 slice).
- **Plexus recovery** (C6b territory — slice uses bearer token or BRC-42-derived auth for V1).
- **Hat switching mid-action** (V4 slice).
- **Conflict resolution / outbox replay** (V5 slice).

These are NOT failures of the slice. They're explicit non-goals, listed so reviewers don't expand C7 by stealth into "the whole substrate works."

---

## §5. Per-layer slice-scope mapping

Tracks contribute to the slice critical path as follows. Anything not on this list is FULL-SCOPE work that follows the green slice:

| Track | Slice-scope work |
|-------|------------------|
| **C1** | Forklift these primitives only: `identity`, `voice`, `gradient`, `repl`, `talk` (for SIR scope only), `shell` (for helm host). Other 8 primitives deferred. |
| **C2** | Create `packages/betterment_experience/` with the minimum surface to render a release flow + a release card. Oddjobz extraction deferred (off-slice). |
| **C3** | No work — rename deferred to after slice green. |
| **C4** | Move `cartridges/betterment/brain/` handler for `do.new betterment.practice.release` + cell persistence. Other brain handlers deferred. |
| **C5** | Wire extension loader for the one self handler. Generic `registerInto(*Dispatcher)` contract designed and used by self handler only. Other cartridges still hardcoded for V1; extension loader expands in full-scope phase. |
| **C6a** | Wallet code path for `sign(hash, hat:self privkey)` from both PWA WalletService and brain HTTP. Full wallet feature parity deferred. |
| **C6b** | Not on slice. Slice uses bearer token; plexusRecoveryEnvelope spec written in parallel as separate doc. |
| **C7** | THIS DOC. The test fixture + the runner stub. |
| **C8** | Delete dead code touched by C1/C2/C4 as we go. No bulk archival on slice path. |
| **C9** | Helm primitive enough to render the verb shelf + the new release card. Surfacing-mode contract designed; only `default` mode exercised by slice. |

---

## §6. Open questions blocking the slice

Captured here so they get answered in `canonicalization-decisions.md` before C1 code moves:

1. **STT path**: on-device whisper.cpp (FFI in the canonical PWA) or brain `/api/v1/voice-extract` upload? Slice can run with either. Decision affects which voice primitive lives in C1.
2. **Helm Flutter widget vs Flutter webview**: native Flutter helm widget (preferred) or webview hosting the brain's helm web surface (faster initial?). Decision affects C9.
3. **Cell-store**: does the canonical PWA ship its own LMDB-equivalent (sqflite, idb) or does it cell-roundtrip through the brain for every state mutation? Affects whether the slice tests local persistence or brain-roundtrip persistence.
4. **Wallet key custody**: where does hat:self's privkey live on the PWA? Android Keystore (per `semantos_shell_native_identity` package) vs the unified wallet's own custody. Affects C6a.
5. **`anchor: optional` default behavior**: when the operator doesn't explicitly opt to anchor, does the verb default to local-only or to chain? Affects the wallet code path's hot-path.
