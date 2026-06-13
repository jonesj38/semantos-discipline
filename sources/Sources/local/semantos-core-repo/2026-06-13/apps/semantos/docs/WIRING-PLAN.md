---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/docs/WIRING-PLAN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.090715+00:00
---

# Canonical PWA — _BootstrapApp wiring plan

**Track**: C1 (wiring tick — connects forklifted primitives into a working _BootstrapApp).
**Status**: Plan. Code changes per this plan are the next wiring tick.

## Why this doc

After 6 ticks the canonical PWA has substrate primitives forklifted (identity, voice, gradient) plus a HelmScaffold widget and a betterment_experience package. None of it is wired — `_BootstrapApp` still composes the old jam/tessera/oddjobz path and ignores the new primitives.

C7-D went GREEN on the live brain at oddjobtodd.info. The slice can now reach the brain end-to-end **if** the PWA constructs the right HTTP call. The wiring tick connects voice → SIR → OIR → `POST /api/v1/cells` → helm card render.

## What the V1 slice actually needs (post-fixture-update)

Per `tests/canonicalization/golden-slice/v1_release.fixture.json` layer 7 (now verified live):

```
operator speaks "release: ..."
  → STT → transcript
  → SIR extracted via sir_extractor (LlmCompleter-aided)
  → OIR resolved via sir_to_oir + BettermentIntentGrammar — yields:
     { verb: do.new, cellType: 'betterment.practice.release',
       payload: { rawText, source: 'voice', prompt: 'freeform', elevation: <derived> } }
  → HTTP POST /api/v1/cells with typeHashHex (computed from triple) + payload
  → brain returns { cellId, cartridgeId, cellType, persistedAt }
  → helm AttentionSurface refreshes; new release card renders
```

No wallet sign on V1 wire. No cell-engine FFI needed (brain encodes the canonical 1024-byte cell from typeHashHex + payload). Layers 5 (kernel) and 6 (wallet) are V2-slice work.

## Seams to wire in _BootstrapApp

### Seam 1: cartridge registration

Current `main.dart` registers Oddjobz/Jam/Tessera. C8 archive direction says drop jam + tessera. Add self.

```dart
// REMOVE
import 'package:jam_experience/jam_experience.dart';
import 'package:tessera_experience/tessera_experience.dart';
// ...
JamManifestLoader.provisionFromAsset(provisioner),
TesseraManifestLoader.provisionFromAsset(provisioner),
// ...
registerJamCartridge();

// ADD
import 'package:betterment_experience/betterment_experience.dart';
// ...
BettermentManifestLoader.provisionFromAsset(provisioner),
// ...
registerBettermentCartridge();
```

Pubspec edit: drop `jam_experience` + `tessera_experience` deps; add `betterment_experience: { path: ../../packages/betterment_experience }`.

### Seam 2: BrainHttpClient (POST /api/v1/cells)

New file: `lib/src/brain/brain_http_client.dart`. Single class with:

```dart
class BrainHttpClient {
  final String baseUrl;
  final String bearerToken;
  // ...
  Future<MintCellResult> mintCell({
    required String typeHashHex,
    required Map<String, dynamic> payload,
  }) async {
    // POST $baseUrl/api/v1/cells with bearer auth, return {cellId, cartridgeId, cellType, persistedAt}
  }
}
```

Wired in `_AsyncShell` via `node.brainBaseUrl` + `node.bearerToken` from `bootResolvedNode()`. Already available — `NodeResolver` resolves these from the paired identity store.

### Seam 3: TypeHash computation

New file: `lib/src/gradient/type_hash.dart` — Dart port of `core/cell-engine/src/type_hash.zig::buildTypeHash`. Pure Dart:

```dart
import 'package:pointycastle/digests/sha256.dart';

Uint8List buildTypeHash(String s1, String s2, String s3, String s4) {
  final out = Uint8List(32);
  for (final (i, seg) in [s1, s2, s3, s4].indexed) {
    final h = SHA256Digest().process(utf8.encode(seg));
    out.setRange(i * 8, (i + 1) * 8, h.sublist(0, 8));
  }
  return out;
}
```

8 lines. pointycastle already in pubspec from C1 tick 1.

### Seam 4: Intent → Cell mint dispatch

New file: `lib/src/dispatch/intent_dispatcher.dart`. Bridges OIR → brain HTTP:

