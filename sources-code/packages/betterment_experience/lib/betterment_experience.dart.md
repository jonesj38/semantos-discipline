---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/betterment_experience/lib/betterment_experience.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.446779+00:00
---

# packages/betterment_experience/lib/betterment_experience.dart

```dart
/// Betterment experience package.
///
/// Import this from the canonical PWA shell to register the betterment
/// cartridge with the CartridgeRegistry at boot.
///
/// Usage:
/// ```dart
/// import 'package:betterment_experience/betterment_experience.dart';
///
/// void main() async {
///   // ... shell bootstrap ...
///   registerBettermentCartridge();
///   // ... continue boot ...
/// }
/// ```
///
/// RENAME (2026-05-29): previously published as `self_experience`.
/// Renamed to free the word "self" for the shell-level identity
/// primitive (root BRC-52 operator cert + helm "me" surface). Package
/// purpose unchanged: personal practice + Paskian narrative substrate
/// for self-development. Cell-type prefix moved from `self.*` to
/// `betterment.*` in the same change.
library betterment_experience;

export 'src/betterment_intent_grammar.dart';
export 'src/betterment_screen.dart';
export 'src/cartridge.dart';
export 'src/intents.dart';
export 'src/manifest_loader.dart';
export 'src/release_capture_screen.dart';

```
