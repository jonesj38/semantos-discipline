---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/talk/conversation_cell.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.864527+00:00
---

# archive/apps-semantos-monolith/lib/src/talk/conversation_cell.dart

```dart
// Talk surface — ConversationCell model.
//
// A conversation is a cell stored in hat_entity_cache (entity_tag =
// 'conversation.v1').  It mutates under patches via the normal outbox
// → BRAIN brain pipeline.  On mobile it is cached in SQLite and updated
// by EventSubscriptionService write-through on every FSM event.
//
// TalkMode mirrors the five surfaces in TalkNode:
//   self      — internal notes / Pask session journal
//   direct    — 1:1 threads with a specific contact
//   squad     — group channels (work team or social group, time-routed)
//   agent     — Semantos brain or on-device Llama agent sessions
//   broadcast — 1-to-many status updates / announcements
//
// ConversationContext links the cell to an entity driving urgency (e.g.
// the invoice that is rising on the attention surface).  When context
// is present TalkSurfaceService uses the linked entity's attention
// score to rank this window higher.

import 'dart:convert';

// ── TalkMode ─────────────────────────────────────────────────────────────

enum TalkMode {
  self,
  direct,
  squad,
  agent,
  broadcast;

  String get label => switch (this) {
        TalkMode.self      => 'Self',
        TalkMode.direct    => 'Direct',
        TalkMode.squad     => 'Squad',
        TalkMode.agent     => 'Agent',
        TalkMode.broadcast => 'Broadcast',
      };

  static TalkMode fromString(String s) => switch (s) {
        'self'      => TalkMode.self,
        'direct'    => TalkMode.direct,
        'squad'     => TalkMode.squad,
        'agent'     => TalkMode.agent,
        'broadcast' => TalkMode.broadcast,
        _           => TalkMode.direct,
      };
}

// ── ConversationTurn ──────────────────────────────────────────────────────

class ConversationTurn {
  final String from;     // entity id or 'self'
  final String body;
  final DateTime ts;

  const ConversationTurn({
    required this.from,
    required this.body,
    required this.ts,
  });

  factory ConversationTurn.fromJson(Map<String, dynamic> j) =>
      ConversationTurn(
        from: (j['from'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        ts: DateTime.tryParse((j['ts'] ?? '').toString()) ?? DateTime(0),
      );

  Map<String, dynamic> toJson() => {
        'from': from,
        'body': body,
        'ts': ts.toIso8601String(),
      };
}

// ── ConversationContext ───────────────────────────────────────────────────

/// Links a conversation to the entity driving its urgency.
class ConversationContext {
  final String? jobId;
  final String? invoiceId;
  final String? quoteId;
  final String? visitId;

  const ConversationContext({
    this.jobId,
    this.invoiceId,
    this.quoteId,
    this.visitId,
  });

  bool get hasContext =>
      jobId != null || invoiceId != null || quoteId != null || visitId != null;

  /// The most specific linked entity id, for display / routing.
  String? get primaryRef => invoiceId ?? jobId ?? quoteId ?? visitId;

  String get primaryLabel => invoiceId != null
      ? 'Invoice'
      : jobId != null
          ? 'Job'
          : quoteId != null
              ? 'Quote'
              : visitId != null
                  ? 'Visit'
                  : '';

  factory ConversationContext.fromJson(Map<String, dynamic> j) =>
      ConversationContext(
        jobId:     (j['job_id'] as String?)?.nullIfEmpty,
        invoiceId: (j['invoice_id'] as String?)?.nullIfEmpty,
        quoteId:   (j['quote_id'] as String?)?.nullIfEmpty,
        visitId:   (j['visit_id'] as String?)?.nullIfEmpty,
      );

  Map<String, dynamic> toJson() => {
        if (jobId != null)     'job_id':     jobId,
        if (invoiceId != null) 'invoice_id': invoiceId,
        if (quoteId != null)   'quote_id':   quoteId,
        if (visitId != null)   'visit_id':   visitId,
      };
}

extension _StringX on String {
  String? get nullIfEmpty => isEmpty ? null : this;
}

// ── ConversationCell ──────────────────────────────────────────────────────

class ConversationCell {
  /// Cell id — matches hat_entity_cache.id.
  final String id;

  /// Human-readable title (group name, contact name, or 'Self').
  final String title;

  /// Avatar initials or emoji for display (e.g. 'JD', '🧑‍🔧').
  final String avatar;

  final TalkMode mode;

  /// Participant entity ids (customer_id, contact_id, squad group_id, etc.)
  final List<String> participants;

  /// For Direct mode cells backed by the Plexus contact book: the
  /// BRC-52 certId of the contact.  Non-null means this thread is
  /// PKI-grounded — messages are encrypted/routed via the MESSAGING
  /// edge for this certId.  Null for OddjobZ domain-entity threads
  /// (customers, tradespeople) that don't yet have a Plexus identity.
  final String? contactCertId;

  final List<ConversationTurn> turns;

  /// Linked entity driving urgency (nullable when no entity context).
  final ConversationContext context;

  /// FSM phase: 'open' | 'active' | 'archived'.
  final String phase;

  final DateTime updatedAt;

  /// Attention score 0.0–1.0 injected by TalkSurfaceService from the
  /// attention surface.  Not stored in the cell; computed at rank time.
  final double attentionScore;

  const ConversationCell({
    required this.id,
    required this.title,
    required this.avatar,
    required this.mode,
    required this.participants,
    required this.turns,
    required this.context,
    required this.phase,
    required this.updatedAt,
    this.contactCertId,
    this.attentionScore = 0.0,
  });

  ConversationTurn? get lastTurn => turns.isEmpty ? null : turns.last;

  String get lastTurnPreview {
    final t = lastTurn;
    if (t == null) return '';
    final body = t.body;
    return body.length > 60 ? '${body.substring(0, 60)}…' : body;
  }

  // ── Serialisation ────────────────────────────────────────────────

  factory ConversationCell.fromEntityJson(String entityJson, {
    String id = '',
    DateTime? updatedAt,
  }) {
    final j = json.decode(entityJson) as Map<String, dynamic>;
    return ConversationCell(
      id:           id.isNotEmpty ? id : (j['id'] ?? '').toString(),
      title:        (j['title']  ?? '').toString(),
      avatar:       (j['avatar'] ?? '').toString(),
      mode:         TalkMode.fromString((j['mode'] ?? 'direct').toString()),
      participants: (j['participants'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      contactCertId: (j['contactCertId'] as String?)?.nullIfEmpty,
      turns: (j['turns'] as List<dynamic>?)
              ?.map((e) => ConversationTurn.fromJson(
                    e as Map<String, dynamic>))
              .toList() ??
          const [],
      context: ConversationContext.fromJson(
          (j['context'] as Map<String, dynamic>?) ?? const {}),
      phase:     (j['phase'] ?? 'open').toString(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  String toEntityJson() => json.encode({
        'id':           id,
        'title':        title,
        'avatar':       avatar,
        'mode':         mode.name,
        'participants': participants,
        if (contactCertId != null) 'contactCertId': contactCertId,
        'turns':        turns.map((t) => t.toJson()).toList(),
        'context':      context.toJson(),
        'phase':        phase,
      });

  ConversationCell copyWith({
    double? attentionScore,
    List<ConversationTurn>? turns,
    String? phase,
  }) =>
      ConversationCell(
        id:             id,
        title:          title,
        avatar:         avatar,
        mode:           mode,
        participants:   participants,
        contactCertId:  contactCertId,
        turns:          turns    ?? this.turns,
        context:        context,
        phase:          phase    ?? this.phase,
        updatedAt:      updatedAt,
        attentionScore: attentionScore ?? this.attentionScore,
      );

  /// True if this cell is backed by a Plexus PKI contact (certId known).
  bool get isPlexusContact => contactCertId != null && contactCertId!.isNotEmpty;
}

// ── Stub factory for mobile-first development ─────────────────────────────

/// Returns a set of stub ConversationCells so TalkNode renders before
/// brain-side conversation cell FSM is wired.  Remove once
/// HatEntityRepository.queryConversations() returns real cells.
List<ConversationCell> stubConversationCells() {
  final now = DateTime.now();
  return [
    // Self
    ConversationCell(
      id: 'conv-self-journal',
      title: 'Journal',
      avatar: '📓',
      mode: TalkMode.self,
      participants: const ['self'],
      turns: [
        ConversationTurn(from: 'self', body: 'Remember to chase invoice #042.', ts: now.subtract(const Duration(hours: 2))),
      ],
      context: const ConversationContext(),
      phase: 'active',
      updatedAt: now.subtract(const Duration(hours: 2)),
    ),
    ConversationCell(
      id: 'conv-self-pask',
      title: 'Pask session',
      avatar: '🧠',
      mode: TalkMode.self,
      participants: const ['self'],
      turns: [],
      context: const ConversationContext(),
      phase: 'open',
      updatedAt: now.subtract(const Duration(minutes: 10)),
    ),
    ConversationCell(
      id: 'conv-self-notes',
      title: 'Voice notes',
      avatar: '🎙️',
      mode: TalkMode.self,
      participants: const ['self'],
      turns: [
        ConversationTurn(from: 'self', body: 'Newtown job — check water pressure at mains.', ts: now.subtract(const Duration(days: 1))),
      ],
      context: const ConversationContext(),
      phase: 'open',
      updatedAt: now.subtract(const Duration(days: 1)),
    ),

    // Direct
    ConversationCell(
      id: 'conv-direct-invoice042',
      title: 'Marie Chen',
      avatar: 'MC',
      mode: TalkMode.direct,
      participants: const ['customer-mc-001'],
      turns: [
        ConversationTurn(from: 'customer-mc-001', body: 'Can you send through the invoice again?', ts: now.subtract(const Duration(hours: 1))),
      ],
      context: const ConversationContext(invoiceId: 'inv-042'),
      phase: 'active',
      updatedAt: now.subtract(const Duration(hours: 1)),
      attentionScore: 0.9,
    ),
    ConversationCell(
      id: 'conv-direct-joe',
      title: "Joe's Plumbing",
      avatar: 'JP',
      mode: TalkMode.direct,
      participants: const ['tradesperson-jp-001'],
      turns: [
        ConversationTurn(from: 'tradesperson-jp-001', body: 'On my way — 10 mins.', ts: now.subtract(const Duration(minutes: 30))),
      ],
      context: const ConversationContext(jobId: 'job-wattle-st'),
      phase: 'active',
      updatedAt: now.subtract(const Duration(minutes: 30)),
      attentionScore: 0.7,
    ),
    ConversationCell(
      id: 'conv-direct-landlord',
      title: 'David Park',
      avatar: 'DP',
      mode: TalkMode.direct,
      participants: const ['landlord-dp-001'],
      turns: [
        ConversationTurn(from: 'self', body: 'Quote approved — works starts Monday.', ts: now.subtract(const Duration(days: 2))),
      ],
      context: const ConversationContext(quoteId: 'quote-007'),
      phase: 'open',
      updatedAt: now.subtract(const Duration(days: 2)),
    ),

    // Squad
    ConversationCell(
      id: 'conv-squad-team',
      title: 'Work crew',
      avatar: '🔧',
      mode: TalkMode.squad,
      participants: const ['joe-p', 'sarah-k', 'mike-t'],
      turns: [
        ConversationTurn(from: 'sarah-k', body: 'Anyone near Newtown this arvo?', ts: now.subtract(const Duration(hours: 3))),
      ],
      context: const ConversationContext(),
      phase: 'active',
      updatedAt: now.subtract(const Duration(hours: 3)),
    ),
    ConversationCell(
      id: 'conv-squad-social',
      title: 'Da boyz',
      avatar: '🍺',
      mode: TalkMode.squad,
      participants: const ['rach', 'tom', 'lewis'],
      turns: [
        ConversationTurn(from: 'rach', body: 'Drinks Friday?', ts: now.subtract(const Duration(hours: 6))),
      ],
      context: const ConversationContext(),
      phase: 'open',
      updatedAt: now.subtract(const Duration(hours: 6)),
    ),
    ConversationCell(
      id: 'conv-squad-rea',
      title: 'REA channel',
      avatar: '🏢',
      mode: TalkMode.squad,
      participants: const ['rea-northside', 'rea-inner-west'],
      turns: [
        ConversationTurn(from: 'rea-northside', body: 'New job raised — see portal.', ts: now.subtract(const Duration(days: 1))),
      ],
      context: const ConversationContext(jobId: 'job-new-rea'),
      phase: 'open',
      updatedAt: now.subtract(const Duration(days: 1)),
    ),

    // Agent
    ConversationCell(
      id: 'conv-agent-semantos',
      title: 'Semantos',
      avatar: '⚡',
      mode: TalkMode.agent,
      participants: const ['agent:semantos'],
      turns: [],
      context: const ConversationContext(),
      phase: 'open',
      updatedAt: now,
    ),
    ConversationCell(
      id: 'conv-agent-llama',
      title: 'On-device Llama',
      avatar: '🦙',
      mode: TalkMode.agent,
      participants: const ['agent:llama-local'],
      turns: [
        ConversationTurn(from: 'agent:llama-local', body: 'Ready.', ts: now.subtract(const Duration(minutes: 5))),
      ],
      context: const ConversationContext(),
      phase: 'open',
      updatedAt: now.subtract(const Duration(minutes: 5)),
    ),
    ConversationCell(
      id: 'conv-agent-scheduler',
      title: 'Scheduler agent',
      avatar: '📅',
      mode: TalkMode.agent,
      participants: const ['agent:scheduler'],
      turns: [
        ConversationTurn(from: 'agent:scheduler', body: 'Visit on 14 May booked.', ts: now.subtract(const Duration(hours: 4))),
      ],
      context: const ConversationContext(visitId: 'visit-14may'),
      phase: 'open',
      updatedAt: now.subtract(const Duration(hours: 4)),
    ),

    // Broadcast
    ConversationCell(
      id: 'conv-bcast-status',
      title: 'Job status updates',
      avatar: '📢',
      mode: TalkMode.broadcast,
      participants: const [],
      turns: [
        ConversationTurn(from: 'self', body: 'Plumbing work at Newtown complete.', ts: now.subtract(const Duration(hours: 5))),
      ],
      context: const ConversationContext(jobId: 'job-wattle-st'),
      phase: 'open',
      updatedAt: now.subtract(const Duration(hours: 5)),
    ),
    ConversationCell(
      id: 'conv-bcast-invoices',
      title: 'Invoice announcements',
      avatar: '🧾',
      mode: TalkMode.broadcast,
      participants: const [],
      turns: [],
      context: const ConversationContext(),
      phase: 'open',
      updatedAt: now.subtract(const Duration(days: 3)),
    ),
    ConversationCell(
      id: 'conv-bcast-availability',
      title: 'Availability',
      avatar: '📆',
      mode: TalkMode.broadcast,
      participants: const [],
      turns: [
        ConversationTurn(from: 'self', body: 'Available next week — Mon/Wed/Fri.', ts: now.subtract(const Duration(days: 2))),
      ],
      context: const ConversationContext(),
      phase: 'open',
      updatedAt: now.subtract(const Duration(days: 2)),
    ),
  ];
}

```
