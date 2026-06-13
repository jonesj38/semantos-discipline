---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/lib/src/oddjobz_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.459599+00:00
---

# cartridges/oddjobz/experience/lib/src/oddjobz_screen.dart

```dart
// OddjobzScreen — entry point for the oddjobz experience.
//
// Checks for a stored bearer token. If missing, shows the LoginView.
// If present, shows the JobListScreen connected to the brain.
//
// BrainClient uses a relative base URL so the same build works when
// served at any origin (the brain serves on the same host).

import 'package:flutter/material.dart';

import 'operator/bearer_store.dart';
import 'operator/brain_client.dart';
import 'operator/job_list_screen.dart';

/// Top-level screen registered at '/oddjobz' by the CartridgeRegistry.
class OddjobzScreen extends StatefulWidget {
  const OddjobzScreen({super.key});

  @override
  State<OddjobzScreen> createState() => _OddjobzScreenState();
}

class _OddjobzScreenState extends State<OddjobzScreen> {
  BrainClient? _client;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final token = await BearerStore.load();
    if (!mounted) return;
    if (token != null && token.length >= 8) {
      setState(() => _client = _makeClient(token));
    }
    setState(() => _loading = false);
  }

  BrainClient _makeClient(String token) {
    // Uri.base.origin throws for non-http(s) schemes (e.g. file:/// on
    // native Android). Check the scheme before accessing .origin.
    final uri = Uri.base;
    final base = (uri.scheme == 'http' || uri.scheme == 'https')
        ? uri.origin
        : 'https://oddjobtodd.info';
    return BrainClient(baseUrl: base, bearer: token);
  }

  Future<void> _onLogin(String token) async {
    await BearerStore.save(token);
    if (!mounted) return;
    setState(() => _client = _makeClient(token));
  }

  Future<void> _onLogout() async {
    _client?.dispose();
    await BearerStore.clear();
    if (!mounted) return;
    setState(() => _client = null);
  }

  @override
  void dispose() {
    _client?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_client == null) {
      return _LoginView(onLogin: _onLogin);
    }
    return JobListScreen(
      client: _client!,
      onLogout: _onLogout,
    );
  }
}

// ── Login view ──────────────────────────────────────────────────────────────

class _LoginView extends StatefulWidget {
  final Future<void> Function(String token) onLogin;
  const _LoginView({required this.onLogin});

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  void _submit() async {
    final token = _ctrl.text.trim();
    if (token.length < 8) return;
    setState(() => _busy = true);
    try {
      await widget.onLogin(token);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'oddjobz',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontFamily: 'monospace',
                          color: cs.primary,
                          letterSpacing: 0.12,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter your operator bearer token',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _ctrl,
                    obscureText: true,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Bearer token',
                      hintText: '64-char hex token',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    onSubmitted: (_) => _submit(),
                    enabled: !_busy,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy || _ctrl.text.trim().length < 8
                          ? null
                          : _submit,
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Connect'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

```
