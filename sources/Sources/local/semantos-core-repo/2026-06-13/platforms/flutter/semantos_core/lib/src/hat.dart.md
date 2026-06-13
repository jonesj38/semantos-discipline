---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/platforms/flutter/semantos_core/lib/src/hat.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.013223+00:00
---

# platforms/flutter/semantos_core/lib/src/hat.dart

```dart
import 'extension_manifest.dart';
import 'grammar_registry.dart';

/// A specific operator role within an active extension.
///
/// Hats are the composition primitive that lets the shell host
/// multiple experiences without cross-contamination. Each hat is
/// (extensionId, roleId): the extension supplies the grammar and
/// the role narrows which entities/views are visible.
///
/// Examples:
///   - (oddjobz,  operator)      — the tradie running their own business
///   - (oddjobz,  customer)      — a client viewing their job thread
///   - (jambox,   producer)      — a music producer managing sessions
///   - (semantos, admin)         — the operator's cross-experience admin
///
/// Switching hats changes which conversation channel is active (one
/// channel per hat) and re-scopes cell reads via the
/// extension's domainFlag plus the operator's hat-derived BRC-42 child
/// cert. The shell never sees an utterance "in two hats at once" except
/// in the explicit hypervisor cross-cut.
class Hat {
  /// Extension identifier (must match an ExtensionManifest.id loaded
  /// in the active GrammarRegistry).
  final String extensionId;

  /// Role name as declared in ExtensionManifest.hatRoles.
  /// Conventional baseline: "operator" — the default role for an
  /// extension that doesn't yet distinguish multiple roles.
  final String roleId;

  /// Optional display label; defaults to "$extensionId · $roleId" when
  /// the experience hasn't supplied a friendlier label.
  final String? displayLabel;

  const Hat({
    required this.extensionId,
    required this.roleId,
    this.displayLabel,
  });

  /// Stable composite identifier for routing + persistence
  /// (e.g. "oddjobz/operator", "jambox/producer").
  String get hatId => '$extensionId/$roleId';

  /// User-facing label. Falls back to the composite id when no
  /// display label is set.
  String get label => displayLabel ?? '$extensionId · $roleId';

  @override
  bool operator ==(Object other) =>
      other is Hat && other.extensionId == extensionId && other.roleId == roleId;

  @override
  int get hashCode => Object.hash(extensionId, roleId);

  @override
  String toString() => 'Hat($hatId)';
}

/// Composition of all hats the operator can wear in this shell — built
/// by enumerating the `hatRoles` field of every manifest in a
/// [GrammarRegistry].
///
/// The shell owns one [HatRegistry] for the operator's session. The
/// active hat is tracked separately (typically via a ValueNotifier in
/// shell state); the registry itself is immutable once built.
///
/// When a new extension is provisioned, the shell rebuilds the
/// registry from the updated [GrammarRegistry]. Today this happens at
/// boot only; once dynamic install lands, it happens whenever the
/// brain pushes a manifest change.
class HatRegistry {
  final List<Hat> _hats;

  HatRegistry._(this._hats);

  /// Build a registry by enumerating each manifest's [ExtensionManifest.hatRoles].
  /// Manifests with no declared hatRoles contribute a single default
  /// hat with roleId="operator" — so single-role extensions don't
  /// have to opt in to the field.
  factory HatRegistry.fromGrammarRegistry(GrammarRegistry registry) {
    return HatRegistry.fromManifests(registry.manifests);
  }

  /// Build directly from a manifest iterable. Useful for tests + for
  /// shells that aren't going through a [GrammarRegistry].
  factory HatRegistry.fromManifests(Iterable<ExtensionManifest> manifests) {
    final hats = <Hat>[];
    for (final m in manifests) {
      final roles = m.hatRoles.isEmpty ? const ['operator'] : m.hatRoles;
      for (final role in roles) {
        hats.add(Hat(extensionId: m.id, roleId: role));
      }
    }
    return HatRegistry._(List.unmodifiable(hats));
  }

  /// Empty registry — useful for tests + shells that boot before any
  /// extension is provisioned.
  factory HatRegistry.empty() => HatRegistry._(const []);

  /// All registered hats. Order matches the manifest iteration order,
  /// which the shell can rely on for stable UI surfacing.
  List<Hat> get hats => _hats;

  /// Number of registered hats across all active extensions.
  int get count => _hats.length;

  /// Lookup by composite hatId ("extensionId/roleId"). Null if absent.
  Hat? byId(String hatId) {
    for (final h in _hats) {
      if (h.hatId == hatId) return h;
    }
    return null;
  }

  /// All hats for a given extension.
  Iterable<Hat> forExtension(String extensionId) =>
      _hats.where((h) => h.extensionId == extensionId);

  /// All distinct extension ids that contribute at least one hat.
  Iterable<String> get extensionIds {
    final seen = <String>{};
    for (final h in _hats) {
      seen.add(h.extensionId);
    }
    return seen;
  }

  /// True if [hatId] is registered.
  bool contains(String hatId) => byId(hatId) != null;

  /// The default hat the shell selects on first boot when the operator
  /// hasn't picked one yet. Today: the first hat in iteration order;
  /// when multi-extension provisioning lands, the brain will surface
  /// an operator preference.
  Hat? get defaultHat => _hats.isEmpty ? null : _hats.first;
}

```
