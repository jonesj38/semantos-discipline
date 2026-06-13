---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/talk/talk_surface_service.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.864209+00:00
---

# archive/apps-semantos-monolith/lib/src/talk/talk_surface_service.dart

```dart
// Talk surface — TalkSurfaceService.
//
// Ranks ConversationCells into the top-3 windows for each TalkMode.
//
// Ranking signal (composite score, 0.0–1.0):
//
//   recency          — how recently the cell was updated, decaying over 24h
//   attentionScore   — injected from AttentionService.signals by matching
//                      the cell's context.primaryRef to a signal's ref
//   timeContext      — squad routing: work team scores higher Mon–Fri 08–18,
//                      social group scores higher outside those hours
//   unread           — whether the last turn is from someone other than 'self'
//
// The service listens to the AttentionService signals stream and re-ranks
// whenever attention changes.  HatEntityRepository.queryConversations()
// provides the cell list; currently backed by stubs until the brain-side
// conversation cell FSM is wired.
//
// Usage:
//   final svc = TalkSurfaceService(attention: myAttentionService);
//   svc.windowsFor(TalkMode.direct) // → List<ConversationCell> (≤ 3)
//   svc.stream                      // → Stream<void> (fires on re-rank)

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../contacts/contacts_repository.dart';
import '../repl/attention_service.dart';
import '../repl/hat_context.dart';
import '../repl/hat_entity_repository.dart';
import 'conversation_cell.dart';

const int kWindowsPerMode = 3;

// Work-hours band for squad time-routing.
const int _kWorkHourStart = 8;
const int _kWorkHourEnd   = 18;

class TalkSurfaceService {
  // ignore: unused_field — retained for future startPolling() integration
  final AttentionService? _attention;
  final HatEntityRepository? _repo;
  final ContactsRepository? _contacts;
  final HatContext _hat;

  // All cells, refreshed on each rebuild.
  List<ConversationCell> _cells = const [];

  // Ranked top-3 per mode, keyed by mode index.
  final Map<TalkMode, List<ConversationCell>> _windows = {};

  // Broadcast stream — fires whenever windows are recomputed.
  final StreamController<void> _ctl =
      StreamController<void>.broadcast();

  StreamSubscription<List<OddjobzAttentionSignal>>? _attentionSub;
  bool _disposed = false;

  TalkSurfaceService({
    required HatContext hat,
    AttentionService? attention,
    HatEntityRepository? repo,
    ContactsRepository? contacts,
  })  : _hat = hat,
        _attention = attention,
        _repo = repo,
        _contacts = contacts {
    // Seed with stubs immediately so TalkNode renders on first frame.
    _cells = stubConversationCells();
    _rank(signals: const []);

    if (attention != null) {
      _attentionSub = attention.signals.listen(_onSignals);
    }
  }

  // ── Public API ────────────────────────────────────────────────────────

  /// Top-3 ranked ConversationCells for [mode].
  List<ConversationCell> windowsFor(TalkMode mode) =>
      _windows[mode] ?? const [];

  /// Returns ALL cells for [mode] (no top-3 cap), optionally filtered by
  /// [query] across title + lastTurnPreview. Sorted by updatedAt DESC.
  List<ConversationCell> allFor(TalkMode mode, {String? query}) {
    var result = _cells
        .where((c) => c.mode == mode && c.phase != 'archived')
        .toList();

    final q = query?.trim().toLowerCase();
    if (q != null && q.isNotEmpty) {
      result = result.where((c) {
        final titleMatch = c.title.toLowerCase().contains(q);
        final previewMatch = c.lastTurnPreview.toLowerCase().contains(q);
        return titleMatch || previewMatch;
      }).toList();
    }

    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  /// Returns the existing job-linked conversation for [jobId], or creates
  /// one with [TalkMode.direct] if none exists yet.
  Future<ConversationCell> findOrCreateJobConversation({
    required String jobId,
    String jobTitle = '',
  }) async {
    final existing = _cells.where(
      (c) => c.context.jobId == jobId,
    );
    if (existing.isNotEmpty) return existing.first;

    return createConversation(
      title:   jobTitle.isEmpty ? 'Job $jobId' : jobTitle,
      mode:    TalkMode.direct,
      context: ConversationContext(jobId: jobId),
    );
  }

  /// Creates a new conversation cell locally (writes to _repo), adds to
  /// _cells, re-ranks, and returns the new cell.
  Future<ConversationCell> createConversation({
    required String title,
    required TalkMode mode,
    List<String> participants = const [],
    String? contactCertId,
    ConversationContext context = const ConversationContext(),
  }) async {
    final now = DateTime.now();
    final id = 'conv-${mode.name}-${now.millisecondsSinceEpoch}';

    // Compute avatar as initials.
    final words = title.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final String avatar;
    if (words.isEmpty) {
      avatar = '?';
    } else if (words.length == 1) {
      avatar = words[0][0].toUpperCase();
    } else {
      avatar = (words.first[0] + words.last[0]).toUpperCase();
    }

    final cell = ConversationCell(
      id: id,
      title: title,
      avatar: avatar,
      mode: mode,
      participants: participants,
      contactCertId: contactCertId,
      turns: const [],
      context: context,
      phase: 'open',
      updatedAt: now,
    );

    final repo = _repo;
    if (repo != null) {
      final entity = HatEntity(
        id: id,
        domainFlag: _hat.domainFlag,
        state: 'open',
        scheduledAt: '',
        entityJson: cell.toEntityJson(),
        updatedAt: now.toUtc().toIso8601String(),
      );
      await repo.upsert(entity);
    }

    _cells = [..._cells, cell];
    _rank(signals: const []);

    return cell;
  }

  /// Fires whenever the windows are recomputed (attention update,
  /// repo refresh, time-context shift).
  Stream<void> get stream => _ctl.stream;

  /// Force a full refresh from [HatEntityRepository] + re-rank.
  Future<void> refresh() async {
    await _loadFromRepo();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _attentionSub?.cancel();
    if (!_ctl.isClosed) _ctl.close();
  }

  // ── Internal ──────────────────────────────────────────────────────────

  void _onSignals(List<OddjobzAttentionSignal> signals) {
    _rank(signals: signals);
  }

  Future<void> _loadFromRepo() async {
    final repo = _repo;
    if (repo != null) {
      try {
        final entities = await repo.queryConversations(domainFlag: _hat.domainFlag);
        _cells = entities.map((e) => ConversationCell.fromEntityJson(
              e.entityJson,
              id: e.id,
              updatedAt: DateTime.tryParse(e.updatedAt),
            )).toList();
      } catch (e) {
        debugPrint('[TalkSurface] queryConversations error: $e');
        // Keep stubs on error so UI doesn't go blank.
      }
    }
    await _mergeContacts();
    _rank(signals: const []);
  }

  /// Merges connected Plexus contacts into _cells as Direct-mode windows.
  /// Skips contacts already represented by an entity-sourced cell that has
  /// the same contactCertId (avoids duplicates when the brain writes a real
  /// ConversationCell for the same contact later).
  Future<void> _mergeContacts() async {
    final contacts = _contacts;
    if (contacts == null) return;
    try {
      final connected = await contacts.listConnectedContacts();
      if (connected.isEmpty) return;

      final existingCertIds = _cells
          .where((c) => c.contactCertId != null)
          .map((c) => c.contactCertId!)
          .toSet();

      final toAdd = connected
          .where((c) => !existingCertIds.contains(c.certId))
          .map((c) => ConversationCell(
                id:            'conv-direct-${c.certId}',
                title:         c.displayName,
                avatar:        c.initials,
                mode:          TalkMode.direct,
                participants:  [c.certId],
                contactCertId: c.certId,
                turns:         const [],
                context:       const ConversationContext(),
                phase:         'open',
                updatedAt:     DateTime.fromMillisecondsSinceEpoch(c.updatedAt),
              ))
          .toList();

      if (toAdd.isNotEmpty) {
        _cells = [..._cells, ...toAdd];
      }
    } catch (e) {
      debugPrint('[TalkSurface] _mergeContacts error: $e');
    }
  }

  void _rank({required List<OddjobzAttentionSignal> signals}) {
    // Build a ref → score map from attention signals for quick lookup.
    final attentionByRef = <String, double>{};
    for (final s in signals) {
      if (s.ref.isNotEmpty) {
        final existing = attentionByRef[s.ref] ?? 0.0;
        if (s.score > existing) attentionByRef[s.ref] = s.score;
      }
    }

    final now = DateTime.now();

    for (final mode in TalkMode.values) {
      final forMode = _cells
          .where((c) => c.mode == mode && c.phase != 'archived')
          .map((c) {
            final attScore = _attentionScoreFor(c, attentionByRef);
            return c.copyWith(attentionScore: attScore);
          })
          .toList();

      forMode.sort((a, b) {
        final sa = _compositeScore(a, now);
        final sb = _compositeScore(b, now);
        return sb.compareTo(sa); // descending
      });

      _windows[mode] = forMode.take(kWindowsPerMode).toList();
    }

    if (!_disposed && !_ctl.isClosed) _ctl.add(null);
  }

  double _attentionScoreFor(
    ConversationCell c,
    Map<String, double> attentionByRef,
  ) {
    final ref = c.context.primaryRef;
    if (ref == null) return c.attentionScore;
    return attentionByRef[ref] ?? c.attentionScore;
  }

  double _compositeScore(ConversationCell c, DateTime now) {
    // 1. Recency: linear decay over 24 hours → 0.0 at 24h+
    final ageMins = now.difference(c.updatedAt).inMinutes.clamp(0, 1440);
    final recency = 1.0 - (ageMins / 1440.0);

    // 2. Attention score from the signal surface.
    final attention = c.attentionScore;

    // 3. Unread: last turn is from someone else.
    final unread =
        (c.lastTurn != null && c.lastTurn!.from != 'self') ? 1.0 : 0.0;

    // 4. Time-context weight for squad.
    final timeWeight = c.mode == TalkMode.squad
        ? _squadTimeWeight(c, now)
        : 1.0;

    // Weights: attention > unread > recency, all scaled by timeWeight.
    final raw = (attention * 0.45) + (unread * 0.30) + (recency * 0.25);
    return (raw * timeWeight).clamp(0.0, 1.0);
  }

  /// Returns a weight [0.3, 1.0] for squad cells based on time-of-day.
  /// Work cells score higher Mon–Fri 08–18; social cells score higher
  /// outside those hours (evenings, weekends).
  double _squadTimeWeight(ConversationCell c, DateTime now) {
    final isWorkHours = now.weekday <= DateTime.friday &&
        now.hour >= _kWorkHourStart &&
        now.hour < _kWorkHourEnd;

    final isWorkGroup = c.participants.any((p) =>
        p.startsWith('rea-') ||
        p.startsWith('tradesperson-') ||
        c.title.toLowerCase().contains('work') ||
        c.title.toLowerCase().contains('crew') ||
        c.title.toLowerCase().contains('team'));

    if (isWorkGroup && isWorkHours) return 1.0;
    if (!isWorkGroup && !isWorkHours) return 1.0;
    // Mismatched context — still show but deprioritised.
    return 0.3;
  }
}

```
