---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/conversation_turn.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.878525+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/conversation_turn.dart

```dart
// ConversationTurn — canonical model mirroring the
// `oddjobz.conversation.turn` sem_objects rows surfaced by
// GET /api/v1/conversation/turns?entityRef=<cellHash>.
//
// This replaces the old OddjobzMessagePatch / OddjobzDispatchDecision
// model in JobThreadScreen.  Canonical field names match the brain's
// conversation_turns_http.zig bun-script output shape verbatim.

class ConversationTurn {
  /// UUID turn id from Postgres.
  final String turnId;

  /// UUID conversation id.
  final String conversationId;

  /// 'customer' | 'operator' | 'assistant'.
  final String participantRole;

  /// 'inbound' | 'outbound'.
  final String direction;

  /// Surface the message arrived on / was sent through:
  /// 'email' | 'gmail' | 'sms' | 'meta-inbox' | 'widget' | ...
  final String surface;

  /// The human-readable message body.
  final String bodyText;

  /// Unix epoch milliseconds.
  final int timestamp;

  /// For outbound turns: 'proposed' | 'approved' | 'sent' | 'delivered'
  /// | 'failed' | 'rejected'.  Null for inbound turns.
  final String? outboundState;

  /// Sender identifier shown as the display name under the surface label
  /// (e.g. an email address, phone number, or contact name).
  /// Null when the brain hasn't resolved it.
  final String? identityValue;

  const ConversationTurn({
    required this.turnId,
    required this.conversationId,
    required this.participantRole,
    required this.direction,
    required this.surface,
    required this.bodyText,
    required this.timestamp,
    this.outboundState,
    this.identityValue,
  });

  /// True when this turn arrived from the customer.
  bool get isInbound => direction == 'inbound';

  /// True when this is an outbound turn waiting for operator approval.
  bool get isProposed => outboundState == 'proposed';

  factory ConversationTurn.fromJson(Map<String, dynamic> j) {
    return ConversationTurn(
      turnId: j['turnId'] as String? ?? '',
      conversationId: j['conversationId'] as String? ?? '',
      participantRole: j['participantRole'] as String? ?? '',
      direction: j['direction'] as String? ?? '',
      surface: j['surface'] as String? ?? '',
      bodyText: j['bodyText'] as String? ?? '',
      timestamp: j['timestamp'] as int? ??
          (j['timestamp'] is num
              ? (j['timestamp'] as num).toInt()
              : 0),
      outboundState: j['outboundState'] as String?,
      // identityHandle is {kind, value}; identityValue is a flattened alias.
      identityValue: j['identityValue'] as String? ??
          (j['identityHandle'] is Map
              ? (j['identityHandle'] as Map<dynamic, dynamic>)['value']
                    as String?
              : null),
    );
  }
}

```
