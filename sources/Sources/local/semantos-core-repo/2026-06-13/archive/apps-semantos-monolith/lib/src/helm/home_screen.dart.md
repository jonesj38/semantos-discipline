---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/helm/home_screen.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.895660+00:00
---

# archive/apps-semantos-monolith/lib/src/helm/home_screen.dart

```dart
// D-O5m — Home screen.
//
// Helm v7 five-node dock shell for a paired device.
//
// Nodes:
//   0 — Home   (HomeNode)  jobs grouped by stage; live-visit pip
//   1 — Do     (DoNode)    verb shelf; SlideToCommit for transitions
//   2 — Talk   (TalkNode)  voice + typed-NL input; mic FAB
//   3 — Find   (FindNode)  unified 5-tab find surface
//   4 — Self   (SelfNode)  personal-practice flows (T7.b, 2026-05-25)
//                          — release / intention / vacuum etc., minted
//                          as self.practice.* cells
//
// Settings pushed as a modal route from the AppBar gear button.
//
// Voice pipeline (D-O5m.followup-3):
//   Phase 1 — Whisper STT on-device → transcript → brain L0–L4
//   Phase 2 — Whisper STT + llama.cpp SIR extraction → sir_candidate
//             multipart + transcript → brain skips L0→L1
//   Phase 3 — full on-device L1→L4 via DartIntentPipeline (future)
//
// OnDeviceVoiceFactory initialises asynchronously after mount so the
// first frame never blocks on model-manager setup.  Until it resolves
// the TalkNode mic button is disabled; the typed-NL bar surfaces
// "extractor unavailable".

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:semantos_ffi/semantos_ffi.dart'
    show SemantosKernel, SqfliteStorageAdapter;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:uuid/uuid.dart';

import '../contacts/contacts_repository.dart';
import '../identity/child_cert_store.dart';
import '../identity/secure_signing_key.dart';
import '../outbox/outbox_db.dart';
import '../outbox/outbox_service.dart';
import '../pask/pask_session_service.dart';
import '../pask/sqlite_pask_snapshot_store.dart';
import '../self/flow_def.dart';
import '../self/scan_screen.dart';
import '../self/self_flow_minter.dart';
import '../self/self_node.dart';
import '../push/push_registration_service.dart';
import '../gradient/dart_pipeline.dart' as pipe;
import '../gradient/intent_inspector_sheet.dart';
import '../gradient/intent_trace_service.dart';
import '../gradient/oddjobz_extension_context.dart';
import '../gradient/production_pipeline_deps.dart' as pipe_deps;
import '../ratification/ratification_queue_client.dart';
import '../ratification/ratification_route.dart';
import '../repl/attention_service.dart';
import '../repl/conversation_send_api.dart';
import '../repl/conversation_turns_repository.dart';
import '../repl/search_contacts_api.dart';
import '../repl/customers_repository.dart';
import '../repl/event_subscription_service.dart';
import '../repl/messagebox_api.dart';
import '../repl/hat_context.dart';
import '../repl/helm_event_stream.dart';
import '../repl/invoices_repository.dart';
import '../repl/hat_entity_repository.dart';
import '../repl/jobs_repository.dart';
import '../repl/oddjobz_query_client.dart';
import '../repl/quotes_repository.dart';
import '../repl/repl_client.dart';
import '../repl/visits_repository.dart';
import '../sensors/voice_memo_capture.dart';
import '../voice/on_device_voice_factory.dart';
import '../voice/sir_extractor.dart' as sir;
import '../voice/text_intent_service.dart';
import '../voice/voice_command_service.dart';
import '../voice/voice_extract_uploader.dart';
import 'attention_screen.dart';
import 'calendar_screen.dart';
import 'messages_screen.dart';
import 'conflicts_screen.dart';
import 'do_node.dart';
import 'find_node.dart';
import 'home_node.dart';
import 'ratify_tray_screen.dart';
import 'settings_screen.dart';
import 'talk_node.dart';
import '../talk/talk_surface_service.dart';
import 'voice_command_sheet.dart';
import 'voice_text_input_bar.dart';
import 'package:semantos_core/semantos_core.dart' show CartridgeDescriptor;
import '../shell/cartridge_entry.dart';
import '../shell/shell_nav.dart';
import '../shell/interceptors/wallet_header_interceptor.dart';
import '../shell/tabs/contacts_tab.dart';

class HomeScreen extends StatefulWidget {
  final ChildCertStore store;
  final Dio http;
  final ChildCertRecord record;
  final VoidCallback onUnpaired;

  /// D-O5m.followup-5 K1 — outbox status indicator + voice-sheet
  /// offline-enqueue.  Nullable so test rigs / dev harnesses without
  /// an outbox still build.
  final OutboxService? outbox;

  /// Tier 2P Phase D.2 — attention service.  Nullable so test rigs and
  /// dev harnesses that don't wire the attention service still build.
  /// HomeScreen manages polling lifecycle (start/pause) via
  /// WidgetsBindingObserver and calls [onEnsureAttention] once to
  /// hand back the live HelmEventStream so AuthRouter can construct
  /// the service after the stream is open.
  final AttentionService? attentionService;

  /// Callback from AuthRouter used to hand it the live HelmEventStream
  /// so it can construct the AttentionService after connect().  Nullable
  /// for the same reason as [attentionService].
  final Future<void> Function(ChildCertRecord, HelmEventStream)?
      onEnsureAttention;

  /// D-O5m.followup-9 Phase C — push notification registration.
  final PushRegistrationService? pushService;

  final SecureStore? secureStore;
  final SecureSigningKeyAdapter? secureSigningKeyAdapter;

  /// 2026-05-07 — initialised SemantosKernel for the on-device L1→L4
  /// typed-NL pipeline.  When non-null AND [outbox] is non-null,
  /// OnDeviceVoiceFactory builds a `DartIntentPipeline` so typed
  /// commands flow through the kernel locally and enqueue an
  /// `oddjobz.intent_cell.v1` envelope into the outbox.  Null on
  /// dev harnesses without the FFI loaded.
  final SemantosKernel? kernel;

  final Future<PushRegistrationResult> Function(PushBackendPreference pref)?
      onApplyBackendPreference;
  final Future<List<String>> Function()? onListUnifiedPushDistributors;
  final Future<void> Function(String distributorId)?
      onChooseUnifiedPushDistributor;

  const HomeScreen({
    super.key,
    required this.store,
    required this.http,
    required this.record,
    required this.onUnpaired,
    this.outbox,
    this.attentionService,
    this.onEnsureAttention,
    this.pushService,
    this.secureStore,
    this.secureSigningKeyAdapter,
    this.kernel,
    this.onApplyBackendPreference,
    this.onListUnifiedPushDistributors,
    this.onChooseUnifiedPushDistributor,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  // Shell nav state is now managed by ShellNav — tab index removed here.

  // Wallet-header interceptor — attached to widget.http at initState,
  // removed at dispose.  Adds X-Brain-Cert + X-Brain-Capabilities to
  // every outbound request for Phase-1 BRC-52 identity disclosure.
  WalletHeaderInterceptor? _walletInterceptor;

  late final ReplClient _repl = ReplClient.withBearer(
    http: widget.http,
    baseUrl: _baseUrlFromBrainEndpoint(widget.record.brainPairEndpoint),
    bearer: widget.record.bearer,
  );

  late final HelmEventStream _eventStream = HelmEventStream(
    wssUrl: widget.record.brainWssEndpoint,
    bearer: widget.record.bearer,
    topics: const [
      'jobs',
      'customers',
      'visits',
      'quotes',
      'invoices',
      'attachments',
      'leads',
    ],
  );

  // W1.1 — hat_entity_cache is opened asynchronously; the field starts
  // null and is set once the DB is ready.  JobsRepository accepts a
  // nullable HatEntityRepository so cold-start reads from the cache
  // and subsequent write-through both work as soon as it's available.
  HatEntityRepository? _hatEntityRepo;

  // W1.3 — pask session service wired to the pask_snapshots SQLite DB.
  // Null until the DB open completes (best-effort; DoNode tolerates null).
  PaskSessionService? _paskSession;

  // W1.4 — Pravega-bridged event subscription.  Connects to
  // /api/v1/events?hat=<domainFlag> once the hat_entity_cache DB is open
  // so the service can update the SQLite cache on every FSM transition.
  // Null until the DB is ready; disposed on logout/unpair.
  EventSubscriptionService? _eventSubscription;

  // D-network-messagebox-first-class — subscription to the push-notification
  // stream that fires whenever the brain stores an inbound message.
  // Cancelled in dispose() before _eventSubscription is disposed.
  StreamSubscription<MessageReceivedEvent>? _msgReceivedSub;

  // D-network-messagebox-first-class — API client + unread badge counter.
  // Constructed lazily once the brain base URL is available (same timing as
  // the event subscription, i.e. after _openHatEntityRepo resolves).
  // _newMessageCount bumps on each push notification and resets to 0 when
  // the user opens MessagesScreen.
  MessageboxApi? _messageboxApi;
  int _newMessageCount = 0;

  // W1.5 — Active hat context.  All SQLite queries, Pravega subscriptions,
  // and capability checks are scoped to this hat.  Call switchHat() to
  // change hat at runtime without restarting the app.
  HatContext _activeHat = HatContext.oddjobz;

  late final JobsRepository _jobs = JobsRepository(
    _repl,
    eventStream: _eventStream,
    entityCache: _hatEntityRepo,
  );
  late final CustomersRepository _customers =
      CustomersRepository(_repl, eventStream: _eventStream);
  late final VisitsRepository _visits =
      VisitsRepository(_repl, eventStream: _eventStream);
  late final QuotesRepository _quotes =
      QuotesRepository(_repl, eventStream: _eventStream);
  late final InvoicesRepository _invoices =
      InvoicesRepository(_repl, eventStream: _eventStream);
  late final RatificationQueueClient _ratification =
      RatificationQueueClient(_repl, eventStream: _eventStream);

  /// D-DOG.1.0c Phase 3 F.1 — graph-aware query client over WSS.
  /// Lifecycle is owned by HelmEventStream; this is a thin typed
  /// surface over `oddjobz.list_*` / `oddjobz.find_*` /
  /// `oddjobz.get_*`.  Used by the FindNode Jobs tab for the bulk
  /// site/customer enrichment pattern; F.2/F.3/F.4 will wire the
  /// other six verbs.
  late final OddjobzQueryClient _oddjobzQuery =
      OddjobzQueryClient(_eventStream);

  // Talk surface — contextually-ranked conversation windows.
  // Constructed lazily once the hat entity repo is ready so the
  // repo's queryConversations() can be wired in.  Null until then;
  // TalkNode renders without the 5-mode strip in the interim.
  TalkSurfaceService? _talkSurface;

  // Hat-scoped Plexus contact book.  Opened alongside the hat entity
  // repo so contacts are available to TalkSurfaceService on first render.
  ContactsRepository? _contacts;
  SqfliteStorageAdapter? _contactsStorage;

  // ── Outbox flush timer ────────────────────────────────────────────
  //
  // Tier 2P Phase A — periodic flush + reconnect-triggered flush.
  // A 30-second Timer.periodic drains the outbox while the app is
  // foregrounded.  The timer is paused on background and resumed on
  // foreground via [didChangeAppLifecycleState].  An additional flush
  // is triggered whenever the WSS transitions to [subscribed] (i.e.
  // the connection came back after an outage).

  Timer? _flushTimer;
  StreamSubscription<HelmEventStreamState>? _streamStateSub;

  static const _flushInterval = Duration(seconds: 30);

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => _triggerFlush());
  }

  void _stopFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  // Best-effort outbox flush.  Non-fatal — the next timer tick retries.
  void _triggerFlush() {
    final outbox = widget.outbox;
    if (outbox == null) return;
    // The flush adapter for generic (non-attachment, non-voice) entries:
    // the payloadJson IS the REPL command string per outbox_db.dart §Wire
    // format note.
    //
    // 2026-05-07 — typed-NL intent cells (cellType =
    // 'oddjobz.intent_cell.v1') ship their canonical envelope as
    // JSON in `payloadJson`, NOT as a REPL command string.  Render
    // them via the production_pipeline_deps adapter so the Semantos Brain
    // handler receives `submit-intent-cell --envelope <base64>`.
    // W1.2 — cellType/payloadJson are gone; the payload BLOB carries
    // the full cell envelope.  All entries route through the intent-cell
    // adapter which base64-wraps the raw envelope bytes so the Semantos Brain
    // handler receives `submit-intent-cell --envelope <base64>`.
    String? adapter(OutboxEntry entry) {
      return pipe_deps.renderIntentCellReplLine(entry.payload);
    }

    outbox.flush(adapter).catchError((Object e) {
      debugPrint('[outbox] flush error: $e');
      return FlushSummary(
          succeeded: 0,
          validationFailed: 0,
          retryable: 0,
          unauthorised: false);
    });
  }

  // ── Voice pipeline ────────────────────────────────────────────────
  //
  // OnDeviceVoiceFactory initialises async after mount.  Until it
  // resolves the TalkNode mic is disabled and TextIntentService
  // surfaces ExtractorUnavailable (prompts operator to use voice).

  OnDeviceVoiceFactory? _voiceFactory;
  TextIntentService _textIntent = TextIntentService();
  VoiceCommandService? _voiceCommandService;

  // Wave 9 follow-up — in-app trace recorder. Wired into the voice
  // factory's pipeline deps so every typed-NL turn streams its
  // PipelineStageEvents here. The AppBar inspector icon reads the
  // latest cascade from this service.
  final IntentTraceService _intentTrace = IntentTraceService();
  // 2026-05-07 — debug-visible error surface for OnDeviceVoiceFactory
  // init failures.  When non-null the AppBar shows a red error icon
  // that opens an AlertDialog with the actual exception + stack
  // trace, replacing the silent debugPrint that left operators with
  // a misleading "no on-device extractor configured. try voice
  // instead" error in the input bar.  Distinguish init-pending (both
  // null) from init-failed (factoryInitError set) so the input bar
  // can show the right message.
  String? _voiceFactoryInitError;
  StackTrace? _voiceFactoryInitStack;

  late final DioVoiceExtractUploader _voiceUploader =
      DioVoiceExtractUploader(
    http: widget.http,
    baseUrl: _baseUrlFromBrainEndpoint(widget.record.brainPairEndpoint),
    bearer: () => widget.record.bearer,
  );

  // W5 of CUSTOMER-CONV-LOOP-PLAN — Twilio SMS dispatch from contact
  // tiles in JobDetailScreen.  Reuses the same Dio + base-URL + bearer
  // plumbing as the voice uploader.
  late final ConversationSendApi _conversationSendApi = ConversationSendApi(
    http: widget.http,
    baseUrl: _baseUrlFromBrainEndpoint(widget.record.brainPairEndpoint),
    bearer: () => widget.record.bearer,
  );

  // Canonical conversation turns repository — feeds JobThreadScreen in
  // the HomeNode and FindNode via JobDetailScreen.  Uses the new
  // GET /api/v1/conversation/turns endpoint that stores canonical
  // `oddjobz.conversation.turn` rows in Postgres.
  late final ConversationTurnsRepository _conversationTurnsRepository =
      ConversationTurnsRepository(
    http: widget.http,
    baseUrl: _baseUrlFromBrainEndpoint(widget.record.brainPairEndpoint),
    bearer: () => widget.record.bearer,
  );

  // W6 — Talk|Direct search-contacts surface.
  late final SearchContactsApi _searchContactsApi = SearchContactsApi(
    http: widget.http,
    baseUrl: _baseUrlFromBrainEndpoint(widget.record.brainPairEndpoint),
    bearer: () => widget.record.bearer,
  );

  // BRAIN-GENERIC-MINT-VERB M4 — self-cartridge cell minter. Replaces
  // the T7.b debugPrint stub with the real POST /api/v1/cells call;
  // reuses the same Dio + base-URL + bearer plumbing as every other
  // brain client on this screen.
  late final SelfCellMinter _selfCellMinter = DioSelfCellMinter(
    http: widget.http,
    baseUrl: _baseUrlFromBrainEndpoint(widget.record.brainPairEndpoint),
    bearer: () => widget.record.bearer,
  );

  static const _uuid = Uuid();

  // Hat context — scoped to the operator's cert binding.
  sir.HatContext get _hatContext => sir.HatContext(
        hatId: widget.record.operatorCertId,
        certId: widget.record.childPubHex,
        extensionId: 'oddjobz',
        capabilities: const [1, 2],
      );

  // 2026-05-07 — Pipeline-side hat context, derived from the same
  // cert binding via the canonical helper in
  // `gradient/oddjobz_extension_context.dart`.  Used by
  // OnDeviceVoiceFactory to drive K3 (domain) + trust-class lowering
  // through `DartIntentPipeline`.
  pipe.PipelineHatContext get _pipelineHatContext =>
      oddjobzPipelineHatContext(widget.record);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Wallet-header interceptor — wire once at auth time, remove on dispose.
    // X-Brain-Cert discloses the device's BRC-42 child pubkey to the brain
    // so it can verify capability ownership without a separate handshake.
    _walletInterceptor = WalletHeaderInterceptor(
      bearer: widget.record.bearer,
      childPubHex: widget.record.childPubHex,
      capabilities: widget.record.capabilities,
    );
    widget.http.interceptors.add(_walletInterceptor!);

    _eventStream.connect();
    RatificationClientHolder.set(_ratification);

    // Tier 2P Phase A — start outbox flush timer + subscribe to WSS
    // reconnect events so we flush on every reconnect even if the
    // 30-second tick hasn't fired yet.
    // Tier 2P Phase D.2 — also trigger attention refresh on reconnect.
    if (widget.outbox != null || widget.onEnsureAttention != null) {
      if (widget.outbox != null) _startFlushTimer();
      _streamStateSub = _eventStream.stateStream.listen((state) {
        if (state == HelmEventStreamState.subscribed) {
          if (widget.outbox != null) _triggerFlush();
          widget.attentionService?.refresh();
        }
      });
    }

    // Tier 2P Phase D.2 — hand the live HelmEventStream back to
    // AuthRouter so it can construct the AttentionService.  Deferred
    // via microtask so the stream is in connecting state before the
    // callback fires.
    if (widget.onEnsureAttention != null) {
      scheduleMicrotask(
        () => widget.onEnsureAttention!(widget.record, _eventStream),
      );
    }

    final pushService = widget.pushService;
    if (pushService != null) {
      Future.microtask(() async {
        await pushService.registerOnPair();
        pushService.startTokenRefreshListener();
      });
    }

    // Seed TalkSurface immediately with stub cells so the 5-mode strip
    // always renders on first frame.  _openHatEntityRepo() replaces this
    // with the fully-wired service (repo + contacts) once the SQLite DB
    // opens.  If the DB open fails, the stub-only service stays active and
    // the strip keeps working.
    _talkSurface = TalkSurfaceService(hat: _activeHat);

    Future.microtask(_initVoiceFactory);
    Future.microtask(_openHatEntityRepo);
    // W1.3 — open the pask_snapshots DB and wire the session service.
    Future.microtask(_openPaskSession);
  }

  // W1.1 — open the hat_entity_cache SQLite DB and wire it into
  // _jobs so cold-start reads and subsequent write-throughs work.
  // Best-effort: if the open fails the cache stays null and the helm
  // simply falls back to a live REPL fetch on first load.
  Future<void> _openHatEntityRepo() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dbPath = '${docsDir.path}/hat_entity_cache.db';
      final raw = await sqflite.openDatabase(dbPath);
      final repo = await HatEntityRepository.fromDatabase(raw);
      if (!mounted) {
        await repo.close();
        return;
      }
      setState(() => _hatEntityRepo = repo);
      // Patch the already-constructed _jobs repository with the cache.
      // The late final JobsRepository is already created; we update
      // its internal field via the setter exposed for this purpose.
      _jobs.setEntityCache(repo);

      // W1.4 — Start the Pravega-bridged event subscription now that
      // the SQLite cache is open.  Events arrive as FSM transitions
      // happen on the brain and update the hat_entity_cache directly,
      // eliminating the 30 s AttentionService polling seam for
      // job-state freshness.
      _eventSubscription = EventSubscriptionService(
        brainWsUrl: _wsUrlFromBrainEndpoint(widget.record.brainWssEndpoint),
        bearer: widget.record.bearer,
        domainFlag: _activeHat.domainFlag,
        entityRepo: repo,
      );
      await _eventSubscription!.connect();

      // D-network-messagebox-first-class — subscribe to push notifications
      // for inbound messages.  The brain emits a "messagebox.received"
      // sentinel event via /api/v1/events whenever a caller POSTs to
      // /api/v1/messages/send; we surface this as a SnackBar + badge so
      // the user knows to check their inbox without polling.
      _messageboxApi ??= MessageboxApi(
        http: widget.http,
        localBrainBaseUrl: _baseUrlFromBrainEndpoint(
            widget.record.brainPairEndpoint),
        bearer: widget.record.bearer,
      );
      _msgReceivedSub?.cancel();
      _msgReceivedSub = _eventSubscription!.messageReceived.listen(
        _onMessageReceived,
      );

      // Open hat-scoped contact book so TalkSurface can show Plexus
      // contacts in the Direct mode strip.  Uses the operator's certId
      // as the hat namespace key — consistent with the BRC-42 derivation
      // that the brain performs for the same hat.
      final contactsStorage = SqfliteStorageAdapter(dbName: 'contacts.db');
      await contactsStorage.open();
      if (!mounted) {
        await contactsStorage.close();
        return;
      }
      final contacts = ContactsRepository(
        storage: contactsStorage,
        hatCertId: widget.record.operatorCertId,
      );

      // Talk surface — replace the stub-only service (seeded in initState)
      // with the fully-wired one now that repo + contacts are available.
      final oldSurface = _talkSurface;
      setState(() {
        _contacts = contacts;
        _contactsStorage = contactsStorage;
        _talkSurface = TalkSurfaceService(
          hat: _activeHat,
          attention: widget.attentionService,
          repo: repo,
          contacts: contacts,
        );
      });
      oldSurface?.dispose();
    } catch (e) {
      debugPrint('[hat_entity_cache] open failed: $e');
    }
  }

  // W1.3 — open the pask_snapshots SQLite DB and construct the
  // PaskSessionService.  The actual pask WASM calls (restoreCall /
  // interactAndSnapshot) are null here; they will be wired in a
  // future phase once the Flutter pask WASM bindings are available.
  // For now the service persists and loads snapshots without driving
  // the WASM directly.
  Future<void> _openPaskSession() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dbPath = '${docsDir.path}/pask_snapshots.db';
      final raw = await sqflite.openDatabase(dbPath);
      final store = await SqlitePaskSnapshotStore.fromDatabase(raw);
      if (!mounted) {
        await store.close();
        return;
      }
      final svc = PaskSessionService(
        store: store,
        // W1.5 — scoped to the active hat's domain flag.
        domainFlag: _activeHat.domainFlag,
        // restoreCall and interactAndSnapshot wired in Phase 4
        // once Flutter pask WASM bindings are available.
      );
      setState(() => _paskSession = svc);
      // Restore on first open so the graph is warm when the app starts.
      await svc.onResume();
    } catch (e) {
      debugPrint('[pask_session] open failed: $e');
    }
  }

  // W1.5 — Switch the active hat.  Closes and reopens services scoped
  // to the new hat's domain_flag; triggers a UI rebuild via setState.
  //
  // Steps:
  //   1. Update _activeHat state variable.
  //   2. Resubscribe EventSubscriptionService to the new hat's event stream.
  //   3. Reinitialise PaskSessionService with the new domainFlag.
  //      (HatEntityRepository is shared across hats — it's keyed by
  //       domain_flag per row, so no close/reopen is needed.)
  //   4. setState() rebuilds the UI scoped to the new hat.
  Future<void> switchHat(HatContext newHat) async {
    if (newHat == _activeHat) return;

    // Step 1 — update state immediately so the UI reflects the switch.
    setState(() => _activeHat = newHat);

    // Step 2 — resubscribe event stream to new hat.
    final sub = _eventSubscription;
    if (sub != null) {
      await sub.updateHat(newHat.domainFlag);
    }

    // Step 3 — reinitialise PaskSessionService for the new hat.
    // Close the old session before opening the new one.
    final oldSession = _paskSession;
    if (oldSession != null) {
      setState(() => _paskSession = null);
      await oldSession.close();
    }
    // Re-run the pask open for the new hat's domain_flag.
    // _openPaskSession reads _activeHat.domainFlag which was updated above.
    await _openPaskSession();
  }

  @override
  void didUpdateWidget(HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Tier 2P Phase D.2 — when AuthRouter supplies the AttentionService
    // for the first time (async construction completes and setState fires),
    // start polling immediately.  Subsequent rebuilds with the same
    // non-null service are a no-op because startPolling() is idempotent.
    if (widget.attentionService != null &&
        oldWidget.attentionService == null) {
      widget.attentionService!.startPolling();
    }
  }

  Future<void> _initVoiceFactory() async {
    try {
      // 2026-05-07 — pass the SemantosKernel (when initialised) and
      // the operator's outbox so OnDeviceVoiceFactory can wire the
      // production `DartIntentPipeline` for the typed-NL path.
      // Without both, the typed-NL service surfaces
      // TextIntentPipelineUnavailable instead of mysteriously freezing
      // on llama and dead-ending in the deps gap that bit us pre-fix.
      // 2026-05-08 — outboxDb is fetched LAZILY per-turn via the
      // closure `() => widget.outbox?.db` because AuthRouter's
      // _ensureOutbox runs in a microtask that can lose the race
      // against this _initVoiceFactory microtask.  Pre-fix the
      // factory captured a null outbox at create time and never
      // recovered when outbox arrived a moment later.
      final factory = await OnDeviceVoiceFactory.create(
        kernel: widget.kernel,
        outboxDbGetter: () => widget.outbox?.db,
        traceService: _intentTrace,
      );
      if (!mounted) {
        factory.dispose();
        return;
      }
      setState(() {
        _voiceFactory = factory;
        _textIntent = factory.buildTextIntentService(
          hatContext: _hatContext,
          pipelineHatContext: _pipelineHatContext,
          // Wave 9 follow-up — supply the active jobs cache so the
          // EntityResolver binds `target.jobId` / `customerId` before
          // each cell mint. Loader is invoked per-turn so cache
          // updates between turns are picked up. Returns [] on any
          // failure rather than throwing — resolution then surfaces
          // `entity_unresolved · no_active_jobs` in the inspector
          // and the cell still mints (just without a bound entity).
          activeJobsLoader: () async {
            try {
              return await _jobs.loadCached() ?? const [];
            } catch (_) {
              return const [];
            }
          },
        );
        _voiceCommandService = factory.buildVoiceCommandService(
          certStore: widget.store,
          hatContext: _hatContext,
          pipelineHatContext: _pipelineHatContext,
        );
        _voiceFactoryInitError = null;
        _voiceFactoryInitStack = null;
      });
    } catch (e, st) {
      // 2026-05-07 — surface init failures to the AppBar so operators
      // can see exactly why the voice/text-intent pipeline didn't come
      // up.  Pre-fix this was silent debugPrint and the input bar
      // showed the misleading "no on-device extractor configured.
      // Try voice instead." message even when voice was equally
      // broken because the entire factory failed to construct.
      debugPrint('OnDeviceVoiceFactory init failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _voiceFactoryInitError = '$e';
        _voiceFactoryInitStack = st;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _eventStream.forceReconnect();
      // Tier 2P Phase A — resume outbox flush timer on foreground.
      // The WSS reconnect above will also trigger a flush once the
      // connection comes back; the timer ensures we keep draining even
      // when the WSS is already subscribed.
      if (widget.outbox != null) {
        _startFlushTimer();
        _triggerFlush();
      }
      // Tier 2P Phase D.2 — resume attention polling on foreground.
      widget.attentionService?.startPolling();
      // W1.3 — restore pask graph state from the last saved snapshot.
      _paskSession?.onResume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Pause the flush timer + attention poll while backgrounded to
      // avoid unnecessary battery drain and network chatter.
      _stopFlushTimer();
      widget.attentionService?.pausePolling();
    }
  }

  @override
  void dispose() {
    // Remove the wallet-header interceptor from the shared Dio instance
    // before tearing down; prevents ghost headers on post-logout requests.
    final wi = _walletInterceptor;
    if (wi != null) {
      widget.http.interceptors.remove(wi);
      _walletInterceptor = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    RatificationClientHolder.clear();
    // Tier 2P Phase A — cancel the outbox flush timer + WSS
    // reconnect subscription before tearing down the event stream.
    _stopFlushTimer();
    _streamStateSub?.cancel();
    _eventStream.dispose();
    _jobs.dispose();
    _customers.dispose();
    _visits.dispose();
    _quotes.dispose();
    _invoices.dispose();
    _ratification.dispose();
    _voiceFactory?.dispose();
    // W1.1 — close the hat_entity_cache DB connection.
    _hatEntityRepo?.close();
    // W1.3 — close the pask_snapshots DB connection.
    _paskSession?.close();
    // D-network-messagebox-first-class — cancel message-received subscription
    // before disposing the event subscription service.
    _msgReceivedSub?.cancel();
    _msgReceivedSub = null;
    // W1.4 — dispose the event subscription service.
    _eventSubscription?.dispose();
    // Talk surface.
    _talkSurface?.dispose();
    // Contacts storage.
    _contactsStorage?.close();
    super.dispose();
  }

  // ── MessageBox notification handler ──────────────────────────────
  //
  // Called whenever the brain delivers a "messagebox.received" event.
  // Shows a SnackBar so the user knows to check their inbox.
  // Pull-on-push: the event carries the message ID; the full envelope
  // is fetched via GET /api/v1/messages/list?recipient=<pubkey>.

  void _onMessageReceived(MessageReceivedEvent event) {
    if (!mounted) return;
    setState(() => _newMessageCount++);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('New message received (${event.kind})'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'View',
          onPressed: _openMessages,
        ),
      ),
    );
  }

  void _openMessages() {
    final api = _messageboxApi;
    if (api == null) return;
    // Reset badge before navigating so the counter clears.
    setState(() => _newMessageCount = 0);
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MessagesScreen(
          api: api,
          // brainPinPubkey is the operator's compressed SEC1 pubkey (66 hex
          // chars) stored during pairing from GET /api/v1/info.  This is
          // exactly the key the remote sender addresses messages to.
          myPubkeyHex: widget.record.brainPinPubkey,
          messageReceived: _eventSubscription?.messageReceived,
        ),
      ),
    ).then((_) {
      // Reset badge on return in case they acked everything.
      if (mounted) setState(() => _newMessageCount = 0);
    });
  }

  // ── Mic handler ───────────────────────────────────────────────────

  VoiceMicHandler get _micHandler => (BuildContext ctx) async {
        final svc = _voiceCommandService;
        if (svc == null) {
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
            content: Text(
                'Voice pipeline initialising — try again shortly.'),
          ));
          return null;
        }
        // VoiceCommandSheet requires a non-null OutboxDb.  The outbox
        // is always wired in production (main.dart constructs it
        // before HomeScreen); guard here for test harness safety.
        final outboxDb = widget.outbox?.db;
        if (outboxDb == null) {
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
            content: Text('Outbox not ready — please try again.'),
          ));
          return null;
        }

        final result =
            await showModalBottomSheet<VoiceTextInputVoiceOutcome?>(
          context: ctx,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => VoiceCommandSheet(
            recorderFactory: () =>
                _RecordAdapterImpl(AudioRecorder()),
            commandService: svc,
            uploader: _voiceUploader,
            outboxDb: outboxDb,
            visitId: '',
            hatContext: widget.record.operatorCertId,
            correlationIdFactory: () => _uuid.v4(),
          ),
        );
        return result;
      };

  // ── Job-scoped voice note factory ─────────────────────────────────
  //
  // Phase 5 — D-OJ-conv-voice-intake.  Opens a VoiceCommandSheet with
  // the job's cellId + turnsRepository wired so the transcript is also
  // submitted as a ConversationTurn anchored to the job.
  //
  // Returns null (no button shown) when voice machinery isn't ready.
  Future<void> Function(
    BuildContext context,
    String jobCellId,
    ConversationTurnsRepository turns,
  )? get _openJobVoiceNote {
    final svc = _voiceCommandService;
    final outboxDb = widget.outbox?.db;
    if (svc == null || outboxDb == null) return null;
    return (BuildContext ctx, String jobCellId,
        ConversationTurnsRepository turns) async {
      await showModalBottomSheet<void>(
        context: ctx,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => VoiceCommandSheet(
          recorderFactory: () => _RecordAdapterImpl(AudioRecorder()),
          commandService: svc,
          uploader: _voiceUploader,
          outboxDb: outboxDb,
          visitId: '',
          hatContext: widget.record.operatorCertId,
          correlationIdFactory: () => _uuid.v4(),
          // Phase 5 — anchor transcript to this job's ConversationTurn.
          jobCellId: jobCellId,
          turnsRepository: turns,
        ),
      );
    };
  }

  // ── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(widget.record.label),
        actions: [
          // 2026-05-07 — voice/text-intent pipeline init error surface.
          // Operator sees a red error icon when OnDeviceVoiceFactory
          // failed to construct; tap → AlertDialog with the actual
          // exception + stack trace so they can copy-paste it for
          // debugging instead of getting the generic misleading
          // "no on-device extractor configured" message in the input
          // bar.
          if (_voiceFactoryInitError != null)
            IconButton(
              icon: const Icon(Icons.error_outline, color: Colors.red),
              tooltip: 'Voice pipeline init failed',
              onPressed: _showVoiceInitError,
            ),
          // Tier 2P Phase E.4 — pending-ratification badge.
          if (widget.attentionService != null)
            _RatifyBadge(
              attention: widget.attentionService!,
              onTap: _openRatifyTray,
            ),
          if (widget.outbox != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: OutboxStatusIndicator(
                outbox: widget.outbox!,
                onTapFailed: _openConflicts,
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _LiveIndicator(stream: _eventStream),
          ),
          // Wave 9 follow-up — intent-cascade inspector. Badge shows
          // the most recent action's outcome (✓ / ⨯ / …). Tap → modal
          // sheet rendering the full PipelineStageEvent cascade.
          _IntentInspectorBadge(trace: _intentTrace),
          // D-network-messagebox-first-class — messages inbox button.
          // Shows an unread badge when push notifications have arrived.
          if (_messageboxApi != null)
            Stack(
              alignment: Alignment.topRight,
              children: [
                IconButton(
                  icon: const Icon(Icons.mail_outline),
                  tooltip: 'Messages',
                  onPressed: _openMessages,
                ),
                if (_newMessageCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        child: Text(
                          '$_newMessageCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.calendar_month_outlined),
            tooltip: 'Calendar',
            onPressed: _openCalendar,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
        ],
      ),
      // Shell-native: cartridge-manifest-driven nav.
      // Tab order: Talk (shell) → Self (self cartridge) →
      //            Home / Do / Find (oddjobz cartridge).
      // Future: Contacts + Pask as additional shell-native tabs once
      //         their host widgets are extracted from this file.
      body: ShellNav(registry: _buildRegistry(), deps: _shellDeps),
    );
  }

  // ── Shell plumbing ────────────────────────────────────────────────

  ShellDeps get _shellDeps => ShellDeps(
        record: widget.record,
        repl: _repl,
        http: widget.http,
        baseUrl: _baseUrlFromBrainEndpoint(widget.record.brainPairEndpoint),
        // Shell-native services — nullable until async DB open completes.
        // ShellNav rebuilds when these become available because they're
        // read inside build() which is called on every setState().
        talkSurface: _talkSurface,
        contacts: _contacts,
        paskSession: _paskSession,
      );

  /// Build the cartridge registry for this session.
  ///
  /// Called on every build — entries are thin adapters backed by
  /// _HomeScreenState's own state fields, so construction is cheap.
  /// Once each cartridge's deps are extracted into its own host widget,
  /// the entries become stateless classes and this method moves to boot.
  ShellCartridgeRegistry _buildRegistry() {
    return ShellCartridgeRegistry([
      // ── Shell-native: Talk ─────────────────────────────────────────
      SimpleEntry(
        descriptor: const CartridgeDescriptor(
          id: 'shell.talk',
          routePath: '/talk',
          title: 'Talk',
          role: 'infra',
        ),
        icon: Icons.mic,
        label: 'Talk',
        builder: (_, deps) => TalkNode(
          textService: _textIntent,
          onMicTap: _micHandler,
          voiceFactory: _voiceFactory,
          talkSurface: deps.talkSurface,
          searchContactsApi: _searchContactsApi,
          conversationSendApi: _conversationSendApi,
          replClient: _repl,
        ),
      ),

      // ── Shell-native: Contacts (PKI contact book) ──────────────────
      SimpleEntry(
        descriptor: const CartridgeDescriptor(
          id: 'shell.contacts',
          routePath: '/contacts',
          title: 'Contacts',
          role: 'infra',
        ),
        icon: Icons.contacts,
        label: 'Contacts',
        builder: (_, deps) => ContactsTab(contacts: deps.contacts),
      ),

      // ── Self cartridge ─────────────────────────────────────────────
      SimpleEntry(
        descriptor: const CartridgeDescriptor(
          id: 'self',
          routePath: '/self',
          title: 'Self',
          role: 'experience',
        ),
        icon: Icons.self_improvement,
        label: 'Self',
        // BRAIN-GENERIC-MINT-VERB M4 — mints via POST /api/v1/cells.
        builder: (ctx, __) => SelfNode(
          onMint: (cellTypeName, fields) async {
            // Errors propagate to the caller (SelfNode._openFlow or
            // SelfSessionView._mint) which each have their own error snackbar.
            final result = await _selfCellMinter.mint(
              cellTypeName: cellTypeName,
              fields: fields,
            );
            return result.cellId;
          },
          sweepFetcher: () async {
            final baseUrl = _baseUrlFromBrainEndpoint(widget.record.brainPairEndpoint);
            final resp = await widget.http.get<Map<String, dynamic>>(
              '$baseUrl/api/v1/self/sweep',
              options: Options(
                headers: {'Authorization': 'Bearer ${widget.record.bearer}'},
                responseType: ResponseType.json,
                validateStatus: (_) => true,
              ),
            );
            if (resp.statusCode != 200 || resp.data == null) return null;
            final data = resp.data!;
            final themes = (data['primedThemes'] as List<dynamic>? ?? [])
                .map((t) => PrimedThemeData.fromJson(t as Map<String, dynamic>))
                .toList();
            return SelfSweepResult(
              primedThemes: themes,
              overallElevationEstimate:
                  (data['overallElevationEstimate'] as num?)?.toDouble() ?? 5.0,
            );
          },
        ),
      ),

      // ── Oddjobz cartridge ─────────────────────────────────────────
      // Three tabs contributed by the oddjobz cartridge.  Once the
      // oddjobz repo state is extracted into OddjobzCartridgeHost,
      // these entries move to packages/oddjobz_experience/.
      // Note: talkSurface sourced from deps (shell-native service) so
      // the oddjobz nodes don't reach past the cartridge boundary.
      SimpleEntry(
        descriptor: const CartridgeDescriptor(
          id: 'oddjobz.home',
          routePath: '/oddjobz/home',
          title: 'Home',
          role: 'experience',
        ),
        icon: Icons.home,
        label: 'Home',
        builder: (_, deps) => HomeNode(
          jobs: _jobs,
          visits: _visits,
          onUnauthorised: _onUnauthorised,
          attention: widget.attentionService,
          oddjobzQuery: _oddjobzQuery,
          talkSurface: deps.talkSurface,
          conversationSendApi: _conversationSendApi,
          turnsRepository: _conversationTurnsRepository,
          replClient: _repl,
          openVoiceNote: _openJobVoiceNote,
        ),
      ),
      SimpleEntry(
        descriptor: const CartridgeDescriptor(
          id: 'oddjobz.do',
          routePath: '/oddjobz/do',
          title: 'Do',
          role: 'experience',
        ),
        icon: Icons.bolt,
        label: 'Do',
        builder: (_, deps) => DoNode(
          jobs: _jobs,
          onUnauthorised: _onUnauthorised,
          paskSession: deps.paskSession,
          quotes: _quotes,
          entityRepo: _hatEntityRepo,
          hat: _activeHat,
          visits: _visits,
          talkSurface: deps.talkSurface,
          conversationSendApi: _conversationSendApi,
          turnsRepository: _conversationTurnsRepository,
          replClient: _repl,
        ),
      ),
      SimpleEntry(
        descriptor: const CartridgeDescriptor(
          id: 'oddjobz.find',
          routePath: '/oddjobz/find',
          title: 'Find',
          role: 'experience',
        ),
        icon: Icons.search,
        label: 'Find',
        builder: (_, deps) => FindNode(
          jobs: _jobs,
          customers: _customers,
          visits: _visits,
          quotes: _quotes,
          invoices: _invoices,
          onUnauthorised: _onUnauthorised,
          oddjobzQuery: _oddjobzQuery,
          turnsRepository: _conversationTurnsRepository,
          talkSurface: deps.talkSurface,
          conversationSendApi: _conversationSendApi,
          replClient: _repl,
        ),
      ),
    ]);
  }

  // ── Helpers ───────────────────────────────────────────────────────

  Future<void> _onUnauthorised() async {
    await widget.store.clear();
    widget.onUnpaired();
  }

  void _openRatifyTray() {
    final attention = widget.attentionService;
    if (attention == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RatifyTrayScreen(attention: attention),
      ),
    );
  }

  void _openConflicts() {
    final outbox = widget.outbox;
    if (outbox == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ConflictsScreen(outbox: outbox),
      ),
    );
  }

  // 2026-05-07 — show the captured OnDeviceVoiceFactory init error.
  // The user can copy the exception + stack trace via long-press or
  // by selecting the SelectableText.  Pre-fix this only landed in
  // debugPrint; operators couldn't see the actual cause without
  // adb logcat.
  void _showVoiceInitError() {
    final err = _voiceFactoryInitError;
    final st = _voiceFactoryInitStack;
    if (err == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Voice pipeline init failed'),
        content: SingleChildScrollView(
          child: SelectableText(
            'Exception:\n$err\n\n'
            'This blocks both typed natural-language input AND voice.\n'
            'The "no on-device extractor configured" message in the input '
            'bar is misleading — the real issue is below.\n\n'
            '${st ?? "(no stack trace captured)"}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _openCalendar() {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => CalendarScreen(
        jobs: _jobs,
        onUnauthorised: _onUnauthorised,
        turnsRepository: _conversationTurnsRepository,
        replClient: _repl,
      ),
    ));
  }

  // ignore: unused_element
  void _openAttention() {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => AttentionScreen(
        jobs: _jobs,
        onUnauthorised: _onUnauthorised,
        visits: _visits,
        talkSurface: _talkSurface,
        conversationSendApi: _conversationSendApi,
        turnsRepository: _conversationTurnsRepository,
        replClient: _repl,
      ),
    ));
  }

  void _openSettings() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(
          store: widget.store,
          record: widget.record,
          onUnpaired: widget.onUnpaired,
          pushService: widget.pushService,
          onMigrateToSecureKey: widget.secureSigningKeyAdapter == null
              ? null
              : () => _migrateSecureKey(),
          onApplyBackendPreference: widget.onApplyBackendPreference,
          onListUnifiedPushDistributors:
              widget.onListUnifiedPushDistributors,
          onChooseUnifiedPushDistributor:
              widget.onChooseUnifiedPushDistributor,
        ),
      ),
    );
  }

  Future<ChildCertRecord> _migrateSecureKey() async {
    final adapter = widget.secureSigningKeyAdapter;
    if (adapter == null) {
      throw const SecureSigningKeyUnsupported(
          'no SecureSigningKeyAdapter wired into HomeScreen');
    }
    final svc = _PairingServiceForMigration(
      store: widget.store,
      adapter: adapter,
    );
    return svc.migrate();
  }
}

// ── VoiceRecorderAdapter for the `record` package ────────────────────────

/// Wraps the `record` package's [AudioRecorder] behind
/// [VoiceRecorderAdapter] so [VoiceCommandSheet] stays plugin-free.
/// Records 16kHz mono WAV — the format whisper.cpp expects.
///
/// Permission note: VoiceCommandSheet calls Permission.microphone.request()
/// BEFORE constructing this adapter, so start() can assume permission is
/// already granted on Android/iOS.  The adapter does not re-check — the
/// single permission request in the sheet is the canonical gate.
class _RecordAdapterImpl implements VoiceRecorderAdapter {
  final AudioRecorder _rec;
  String? _lastPath;

  _RecordAdapterImpl(this._rec);

  @override
  Future<void> start() async {
    final dir = await getTemporaryDirectory();
    _lastPath =
        '${dir.path}/voice_cmd_${DateTime.now().millisecondsSinceEpoch}.wav';
    await _rec.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _lastPath!,
    );
  }

  @override
  Future<RecordedClip?> stop() async {
    final path = await _rec.stop();
    if (path == null) return null;
    final bytes = await File(path).readAsBytes();
    return RecordedClip(
      bytes: bytes,
      mimeType: 'audio/wav',
      reportedDurationMs: null,
    );
  }

  @override
  Future<void> cancel() async {
    await _rec.cancel();
    // Dispose the AudioRecorder so the OS mic resource is released.
    // The adapter is single-use; VoiceCommandSheet creates a fresh
    // recorderFactory() for each new recording session.
    await _rec.dispose();
  }
}

// ── Outbox status indicator ───────────────────────────────────────────────

class OutboxStatusIndicator extends StatelessWidget {
  final OutboxService outbox;
  final VoidCallback onTapFailed;
  const OutboxStatusIndicator({
    super.key,
    required this.outbox,
    required this.onTapFailed,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OutboxFailedEntry>>(
      stream: outbox.failedEntries,
      initialData: const <OutboxFailedEntry>[],
      builder: (context, snap) {
        final failed = snap.data ?? const <OutboxFailedEntry>[];
        if (failed.isNotEmpty) {
          return Tooltip(
            message: '${failed.length} failed — tap to view',
            child: GestureDetector(
              onTap: onTapFailed,
              child: _RedDotWithCount(count: failed.length),
            ),
          );
        }
        return _PendingCountDot(outbox: outbox);
      },
    );
  }
}

class _RedDotWithCount extends StatelessWidget {
  final int count;
  const _RedDotWithCount({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _PendingCountDot extends StatelessWidget {
  final OutboxService outbox;
  const _PendingCountDot({required this.outbox});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: outbox.pendingCount,
      initialData: 0,
      builder: (context, snap) {
        final pending = snap.data ?? 0;
        final hasPending = pending > 0;
        final color = hasPending ? Colors.amber : Colors.green;
        final tooltip =
            hasPending ? '$pending pending changes' : 'Outbox clear';
        return Tooltip(
          message: tooltip,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
        );
      },
    );
  }
}

// ── Live event stream indicator ───────────────────────────────────────────

class _LiveIndicator extends StatelessWidget {
  final HelmEventStream stream;
  const _LiveIndicator({required this.stream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<HelmEventStreamState>(
      stream: stream.stateStream,
      initialData: stream.state,
      builder: (context, snap) {
        final s = snap.data ?? HelmEventStreamState.disconnected;
        switch (s) {
          case HelmEventStreamState.subscribed:
            return const _Dot(color: Colors.greenAccent, tooltip: 'Live');
          case HelmEventStreamState.connecting:
          case HelmEventStreamState.reconnecting:
            return const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.amber),
              ),
            );
          case HelmEventStreamState.disconnected:
            return const _Dot(color: Colors.grey, tooltip: 'Offline');
        }
      },
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;
  final String tooltip;
  const _Dot({required this.color, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

// ── Migration helper ──────────────────────────────────────────────────────

class _PairingServiceForMigration {
  final ChildCertStore store;
  final SecureSigningKeyAdapter adapter;
  _PairingServiceForMigration({required this.store, required this.adapter});

  Future<ChildCertRecord> migrate() async {
    final existing = await store.read();
    if (existing == null) {
      throw const SecureSigningKeyError('NOT_PAIRED',
          'cannot migrate: device is not paired (no ChildCertRecord)');
    }
    if (existing.usesSecureKeyHandle) return existing;
    final material = await adapter.generateNew(label: existing.label);
    final pubHex = _hex(material.publicKey);
    final migrated = existing.copyWith(
      devicePrivHex: '',
      secureKeyHandle: material.keyHandle,
      childPubHex: pubHex,
    );
    await store.write(migrated);
    return migrated;
  }

  static String _hex(List<int> b) {
    final sb = StringBuffer();
    for (final x in b) {
      sb.write((x & 0xff).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

// ── Ratify badge ──────────────────────────────────────────────────────────

/// AppBar badge showing the count of pending ratifications.
///
/// Subscribes to [AttentionService.pendingRatifications] and renders a
/// [Badge] with the pending count when > 0.  Hidden (returns
/// [SizedBox.shrink]) when the stream emits 0 items.  Tap pushes
/// [RatifyTrayScreen] via the parent-supplied [onTap] callback so the
/// badge itself stays stateless about navigation.
class _RatifyBadge extends StatelessWidget {
  final AttentionService attention;
  final VoidCallback onTap;

  const _RatifyBadge({required this.attention, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<OddjobzDispatchDecision>>(
      stream: attention.pendingRatifications,
      initialData: const <OddjobzDispatchDecision>[],
      builder: (context, snap) {
        final count = snap.data?.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Tooltip(
            message: '$count pending ratification${count == 1 ? '' : 's'}',
            child: Badge.count(
              count: count,
              child: IconButton(
                icon: const Icon(Icons.rule_outlined),
                onPressed: onTap,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Intent inspector badge (Wave 9 follow-up) ─────────────────────────────

/// AppBar icon that opens the `IntentInspectorSheet`. Rebuilds when
/// the trace service notifies, so the marker reflects the latest
/// turn's outcome without any external state plumbing.
class _IntentInspectorBadge extends StatelessWidget {
  const _IntentInspectorBadge({required this.trace});

  final IntentTraceService trace;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: trace,
      builder: (ctx, _) {
        final latest = trace.latest;
        final cs = Theme.of(ctx).colorScheme;
        final hasLatest = latest != null;
        final color = latest == null
            ? cs.outline
            : latest.isRejected
                ? cs.error
                : latest.isCompleted
                    ? cs.primary
                    : cs.onSurfaceVariant;
        return IconButton(
          icon: Icon(Icons.troubleshoot_outlined, color: color),
          tooltip: hasLatest
              ? 'Intent inspector — last turn ${latest.isRejected ? "rejected" : latest.isCompleted ? "ok" : "in-flight"}'
              : 'Intent inspector — no traces yet',
          onPressed: () => IntentInspectorSheet.show(ctx, trace),
        );
      },
    );
  }
}

// ── URL helper ────────────────────────────────────────────────────────────

String _baseUrlFromBrainEndpoint(String pairEndpoint) {
  final uri = Uri.parse(pairEndpoint);
  final base = uri.replace(
    pathSegments: const <String>[],
    queryParameters: null,
  ).toString();
  return base.endsWith('/') ? base.substring(0, base.length - 1) : base;
}

/// W1.4 — Derive the WebSocket base URL from [brainWssEndpoint].
///
/// The event subscription service needs `ws://<host>/api/v1` (without
/// the trailing `/events` which it appends itself).  The existing WSS
/// endpoint for the helm wallet is `wss://<host>/api/v1/wallet`; we
/// strip the last path segment to get the `/api/v1` base.
String _wsUrlFromBrainEndpoint(String brainWssEndpoint) {
  final uri = Uri.parse(brainWssEndpoint);
  final segments = List<String>.from(uri.pathSegments);
  // Remove the trailing verb (e.g. "wallet") so we keep "/api/v1".
  if (segments.isNotEmpty) segments.removeLast();
  return uri
      .replace(pathSegments: segments, queryParameters: null)
      .toString()
      .replaceAll(RegExp(r'/$'), '');
}

```
