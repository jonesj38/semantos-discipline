---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/src/app.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.586829+00:00
---

# cartridges/jambox/mobile/lib/src/app.dart

```dart
// D-G.2 — Auth-gated router for the jam-room mobile shell.
//
// Same pattern as apps/oddjobz-mobile/lib/src/app.dart: switches between
// the pairing screen (no persisted record) and the jam-room home screen
// (paired).  On a 401 from the WSS, the router rebuilds back to pairing.
//
// The jam-room specific additions:
//   - Passes roomId to HomeScreen (from the pair record's capabilities or
//     a room selection screen — defaults to 'lobby' for now).
//   - Wires up ThemeService with the same warm-from-cache pattern.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'identity/auth_state.dart';
import 'identity/child_cert_store.dart';
import 'jam/home_screen.dart';
import 'jam/pairing_screen.dart';
import 'theme/theme_service.dart';

class JamRoomApp extends StatefulWidget {
  final ChildCertStore store;
  final SecureStore secureStore;
  final Dio http;
  final ThemeServiceCore themeCore;

  const JamRoomApp({
    super.key,
    required this.store,
    required this.secureStore,
    required this.http,
    required this.themeCore,
  });

  @override
  State<JamRoomApp> createState() => _JamRoomAppState();
}

class _JamRoomAppState extends State<JamRoomApp> {
  Future<AuthState>? _state;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _state = currentAuthState(widget.store);
    });
    // Best-effort theme fetch on re-auth.
    widget.themeCore.fetch();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AuthState>(
      future: _state,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final state = snapshot.data!;
        return switch (state) {
          AuthAuthenticated(:final record) => HomeScreen(
              record: record,
              roomId: _extractRoomId(record),
              onUnpaired: _refresh,
            ),
          AuthUnauthenticated() => JamRoomPairingScreen(
              store: widget.store,
              http: widget.http,
              onPaired: _refresh,
            ),
          AuthPending() => const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
        };
      },
    );
  }

  /// Extract the room ID from the pair record.
  ///
  /// Phase G: defaults to 'lobby'.  A future phase will add a room-picker
  /// screen so the user can choose which room to join.
  String _extractRoomId(ChildCertRecord record) {
    // The jam room can encode the default room in a capability like
    // 'cap.jam.room.lobby' — parse the suffix if present.
    for (final cap in record.capabilities) {
      if (cap.startsWith('cap.jam.room.')) {
        return cap.substring('cap.jam.room.'.length);
      }
    }
    return 'lobby';
  }
}

```
