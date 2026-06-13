---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/conversation_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.887973+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/conversation_screen.dart

```dart
// Talk surface — ConversationScreen.
//
// Cell viewer + turn composer for a single ConversationCell.
// Pushed as a modal route from TalkNode when a window card is tapped.
//
// Layout:
//   AppBar  — title (cell.title), subtitle (linked entity context if any)
//   Turn list (Expanded, reversed so newest is at bottom)
//   Compose bar — text field + send button (+ mic FAB for voice turns)
//
// Sending a turn:
//   New turns go to the outbox as an 'oddjobz.conversation.append.v1'
//   patch.  The optimistic local append is immediate; the brain confirms
//   via EventSubscriptionService write-through.  For agent windows the
//   turn body also goes to the SirExtractor / TalkNode's onMicTap path
//   so voice commands work from within the conversation.

import 'package:flutter/material.dart';
import '../talk/conversation_cell.dart';

/// Called when the user submits a new turn body.  Returns null on
/// success or an error string to show in a snackbar.
typedef TurnSubmitCallback = Future<String?> Function(
    ConversationCell cell, String body);

class ConversationScreen extends StatefulWidget {
  final ConversationCell cell;

  /// Null → send button is disabled (read-only view, e.g. broadcast archive).
  final TurnSubmitCallback? onSendTurn;

  const ConversationScreen({
    super.key,
    required this.cell,
    this.onSendTurn,
  });

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  // Local optimistic turns appended before server confirmation.
  final List<ConversationTurn> _optimistic = [];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<ConversationTurn> get _allTurns =>
      [...widget.cell.turns, ..._optimistic];

  Future<void> _send() async {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    final cb = widget.onSendTurn;
    if (cb == null) return;

    final turn = ConversationTurn(
      from: 'self',
      body: body,
      ts: DateTime.now(),
    );

    setState(() {
      _sending = true;
      _optimistic.add(turn);
      _controller.clear();
    });

    _scrollToBottom();

    final err = await cb(widget.cell, body);
    if (!mounted) return;
    setState(() => _sending = false);
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cell = widget.cell;
    final turns = _allTurns;
    final canSend = widget.onSendTurn != null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            // Avatar
            _Avatar(avatar: cell.avatar, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cell.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (cell.context.hasContext)
                    Text(
                      '${cell.context.primaryLabel} · ${cell.context.primaryRef ?? ''}',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.55)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Turn list ─────────────────────────────────────────────
          Expanded(
            child: turns.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet',
                      style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.4),
                          fontStyle: FontStyle.italic),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: turns.length,
                    itemBuilder: (ctx, i) =>
                        _TurnBubble(turn: turns[i]),
                  ),
          ),

          // ── Compose bar ───────────────────────────────────────────
          if (canSend)
            _ComposeBar(
              controller: _controller,
              sending: _sending,
              onSend: _send,
            ),
        ],
      ),
    );
  }
}

// ── Turn bubble ───────────────────────────────────────────────────────────

class _TurnBubble extends StatelessWidget {
  final ConversationTurn turn;
  const _TurnBubble({required this.turn});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isSelf = turn.from == 'self';
    final h = turn.ts.hour.toString().padLeft(2, '0');
    final m = turn.ts.minute.toString().padLeft(2, '0');
    final timeStr = '$h:$m';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isSelf ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isSelf) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: cs.surfaceContainerHighest,
              child: Text(
                turn.from.isNotEmpty
                    ? turn.from[0].toUpperCase()
                    : '?',
                style: TextStyle(
                    fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isSelf
                    ? cs.primary
                    : cs.surfaceContainerHigh,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft:
                      Radius.circular(isSelf ? 16 : 4),
                  bottomRight:
                      Radius.circular(isSelf ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    turn.body,
                    style: TextStyle(
                      fontSize: 14,
                      color:
                          isSelf ? cs.onPrimary : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelf
                          ? cs.onPrimary.withValues(alpha: 0.65)
                          : cs.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isSelf) const SizedBox(width: 6),
        ],
      ),
    );
  }
}

// ── Compose bar ───────────────────────────────────────────────────────────

class _ComposeBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _ComposeBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Message…',
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  filled: true,
                  fillColor: cs.surfaceContainerHigh,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: sending
                  ? Padding(
                      padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.primary),
                    )
                  : IconButton.filled(
                      onPressed: onSend,
                      icon: const Icon(Icons.send_rounded, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String avatar;
  final double size;
  const _Avatar({required this.avatar, required this.size});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Emoji avatar (length > 2 or contains non-ASCII) → text directly.
    final isEmoji = avatar.runes.any((r) => r > 127);
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: cs.surfaceContainerHighest,
      child: Text(
        avatar.isEmpty ? '?' : avatar,
        style: TextStyle(
          fontSize: isEmoji ? size * 0.5 : size * 0.38,
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

```
