---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/app.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.861619+00:00
---

# archive/apps-semantos-monolith/lib/src/app.dart

```dart
// D-O5m — auth-gated router.
//
// Top-level switch between the pairing screen (no persisted record)
// and the helm surface (paired). On a 401 from the helm REPL, child
// surfaces clear the persisted record and the router rebuilds back
// to the pairing screen.
//
// Tier 2P Phase A — outbox wiring.  When the device is authenticated,
// this router opens an [OutboxDb] and constructs an [OutboxService]
// then passes it down to [HomeScreen].  The DB is closed on dispose
// so the SQLite connection is cleanly released whenever the user
// logs out or the widget tree is torn down.
//
// Tier 2P Phase D.2 — attention wiring.  When the device is
// authenticated, this router constructs an [AttentionService] (backed
// by [OddjobzAttentionClient] over the same WSS HelmEventStream that
// HomeScreen creates) and passes it down to [HomeScreen].  Mirrors the
// _ensureOutbox / _tearDownOutbox pattern from Phase A exactly.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:semantos_ffi/semantos_ffi.dart' show SemantosKernel;
import 'package:sqflite/sqflite.dart' as sqflite;

import 'helm/home_screen.dart';
import 'helm/pairing_screen.dart';
import 'identity/auth_state.dart';
import 'identity/child_cert_store.dart';
import 'outbox/outbox_db.dart';
import 'outbox/outbox_service.dart';
import 'push/push_registration_service.dart';
import 'repl/attention_service.dart';
import 'repl/helm_event_stream.dart';
import 'repl/oddjobz_attention_client.dart';
import 'repl/repl_client.dart';
import 'theme/theme_service_flutter.dart';

class AuthRouter extends StatefulWidget {
  final ChildCertStore store;

  /// Same SecureStore the [store] was constructed from.  Forwarded
  /// to PushRegistrationService so it shares the persisted-state
  /// surface (notification registration is stored on the same
  /// keychain / keystore as the child cert).
  final SecureStore? secureStore;

  final Dio http;

  /// D-O5m.followup-9 Phase C — push notification service.  Nullable
  /// because the dev harness can boot without Firebase configured.
  /// HomeScreen treats null as "push disabled" and the operator-
  /// facing notification card in SettingsScreen renders an info
  /// banner explaining that push isn't wired in this build.
  final PushRegistrationService? pushService;

  /// D-O5.followup-6 — per-tenant theme service.  Nullable for
  /// older test harnesses that construct AuthRouter without theme
  /// wiring; HomeScreen kicks off a `fetch()` post-auth when set.
  final ThemeService? themeService;

  /// 2026-05-07 — initialised SemantosKernel for the on-device L1→L4
  /// typed-NL pipeline.  Forwarded through HomeScreen into
  /// OnDeviceVoiceFactory.create.  Null on dev harnesses without the
  /// FFI loaded; the typed-NL path falls through to
  /// `TextIntentPipelineUnavailable` in that case.
  final SemantosKernel? kernel;

  /// Sovereign-push D.3 — Settings → Push backend picker callbacks.
  /// Constructed in main.dart against the live UnifiedPush + Firebase
  /// adapters; forwarded straight through to HomeScreen → SettingsScreen.
  final Future<PushRegistrationResult> Function(PushBackendPreference pref)?
      onApplyBackendPreference;
  final Future<List<String>> Function()? onListUnifiedPushDistributors;
  final Future<void> Function(String distributorId)?
      onChooseUnifiedPushDistributor;

  const AuthRouter({
    super.key,
    required this.store,
    required this.http,
    this.secureStore,
    this.pushService,
    this.themeService,
    this.kernel,
    this.onApplyBackendPreference,
    this.onListUnifiedPushDistributors,
    this.onChooseUnifiedPushDistributor,
  });

  @override
  State<AuthRouter> createState() => _AuthRouterState();
}

class _AuthRouterState extends State<AuthRouter> {
  Future<AuthState>? _state;

  // Tier 2P Phase A — outbox wiring.  Opened once when the router
  // first sees an AuthAuthenticated state; closed in dispose().
  OutboxDb? _outboxDb;
  OutboxService? _outboxService;
  // Guard so the async open is only kicked off once per auth session.
  bool _outboxOpening = false;

  // Tier 2P Phase D.2 — attention wiring.  Constructed once when the
  // router first sees an AuthAuthenticated state; disposed in dispose().
  // Nullable so HomeScreen / test rigs that don't need it still build.
  AttentionService? _attentionService;
  // Guard so the construction is only kicked off once per auth session.
  bool _attentionOpening = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    // On logout/unpair the existing outbox + attention resources are
    // torn down so a fresh construction happens on the next authenticate.
    _tearDownOutbox();
    _tearDownAttention();
    setState(() {
      _state = currentAuthState(widget.store);
    });
  }

  // Opens the outbox DB and constructs the OutboxService once per
  // authenticated session.  Safe to call multiple times — the
  // _outboxOpening guard prevents concurrent opens.
  Future<void> _ensureOutbox(ChildCertRecord record) async {
    if (_outboxOpening || _outboxDb != null) return;
    _outboxOpening = true;
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dbPath = '${docsDir.path}/outbox.db';
      final raw = await sqflite.openDatabase(dbPath);
      final db = await OutboxDb.fromDatabase(raw);

      // Build a ReplClient from the paired record so flush() can push
      // entries over the bearer-gated REPL endpoint.
      final baseUrl = _brainBaseUrl(record.brainPairEndpoint);
      final repl = ReplClient.withBearer(
        http: widget.http,
        baseUrl: baseUrl,
        bearer: record.bearer,
      );

      final svc = OutboxService(db: db, repl: repl);

      if (!mounted) {
        // Widget was disposed before the open finished — clean up.
        await svc.dispose();
        await db.close();
        return;
      }
      setState(() {
        _outboxDb = db;
        _outboxService = svc;
      });
    } catch (e) {
      // Non-fatal — the outbox stays null and the "not ready" guard
      // in HomeScreen will remain active until the next reconnect.
      debugPrint('[outbox] open failed: $e');
    } finally {
      _outboxOpening = false;
    }
  }

  // Releases outbox resources on logout / unpair.
  void _tearDownOutbox() {
    final svc = _outboxService;
    final db = _outboxDb;
    _outboxService = null;
    _outboxDb = null;
    _outboxOpening = false;
    // Fire-and-forget — disposal is best-effort; the Flutter runtime
    // will release the SQLite file handle even if this future is
    // abandoned.
    if (svc != null) svc.dispose();
    if (db != null) db.close();
  }

  // Constructs the AttentionService once per authenticated session.
  // Mirrors _ensureOutbox() exactly — guard prevents concurrent creates.
  // The HelmEventStream used here is the canonical one owned by
  // HomeScreen; we forward it in so AttentionService can subscribe to
  // topic events.  The stream must already be connected before this is
  // called; HomeScreen.initState() calls _eventStream.connect() before
  // the first frame, so by the time the microtask fires it is open or
  // connecting.
  Future<void> _ensureAttention(
    ChildCertRecord record,
    HelmEventStream eventStream,
  ) async {
    if (_attentionOpening || _attentionService != null) return;
    _attentionOpening = true;
    try {
      final client = OddjobzAttentionClient(eventStream);
      final svc = AttentionService(
        client: client,
        eventStream: eventStream,
      );

      if (!mounted) {
        await svc.dispose();
        return;
      }
      setState(() {
        _attentionService = svc;
      });
    } catch (e) {
      // Non-fatal — AttentionService stays null; screens should handle
      // the null case gracefully.
      debugPrint('[attention] create failed: $e');
    } finally {
      _attentionOpening = false;
    }
  }

  // Releases attention resources on logout / unpair.
  void _tearDownAttention() {
    final svc = _attentionService;
    _attentionService = null;
    _attentionOpening = false;
    if (svc != null) svc.dispose(); // fire-and-forget
  }

  @override
  void dispose() {
    _tearDownOutbox();
    _tearDownAttention();
    super.dispose();
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
        // D-O5.followup-6 — kick off a theme fetch post-auth.  Best-
        // effort: errors fall back to the cached value (or defaults)
        // inside ThemeService.fetch().
        if (state is AuthAuthenticated && widget.themeService != null) {
          // Fire-and-forget; ValueListenableBuilder in main.dart will
          // rebuild MaterialApp when theme.value changes.
          widget.themeService!.fetch();
        }
        // Tier 2P Phase A — ensure the outbox is open once a paired
        // record is available.  Uses scheduleMicrotask so the async
        // work is deferred past the current build frame (same pattern
        // as HomeScreen._initVoiceFactory).
        if (state is AuthAuthenticated) {
          scheduleMicrotask(() => _ensureOutbox(state.record));
        }
        return switch (state) {
          AuthAuthenticated(:final record) => HomeScreen(
              store: widget.store,
              http: widget.http,
              record: record,
              onUnpaired: _refresh,
              pushService: widget.pushService,
              secureStore: widget.secureStore,
              outbox: _outboxService,
              attentionService: _attentionService,
              onEnsureAttention: _ensureAttention,
              kernel: widget.kernel,
              onApplyBackendPreference: widget.onApplyBackendPreference,
              onListUnifiedPushDistributors:
                  widget.onListUnifiedPushDistributors,
              onChooseUnifiedPushDistributor:
                  widget.onChooseUnifiedPushDistributor,
            ),
          AuthUnauthenticated() => PairingScreen(
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
}

// Convert a brain pair endpoint (e.g. `https://brain.example.com/pair`)
// to the bare origin base URL the ReplClient expects.  Mirrors the
// private `_baseUrlFromBrainEndpoint` helper in home_screen.dart so
// AuthRouter can build its own ReplClient without importing that file.
String _brainBaseUrl(String pairEndpoint) {
  final uri = Uri.parse(pairEndpoint);
  final base = uri.replace(
    pathSegments: const <String>[],
    queryParameters: null,
  ).toString();
  return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
}

```
