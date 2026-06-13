---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-tessera_experience/lib/tessera_experience.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.826637+00:00
---

# archive/packages-tessera_experience/lib/tessera_experience.dart

```dart
/// Tessera experience package.
///
/// Import this from the shell app (`semantos-shell/lib/main.dart`) to
/// register the tessera grammar + lexicon + intent handlers with the
/// ConversationEngine at boot, and to surface the six operator hats
/// (producer, field-worker, distributor, dock-handler, retailer,
/// club-member) in the HatRegistry.
///
/// Usage:
/// ```dart
/// import 'package:tessera_experience/tessera_experience.dart';
///
/// final provisioned = await TesseraManifestLoader.provisionFromAsset(
///   provisioner,
/// );
/// ConversationEngine(
///   grammars: [const TesseraIntentGrammar()],
/// );
/// ```
///
/// The consumer NFC-tap PWA (Wave Tessera V1.6) is a separate
/// codebase — anonymous, no login, no shell composition — and is
/// deliberately NOT part of this package.
library tessera_experience;

export 'src/tessera_client.dart';
export 'src/tessera_intent_grammar.dart';
export 'src/tessera_screen.dart';
export 'src/intents.dart';
export 'src/manifest_loader.dart';

```
