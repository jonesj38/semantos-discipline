---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/lib/services/bsv_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.749078+00:00
---

# archive/apps-navigation_app/lib/services/bsv_service.dart

```dart
import 'dart:async';
import 'node_client.dart';

/// Thin convenience layer over NodeClient for BSV-related operations.
/// All actual financial logic runs on the node — this just provides
/// a clean API for the UI to bind to.
class BsvService {
  final NodeClient _node;
  final StreamController<PrizeWonEvent> _prizeController =
      StreamController.broadcast();

  BsvService({required NodeClient node}) : _node = node {
    // Forward prize events from node
    _node.events.listen((event) {
      if (event is PrizeWonEvent) {
        _prizeController.add(event);
      }
    });
  }

  /// Live prize stream for UI
  Stream<PrizeWonEvent> get prizeStream => _prizeController.stream;

  /// Current wallet state from last sync
  NodeWalletState? get wallet => _node.wallet;
  NodeStreakState? get streak => _node.streak;

  /// Request a deposit address from the node
  Future<Map<String, dynamic>> requestDeposit({required int satoshis}) {
    return _node.requestDeposit(satoshis: satoshis);
  }

  /// Claim vested winnings
  Future<Map<String, dynamic>> claimVested({required String address}) {
    return _node.claimVested(destinationAddress: address);
  }

  /// Force a state refresh
  Future<void> refresh() => _node.syncState();

  void dispose() {
    _prizeController.close();
  }
}

```
