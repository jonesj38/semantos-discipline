---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/shell/cartridge_switcher.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.901320+00:00
---

# archive/apps-semantos-monolith/lib/src/shell/cartridge_switcher.dart

```dart
// Cartridge switcher — long-press-Home modal sheet.
//
// Renders the operator's foreground cartridges as a searchable list.
// The list order is alphabetic for v1; SHELL-CARTRIDGE-MODEL §7 calls
// for Pask-ranked ordering (per-cartridge interaction count + recency)
// — that's a follow-up once the `cartridge_dwell` signal is wired into
// the attention graph.
//
// Returns the picked cartridge id, or null if the operator dismissed
// without choosing.  The caller (ShellNav) is responsible for applying
// the selection and persisting it.
//
// Settings gear at the bottom is currently a stub — the settings screen
// itself ships in a follow-up commit alongside the shell-config cartridge
// that defines the cell types for persisted preferences.

import 'package:flutter/material.dart';

import 'cartridge_entry.dart';

/// Show the cartridge switcher.  Returns the picked cartridge id, or
/// null if dismissed.
Future<String?> showCartridgeSwitcher(
  BuildContext context, {
  required List<CartridgeEntry> foregrounds,
  required String activeCartridgeId,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CartridgeSwitcherSheet(
      foregrounds: foregrounds,
      activeCartridgeId: activeCartridgeId,
    ),
  );
}

class _CartridgeSwitcherSheet extends StatefulWidget {
  const _CartridgeSwitcherSheet({
    required this.foregrounds,
    required this.activeCartridgeId,
  });

  final List<CartridgeEntry> foregrounds;
  final String activeCartridgeId;

  @override
  State<_CartridgeSwitcherSheet> createState() =>
      _CartridgeSwitcherSheetState();
}

class _CartridgeSwitcherSheetState extends State<_CartridgeSwitcherSheet> {
  String _query = '';

  /// Apply search filter + the v1 alphabetic ordering.  The active
  /// cartridge is pinned to the top regardless of search/ordering so
  /// the operator can always see "where I am now".
  List<CartridgeEntry> get _filteredFromList {
    final q = _query.trim().toLowerCase();
    Iterable<CartridgeEntry> source = widget.foregrounds;
    if (q.isNotEmpty) {
      source = source.where((e) =>
          e.label.toLowerCase().contains(q) ||
          e.descriptor.id.toLowerCase().contains(q) ||
          e.descriptor.title.toLowerCase().contains(q));
    }
    final sorted = source.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final filtered = _filteredFromList;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          // Drag handle.
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Search bar.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              autofocus: false,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search cartridges…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const Divider(height: 1),
          // Cartridge list.
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('No cartridges match "$_query".',
                          style: tt.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant)),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final entry = filtered[i];
                      final isActive =
                          entry.descriptor.id == widget.activeCartridgeId;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              isActive ? cs.primary : cs.primaryContainer,
                          child: Icon(entry.icon,
                              color: isActive
                                  ? cs.onPrimary
                                  : cs.onPrimaryContainer),
                        ),
                        title: Text(entry.label),
                        subtitle: Text(
                          entry.descriptor.title,
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        trailing: isActive
                            ? const Icon(Icons.check_circle, size: 20)
                            : const Icon(Icons.arrow_forward, size: 20),
                        selected: isActive,
                        onTap: () =>
                            Navigator.of(context).pop(entry.descriptor.id),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          // Settings stub.
          ListTile(
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Settings'),
            subtitle: const Text('Coming with shell-config cartridge'),
            enabled: false,
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

```
