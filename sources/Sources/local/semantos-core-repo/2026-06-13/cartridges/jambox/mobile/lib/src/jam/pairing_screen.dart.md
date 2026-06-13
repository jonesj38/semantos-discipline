---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/jam/pairing_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.591468+00:00
---

# cartridges/jambox/mobile/lib/src/jam/pairing_screen.dart

```dart
// D-G.3 — Jam-room pairing screen.
//
// Reuses the Phase C BRC-42 pairing flow from oddjobz-mobile with a
// jam-room themed UI.  Scan QR from the desktop room (which shows a
// pairing URL on demand) or paste a raw token.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../identity/child_cert_store.dart';
import '../pairing/pairing_service.dart';

/// Pairing screen: presents QR scanner + paste-fallback.
class JamRoomPairingScreen extends StatefulWidget {
  final ChildCertStore store;
  final Dio http;
  final VoidCallback onPaired;

  const JamRoomPairingScreen({
    super.key,
    required this.store,
    required this.http,
    required this.onPaired,
  });

  @override
  State<JamRoomPairingScreen> createState() =>
      _JamRoomPairingScreenState();
}

class _JamRoomPairingScreenState extends State<JamRoomPairingScreen> {
  final _pasteCtrl = TextEditingController();
  bool _scanning = false;
  bool _pairing = false;
  String? _error;

  late final PairingService _svc;

  @override
  void initState() {
    super.initState();
    _svc = PairingService(
      store: widget.store,
      dio: widget.http,
    );
  }

  @override
  void dispose() {
    _pasteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pair(String tokenOrUrl) async {
    setState(() { _pairing = true; _error = null; });
    try {
      await _svc.pair(tokenOrUrl);
      widget.onPaired();
    } on PairingDecodeError catch (e) {
      setState(() => _error = 'Invalid token: ${e.message}');
    } on PairingRejectedError catch (e) {
      setState(() => _error = 'Brain rejected pairing (${e.statusCode}).');
    } on PairingNetworkError catch (e) {
      setState(() => _error = 'Network error: ${e.message}');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _pairing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1014),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              const Text(
                'jam room',
                style: TextStyle(
                  color: Color(0xFF65D6F5),
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'pair your device',
                style: TextStyle(
                  color: Color(0xFF8B94A8),
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              if (_scanning)
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: MobileScanner(
                      onDetect: (capture) {
                        final barcode = capture.barcodes.firstOrNull;
                        final raw = barcode?.rawValue;
                        if (raw != null && raw.isNotEmpty) {
                          setState(() => _scanning = false);
                          _pair(raw);
                        }
                      },
                    ),
                  ),
                )
              else ...[
                ElevatedButton.icon(
                  onPressed: _pairing
                      ? null
                      : () => setState(() => _scanning = true),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR from desktop room'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF65D6F5),
                    foregroundColor: const Color(0xFF0E1014),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '— or paste a token —',
                  style: TextStyle(
                    color: Color(0xFF4A5070),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pasteCtrl,
                  style: const TextStyle(
                    color: Color(0xFFE6E9F2),
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Paste pairing token or URL',
                    hintStyle: TextStyle(
                      color: Color(0xFF4A5070),
                      fontFamily: 'monospace',
                    ),
                    filled: true,
                    fillColor: Color(0xFF1D2230),
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF2A3142)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF2A3142)),
                    ),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _pairing
                      ? null
                      : () {
                          final t = _pasteCtrl.text.trim();
                          if (t.isNotEmpty) _pair(t);
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D2230),
                    foregroundColor: const Color(0xFF65D6F5),
                    side: const BorderSide(color: Color(0xFF65D6F5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(fontFamily: 'monospace'),
                  ),
                  child: _pairing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF65D6F5),
                          ),
                        )
                      : const Text('Pair'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFFF97A4),
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const Spacer(),
              const Text(
                'Wire format: semantos-pair (v2)',
                style: TextStyle(
                  color: Color(0xFF4A5070),
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

```
