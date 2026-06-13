---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/platform/ffi_wallet_factory_stub.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.100184+00:00
---

# apps/semantos/lib/platform/ffi_wallet_factory_stub.dart

```dart
import 'package:semantos_core/semantos_core.dart';

/// PWA stub — there is no local FFI wallet on web.
///
/// The shell's [NodeResolver] receives null here and falls back to
/// requiring a paired brain. Conditional import selects this file on
/// `dart.library.html` targets; the native counterpart returns a real
/// factory backed by semantos_ffi.
WalletService Function({required String wif})? buildFfiWalletFactory() => null;

```
