---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_shell_native_identity/pubspec.yaml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.990346+00:00
---

# platforms/flutter/semantos_shell_native_identity/pubspec.yaml

```yaml
name: semantos_shell_native_identity
description: >
  Native-only IdentityStore adapter for the Semantos shell. Backs
  IdentityStore with flutter_secure_storage (iOS Keychain / Android
  Keystore / macOS Keychain / Linux libsecret / Windows DPAPI).

  This package exists so flutter_secure_storage stays out of the web
  build graph. Flutter's auto-generated web_plugin_registrant.dart
  imports every registered web plugin unconditionally — declaring
  flutter_secure_storage at the shell's top-level pubspec pulls
  flutter_secure_storage_web (and its dart:html / dart:js_util / package:js
  dependencies) into the wasm graph and breaks `flutter build web --wasm`.

  By isolating flutter_secure_storage in this sub-package and importing
  it only via a conditional `dart.library.io` import, the web plugin
  registrant never sees it on web builds. The PWA target uses the
  IndexedDB adapter (`identity_store_web.dart`) instead.

  This package is platform-pinned to iOS, Android, macOS, Linux, Windows
  to make the constraint explicit; pub will refuse to resolve it on web.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.11.0
  flutter: ^3.41.0

dependencies:
  flutter:
    sdk: flutter
  flutter_secure_storage: ^9.2.0
  semantos_core:
    path: ../semantos_core

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
# Intentionally NOT declared as a Flutter plugin — flutter_secure_storage
# already provides its own native plugin registration; this package only
# wraps the Dart API surface. Skipping the plugin manifest keeps Flutter
# from emitting `default_package` warnings during pub get.

```
