---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/push/push_platform.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.872991+00:00
---

# archive/apps-semantos-monolith/lib/src/push/push_platform.dart

```dart
// D-O5m.followup-9 Phase A — typed push-platform models for the
// mobile shell.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §D-O5m.followup-9
// Phase A (substrate scope: schema + register endpoint + event flag,
// no Firebase / APNs wiring).
//
// What this is: the typed shape Phase C's PushRegistrationService will
// consume.  Phase A ships ONLY the model — no Firebase plugin in
// pubspec.yaml, no actual subscription flow, no service.  These are
// the on-the-wire types that the mobile shell will marshal when it
// calls POST /api/v1/push-register (the brain endpoint introduced in
// the Zig side of this same Phase A PR — see
// runtime/semantos-brain/src/push_register_http.zig).
//
// Mirrors `runtime/semantos-brain/src/identity_certs.zig`'s `PushPlatform` enum
// + the apns_token / fcm_token / push_registered_at fields on the
// CertRecord.  When Phase B's brain-side dispatcher reads the cert
// record to decide which transport to use, the discriminator on this
// side is the same `PushPlatform` set.

/// Discriminator for which push transport the device is subscribed
/// to.  Mirrors `identity_certs.zig`'s PushPlatform exactly so the
/// wire round-trips without a translation layer.
enum PushPlatform {
  /// Default for unsubscribed devices.  Also used as the explicit
  /// unregister marker (DELETE /api/v1/push-register clears the cert
  /// record + flips the platform back to none).
  none,

  /// Apple Push Notification service — iOS / iPadOS / macOS devices.
  apns,

  /// Firebase Cloud Messaging — Android devices (and the Firebase
  /// web bridge if/when we ever ship a PWA helm).
  fcm,

  /// Sovereign-push D.3 — UnifiedPush (https://unifiedpush.org/).
  /// The libre push protocol.  Operator picks a distributor app
  /// (ntfy, NextPush, Conversations, …) on their Android device; the
  /// distributor mints a per-instance endpoint URL; the brain POSTs
  /// the wake envelope directly to that URL.  No Google Firebase, no
  /// Apple APNs, no provider wrapper.  iOS operators stay on `apns`
  /// because the Apple sandbox forbids alternative wake mechanisms.
  unifiedpush;

  /// Wire-name for this discriminator.  Matches the enum name
  /// case-for-case so the JSON shape is the canonical lower-case
  /// identifier.
  String toJson() => name;

  /// Inverse of [toJson].  Returns null on an unknown value so the
  /// caller can surface a typed error (the Phase C PushRegistration
  /// service will turn null into an unrecoverable `platform_invalid`).
  static PushPlatform? fromJson(String value) {
    for (final p in PushPlatform.values) {
      if (p.name == value) return p;
    }
    return null;
  }
}

/// The typed wire-shape the device sends to POST /api/v1/push-register
/// and persists locally so the helm UI can render "subscribed since
/// X" without re-hitting the brain.
///
/// `registeredAt` is whatever the brain stamped (ISO-8601 UTC) — the
/// device echoes it back verbatim from the brain's response.  An empty
/// string is the canonical "not registered" sentinel and pairs with
/// `platform == PushPlatform.none`.
class PushTokenRegistration {
  final PushPlatform platform;
  final String token;
  final String registeredAt;

  const PushTokenRegistration({
    required this.platform,
    required this.token,
    required this.registeredAt,
  });

  /// Sentinel "no registration" record — the device hasn't subscribed
  /// (or has just unregistered).  Constructors that accept JSON return
  /// this when the wire shape lacks a `platform` field.
  static const empty = PushTokenRegistration(
    platform: PushPlatform.none,
    token: '',
    registeredAt: '',
  );

  Map<String, dynamic> toJson() => {
        'platform': platform.toJson(),
        'token': token,
        'registered_at': registeredAt,
      };

  /// Decode from the brain's success-response body (or from local
  /// secure-storage).  Falls back to `PushTokenRegistration.empty`
  /// when the platform discriminator is missing or unknown — the
  /// Phase C service treats both as "not subscribed".
  factory PushTokenRegistration.fromJson(Map<String, dynamic> json) {
    final platformRaw = json['platform'];
    if (platformRaw is! String) return empty;
    final platform = PushPlatform.fromJson(platformRaw);
    if (platform == null) return empty;
    final token = (json['token'] is String) ? json['token'] as String : '';
    final registeredAt =
        (json['registered_at'] is String) ? json['registered_at'] as String : '';
    return PushTokenRegistration(
      platform: platform,
      token: token,
      registeredAt: registeredAt,
    );
  }

  /// Convenience predicate the helm UI checks before rendering the
  /// "subscribed since X" pill.
  bool get isRegistered => platform != PushPlatform.none && token.isNotEmpty;
}

```
