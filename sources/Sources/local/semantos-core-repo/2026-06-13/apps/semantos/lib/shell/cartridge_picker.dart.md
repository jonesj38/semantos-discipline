---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/cartridge_picker.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.102523+00:00
---

# apps/semantos/lib/shell/cartridge_picker.dart

```dart
// C9 PR-C9-5 — cartridge picker.
//
// Per user 2026-05-29: "there's going to be tens or hundreds of cartridges
// that a user might use. that switching won't work [tab strip]. The til
// works better and it opens the list organised by most used but with a
// search bar to type to find more."
//
// Supersedes the cartridge tab strip (PR-C9-3) which didn't scale beyond
// ~3 cartridges. The apps-icon affordance in the helm AppBar opens this
// picker — a bottom sheet with a search bar + a list of cartridges
// (recency-sorted in future; alphabetical for today's small N).
//
// Tap a cartridge → CartridgeHatState.activeCartridge is set →
// HatSwitcher reactively re-scopes + (PR-C9-6) the DO/TALK/FIND modal
// shelf filters its sub-verb list to the active cartridge's
// contributions. Sheet auto-dismisses.
//
// Future evolution (recency + dedicated mode):
//   - Recency sort: track lastUsed timestamps in CartridgeHatState
//     (or a sister notifier); show "Recent" section at top above
//     alphabetical when N > 5.
//   - Dedicated-mode cartridges (e.g., jam-room): tap → navigate to
//     cartridge's own surface route instead of just setting active
//     context. Today every cartridge is default-mode; this branch
//     adds the route push when ui.surfacingMode parsing lands
//     alongside PR-C9-6.

import 'package:cartridge_sdk/cartridge_sdk.dart';
import 'package:flutter/material.dart';
import 'package:semantos_core/semantos_core.dart';

import 'cartridge_hat_state.dart';
import 'semantos_platform.dart';

/// Show the cartridge picker as a modal bottom sheet.
/// Caller (typically the AppBar apps-icon onPressed) just calls this.
Future<void> showCartridgePicker(BuildContext context) {
  final state = CartridgeHatScope.of(context);
  final platform = SemantosPlatform.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) =>
        _CartridgePickerSheet(state: state, platform: platform),
  );
}

class _CartridgePickerSheet extends StatefulWidget {
  const _CartridgePickerSheet({required this.state, required this.platform});

  final CartridgeHatState state;
  final SemantosPlatform platform;

  @override
  State<_CartridgePickerSheet> createState() => _CartridgePickerSheetState();
}

class _CartridgePickerSheetState extends State<_CartridgePickerSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      setState(() => _query = _search.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final platform = widget.platform;
    // C9 PR-C9-6: hide passive cartridges (substrate-only, no helm
    // surfacing). Dedicated cartridges stay (picker tap → route push
    // to their dedicated surface; today routePath wires from
    // CartridgeRegistry but not yet active per surfacing mode).
    final allEntries = CartridgeRegistry.instance.entries
        .where((e) => e.role == 'experience')
        .where((e) {
          final mode =
              platform.grammarRegistry.byId(e.id)?.surfacingMode ??
              HelmSurfacingMode.defaultMode;
          return mode != HelmSurfacingMode.passive;
        })
        .toList();

    // Sort: active first, then alphabetical. Recency tracking
    // lands as a follow-up; for today's N ≤ 3 alphabetical reads
    // fine.
    allEntries.sort((a, b) {
      if (a.id == state.activeCartridge) return -1;
      if (b.id == state.activeCartridge) return 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    // Filter by search query.
    final filtered = _query.isEmpty
        ? allEntries
        : allEntries
              .where(
                (e) =>
                    e.title.toLowerCase().contains(_query) ||
                    e.id.toLowerCase().contains(_query),
              )
              .toList();

    final insets = MediaQuery.of(context).viewInsets;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: Column(
            children: [
              // Grab handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Cartridges',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${allEntries.length} active',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _search,
                  autofocus: false,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search cartridges',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            'No cartridges match "$_query".',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final entry = filtered[i];
                          final isActive = entry.id == state.activeCartridge;
                          return _CartridgeTile(
                            entry: entry,
                            isActive: isActive,
                            onTap: () {
                              state.activeCartridge = entry.id;
                              Navigator.of(context).pop();
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  settings: RouteSettings(
                                    name: entry.routePath,
                                  ),
                                  builder: entry.buildScreen,
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CartridgeTile extends StatelessWidget {
  const _CartridgeTile({
    required this.entry,
    required this.isActive,
    required this.onTap,
  });

  final CartridgeEntry entry;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: isActive
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          entry.icon ?? Icons.extension,
          color: isActive
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Text(
        entry.title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        entry.id,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: isActive
          ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}

```
