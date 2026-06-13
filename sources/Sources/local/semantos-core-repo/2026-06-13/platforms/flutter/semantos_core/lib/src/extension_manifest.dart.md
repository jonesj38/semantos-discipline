---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/extension_manifest.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.016675+00:00
---

# platforms/flutter/semantos_core/lib/src/extension_manifest.dart

```dart
import 'dart:convert';

/// Runtime representation of an extension manifest loaded by the shell.
///
/// Mirrors the TS interface at:
///   core/protocol-types/src/extension-manifest.ts (ExtensionManifest)
/// plus the embedded grammar fragment from:
///   extensions/<id>/src/conversation/<id>-grammar-spec.ts (GrammarSpec)
///
/// Both TS and Dart consume the SAME JSON shape — there is no Dart
/// codegen pipeline. The manifest is loaded from a config.json file
/// (compile-time bundled today; URL/file-fetched at provisioning later)
/// and parsed into this class at boot.
class ExtensionManifest {
  /// Stable extension identifier (e.g. "oddjobz", "jambox").
  final String id;

  /// Human-readable name (e.g. "Trades & Services").
  final String name;

  /// Semantic version.
  final String version;

  /// Brain-scoped namespace partition for this extension's cells.
  /// Canonical values live in runtime/semantos-brain/src/hat_registry.zig.
  /// Example: 0x000101 for oddjobz.
  final int domainFlag;

  /// Embedded grammar (lexicon + taxonomy + actions). Identical shape to
  /// the GrammarSpec in @semantos/intent/reducer/types.
  final ExtensionGrammarSpec grammar;

  /// Capability tokens required to activate this extension. Empty = always
  /// available.
  final List<int> requiredCapabilities;

  /// Hat roles that can manage this extension (admin, governor, etc.).
  final List<String> hatRoles;

  /// UI metadata (icon, description, documentation URL, author).
  final Map<String, String> metadata;

  /// C9 PR-C9-6 (2026-05-29 per HELM-CANONICAL-SURFACE.md §2): how the
  /// cartridge surfaces in the shell helm.
  ///   - `default` (most common): contributes sub-verbs + cells INTO
  ///     the helm via [uiVerbs] declarations. The cartridge has no
  ///     dedicated screen of its own.
  ///   - `dedicated`: cartridge ships its own full-screen UI; helm
  ///     picker tap routes to it (per CartridgeEntry.routePath +
  ///     buildScreen). E.g., a real-time music room.
  ///   - `passive`: cartridge runs in background; no helm surfacing;
  ///     hidden from the cartridge picker. E.g., wallet-headers
  ///     substrate service.
  ///   - `priority`: cartridge claims always-on-top helm slot
  ///     (alarm pattern). Pre-empts default-mode contributions.
  final HelmSurfacingMode surfacingMode;

  /// C9 PR-C9-6: sub-verbs this cartridge contributes to the shell's
  /// modal verb shelf (DO | TALK | FIND). Each entry declares its
  /// modal + display label + intentType the cartridge knows how to
  /// dispatch. The shell aggregates verbs across all default-mode
  /// cartridges and renders them in the corresponding modal sheet.
  final List<HelmUiVerb> uiVerbs;

  const ExtensionManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.domainFlag,
    required this.grammar,
    this.requiredCapabilities = const [],
    this.hatRoles = const [],
    this.metadata = const {},
    this.surfacingMode = HelmSurfacingMode.defaultMode,
    this.uiVerbs = const [],
  });

  factory ExtensionManifest.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw FormatException('Manifest missing/invalid "id": $json');
    }
    final name = json['name'];
    if (name is! String || name.isEmpty) {
      throw FormatException('Manifest "$id" missing/invalid "name"');
    }
    final version = json['version'];
    if (version is! String || version.isEmpty) {
      throw FormatException('Manifest "$id" missing/invalid "version"');
    }

    // domainFlag may arrive as int or as hex string ("0x000101")
    final flagRaw = json['domainFlag'];
    final int domainFlag;
    if (flagRaw is int) {
      domainFlag = flagRaw;
    } else if (flagRaw is String) {
      domainFlag = int.parse(
        flagRaw.startsWith('0x') ? flagRaw.substring(2) : flagRaw,
        radix: 16,
      );
    } else {
      throw FormatException('Manifest "$id" missing/invalid "domainFlag"');
    }

    final grammarJson = json['grammar'];
    if (grammarJson is! Map<String, dynamic>) {
      throw FormatException('Manifest "$id" missing/invalid "grammar"');
    }

    // C9 PR-C9-6 — optional `ui` block holds surfacingMode + verbs.
    // Manifests without it default to surfacingMode=default + no verbs
    // (cartridge contributes no helm affordances — degenerate but valid).
    final uiJson = json['ui'];
    final HelmSurfacingMode surfacingMode;
    final List<HelmUiVerb> uiVerbs;
    if (uiJson is Map<String, dynamic>) {
      surfacingMode = HelmSurfacingMode.parse(uiJson['surfacingMode']);
      final verbsJson = uiJson['verbs'];
      uiVerbs = verbsJson is List
          ? verbsJson
              .whereType<Map<String, dynamic>>()
              .map(HelmUiVerb.fromJson)
              .toList(growable: false)
          : const [];
    } else {
      surfacingMode = HelmSurfacingMode.defaultMode;
      uiVerbs = const [];
    }

    return ExtensionManifest(
      id: id,
      name: name,
      version: version,
      domainFlag: domainFlag,
      grammar: ExtensionGrammarSpec.fromJson(grammarJson),
      requiredCapabilities: _intList(json['requiredCapabilities']),
      hatRoles: _stringList(json['hatRoles']),
      metadata: _stringMap(json['metadata']),
      surfacingMode: surfacingMode,
      uiVerbs: uiVerbs,
    );
  }

  factory ExtensionManifest.fromJsonString(String jsonStr) {
    return ExtensionManifest.fromJson(
      jsonDecode(jsonStr) as Map<String, dynamic>,
    );
  }

  static List<int> _intList(dynamic v) {
    if (v == null) return const [];
    if (v is! List) return const [];
    return v.whereType<int>().toList(growable: false);
  }

  static List<String> _stringList(dynamic v) {
    if (v == null) return const [];
    if (v is! List) return const [];
    return v.whereType<String>().toList(growable: false);
  }

  static Map<String, String> _stringMap(dynamic v) {
    if (v == null) return const {};
    if (v is! Map) return const {};
    final out = <String, String>{};
    v.forEach((k, val) {
      if (k is String && val is String) out[k] = val;
    });
    return out;
  }
}

/// Grammar slice of an [ExtensionManifest]. Mirrors GrammarSpec from
/// @semantos/intent/reducer/types.
class ExtensionGrammarSpec {
  /// Extension identifier echoed at the grammar level (e.g. "odd-job-todd").
  final String extensionId;

  /// Lexicon binding (name + allowed categories).
  final LexiconBinding lexicon;

  /// Default taxonomy "what" coordinate (e.g. "maintenance.job").
  final String defaultTaxonomyWhat;

  /// Object type vocabulary (taxonomy coordinates this extension declares).
  final List<ObjectType> objectTypes;

  /// Action verbs the SIR pipeline accepts for this extension. The
  /// conversation channel uses these to constrain LLM output and the
  /// brain dispatcher routes them to the extension's walker.
  final List<ActionVerb> actions;

  /// Trust class label (e.g. "interpretive", "authoritative").
  final String trustClass;

  /// Proof requirement label (e.g. "none", "attestation", "formal").
  final String proofRequirement;

  const ExtensionGrammarSpec({
    required this.extensionId,
    required this.lexicon,
    required this.defaultTaxonomyWhat,
    required this.objectTypes,
    required this.actions,
    required this.trustClass,
    required this.proofRequirement,
  });

  factory ExtensionGrammarSpec.fromJson(Map<String, dynamic> json) {
    final lexicon = json['lexicon'];
    if (lexicon is! Map<String, dynamic>) {
      throw const FormatException('grammar.lexicon missing or invalid');
    }
    final objectTypes = (json['objectTypes'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ObjectType.fromJson)
        .toList(growable: false);
    final actions = (json['actions'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ActionVerb.fromJson)
        .toList(growable: false);
    return ExtensionGrammarSpec(
      extensionId: (json['extensionId'] as String?) ?? '',
      lexicon: LexiconBinding.fromJson(lexicon),
      defaultTaxonomyWhat: (json['defaultTaxonomyWhat'] as String?) ?? '',
      objectTypes: objectTypes,
      actions: actions,
      trustClass: (json['trustClass'] as String?) ?? 'informal',
      proofRequirement: (json['proofRequirement'] as String?) ?? 'none',
    );
  }

  /// Action verb names — convenience accessor for the GBNF prompt
  /// builder and the host-side confidence scorer.
  List<String> get actionVerbs =>
      actions.map((a) => a.name).toList(growable: false);
}

class LexiconBinding {
  final String name;
  final List<String> categories;
  const LexiconBinding({required this.name, required this.categories});

  factory LexiconBinding.fromJson(Map<String, dynamic> json) {
    return LexiconBinding(
      name: (json['name'] as String?) ?? '',
      categories: (json['categories'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
    );
  }
}

class ObjectType {
  final String name;
  final String description;
  const ObjectType({required this.name, required this.description});

  factory ObjectType.fromJson(Map<String, dynamic> json) {
    return ObjectType(
      name: (json['name'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
    );
  }
}

class ActionVerb {
  final String name;
  final String category;
  final List<String> authoredBy;
  final String description;

  const ActionVerb({
    required this.name,
    required this.category,
    required this.authoredBy,
    required this.description,
  });

  factory ActionVerb.fromJson(Map<String, dynamic> json) {
    return ActionVerb(
      name: (json['name'] as String?) ?? '',
      category: (json['category'] as String?) ?? '',
      authoredBy: (json['authoredBy'] as List? ?? const [])
          .whereType<String>()
          .toList(growable: false),
      description: (json['description'] as String?) ?? '',
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// C9 PR-C9-6 — helm surfacing mode + verb declarations
//
// Per docs/design/HELM-CANONICAL-SURFACE.md §2 (surfacing modes) + §5
// (modal verb shelf). Each cartridge's manifest.json declares its
// surfacing mode + the sub-verbs it contributes to DO | TALK | FIND.
// The shell aggregates verbs across default-mode cartridges + renders
// the right ones in each modal sheet.
// ─────────────────────────────────────────────────────────────────────

/// How a cartridge surfaces in the shell helm.
enum HelmSurfacingMode {
  /// Cartridge contributes sub-verbs + cells INTO the canonical helm
  /// via [ExtensionManifest.uiVerbs]. No dedicated screen.
  defaultMode,

  /// Cartridge has its own full-screen UI. Picker tap routes there
  /// (CartridgeEntry.routePath + buildScreen).
  dedicated,

  /// Cartridge runs silent. No helm surfacing. Hidden from picker.
  passive,

  /// Always-on-top helm slot — pre-empts default-mode contributions.
  priority;

  /// Wire name as it appears in cartridge.json/manifest.json. Falls
  /// back to `default` for unknown / missing values so legacy manifests
  /// keep working.
  static HelmSurfacingMode parse(dynamic raw) {
    if (raw is! String) return HelmSurfacingMode.defaultMode;
    switch (raw.toLowerCase()) {
      case 'default':
        return HelmSurfacingMode.defaultMode;
      case 'dedicated':
        return HelmSurfacingMode.dedicated;
      case 'passive':
        return HelmSurfacingMode.passive;
      case 'priority':
        return HelmSurfacingMode.priority;
      default:
        return HelmSurfacingMode.defaultMode;
    }
  }

  String get wireName => switch (this) {
        HelmSurfacingMode.defaultMode => 'default',
        HelmSurfacingMode.dedicated => 'dedicated',
        HelmSurfacingMode.passive => 'passive',
        HelmSurfacingMode.priority => 'priority',
      };
}

/// Which modal a verb surfaces in on the shell verb shelf.
enum HelmVerbModal {
  /// State-mutating verbs (e.g., release, new_job, set_intention).
  do_,

  /// Conversational scope verbs (e.g., chat, ask).
  talk,

  /// Read-only retrieval verbs (e.g., find, list, inspect).
  find;

  static HelmVerbModal? parse(dynamic raw) {
    if (raw is! String) return null;
    switch (raw.toLowerCase()) {
      case 'do':
      case 'do_':
        return HelmVerbModal.do_;
      case 'talk':
        return HelmVerbModal.talk;
      case 'find':
        return HelmVerbModal.find;
      default:
        return null;
    }
  }

  String get wireName => switch (this) {
        HelmVerbModal.do_ => 'do',
        HelmVerbModal.talk => 'talk',
        HelmVerbModal.find => 'find',
      };
}

/// A single sub-verb a cartridge contributes to the helm's modal
/// verb shelf. Surfaces as a tappable tile in the DO|TALK|FIND
/// bottom sheet; tap dispatches the intent through the shell's
/// IntentDispatcher.
class HelmUiVerb {
  /// Which modal sheet this verb surfaces in.
  final HelmVerbModal modal;

  /// User-facing label (e.g., "Release", "New job").
  final String label;

  /// Intent type identifier — the shell's IntentDispatcher resolves
  /// this string to a registered intent binding (which knows the
  /// cellType + triple + default payload). The cartridge registers
  /// its bindings at boot via [IntentDispatcher.register]; the shell
  /// dispatches by name via [IntentDispatcher.dispatchByName] without
  /// importing the cartridge's intent class.
  final String intentType;

  /// Optional short subtitle shown under the label.
  final String subtitle;

  /// Optional Material icon name (e.g., "flash_on", "search"). The
  /// shell resolves it via a name → IconData map; unknown names
  /// fall back to a generic verb icon.
  final String? iconName;

  /// C9 PR-C9-7c: declares the shape of input the helm should collect
  /// before dispatching the intent. The shell renders a generic input
  /// sheet driven by this shape — text field, multiline, etc. — and
  /// posts the collected value(s) into the payload under
  /// [HelmInputShape.field]. Null = no input UI; tap dispatches
  /// immediately with the cartridge's default payload.
  final HelmInputShape? inputShape;

  /// C9 PR-C9-7d: dispatch metadata — cellType + triple + payload
  /// defaults — that the shell needs to mint the cell when this verb
  /// is invoked. The shell registers a dispatcher binding per verb
  /// whose `dispatch` block is populated; verbs without `dispatch`
  /// render as `(unwired)` tiles in the modal verb shelf.
  ///
  /// Single source of truth for shell-driven dispatch — replaces
  /// the parallel hand-written cartridge-side data constant
  /// (PR-C9-7c's `IntentSpec` list, removed in PR-C9-7d).
  ///
  /// Long-term: the cellType triple is already declared by
  /// `cartridges/<id>/cartridge.json` cellTypes[].triple. A future
  /// refactor will bundle cartridge.json and have the shell resolve
  /// the triple by name lookup, keeping cartridge.json as the single
  /// source. For now `dispatch` is a manifest-side projection of the
  /// cartridge.json cellType data.
  final HelmUiVerbDispatch? dispatch;

  /// M1.8 — read spec for FIND verbs. Declares the typeHash (+ optional
  /// filter + render hints) the shell queries via `cell.query` and renders
  /// generically as a cell list. Null on DO/TALK verbs. This is the read-side
  /// analog of [dispatch]: the manifest is the single source of truth for what
  /// a FIND verb retrieves, so the shell needs no per-cartridge read code.
  final HelmUiVerbQuery? query;

  const HelmUiVerb({
    required this.modal,
    required this.label,
    required this.intentType,
    this.subtitle = '',
    this.iconName,
    this.inputShape,
    this.dispatch,
    this.query,
  });

  factory HelmUiVerb.fromJson(Map<String, dynamic> json) {
    final modal = HelmVerbModal.parse(json['modal']);
    if (modal == null) {
      throw FormatException(
        'HelmUiVerb missing/invalid "modal" (expected do|talk|find): $json',
      );
    }
    final label = json['label'];
    if (label is! String || label.isEmpty) {
      throw FormatException('HelmUiVerb missing/invalid "label": $json');
    }
    final intentType = json['intentType'];
    if (intentType is! String || intentType.isEmpty) {
      throw FormatException(
        'HelmUiVerb missing/invalid "intentType": $json',
      );
    }
    final inputShapeJson = json['inputShape'];
    final HelmInputShape? inputShape = inputShapeJson is Map<String, dynamic>
        ? HelmInputShape.fromJson(inputShapeJson)
        : null;
    final dispatchJson = json['dispatch'];
    final HelmUiVerbDispatch? dispatch = dispatchJson is Map<String, dynamic>
        ? HelmUiVerbDispatch.fromJson(dispatchJson)
        : null;
    final queryJson = json['query'];
    final HelmUiVerbQuery? query = queryJson is Map<String, dynamic>
        ? HelmUiVerbQuery.fromJson(queryJson)
        : null;
    return HelmUiVerb(
      modal: modal,
      label: label,
      intentType: intentType,
      subtitle: (json['subtitle'] as String?) ?? '',
      iconName: json['icon'] as String?,
      inputShape: inputShape,
      dispatch: dispatch,
      query: query,
    );
  }
}

/// M1.8 — read spec for a FIND verb. Projected from the manifest's
/// `ui.verbs[].query` block; the shell runs `cell.query(typeHash, filter)`
/// over the unified channel and renders the rows generically.
///
/// Wire shape (manifest.json):
///   "query": {
///     "typeHash": "oddjobz.customer.v2",
///     "collectionTitle": "Customers",
///     "titleField": "display_name",
///     "subtitleField": "phone",
///     "filter": { "state": "open" }
///   }
class HelmUiVerbQuery {
  /// typeHash the brain resolves for `cell.query` — the friendly alias the
  /// cartridge registers (e.g. `oddjobz.customer.v2`) or a 64-hex string.
  final String typeHash;

  /// Title shown at the top of the results screen (e.g. "Customers").
  /// Falls back to the verb label when empty.
  final String collectionTitle;

  /// Row key whose value renders as each card's title. When absent/missing,
  /// the renderer picks the first stringy field.
  final String? titleField;

  /// Row key whose value renders as each card's subtitle. Optional.
  final String? subtitleField;

  /// Optional filter object passed through to `cell.query` (some decoders
  /// require one; e.g. oddjobz jobs filter by state).
  final Map<String, dynamic>? filter;

  const HelmUiVerbQuery({
    required this.typeHash,
    this.collectionTitle = '',
    this.titleField,
    this.subtitleField,
    this.filter,
  });

  factory HelmUiVerbQuery.fromJson(Map<String, dynamic> json) {
    final typeHash = json['typeHash'];
    if (typeHash is! String || typeHash.isEmpty) {
      throw FormatException(
        'HelmUiVerbQuery missing/invalid "typeHash": $json',
      );
    }
    final filterJson = json['filter'];
    return HelmUiVerbQuery(
      typeHash: typeHash,
      collectionTitle: (json['collectionTitle'] as String?) ?? '',
      titleField: json['titleField'] as String?,
      subtitleField: json['subtitleField'] as String?,
      filter: filterJson is Map<String, dynamic>
          ? Map<String, dynamic>.from(filterJson)
          : null,
    );
  }
}

/// C9 PR-C9-7d — dispatch metadata projected from cartridge.json's
/// `cellTypes[]` into the manifest's `ui.verbs[].dispatch` block.
///
/// The shell uses this to register a dispatcher binding per verb
/// without the cartridge having to hand-write a separate
/// `IntentSpec` constant (PR-C9-7c's parallel data structure —
/// now removed in PR-C9-7d).
///
/// Wire shape (manifest.json):
///   "dispatch": {
///     "cellType": "betterment.practice.release",
///     "triple": ["betterment", "practice", "release", ""],
///     "defaultPayload": { "source": "keyboard", ... }
///   }
class HelmUiVerbDispatch {
  /// Dotted cellType name (e.g. `betterment.practice.release`).
  /// Must match a `cellTypes[].name` in the cartridge.json source.
  final String cellType;

  /// 4-segment cellType triple (segment4 may be empty). Mirrors
  /// `cellTypes[].triple` in cartridge.json. The shell uses these to
  /// compute the type hash for the brain mint.
  final String s1;
  final String s2;
  final String s3;
  final String s4;

  /// Cartridge-defined default payload fields the shell merges
  /// BENEATH any user-collected payload. Lets the cartridge keep
  /// schema knowledge (required-but-defaulted fields like
  /// source='keyboard', elevation=5 for Release) without the shell
  /// needing it. Caller-supplied fields win on conflict.
  final Map<String, dynamic> defaultPayload;

  const HelmUiVerbDispatch({
    required this.cellType,
    required this.s1,
    required this.s2,
    required this.s3,
    this.s4 = '',
    this.defaultPayload = const {},
  });

  factory HelmUiVerbDispatch.fromJson(Map<String, dynamic> json) {
    final cellType = json['cellType'];
    if (cellType is! String || cellType.isEmpty) {
      throw FormatException(
        'HelmUiVerbDispatch missing/invalid "cellType": $json',
      );
    }
    final tripleJson = json['triple'];
    if (tripleJson is! List || tripleJson.isEmpty || tripleJson.length > 4) {
      throw FormatException(
        'HelmUiVerbDispatch "triple" must be a list of 1..4 strings: $json',
      );
    }
    final segs = [
      for (final v in tripleJson) v is String ? v : '',
      for (int i = tripleJson.length; i < 4; i++) '',
    ];
    final defaultPayloadJson = json['defaultPayload'];
    final Map<String, dynamic> defaultPayload =
        defaultPayloadJson is Map<String, dynamic>
            ? Map<String, dynamic>.from(defaultPayloadJson)
            : const {};
    return HelmUiVerbDispatch(
      cellType: cellType,
      s1: segs[0],
      s2: segs[1],
      s3: segs[2],
      s4: segs[3],
      defaultPayload: defaultPayload,
    );
  }
}

/// C9 PR-C9-7c — declares what input the helm should collect before
/// dispatching a verb. The shell renders a generic input sheet
/// driven by this; the cartridge never ships UI code into the shell.
///
/// Today: `text` (single-line) and `multiline` are supported. Future
/// shapes (`form` with multiple fields, `enum` for picker, etc.) slot
/// into [HelmInputShapeKind].
class HelmInputShape {
  final HelmInputShapeKind kind;

  /// Field name in the dispatched payload the collected value lands
  /// under. E.g., 'rawText' for betterment.practice.release.
  final String field;

  /// Label shown above the input (e.g., "What are you releasing?").
  final String label;

  /// Placeholder hint shown when empty (e.g., "I'm letting go of…").
  final String hint;

  /// For `multiline`: rough number of visible rows when empty.
  final int? minLines;

  /// For `multiline`: cap on visible rows.
  final int? maxLines;

  /// For `custom`: the key into CustomVerbSurfaceRegistry selecting the
  /// cartridge-owned capture screen (e.g. "betterment.release"). Null otherwise.
  final String? customKey;

  const HelmInputShape({
    required this.kind,
    required this.field,
    this.label = '',
    this.hint = '',
    this.minLines,
    this.maxLines,
    this.customKey,
  });

  factory HelmInputShape.fromJson(Map<String, dynamic> json) {
    final kind = HelmInputShapeKind.parse(json['kind']);
    if (kind == null) {
      throw FormatException(
        'HelmInputShape missing/invalid "kind" (expected text|multiline|custom): $json',
      );
    }
    // `field` is required for text/multiline (where the collected value lands);
    // a `custom` surface owns its own payload assembly, so field is optional
    // there but customKey is required.
    final rawField = json['field'];
    if (kind == HelmInputShapeKind.custom) {
      final ck = json['customKey'];
      if (ck is! String || ck.isEmpty) {
        throw FormatException(
          'HelmInputShape kind=custom missing/invalid "customKey": $json',
        );
      }
      return HelmInputShape(
        kind: kind,
        field: (rawField is String) ? rawField : '',
        label: (json['label'] as String?) ?? '',
        hint: (json['hint'] as String?) ?? '',
        customKey: ck,
      );
    }
    if (rawField is! String || rawField.isEmpty) {
      throw FormatException('HelmInputShape missing/invalid "field": $json');
    }
    return HelmInputShape(
      kind: kind,
      field: rawField,
      label: (json['label'] as String?) ?? '',
      hint: (json['hint'] as String?) ?? '',
      minLines: json['minLines'] as int?,
      maxLines: json['maxLines'] as int?,
    );
  }
}

enum HelmInputShapeKind {
  text,
  multiline,

  /// A cartridge-owned full-screen capture surface. The verb's
  /// [HelmInputShape.customKey] selects the registered builder
  /// (CustomVerbSurfaceRegistry); the shell pushes it instead of the
  /// generic input sheet. Keeps the shell cartridge-neutral.
  custom;

  static HelmInputShapeKind? parse(dynamic raw) {
    if (raw is! String) return null;
    switch (raw.toLowerCase()) {
      case 'text':
        return HelmInputShapeKind.text;
      case 'multiline':
        return HelmInputShapeKind.multiline;
      case 'custom':
        return HelmInputShapeKind.custom;
      default:
        return null;
    }
  }
}

```
