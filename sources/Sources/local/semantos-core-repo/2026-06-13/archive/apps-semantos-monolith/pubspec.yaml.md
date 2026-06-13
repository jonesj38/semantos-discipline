---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/pubspec.yaml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.694604+00:00
---

# archive/apps-semantos-monolith/pubspec.yaml

```yaml
name: semantos
description: >
  Semantos mobile shell. Cartridge-driven nav: cartridges register
  nav destinations, cell-type renderers, and grammar fragments at boot.
  Ships with four shell-native primitives (Conversation/Talk, Pask graph
  engine, Wallet/BRC-42 identity, Contacts/PKI) plus the self and
  oddjobz cartridges.  Brain pairing via device-side BRC-42 handshake;
  bearer-gated `POST /api/v1/repl` + generic mint path `POST /api/v1/cells`.

  Architecture: docs/design/SEMANTOS-SHELL.md
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: ^3.11.0
  flutter: ^3.41.0

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  # Crypto primitives for BRC-42 child derivation (secp256k1, HMAC-SHA-256,
  # ECDH). Pure Dart so it works on iOS + Android + the desktop test
  # harness without an FFI dependency.
  pointycastle: ^3.9.1
  # HTTP — bearer-gated POST /api/v1/repl + POST /api/v1/device-pair.
  dio: ^5.7.0
  # Child-cert + bearer custody. Uses iOS Keychain + Android Keystore
  # under the hood.
  flutter_secure_storage: ^9.2.0
  # Outbox queue (D-O5m-i skeleton) — persistent local storage of
  # signed cell transitions awaiting flush-on-reconnect.
  sqflite: ^2.4.0
  # sqflite_common holds the cross-platform Database interface that
  # both the production sqflite plugin and the FFI test harness
  # implement. Pulled in explicitly so `dart analyze` doesn't flag
  # the import as transitive.
  sqflite_common: ^2.5.4
  path: ^1.9.0
  path_provider: ^2.1.0
  # QR scanner + paste-fallback parsing for the pairing screen.
  mobile_scanner: ^5.2.3
  # D-O5m.followup-8 capture+upload — mobile camera capture + signed
  # cell production.  image_picker abstracts iOS UIImagePicker /
  # Android MediaStore through a single Future-returning API; uuid is
  # used by attachment_builder.dart to mint fresh attachmentId values
  # at capture time.
  image_picker: ^1.1.0
  uuid: ^4.5.0
  # D-O5m.followup-8 GPS + voice memo adapters — completes the sensor
  # adapter trio (camera/GPS/mic) per spec §O5m-f.  geolocator drives
  # the GPS pin capture flow; record drives voice memo recording;
  # audioplayers drives the playback modal for previously-uploaded
  # voice memos.  All three pull behind dependency-injectable adapter
  # interfaces (GeolocatorAdapter, VoiceRecorderAdapter,
  # VoicePlaybackAdapter) so the unit tests stay Flutter-SDK-free.
  geolocator: ^11.0.0
  record: ^5.0.0
  audioplayers: ^6.0.0
  # D-O5.followup-4 — WSS live-tick stream client.  HelmEventStream
  # opens an authenticated WebSocket to /api/v1/wallet, sends
  # helm.subscribe with the topic list, then emits incoming
  # helm.event notifications to the helm UI.  web_socket_channel
  # ships the same WebSocketChannel shape Flutter uses on iOS +
  # Android + dart:io desktop test harness.
  web_socket_channel: ^3.0.0
  # D-O5m.followup-9 Phase C — Firebase + push notifications.
  # firebase_core wires up the Flutter ↔ native Firebase
  # bridge; firebase_messaging registers for APNs/FCM device
  # tokens and surfaces foreground / background / tap callbacks.
  # flutter_local_notifications renders an in-app banner when a
  # push arrives while the app is in the foreground (firebase
  # itself only delivers a system notification when backgrounded).
  # permission_handler is needed for the Android 13+
  # POST_NOTIFICATIONS runtime permission and the iOS Open-Settings
  # CTA in SettingsScreen when the operator has previously denied
  # notifications.  All four are pulled behind injectable adapter
  # interfaces in lib/src/push/ so the unit-test suite stays
  # Flutter-SDK-free (see PushRegistrationService +
  # InMemoryPushAdapter for the test seam).
  # 2026-05-06 — Firebase deps temporarily commented out so the iOS
  # Simulator build resolves for Bridget's field-node ↔ brain pairing
  # test.  Firebase's transitive iOS CocoaPods conflict with the
  # current Flutter iOS target.  The push subsystem has TWO adapters
  # (FirebasePushAdapter, UnifiedPushAdapter); only the Firebase one
  # is stubbed.  UnifiedPush continues to work on Android.  iOS uses
  # APNs natively per the sovereign-push design (D-O5m.followup-9
  # Phase D); when we restore Firebase on iOS, also restore the
  # `Firebase.initializeApp()` block + FirebasePushAdapter wire-up
  # in lib/main.dart and the `import` in lib/src/push/firebase_push_adapter.dart.
  # firebase_core: ^3.0.0
  # firebase_messaging: ^15.0.0
  flutter_local_notifications: ^17.0.0
  permission_handler: ^11.0.0
  # Sovereign-push D.3 — UnifiedPush adapter.  Lets Android operators
  # opt out of Firebase entirely by routing wakes through a libre
  # distributor (ntfy, NextPush, Conversations, …) of their choice.
  # iOS still uses APNs (Apple sandbox limitation).  The plugin's
  # native side registers the org.unifiedpush.android.distributor.*
  # broadcast receivers — no manual AndroidManifest edits needed.
  # See docs/operator-runbooks/push-architecture.md §"Phase D.3:
  # UnifiedPush" for end-to-end wiring.
  unifiedpush: ^6.2.0
  # Local FFI plugin (kernel + adapters) — included as a path dep so any
  # FFI calls the helm needs (e.g. on-device cell engine) compose with
  # the existing scaffolding. The MVP doesn't fire up the kernel yet
  # but keeping the wiring discoverable de-risks the O5m-c follow-up.
  semantos_ffi:
    path: ../../platforms/flutter/semantos_ffi
  # Platform interfaces (WalletService, IdentityStore, NodeResolver,
  # ExtensionManifest, GrammarRegistry, CellQueryClient). Imported here
  # so the voice pipeline can construct its ExtensionGrammar from a
  # manifest spec rather than the hand-maintained mirror constant.
  semantos_core:
    path: ../../platforms/flutter/semantos_core
  # Oddjobz extension package — supplies the bundled manifest.json asset
  # via OddjobzManifestLoader. When the unified shell + dynamic install
  # land, this path dep gets replaced by a brain-fetched provisioning
  # flow; until then we ship the manifest alongside this app.
  oddjobz_experience:
    path: ../../packages/oddjobz_experience
  # D-O5m.followup-3 Phase 1 — on-device STT via whisper.cpp FFI.
  # WhisperService wraps the native library behind the VoiceTranscriber
  # seam; WhisperModelManager downloads + caches whisper.base.en (~140 MiB)
  # on first use; the model is never bundled in the APK/IPA.
  whisper_cpp:
    path: ../../platforms/flutter/whisper_cpp
  # llama_cpp removed — SIR extractor now uses AnthropicLlmCompleter
  # (claude-haiku-4-5 via api.anthropic.com). Sub-second vs 5-min on-device
  # inference. Key supplied at build time:
  #   flutter build apk --dart-define=ANTHROPIC_API_KEY=sk-ant-...
  # See apps/oddjobz-mobile/lib/src/voice/on_device_voice_factory.dart.
  # D-DOG.1.0c Phase 3 F.4 — PDF rendering for the mobile attachment
  # screen.  pdfx wraps PDFium (Android) + native iOS PDFKit behind a
  # single Flutter widget; we use it to preview legacy-ingest source
  # PDFs once the operator's brain ships the `legacy attachment <id>`
  # verb that decrypts the source bytes.  Until then the attachment
  # screen renders a placeholder explaining where the bytes live, so
  # this dependency is also exercised by the smoke build itself
  # (no runtime PDF rendering yet, just resolution + linkage).
  pdfx: ^2.9.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  # Mocking for unit tests (HTTP, secure storage).
  mocktail: ^1.0.4
  # Pure-Dart test runner — used for `dart test` runs of the pairing /
  # repl / outbox unit tests so the parity test doesn't require the
  # full Flutter SDK to gate the PR.
  test: ^1.25.0
  # FFI-backed sqflite for `dart test` runs of outbox_db_test.dart.
  # Production uses sqflite's MethodChannel adapter on iOS + Android.
  sqflite_common_ffi: ^2.3.3

# D-OPS.mobile-smoke-test (2026-05-02): `record 5.2.1` resolves
# `record_linux: ^0.7.0` but the 0.7.x branch on pub.dev is
# incompatible with `record_platform_interface 1.5.0` (the stable
# version `record_android` / `record_darwin` resolve to).  The
# concrete failure is "RecordLinux is missing implementations for
# RecordMethodChannelPlatformInterface.startStream" during
# kernel_snapshot.  Pinning record_linux to the 1.x line (which
# matches the 1.5.x platform interface) is a no-op for Android +
# iOS builds since record_linux only loads on Linux desktop, but
# it lets `flutter build apk --debug` reach the native CMake step
# where libsemantos.a is linked.  Drop this override once the
# upstream `record` package republishes with a tighter constraint.
dependency_overrides:
  record_linux: ^1.0.0

flutter:
  uses-material-design: true
  assets:
    - test/fixtures/
    - assets/llama/

```
