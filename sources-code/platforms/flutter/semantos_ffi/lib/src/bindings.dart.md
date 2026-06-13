---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/lib/src/bindings.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.008626+00:00
---

# platforms/flutter/semantos_ffi/lib/src/bindings.dart

```dart
// Semantos FFI — Dart bindings to the Semantos kernel C ABI.
//
// FFIGEN DECISION: Hand-written (not auto-generated via ffigen).
//
// Rationale:
// 1. The API surface is small (14 exported functions + 7 callback types).
//    Hand-writing is faster than setting up an ffigen pipeline.
// 2. Full control over Dart type mappings and documentation inline with
//    each function, improving readability for Dart developers.
// 3. No build-time dependency on ffigen or LLVM/libclang toolchain.
// 4. Callback function pointer types need careful Dart-side signatures
//    that ffigen doesn't always get right for callconv(.c) Zig exports.
//
// All signatures match src/ffi/semantos.h and src/ffi/callbacks.zig exactly.

import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart' show Utf8;

// ── Error codes (must match semantos.h) ──

const int semantosOk = 0;
const int semantosErrNotFound = -1;
const int semantosErrInvalidJson = -2;
const int semantosErrAlreadyConsumed = -3;
const int semantosErrAlreadyInit = -4;
const int semantosErrNotInit = -5;
const int semantosErrBufferTooSmall = -6;
const int semantosErrInvalidProof = -7;
const int semantosErrDenied = -8;
const int semantosErrExpired = -9;

// ── Library loading ──

ffi.DynamicLibrary _loadLibrary() {
  if (Platform.isIOS) {
    // iOS: statically linked via XCFramework — symbols in process
    return ffi.DynamicLibrary.process();
  } else if (Platform.isAndroid) {
    return ffi.DynamicLibrary.open('libsemantos.so');
  } else if (Platform.isMacOS) {
    return ffi.DynamicLibrary.open('libsemantos.dylib');
  } else if (Platform.isLinux) {
    return ffi.DynamicLibrary.open('libsemantos.so');
  } else if (Platform.isWindows) {
    return ffi.DynamicLibrary.open('semantos.dll');
  } else {
    throw UnsupportedError(
      'Semantos FFI: unsupported platform ${Platform.operatingSystem}',
    );
  }
}

// ── Native function typedefs ──
// Convention: <Name>Native = C signature, <Name>Dart = Dart signature

// Lifecycle
typedef _InitNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> configJson,
  ffi.Size configLen,
);
typedef _InitDart = int Function(
  ffi.Pointer<ffi.Uint8> configJson,
  int configLen,
);

typedef _ShutdownNative = ffi.Int32 Function();
typedef _ShutdownDart = int Function();

// Cell operations
typedef _CellWriteNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> path,
  ffi.Size pathLen,
  ffi.Pointer<ffi.Uint8> data,
  ffi.Size dataLen,
);
typedef _CellWriteDart = int Function(
  ffi.Pointer<ffi.Uint8> path,
  int pathLen,
  ffi.Pointer<ffi.Uint8> data,
  int dataLen,
);

typedef _CellReadNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> path,
  ffi.Size pathLen,
  ffi.Pointer<ffi.Uint8> outData,
  ffi.Pointer<ffi.Size> inoutLen,
);
typedef _CellReadDart = int Function(
  ffi.Pointer<ffi.Uint8> path,
  int pathLen,
  ffi.Pointer<ffi.Uint8> outData,
  ffi.Pointer<ffi.Size> inoutLen,
);

typedef _CellVerifyNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> path,
  ffi.Size pathLen,
  ffi.Pointer<ffi.Uint8> proof,
  ffi.Size proofLen,
);
typedef _CellVerifyDart = int Function(
  ffi.Pointer<ffi.Uint8> path,
  int pathLen,
  ffi.Pointer<ffi.Uint8> proof,
  int proofLen,
);

// Memory management
typedef _FreeNative = ffi.Void Function(
  ffi.Pointer<ffi.Uint8> ptr,
  ffi.Size len,
);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Uint8> ptr, int len);

// Metadata
typedef _VersionNative = ffi.Pointer<Utf8> Function();
typedef _VersionDart = ffi.Pointer<Utf8> Function();

typedef _LastErrorNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> outBuf,
  ffi.Pointer<ffi.Size> inoutLen,
);
typedef _LastErrorDart = int Function(
  ffi.Pointer<ffi.Uint8> outBuf,
  ffi.Pointer<ffi.Size> inoutLen,
);

// Capability (Phase 30C)
typedef _CapabilityCheckNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> certJson,
  ffi.Size certLen,
  ffi.Pointer<ffi.Uint8> resourceId,
  ffi.Size ridLen,
  ffi.Uint32 requiredFlags,
);
typedef _CapabilityCheckDart = int Function(
  ffi.Pointer<ffi.Uint8> certJson,
  int certLen,
  ffi.Pointer<ffi.Uint8> resourceId,
  int ridLen,
  int requiredFlags,
);

typedef _CapabilityPresentNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> parentCert,
  ffi.Size parentLen,
  ffi.Pointer<ffi.Uint8> resourceId,
  ffi.Size ridLen,
  ffi.Uint32 grantedFlags,
  ffi.Pointer<ffi.Uint8> outCert,
  ffi.Pointer<ffi.Size> inoutLen,
);
typedef _CapabilityPresentDart = int Function(
  ffi.Pointer<ffi.Uint8> parentCert,
  int parentLen,
  ffi.Pointer<ffi.Uint8> resourceId,
  int ridLen,
  int grantedFlags,
  ffi.Pointer<ffi.Uint8> outCert,
  ffi.Pointer<ffi.Size> inoutLen,
);

// Anchor (Phase 30D)
typedef _AnchorBatchNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> stateHash,
  ffi.Size hashLen,
  ffi.Pointer<ffi.Uint8> metadataJson,
  ffi.Size metaLen,
  ffi.Pointer<ffi.Uint8> outProof,
  ffi.Pointer<ffi.Size> inoutLen,
);
typedef _AnchorBatchDart = int Function(
  ffi.Pointer<ffi.Uint8> stateHash,
  int hashLen,
  ffi.Pointer<ffi.Uint8> metadataJson,
  int metaLen,
  ffi.Pointer<ffi.Uint8> outProof,
  ffi.Pointer<ffi.Size> inoutLen,
);

typedef _AnchorVerifyNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> proof,
  ffi.Size proofLen,
  ffi.Pointer<ffi.Uint8> stateHash,
  ffi.Size hashLen,
);
typedef _AnchorVerifyDart = int Function(
  ffi.Pointer<ffi.Uint8> proof,
  int proofLen,
  ffi.Pointer<ffi.Uint8> stateHash,
  int hashLen,
);

// Linearity (Phase 30C)
typedef _LinearConsumeNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> path,
  ffi.Size pathLen,
);
typedef _LinearConsumeDart = int Function(
  ffi.Pointer<ffi.Uint8> path,
  int pathLen,
);

// Platform wallet operations (native targets only)
typedef _WalletIdentityPubkeyNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> wifPtr,
  ffi.Size wifLen,
  ffi.Pointer<ffi.Uint8> outBuf,
  ffi.Size outCap,
  ffi.Pointer<ffi.Size> outLen,
);
typedef _WalletIdentityPubkeyDart = int Function(
  ffi.Pointer<ffi.Uint8> wifPtr,
  int wifLen,
  ffi.Pointer<ffi.Uint8> outBuf,
  int outCap,
  ffi.Pointer<ffi.Size> outLen,
);

typedef _WalletPayNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> wifPtr,
  ffi.Size wifLen,
  ffi.Pointer<ffi.Uint8> utxosJsonPtr,
  ffi.Size utxosJsonLen,
  ffi.Pointer<ffi.Uint8> outputsJsonPtr,
  ffi.Size outputsJsonLen,
  ffi.Pointer<ffi.Uint8> arcUrlPtr,
  ffi.Size arcUrlLen,
  ffi.Pointer<ffi.Uint8> outTxid,
  ffi.Size outTxidCap,
  ffi.Pointer<ffi.Size> outTxidLen,
);
typedef _WalletPayDart = int Function(
  ffi.Pointer<ffi.Uint8> wifPtr,
  int wifLen,
  ffi.Pointer<ffi.Uint8> utxosJsonPtr,
  int utxosJsonLen,
  ffi.Pointer<ffi.Uint8> outputsJsonPtr,
  int outputsJsonLen,
  ffi.Pointer<ffi.Uint8> arcUrlPtr,
  int arcUrlLen,
  ffi.Pointer<ffi.Uint8> outTxid,
  int outTxidCap,
  ffi.Pointer<ffi.Size> outTxidLen,
);

typedef _WalletAnchorTransitionNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> wifPtr,
  ffi.Size wifLen,
  ffi.Pointer<ffi.Uint8> typeHashPtr,
  ffi.Size typeHashLen,
  ffi.Uint64 anchorIndex,
  ffi.Pointer<ffi.Uint8> anchorUtxosJsonPtr,
  ffi.Size anchorUtxosJsonLen,
  ffi.Pointer<ffi.Uint8> arcUrlPtr,
  ffi.Size arcUrlLen,
  ffi.Pointer<ffi.Uint8> outTxid,
  ffi.Size outTxidCap,
  ffi.Pointer<ffi.Size> outTxidLen,
);
typedef _WalletAnchorTransitionDart = int Function(
  ffi.Pointer<ffi.Uint8> wifPtr,
  int wifLen,
  ffi.Pointer<ffi.Uint8> typeHashPtr,
  int typeHashLen,
  int anchorIndex,
  ffi.Pointer<ffi.Uint8> anchorUtxosJsonPtr,
  int anchorUtxosJsonLen,
  ffi.Pointer<ffi.Uint8> arcUrlPtr,
  int arcUrlLen,
  ffi.Pointer<ffi.Uint8> outTxid,
  int outTxidCap,
  ffi.Pointer<ffi.Size> outTxidLen,
);

// Execute script (D-O5m.followup-3 Phase 3)
typedef _ExecuteScriptNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> bytesPtr,
  ffi.Size bytesLen,
  ffi.Pointer<ffi.Uint8> ctxJsonPtr,
  ffi.Size ctxJsonLen,
  ffi.Pointer<ffi.Uint8> outResultPtr,
  ffi.Size outResultCap,
  ffi.Pointer<ffi.Size> outResultLen,
);
typedef _ExecuteScriptDart = int Function(
  ffi.Pointer<ffi.Uint8> bytesPtr,
  int bytesLen,
  ffi.Pointer<ffi.Uint8> ctxJsonPtr,
  int ctxJsonLen,
  ffi.Pointer<ffi.Uint8> outResultPtr,
  int outResultCap,
  ffi.Pointer<ffi.Size> outResultLen,
);

// ── Callback function pointer types (Phase 30B) ──
// These match the Zig callconv(.c) signatures in callbacks.zig.

typedef HostStorageReadNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> path,
  ffi.Size pathLen,
  ffi.Pointer<ffi.Uint8> outData,
  ffi.Pointer<ffi.Size> inoutLen,
);

typedef HostStorageWriteNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> path,
  ffi.Size pathLen,
  ffi.Pointer<ffi.Uint8> data,
  ffi.Size dataLen,
);

typedef HostIdentityResolveNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> certId,
  ffi.Size certLen,
  ffi.Pointer<ffi.Uint8> outJson,
  ffi.Pointer<ffi.Size> inoutLen,
);

typedef HostIdentityDeriveNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> parentCert,
  ffi.Size certLen,
  ffi.Pointer<ffi.Uint8> resourceId,
  ffi.Size ridLen,
  ffi.Uint32 domainFlag,
  ffi.Pointer<ffi.Uint8> outJson,
  ffi.Pointer<ffi.Size> inoutLen,
);

typedef HostAnchorSubmitNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> stateHash,
  ffi.Size hashLen,
  ffi.Pointer<ffi.Uint8> metadataJson,
  ffi.Size metaLen,
  ffi.Pointer<ffi.Uint8> outProof,
  ffi.Pointer<ffi.Size> inoutLen,
);

typedef HostNetworkPublishNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> objectJson,
  ffi.Size jsonLen,
);

typedef HostNetworkResolveNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Uint8> queryJson,
  ffi.Size jsonLen,
  ffi.Pointer<ffi.Uint8> outResults,
  ffi.Pointer<ffi.Size> inoutLen,
);

// Callback registration
typedef _RegisterCallbacksNative = ffi.Int32 Function(
  ffi.Pointer<ffi.NativeFunction<HostStorageReadNative>> storageRead,
  ffi.Pointer<ffi.NativeFunction<HostStorageWriteNative>> storageWrite,
  ffi.Pointer<ffi.NativeFunction<HostIdentityResolveNative>> identityResolve,
  ffi.Pointer<ffi.NativeFunction<HostIdentityDeriveNative>> identityDerive,
  ffi.Pointer<ffi.NativeFunction<HostAnchorSubmitNative>> anchorSubmit,
  ffi.Pointer<ffi.NativeFunction<HostNetworkPublishNative>> networkPublish,
  ffi.Pointer<ffi.NativeFunction<HostNetworkResolveNative>> networkResolve,
);
typedef _RegisterCallbacksDart = int Function(
  ffi.Pointer<ffi.NativeFunction<HostStorageReadNative>> storageRead,
  ffi.Pointer<ffi.NativeFunction<HostStorageWriteNative>> storageWrite,
  ffi.Pointer<ffi.NativeFunction<HostIdentityResolveNative>> identityResolve,
  ffi.Pointer<ffi.NativeFunction<HostIdentityDeriveNative>> identityDerive,
  ffi.Pointer<ffi.NativeFunction<HostAnchorSubmitNative>> anchorSubmit,
  ffi.Pointer<ffi.NativeFunction<HostNetworkPublishNative>> networkPublish,
  ffi.Pointer<ffi.NativeFunction<HostNetworkResolveNative>> networkResolve,
);

// ── Bindings class ──

class SemantosBindings {
  final ffi.DynamicLibrary _lib;

  SemantosBindings() : _lib = _loadLibrary();

  /// For testing: load from an explicit path.
  SemantosBindings.fromPath(String path)
      : _lib = ffi.DynamicLibrary.open(path);

  // ── Lifecycle ──

  late final semantosInit =
      _lib.lookupFunction<_InitNative, _InitDart>('semantos_init');

  late final semantosShutdown =
      _lib.lookupFunction<_ShutdownNative, _ShutdownDart>('semantos_shutdown');

  // ── Cell operations ──

  late final semantosCellWrite =
      _lib.lookupFunction<_CellWriteNative, _CellWriteDart>(
        'semantos_cell_write',
      );

  late final semantosCellRead =
      _lib.lookupFunction<_CellReadNative, _CellReadDart>(
        'semantos_cell_read',
      );

  late final semantosCellVerify =
      _lib.lookupFunction<_CellVerifyNative, _CellVerifyDart>(
        'semantos_cell_verify',
      );

  // ── Memory ──

  late final semantosFree =
      _lib.lookupFunction<_FreeNative, _FreeDart>('semantos_free');

  // ── Metadata ──

  late final semantosVersion =
      _lib.lookupFunction<_VersionNative, _VersionDart>('semantos_version');

  late final semantosLastError =
      _lib.lookupFunction<_LastErrorNative, _LastErrorDart>(
        'semantos_last_error',
      );

  // ── Capability (Phase 30C) ──

  late final semantosCapabilityCheck =
      _lib.lookupFunction<_CapabilityCheckNative, _CapabilityCheckDart>(
        'semantos_capability_check',
      );

  late final semantosCapabilityPresent =
      _lib.lookupFunction<_CapabilityPresentNative, _CapabilityPresentDart>(
        'semantos_capability_present',
      );

  // ── Anchor (Phase 30D) ──

  late final semantosAnchorBatch =
      _lib.lookupFunction<_AnchorBatchNative, _AnchorBatchDart>(
        'semantos_anchor_batch',
      );

  late final semantosAnchorVerify =
      _lib.lookupFunction<_AnchorVerifyNative, _AnchorVerifyDart>(
        'semantos_anchor_verify',
      );

  // ── Linearity (Phase 30C) ──

  late final semantosLinearConsume =
      _lib.lookupFunction<_LinearConsumeNative, _LinearConsumeDart>(
        'semantos_linear_consume',
      );

  // ── Script execution (D-O5m.followup-3 Phase 3) ──

  late final semantosExecuteScript =
      _lib.lookupFunction<_ExecuteScriptNative, _ExecuteScriptDart>(
        'semantos_execute_script',
      );

  // ── Platform wallet (native only) ──

  late final semantosWalletIdentityPubkey = _lib.lookupFunction<
      _WalletIdentityPubkeyNative,
      _WalletIdentityPubkeyDart>('semantos_wallet_identity_pubkey');

  late final semantosWalletPay =
      _lib.lookupFunction<_WalletPayNative, _WalletPayDart>(
        'semantos_wallet_pay',
      );

  late final semantosWalletAnchorTransition = _lib.lookupFunction<
      _WalletAnchorTransitionNative,
      _WalletAnchorTransitionDart>('semantos_wallet_anchor_transition');

  // ── Callback registration (Phase 30B) ──

  late final semantosRegisterCallbacks =
      _lib.lookupFunction<_RegisterCallbacksNative, _RegisterCallbacksDart>(
        'semantos_register_callbacks',
      );
}

```
