---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/lib/src/dispatch/intent_dispatcher.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.117511+00:00
---

# apps/semantos/lib/src/dispatch/intent_dispatcher.dart

```dart
/// intent_dispatcher.dart — bridge from StructuredIntent → brain cell mint.
///
/// Wire tick 3 of the canonical-PWA wiring plan (see
/// apps/semantos/docs/WIRING-PLAN.md).
///
/// Flow per the C7 V1 golden slice:
///   StructuredIntent (e.g. Release from betterment_experience)
///     ↓ resolve binding (intent type → cellType triple + payload builder)
///     ↓ buildTypeHash on the triple
///     ↓ CellMinter.mintCell(typeHashHex, payload) — cells.mint over WSS RPC
///     → MintCellResult { cellId, cartridgeId, cellType, persistedAt }
///
/// Cartridges register their intent bindings via [IntentDispatcher.register].
/// The dispatcher is generic — knows nothing about the betterment cartridge or
/// any other specific cartridge. New cartridge = add a binding, no
/// dispatcher edit needed.
///
/// SUPERSEDES bespoke per-cartridge dispatch handlers. Aligned with C9
/// surfacing-mode model: any cartridge with `ui.surfacingMode: default`
/// routes through the helm DO verb shelf which fires intents into this
/// dispatcher.
library;

import 'package:semantos_core/semantos_core.dart' show StructuredIntent;

import '../gradient/type_hash.dart';
import 'cell_minter.dart';

/// Build a JSON payload from a [StructuredIntent].
typedef PayloadBuilder<I extends StructuredIntent> = Map<String, dynamic>
    Function(I intent);

/// Registers a (StructuredIntent subtype) → (cellType triple + payload builder)
/// binding with the IntentDispatcher.
///
/// Cartridges create these with a typed [PayloadBuilder] of their concrete
/// intent subtype (e.g. `PayloadBuilder<Release>`); internally the binding
/// stores a wrapper that downcasts at call time. The Dart generic-erasure
/// trap (covariance over function parameter type) makes a fully-typed
/// generic field impossible to read polymorphically.
///
/// C9 PR-C9-7c additions:
///   - [intentTypeName] keys the binding for shell-driven dispatch by
///     string name (matches manifest `ui.verbs[].intentType`). The shell
///     calls [IntentDispatcher.dispatchByName] without importing the
///     cartridge's intent class.
///   - [defaultPayload] supplies cartridge-defined defaults that get
///     merged with the shell-provided payload. Keeps cartridge-specific
///     knowledge (e.g. "source defaults to 'keyboard'") in the cartridge.
class IntentBinding<I extends StructuredIntent> {
  /// Concrete StructuredIntent subtype this binding handles.
  /// Used for runtime type matching in dispatch().
  final Type intentType;

  /// String name keying this binding for shell-driven dispatch
  /// ([IntentDispatcher.dispatchByName]). Defaults to
  /// `intentType.toString()` — cartridges can override when the
  /// manifest's `ui.verbs[].intentType` uses a different identifier.
  final String intentTypeName;

  /// Cartridge id (matches cartridges/<id>/cartridge.json's `id`).
  /// Asserted equal to the brain response's cartridgeId at dispatch time.
  final String cartridgeId;

  /// CellType dotted name (e.g. 'betterment.practice.release').
  /// Used for assertions + telemetry.
  final String cellType;

  /// 4-segment triple matching cartridge.json's cellTypes[].triple field.
  /// Empty s4 is fine — buildTypeHash hashes the empty string deterministically.
  final String s1;
  final String s2;
  final String s3;
  final String s4;

  /// Type-erased payload builder. Cartridges supply a typed builder via the
  /// constructor; we wrap it here so the dispatcher can call it with the
  /// base StructuredIntent type without hitting Dart's covariance check.
  /// The runtimeType match in dispatch() already guarantees the cast is safe.
  final Map<String, dynamic> Function(StructuredIntent intent) erasedBuilder;

  /// Cartridge-defined default payload fields. Merged with the
  /// shell-provided payload in [IntentDispatcher.dispatchByName] (shell
  /// fields win on conflict). Lets cartridges keep their schema knowledge
  /// (required-but-defaulted fields) without the shell needing to know.
  final Map<String, dynamic> defaultPayload;

  IntentBinding({
    required this.intentType,
    String? intentTypeName,
    required this.cartridgeId,
    required this.cellType,
    required this.s1,
    required this.s2,
    required this.s3,
    this.s4 = '',
    required PayloadBuilder<I> payloadBuilder,
    this.defaultPayload = const {},
  })  : intentTypeName = intentTypeName ?? intentType.toString(),
        erasedBuilder = ((StructuredIntent i) => payloadBuilder(i as I));
}

/// Result of an intent → cell mint dispatch. Mirrors [MintCellResult]
/// from CellMinter + carries the matched binding for callers that
/// want to surface cellType/cartridgeId in helm cards.
class IntentDispatchResult {
  final MintCellResult mint;
  final IntentBinding<StructuredIntent> binding;
  const IntentDispatchResult(this.mint, this.binding);
}

/// Raised when no [IntentBinding] is registered for the dispatched intent
/// type. Surfaces clearly so cartridges know to call [IntentDispatcher.register].
class UnboundIntentError implements Exception {
  /// Type-keyed lookup miss. Null when the miss was name-keyed
  /// (see [intentTypeName]).
  final Type? intentType;

  /// Name-keyed lookup miss (e.g. shell dispatchByName('Release') with no
  /// matching binding). Null when the miss was Type-keyed.
  final String? intentTypeName;

  /// All registered intent types at lookup time — useful for diagnostics.
  final List<Type> registeredTypes;

  /// All registered intent type NAMES at lookup time.
  final List<String> registeredNames;

  UnboundIntentError(this.intentType, this.registeredTypes)
      : intentTypeName = null,
        registeredNames = const [];

  UnboundIntentError.named(String name, List<String> registered)
      : intentType = null,
        intentTypeName = name,
        registeredTypes = const [],
        registeredNames = registered;

  @override
  String toString() {
    if (intentTypeName != null) {
      return 'UnboundIntentError: no IntentBinding named "$intentTypeName" '
          '(registered: $registeredNames). The cartridge that owns this verb '
          'must call IntentDispatcher.register at boot.';
    }
    return 'UnboundIntentError: no IntentBinding for $intentType '
        '(registered: $registeredTypes)';
  }
}

/// A sovereign-mint authorisation: the operator's 64-byte (r‖s) signature
/// as 128 hex chars over `canonicaliseCellPayload(payload)` + the signer
/// cert id the brain looks up. See dispatch/signed_mint.dart.
typedef MintSignature = ({String signatureHex, String signerCertIdHex});

/// Produces a [MintSignature] for a mint payload, or null to fall back to an
/// unsigned mint (e.g. no identity loaded). When set on [IntentDispatcher],
/// non-null returns route the mint through `brain.mintCellSigned` (operator
/// authorises; brain #828 verifies before persisting).
typedef MintSigner = MintSignature? Function(Map<String, dynamic> payload);

/// Dispatches StructuredIntents to the brain via cells_mint_handler.
///
/// Single-purpose: wraps a [CellMinter] + a binding registry.
/// Construct one at shell boot per the WIRING-PLAN; cartridges register
/// their bindings at registerXCartridge() time.
class IntentDispatcher {
  /// The mint surface — M1.7b wires this to BrainRpcClient (`cells.mint` over
  /// the unified WSS channel); any [CellMinter] (incl. a test fake) works.
  final CellMinter brain;

  /// Optional sovereign-mint signer (C7-B). When set and it returns a
  /// [MintSignature] for the payload, the mint routes through
  /// `brain.mintCellSigned`; null (or a null return) ⇒ the unsigned
  /// `brain.mintCell` path. Lets the operator's hat key authorise mints
  /// without the dispatcher knowing anything about keys.
  final MintSigner? signer;
  final List<IntentBinding> _bindings = [];

  IntentDispatcher({required this.brain, this.signer});

  /// Register a typed binding. Must be called BEFORE any matching
  /// intent is dispatched. Idempotent on (intentTypeName, cellType) —
  /// repeat registration throws to surface ambiguous mappings.
  void register<I extends StructuredIntent>(IntentBinding<I> binding) {
    _assertNotDuplicate(binding.intentTypeName, binding.cellType);
    _bindings.add(binding);
  }

  /// C9 PR-C9-7c: register a name-only binding from cartridge-supplied
  /// spec data. The cartridge declares its intent metadata
  /// (intentTypeName, triple, default payload) without having to import
  /// the shell's IntentBinding / PayloadBuilder. The shell wraps the
  /// spec at boot.
  ///
  /// Bindings registered this way are dispatchable via
  /// [dispatchByName] only; calling [dispatch] with a typed intent
  /// won't match (no [IntentBinding.intentType] to key on).
  ///
  /// Idempotent on intentTypeName — duplicate registration throws.
  void registerSpec({
    required String intentTypeName,
    required String cartridgeId,
    required String cellType,
    required String s1,
    required String s2,
    required String s3,
    String s4 = '',
    Map<String, dynamic> defaultPayload = const {},
  }) {
    _assertNotDuplicate(intentTypeName, cellType);
    _bindings.add(_SpecBinding(
      intentTypeName: intentTypeName,
      cartridgeId: cartridgeId,
      cellType: cellType,
      s1: s1,
      s2: s2,
      s3: s3,
      s4: s4,
      defaultPayload: defaultPayload,
    ));
  }

  void _assertNotDuplicate(String intentTypeName, String cellType) {
    for (final existing in _bindings) {
      if (existing.intentTypeName == intentTypeName) {
        throw StateError(
          'IntentDispatcher: binding for "$intentTypeName" already registered '
          '(existing cellType: ${existing.cellType}, new: $cellType)',
        );
      }
    }
  }

  /// All registered intent types — useful for diagnostic output + helm
  /// verb shelf surfacing (which intents are available in the current
  /// cartridge context).
  List<Type> get registeredIntentTypes =>
      _bindings.map((b) => b.intentType).toList(growable: false);

  /// All registered intent NAMES (string keys). Used by the helm verb
  /// shelf to confirm a `ui.verbs[].intentType` actually has a binding
  /// before rendering the tile as tappable.
  List<String> get registeredIntentTypeNames =>
      _bindings.map((b) => b.intentTypeName).toList(growable: false);

  /// True when a binding exists for [intentType] (string name keyed).
  /// Cheap check the modal verb shelf uses to decide tappable vs
  /// "not yet wired" placeholder for declared verbs.
  bool hasBindingFor(String intentType) {
    for (final b in _bindings) {
      if (b.intentTypeName == intentType) return true;
    }
    return false;
  }

  /// Dispatch a structured intent → brain cell mint.
  ///
  /// Throws [UnboundIntentError] if no binding matches.
  /// Throws an RpcError on brain rejection (e.g. schema violation).
  Future<IntentDispatchResult> dispatch(StructuredIntent intent) async {
    final binding = _resolveBinding(intent);
    // erasedBuilder accepts StructuredIntent + casts internally to the
    // binding's concrete type. The _resolveBinding runtimeType match
    // already guarantees the cast succeeds.
    final payload = binding.erasedBuilder(intent);
    return _mintAndAssert(binding, payload);
  }

  /// C9 PR-C9-7c: dispatch by string intent name + raw payload map.
  ///
  /// Used by the shell's modal verb shelf where the shell collects
  /// input via a generic input sheet (driven by manifest
  /// `ui.verbs[].inputShape`) and posts the payload directly — no
  /// typed StructuredIntent class needed, no shell→cartridge import.
  ///
  /// The cartridge's binding's [IntentBinding.defaultPayload] gets
  /// merged BENEATH the supplied [payload] (caller-provided fields
  /// win). This lets cartridges declare required-but-defaulted
  /// fields (source/prompt/elevation for release) without the shell
  /// knowing what they are.
  Future<IntentDispatchResult> dispatchByName({
    required String intentType,
    required Map<String, dynamic> payload,
  }) async {
    final binding = _resolveBindingByName(intentType);
    return _mintAndAssert(binding, {
      ...binding.defaultPayload,
      ...payload,
    });
  }

  Future<IntentDispatchResult> _mintAndAssert(
    IntentBinding binding,
    Map<String, dynamic> payload,
  ) async {
    final hash = buildTypeHash(binding.s1, binding.s2, binding.s3, binding.s4);
    final thh = typeHashHex(hash);
    // C7-B sovereign mint — when a signer is wired and yields a signature,
    // submit the operator-signed mint; otherwise the unsigned path.
    final sig = signer?.call(payload);
    final mint = sig != null
        ? await brain.mintCellSigned(
            typeHashHex: thh,
            payload: payload,
            signatureHex: sig.signatureHex,
            signerCertIdHex: sig.signerCertIdHex,
          )
        : await brain.mintCell(
            typeHashHex: thh,
            payload: payload,
          );
    assert(
      mint.cartridgeId == binding.cartridgeId,
      'brain returned cartridgeId=${mint.cartridgeId}, binding expected ${binding.cartridgeId}',
    );
    assert(
      mint.cellType == binding.cellType,
      'brain returned cellType=${mint.cellType}, binding expected ${binding.cellType}',
    );
    return IntentDispatchResult(mint, binding);
  }

  IntentBinding _resolveBinding(StructuredIntent intent) {
    final t = intent.runtimeType;
    for (final b in _bindings) {
      if (b.intentType == t) return b;
    }
    throw UnboundIntentError(t, registeredIntentTypes);
  }

  IntentBinding _resolveBindingByName(String name) {
    for (final b in _bindings) {
      if (b.intentTypeName == name) return b;
    }
    throw UnboundIntentError.named(name, registeredIntentTypeNames);
  }
}

/// Private name-only binding used by [IntentDispatcher.registerSpec].
/// Carries no payload builder — spec bindings are exclusively for
/// shell-driven dispatch via [IntentDispatcher.dispatchByName]. Typed
/// dispatch via [IntentDispatcher.dispatch] can't accidentally match
/// because `intentType` is the abstract base class.
class _SpecBinding extends IntentBinding<StructuredIntent> {
  _SpecBinding({
    required String intentTypeName,
    required String cartridgeId,
    required String cellType,
    required String s1,
    required String s2,
    required String s3,
    String s4 = '',
    Map<String, dynamic> defaultPayload = const {},
  }) : super(
          intentType: StructuredIntent,
          intentTypeName: intentTypeName,
          cartridgeId: cartridgeId,
          cellType: cellType,
          s1: s1,
          s2: s2,
          s3: s3,
          s4: s4,
          defaultPayload: defaultPayload,
          payloadBuilder: (_) => throw StateError(
            'spec-only binding "$intentTypeName" registered via '
            'IntentDispatcher.registerSpec — call dispatchByName, not dispatch',
          ),
        );
}

```
