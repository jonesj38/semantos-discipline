---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/packages-jam_experience/lib/jam_experience.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.811731+00:00
---

# archive/packages-jam_experience/lib/jam_experience.dart

```dart
/// Jam Room experience package.
///
/// Import this from the shell app (`semantos-shell/lib/main.dart`) to
/// register the jambox grammar + lexicon + intent handlers with the
/// ConversationEngine at boot — alongside any other experience packages
/// the operator has installed.
///
/// Vocabulary anchored on the JamboxObjectKind union in
/// `apps/world-apps/jam-room/src/semantic/objects.ts` and the action
/// verbs in `docs/prd/jam-room/PHASE-A-VOCABULARY-AND-RACK.md`.
///
/// Usage:
/// ```dart
/// import 'package:jam_experience/jam_experience.dart';
/// import 'package:oddjobz_experience/oddjobz_experience.dart';
///
/// // Multi-extension shell boot: load both manifests, register both
/// // grammars, compose both hat sets.
/// final oddjobz = await OddjobzManifestLoader.provisionFromAsset(provisioner);
/// final jambox  = await JamManifestLoader.provisionFromAsset(provisioner);
/// final registry = GrammarRegistry.fromProvisioned([oddjobz, jambox]);
/// final hats     = HatRegistry.fromGrammarRegistry(registry);
/// ```
library jam_experience;

export 'src/intents.dart';
export 'src/jam_colours.dart';
export 'src/jam_intent_grammar.dart';
export 'src/jam_screen.dart';
export 'src/jambox_client.dart';
export 'src/loop_orb.dart';
export 'src/manifest_loader.dart';
export 'src/cartridge.dart';
export 'src/pad_grid.dart';
export 'src/peer_rail.dart';
export 'src/rack_tab_bar.dart';
export 'src/support_sheet.dart';
export 'src/tap_overlay.dart';

```
