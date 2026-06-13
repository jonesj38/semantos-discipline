---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/pairing_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.890171+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/pairing_screen.dart

```dart
// D-O5m — Pairing screen.
//
// The first screen the operator sees when they open the app on a
// fresh device. Two paths in:
//
//   1. Scan QR — uses mobile_scanner for the device's camera. The
//      operator's desktop helm runs `brain device pair` (D-O5p) which
//      renders the QR; the mobile shell decodes the embedded
//      base64url payload + runs the BRC-42 derivation.
//
//   2. Paste URL — fallback for the desktop case where the operator
//      pastes the `https://oddjobtodd.info/pair?token=<base64url>`
//      URL directly. Same decode path, no camera needed.
//
// On successful brain-side accept (200 + bearer), the parent
// AuthRouter rebuilds and lands the operator on HomeScreen.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../identity/child_cert_store.dart';
import '../identity/secure_signing_key.dart';
import '../pairing/pair_payload.dart';
import '../pairing/pairing_service.dart';

class PairingScreen extends StatefulWidget {
  final ChildCertStore store;
  final Dio http;
  final VoidCallback onPaired;

  /// D-O5m.followup-2 — when supplied, new pairings generate the
  /// signing priv inside the platform secure store (Keychain on
  /// iOS, EncryptedSharedPreferences on Android).  When null, the
  /// legacy raw-priv path is used (and operators can opt in later
  /// via Settings → Migrate now).
  final SecureSigningKeyAdapter? secureSigningKeyAdapter;

  const PairingScreen({
    super.key,
    required this.store,
    required this.http,
    required this.onPaired,
    this.secureSigningKeyAdapter,
  });

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final TextEditingController _pasteController = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _scanning = false;

  late final PairingService _service = PairingService(
    store: widget.store,
    http: widget.http,
    secureSigningKeyAdapter: widget.secureSigningKeyAdapter,
  );

  Future<void> _submit(String tokenOrUrl) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.pair(tokenOrUrl.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paired as "${result.payload.label}"')),
      );
      widget.onPaired();
    } on PairingDecodeError catch (e) {
      setState(() => _error = 'Invalid pairing token: ${e.message}');
    } on PairingNetworkError catch (e) {
      setState(() => _error = 'Network error: ${e.message}');
    } on PairingRejectedError catch (e) {
      setState(() => _error =
          'Brain rejected pairing (${e.statusCode}): ${e.brainMessage ?? "no message"}');
    } on PairingResponseError catch (e) {
      setState(() => _error = 'Brain response error: ${e.message}');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _scanning = false;
        });
      }
    }
  }

  void _onScan(BarcodeCapture capture) {
    if (_busy) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null || raw.isEmpty) return;
    _submit(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair this device'),
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Run "brain device pair" on your operator brain to generate a pairing QR. '
              'Scan it with this device, or paste the pair URL below.',
            ),
            const SizedBox(height: 16),
            if (_scanning)
              SizedBox(
                height: 320,
                child: MobileScanner(onDetect: _onScan),
              )
            else
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() => _scanning = true),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan pairing QR'),
              ),
            const SizedBox(height: 24),
            const Text('Or paste the pair URL:'),
            const SizedBox(height: 8),
            TextField(
              controller: _pasteController,
              minLines: 2,
              maxLines: 6,
              enabled: !_busy,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText:
                    'https://oddjobtodd.info/pair?token=eyJicmFpbl9wYWlyX2VuZHBvaW50...',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _submit(_pasteController.text),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Pair'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
            ],
            const SizedBox(height: 32),
            // Reference signal — operator-readable wire-format domain.
            // If this changes, both this screen and the brain are
            // out of sync; surfacing it here helps diagnose
            // mismatched-version bugs without a debugger.
            Text(
              'Wire format: $wireDomain (v$wireVersion)',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}

```
