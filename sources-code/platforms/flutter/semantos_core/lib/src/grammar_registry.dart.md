---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/grammar_registry.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.015242+00:00
---

# platforms/flutter/semantos_core/lib/src/grammar_registry.dart

```dart
import 'extension_manifest.dart';
import 'manifest_provisioner.dart';

/// Runtime registry of active extension manifests in this shell.
///
/// Replaces the hardcoded `ExtensionGrammar.oddjobz` in oddjobz-mobile's
/// `sir_extractor.dart`. The shell loads manifests at boot (from compiled-
/// in JSON assets today, URL/file-fetched at provisioning later) and the
/// conversation engine consults the registry to pick which grammar applies
/// to the active hat / channel.
///
/// One [ExtensionManifest] per active extension. Lookup by extension id.
class GrammarRegistry {
  final Map<String, ExtensionManifest> _byId;

  GrammarRegistry._(this._byId);

  /// Build a registry from a list of manifests, indexed by [ExtensionManifest.id].
  /// Duplicates throw — extensions must have unique ids.
  factory GrammarRegistry.fromManifests(Iterable<ExtensionManifest> manifests) {
    final map = <String, ExtensionManifest>{};
    for (final m in manifests) {
      if (map.containsKey(m.id)) {
        throw StateError(
          'GrammarRegistry: duplicate extension id "${m.id}". '
          'Each extension must have a unique id.',
        );
      }
      map[m.id] = m;
    }
    return GrammarRegistry._(map);
  }

  /// Parse a list of JSON manifest strings and build a registry.
  /// Convenience for boot wiring that loads JSON assets.
  factory GrammarRegistry.fromJsonStrings(Iterable<String> jsonStrings) {
    return GrammarRegistry.fromManifests(
      jsonStrings.map(ExtensionManifest.fromJsonString),
    );
  }

  /// Empty registry — useful for tests and for shells that boot before
  /// any extension is provisioned.
  factory GrammarRegistry.empty() => GrammarRegistry._(const {});

  /// Build from a list of provisioned extensions — the natural output
  /// of [ManifestProvisioner.loadFromUrl] / [provisionFromCompileBundle].
  /// The registry holds the manifests; verification evidence stays on
  /// each [ProvisionedExtension] for the shell's audit log.
  factory GrammarRegistry.fromProvisioned(
    Iterable<ProvisionedExtension> provisioned,
  ) {
    return GrammarRegistry.fromManifests(provisioned.map((p) => p.manifest));
  }

  /// All registered extension ids.
  Iterable<String> get extensionIds => _byId.keys;

  /// All registered manifests.
  Iterable<ExtensionManifest> get manifests => _byId.values;

  /// Lookup by extension id. Returns null if not registered.
  ExtensionManifest? byId(String id) => _byId[id];

  /// Lookup by canonical domainFlag (extension namespace). Returns null
  /// if no registered extension uses that flag.
  ExtensionManifest? byDomainFlag(int domainFlag) {
    for (final m in _byId.values) {
      if (m.domainFlag == domainFlag) return m;
    }
    return null;
  }

  /// True if [extensionId] is registered and active.
  bool isActive(String extensionId) => _byId.containsKey(extensionId);

  /// Number of active extensions.
  int get count => _byId.length;

  // ───────────────────────────────────────────────────────────────────
  // C9 PR-C9-6 — helm verb shelf aggregation
  //
  // The shell's modal verb shelf (DO | TALK | FIND) reads from these
  // helpers to render the right sub-verbs per modal. Verbs are
  // aggregated across all default-mode cartridges (passive cartridges
  // never contribute; priority cartridges pre-empt). Per
  // HELM-CANONICAL-SURFACE.md §5.
  // ───────────────────────────────────────────────────────────────────

  /// All [HelmUiVerb] declarations across active cartridges, filtered
  /// to [modal]. Only `default`-mode cartridges contribute (passive
  /// cartridges silent; dedicated cartridges have their own surface;
  /// priority cartridges are TODO).
  ///
  /// Returns verbs paired with their owning extension id so the shell
  /// can show provenance ("Self · Release", "Oddjobz · New job") +
  /// route dispatch correctly.
  List<HelmVerbBinding> verbsForModal(HelmVerbModal modal) {
    final out = <HelmVerbBinding>[];
    for (final m in _byId.values) {
      if (m.surfacingMode != HelmSurfacingMode.defaultMode) continue;
      for (final v in m.uiVerbs) {
        if (v.modal == modal) {
          out.add(HelmVerbBinding(extensionId: m.id, extensionName: m.name, verb: v));
        }
      }
    }
    return out;
  }

  /// Same as [verbsForModal] but filtered to a single cartridge —
  /// used when the operator has scoped the helm to one active
  /// cartridge via the picker (PR-C9-5).
  List<HelmVerbBinding> verbsForModalAndExtension(
      HelmVerbModal modal, String extensionId) {
    final m = _byId[extensionId];
    if (m == null) return const [];
    if (m.surfacingMode != HelmSurfacingMode.defaultMode) return const [];
    return [
      for (final v in m.uiVerbs)
        if (v.modal == modal)
          HelmVerbBinding(extensionId: m.id, extensionName: m.name, verb: v),
    ];
  }
}

/// A verb declaration paired with its owning extension's identity.
/// Surfaces provenance + dispatch routing on the helm verb shelf.
class HelmVerbBinding {
  final String extensionId;
  final String extensionName;
  final HelmUiVerb verb;
  const HelmVerbBinding({
    required this.extensionId,
    required this.extensionName,
    required this.verb,
  });
}

```
