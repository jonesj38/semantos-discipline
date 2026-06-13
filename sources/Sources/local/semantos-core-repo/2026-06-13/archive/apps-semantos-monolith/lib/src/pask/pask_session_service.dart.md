---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/pask/pask_session_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.865244+00:00
---

# archive/apps-semantos-monolith/lib/src/pask/pask_session_service.dart

```dart
// W1.3 — PaskSessionService: lifecycle seam between the Flutter app and
// the pask WASM kernel.
//
// The pask WASM exposes two operations relevant to the mobile FSM:
//
//   pask_restore_state(ptr) — reload the graph from a prior snapshot.
//     Called on app foreground (AppLifecycleState.resumed) so the WASM
//     graph picks up where it left off after a cold-start or background.
//
//   pask_interact_run(primaryIdx, kindPtr, kindLen, effectiveStrength,
//                     relatedIdxPtr, relatedCount, nowMs) → affectedCount
//     Called after every confirmed FSM action (quoteJob, invoiceJob, etc.)
//     to notify the attention graph.  After the run, the snapshot is
//     exported and persisted so the next restore gets the updated state.
//
// This service owns the lifecycle plumbing.  The actual WASM calls are
// injected via [PaskRestoreCall] and [PaskInteractCall] so this class
// stays Flutter-SDK-free for unit tests.
//
// Production wiring (home_screen.dart):
//   1. `initState` opens the DB, constructs this service.
//   2. `didChangeAppLifecycleState(resumed)` calls `onResume()`.
//   3. `quoteJob`/`invoiceJob`/etc. calls `onFsmAction(cellId, kindPath)`.

import 'dart:typed_data';

import 'sqlite_pask_snapshot_store.dart';

/// Snapshot key used for the primary pask graph snapshot.
const String kPaskGraphSnapshotKey = 'graph';

/// Callback type for pask_restore_state.
/// Returns 0 on success; negative on error.
typedef PaskRestoreCall = int Function(Uint8List snapshot);

/// Callback type for pask_interact_run + snapshot export.
/// [cellId] is the cell whose state changed; [kindPath] is the FSM
/// action kind (e.g. 'oddjobz.job.quote').
/// Returns the exported snapshot bytes after the interaction, or null
/// on failure.
typedef PaskInteractAndSnapshotCall = Future<Uint8List?> Function(
    String cellId, String kindPath);

/// Wires the Pask WASM graph into the Flutter app lifecycle.
///
/// See module comment for the contract.
class PaskSessionService {
  final SqlitePaskSnapshotStore _store;
  final int _domainFlag;
  final PaskRestoreCall? _restoreCall;
  final PaskInteractAndSnapshotCall? _interactAndSnapshot;

  /// Whether a snapshot has been loaded since the last [onResume].
  bool _restored = false;

  /// Last snapshot bytes (in-memory cache; null until first restore).
  Uint8List? _cachedSnapshot;

  PaskSessionService({
    required SqlitePaskSnapshotStore store,
    required int domainFlag,
    PaskRestoreCall? restoreCall,
    PaskInteractAndSnapshotCall? interactAndSnapshot,
  })  : _store = store,
        _domainFlag = domainFlag,
        _restoreCall = restoreCall,
        _interactAndSnapshot = interactAndSnapshot;

  /// Called when the app returns to the foreground.
  ///
  /// Loads the stored snapshot and calls [PaskRestoreCall] to restore
  /// the WASM graph.  A no-op when no snapshot has been saved yet
  /// (cold start) or when no [restoreCall] was provided (test / stub).
  Future<void> onResume() async {
    final blob = await _store.load(
        domainFlag: _domainFlag, key: kPaskGraphSnapshotKey);
    if (blob == null) {
      _restored = false;
      return;
    }
    _cachedSnapshot = blob;
    if (_restoreCall != null) {
      _restoreCall(blob);
    }
    _restored = true;
  }

  /// Called after a confirmed FSM action.
  ///
  /// [cellId] — the affected cell (e.g. a job or visit id).
  /// [kindPath] — the action kind (e.g. 'oddjobz.job.quote').
  ///
  /// Calls [PaskInteractAndSnapshotCall] to run pask_interact_run and
  /// export the updated snapshot, then persists it for the next resume.
  /// A no-op when no [interactAndSnapshot] was provided.
  Future<void> onFsmAction(String cellId, String kindPath) async {
    if (_interactAndSnapshot == null) return;
    final snapshot = await _interactAndSnapshot(cellId, kindPath);
    if (snapshot == null) return;
    _cachedSnapshot = snapshot;
    await _store.save(
        domainFlag: _domainFlag,
        key: kPaskGraphSnapshotKey,
        blob: snapshot);
  }

  /// Whether a snapshot was successfully restored on the last [onResume].
  bool get isRestored => _restored;

  /// The most recently cached snapshot bytes (may be null if no snapshot
  /// has been saved or loaded yet).
  Uint8List? get cachedSnapshot => _cachedSnapshot;

  /// Close the underlying snapshot store.  Call from the owning widget's
  /// `dispose()`.
  Future<void> close() => _store.close();
}

```
