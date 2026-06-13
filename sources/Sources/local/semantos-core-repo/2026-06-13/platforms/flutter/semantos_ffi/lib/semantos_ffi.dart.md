---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/lib/semantos_ffi.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.995082+00:00
---

# platforms/flutter/semantos_ffi/lib/semantos_ffi.dart

```dart
// Semantos FFI — Flutter bindings to the Semantos kernel.
//
// Provides cell read/write, capability verification, anchor batching,
// and adapter callback registration via a pure C ABI boundary.

export 'src/bindings.dart' show SemantosBindings;
export 'src/kernel.dart'
    show
        SemantosKernel,
        SemantosException,
        ScriptContext,
        ScriptResult,
        ScriptOutcome,
        ScriptOk,
        ScriptViolation,
        ScriptViolationKind;
export 'src/callback_bridge.dart' show CallbackBridge;
export 'src/adapters/sqflite_storage_adapter.dart' show SqfliteStorageAdapter;
export 'src/adapters/platform_identity_adapter.dart'
    show PlatformIdentityAdapter;
export 'src/adapters/http_anchor_adapter.dart' show HttpAnchorAdapter;
export 'src/adapters/http_network_adapter.dart' show HttpNetworkAdapter;
export 'src/ffi_wallet_service.dart' show FfiWalletService, FfiWalletException;

```
