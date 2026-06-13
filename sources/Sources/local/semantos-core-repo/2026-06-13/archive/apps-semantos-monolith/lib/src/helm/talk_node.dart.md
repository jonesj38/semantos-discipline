---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/talk_node.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.891963+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/talk_node.dart

```dart
// Helm v8 — TalkNode: 5-mode conversation surface.
//
// Replaces the single mic-FAB + feedback area with a structured
// 1-3-5-3-1 conscious stack:
//
//   5-mode strip (Self / Direct / Squad / Agent / Broadcast)
//     → 3 contextually-ranked ConversationWindowCards per mode
//       → ConversationScreen on tap
//
// The existing voice pipeline (mic FAB + VoiceTextInputBar) is
// preserved below the window cards so operators can still issue
// voice/text commands from the Talk surface.  Model download cards
// appear above the mode strip when models aren't cached.
//
// TalkSurfaceService provides the ranked windows; it is constructed
// in HomeScreen and passed in so it shares the AttentionService
// singleton.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:whisper_cpp/whisper_cpp.dart';

import '../repl/conversation_send_api.dart';
import '../repl/repl_client.dart';
import '../repl/repl_errors.dart';
import '../repl/search_contacts_api.dart';
import '../talk/conversation_cell.dart';
import '../talk/talk_surface_service.dart';
import '../voice/on_device_voice_factory.dart';
import '../voice/text_intent_service.dart';
import 'conversation_list_screen.dart';
import 'conversation_screen.dart';
import 'talk_direct_search_screen.dart';
// VoiceMicHandler typedef lives in voice_text_input_bar.dart — kept for
// the onMicTap callback signature even though the input bar widget
// itself was retired in favour of the single big mic FAB below.
import 'voice_text_input_bar.dart' show VoiceMicHandler;

class TalkNode extends StatefulWidget {
  final TextIntentService textService;
  final VoiceMicHandler? onMicTap;
  final OnDeviceVoiceFactory? voiceFactory;

  /// Ranked conversation windows.  When null the node renders without
  /// the 5-mode surface (dev harness / test rigs).
  final TalkSurfaceService? talkSurface;

  /// W6 of CUSTOMER-CONV-LOOP-PLAN — pair of APIs that drives the
  /// search-by-name/address surface for Direct mode.  When both
  /// non-null, the Direct mode header shows a "Search contacts" CTA
  /// that opens TalkDirectSearchScreen.
  final SearchContactsApi? searchContactsApi;
  final ConversationSendApi? conversationSendApi;

  /// W-CONV-1 — REPL client used to persist operator turns to the brain.
  /// When non-null, [_sendTurn] POSTs the operator's text to
  /// `POST /api/v1/repl`.  The brain's `--enable-intent-action-router`
  /// flag routes the command through the intent pipeline, which triggers
  /// FSM transitions on the relevant job/entity.  Without this, typed
  /// notes show locally (optimistic) but are lost on navigation.
  final ReplClient? replClient;

  const TalkNode({
    super.key,
    required this.textService,
    this.onMicTap,
    this.voiceFactory,
    this.talkSurface,
    this.searchContactsApi,
    this.conversationSendApi,
    this.replClient,
  });

  @override
  State<TalkNode> createState() => _TalkNodeState();
}

// ── Per-model download state ──────────────────────────────────────────────

enum _ModelStatus { checking, cached, absent, downloading, failed }

class _ModelState {
  _ModelStatus status;
  double? fraction;
  String? errorMessage;
  _ModelState()
      : status = _ModelStatus.checking,
        fraction = null,
        errorMessage = null;
}

// ── State ─────────────────────────────────────────────────────────────────

class _TalkNodeState extends State<TalkNode>
    with SingleTickerProviderStateMixin {
  // Mode strip
  TalkMode _activeMode = TalkMode.direct;

  // Windows from TalkSurfaceService
  List<ConversationCell> _windows = const [];
  StreamSubscription<void>? _surfaceSub;

  // Voice feedback
  String? _lastFeedback;
  bool _feedbackVisible = false;
  late final AnimationController _fadeCtl;
  late final Animation<double> _fadeAnim;

  // Model state (Whisper only — llama removed, SIR uses Anthropic)
  final _whisper = _ModelState();

  @override
  void initState() {
    super.initState();
    _fadeCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtl, curve: Curves.easeIn);
    _checkModels();
    _bindSurface(widget.talkSurface);
  }

  @override
  void didUpdateWidget(TalkNode old) {
    super.didUpdateWidget(old);
    if (old.voiceFactory == null && widget.voiceFactory != null) {
      _checkModels();
    }
    if (old.talkSurface != widget.talkSurface) {
      _surfaceSub?.cancel();
      _bindSurface(widget.talkSurface);
    }
  }

  void _bindSurface(TalkSurfaceService? svc) {
    if (svc == null) return;
    _updateWindows(svc);
    _surfaceSub = svc.stream.listen((_) {
      if (mounted) _updateWindows(svc);
    });
  }

  void _updateWindows(TalkSurfaceService svc) {
    setState(() => _windows = svc.windowsFor(_activeMode));
  }

  void _onModeSelected(TalkMode mode) {
    setState(() {
      _activeMode = mode;
      _windows = widget.talkSurface?.windowsFor(mode) ?? const [];
    });
  }

  @override
  void dispose() {
    _surfaceSub?.cancel();
    _fadeCtl.dispose();
    super.dispose();
  }

  // ── Model checks + downloads (unchanged from v7) ──────────────────

  Future<void> _checkModels() async {
    final factory = widget.voiceFactory;
    if (factory == null) return;
    final wCached = await factory.isWhisperModelCached();
    if (!mounted) return;
    setState(() {
      _whisper.status =
          wCached ? _ModelStatus.cached : _ModelStatus.absent;
    });
  }

  Future<void> _downloadWhisper() async {
    final factory = widget.voiceFactory;
    if (factory == null) return;
    setState(() {
      _whisper.status = _ModelStatus.downloading;
      _whisper.fraction = null;
      _whisper.errorMessage = null;
    });
    try {
      final ok = await factory.ensureWhisperModel(
        onProgress: (WhisperModelDownloadProgress p) {
          if (!mounted) return;
          setState(() => _whisper.fraction = p.fraction);
        },
      );
      if (!mounted) return;
      setState(() {
        _whisper.status =
            ok ? _ModelStatus.cached : _ModelStatus.failed;
        if (!ok) _whisper.errorMessage = 'Download failed — tap to retry';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _whisper.status = _ModelStatus.failed;
        _whisper.errorMessage = e.toString();
      });
    }
  }

  // ── Mic handler ───────────────────────────────────────────────────

  Future<void> _onMicTap() async {
    final handler = widget.onMicTap;
    if (handler == null) return;
    final outcome = await handler(context);
    if (!mounted) return;
    if (outcome != null) {
      final msg = outcome.success
          ? (outcome.summary ?? 'Command sent.')
          : '${outcome.refusalStage ?? 'refused'}: ${outcome.refusalReason ?? ''}';
      _showFeedback(msg);
    }
  }

  void _showFeedback(String msg) {
    setState(() {
      _lastFeedback = msg;
      _feedbackVisible = true;
    });
    _fadeCtl.forward(from: 0.0);
  }

  bool get _whisperReady => _whisper.status == _ModelStatus.cached;
  bool get _micEnabled =>
      widget.onMicTap != null && _whisperReady;

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final showWhisperCard = widget.voiceFactory != null &&
        _whisper.status != _ModelStatus.cached &&
        _whisper.status != _ModelStatus.checking;

    return Column(
      children: [
        // ── Model download card (Whisper only — llama removed) ────
        if (showWhisperCard)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _ModelDownloadCard(
              icon: Icons.mic,
              title: 'Voice model',
              subtitle: 'whisper.base.en · 141 MB · required for mic',
              state: _whisper,
              onDownload: _downloadWhisper,
            ),
          ),

        // ── 5-mode strip ──────────────────────────────────────────
        if (widget.talkSurface != null) ...[
          _ModeStrip(
            activeMode: _activeMode,
            onSelected: _onModeSelected,
          ),
          const Divider(height: 1),
        ],

        // ── Per-mode search CTA ──────────────────────────────────
        // Every mode gets a top-of-list search row so the operator has
        // muscle-memory consistency.  Direct mode keeps its specialised
        // contact-search screen (PKI-aware: name / address / suburb);
        // every other mode opens ConversationListScreen with the mode
        // pre-filtered and the search input focused.
        if (widget.talkSurface != null) ...[
          _ModeSearchCta(
            mode: _activeMode,
            onTapDirect:
                (widget.searchContactsApi != null &&
                        widget.conversationSendApi != null)
                    ? () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TalkDirectSearchScreen(
                            searchApi: widget.searchContactsApi!,
                            sendApi: widget.conversationSendApi!,
                          ),
                        ))
                    : null,
            onTapOther: () => _openConversationList(initialQuery: ''),
          ),
          const Divider(height: 1),
        ],

        // ── Window cards (3 per mode) or voice feedback ───────────
        Expanded(
          child: widget.talkSurface != null
              ? _WindowList(
                  windows: _windows,
                  activeMode: _activeMode,
                  onTap: _openConversation,
                  onSeeAll: () => _openConversationList(),
                )
              : _VoiceFeedback(
                  visible: _feedbackVisible,
                  feedback: _lastFeedback,
                  fadeAnim: _fadeAnim,
                  whisperReady: _whisperReady,
                ),
        ),

        // ── Big mic — single voice-first affordance ─────────────────
        // The old "Speak or type a command…" text field + mic + send
        // icons was three things competing for attention.  Voice-first
        // direction: one large mic button that opens the voice command
        // sheet (Whisper → intent extractor → action dispatch).  Typing
        // commands is still possible via the per-conversation thread
        // composers (job-thread footer, etc.) — the Talk surface is for
        // VOICE.
        if (widget.onMicTap != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Center(
              child: SizedBox(
                width: 72,
                height: 72,
                child: FloatingActionButton(
                  heroTag: 'talk_node_main_mic_fab',
                  onPressed: _micEnabled ? _onMicTap : null,
                  backgroundColor:
                      _micEnabled ? cs.primary : cs.surfaceContainerHighest,
                  foregroundColor: _micEnabled
                      ? cs.onPrimary
                      : cs.onSurface.withValues(alpha: 0.4),
                  elevation: _micEnabled ? 4 : 1,
                  tooltip: _whisperReady
                      ? 'Tap to talk'
                      : 'Voice model downloading…',
                  child: Icon(Icons.mic, size: 36),
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openConversationList({String? initialQuery}) {
    final surface = widget.talkSurface;
    if (surface == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ConversationListScreen(
          talkSurface: surface,
          mode: _activeMode,
          initialQuery: initialQuery,
          onSendTurn: _sendTurn,
        ),
      ),
    );
  }

  Future<bool> _handleTalkCommand(String text) async {
    final surface = widget.talkSurface;
    if (surface == null) return false;
    final t = text.trim();

    // find / search → open list with query
    final findMatch =
        RegExp(r'^(find|search)\s+(.+)$', caseSensitive: false).firstMatch(t);
    if (findMatch != null) {
      _openConversationList(initialQuery: findMatch.group(2)?.trim());
      return true;
    }

    // start/new/create group with ... → new Squad cell
    final squadMatch = RegExp(
      r'^(start\s+(?:a\s+)?(?:new\s+)?group|new\s+group|create\s+(?:a\s+)?group)\s+(?:with\s+)?(.+)$',
      caseSensitive: false,
    ).firstMatch(t);
    if (squadMatch != null) {
      final raw = squadMatch.group(2) ?? '';
      final participants = raw
          .split(RegExp(r'\s+and\s+|,\s*'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final cell = await surface.createConversation(
        title: participants.join(', '),
        mode: TalkMode.squad,
        participants: participants,
      );
      if (mounted) _openConversation(cell);
      return true;
    }

    // message / dm <name> → new Direct cell
    final directMatch = RegExp(
      r'^(?:message|dm|direct)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(t);
    if (directMatch != null) {
      final name = (directMatch.group(1) ?? '').trim();
      if (name.isNotEmpty) {
        final cell = await surface.createConversation(
          title: name,
          mode: TalkMode.direct,
          participants: [name],
        );
        if (mounted) _openConversation(cell);
        return true;
      }
    }

    return false;
  }

  void _openConversation(ConversationCell cell) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          cell: cell,
          onSendTurn: _sendTurn,
        ),
      ),
    );
  }

  /// W-CONV-1 — persist an operator turn to the brain via REPL.
  ///
  /// Sends `POST /api/v1/repl {"cmd": body}` so the brain's intent
  /// pipeline runs the text and `--enable-intent-action-router` fires
  /// any matching FSM transitions on the relevant job/entity.
  ///
  /// Returns null on success (caller already appended optimistically).
  /// Surfaces a SnackBar on failure so the operator knows the note was
  /// not persisted.
  Future<String?> _sendTurn(ConversationCell cell, String body) async {
    final repl = widget.replClient;
    if (repl == null) {
      // REPL not wired — optimistic-only (old behaviour).
      return null;
    }
    try {
      await repl.send(body.trim());
    } on ReplUnauthorisedError {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Not authorised — please re-pair this device.')),
      );
    } on ReplError catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Note not saved: ${e.message}')),
      );
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Note not saved: $e')),
      );
    }
    return null;
  }
}

// ── 5-mode strip ──────────────────────────────────────────────────────────

class _ModeStrip extends StatelessWidget {
  final TalkMode activeMode;
  final ValueChanged<TalkMode> onSelected;

  const _ModeStrip({required this.activeMode, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: TalkMode.values.map((mode) {
          final active = mode == activeMode;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelected(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 0),
                decoration: BoxDecoration(
                  color: active
                      ? cs.primary
                      : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: Text(
                  mode.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? cs.onPrimary
                        : cs.onSurface.withValues(alpha: 0.75),
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Window list (3 cards) ─────────────────────────────────────────────────

class _WindowList extends StatelessWidget {
  final List<ConversationCell> windows;
  final TalkMode activeMode;
  final ValueChanged<ConversationCell> onTap;
  final VoidCallback? onSeeAll;

  const _WindowList({
    required this.windows,
    required this.activeMode,
    required this.onTap,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    final seeAllButton = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextButton(
        onPressed: onSeeAll,
        child: Text('See all ${activeMode.label.toLowerCase()} conversations →'),
      ),
    );

    if (windows.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No ${activeMode.label.toLowerCase()} conversations yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
          ),
          seeAllButton,
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            itemCount: windows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, i) => _WindowCard(
              cell: windows[i],
              onTap: onTap,
            ),
          ),
        ),
        seeAllButton,
      ],
    );
  }
}

// ── Window card ───────────────────────────────────────────────────────────

class _WindowCard extends StatelessWidget {
  final ConversationCell cell;
  final ValueChanged<ConversationCell> onTap;

  const _WindowCard({required this.cell, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final last = cell.lastTurn;
    final isUnread = last != null && last.from != 'self';
    final hasAttention = cell.attentionScore > 0.6;

    return Card(
      margin: EdgeInsets.zero,
      elevation: hasAttention ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: hasAttention
            ? BorderSide(color: cs.primary.withValues(alpha: 0.6), width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onTap(cell),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Avatar
              _CardAvatar(avatar: cell.avatar, unread: isUnread),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            cell.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: cs.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (last != null)
                          Text(
                            _relativeTime(last.ts),
                            style: TextStyle(
                              fontSize: 11,
                              color: isUnread
                                  ? cs.primary
                                  : cs.onSurface
                                      .withValues(alpha: 0.45),
                            ),
                          ),
                      ],
                    ),
                    if (cell.context.hasContext) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.link,
                              size: 11,
                              color: cs.onSurface.withValues(alpha: 0.4)),
                          const SizedBox(width: 3),
                          Text(
                            '${cell.context.primaryLabel}',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (cell.lastTurnPreview.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        cell.lastTurnPreview,
                        style: TextStyle(
                          fontSize: 13,
                          color: isUnread
                              ? cs.onSurface
                              : cs.onSurface.withValues(alpha: 0.55),
                          fontWeight: isUnread
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // Attention dot
              if (hasAttention) ...[
                const SizedBox(width: 8),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}

class _CardAvatar extends StatelessWidget {
  final String avatar;
  final bool unread;
  const _CardAvatar({required this.avatar, required this.unread});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEmoji = avatar.runes.any((r) => r > 127);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: cs.surfaceContainerHighest,
          child: Text(
            avatar.isEmpty ? '?' : avatar,
            style: TextStyle(
              fontSize: isEmoji ? 18 : 14,
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (unread)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
                border: Border.all(
                    color: cs.surface, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Voice feedback (classic mode — no talkSurface) ────────────────────────

class _VoiceFeedback extends StatelessWidget {
  final bool visible;
  final String? feedback;
  final Animation<double> fadeAnim;
  final bool whisperReady;

  const _VoiceFeedback({
    required this.visible,
    required this.feedback,
    required this.fadeAnim,
    required this.whisperReady,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: visible && feedback != null
            ? FadeTransition(
                opacity: fadeAnim,
                child: Card(
                  color: cs.surfaceContainerHigh,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      feedback!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16, color: cs.onSurface),
                    ),
                  ),
                ),
              )
            : Text(
                whisperReady
                    ? 'speak or type a command'
                    : 'download voice model to enable mic',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: cs.onSurface.withValues(alpha: 0.4),
                  fontStyle: FontStyle.italic,
                ),
              ),
      ),
    );
  }
}

// ── Model download card (unchanged from v7) ───────────────────────────────

class _ModelDownloadCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final _ModelState state;
  final VoidCallback onDownload;

  const _ModelDownloadCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.state,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final downloading = state.status == _ModelStatus.downloading;
    final failed = state.status == _ModelStatus.failed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  const SizedBox(height: 2),
                  Text(
                    failed
                        ? (state.errorMessage ?? 'Download failed — tap to retry')
                        : subtitle,
                    style: TextStyle(
                        fontSize: 11,
                        color:
                            failed ? cs.error : cs.onSurfaceVariant),
                  ),
                  if (downloading) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: state.fraction,
                      backgroundColor: cs.surfaceContainerHighest,
                      color: cs.primary,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    if (state.fraction != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${(state.fraction! * 100).toStringAsFixed(0)} %',
                          style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (downloading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: cs.primary),
              )
            else
              TextButton(
                onPressed: onDownload,
                style: TextButton.styleFrom(
                  foregroundColor: cs.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.06),
                ),
                child: Text(failed ? 'RETRY' : 'DOWNLOAD'),
              ),
          ],
        ),
      ),
    );
  }
}


/// Per-mode "Search…" CTA row shown above the windows list in
/// talk_node.dart.  Mirrors the original Direct-mode CTA but adapts the
/// hint text + tap target to whichever mode is active.  Direct routes
/// into TalkDirectSearchScreen (PKI contact search); every other mode
/// routes into ConversationListScreen with the mode pre-filtered.
class _ModeSearchCta extends StatelessWidget {
  const _ModeSearchCta({
    required this.mode,
    required this.onTapDirect,
    required this.onTapOther,
  });

  final TalkMode mode;
  final VoidCallback? onTapDirect;
  final VoidCallback onTapOther;

  String _hintFor(TalkMode m) {
    switch (m) {
      case TalkMode.self:
        return "Search your private notes…";
      case TalkMode.direct:
        return "Search contacts (name, address, suburb)…";
      case TalkMode.squad:
        return "Search squads + group chats…";
      case TalkMode.agent:
        return "Search agent conversations…";
      case TalkMode.broadcast:
        return "Search broadcasts…";
    }
  }

  @override
  Widget build(BuildContext context) {
    final onTap = mode == TalkMode.direct ? onTapDirect : onTapOther;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.search, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _hintFor(mode),
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

```
