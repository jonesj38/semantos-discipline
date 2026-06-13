---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/messages_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.889861+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/messages_screen.dart

```dart
// D-network-messagebox-first-class — MessagesScreen.
//
// Inbox + compose surface for brain-to-brain BRC-77/78 messages.
//
// V1 scope:
//   - Inbox: lists pending messages on the local brain addressed to
//     [myPubkeyHex].  Swipe-to-dismiss acks each message.  Text
//     payloads (base64-encoded UTF-8) are decoded and displayed; binary
//     BRC-77/78 envelopes show a "(encrypted)" placeholder.
//   - Compose: FAB opens a dialog to send a plaintext message to a
//     recipient on any brain.  The user supplies the remote brain URL,
//     the recipient's 66-char hex pubkey, and the message text.
//
// V2 will add: BRC-77 signing of outbound messages, BRC-78 encryption,
// and auto-population of the remote brain URL via /api/v1/bundle discovery.
//
// Navigation: opened via Navigator.push from HomeScreen's AppBar action.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../repl/messagebox_api.dart';
import '../repl/event_subscription_service.dart';

class MessagesScreen extends StatefulWidget {
  final MessageboxApi api;

  /// Own 66-char compressed pubkey hex.  Used as the recipient filter for
  /// list().  Pre-populated from the last-used value stored in-memory;
  /// the user can override it in the compose dialog.
  final String myPubkeyHex;

  /// Stream that fires whenever the brain delivers a "messagebox.received"
  /// event — used to auto-refresh the list without polling.
  final Stream<MessageReceivedEvent>? messageReceived;

  const MessagesScreen({
    super.key,
    required this.api,
    required this.myPubkeyHex,
    this.messageReceived,
  });

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<MessageboxMessage> _messages = [];
  bool _loading = false;
  String? _error;
  StreamSubscription<MessageReceivedEvent>? _pushSub;

  // Compose form state (preserved across dialog opens).
  final _remoteBrainCtl = TextEditingController();
  final _recipientCtl = TextEditingController();
  final _textCtl = TextEditingController();
  final _senderCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _senderCtl.text = widget.myPubkeyHex;
    _load();
    // Auto-refresh when the brain pushes a notification.
    _pushSub = widget.messageReceived?.listen((_) => _load());
  }

  @override
  void dispose() {
    _pushSub?.cancel();
    _remoteBrainCtl.dispose();
    _recipientCtl.dispose();
    _textCtl.dispose();
    _senderCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final msgs = await widget.api.list(widget.myPubkeyHex);
      if (!mounted) return;
      setState(() {
        _messages = msgs;
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

  Future<void> _ack(MessageboxMessage msg) async {
    try {
      await widget.api.ack(msg.id);
      // Optimistic remove from list.
      if (!mounted) return;
      setState(() => _messages.removeWhere((m) => m.id == msg.id));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to ack: $e')),
      );
    }
  }

  Future<void> _showCompose() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ComposeDialog(
        remoteBrainCtl: _remoteBrainCtl,
        recipientCtl: _recipientCtl,
        senderCtl: _senderCtl,
        textCtl: _textCtl,
      ),
    );
    if (confirmed != true || !mounted) return;

    final remoteBrainUrl = _remoteBrainCtl.text.trim();
    final recipientHex = _recipientCtl.text.trim();
    final senderHex = _senderCtl.text.trim();
    final text = _textCtl.text;

    if (remoteBrainUrl.isEmpty || recipientHex.length != 66 ||
        senderHex.length != 66 || text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fill in all fields. Pubkeys must be 66 hex chars.'),
        ),
      );
      return;
    }

    try {
      await widget.api.send(
        remoteBrainUrl: remoteBrainUrl,
        recipientHex: recipientHex,
        senderHex: senderHex,
        text: text,
      );
      if (!mounted) return;
      _textCtl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message sent.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: _load,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else if (_messages.isEmpty) {
      body = const Center(child: Text('No messages'));
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          itemCount: _messages.length,
          itemBuilder: (_, i) => _MessageTile(
            msg: _messages[i],
            onAck: () => _ack(_messages[i]),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Your pubkey',
            onPressed: () => _showPubkeyDialog(context),
          ),
        ],
      ),
      body: body,
      floatingActionButton: FloatingActionButton(
        onPressed: _showCompose,
        tooltip: 'Compose',
        child: const Icon(Icons.edit_outlined),
      ),
    );
  }

  void _showPubkeyDialog(BuildContext ctx) {
    showDialog<void>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Your pubkey'),
        content: SelectableText(
          widget.myPubkeyHex,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: widget.myPubkeyHex),
              );
              Navigator.of(dialogCtx).pop();
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Pubkey copied')),
              );
            },
            child: const Text('Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

// ── Message tile ──────────────────────────────────────────────────────────

class _MessageTile extends StatelessWidget {
  final MessageboxMessage msg;
  final VoidCallback onAck;

  const _MessageTile({required this.msg, required this.onAck});

  @override
  Widget build(BuildContext context) {
    final text = msg.text;
    final ts = DateTime.fromMillisecondsSinceEpoch(msg.tsMs).toLocal();
    final tsStr =
        '${ts.month}/${ts.day} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

    return Dismissible(
      key: ValueKey(msg.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Colors.red.shade400,
        child: const Icon(Icons.check, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        onAck();
        return true;
      },
      child: ListTile(
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: msg.kind == 'encrypted'
              ? Colors.purple.shade100
              : Colors.blue.shade100,
          child: Icon(
            msg.kind == 'encrypted' ? Icons.lock_outlined : Icons.mail_outline,
            size: 18,
            color: msg.kind == 'encrypted'
                ? Colors.purple.shade700
                : Colors.blue.shade700,
          ),
        ),
        title: text != null
            ? Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)
            : const Text(
                '(encrypted payload)',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
        subtitle: Text('${msg.senderShort}  ·  $tsStr'),
        trailing: IconButton(
          icon: const Icon(Icons.check_circle_outline),
          tooltip: 'Acknowledge',
          onPressed: onAck,
        ),
      ),
    );
  }
}

// ── Compose dialog ────────────────────────────────────────────────────────

class _ComposeDialog extends StatelessWidget {
  final TextEditingController remoteBrainCtl;
  final TextEditingController recipientCtl;
  final TextEditingController senderCtl;
  final TextEditingController textCtl;

  const _ComposeDialog({
    required this.remoteBrainCtl,
    required this.recipientCtl,
    required this.senderCtl,
    required this.textCtl,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New message'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: remoteBrainCtl,
              decoration: const InputDecoration(
                labelText: 'Recipient brain URL',
                hintText: 'https://brain.utxoengineer.com',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: recipientCtl,
              decoration: const InputDecoration(
                labelText: 'Recipient pubkey (66 hex chars)',
                hintText: '02abc...',
              ),
              autocorrect: false,
              maxLength: 66,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: senderCtl,
              decoration: const InputDecoration(
                labelText: 'Your pubkey (66 hex chars)',
                hintText: '029cf8...',
              ),
              autocorrect: false,
              maxLength: 66,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: textCtl,
              decoration: const InputDecoration(
                labelText: 'Message',
              ),
              maxLines: 4,
              autofocus: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Send'),
        ),
      ],
    );
  }
}

```
