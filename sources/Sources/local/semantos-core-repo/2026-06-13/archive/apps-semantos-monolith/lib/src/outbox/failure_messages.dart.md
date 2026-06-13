---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/outbox/failure_messages.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.863865+00:00
---

# archive/apps-semantos-monolith/lib/src/outbox/failure_messages.dart

```dart
// D-O5m.followup-5 K1 conflict UI — operator-facing English for each
// typed [OutboxFailureKind].
//
// Single point of truth for the strings the conflicts screen renders.
// Keep these clear and actionable; avoid technical jargon (no "401",
// no "ECDSA", no "FK").  When a string includes operator-actionable
// guidance ("Re-pair your device") that copy lives here, not in the
// view layer, so the messaging stays consistent across the AppBar
// indicator tooltip + the conflicts row.
//
// The `detail` argument is the brain's optional human-readable hint
// (e.g. for `validation_failed` the brain may include a field name
// or a constraint description).  Most kinds ignore it; the few that
// surface it interpolate it into the message body.

import 'outbox_db.dart';

/// Render an operator-facing English message for [kind].  When
/// [detail] is non-empty the message may interpolate it (currently
/// only `validationFailed` uses it).
String readableMessage(OutboxFailureKind kind, [String? detail]) {
  switch (kind) {
    case OutboxFailureKind.networkError:
      return 'No connection. Will retry when online.';
    case OutboxFailureKind.hashMismatch:
      return 'Upload corrupted in transit. Tap retry.';
    case OutboxFailureKind.signatureInvalid:
      return 'Your device signature was rejected. Re-pair your device.';
    case OutboxFailureKind.certUnknown:
      return 'This device is not authorized. Re-pair to continue.';
    case OutboxFailureKind.visitNotFound:
      return 'The visit this photo belongs to no longer exists on the brain.';
    case OutboxFailureKind.stateMovedOn:
      return 'This job changed on the brain while you were offline. Tap to view.';
    case OutboxFailureKind.replay:
      return 'Already received by the brain (no action needed).';
    case OutboxFailureKind.validationFailed:
      final d = detail?.trim();
      if (d == null || d.isEmpty) {
        return "The data didn't validate.";
      }
      return "The data didn't validate: $d";
    case OutboxFailureKind.unauthorised:
      return 'Your session expired. Re-authenticate to continue.';
  }
}

```
