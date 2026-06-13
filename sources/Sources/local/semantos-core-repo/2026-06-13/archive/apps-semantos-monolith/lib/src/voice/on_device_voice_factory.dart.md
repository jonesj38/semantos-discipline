---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/voice/on_device_voice_factory.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.867734+00:00
---

# archive/apps-semantos-monolith/lib/src/voice/on_device_voice_factory.dart

```dart
// D-O5m.followup-3 — on-device voice pipeline factory.
//
// Bridges the abstract VoiceTranscriber / LlmCompleter seams defined in
// voice_command_service.dart and sir_extractor.dart onto:
//   - whisper_cpp FFI plugin for voice transcription (Whisper.base.en)
//   - AnthropicLlmCompleter for SIR extraction (claude-haiku-4-5 via API)
//
// llama_cpp was removed — on-device inference took ~5 min on field hardware
// (S20 FE) making the intent path unusable. Anthropic gives sub-second
// roundtrips. API key is baked in at build time:
//   flutter build apk --dart-define=ANTHROPIC_API_KEY=sk-ant-...
//
// The factory is constructed once in HomeScreen and its products are injected into:
//
//   - VoiceCommandService (whisper transcriber + sir extractor)
//   - TextIntentService   (sir extractor for typed-NL path)
//
// Model lifecycle:
//
//   - WhisperModelManager is constructed at factory init.
//   - Whisper model is downloaded on first use via ensureModelDownloaded(),
//     guarded behind isCached() — no download until the operator taps mic.
//   - The download progress stream is exposed so TalkNode can show progress.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:oddjobz_experience/oddjobz_experience.dart'
    show OddjobzManifestLoader;
import 'package:path_provider/path_provider.dart';
import 'package:semantos_core/semantos_core.dart' as core
    show ExtensionManifest, GrammarRegistry;
import 'package:semantos_ffi/semantos_ffi.dart' show SemantosKernel;
import 'package:uuid/uuid.dart' show Uuid;
import 'package:whisper_cpp/whisper_cpp.dart';

import '../gradient/dart_pipeline.dart' as pipe;
import '../gradient/intent_trace_service.dart';
import '../gradient/production_pipeline_deps.dart' as pipe_deps;
import '../repl/jobs_repository.dart' as job_repo;
import '../identity/child_cert_store.dart';
import '../outbox/outbox_db.dart';
import 'anthropic_llm_completer.dart';
import 'sir_extractor.dart';
import 'text_intent_service.dart';
import 'voice_command_service.dart';

/// Stable JSON encoding of a small map — keys are emitted in the
/// canonical order Dart's `jsonEncode` uses (insertion order), which
/// matches the Semantos Brain-side decoder's tolerance.  Used to render the
/// taxonomy `{what,how,why}` triple for the envelope without
/// inheriting `dart:convert`'s default behaviour drift between
/// Dart versions.
String _encodeJsonStable(Map<String, dynamic> m) => jsonEncode(m);

// ── VoiceTranscriber adapter ─────────────────────────────────────────────

/// Adapts [WhisperService] onto [VoiceTranscriber] so the voice command
/// service stays plugin-free at compile time (no whisper_cpp import in
/// the service itself).
class _WhisperAdapter implements VoiceTranscriber {
  final WhisperService _svc;
  const _WhisperAdapter(this._svc);

  @override
  Future<String> transcribe(Uint8List pcmAudioBytes,
      {String language = 'en'}) =>
      _svc.transcribe(pcmAudioBytes, language: language);
}

// ── Factory ─────────────────────────────────────────────────────────────

/// Constructs and wires the on-device voice pipeline.  Constructed once
/// per HomeScreen mount; [dispose] must be called on screen dispose.
class OnDeviceVoiceFactory {
  // ── Whisper side ──────────────────────────────────────────────────

  final WhisperModelManager whisperModelManager;
  late final WhisperService _whisperSvc;
  late final _WhisperAdapter _whisperAdapter;

  // ── Production pipeline deps ──────────────────────────────────────

  /// 2026-05-07 — wired when both an initialised [SemantosKernel] and
  /// the operator's [OutboxDb] are available.  When non-null,
  /// [buildTextIntentService] + [buildVoiceCommandService] also
  /// construct a [DartIntentPipeline] so typed-NL turns flow
  /// through L1→L4 fully on-device.  When either is null
  /// the typed-NL path falls through to
  /// `TextIntentPipelineUnavailable` (operator sees a meaningful
  /// inline message).
  ///
  /// 2026-05-08 — outboxDb is a GETTER, not a captured value.  The
  /// HomeScreen wires it as `() => widget.outbox?.db` so when the
  /// AuthRouter's _ensureOutbox microtask resolves AFTER
  /// _initVoiceFactory has already built the factory, the next
  /// typed-NL turn picks up the now-non-null outbox without us
  /// having to rebuild the factory.  Pre-fix: outbox was captured
  /// at create() time → factory baked in `null` and never recovered.
  final SemantosKernel? kernel;
  final OutboxDb? Function() outboxDbGetter;

  // ── Assembled products ────────────────────────────────────────────

  /// Ready-to-use SIR extractor — shared between VoiceCommandService
  /// and TextIntentService so both paths draw from the same LLM context.
  /// Null until [initAsync] resolves.
  SirExtractor? sirExtractor;

  /// Manifest-derived [ExtensionGrammar] for the active extension.
  /// Loaded from the bundled `oddjobz_experience` assets at boot via
  /// [OddjobzManifestLoader]; mirrors the same JSON the brain reducer
  /// consumes so the host-side confidence scorer no longer diverges
  /// from TRADES_GRAMMAR_SPEC. Falls back to the deprecated
  /// `ExtensionGrammar.oddjobz` constant only if manifest load fails
  /// (logged + visible in debug builds).
  ExtensionGrammar extensionGrammar = ExtensionGrammar.oddjobz;

  /// Grammar registry populated from the loaded manifest. Other shell
  /// subsystems (e.g. multi-experience hat routing) read from this.
  core.GrammarRegistry grammarRegistry = core.GrammarRegistry.empty();

  /// Active extension manifest (single-extension today; multi-extension
  /// when the unified shell lands).
  core.ExtensionManifest? activeManifest;

  /// Transcriber adapter for VoiceCommandService.
  VoiceTranscriber get transcriber => _whisperAdapter;

  /// Wave 9 follow-up — when set, every pipeline stage event from this
  /// factory's `DartIntentPipeline` is mirrored into the recorder so
  /// the `IntentInspectorSheet` widget can render the cascade for the
  /// user's last action. Optional — null keeps the previous log-only
  /// behaviour.
  final IntentTraceService? traceService;

  OnDeviceVoiceFactory._({
    required this.whisperModelManager,
    this.kernel,
    this.traceService,
    OutboxDb? Function()? outboxDbGetter,
  }) : outboxDbGetter = outboxDbGetter ?? (() => null) {
    _whisperSvc = WhisperService(modelManager: whisperModelManager);
    _whisperAdapter = _WhisperAdapter(_whisperSvc);
  }


  /// Construct + perform async init (load the grammar BNF from the
  /// bundled asset, build the SirExtractor).  Prefer using this over
  /// the default constructor so callers don't need to chain [initAsync].
  ///
  /// [kernel] + [outboxDb] are optional; both must be supplied (and
  /// the kernel must already be initialised) for the typed-NL path
  /// to run end-to-end through `DartIntentPipeline`.  When either is
  /// null the factory still builds — the typed-NL service surfaces
  /// `TextIntentPipelineUnavailable` so the input bar can render an
  /// honest message.
  static Future<OnDeviceVoiceFactory> create({
    SemantosKernel? kernel,
    OutboxDb? Function()? outboxDbGetter,
    IntentTraceService? traceService,
  }) async {
    final whisperMgr = WhisperModelManager(
      model: WhisperModel.baseEn,
      supportDirectory: getApplicationSupportDirectory,
    );
    final factory = OnDeviceVoiceFactory._(
      whisperModelManager: whisperMgr,
      kernel: kernel,
      outboxDbGetter: outboxDbGetter,
      traceService: traceService,
    );
    await factory._initAsync();
    return factory;
  }

  Future<void> _initAsync() async {
    // GBNF still loaded — AnthropicLlmCompleter ignores it, but it's kept
    // so the asset bundle doesn't need to change and an alternative backend
    // can be wired cheaply in future.
    final gbnf = await rootBundle.loadString('assets/llama/intent.gbnf');

    // SIR extractor is always backed by Anthropic's /v1/messages endpoint.
    // llama.cpp is no longer used — on-device inference was too slow for
    // field use (~5 min on S20 FE). Supply the key at build time:
    //   flutter build apk --dart-define=ANTHROPIC_API_KEY=sk-ant-...
    //
    // When the key is absent sirExtractor stays null → TextIntentService
    // surfaces TextIntentExtractorUnavailable with a clear inline message.
    const anthropicKey = String.fromEnvironment('ANTHROPIC_API_KEY');
    const anthropicModel = String.fromEnvironment(
      'ANTHROPIC_MODEL',
      defaultValue: 'claude-haiku-4-5',
    );
    if (anthropicKey.isNotEmpty) {
      debugPrint(
        '[voice] SIR extractor → Anthropic (model=$anthropicModel)',
      );
      sirExtractor = SirExtractor(
        completer: AnthropicLlmCompleter(
          apiKey: anthropicKey,
          model: anthropicModel,
        ),
        intentGrammarBNF: gbnf,
      );
    } else {
      debugPrint(
        '[voice] ANTHROPIC_API_KEY not set — SIR extractor disabled. '
        'Rebuild with --dart-define=ANTHROPIC_API_KEY=sk-ant-... to enable.',
      );
      sirExtractor = null;
    }

    // Load the oddjobz manifest from the bundled asset and build the
    // ExtensionGrammar + GrammarRegistry from it. Manifest is the source
    // of truth shared with the brain reducer (no Dart codegen, no hand-
    // maintained mirror). On failure we keep the deprecated default
    // constant so the voice path stays usable; debugPrint surfaces the
    // problem so it's visible in dev builds.
    try {
      final manifest = await OddjobzManifestLoader.load();
      activeManifest = manifest;
      extensionGrammar = ExtensionGrammar.fromManifest(manifest);
      grammarRegistry = core.GrammarRegistry.fromManifests([manifest]);
      debugPrint(
        '[voice] loaded extension manifest: ${manifest.id} v${manifest.version} '
        '(${manifest.grammar.actions.length} actions, '
        'lexicon=${manifest.grammar.lexicon.name})',
      );
    } catch (e, st) {
      debugPrint('[voice] manifest load failed — falling back to legacy '
          'ExtensionGrammar.oddjobz constant: $e\n$st');
    }
  }

  // ── Assembled VoiceCommandService ─────────────────────────────────

  /// Build a [VoiceCommandService] scoped to [certStore] + [hatContext].
  /// [sirExtractor] is injected when the Llama model has been downloaded
  /// and the grammar asset loaded; Phase 1 fallback applies when null.
  ///
  /// [pipelineHatContext] is plumbed for symmetry with
  /// [buildTextIntentService] but the voice path stays on the
  /// existing Phase 2 brain-side fallback in this slice — the voice
  /// recording uploads as a `voice_extract.v1` cell (with the optional
  /// SIR candidate) and the brain runs L2→L4.  Wiring the on-device
  /// pipeline through voice is a follow-up; the operator's immediate
  /// need is the typed-text path (PR #427+ stack).
  VoiceCommandService buildVoiceCommandService({
    required ChildCertStore certStore,
    HatContext? hatContext,
    pipe.PipelineHatContext? pipelineHatContext,
  }) =>
      VoiceCommandService(
        certStore: certStore,
        transcriber: _whisperAdapter,
        sirExtractor: sirExtractor,
        hatContext: hatContext,
        extensionGrammar: extensionGrammar,
        localPipeline: null,
        pipelineHatContext: pipelineHatContext,
      );

  // ── Assembled TextIntentService ───────────────────────────────────

  /// Build a [TextIntentService] for the typed-NL path.
  /// When [sirExtractor] is null (grammar not yet loaded / first launch)
  /// the service surfaces [TextIntentExtractorUnavailable] so the input
  /// bar can route to the brain-side fallback.
  ///
  /// [pipelineHatContext] enables the on-device L1→L4 pipeline when
  /// [kernel] + [outboxDb] are also wired; without it the typed-NL
  /// path returns [TextIntentPipelineUnavailable] (and the input bar
  /// renders the matching inline message).  See
  /// `oddjobz_extension_context.dart`.
  TextIntentService buildTextIntentService({
    HatContext? hatContext,
    pipe.PipelineHatContext? pipelineHatContext,
    Future<List<job_repo.Job>> Function()? activeJobsLoader,
  }) {
    final factory = _maybePipelineForIntentFactory(
      hatContext,
      pipelineHatContext,
    );
    return TextIntentService(
      sirExtractor: sirExtractor,
      hatContext: hatContext,
      extensionGrammar: extensionGrammar,
      pipelineForIntent: factory,
      pipelineHatContext: pipelineHatContext,
      // Wave 9 follow-up — surfaces synthetic intent_produced +
      // intent_rejected events into the inspector even when the
      // typed-NL path short-circuits before the pipeline runs.
      traceService: traceService,
      // Wave 9 follow-up — when the caller supplies a loader for
      // active jobs (e.g. `() => jobsRepo.loadCached() ?? []`), the
      // service runs the EntityResolver against that list and patches
      // intent.target.jobId / customerId before the cell is minted.
      activeJobsLoader: activeJobsLoader,
    );
  }

  /// 2026-05-07 — internal helper that builds a per-turn
  /// `pipelineForIntent` factory closure when production deps are
  /// available.  Returns null when [kernel] / [outboxDb] /
  /// [pipelineHatContext] / [hatContext] are missing, which lets the
  /// caller surface the right typed failure
  /// (`TextIntentPipelineUnavailable`) to the operator.
  ///
  /// The factory is invoked per typed-NL turn with the SIR-extracted
  /// intent so the deps' writeCell can render the canonical
  /// envelope's `originalIntent` fields (summary / action /
  /// taxonomy) without re-parsing the cell bytes.
  pipe.DartIntentPipeline? Function(Map<String, dynamic> intent)?
      _maybePipelineForIntentFactory(
    HatContext? hatContext,
    pipe.PipelineHatContext? pipelineHatContext,
  ) {
    final k = kernel;
    final ph = pipelineHatContext;
    if (k == null || ph == null || hatContext == null) {
      return null;
    }
    final hatId = ph.hatId;
    final certId = ph.certId ?? hatContext.certId ?? '';
    final uuid = const Uuid();
    return (Map<String, dynamic> intent) {
      // 2026-05-08 — fetch outboxDb lazily.  AuthRouter opens the
      // outbox in a microtask that races _initVoiceFactory; on the
      // operator's S20 FE the voice factory was winning that race
      // and capturing a null outbox.  Per-turn lookup means we pick
      // up the outbox as soon as it's open, no factory rebuild
      // needed.  If still null when the operator types, return null
      // → TextIntentPipelineUnavailable so the inline message is
      // honest.
      // ignore: avoid_print
      final db = outboxDbGetter();
      if (db == null) {
        // ignore: avoid_print
        print('[factory] pipelineForIntent: outboxDb null at turn time');
        return null;
      }
      final summary = (intent['summary'] as String?)?.trim() ?? '';
      final action = (intent['action'] as String?)?.trim() ?? 'note';
      final taxonomy = intent['taxonomy'];
      final taxonomyJson = taxonomy is Map<String, dynamic>
          ? _encodeJsonStable(taxonomy)
          : '{}';
      // Wave 9 follow-up — hoist Intent.target onto the envelope so
      // the brain's intent_action_router can address entities by
      // resolved id instead of regex-matching `intent_summary` tokens
      // against the customer-name column.
      final target = intent['target'];
      final targetJson = (target is Map<String, dynamic> && target.isNotEmpty)
          ? _encodeJsonStable(target)
          : '';
      return pipe.DartIntentPipeline(
        pipe_deps.buildProductionPipelineDeps(
          kernelExecute: k.executeScript,
          outboxDb: db,
          hatId: hatId,
          certId: certId,
          intentSummary: summary,
          intentAction: action,
          intentTaxonomyJson: taxonomyJson,
          intentTargetJson: targetJson,
          uuid: uuid.v4,
          traceService: traceService,
        ),
      );
    };
  }

  // ── Model download helpers ────────────────────────────────────────

  /// Whether the Whisper model is already cached on disk.
  Future<bool> isWhisperModelCached() => whisperModelManager.isCached();

  /// Start downloading the Whisper model if not already cached.
  /// [onProgress] fires with each [WhisperModelDownloadProgress] chunk
  /// so the UI can show a progress bar.  Resolves `true` when the model
  /// is ready, `false` on failure.
  Future<bool> ensureWhisperModel({
    void Function(WhisperModelDownloadProgress)? onProgress,
  }) =>
      whisperModelManager.ensureModelDownloaded(onProgress: onProgress);

  void dispose() {
    // No long-lived handles to release — FFI contexts are per-call.
  }
}

```
