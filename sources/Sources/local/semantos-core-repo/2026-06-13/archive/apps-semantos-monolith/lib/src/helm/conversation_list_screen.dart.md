---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/conversation_list_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.894758+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/conversation_list_screen.dart

```dart
// Helm — ConversationListScreen.
//
// Full list of ConversationCells for a given TalkMode with search and
// a FAB to create a new conversation.  Opened from TalkNode via
// "See all →" or from the text tray command interceptor.

import 'dart:async';

import 'package:flutter/material.dart';

import '../talk/conversation_cell.dart';
import '../talk/talk_surface_service.dart';
import 'conversation_screen.dart';

class ConversationListScreen extends StatefulWidget {
  final TalkSurfaceService talkSurface;
  final TalkMode mode;
  final String? initialQuery;
  final Future<String?> Function(ConversationCell cell, String body) onSendTurn;

  const ConversationListScreen({
    super.key,
    required this.talkSurface,
    required this.mode,
    this.initialQuery,
    required this.onSendTurn,
  });

  @override
  State<ConversationListScreen> createState() => _ConversationListScreenState();
}

class _ConversationListScreenState extends State<ConversationListScreen> {
  late final TextEditingController _searchCtl;
  StreamSubscription<void>? _sub;
  List<ConversationCell> _cells = const [];

  @override
  void initState() {
    super.initState();
    _searchCtl = TextEditingController(text: widget.initialQuery ?? '');
    _searchCtl.addListener(_rebuild);
    _sub = widget.talkSurface.stream.listen((_) => _rebuild());
    _rebuild();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _searchCtl.removeListener(_rebuild);
    _searchCtl.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (!mounted) return;
    setState(() {
      _cells = widget.talkSurface.allFor(
        widget.mode,
        query: _searchCtl.text.trim(),
      );
    });
  }

  void _openConversation(ConversationCell cell) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ConversationScreen(
          cell: cell,
          onSendTurn: widget.onSendTurn,
        ),
      ),
    );
  }

  Future<void> _showNewConversationDialog() async {
    final titleCtl = TextEditingController();
    final participantsCtl = TextEditingController();
    final isSquad = widget.mode == TalkMode.squad;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New ${widget.mode.label} conversation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Conversation name',
              ),
            ),
            if (isSquad) ...[
              const SizedBox(height: 12),
              TextField(
                controller: participantsCtl,
                decoration: const InputDecoration(
                  labelText: 'Participants',
                  hintText: 'Comma-separated names',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final title = titleCtl.text.trim();
    if (title.isEmpty) return;

    final List<String> participants;
    if (isSquad && participantsCtl.text.trim().isNotEmpty) {
      participants = participantsCtl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } else {
      participants = const [];
    }

    final cell = await widget.talkSurface.createConversation(
      title: title,
      mode: widget.mode,
      participants: participants,
    );

    if (mounted) _openConversation(cell);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mode.label),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtl,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search ${widget.mode.label.toLowerCase()} conversations…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(
            child: _cells.isEmpty
                ? Center(
                    child: Text(
                      'No ${widget.mode.label.toLowerCase()} conversations found',
                      style: TextStyle(
                        fontSize: 14,
                        color: cs.onSurface.withValues(alpha: 0.4),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _cells.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final cell = _cells[i];
                      final last = cell.lastTurn;
                      final isUnread = last != null && last.from != 'self';
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cs.surfaceContainerHighest,
                          child: Text(
                            cell.avatar.isEmpty ? '?' : cell.avatar,
                            style: TextStyle(
                              fontSize: cell.avatar.runes.any((r) => r > 127)
                                  ? 16
                                  : 13,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        title: Text(
                          cell.title,
                          style: TextStyle(
                            fontWeight: isUnread
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: cell.lastTurnPreview.isNotEmpty
                            ? Text(
                                cell.lastTurnPreview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )
                            : null,
                        trailing: last != null
                            ? Text(
                                _relativeTime(last.ts),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isUnread
                                      ? cs.primary
                                      : cs.onSurface.withValues(alpha: 0.45),
                                ),
                              )
                            : null,
                        onTap: () => _openConversation(cell),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewConversationDialog,
        tooltip: 'New conversation',
        child: const Icon(Icons.add),
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

```
