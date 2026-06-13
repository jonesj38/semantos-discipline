---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/dispatch/intent_dispatcher_factory.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.116930+00:00
---

# apps/semantos/lib/src/dispatch/intent_dispatcher_factory.dart

```dart
/// intent_dispatcher_factory.dart — wires a bare IntentDispatcher onto a
/// connected mint surface (M1.7b: the unified-channel BrainRpcClient).
///
/// Wire-tick 4a (2026-05-28). Builds a ready-to-dispatch IntentDispatcher
/// against the operator's paired brain. Cartridges register THEIR intent
/// bindings into this dispatcher at boot — the factory itself is
/// cartridge-agnostic.
///
/// PR-C9-7c (2026-05-29) — REMOVED the hardcoded `betterment_experience`
/// import + hardcoded `dispatcher.register<Release>(...)` block. The
/// dispatcher comes out empty; each cartridge contributes its own
/// bindings via its `registerXxxIntents(dispatcher)` function called
/// from main.dart after both the dispatcher and the cartridge are
/// available. Shell no longer imports any cartridge package directly.
///
/// M1.7b (2026-06-10) — the factory no longer reads creds + constructs a
/// BrainHttpClient. The shell constructs + connects the BrainRpcClient at
/// boot (M1.6) and passes it here as the [CellMinter], so the dispatcher's
/// mints ride `cells.mint` over the same WSS channel the reads use. A null
/// minter (unpaired / connect failed) ⇒ no dispatcher, caller renders the
/// connect prompt.
library;

import 'cell_minter.dart';
import 'intent_dispatcher.dart';

/// Result of resolving an [IntentDispatcher] from the current connection.
class ResolvedDispatcher {
  /// The constructed dispatcher (empty — cartridges register their own
  /// bindings post-construction). Null when there's no connected minter.
  final IntentDispatcher? dispatcher;

  /// True when no connected minter was available — UI renders the connect
  /// prompt.
  final bool needsPairing;

  const ResolvedDispatcher({
    required this.dispatcher,
    required this.needsPairing,
  });
}

/// Build a bare IntentDispatcher on the supplied [minter] (the connected
/// BrainRpcClient at boot). The returned dispatcher has ZERO intent bindings —
/// cartridges register their own at boot.
///
/// [minter] is null when the brain connection is absent or the boot connect
/// failed; the dispatcher is then null and `needsPairing` true.
Future<ResolvedDispatcher> buildIntentDispatcher({
  required CellMinter? minter,
  MintSigner? signer,
}) async {
  if (minter == null) {
    return const ResolvedDispatcher(dispatcher: null, needsPairing: true);
  }
  return ResolvedDispatcher(
    dispatcher: IntentDispatcher(brain: minter, signer: signer),
    needsPairing: false,
  );
}

```
