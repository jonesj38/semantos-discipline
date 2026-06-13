---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/jam/support_sheet.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.590734+00:00
---

# cartridges/jambox/mobile/lib/src/jam/support_sheet.dart

```dart
// D-G.4 — Support sheet: modal bottom sheet with 5 L3 entries.
//
// Entries: Sequencer / Mix / Session / Arrange / Custom.
// Custom is ENABLED (Phase C is a prerequisite for G).
//
// Revealed via long-press on an L2 tab or the anchor-card menu button.

import 'package:flutter/material.dart';

const _entries = [
  _SheetEntry(id: 'sequencer', label: 'Sequencer', icon: Icons.grid_on),
  _SheetEntry(id: 'mix',       label: 'Mix',        icon: Icons.tune),
  _SheetEntry(id: 'session',   label: 'Session',    icon: Icons.play_circle_outline),
  _SheetEntry(id: 'arrange',   label: 'Arrange',    icon: Icons.view_timeline),
  _SheetEntry(id: 'custom',    label: 'Custom',     icon: Icons.extension),
];

class _SheetEntry {
  final String id;
  final String label;
  final IconData icon;
  final bool enabled;
  const _SheetEntry({
    required this.id,
    required this.label,
    required this.icon,
    this.enabled = true,
  });
}

/// Modal bottom sheet exposing L3 support entries.
///
/// [onEntry] is called with the entry id ('sequencer', 'mix', etc.) when
/// the user taps an entry.
class SupportSheet extends StatelessWidget {
  final ValueChanged<String> onEntry;

  const SupportSheet({super.key, required this.onEntry});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF161922),
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(top: BorderSide(color: Color(0xFF2A3142))),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF4A5070),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: const [
                  Text(
                    'SUPPORT',
                    style: TextStyle(
                      color: Color(0xFF8B94A8),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      letterSpacing: 0.08,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF2A3142), height: 1),
            // Entries
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (_, i) {
                  final e = _entries[i];
                  return _SupportEntryTile(
                    entry: e,
                    onTap: e.enabled ? () => onEntry(e.id) : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportEntryTile extends StatelessWidget {
  final _SheetEntry entry;
  final VoidCallback? onTap;

  const _SupportEntryTile({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1D2230),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF2A3142)),
            ),
            child: Row(
              children: [
                Icon(
                  entry.icon,
                  color: enabled
                      ? const Color(0xFF65D6F5)
                      : const Color(0xFF4A5070),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.label,
                    style: TextStyle(
                      color: enabled
                          ? const Color(0xFFE6E9F2)
                          : const Color(0xFF4A5070),
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                if (enabled)
                  const Icon(
                    Icons.chevron_right,
                    color: Color(0xFF4A5070),
                    size: 18,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

```
