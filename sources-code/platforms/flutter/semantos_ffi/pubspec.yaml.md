---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/pubspec.yaml
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.989904+00:00
---

# platforms/flutter/semantos_ffi/pubspec.yaml

```yaml
name: semantos_ffi
description: >
  Flutter FFI bindings to the Semantos kernel. Provides cell read/write,
  capability verification, anchor batching, and adapter callback registration
  via a pure C ABI boundary.
version: 1.0.0

environment:
  sdk: ^3.11.0
  flutter: ^3.41.0

dependencies:
  flutter:
    sdk: flutter
  ffi: ^2.1.0
  semantos_core:
    path: ../semantos_core
  path_provider: ^2.1.0
  sqflite: ^2.4.0
  flutter_secure_storage: ^9.2.0
  dio: ^5.7.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0

flutter:
  plugin:
    platforms:
      ios:
        ffiPlugin: true
      android:
        ffiPlugin: true
      macos:
        ffiPlugin: true

```
