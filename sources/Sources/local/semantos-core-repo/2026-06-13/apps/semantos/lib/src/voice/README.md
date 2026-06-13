---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/voice/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.109555+00:00
---

# voice — canonical PWA substrate primitive

**Track**: C1 (PWA Primitive Forklift). Voice forklift landed 2026-05-28.
**Source**: forklifted from `apps/semantos/lib/src/voice/`.
**Decision basis**: Q1 (brain upload via `/api/v1/voice-extract` for V1; on-device whisper.cpp as future enhancement).

## What's here (first move — slice-path subset)

| File | Purpose |
|------|---------|
| `sir_extractor.dart` | Parses transcript → SIR JSON via an `LlmCompleter`. Layer 2 of the C7 slice. |
| `anthropic_llm_completer.dart` | Concrete `LlmCompleter` calling the Anthropic API via dio. |
| `voice_extract_uploader.dart` | Uploads audio → brain `/api/v1/voice-extract` → transcript. Layer 1 of the C7 slice. |
| `voice_session_service.dart` | Per-session signing for voice uploads (uses identity `cell_signer` + `child_cert_store`). |

All four files import only:
- `dart:*`
- `package:flutter/foundation.dart` (debug only)
- `package:dio/dio.dart` (HTTP)
- `package:pointycastle/digests/sha256.dart`
- `package:semantos_core/semantos_core.dart` (canonical interfaces)
- intra-voice/ + intra-identity/ (identity forklifted in C1 tick 1)

`pubspec.yaml` gains `dio: ^5.7.0`.

## What's deferred (later moves)

| File | Reason |
|------|--------|
| `voice_command_service.dart` | Depends on `../gradient/dart_pipeline.dart` — gradient subsystem not yet forklifted. |
| `text_intent_service.dart` | Same gradient dep + `../repl/jobs_repository.dart`. |
| `voice_text_input_bar_controller.dart` | Same gradient dep. |
| `on_device_voice_factory.dart` | Imports `package:oddjobz_experience/oddjobz_experience.dart` (cross-cartridge contamination) + `package:semantos_ffi/...` (on-device whisper, deferred per Q1). |

Gradient forklift will resurrect the first three. The cross-cartridge factory is structurally wrong and should be rewritten cartridge-side rather than forklifted.

## Status vs C7 golden slice

The slice needs the voice substrate at:
- **Layer 1** (voice capture): `voice_extract_uploader.uploadAudio()` → brain returns transcript.
- **Layer 2** (SIR extraction): `sir_extractor.SirExtractor.extract(transcript)` → SIR JSON.

Both forklifted here. **Wiring** (instantiating these in the canonical PWA's `_BootstrapApp` + connecting to the helm mic) is a third move on C1 that depends on gradient (layer 3+) also being forklifted. After this commit, layers 1+2 narrow from "primitive not present" to "primitive present, awaiting bootstrap wiring + brain endpoint."

`dart analyze apps/semantos/lib/src/voice/` — clean.
