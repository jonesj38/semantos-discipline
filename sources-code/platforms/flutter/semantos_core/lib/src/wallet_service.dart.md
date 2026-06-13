---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/wallet_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.015810+00:00
---

# platforms/flutter/semantos_core/lib/src/wallet_service.dart

```dart
import 'dart:typed_data';

/// Result of a pay operation.
class PayResult {
  final String txid;
  const PayResult({required this.txid});
}

/// Result of an anchorTransition operation.
class AnchorResult {
  final String txid;
  const AnchorResult({required this.txid});
}

/// A transaction output: locking script (hex) + satoshis.
class Output {
  final String lockScript;
  final int satoshis;
  const Output(this.lockScript, this.satoshis);

  Map<String, dynamic> toJson() => {
        'lockScript': lockScript,
        'satoshis': satoshis,
      };
}

/// A transaction input for createAction (explicit spend).
class TxInput {
  final String txid;
  final int vout;
  final String? lockScript;
  final int? satoshis;
  const TxInput({
    required this.txid,
    required this.vout,
    this.lockScript,
    this.satoshis,
  });

  Map<String, dynamic> toJson() => {
        'txid': txid,
        'vout': vout,
        if (lockScript != null) 'lockScript': lockScript,
        if (satoshis != null) 'satoshis': satoshis,
      };
}

/// Wallet operations interface.
///
/// Implementations:
///   - [BrainWalletService] — calls POST /api/v1/wallet-op on a connected
///     `brain` instance (online operators).
///   - semantos_ffi FfiWalletService — calls the C ABI wallet directly
///     (offline / embedded; ships in P2).
abstract class WalletService {
  /// Build and broadcast a payment transaction.
  ///
  /// [outputs] are fully resolved (lock scripts + satoshis). Contact
  /// resolution (name → pubkey → lock script) is the caller's
  /// responsibility — the wallet never holds a contact book.
  Future<PayResult> pay(
    List<Output> outputs, {
    String? description,
  });

  /// Spend a LINEAR cell anchor UTXO, recording the state transition
  /// on-chain. [typeHash] is the 32-byte cell type identifier. The wallet
  /// derives the anchor spending key via BRC-42 self-ECDH.
  Future<AnchorResult> anchorTransition(
    Uint8List typeHash,
    int anchorIndex,
    Uint8List newStateHash, {
    String? description,
  });

  /// General-purpose spend with explicit inputs + outputs. Inputs that
  /// have no unlocking script are signed with the operator's identity key.
  Future<PayResult> createAction(
    List<TxInput> inputs,
    List<Output> outputs, {
    String? description,
  });

  /// Returns the operator's compressed identity public key as lowercase hex.
  Future<String> identityPubkeyHex();
}

```
