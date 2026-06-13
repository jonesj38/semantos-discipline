---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/PWA-WASM-BUILD.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.050096+00:00
---

# Building the Semantos shell as a pure-WASM PWA

By default `flutter build web` produces a working JavaScript bundle that
ships as a PWA — this is the recommended target for most operators
because it works on every browser without additional build flags.

For operators who want the **smaller, faster WebAssembly bundle**
(`flutter build web --wasm`), the build needs a one-line dependency
override to exclude `flutter_secure_storage_web` (which imports
`dart:html` and isn't wasm-compatible).

## Why the workaround is needed

The shell's `IdentityStore` seam uses Dart conditional imports
(`identity_store_stub.dart` for native, `identity_store_web.dart` for
PWA) to route platform identity custody. **On web, the conditional
import correctly excludes the native adapter from compilation.**
However, Flutter's auto-generated `web_plugin_registrant.dart` scans
the resolved pub graph and imports every declared web plugin
unconditionally — including `flutter_secure_storage_web`, even though
no shell code references it.

The shell's pubspec no longer declares `flutter_secure_storage`
directly (it's isolated in the `semantos_shell_native_identity`
sub-package), so the JS build is clean. The `--wasm` build still
pulls the plugin in transitively because Flutter resolves and
registers it before tree-shaking.

## The workaround

Add a `pubspec_overrides.yaml` in `apps/semantos/` (this file
is gitignored by Flutter's default templates; check it in if your
workflow runs `flutter build web --wasm` regularly):

```yaml
# pubspec_overrides.yaml — for `flutter build web --wasm` only.
# Replaces the native identity sub-package with an empty stub that
# pulls no platform plugins. The IndexedDB-backed identity store
# (idb_shim) still works on web via the conditional import in
# wallet_resolver.dart.
dependency_overrides:
  semantos_shell_native_identity:
    path: ./web_overrides/semantos_shell_native_identity_stub
```

Then in `apps/semantos/web_overrides/semantos_shell_native_identity_stub/`
create a minimal package with the same name + an empty IdentityStore
factory that throws if called (it never will on web — the conditional
import routes around it):

```yaml
# pubspec.yaml
name: semantos_shell_native_identity
version: 0.1.0
publish_to: none
environment:
  sdk: ^3.11.0
  flutter: ^3.41.0
dependencies:
  flutter:
    sdk: flutter
  semantos_core:
    path: ../../../../platforms/flutter/semantos_core
```

```dart
// lib/semantos_shell_native_identity.dart
import 'package:semantos_core/semantos_core.dart';

IdentityStore buildIdentityStore() => throw UnsupportedError(
      'Native IdentityStore stub on web — conditional import should '
      'have routed to identity_store_web.dart',
    );
```

## Build commands

```bash
# Standard JS build (works on every browser; the recommended PWA target)
flutter build web

# Pure-WASM build (smaller bundle, requires the override above)
flutter build web --wasm
```

## Verifying the override is in effect

After `flutter pub get`, check that the resolved version of
`flutter_secure_storage_web` no longer appears under
`build/web/.dart_tool/package_config.json` for the wasm target.

## When this can go away

Once Flutter's web plugin registrant supports conditional plugin
discovery (mirroring the Dart-side conditional import semantics), or
once `flutter_secure_storage_web` itself migrates from `dart:html` to
`package:web`, this workaround is no longer needed. Track:

- Flutter issue: https://github.com/flutter/flutter/issues/119271
  (web plugin discovery + tree-shaking)
- flutter_secure_storage_web migration to package:web (upstream)
