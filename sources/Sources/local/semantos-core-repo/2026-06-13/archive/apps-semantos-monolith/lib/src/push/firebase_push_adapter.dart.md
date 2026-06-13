---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/push/firebase_push_adapter.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.871459+00:00
---

# archive/apps-semantos-monolith/lib/src/push/firebase_push_adapter.dart

```dart
// D-O5m.followup-9 Phase C — production firebase_messaging adapter.
//
// 2026-05-06 — TEMPORARILY STUBBED so the iOS Simulator build resolves
// for Bridget's field-node ↔ brain pairing test.  The real adapter
// pulled `firebase_messaging` whose iOS CocoaPods conflict with the
// current Flutter target.  Both `firebase_core` and `firebase_messaging`
// are commented out in pubspec.yaml; this file no longer imports them.
//
// What this stub does: implements the PushPlatformAdapter interface
// with no-op methods — `requestPermission` returns false, `getDeviceToken`
// returns null, `tokenRefreshStream` is empty.  PushRegistrationService
// detects the no-op behaviour and falls back to UnifiedPushAdapter on
// Android (which still works fully); on iOS, push is disabled until the
// Firebase deps are restored or replaced with a native APNs shim.
//
// To restore: uncomment firebase_core + firebase_messaging in
// pubspec.yaml, restore the imports below + the original method bodies
// (preserved in git history at commit 4a0d92f and earlier), and revive
// the `Firebase.initializeApp()` block in lib/main.dart.

import 'dart:async';

import 'push_registration_service.dart';

/// Stub [PushPlatformAdapter] — no-op until Firebase deps are restored.
///
/// Constructed at app boot from main.dart and passed into
/// [PushRegistrationService].  When this returns null tokens, the
/// service routes Android operators to UnifiedPushAdapter and disables
/// push entirely on iOS.
class FirebasePushAdapter implements PushPlatformAdapter {
  FirebasePushAdapter();

  /// `'fcm'` — even when stubbed, Android operators may still register
  /// the platform name with the brain.  The brain's wake-only payload
  /// dispatcher is platform-agnostic; the tokens are what matter and
  /// those are null in this stub.
  @override
  String get platformName => 'fcm';

  /// Stubbed — always returns false.  PushRegistrationService treats
  /// this as "permission denied / push unavailable" and the operator
  /// can opt into UnifiedPush via Settings (Android) or rely on
  /// in-session WSS for live updates (iOS).
  @override
  Future<bool> requestPermission() async => false;

  /// Stubbed — always returns null.  See class doc for restoration.
  @override
  Future<String?> getDeviceToken() async => null;

  /// Stubbed — empty stream (never emits).  When Firebase is restored,
  /// this returns to `_messaging.onTokenRefresh`.
  @override
  Stream<String> get tokenRefreshStream => const Stream<String>.empty();
}

```
