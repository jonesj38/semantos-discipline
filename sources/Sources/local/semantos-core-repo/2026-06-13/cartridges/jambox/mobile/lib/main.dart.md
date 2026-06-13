---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/mobile/lib/main.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.583676+00:00
---

# cartridges/jambox/mobile/lib/main.dart

```dart
// D-G.2 — jam-room-mobile entry point.
//
// Wires up the app's top-level state:
//   - ChildCertStore (with flutter_secure_storage adapter)
//   - Dio HTTP client with bounded timeouts
//   - ThemeServiceCore (warm from cache before first paint)
//
// Then hands off to JamRoomApp which gates on auth state and routes
// to either the pairing screen or the home screen.
//
// Modelled on apps/oddjobz-mobile/lib/main.dart; the jam-room version
// omits Firebase/push (out of scope for Phase G) and Firebase references.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/identity/child_cert_store.dart';
import 'src/identity/flutter_secure_store_adapter.dart';
import 'src/theme/theme_service.dart';
import 'src/theme/theme_service_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final secureStore = FlutterSecureStoreAdapter();
  final certStore = ChildCertStore(secureStore);

  // Bounded HTTP timeouts — same values as oddjobz-mobile.
  final http = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 10),
  ));

  // Per-tenant theme — warm from cache before first paint.
  final themeCore = ThemeServiceCore(
    certStore: certStore,
    secureStore: secureStore,
    dio: http,
  );
  await themeCore.warmFromCache();

  runApp(_JamRoomMaterialApp(
    certStore: certStore,
    secureStore: secureStore,
    http: http,
    themeCore: themeCore,
  ));
}

/// Top-level MaterialApp with per-tenant theme.
class _JamRoomMaterialApp extends StatefulWidget {
  final ChildCertStore certStore;
  final SecureStore secureStore;
  final Dio http;
  final ThemeServiceCore themeCore;

  const _JamRoomMaterialApp({
    required this.certStore,
    required this.secureStore,
    required this.http,
    required this.themeCore,
  });

  @override
  State<_JamRoomMaterialApp> createState() => _JamRoomMaterialAppState();
}

class _JamRoomMaterialAppState extends State<_JamRoomMaterialApp> {
  late TenantTheme _theme;

  @override
  void initState() {
    super.initState();
    _theme = widget.themeCore.current;
    widget.themeCore.changes.listen((t) {
      if (mounted) setState(() => _theme = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'jam room',
      theme: toMaterialTheme(_theme),
      darkTheme: toMaterialDarkTheme(_theme),
      themeMode: toFlutterThemeMode(_theme.mode),
      debugShowCheckedModeBanner: kDebugMode,
      home: JamRoomApp(
        store: widget.certStore,
        secureStore: widget.secureStore,
        http: widget.http,
        themeCore: widget.themeCore,
      ),
    );
  }
}

```
