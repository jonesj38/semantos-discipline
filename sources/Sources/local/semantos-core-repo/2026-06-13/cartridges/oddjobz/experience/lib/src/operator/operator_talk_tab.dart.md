---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/operator_talk_tab.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.463506+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/operator_talk_tab.dart

```dart
import 'package:flutter/material.dart';

import 'operator_jobs_repository.dart';
import 'oddjobz_rpc.dart';

/// The 5 conversation modes (self → direct → squad → agent → broadcast).
enum TalkMode {
  self('Self', Icons.sticky_note_2_outlined),
  direct('Direct', Icons.person_outline),
  squad('Squad', Icons.groups_outlined),
  agent('Agent', Icons.smart_toy_outlined),
  broadcast('Broadcast', Icons.campaign_outlined);

  const TalkMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Talk — conversations by mode. The 5-mode strip selects a persistent
/// conversation space; each shows its windows. (Direct lists the operator's
/// contacts as 1:1 threads; the other modes' window caches wire in next.)
class OperatorTalkTab extends StatefulWidget {
  const OperatorTalkTab({super.key, required this.rpc});
  final OddjobzRpc rpc;

  @override
  State<OperatorTalkTab> createState() => _OperatorTalkTabState();
}

class _OperatorTalkTabState extends State<OperatorTalkTab>
    with AutomaticKeepAliveClientMixin {
  TalkMode _mode = TalkMode.direct;
  late final OperatorJobsRepository _repo = OperatorJobsRepository(widget.rpc);
  Future<List<Map<String, dynamic>>>? _contacts;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _contacts = _repo.findEntities('customers');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _ModeStrip(mode: _mode, onChanged: (m) => setState(() => _mode = m)),
        const Divider(height: 1),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    switch (_mode) {
      case TalkMode.direct:
        return _DirectList(future: _contacts!);
      case TalkMode.self:
        return const _ModeEmpty(
          icon: Icons.sticky_note_2_outlined,
          text: 'Your private notes & journal.\nStart by tapping the mic.',
        );
      case TalkMode.squad:
        return const _ModeEmpty(
          icon: Icons.groups_outlined,
          text: 'No squad channels yet.',
        );
      case TalkMode.agent:
        return const _ModeEmpty(
          icon: Icons.smart_toy_outlined,
          text: 'Chat with your brain / on-device agent.',
        );
      case TalkMode.broadcast:
        return const _ModeEmpty(
          icon: Icons.campaign_outlined,
          text: 'No broadcasts yet.',
        );
    }
  }
}

class _ModeStrip extends StatelessWidget {
  const _ModeStrip({required this.mode, required this.onChanged});
  final TalkMode mode;
  final ValueChanged<TalkMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          for (final m in TalkMode.values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                avatar: Icon(
                  m.icon,
                  size: 18,
                  color: m == mode
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                ),
                label: Text(m.label),
                selected: m == mode,
                onSelected: (_) => onChanged(m),
              ),
            ),
        ],
      ),
    );
  }
}

class _DirectList extends StatelessWidget {
  const _DirectList({required this.future});
  final Future<List<Map<String, dynamic>>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snap.data ?? const [];
        if (rows.isEmpty) {
          return const _ModeEmpty(
            icon: Icons.person_outline,
            text: 'No contacts yet.',
          );
        }
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final r = rows[i];
            final name = (r['display_name'] ?? '(unknown)').toString();
            final phone = (r['phone'] ?? '').toString();
            return ListTile(
              leading: CircleAvatar(child: Text(_initials(name))),
              title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: phone.isEmpty ? null : Text(phone),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Direct thread with $name — composer coming next',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              ),
            );
          },
        );
      },
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _ModeEmpty extends StatelessWidget {
  const _ModeEmpty({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

```
