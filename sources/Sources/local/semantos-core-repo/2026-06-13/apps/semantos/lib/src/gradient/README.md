---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/gradient/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.114821+00:00
---

# gradient — canonical PWA substrate primitive

**Track**: C1 (PWA Primitive Forklift). Gradient forklift landed 2026-05-28.
**Source**: forklifted from `apps/semantos/lib/src/gradient/`.

The compression gradient intent pipeline — SIR → OIR → opcode → kernel bytes. Layers 3+4 of the C7 golden slice.

## What's here (slice-path subset, 5 files)

| File | Purpose | Slice layer |
|------|---------|-------------|
| `sir_to_oir.dart` | Semantic Intent (modal + who/what/why) → Operational Intent (verb + cellType + cartridge + hat + payload) | Layer 3 |
| `oir_to_bytes.dart` | OIR → opcode byte sequence for the cell-engine | Layer 4 |
| `dart_pipeline.dart` | Orchestrator chaining SIR → OIR → opcode → kernel call | Layers 3+4 glue |
| `cell_id.dart` | Cell-id derivation utilities (sha256 over canonical bytes) | Layer 5 helper |
| `intent_trace_service.dart` | Per-intent observability (traces each pipeline stage for debug + the `do | find | trace` substrate verb) | Observability |

Intra-package + identity + voice deps only. `sir_to_oir.dart` imports `../voice/sir_extractor.dart` (forklifted in C1 voice tick).

## What's deferred

| File | Reason |
|------|--------|
| `oddjobz_extension_context.dart` | Oddjobz-cartridge-specific (`kOddjobzDomainFlag`). Belongs in `cartridges/oddjobz/experience/` not the canonical shell. Cross-cartridge contamination — needs a structural fix, not a forklift. |
| `entity_resolver.dart` | Imports `../repl/jobs_repository.dart` (oddjobz REPL surface). Same contamination — should be split into substrate-agnostic core + cartridge-side resolver. |
| `production_pipeline_deps.dart` | Pulls semantos_ffi (FFI kernel — not yet wired in canonical shell) + outbox (sqflite outbox — not on slice per Q3 brain-roundtrip decision) + oddjobz_extension_context (above). |
| `intent_inspector_sheet.dart` | Flutter UI surface for trace inspection — useful but not on slice critical path. |

After future cleanup ticks split substrate-from-cartridge code, these forklift cleanly.

## Status vs C7 golden slice

The slice needs gradient at:
- **Layer 3** (OIR resolution): `SirToOirResolver.resolve(sir)` → OIR matching `fixture[layer3_oir][expected]`.
- **Layer 4** (opcode encoding): `OirToBytes.encode(oir)` → opcode sequence matching `fixture[layer4_opcode][expected_sequence]`.

Both forklifted here. **Wiring** (instantiating the DartPipeline in the canonical PWA's `_BootstrapApp` + connecting it to the helm verb dispatch) is a third move on C1 that also needs the shell helm host forklifted.

After this commit, layers 3+4 narrow from "primitive not present" to "primitive present, awaiting bootstrap wiring". Combined with C1 tick 1 (identity) + tick 2 (voice), the slice now has substrate primitives present for layers 1, 2, 3, 4, and 6 (identity → wallet via cell_signer). Layers 5 (cell-engine binding), 7 (brain dispatch), 8 (helm render) still pending.

`dart analyze apps/semantos/lib/src/gradient/` — 1 inherited info-level lint (use_null_aware_elements in monolith's sir_to_oir.dart line 724). No errors. No warnings.
