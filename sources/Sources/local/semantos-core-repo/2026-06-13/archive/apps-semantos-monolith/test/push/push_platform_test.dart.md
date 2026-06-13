---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/push/push_platform_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.915384+00:00
---

# archive/apps-semantos-monolith/test/push/push_platform_test.dart

```dart
// D-O5m.followup-9 Phase A — push-platform typed-model coverage.
//
// Substrate scope: this PR ships the types only.  Firebase wiring +
// the PushRegistrationService land in Phase C.

import 'package:test/test.dart';
import 'package:semantos/src/push/push_platform.dart';

void main() {
  group('PushPlatform enum', () {
    test('toJson + fromJson round-trip every variant', () {
      for (final p in PushPlatform.values) {
        expect(PushPlatform.fromJson(p.toJson()), equals(p));
      }
    });

    test('fromJson returns null for unknown values', () {
      expect(PushPlatform.fromJson('oops'), isNull);
      expect(PushPlatform.fromJson(''), isNull);
    });
  });

  group('PushTokenRegistration', () {
    test('toJson + fromJson round-trip an apns registration', () {
      const reg = PushTokenRegistration(
        platform: PushPlatform.apns,
        token: 'apns-tok-001',
        registeredAt: '2026-05-02T10:00:00Z',
      );
      final round = PushTokenRegistration.fromJson(reg.toJson());
      expect(round.platform, equals(PushPlatform.apns));
      expect(round.token, equals('apns-tok-001'));
      expect(round.registeredAt, equals('2026-05-02T10:00:00Z'));
      expect(round.isRegistered, isTrue);
    });

    test('toJson + fromJson round-trip an fcm registration', () {
      const reg = PushTokenRegistration(
        platform: PushPlatform.fcm,
        token: 'fcm-reg-token-001',
        registeredAt: '2026-05-02T11:00:00Z',
      );
      final round = PushTokenRegistration.fromJson(reg.toJson());
      expect(round.platform, equals(PushPlatform.fcm));
      expect(round.isRegistered, isTrue);
    });

    test('toJson + fromJson round-trip a unifiedpush registration', () {
      // Sovereign-push D.3 — for UP the `token` field carries the
      // distributor endpoint URL.  The shape on the wire is
      // identical to APNs/FCM; only the semantic interpretation
      // differs (the brain stores it on cert.up_endpoint instead
      // of cert.fcm_token / cert.apns_token).
      const reg = PushTokenRegistration(
        platform: PushPlatform.unifiedpush,
        token: 'https://ntfy.example.org/UPxyzABC123',
        registeredAt: '2026-05-02T13:00:00Z',
      );
      final round = PushTokenRegistration.fromJson(reg.toJson());
      expect(round.platform, equals(PushPlatform.unifiedpush));
      expect(round.token, equals('https://ntfy.example.org/UPxyzABC123'));
      expect(round.isRegistered, isTrue);
      // Wire-name MUST be the lower-case identifier so the brain's
      // PushPlatform.fromWireName picks it up as the same variant.
      expect(reg.toJson()['platform'], equals('unifiedpush'));
    });

    test('PushPlatform.unifiedpush wire-name matches the brain enum', () {
      // Cross-language contract: the Zig PushPlatform enum spells
      // this exact string, and the brain's parsePostBody validates
      // against it.  Catching this on the Dart side keeps the
      // round-trip honest without a full brain↔device integration
      // test.
      expect(PushPlatform.unifiedpush.toJson(), equals('unifiedpush'));
      expect(
        PushPlatform.fromJson('unifiedpush'),
        equals(PushPlatform.unifiedpush),
      );
    });

    test('empty sentinel has platform=none and is not registered', () {
      expect(PushTokenRegistration.empty.platform, equals(PushPlatform.none));
      expect(PushTokenRegistration.empty.isRegistered, isFalse);
    });

    test('fromJson with missing/unknown platform falls back to empty', () {
      expect(
        PushTokenRegistration.fromJson({}).platform,
        equals(PushPlatform.none),
      );
      expect(
        PushTokenRegistration.fromJson({'platform': 'oops', 'token': 't'})
            .platform,
        equals(PushPlatform.none),
      );
    });
  });
}

```
