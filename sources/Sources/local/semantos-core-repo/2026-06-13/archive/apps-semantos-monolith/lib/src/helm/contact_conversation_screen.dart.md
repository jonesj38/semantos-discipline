---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/contact_conversation_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.893199+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/contact_conversation_screen.dart

```dart
// Per-contact conversation screen — operator types a message, taps
// Send, the brain dispatches an SMS via Twilio.
//
// W5 of CUSTOMER-CONV-LOOP-PLAN. UI is intentionally minimal at this
// phase: title + contact details + composer.  Message history list
// lands in a follow-up once the brain wires persist (currently the
// Twilio sid is the receipt of truth).
//
// P1b — when `jobCellId` is non-null, the composer is pre-seeded with a
// chat widget link (`https://oddjobtodd.info/w?j=<cellId>`) appended to
// a short introductory phrase.  The operator can edit before sending.
//
// P4c — when `jobState == 'quoted'`, an "Approval request" chip appears
// above the compose field.  Tapping it fills the composer with the
// standard approval-request template so the operator sends it in one tap.

import 'package:flutter/material.dart';

import '../repl/conversation_send_api.dart';
import '../repl/oddjobz_query_client.dart';

class ContactConversationScreen extends StatefulWidget {
  final OddjobzCustomer contact;
  final ConversationSendApi api;

  /// P1b — optional job cell ID (64-hex LMDB hash).  When supplied, the
  /// message composer is pre-seeded with a chat widget link so the
  /// operator can send the job-specific widget URL in one tap.
  final String? jobCellId;

  /// P4c — optional job FSM state.  When `'quoted'`, shows an "Approval
  /// request" chip that fills the composer with the standard approval
  /// template (customer replies YES → brain auto-authorises via P4b).
  final String? jobState;

  const ContactConversationScreen({
    super.key,
    required this.contact,
    required this.api,
    this.jobCellId,
    this.jobState,
  });

  @override
  State<ContactConversationScreen> createState() => _ContactConversationScreenState();
}

class _ContactConversationScreenState extends State<ContactConversationScreen> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _lastSentSid;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    // P1b: pre-seed the composer with the job widget link so the operator
    // can share the URL in one tap (still editable before sending).
    final cellId = widget.jobCellId;
    if (cellId != null && cellId.isNotEmpty) {
      _controller.text =
          'Hi, here is the link to chat about your job: '
          'https://oddjobtodd.info/w?j=$cellId';
      // Place cursor at end.
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _lastError = null;
    });
    try {
      final result = await widget.api.send(
        conversationId: widget.contact.id,
        body: text,
      );
      if (!mounted) return;
      _controller.clear();
      setState(() {
        _lastSentSid = result.sid;
        _sending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sent (${result.status})')),
      );
    } on ConversationSendError catch (e) {
      if (!mounted) return;
      setState(() {
        _lastError = e.userMessage;
        _sending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.userMessage)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastError = 'Send failed: $e';
        _sending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.contact;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.displayName.isNotEmpty ? c.displayName : 'Contact'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (c.role != null && c.role!.isNotEmpty)
                  Text(
                    '${c.role![0].toUpperCase()}${c.role!.substring(1)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                if (c.phone.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(c.phone, style: const TextStyle(fontSize: 14)),
                  ),
                if (c.email.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(c.email, style: const TextStyle(color: Colors.grey, fontSize: 13)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'No message history yet.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    if (_lastSentSid != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Last sent: $_lastSentSid',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                    if (_lastError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _lastError!,
                        style: const TextStyle(fontSize: 12, color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // P4c — approval-request chip; only shown for quoted jobs.
                if (widget.jobState == 'quoted')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: ActionChip(
                        avatar: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('Approval request'),
                        visualDensity: VisualDensity.compact,
                        onPressed: _sending
                            ? null
                            : () {
                                final name = widget.contact.displayName.isNotEmpty
                                    ? widget.contact.displayName.split(' ').first
                                    : 'there';
                                _controller.text =
                                    "Hi $name, we've prepared a quote for your job. "
                                    'Please reply YES to approve, or call us to discuss.';
                                _controller.selection = TextSelection.fromPosition(
                                  TextPosition(offset: _controller.text.length),
                                );
                              },
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          enabled: !_sending,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            hintText: 'Type a message…',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send),
                        tooltip: 'Send via SMS',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

```
