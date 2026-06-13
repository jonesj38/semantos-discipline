---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/conversation_turn.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.461114+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/conversation_turn.dart

```dart
// OddjobzConversationTurn — Dart model matching
// OddjobzConversationTurnPayload from the TypeScript side.
//
// Populated from GET /api/v1/conversation/turns?entityRef=<cellHash>
// response shape: { ok: true, turns: [...] }

class ConversationTurn {
  final String turnId;
  final String conversationId;
  final String participantRole; // 'external'|'operator'|'ai'|'subcontractor'
  final String direction; // 'inbound'|'outbound'
  final String surface; // 'email'|'gmail'|'sms'|'meta-inbox'|'widget'
  final String bodyText;
  final int timestamp; // ms epoch

  final String? outboundState; // 'drafted'|'proposed'|'approved'|'sent'|...
  final String? identityValue; // identityHandle.value when present
  final String? entityCellHash; // entityRef.cellHash when present

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
    this.entityCellHash,
  });

  factory ConversationTurn.fromJson(Map<String, dynamic> j) {
    final identity = j['identityHandle'] as Map<String, dynamic>?;
    final entityRef = j['entityRef'] as Map<String, dynamic>?;
    return ConversationTurn(
      turnId: j['turnId'] as String? ?? '',
      conversationId: j['conversationId'] as String? ?? '',
      participantRole: j['participantRole'] as String? ?? 'external',
      direction: j['direction'] as String? ?? 'inbound',
      surface: j['surface'] as String? ?? 'email',
      bodyText: j['bodyText'] as String? ?? '',
      timestamp: (j['timestamp'] as num? ?? 0).toInt(),
      outboundState: j['outboundState'] as String?,
      identityValue: identity?['value'] as String?,
      entityCellHash: entityRef?['cellHash'] as String?,
    );
  }

  bool get isInbound => direction == 'inbound';
  bool get isProposed => outboundState == 'proposed';
}

```
