---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/outbox/conflict_summary.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.862656+00:00
---

# archive/apps-semantos-monolith/lib/src/outbox/conflict_summary.dart

```dart
// D-O5m.followup-5 K1 conflict UI — pure-Dart helpers used by the
// ConflictsScreen.  Kept separate from `conflicts_screen.dart` so
// `dart test` (no Flutter SDK gate) can exercise the rendering rules
// directly via DI mocks.

import 'outbox_db.dart';

/// Render a one-line summary for an [OutboxEntry].
///
/// W1.2 — the old `cellType` / `payloadJson` text fields are gone.
/// The entry now carries a 1024-byte `payload` BLOB (cell envelope)
/// and a 32-byte `cellId`.  We surface the hex-encoded cellId prefix
/// as the operator-facing handle; the domain_flag is shown as context.
String summariseEntry(OutboxEntry entry) {
  final cellIdHex = entry.cellId
      .take(8)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return 'Cell $cellIdHex… (domain 0x${entry.domainFlag.toRadixString(16)}, entry #${entry.id})';
}

// W1.2 — _capitalise and _sniff helpers removed (no longer needed after
// cellType/payloadJson columns were dropped from OutboxEntry).

```
