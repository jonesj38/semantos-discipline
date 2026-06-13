---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/shell/tabs/contacts_tab.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.904342+00:00
---

# archive/apps-semantos-monolith/lib/src/shell/tabs/contacts_tab.dart

```dart
// Contacts — shell-native PKI contact book tab.
//
// Shows the operator's hat-scoped contacts from ContactsRepository
// (BRC-52 cert-identified peers).  Contacts are keyed by certId
// (compressed secp256k1 pubkey hex) and scoped to the active hat so
// switching hats switches the visible contact set.
//
// This tab is shell-native: it renders ContactRecord objects directly
// from the storage layer without going through any cartridge-specific
// REPL verb.  Cartridges (e.g. oddjobz) may layer richer views on top
// (e.g. CustomerDetailScreen), but the canonical identity book lives here.
//
// Tap a contact → ContactProfileSheet (local modal, no cartridge dep).
// The shell's Talk node surfaces "Start conversation" actions; we don't
// replicate that here — contacts tab is identity, talk tab is conversation.

import 'package:flutter/material.dart';

import '../../contacts/contact_record.dart';
import '../../contacts/contacts_repository.dart';

class ContactsTab extends StatefulWidget {
  const ContactsTab({super.key, required this.contacts});

  final ContactsRepository? contacts;

  @override
  State<ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<ContactsTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<ContactRecord>? _records;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ContactsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-load when the repository becomes available (was null → non-null).
    if (oldWidget.contacts == null && widget.contacts != null) {
      _load();
    }
  }

  Future<void> _load() async {
    final repo = widget.contacts;
    if (repo == null) return;
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = await repo.listContacts();
      if (!mounted) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cs = Theme.of(context).colorScheme;

    if (widget.contacts == null) {
      return const _LoadingPlaceholder(message: 'Opening contact book…');
    }

    if (_loading && _records == null) {
      return const _LoadingPlaceholder(message: 'Loading contacts…');
    }

    if (_error != null) {
      return _ErrorPlaceholder(error: _error!, onRetry: _load);
    }

    final records = _records ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: records.isEmpty
          ? _EmptyContacts(cs: cs)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: records.length,
                itemBuilder: (ctx, i) =>
                    _ContactTile(record: records[i], cs: cs),
              ),
            ),
    );
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
            ],
          ),
        ),
      );
}

class _ErrorPlaceholder extends StatelessWidget {
  const _ErrorPlaceholder({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text('Failed to load contacts',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(error,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton.tonal(
                    onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.contacts_outlined, size: 64, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text('No contacts yet',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    )),
            const SizedBox(height: 8),
            Text('Contacts are discovered through brain pairing\nand federation.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.outlineVariant,
                    ),
                textAlign: TextAlign.center),
          ],
        ),
      );
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.record, required this.cs});
  final ContactRecord record;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final initials = record.displayName.isEmpty
        ? '?'
        : record.displayName[0].toUpperCase();
    final isConnected = record.edgeId != null;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: cs.primaryContainer,
        child: Text(initials,
            style: TextStyle(
                color: cs.onPrimaryContainer, fontWeight: FontWeight.w600)),
      ),
      title: Text(record.displayName),
      subtitle: Text(
        record.email ?? _truncatePub(record.publicKey),
        overflow: TextOverflow.ellipsis,
      ),
      trailing: isConnected
          ? Icon(Icons.circle, size: 10, color: cs.primary)
          : Icon(Icons.circle_outlined, size: 10, color: cs.outlineVariant),
      onTap: () => _showProfile(context),
    );
  }

  void _showProfile(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ContactProfileSheet(record: record),
    );
  }

  String _truncatePub(String hex) {
    if (hex.length <= 12) return hex;
    return '${hex.substring(0, 6)}…${hex.substring(hex.length - 6)}';
  }
}

/// Contact identity profile sheet — shows the BRC-52 cert fields.
class _ContactProfileSheet extends StatelessWidget {
  const _ContactProfileSheet({required this.record});
  final ContactRecord record;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        children: [
          Center(
            child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2))),
          ),
          CircleAvatar(
            radius: 32,
            backgroundColor: cs.primaryContainer,
            child: Text(
              record.displayName.isEmpty
                  ? '?'
                  : record.displayName[0].toUpperCase(),
              style: tt.headlineMedium
                  ?.copyWith(color: cs.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(record.displayName,
                style: tt.titleLarge, textAlign: TextAlign.center),
          ),
          if (record.email != null) ...[
            const SizedBox(height: 4),
            Center(
                child: Text(record.email!,
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
          ],
          const SizedBox(height: 24),
          _Field(label: 'Cert ID', value: record.certId),
          _Field(label: 'Public Key', value: record.publicKey),
          if (record.nodeType != null)
            _Field(label: 'Node Type', value: record.nodeType!),
          _Field(
              label: 'Connection',
              value: record.edgeId != null
                  ? 'Connected (edge: ${record.edgeId!.substring(0, 8)}…)'
                  : 'Not connected'),
          _Field(label: 'Source', value: record.source),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          SelectableText(value,
              style: tt.bodyMedium?.copyWith(fontFamily: 'monospace')),
          const Divider(height: 1, thickness: 0.5),
        ],
      ),
    );
  }
}

```
