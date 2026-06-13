---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/lib/kernel/wasm_bridge.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.747300+00:00
---

# archive/apps-navigation_app/lib/kernel/wasm_bridge.dart

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Result from a kernel operation
class KernelResult {
  final bool success;
  final String? objectId;
  final String? error;
  final Map<String, dynamic>? metadata;

  KernelResult({
    required this.success,
    this.objectId,
    this.error,
    this.metadata,
  });
}

/// Consumption validation result
class ConsumptionCheck {
  final bool allowed;
  final String reason;
  final String consumptionType; // linear, affine, relevant

  ConsumptionCheck({
    required this.allowed,
    required this.reason,
    required this.consumptionType,
  });
}

/// Bridge between the Flutter app and the Semantos WASM kernel.
///
/// The kernel enforces consumption semantics:
/// - LINEAR objects (releases, sessions) can only be consumed once
/// - AFFINE objects (intentions) can be acknowledged or discarded
/// - RELEVANT objects (insights, patterns) persist until explicitly revoked
///
/// This is what makes this a Semantos app, not just a regular app.
/// The kernel also validates types against the navigation vertical config.
class WasmKernelBridge {
  // WASM module instance
  // WasmModule? _module;
  bool _initialized = false;

  /// Kernel state
  final Map<String, Map<String, dynamic>> _objectStore = {};
  final Map<String, bool> _consumedObjects = {};

  /// Initialize the WASM kernel module
  Future<void> initialize({required Uint8List wasmBytes}) async {
    if (_initialized) return;

    // TODO: Load WASM module
    // _module = await WasmModule.compile(wasmBytes);
    // await _module!.instantiate();

    // Load the navigation vertical config into the kernel
    // This registers all the type definitions and consumption rules
    // await _callKernel('load_vertical', {'config': 'navigation'});

    _initialized = true;
  }

  /// Initialize with bundled WASM from assets
  Future<void> initializeFromAssets() async {
    // TODO: Load from Flutter assets
    // final bytes = await rootBundle.load('assets/wasm/semantos_kernel.wasm');
    // await initialize(wasmBytes: bytes.buffer.asUint8List());

    // For now, initialize in-memory simulation mode
    _initialized = true;
  }

  bool get isInitialized => _initialized;

  /// Create a new semantic object in the kernel.
  /// The kernel validates the type against the navigation vertical config
  /// and assigns the correct consumption rules.
  Future<KernelResult> createObject({
    required String typeHash,
    required String typeName,
    required Map<String, dynamic> data,
  }) async {
    _ensureInitialized();

    // TODO: Call WASM kernel
    // final result = await _callKernel('create_object', {
    //   'type_hash': typeHash,
    //   'type_name': typeName,
    //   'data': jsonEncode(data),
    // });

    // In-memory simulation
    final objectId = data['id'] as String? ?? _generateId();
    _objectStore[objectId] = {
      'typeHash': typeHash,
      'typeName': typeName,
      'data': data,
      'createdAt': DateTime.now().toIso8601String(),
    };

    return KernelResult(
      success: true,
      objectId: objectId,
      metadata: {'typeName': typeName, 'typeHash': typeHash},
    );
  }

  /// Consume a LINEAR object (e.g., release a Release, complete a Session).
  /// The kernel enforces that LINEAR objects can only be consumed once.
  /// Attempting to consume again returns an error.
  Future<KernelResult> consumeLinear(String objectId) async {
    _ensureInitialized();

    // Check if already consumed
    if (_consumedObjects[objectId] == true) {
      return KernelResult(
        success: false,
        error: 'Object $objectId already consumed (LINEAR — cannot re-consume)',
      );
    }

    // TODO: Call WASM kernel consume
    // final result = await _callKernel('consume_linear', {'id': objectId});

    _consumedObjects[objectId] = true;
    return KernelResult(success: true, objectId: objectId);
  }

