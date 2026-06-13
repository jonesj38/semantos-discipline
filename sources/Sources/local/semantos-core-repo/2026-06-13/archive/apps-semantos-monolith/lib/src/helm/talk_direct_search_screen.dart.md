---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/talk_direct_search_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.888609+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/talk_direct_search_screen.dart

```dart
// Talk | Direct search surface.
//
// W6 of CUSTOMER-CONV-LOOP-PLAN. Per Todd's verbatim 2026-05-14:
//
//   "It would be great to be able to message them from the
//    talk | direct page via typing in their name or the job
//    address/suburb and the job surfaces with their contact names."
//
// Renders a search bar at the top + a results list.  Search is
// debounced (300ms after last keystroke).  Tapping a result opens
// the contact's per-contact SMS composer (same screen as W5's
// JobDetailScreen contact-tile flow).
//
// Empty state: helper text + suggestion to type a name or suburb.

import 'dart:async';
import 'package:flutter/material.dart';

import '../repl/conversation_send_api.dart';
import '../repl/oddjobz_query_client.dart';
import '../repl/search_contacts_api.dart';
import 'contact_conversation_screen.dart';

class TalkDirectSearchScreen extends StatefulWidget {
  final SearchContactsApi searchApi;
  final ConversationSendApi sendApi;

  const TalkDirectSearchScreen({
    super.key,
    required this.searchApi,
    required this.sendApi,
  });

  @override
  State<TalkDirectSearchScreen> createState() =>
      _TalkDirectSearchScreenState();
}

class _TalkDirectSearchScreenState extends State<TalkDirectSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  List<ContactSearchHit> _hits = const [];
  String _activeQuery = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    final q = text.trim();
    if (q.isEmpty) {
      setState(() {
        _activeQuery = '';
        _hits = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(q));
  }

  Future<void> _run(String q) async {
    if (!mounted) return;
    setState(() {
      _activeQuery = q;
      _loading = true;
      _error = null;
    });
    try {
      final hits = await widget.searchApi.search(q);
      if (!mounted || _activeQuery != q) return; // stale response
      setState(() {
        _hits = hits;
        _loading = false;
      });
    } on SearchContactsError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.userMessage;
        _loading = false;
        _hits = const [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Search failed: $e';
        _loading = false;
        _hits = const [];
      });
    }
  }

  void _openContact(ContactSearchHit hit) {
    // Project the lightweight ContactSearchHit onto the OddjobzCustomer
    // shape expected by ContactConversationScreen.  Only fields the
    // screen actually reads (id / displayName / phone / email / role)
    // are meaningful; the rest are passed as null/empty.
    final c = OddjobzCustomer(
      id: hit.id,
      displayName: hit.displayName,
      phone: hit.phone,
      email: '',
      address: '',
      cellId: null,
      typeHash: null,
      role: null,
      siteRef: hit.siteRef,
    );
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ContactConversationScreen(
        contact: c,
        api: widget.sendApi,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Direct — search contacts')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Name, address, or suburb…',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _controller.clear();
                          _onChanged('');
                        },
                      )
                    : null,
              ),
              onChanged: _onChanged,
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: LinearProgressIndicator(),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!,
              style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
        ),
      );
    }
    if (_activeQuery.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Type a contact name, job address, or suburb to find someone to message.',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_hits.isEmpty && !_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No matches.', style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return ListView.separated(
      itemCount: _hits.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final h = _hits[i];
        final hasPhone = h.phone.isNotEmpty;
        return ListTile(
          title: Text(h.displayName.isNotEmpty ? h.displayName : '(unnamed)'),
          subtitle: hasPhone
              ? Text(h.phone)
              : const Text('no phone on record',
                  style: TextStyle(color: Colors.grey)),
          trailing: hasPhone
              ? const Icon(Icons.send, size: 18, color: Colors.grey)
              : null,
          enabled: hasPhone,
          onTap: hasPhone ? () => _openContact(h) : null,
        );
      },
    );
  }
}

```