```dart
class IntentDispatcher {
  final BrainHttpClient brain;
  // ...
  Future<MintCellResult> dispatch(OperationalIntent oir) async {
    // 1. Resolve cellType triple from manifest (e.g. betterment.practice.release → {self, practice, release, ''})
    // 2. Compute typeHashHex via buildTypeHash
    // 3. brain.mintCell(typeHashHex, oir.payload)
  }
}
```

The cellType → triple resolution can live in the cartridge manifest (each cellType entry already has a triple field per cartridges/betterment/cartridge.json) — loaded into GrammarRegistry via BettermentManifestLoader.

### Seam 5: Helm verb shelf wiring

Currently `HelmScaffold` has `onDoPressed: VoidCallback?`. Wire it to open a verb-picker sheet that lets the operator pick a do-subverb (or, for V1, just goes straight to a "describe your release" textarea + Send button → constructs Release intent → IntentDispatcher.dispatch).

For shortest possible V1, the "DO" button on helm opens:

```
┌─────────────────────────────────────┐
│ What are you releasing?             │
│ ┌─────────────────────────────────┐ │
│ │                                 │ │
│ │  [textarea — capture rawText]   │ │
│ │                                 │ │
│ └─────────────────────────────────┘ │
│                          [ Release ]│
└─────────────────────────────────────┘
```

Tap Release → build Release intent → IntentDispatcher → brain mint → close sheet → AttentionSurface refresh.

### Seam 6: AttentionSurface (placeholder → live)

Currently `_PlaceholderAttentionSurface`. For V1, replace with a `BrainCellsList` that:
- Queries `GET /api/v1/cells?cartridge=self` (or similar — needs brain endpoint check)
- Renders each cell as a card with title from cartridge manifest's displayName + first 80 chars of payload.rawText

C9 AttentionEngine substrate forklift (with Pask-ranked weights) is V2+. V1 just shows recency-ordered list of cells.

## Wiring sequence (each = one commit)

| # | Tick | What | Deps |
|---|------|------|------|
| 1 | C1 wire 1 — manifest + cartridge registry | Drop jam/tessera; add betterment_experience. Pubspec + main.dart edits. | betterment_experience package present (✓ from c2) |
| 2 | C1 wire 2 — typeHash + BrainHttpClient | New files; pure Dart; no main.dart change. | pointycastle (✓), dio (✓) |
| 3 | C1 wire 3 — IntentDispatcher | New file. Stitches OIR → typeHash → BrainHttpClient. | seams 2 + cellType-triple from manifest |
| 4 | C1 wire 4 — helm DO button → Release intent → dispatch | Edit main.dart to wire HelmScaffold callbacks to dispatcher. Adds the simplest possible "describe release" sheet. | seams 1-3 + HelmScaffold (✓ from c9) |
| 5 | C1 wire 5 — AttentionSurface from brain cells | Replace placeholder with BrainCellsList. | seam 2 + brain query endpoint |

After ticks 1-5, the V1 slice can run end-to-end on the canonical PWA against the live brain. This is C7 V1 GREEN.

## Branch integration order

The wiring ticks live on canon-c1-primitives but pull from c2 (betterment_experience) and c9 (HelmScaffold). Two options:

**A. Merge c2 + c9 into c1 first** (single integration commit, then wiring ticks land cleanly).
**B. Pull files into c1 via git show** (copy files from sister branches without merging; messier but no merge commits).

Recommend A. The merges should be clean — no overlapping files. Order: `git merge canon/c2-self-experience` then `git merge canon/c9-helm` on canon-c1-primitives. Use `--no-ff` so the integration is identifiable in log.

## Decisions still required

None blocking — Q1-Q9 cover everything in this plan.

Open question worth raising before wire-tick 5: which brain endpoint returns the cell list for the AttentionSurface? Need to grep brain HTTP routes for `/api/v1/cells` (GET) or similar. If no list endpoint exists, V1 AttentionSurface stays placeholder (the just-minted cellId still surfaces via a "Last release" card built from the mint response).

## Once V1 is green

Move to V2 slice: anchored release cells (sig + pubkey on the wire, BSV pushdrop), wallet integration into the dispatch path, plexusRecoveryEnvelope (C6b) for Root Operator recovery.
