---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/platform/ffi_wallet_factory_native.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.099624+00:00
---

# apps/semantos/lib/platform/ffi_wallet_factory_native.dart

```dart
import 'package:semantos_core/semantos_core.dart';
import 'package:semantos_ffi/semantos_ffi.dart';

/// Native build — returns a factory that constructs an [FfiWalletService]
/// backed by the libsemantos FFI bindings. Selected by conditional import
/// on `dart.library.io` targets (iOS / Android / macOS / Linux / Windows).
WalletService Function({required String wif})? buildFfiWalletFactory() {
  return ({required String wif}) => FfiWalletService(
        bindings: SemantosBindings(),
        wifKey: wif,
      );
}

```
