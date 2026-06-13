---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/operator/operator_find_tab.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.465033+00:00
---

# cartridges/oddjobz/experience/lib/src/operator/operator_find_tab.dart

```dart
import 'package:flutter/material.dart';

import 'dart:convert';

import 'operator_jobs_repository.dart';
import 'oddjobz_visuals.dart';
import 'oddjobz_rpc.dart';
import 'operator_shell.dart' show JobRow;

/// Find — unified search across the operator's entity types: Jobs, Customers,
/// Visits, Quotes, Invoices. Jobs + Customers have live data; Visits/Quotes/
/// Invoices have no cell.query decoder on the brain yet and show that honestly.
class OperatorFindTab extends StatefulWidget {
  const OperatorFindTab({super.key, required this.rpc});
  final OddjobzRpc rpc;

  @override
  State<OperatorFindTab> createState() => _OperatorFindTabState();
}

class _OperatorFindTabState extends State<OperatorFindTab>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late final TabController _tabs = TabController(length: 5, vsync: this);

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Jobs'),
            Tab(text: 'Customers'),
            Tab(text: 'Visits'),
            Tab(text: 'Quotes'),
            Tab(text: 'Invoices'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _JobsSearch(rpc: widget.rpc),
              _CellSearch(
                rpc: widget.rpc,
                noun: 'customers',
                titleField: 'name',
                subtitleField: 'phone',
              ),
              _CellSearch(rpc: widget.rpc, noun: 'visits'),
              _CellSearch(rpc: widget.rpc, noun: 'quotes'),
              _CellSearch(rpc: widget.rpc, noun: 'invoices'),
            ],
          ),
        ),
      ],
    );
  }
}

class _JobsSearch extends StatefulWidget {
  const _JobsSearch({required this.rpc});
  final OddjobzRpc rpc;
  @override
  State<_JobsSearch> createState() => _JobsSearchState();
}

class _JobsSearchState extends State<_JobsSearch>
    with AutomaticKeepAliveClientMixin {
  late final OperatorJobsRepository _repo = OperatorJobsRepository(widget.rpc);
  late Future<List<OperatorJob>> _future = _repo.findJobs();
  String _q = '';

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _SearchBox(onChanged: (q) => setState(() => _q = q.toLowerCase())),
        Expanded(
          child: FutureBuilder<List<OperatorJob>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return _err(context, snap.error.toString());
              }
              final jobs = snap.data!
                  .where(
                    (j) =>
                        _q.isEmpty ||
                        j.customerName.toLowerCase().contains(_q) ||
                        j.propertyAddress.toLowerCase().contains(_q) ||
                        j.description.toLowerCase().contains(_q),
                  )
                  .toList();
              if (jobs.isEmpty) return _empty(context, 'No jobs');
              return RefreshIndicator(
                onRefresh: () async =>
                    setState(() => _future = _repo.findJobs()),
                child: ListView.separated(
                  itemCount: jobs.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) => JobRow(rpc: widget.rpc, job: jobs[i]),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Generic `find <noun>`-backed search list (Customers/Visits/Quotes/Invoices)
/// — the cartridge store, not owner-scoped cell.query.
class _CellSearch extends StatefulWidget {
  const _CellSearch({
    required this.rpc,
    required this.noun,
    this.titleField,
    this.subtitleField,
  });
  final OddjobzRpc rpc;
  final String noun;
  final String? titleField;
  final String? subtitleField;

  @override
  State<_CellSearch> createState() => _CellSearchState();
}

class _CellSearchState extends State<_CellSearch>
    with AutomaticKeepAliveClientMixin {
  late final OperatorJobsRepository _repo = OperatorJobsRepository(widget.rpc);
  late Future<List<Map<String, dynamic>>> _future = _load();
  String _q = '';

  Future<List<Map<String, dynamic>>> _load() => _repo.findEntities(widget.noun);

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        _SearchBox(onChanged: (q) => setState(() => _q = q.toLowerCase())),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                // No decoder for this type → honest message.
                return _empty(
                  context,
                  'No ${widget.noun} (not queryable on the brain yet)',
                );
              }
              final rows = snap.data!.where((r) {
                if (_q.isEmpty) return true;
                return r.values.any(
                  (v) => v.toString().toLowerCase().contains(_q),
                );
              }).toList();
              if (rows.isEmpty) return _empty(context, 'No ${widget.noun}');
              return RefreshIndicator(
                onRefresh: () async => setState(() => _future = _load()),
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final r = rows[i];
                    final title =
                        (r[widget.titleField] ?? _firstStringy(r) ?? '(item)')
                            .toString();
                    final sub = widget.subtitleField == null
                        ? null
                        : r[widget.subtitleField]?.toString();
                    return ListTile(
                      title: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: (sub != null && sub.isNotEmpty)
                          ? Text(sub)
                          : null,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _EntityDetailScreen(
                            noun: widget.noun,
                            title: title,
                            subtitle: sub,
                            row: r,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static String? _firstStringy(Map<String, dynamic> r) {
    const skip = {'id', 'cellId', 'cellHash', 'cellType', 'cartridgeId'};
    for (final e in r.entries) {
      if (skip.contains(e.key)) continue;
      if (e.value is String && (e.value as String).isNotEmpty) {
        return e.value as String;
      }
    }
    return null;
  }
}

class _EntityDetailScreen extends StatelessWidget {
  const _EntityDetailScreen({
    required this.noun,
    required this.title,
    required this.row,
    this.subtitle,
  });

  final String noun;
  final String title;
  final String? subtitle;
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = _idOf(row);
    return Scaffold(
      appBar: AppBar(title: Text(_singularTitle(noun))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OddjobzCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.isEmpty ? '(untitled)' : title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (id.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SelectableText(
                    id,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          OddjobzSectionLabel(
            label: 'Canonical fields',
            count: row.length,
            icon: Icons.data_object,
          ),
          const SizedBox(height: 8),
          for (final entry in _displayEntries(row))
            _FieldRow(name: entry.key, value: entry.value),
          const SizedBox(height: 16),
          ExpansionTile(
            title: const Text('Raw JSON'),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(row),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _singularTitle(String noun) {
    switch (noun) {
      case 'customers':
        return 'Customer';
      case 'visits':
        return 'Visit';
      case 'quotes':
        return 'Quote';
      case 'invoices':
        return 'Invoice';
      default:
        return noun;
    }
  }

  static String _idOf(Map<String, dynamic> row) =>
      (row['cellHash'] ?? row['cellId'] ?? row['id'] ?? '').toString();

  static List<MapEntry<String, dynamic>> _displayEntries(
    Map<String, dynamic> row,
  ) {
    final entries = row.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.name, required this.value});

  final String name;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = _formatValue(value);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(text),
          ],
        ),
      ),
    );
  }

  static String _formatValue(dynamic value) {
    if (value == null) return '—';
    if (value is String || value is num || value is bool)
      return value.toString();
    return const JsonEncoder.withIndent('  ').convert(value);
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.onChanged});
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: SearchBar(
        leading: const Icon(Icons.search),
        hintText: 'Search',
        onChanged: onChanged,
        elevation: const WidgetStatePropertyAll(0),
      ),
    );
  }
}

Widget _empty(BuildContext context, String text) {
  final theme = Theme.of(context);
  return ListView(
    children: [
      const SizedBox(height: 80),
      Center(
        child: Text(
          text,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );
}

Widget _err(BuildContext context, String e) {
  final theme = Theme.of(context);
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        e,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    ),
  );
}

```
