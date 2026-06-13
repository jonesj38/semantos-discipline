---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/shell/brain_connect_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.100507+00:00
---

# apps/semantos/lib/shell/brain_connect_screen.dart

```dart
import 'package:flutter/material.dart';

import '../platform/wallet_resolver.dart';

/// Brain connection screen — enter a brain URL + bearer token and persist
/// them via [WalletResolver.saveBrainConnection].
///
/// Reached two ways:
///   - boot fallback on web (no wallet → bootResolvedNode throws → this), and
///   - the helm's "Connect" affordance on native (M1.6), where there is no
///     wallet-gated pairing step but an operator still needs to point the app
///     at a brain.
///
/// On a successful save, [onConnected] fires so the caller can re-run boot /
/// reconnect the RPC client against the new connection.
class BrainConnectScreen extends StatefulWidget {
  const BrainConnectScreen({super.key, required this.onConnected});

  /// Invoked after the connection is persisted. Callers typically re-run the
  /// boot prepare step so [BrainRpcClient] reconnects with the new creds.
  final VoidCallback onConnected;

  @override
  State<BrainConnectScreen> createState() => _BrainConnectScreenState();
}

class _BrainConnectScreenState extends State<BrainConnectScreen> {
  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _urlCtrl.text.trim();
    final token = _tokenCtrl.text.trim();
    if (url.isEmpty || token.isEmpty) {
      setState(() => _error = 'Both fields are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await WalletResolver.saveBrainConnection(
        baseUrl: url,
        bearerToken: token,
      );
      widget.onConnected();
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to Brain')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Enter your brain URL and bearer token to connect.'),
            const SizedBox(height: 24),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'Brain URL',
                hintText: 'https://your-brain.example.com',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tokenCtrl,
              decoration: const InputDecoration(
                labelText: 'Bearer token',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              autocorrect: false,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
          ],
        ),
      ),
    );
  }
}

```