  /// Acknowledge an AFFINE object (e.g., fulfil or discard an Intention).
  /// AFFINE objects can be acknowledged exactly once — fulfil OR discard.
  Future<KernelResult> acknowledgeAffine(
    String objectId, {
    required String action, // 'fulfil', 'discard', 'transform'
  }) async {
    _ensureInitialized();

    if (_consumedObjects[objectId] == true) {
      return KernelResult(
        success: false,
        error: 'Object $objectId already acknowledged (AFFINE — one action only)',
      );
    }

    // TODO: Call WASM kernel
    _consumedObjects[objectId] = true;
    final stored = _objectStore[objectId];
    if (stored != null) {
      (stored['data'] as Map<String, dynamic>)['status'] = action;
    }

    return KernelResult(
      success: true,
      objectId: objectId,
      metadata: {'action': action},
    );
  }

  /// Check if an object can be consumed/acknowledged
  Future<ConsumptionCheck> checkConsumption(String objectId) async {
    _ensureInitialized();

    final stored = _objectStore[objectId];
    if (stored == null) {
      return ConsumptionCheck(
        allowed: false,
        reason: 'Object not found',
        consumptionType: 'unknown',
      );
    }

    final consumed = _consumedObjects[objectId] == true;
    final typeName = stored['typeName'] as String;
    final consumptionType = _getConsumptionType(typeName);

    if (consumed) {
      return ConsumptionCheck(
        allowed: false,
        reason: '$consumptionType object already consumed',
        consumptionType: consumptionType,
      );
    }

    return ConsumptionCheck(
      allowed: true,
      reason: 'Object available for consumption',
      consumptionType: consumptionType,
    );
  }

  /// Query RELEVANT objects — these are always accessible
  Future<List<Map<String, dynamic>>> queryRelevant({
    String? typeName,
    Map<String, dynamic>? filters,
  }) async {
    _ensureInitialized();

    return _objectStore.entries
        .where((e) {
          if (typeName != null && e.value['typeName'] != typeName) return false;
          final ct = _getConsumptionType(e.value['typeName'] as String);
          return ct == 'relevant';
        })
        .map((e) => {'id': e.key, ...e.value})
        .toList();
  }

  /// Revoke a RELEVANT object (insight outgrown, pattern no longer applies)
  Future<KernelResult> revokeRelevant(String objectId) async {
    _ensureInitialized();

    final stored = _objectStore[objectId];
    if (stored == null) {
      return KernelResult(success: false, error: 'Object not found');
    }

    final ct = _getConsumptionType(stored['typeName'] as String);
    if (ct != 'relevant') {
      return KernelResult(
        success: false,
        error: 'Only RELEVANT objects can be revoked',
      );
    }

    _objectStore.remove(objectId);
    return KernelResult(success: true, objectId: objectId);
  }

  /// Validate a BSV transaction against the kernel's financial rules.
  /// The kernel ensures deposits, vesting, and forfeit follow the protocol.
  Future<KernelResult> validateTransaction({
    required String txType,
    required int satoshis,
    required Map<String, dynamic> context,
  }) async {
    _ensureInitialized();

    // TODO: Call WASM kernel for transaction validation
    // Kernel checks:
    // 1. Deposit amount within allowed range
    // 2. Vesting schedule matches tier rules
    // 3. Forfeit only applies to unvested amounts
    // 4. Refund only on verified completion

    return KernelResult(
      success: true,
      metadata: {'txType': txType, 'satoshis': satoshis, 'validated': true},
    );
  }

  String _getConsumptionType(String typeName) {
    const linearTypes = {
      'Release', 'Session', 'VacuumSession', 'GoldSeal',
      'Connection', 'DailyReview', 'MorningIntention',
    };
    const affineTypes = {'Intention', 'DimensionPulse'};
    const relevantTypes = {
      'Insight', 'Pattern', 'DimensionState',
      'AccountabilityStreak',
    };

    if (linearTypes.contains(typeName)) return 'linear';
    if (affineTypes.contains(typeName)) return 'affine';
    if (relevantTypes.contains(typeName)) return 'relevant';
    return 'unknown';
  }

  String _generateId() => DateTime.now().microsecondsSinceEpoch.toString();

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('Kernel not initialized. Call initialize() first.');
    }
  }

  void dispose() {
    _objectStore.clear();
    _consumedObjects.clear();
  }
}

```
