---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/canonicalization/golden-slice/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.591039+00:00
---

# C7 Golden Slice — V1 Release

This directory holds the **gate test** for the canonicalization. RED on day 1; goes green cell-by-cell as canonicalization tracks (C1, C2, C4, C5, C6a, C9) land their slice-scope contribution.

The rule:

> **No canonicalization track may claim ✓ on its `C` (tests) axis without re-running this test and reporting the result in its matrix cell note.**

---

## What this tests

ONE operator action — chosen as the golden slice that exercises every layer the canonicalization touches:

```
operator speaks "release: I'm letting go of the pressure to make every interaction perfect."
   │
   ▼ layer 1 — voice capture + STT (C1: voice forklift)
transcript
   │
   ▼ layer 2 — SIR extractor (C1: voice forklift)
SIR { modal: do, who: self, what: release, payload: { rawText: ... } }
   │
   ▼ layer 3 — gradient resolver (C1: gradient forklift; C2: betterment_experience cartridge registered)
OIR { verb: do.new, cellType: betterment.practice.release, cartridge: self, hat: self, payload, anchor: optional }
   │
   ▼ layer 4 — opcode encoder (C1: gradient forklift)
[ OP_NEW_CELL, OP_SET_FIELD rawText, OP_SIGN hat:self, OP_PERSIST ]
   │
   ▼ layer 5 — cell-engine emits 1024-byte canonical cell (C1: cell-engine binding)
1024-byte cell with betterment.practice.release type hash
   │
   ▼ layer 6 — unified wallet signs sha256(cell) (C6a: wallet unification)
64-byte secp256k1 sig + 33-byte compressed pubkey
   │
   ▼ layer 7 — brain dispatch (C4: extract handler; C5: extension loader wires it)
POST /api/v1/repl → 200 { result: cell-id, persisted: true }
   │
   ▼ layer 8 — helm renders new release card (C9: helm widget; C2: card renderer)
release card on attention surface
```

Layer 9 (chain anchor) is **deferred to V2 slice** — Q5 decision set `anchor: optional` default to local-only, so V1 doesn't exercise BSV chain.

---

## Files

| File | Purpose |
|------|---------|
| [v1_release.fixture.json](v1_release.fixture.json) | The contract — expected SIR/OIR/opcode/cell/wallet/dispatch/render shapes. Both Dart and Zig tests assert against this. |
| [v1_release.dart](v1_release.dart) | PWA-side test — 8 layer assertions + 1 end-to-end. Currently 9 RED tests that throw `LayerNotWired` with the responsible track id and a "what to do when wiring lands" hint. |
| [v1_release.zig](v1_release.zig) | Brain-side test — 4 assertions covering dispatch, persistence, brain wallet path, extension-loader discovery. Currently 4 RED tests via `LayerNotWired` error. |
| `README.md` | This file. |

---

## How to run

### Dart side (PWA layers 1–6, 8)

Before the canonical PWA exists at `apps/semantos/`:
```bash
cd tests/canonicalization/golden-slice
dart pub global activate test  # one-time, if needed
dart test v1_release.dart
```

After the canonical PWA exists (full integration test):
```bash
cd apps/semantos
flutter test ../../tests/canonicalization/golden-slice/v1_release.dart
```

**Expected output (today, day 1)**: 9 red tests, each printing the layer name + responsible track + actionable "what to do when wiring lands" message. No silent failures.

### Zig side (brain layers 6 brain-side, 7, 7b, 7c)

```bash
# Once the brain test harness includes this file (TODO: add to runtime/semantos-brain/build.zig test set):
cd runtime/semantos-brain
zig build test -j1 --summary all

# Or directly:
zig test ../../tests/canonicalization/golden-slice/v1_release.zig
```

**Expected output (today, day 1)**: 4 red tests, each emitting a structured `LayerNotWired` print + erroring out.

---

## What "passing" means

A layer passes when:

1. Its wiring is landed at the source location named in `_source` fields of the fixture.
2. Re-running the test executes that wiring against the fixture's input.
3. The output matches the fixture (byte-equal where stated, semantically-equal where stated, structurally-equal for `_runtime` fields).

A track passes (claims ✓ on its `C` axis) when:

1. All layers it owns are passing in this test.
2. The matrix cell note for that track records: which layers, the date, and the test runner output summary.

The whole canonicalization passes (declares done) when:

1. All 9 Dart tests + all 4 Zig tests are green.
2. `v1_slice_acceptance.definition` in the fixture is satisfied.
3. End-to-end test in `v1_release.dart` (last test) is green — composite of layers 1–8.

---

## How layers go green

| Layer | Track(s) | First moment it can go green |
|-------|----------|------------------------------|
| 1 voice | C1 (voice forklift) + brain `/api/v1/voice-extract` | When `voice_extract_uploader.dart` is forklifted from monolith to canonical PWA |
| 2 SIR | C1 (sir_extractor forklift) | When `sir_extractor.dart` is forklifted |
| 3 OIR | C1 (sir_to_oir forklift) + C2 (betterment_experience cartridge registered) | When both resolver code + self cartridge manifest are loaded |
| 4 opcode | C1 (oir_to_bytes forklift) | When encoder is forklifted |
| 5 cell | C1 (cell-engine binding) | When cell-engine FFI is wired in canonical PWA |
| 6 wallet sign | C6a (wallet unification) | When unified wallet module is callable from both PWA + brain |
| 7 brain dispatch | C4 (extract self handler) + C5 (extension loader) | When self handler is at `cartridges/betterment/brain/zig/` AND extension loader registers it |
| 7b persistence | C4 | When cell-store path for self cells is wired |
| 7c handler discovery | C5 | When the handler reaches dispatcher via extension-loader contract, not hardcoded `register()` |
| 8 helm card | C9 (helm widget) + C2 (card renderer) | When canonical helm + betterment_experience card renderer both exist |

---

## When V1 is green

Move to V2 — anchored slice. Same utterance, but `--anchor` flag wires layer 9 (BSV pushdrop via unified wallet). V2 fixture lives at `v2_release_anchored.fixture.json` (TBD).
