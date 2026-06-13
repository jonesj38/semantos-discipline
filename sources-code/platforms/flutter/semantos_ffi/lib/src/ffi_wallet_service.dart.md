---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_ffi/lib/src/ffi_wallet_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.007688+00:00
---

# platforms/flutter/semantos_ffi/lib/src/ffi_wallet_service.dart

```dart
// FfiWalletService — WalletService implementation backed by the native
// semantos FFI library (offline / embedded mode).
//
// Uses semantos_wallet_pay, semantos_wallet_anchor_transition, and
// semantos_wallet_identity_pubkey from the libsemantos C ABI.
//
// The signing key (WIF) is held by the caller and passed on each call
// rather than stored inside the library — this matches the design
// intent: the mobile Keychain owns the key; the FFI library is
// stateless with respect to the signing key.

import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:semantos_core/semantos_core.dart';

import 'bindings.dart';

class FfiWalletService implements WalletService {
  final SemantosBindings _bindings;
  final String _wifKey;

  FfiWalletService({
    required SemantosBindings bindings,
    required String wifKey,
  })  : _bindings = bindings,
        _wifKey = wifKey;

  @override
  Future<PayResult> pay(
    List<Output> outputs, {
    String? description,
    List<Map<String, dynamic>>? utxos,
  }) async {
    // The caller is responsible for providing UTXOs (from the output store
    // or an on-device UTXO cache). Pass them as a JSON array.
    final utxosJson = jsonEncode(utxos ?? []);
    final outputsJson = jsonEncode(outputs.map((o) => o.toJson()).toList());
    final txid = _walletPay(utxosJson, outputsJson);
    return PayResult(txid: txid);
  }

  @override
  Future<AnchorResult> anchorTransition(
    Uint8List typeHash,
    int anchorIndex,
    Uint8List newStateHash, {
    String? description,
    List<Map<String, dynamic>>? anchorUtxos,
  }) async {
    final anchorUtxosJson = jsonEncode(anchorUtxos ?? []);
    final txid = _anchorTransition(typeHash, anchorIndex, anchorUtxosJson);
    return AnchorResult(txid: txid);
  }

  @override
  Future<PayResult> createAction(
    List<TxInput> inputs,
    List<Output> outputs, {
    String? description,
  }) async {
    final utxosJson = jsonEncode(inputs.map((i) => i.toJson()).toList());
    final outputsJson = jsonEncode(outputs.map((o) => o.toJson()).toList());
    final txid = _walletPay(utxosJson, outputsJson);
    return PayResult(txid: txid);
  }

  @override
  Future<String> identityPubkeyHex() async {
    return _identityPubkeyHex();
  }

  String _identityPubkeyHex() {
    final wifBytes = utf8.encode(_wifKey);
    return using((arena) {
      final wifPtr = arena<ffi.Uint8>(wifBytes.length);
      for (var i = 0; i < wifBytes.length; i++) {
        wifPtr[i] = wifBytes[i];
      }
      const bufCap = 67;
      final outBuf = arena<ffi.Uint8>(bufCap);
      final outLen = arena<ffi.Size>();
      final rc = _bindings.semantosWalletIdentityPubkey(
        wifPtr, wifBytes.length,
        outBuf, bufCap, outLen,
      );
      if (rc != semantosOk) {
        throw FfiWalletException('semantos_wallet_identity_pubkey failed: $rc');
      }
      return String.fromCharCodes(outBuf.asTypedList(outLen.value));
    });
  }

  String _walletPay(String utxosJson, String outputsJson) {
    final wifBytes = utf8.encode(_wifKey);
    final utxosBytes = utf8.encode(utxosJson);
    final outputsBytes = utf8.encode(outputsJson);
    return using((arena) {
      final wifPtr = arena<ffi.Uint8>(wifBytes.length);
      for (var i = 0; i < wifBytes.length; i++) { wifPtr[i] = wifBytes[i]; }
      final utxosPtr = arena<ffi.Uint8>(utxosBytes.length);
      for (var i = 0; i < utxosBytes.length; i++) { utxosPtr[i] = utxosBytes[i]; }
      final outputsPtr = arena<ffi.Uint8>(outputsBytes.length);
      for (var i = 0; i < outputsBytes.length; i++) { outputsPtr[i] = outputsBytes[i]; }
      const txidCap = 65;
      final txidBuf = arena<ffi.Uint8>(txidCap);
      final txidLen = arena<ffi.Size>();
      final rc = _bindings.semantosWalletPay(
        wifPtr, wifBytes.length,
        utxosPtr, utxosBytes.length,
        outputsPtr, outputsBytes.length,
        ffi.nullptr, 0,
        txidBuf, txidCap, txidLen,
      );
      if (rc != semantosOk) {
        throw FfiWalletException('semantos_wallet_pay failed: $rc');
      }
      return String.fromCharCodes(txidBuf.asTypedList(txidLen.value));
    });
  }

  String _anchorTransition(
    Uint8List typeHash,
    int anchorIndex,
    String anchorUtxosJson,
  ) {
    final wifBytes = utf8.encode(_wifKey);
    final anchorUtxosBytes = utf8.encode(anchorUtxosJson);
    return using((arena) {
      final wifPtr = arena<ffi.Uint8>(wifBytes.length);
      for (var i = 0; i < wifBytes.length; i++) { wifPtr[i] = wifBytes[i]; }
      final hashPtr = arena<ffi.Uint8>(typeHash.length);
      for (var i = 0; i < typeHash.length; i++) { hashPtr[i] = typeHash[i]; }
      final utxosPtr = arena<ffi.Uint8>(anchorUtxosBytes.length);
      for (var i = 0; i < anchorUtxosBytes.length; i++) { utxosPtr[i] = anchorUtxosBytes[i]; }
      const txidCap = 65;
      final txidBuf = arena<ffi.Uint8>(txidCap);
      final txidLen = arena<ffi.Size>();
      final rc = _bindings.semantosWalletAnchorTransition(
        wifPtr, wifBytes.length,
        hashPtr, typeHash.length,
        anchorIndex,
        utxosPtr, anchorUtxosBytes.length,
        ffi.nullptr, 0,
        txidBuf, txidCap, txidLen,
      );
      if (rc != semantosOk) {
        throw FfiWalletException('semantos_wallet_anchor_transition failed: $rc');
      }
      return String.fromCharCodes(txidBuf.asTypedList(txidLen.value));
    });
  }
}

class FfiWalletException implements Exception {
  final String message;
  const FfiWalletException(this.message);

  @override
  String toString() => 'FfiWalletException: $message';
}

```
