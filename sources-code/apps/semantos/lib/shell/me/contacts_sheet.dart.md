---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/me/contacts_sheet.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.120455+00:00
---

# apps/semantos/lib/shell/me/contacts_sheet.dart

```dart
// PWA contacts-PKI — the Contacts surface.
//
// Mirrors the brain's invite → bilateral edge → BRC-69 backup flow
// (cartridges/wallet-headers/brain/src/{peer-invite,ecdh-edge}.ts) in
// the field app. Three affordances over `ContactsService`:
//   - Generate invite : produce my invite URL to share with a peer.
//   - Accept invite   : paste a peer's invite URL/token → mint + persist
//                       a LocalEdgeEnvelope (edgeId + BRC-69 recipe).
//   - Edge list       : the contacts the wallet holds.
//
// The crypto + persistence live in `lib/src/wallet/` (edge_invite.dart,
// edge_store.dart, contacts_service.dart); this file is presentation
// only. QR rendering is deferred (no QR widget in deps yet) — invites
// surface as a copyable URL.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../src/wallet/contacts_service.dart';
import '../../src/wallet/edge_store.dart';
import '../semantos_platform.dart';

/// Open the Contacts bottom sheet.
Future<void> showContactsSheet(BuildContext context) {
  final platform = SemantosPlatform.of(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => _ContactsSheet(
      service: ContactsService(identityStore: platform.identityStore),
    ),
  );
}

class _ContactsSheet extends StatefulWidget {
  const _ContactsSheet({required this.service});

  final ContactsService service;

  @override
  State<_ContactsSheet> createState() => _ContactsSheetState();
}

class _ContactsSheetState extends State<_ContactsSheet> {
  late Future<List<LocalEdgeEnvelope>> _edgesFuture;
  final TextEditingController _inviteController = TextEditingController();
  bool _accepting = false;

  @override
  void initState() {
    super.initState();
    _edgesFuture = widget.service.listEdges();
  }

  @override
  void dispose() {
    _inviteController.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _edgesFuture = widget.service.listEdges();
    });
  }

  Future<void> _generateInvite() async {
    final generated = await widget.service.generateMyInvite();
    if (!mounted) return;
    if (generated == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No identity bound — set up your wallet first.'),
        ),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => _InviteDialog(url: generated.url),
    );
  }

  Future<void> _acceptInvite() async {
    final input = _inviteController.text.trim();
    if (input.isEmpty) return;
    setState(() => _accepting = true);
    try {
      final env = await widget.service.acceptInvite(input);
      if (!mounted) return;
      _inviteController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Edge created · ${_short(env.edgeId)}'),
          duration: const Duration(seconds: 4),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Accept failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final insets = MediaQuery.of(context).viewInsets;
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: Column(
            children: [
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
                    Icon(Icons.people_alt_outlined,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Text(
                      'Contacts',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Refresh',
                      icon: const Icon(Icons.refresh),
                      onPressed: _reload,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    _generateSection(theme),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _acceptSection(theme),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    _edgeListSection(theme),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _generateSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(theme, Icons.qr_code_2, 'Invite a contact'),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Share an invite link. When they accept, a bilateral '
                  'edge (BRC-42) + BRC-69 backup recipe is created on '
                  'their side.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Generate invite'),
                  onPressed: _generateInvite,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _acceptSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(theme, Icons.person_add_alt_1_outlined,
              'Accept an invite'),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 36),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _inviteController,
                  minLines: 1,
                  maxLines: 3,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    hintText: 'Paste invite URL or token',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  icon: _accepting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: const Text('Accept invite'),
                  onPressed: _accepting ? null : _acceptInvite,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _edgeListSection(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(theme, Icons.hub_outlined, 'My edges'),
          const SizedBox(height: 8),
          FutureBuilder<List<LocalEdgeEnvelope>>(
            future: _edgesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.only(left: 36, top: 4),
                  child: Text(
                    'Could not read edges: ${snapshot.error}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                );
              }
              final edges = snapshot.data ?? const [];
              if (edges.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.only(left: 36, top: 4),
                  child: Text(
                    'No edges yet. Generate an invite or accept one to '
                    'create your first contact.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                );
              }
              return Column(
                children: [for (final e in edges) _EdgeTile(envelope: e)],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Text(
          title,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  static String _short(String s) {
    if (s.length <= 16) return s;
    return '${s.substring(0, 8)}…${s.substring(s.length - 4)}';
  }
}

/// One edge row — peer cert id + edge id + signing index.
class _EdgeTile extends StatelessWidget {
  const _EdgeTile({required this.envelope});

  final LocalEdgeEnvelope envelope;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 36, right: 0),
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Icon(Icons.person_outline,
            size: 18, color: theme.colorScheme.onPrimaryContainer),
      ),
      title: Text(
        'peer ${_short(envelope.theirCertId)}',
        style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace'),
      ),
      subtitle: Text(
        'edge ${_short(envelope.edgeId)} · idx ${envelope.signingKeyIndex} · '
        '${envelope.edgeType.toLowerCase()}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  static String _short(String s) {
    if (s.length <= 16) return s;
    return '${s.substring(0, 8)}…${s.substring(s.length - 4)}';
  }
}

/// Dialog rendering a generated invite URL with a copy action. QR is a
/// future enhancement (no QR widget in deps).
class _InviteDialog extends StatelessWidget {
  const _InviteDialog({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Your invite'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Share this link with the contact you want to connect with. '
            'It expires in 24 hours.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              url,
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copy link'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (context.mounted) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invite link copied')),
              );
            }
          },
        ),
      ],
    );
  }
}

```
