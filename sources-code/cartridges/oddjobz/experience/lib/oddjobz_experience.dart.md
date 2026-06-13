---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/oddjobz_experience.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.454398+00:00
---

# cartridges/oddjobz/experience/lib/oddjobz_experience.dart

```dart
/// Oddjobz experience package.
///
/// Import this from the shell app (`semantos-shell/lib/main.dart`) to
/// register the oddjobz grammar + lexicon + intent handlers with the
/// ConversationEngine at boot.
///
/// Usage:
/// ```dart
/// import 'package:oddjobz_experience/oddjobz_experience.dart';
///
/// ConversationEngine(
///   grammars: [OddjobzIntentGrammar()],
/// )
/// ```
library oddjobz_experience;

export 'src/oddjobz_intent_grammar.dart';
export 'src/oddjobz_screen.dart';
export 'src/intents.dart';
export 'src/manifest_loader.dart';
export 'src/cartridge.dart';
export 'src/operator/quote_document.dart';
export 'src/operator/quote_catalog.dart';
export 'src/operator/quote_catalog_store.dart';
export 'src/operator/quote_editor_screen.dart';

export 'src/operator/operator_shell.dart';
export 'src/operator/oddjobz_rpc.dart';

```
