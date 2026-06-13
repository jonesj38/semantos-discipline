---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/semantos_core.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.011949+00:00
---

# platforms/flutter/semantos_core/lib/semantos_core.dart

```dart
/// Semantos platform interfaces.
///
/// Import this package from experience packages (oddjobz_experience,
/// jam_experience) and from the canonical Semantos PWA (apps/semantos). Never import
/// the wallet implementation directly from an experience.
library semantos_core;

export 'src/wallet_service.dart';
export 'src/cell_signer.dart';
export 'src/intent_grammar.dart';
export 'src/brain_wallet_service.dart';

// Target-resolution layer — selects (wallet, kernel, STT, identity)
// tuple per NodeTarget. Generalizes the previous WalletResolver to
// cover all platform-aware seams.
export 'src/node_target.dart';
export 'src/identity_store.dart';
export 'src/stt_provider.dart';
export 'src/node_resolver.dart';

// Extension manifest + runtime grammar registry — load extension
// configs at provision time (JSON, no Dart codegen).
export 'src/extension_manifest.dart';
export 'src/grammar_registry.dart';

// PR-C9-7c introduced a separate `IntentSpec` data class as a
// stop-gap so cartridges could declare dispatch metadata without
// importing the shell. PR-C9-7d removed it — dispatch metadata now
// lives in `HelmUiVerb.dispatch` (a field on the existing manifest
// verb declaration), so the manifest is the single source of truth
// and cartridges don't hand-maintain a parallel constant. See
// extension_manifest.dart `HelmUiVerbDispatch` for the schema.

// Hat composition — per-extension operator roles, composed across
// active extensions into a uniform registry. The shell's active hat
// selects which extension's grammar drives the active conversation
// channel.
export 'src/hat.dart';

// CC2c — Flutter-free cartridge identity/discovery (the Brain
// /api/v1/info maps to this). The Flutter CartridgeEntry +
// CartridgeRegistry live in package:cartridge_sdk (semantos_core
// stays pure Dart).
export 'src/cartridge_descriptor.dart';

// Substrate-portability layer — bundle envelope, signature, verifier,
// and URL/asset/file provisioner. Operators install extensions from
// any URL signed by any author; the shell wires them into the
// GrammarRegistry without any marketplace dependency.
export 'src/extension_bundle.dart';
export 'src/bundle_verifier.dart';
export 'src/manifest_provisioner.dart';
export 'src/brc42_verifier.dart';

// Brain-side runtime installation — push a verified manifest to the
// paired brain so other shells discover it. Backed by manifest_registry.zig.
export 'src/manifest_install_client.dart';

// Generic cell-DAG query primitive — JSON-RPC wrapper + result type.
// Experience packages compose typed repositories on top of this.
export 'src/cell_query_client.dart';

// Generic verb.dispatch primitive — uniform write-seam for declared
// extension action verbs. Experience packages compose typed handler
// wrappers on top of this (e.g. OddjobzRatifyClient).
export 'src/verb_dispatch_client.dart';

// BrainVerbDispatchClient — concrete WSS JSON-RPC transport to a
// paired brain's /api/v1/wallet endpoint. The shell builds one from
// the operator's brainUrl + bearerToken once a pairing is confirmed.
export 'src/brain_verb_dispatch_client.dart';

```
