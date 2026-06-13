---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/cell_list_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.102808+00:00
---

# apps/semantos/lib/shell/cell_list_screen.dart

```dart
import 'package:flutter/material.dart';
import 'package:semantos_core/semantos_core.dart' show HelmUiVerbQuery;

import '../src/repositories/cell_query_repository.dart';
import '../src/rpc/brain_rpc_client.dart' show RpcCaller;

/// M1.8 — the GENERIC, manifest-driven cell-list renderer.
///
/// Runs `cell.query` for a FIND verb's [HelmUiVerbQuery] over the unified WSS
/// channel (via [CellQueryRepository]) and renders the rows as cards. Title /
/// subtitle come from the query's render hints (titleField / subtitleField),
/// falling back to the first non-id stringy field. One screen serves every
/// cartridge + cellType — the anti-circling seam: no per-type read UI.
class CellListScreen extends StatefulWidget {
  const CellListScreen({super.key, required this.rpc, required this.query});

  final RpcCaller rpc;
  final HelmUiVerbQuery query;

  @override
  State<CellListScreen> createState() => _CellListScreenState();
}

class _CellListScreenState extends State<CellListScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() => CellQueryRepository(widget.rpc)
      .list(widget.query.typeHash, filter: widget.query.filter);

  Future<void> _refresh() async {
    final f = _load();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.query;
    final title = q.collectionTitle.isNotEmpty ? q.collectionTitle : q.typeHash;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorState(error: snap.error.toString(), onRetry: _refresh);
          }
          final rows = snap.data ?? const [];
          if (rows.isEmpty) return _EmptyState(title: title, onRefresh: _refresh);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              itemCount: rows.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _CellCard(row: rows[i], query: q),
            ),
          );
        },
      ),
    );
  }
}

/// One generic cell card. Title/subtitle resolved from the query render hints,
/// with a sensible fallback so an un-hinted type still shows something useful.
class _CellCard extends StatelessWidget {
  const _CellCard({required this.row, required this.query});

  final Map<String, dynamic> row;
  final HelmUiVerbQuery query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _field(row, query.titleField) ?? _firstStringy(row) ?? '(cell)';
    final subtitle = _field(row, query.subtitleField);
    final id = (row['cellId'] ?? row['id'])?.toString();
    return ListTile(
      leading: const Icon(Icons.description_outlined),
      title: Text(title),
      subtitle: subtitle != null && subtitle.isNotEmpty
          ? Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis)
          : null,
      trailing: id != null
          ? Text(
              id.length > 8 ? '${id.substring(0, 8)}…' : id,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            )
          : null,
    );
  }

  static String? _field(Map<String, dynamic> row, String? key) {
    if (key == null) return null;
    final v = row[key];
    return v?.toString();
  }

  /// First non-empty string value that isn't an identifier — a reasonable
  /// title when the manifest declared no titleField.
  static String? _firstStringy(Map<String, dynamic> row) {
    const skip = {'id', 'cellId', 'cellType', 'cartridgeId'};
    for (final e in row.entries) {
      if (skip.contains(e.key)) continue;
      if (e.value is String && (e.value as String).isNotEmpty) {
        return e.value as String;
      }
    }
    return null;
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.onRefresh});

  final String title;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Wrap in a scroll view so RefreshIndicator works even when empty.
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.inbox_outlined,
              size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Center(
            child: Text('No $title yet.', style: theme.textTheme.titleMedium),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text('Pull to refresh.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 40, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('Query failed', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(error,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

```
