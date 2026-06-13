---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/main.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.849493+00:00
---

# archive/apps-semantos-monolith/lib/main.dart

```dart
// Semantos shell entrypoint.
//
// Wires up top-level state — ChildCertStore (flutter_secure_storage
// adapter) + a Dio instance shared by all shell clients — and hands
// off to the auth-gated router in `src/app.dart`.
//
// After authentication, HomeScreen adds a WalletHeaderInterceptor to
// the Dio instance (X-Brain-Cert + X-Brain-Capabilities).  Removed
// on dispose/logout so subsequent PairingScreen requests are clean.
//
// Push (Firebase / UnifiedPush) initialised before runApp() so
// terminated-app taps route correctly via navigatorKey.  PushRegistrationService
// passed down via AuthRouter → HomeScreen.

import 'dart:io' show Platform;

import 'package:dio/dio.dart';
// 2026-05-06 — firebase_core import temporarily removed so the iOS
// Simulator build resolves.  Restore alongside pubspec.yaml's
// firebase_core + firebase_messaging when re-enabling push on iOS.
// import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:semantos_ffi/semantos_ffi.dart' show SemantosKernel;

import 'src/app.dart';
import 'src/identity/child_cert_store.dart';
import 'src/identity/flutter_secure_store_adapter.dart';
import 'src/push/firebase_push_adapter.dart';
import 'src/push/push_handlers.dart';
import 'src/push/push_registration_service.dart';
import 'src/push/unified_push_adapter.dart';
import 'src/ratification/ratification_route.dart';
import 'src/theme/theme_service_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final secureStore = FlutterSecureStoreAdapter();
  final certStore = ChildCertStore(secureStore);
  // Smoke-test pass #1, fix #12 — bound REPL HTTP timeouts.
  // Pre-fix the default Dio had no connect / receive timeouts, so a
  // hung tunnel (cloudflared zombie, dropped phone connection, etc.)
  // could leave a fetch outstanding indefinitely.  Combined with the
  // Global Dio timeouts.  connectTimeout stays tight (10s) — if the
  // brain is unreachable we want to fail fast.  receiveTimeout and
  // sendTimeout are raised to 30s: the brain's `find jobs` REPL
  // command scans the loom index and can take 15–25 s on rbs under
  // load.  LLM and voice-transcription calls override further to
  // 60–90s at the call site (ReplClient.send receiveTimeout param).
  final http = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout: const Duration(seconds: 30),
  ));
  final navKey = GlobalKey<NavigatorState>();

  // Best-effort Firebase boot.  If `GoogleService-Info.plist` /
  // `google-services.json` are placeholders (the runbook explains
  // how to swap real values in at deploy time), Firebase.initializeApp
  // logs an error but the app continues to function with push
  // disabled.  PushRegistrationService surfaces the lack of a token
  // as PushUnsupported.
  //
  // Sovereign-push D.3: on Android also construct a [UnifiedPushAdapter]
  // and wire it as the PRIMARY adapter (with Firebase as the
  // fallback), honouring the operator's stored backend preference.
  // iOS skips UP entirely — Apple's sandbox bans alternative wakes.
  PushRegistrationService? pushService;
  UnifiedPushAdapter? upAdapter;
  try {
    // 2026-05-06 — Firebase.initializeApp() temporarily commented out
    // along with firebase_core/firebase_messaging in pubspec.yaml.
    // FirebasePushAdapter is now a no-op stub so the catch block won't
    // fire just from Firebase being unavailable; the no-op adapter
    // returns null tokens and PushRegistrationService treats that as
    // push-disabled (Android still uses UnifiedPushAdapter as primary).
    // Restore alongside the pubspec deps when re-enabling iOS push.
    // await Firebase.initializeApp();
    await setupPushHandlers(navKey: navKey);
    final fcmAdapter = FirebasePushAdapter();
    if (Platform.isAndroid) {
      upAdapter = UnifiedPushAdapter();
    }
    // Decide initial primary based on the persisted preference.  On
    // first launch the preference defaults to UnifiedPush
    // (sovereignty-first); registerOnPair falls back to FCM if no
    // distributor is installed.
    PushPlatformAdapter primary = fcmAdapter;
    PushPlatformAdapter? fallback;
    if (Platform.isAndroid && upAdapter != null) {
      final raw =
          await secureStore.read('d-o5m.v3.push_backend_preference') ?? '';
      final pref = PushBackendPreference.fromJson(raw) ??
          PushBackendPreference.unifiedpush;
      if (pref == PushBackendPreference.unifiedpush) {
        primary = upAdapter;
        fallback = fcmAdapter;
      }
    }
    pushService = PushRegistrationService(
      certStore: certStore,
      secureStore: secureStore,
      dio: http,
      adapter: primary,
      fallbackAdapter: fallback,
      // The brain base URL is recovered from the persisted child
      // cert at registration time — see HomeScreen wiring.  We pass
      // an empty placeholder here so the field has a sensible
      // default; HomeScreen reconstructs the service with the real
      // URL once a paired record is loaded.
      brainBaseUrl: '',
    );
  } catch (e, st) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[push] Firebase init failed (push disabled): $e\n$st');
    }
    pushService = null;
  }

  // Sovereign-push D.3 — closures the SettingsScreen invokes when
  // the operator picks a different backend / distributor.  Captured
  // here so the implementation can build a fresh
  // FirebasePushAdapter / UnifiedPushAdapter pair on demand.
  final svc = pushService;
  Future<PushRegistrationResult> Function(PushBackendPreference)?
      onApplyBackendPreference;
  Future<List<String>> Function()? onListUnifiedPushDistributors;
  Future<void> Function(String)? onChooseUnifiedPushDistributor;
  if (svc != null && Platform.isAndroid && upAdapter != null) {
    final fcmAdapter = FirebasePushAdapter();
    final up = upAdapter; // capture non-null for closure
    onApplyBackendPreference = (PushBackendPreference pref) async {
      await svc.writeBackendPreference(pref);
      // Tear down any existing token-refresh listener; swapAdapters
      // doesn't touch it (the old subscription was on the previous
      // primary's stream).
      await svc.stop();
      if (pref == PushBackendPreference.unifiedpush) {
        svc.swapAdapters(primary: up, fallback: fcmAdapter);
      } else {
        svc.swapAdapters(primary: fcmAdapter, fallback: null);
      }
      final result = await svc.registerOnPair();
      svc.startTokenRefreshListener();
      return result;
    };
    onListUnifiedPushDistributors = () => up.getDistributors();
    onChooseUnifiedPushDistributor = (d) => up.saveDistributor(d);
  }

  // D-O5.followup-6 — per-tenant theme.  ThemeService is constructed
  // here so the first MaterialApp build can consume the cached value;
  // a call to warmFromCache() seeds the notifier from SecureStore.
  // HomeScreen kicks off `fetch()` post-pairing so the operator's
  // brand colors land as soon as the brain is reachable.
  final themeService = ThemeService(
    certStore: certStore,
    secureStore: secureStore,
    dio: http,
  );
  await themeService.warmFromCache();

  // 2026-05-07 — bring up the SemantosKernel as a process singleton so
  // the on-device L1→L4 typed-NL pipeline can re-use the same FFI
  // context for every turn.  Best-effort: the FFI may not be loadable
  // on the iOS Simulator (lacks the platform binary on some configs)
  // or in the dev harness, in which case OnDeviceVoiceFactory's
  // typed-NL path falls through to TextIntentPipelineUnavailable
  // (the input bar renders the matching honest message).
  SemantosKernel? kernel;
  try {
    debugPrint('[kernel] constructing SemantosKernel');
    final k = SemantosKernel();
    debugPrint('[kernel] calling initialize');
    await k.initialize('{}');
    kernel = k;
    debugPrint('[kernel] initialized — typed-NL pipeline available');
  } catch (e, st) {
    // Log unconditionally — kDebugMode-gated print was hiding this in
    // release builds.  On the operator's S20 FE (release APK) this is
    // catching SOMETHING and the typed-NL pipeline silently downgrades
    // to TextIntentPipelineUnavailable; we need to see the exception
    // type + stack to know whether it's a missing libsemantos.so, a
    // kernel-init error, or something else.
    debugPrint('[kernel] init FAILED — typed-NL pipeline disabled: $e');
    debugPrint('[kernel] stack: $st');
    kernel = null;
  }

  runApp(OddjobzMobileApp(
    store: certStore,
    secureStore: secureStore,
    http: http,
    navigatorKey: navKey,
    pushService: pushService,
    themeService: themeService,
    kernel: kernel,
    onApplyBackendPreference: onApplyBackendPreference,
    onListUnifiedPushDistributors: onListUnifiedPushDistributors,
    onChooseUnifiedPushDistributor: onChooseUnifiedPushDistributor,
  ));
}

class OddjobzMobileApp extends StatelessWidget {
  final ChildCertStore store;
  final SecureStore secureStore;
  final Dio http;
  final GlobalKey<NavigatorState> navigatorKey;

  /// Nullable so the dev harness + early boot paths (where Firebase
  /// init failed) still build a working app.  HomeScreen treats
  /// null as "push disabled" and skips the registerOnPair call.
  final PushRegistrationService? pushService;

  /// D-O5.followup-6 — per-tenant theme.  Listened to via
  /// ValueListenableBuilder so MaterialApp rebuilds on every successful
  /// fetch from the brain's `/api/v1/info` endpoint.
  final ThemeService themeService;

  /// 2026-05-07 — initialised SemantosKernel (or null when the FFI
  /// failed to load).  Forwarded via AuthRouter into HomeScreen so
  /// OnDeviceVoiceFactory can wire the typed-NL on-device L1→L4
  /// pipeline.  Null on dev harnesses without the FFI.
  final SemantosKernel? kernel;

  /// Sovereign-push D.3 — Settings → Push backend picker callbacks.
  /// Forwarded straight through to AuthRouter → HomeScreen →
  /// SettingsScreen.  Null on iOS (APNs only) and on Android dev
  /// builds without push wiring.
  final Future<PushRegistrationResult> Function(PushBackendPreference)?
      onApplyBackendPreference;
  final Future<List<String>> Function()? onListUnifiedPushDistributors;
  final Future<void> Function(String)? onChooseUnifiedPushDistributor;

  const OddjobzMobileApp({
    super.key,
    required this.store,
    required this.secureStore,
    required this.http,
    required this.navigatorKey,
    required this.pushService,
    required this.themeService,
    this.kernel,
    this.onApplyBackendPreference,
    this.onListUnifiedPushDistributors,
    this.onChooseUnifiedPushDistributor,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TenantTheme>(
      valueListenable: themeService.theme,
      builder: (context, theme, child) {
        return MaterialApp(
          title: 'oddjobz mobile',
          navigatorKey: navigatorKey,
          theme: toMaterialTheme(theme),
          darkTheme: toMaterialDarkTheme(theme),
          themeMode: toFlutterThemeMode(theme.mode),
          // D-O5m.followup-7 Phase B — register the `/ratify` route so
          // PushNotificationRouter's deep-link push (#328) lands on the
          // RatificationCardScreen instead of falling through to
          // onUnknownRoute.  HomeScreen sets RatificationClientHolder.active
          // on mount; the route factory looks it up at push time.  Returning
          // null for non-`/ratify` names lets the home: child resolve other
          // routes via its own Navigator stack.
          onGenerateRoute: buildRatificationRoute,
          home: AuthRouter(
            store: store,
            secureStore: secureStore,
            http: http,
            pushService: pushService,
            themeService: themeService,
            kernel: kernel,
            onApplyBackendPreference: onApplyBackendPreference,
            onListUnifiedPushDistributors: onListUnifiedPushDistributors,
            onChooseUnifiedPushDistributor: onChooseUnifiedPushDistributor,
          ),
        );
      },
    );
  }
}

```
