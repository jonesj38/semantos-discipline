---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/outbox/outbox_failure_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.907961+00:00
---

# archive/apps-semantos-monolith/test/outbox/outbox_failure_test.dart

```dart
// D-O5m.followup-5 K1 conflict UI — outbox failure-mapping tests.
//
// One test per OutboxFailureKind asserting:
//   - parseBrainError maps the brain's wire string to the right kind;
//   - readableMessage renders an operator-facing English string for it;
//   - the message is non-empty, doesn't contain the raw wire kind
//     verbatim (operator-facing copy is plain English).

import 'package:test/test.dart';

import 'package:semantos/src/outbox/failure_messages.dart';
import 'package:semantos/src/outbox/outbox_db.dart';
import 'package:semantos/src/outbox/outbox_service.dart';

void main() {
  group('parseBrainError + readableMessage per OutboxFailureKind', () {
    test('network_error: maps + renders no-connection English', () {
      // The brain doesn't emit a "network_error" wire string — it's
      // a client-side mapping from connection-refused / timeout.
      // The flush service uses OutboxFailureKind.networkError directly
      // so we only need to assert the readable copy here.
      final msg = readableMessage(OutboxFailureKind.networkError);
      expect(msg, contains('connection'));
      expect(msg, isNot(contains('network_error')));
    });

    test('hash_mismatch: maps from brain wire + renders retry-prompting copy',
        () {
      expect(parseBrainError('hash_mismatch'),
          equals(OutboxFailureKind.hashMismatch));
      final msg = readableMessage(OutboxFailureKind.hashMismatch);
      expect(msg, contains('corrupted'));
      expect(msg, contains('retry'));
    });

    test('signature_invalid: maps + renders re-pair guidance', () {
      expect(parseBrainError('signature_invalid'),
          equals(OutboxFailureKind.signatureInvalid));
      final msg = readableMessage(OutboxFailureKind.signatureInvalid);
      expect(msg, contains('Re-pair'));
    });

    test('cert_unknown: maps + renders re-pair guidance', () {
      expect(parseBrainError('cert_unknown'),
          equals(OutboxFailureKind.certUnknown));
      final msg = readableMessage(OutboxFailureKind.certUnknown);
      expect(msg, contains('not authorized'));
      expect(msg, contains('Re-pair'));
    });

    test('visit_not_found: maps + renders deletion-acknowledging copy', () {
      expect(parseBrainError('visit_not_found'),
          equals(OutboxFailureKind.visitNotFound));
      // Also covers the generic "not_found" alias.
      expect(parseBrainError('not_found'),
          equals(OutboxFailureKind.visitNotFound));
      final msg = readableMessage(OutboxFailureKind.visitNotFound);
      expect(msg, contains('no longer exists'));
    });

    test('state_moved_on: maps from FSM-rejection wire kinds + renders K1 copy',
        () {
      // The brain doesn't emit "state_moved_on" verbatim today — it
      // emits FSM rejection kinds that map to it client-side.
      for (final wire in const [
        'state_moved_on',
        'not_reachable',
        'wrong_principal',
        'wrong_cap',
      ]) {
        expect(parseBrainError(wire), equals(OutboxFailureKind.stateMovedOn),
            reason: 'wire $wire should map to stateMovedOn');
      }
      final msg = readableMessage(OutboxFailureKind.stateMovedOn);
      expect(msg, contains('changed on the brain'));
    });

    test('replay: maps + renders idempotent-retry copy', () {
      expect(parseBrainError('attachment_id_in_use_with_different_contents'),
          equals(OutboxFailureKind.replay));
      final msg = readableMessage(OutboxFailureKind.replay);
      expect(msg, contains('Already received'));
      expect(msg, contains('no action needed'));
    });

    test('validation_failed: maps from generic shape errors + interpolates detail',
        () {
      for (final wire in const [
        'payload_invalid_format',
        'invalid_args',
        'too_large',
      ]) {
        expect(parseBrainError(wire),
            equals(OutboxFailureKind.validationFailed),
            reason: 'wire $wire should map to validationFailed');
      }
      // No-detail rendering is bare.
      final bare = readableMessage(OutboxFailureKind.validationFailed);
      expect(bare, equals("The data didn't validate."));
      // With detail: interpolates.
      final detailed = readableMessage(
        OutboxFailureKind.validationFailed,
        'visit_id missing',
      );
      expect(detailed, contains('visit_id missing'));
    });

    test('unauthorised: maps + renders session-expired copy', () {
      expect(parseBrainError('bearer_invalid'),
          equals(OutboxFailureKind.unauthorised));
      final msg = readableMessage(OutboxFailureKind.unauthorised);
      expect(msg, contains('session expired'));
      expect(msg, contains('Re-authenticate'));
    });

    test('unknown wire string falls back to null (caller maps to validation)',
        () {
      expect(parseBrainError(null), isNull);
      expect(parseBrainError(''), isNull);
      expect(parseBrainError('   '), isNull);
      expect(parseBrainError('totally_made_up_kind'), isNull);
    });

    test('OutboxFailureKind.fromWire round-trips every kind', () {
      for (final kind in OutboxFailureKind.values) {
        expect(OutboxFailureKind.fromWire(kind.wire), equals(kind),
            reason: '${kind.wire} should round-trip');
      }
      // Unknown wire strings map to validationFailed (safe catch-all).
      expect(OutboxFailureKind.fromWire(null),
          equals(OutboxFailureKind.validationFailed));
      expect(OutboxFailureKind.fromWire('made_up'),
          equals(OutboxFailureKind.validationFailed));
    });
  });
}

```
