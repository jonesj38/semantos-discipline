---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-navigation_app/lib/services/node_client.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.747925+00:00
---

# archive/apps-navigation_app/lib/services/node_client.dart

```dart
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;

/// Events streamed from the node
sealed class NodeEvent {}

class PrizeWonEvent extends NodeEvent {
  final String txId;
  final int satoshis;
  final String tierName;
  final DateTime timestamp;
  PrizeWonEvent({
    required this.txId,
    required this.satoshis,
    required this.tierName,
    required this.timestamp,
  });
}

class VestingReleasedEvent extends NodeEvent {
  final int satoshis;
  final String scheduleId;
  VestingReleasedEvent({required this.satoshis, required this.scheduleId});
}

class StreakBrokenEvent extends NodeEvent {
  final int forfeitedSatoshis;
  final int streakDays;
  StreakBrokenEvent({required this.forfeitedSatoshis, required this.streakDays});
}

class SessionValidatedEvent extends NodeEvent {
  final String sessionId;
  final bool accepted;
  final String? reason;
  SessionValidatedEvent({
    required this.sessionId,
    required this.accepted,
    this.reason,
  });
}

class SyncStateEvent extends NodeEvent {
  final NodeWalletState wallet;
  final NodeStreakState streak;
  SyncStateEvent({required this.wallet, required this.streak});
}

/// Wallet state as reported by the node
class NodeWalletState {
  final int depositedSatoshis;
  final int vestedSatoshis;
  final int unvestedSatoshis;
  final int claimableSatoshis;
  final List<NodeVestingEntry> vestingSchedules;

  NodeWalletState({
    required this.depositedSatoshis,
    required this.vestedSatoshis,
    required this.unvestedSatoshis,
    required this.claimableSatoshis,
    required this.vestingSchedules,
  });

  factory NodeWalletState.fromJson(Map<String, dynamic> json) {
    return NodeWalletState(
      depositedSatoshis: json['depositedSatoshis'] as int? ?? 0,
      vestedSatoshis: json['vestedSatoshis'] as int? ?? 0,
      unvestedSatoshis: json['unvestedSatoshis'] as int? ?? 0,
      claimableSatoshis: json['claimableSatoshis'] as int? ?? 0,
      vestingSchedules: (json['vestingSchedules'] as List<dynamic>?)
              ?.map((e) => NodeVestingEntry.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  double get vestedBsv => vestedSatoshis / 100000000;
  double get unvestedBsv => unvestedSatoshis / 100000000;
}

class NodeVestingEntry {
  final String id;
  final int totalSatoshis;
  final int releasedSatoshis;
  final double progress;
  final int daysRemaining;

  NodeVestingEntry({
    required this.id,
    required this.totalSatoshis,
    required this.releasedSatoshis,
    required this.progress,
    required this.daysRemaining,
  });

  factory NodeVestingEntry.fromJson(Map<String, dynamic> json) {
    return NodeVestingEntry(
      id: json['id'] as String,
      totalSatoshis: json['totalSatoshis'] as int,
      releasedSatoshis: json['releasedSatoshis'] as int? ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      daysRemaining: json['daysRemaining'] as int? ?? 0,
    );
  }
}

/// Streak state as reported by the node
class NodeStreakState {
  final int currentStreak;
  final int longestStreak;
  final DateTime lastCheckIn;
  final int totalSessions;
  final bool atRisk; // No check-in today and it's past warning time

  NodeStreakState({
    required this.currentStreak,
    required this.longestStreak,
    required this.lastCheckIn,
    required this.totalSessions,
    required this.atRisk,
  });

  factory NodeStreakState.fromJson(Map<String, dynamic> json) {
    return NodeStreakState(
      currentStreak: json['currentStreak'] as int? ?? 0,
      longestStreak: json['longestStreak'] as int? ?? 0,
      lastCheckIn: DateTime.parse(
          json['lastCheckIn'] as String? ?? DateTime.now().toIso8601String()),
      totalSessions: json['totalSessions'] as int? ?? 0,
      atRisk: json['atRisk'] as bool? ?? false,
    );
  }
}

/// Client that syncs with the Semantos node.
///
/// Architecture: The economic incentives (deposits, prize pools, vesting,
/// forfeits) all run on the node. The app is a client that:
///
/// 1. Submits declarations (sessions, reviews, intentions) to the node
/// 2. Receives validation results (accepted/rejected + reason)
/// 3. Streams real-time events (prize wins, vesting releases)
/// 4. Periodically syncs full state (wallet, streak)
///
/// The WASM kernel runs in both places:
/// - On the node: enforces the financial protocol + validates sessions
/// - In the app: enforces consumption semantics locally for UX
///
/// The Paskian learning graph runs on the node and can flag suspicious
/// patterns (e.g., sessions that are too short, too regular, or lack
/// the variation signature of genuine practice).
class NodeClient {
  final String nodeUrl;
  final String _wsUrl;
  String? _authToken;
  WebSocketChannel? _channel;
  http.Client? _httpClient;

  final StreamController<NodeEvent> _eventController =
      StreamController.broadcast();

  /// Live event stream from the node
  Stream<NodeEvent> get events => _eventController.stream;

  /// Last known state
  NodeWalletState? _walletState;
  NodeStreakState? _streakState;

  NodeWalletState? get wallet => _walletState;
  NodeStreakState? get streak => _streakState;

  NodeClient({
    this.nodeUrl = 'https://node.semantos.io',
  }) : _wsUrl = nodeUrl.replaceFirst('https', 'wss').replaceFirst('http', 'ws');

  /// Connect to node and authenticate
  Future<bool> connect({required String authToken}) async {
    _authToken = authToken;
    _httpClient = http.Client();

    try {
      // Open WebSocket for real-time events
      _channel = WebSocketChannel.connect(
        Uri.parse('$_wsUrl/ws/navigation?token=$authToken'),
      );

      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          // Reconnect on error
          Future.delayed(const Duration(seconds: 5), () {
            connect(authToken: authToken);
          });
        },
        onDone: () {
          // Reconnect on close
          Future.delayed(const Duration(seconds: 5), () {
            connect(authToken: authToken);
          });
        },
      );

      // Initial state sync
      await syncState();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Submit a session declaration to the node.
  /// The node validates it (Paskian anti-fudge check) and returns accepted/rejected.
  Future<SessionValidatedEvent> submitSession({
    required String sessionId,
    required String sessionType,
    required int durationSeconds,
    required Map<String, dynamic> data,
  }) async {
    final response = await _post('/api/navigation/sessions', {
      'sessionId': sessionId,
      'sessionType': sessionType,
      'durationSeconds': durationSeconds,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });

    final result = SessionValidatedEvent(
      sessionId: sessionId,
      accepted: response['accepted'] as bool? ?? false,
      reason: response['reason'] as String?,
    );

    _eventController.add(result);
    return result;
  }

  /// Submit a daily review to the node
  Future<SessionValidatedEvent> submitDailyReview({
    required String reviewId,
    required Map<String, dynamic> data,
  }) async {
    final response = await _post('/api/navigation/reviews', {
      'reviewId': reviewId,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });

    return SessionValidatedEvent(
      sessionId: reviewId,
      accepted: response['accepted'] as bool? ?? false,
      reason: response['reason'] as String?,
    );
  }

  /// Submit a morning intention
  Future<SessionValidatedEvent> submitIntention({
    required String intentionId,
    required Map<String, dynamic> data,
  }) async {
    final response = await _post('/api/navigation/intentions', {
      'intentionId': intentionId,
      'data': data,
      'timestamp': DateTime.now().toIso8601String(),
    });

    return SessionValidatedEvent(
      sessionId: intentionId,
      accepted: response['accepted'] as bool? ?? true,
      reason: response['reason'] as String?,
    );
  }

  /// Request deposit (node returns a BSV address to pay)
  Future<Map<String, dynamic>> requestDeposit({
    required int satoshis,
  }) async {
    return await _post('/api/navigation/deposit', {
      'satoshis': satoshis,
    });
    // Returns: { 'address': '1...', 'satoshis': 10500000, 'expiresAt': '...' }
  }

  /// Claim vested winnings (node initiates BSV transfer)
  Future<Map<String, dynamic>> claimVested({
    required String destinationAddress,
  }) async {
    return await _post('/api/navigation/claim', {
      'destinationAddress': destinationAddress,
    });
  }

  /// Get Paskian graph state from the node
  /// (The node runs the authoritative graph; app mirrors it)
  Future<Map<String, dynamic>> getPaskianState() async {
    return await _get('/api/navigation/paskian');
  }

  /// Get Paskian insights generated by the node
  Future<List<String>> getPaskianInsights() async {
    final response = await _get('/api/navigation/paskian/insights');
    return (response['insights'] as List<dynamic>?)
            ?.cast<String>() ??
        [];
  }

  /// Sync full state from node
  Future<void> syncState() async {
    try {
      final state = await _get('/api/navigation/state');

      _walletState = NodeWalletState.fromJson(
          state['wallet'] as Map<String, dynamic>? ?? {});
      _streakState = NodeStreakState.fromJson(
          state['streak'] as Map<String, dynamic>? ?? {});

      _eventController.add(SyncStateEvent(
        wallet: _walletState!,
        streak: _streakState!,
      ));
    } catch (e) {
      // Offline — use cached state
    }
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final type = data['type'] as String?;

      switch (type) {
        case 'prize_won':
          _eventController.add(PrizeWonEvent(
            txId: data['txId'] as String,
            satoshis: data['satoshis'] as int,
            tierName: data['tierName'] as String,
            timestamp: DateTime.parse(data['timestamp'] as String),
          ));
        case 'vesting_released':
          _eventController.add(VestingReleasedEvent(
            satoshis: data['satoshis'] as int,
            scheduleId: data['scheduleId'] as String,
          ));
        case 'streak_broken':
          _eventController.add(StreakBrokenEvent(
            forfeitedSatoshis: data['forfeitedSatoshis'] as int,
            streakDays: data['streakDays'] as int,
          ));
        case 'session_validated':
          _eventController.add(SessionValidatedEvent(
            sessionId: data['sessionId'] as String,
            accepted: data['accepted'] as bool,
            reason: data['reason'] as String?,
          ));
        case 'sync':
          syncState();
      }
    } catch (e) {
      // Malformed message — ignore
    }
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final response = await _httpClient!.get(
      Uri.parse('$nodeUrl$path'),
      headers: {
        'Authorization': 'Bearer $_authToken',
        'Content-Type': 'application/json',
      },
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(
      String path, Map<String, dynamic> body) async {
    final response = await _httpClient!.post(
      Uri.parse('$nodeUrl$path'),
      headers: {
        'Authorization': 'Bearer $_authToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void dispose() {
    _channel?.sink.close();
    _httpClient?.close();
    _eventController.close();
  }
}

```
