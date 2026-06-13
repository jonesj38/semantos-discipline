---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/repl/hat_context.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.883016+00:00
---

# archive/apps-semantos-monolith/lib/src/repl/hat_context.dart

```dart
// W1.5 — HatContext: universal hat state stored in app state.
//
// An immutable value object that captures the active hat (domain scope)
// for the Flutter app.  All SQLite queries, Pravega subscriptions, and
// capability checks are scoped by the active HatContext.
//
// Switching hat:
//   HomeScreen._HomeScreenState holds `HatContext _activeHat` and exposes
//   `switchHat(HatContext newHat)` which:
//     1. Closes/reopens HatEntityRepository with newHat.domainFlag.
//     2. Calls EventSubscriptionService.updateHat(newHat.domainFlag).
//     3. Reinitialises PaskSessionService with newHat.domainFlag.
//     4. Calls setState() to rebuild the UI.
//
// Design decision: plain Dart const value class with == / hashCode so it
// can be used as a map key and compared in tests without extra dependencies.
// No provider/bloc/riverpod wiring for W1.5 — a state variable in
// HomeScreen is sufficient given the single-screen-stack architecture.

/// The active hat (domain) context carried through all services.
///
/// [domainFlag] identifies the domain in the cell-DAG (e.g. `0x000101`
/// for oddjobz).  [extensionId] is the human-readable extension name
/// used for logging and UI labels.
///
/// [hatCertId] is the BRC-42 child cert derived from the operator's
/// root cert for this hat:
///   identityPort.deriveChild(rootCertId, extensionId, domainFlag)
/// It scopes the contact book — contacts/{hatCertId}/ — so each hat
/// has its own isolated contact namespace under the user's root
/// identity cert.  Empty string until the cert is resolved at boot.
class HatContext {
  final int domainFlag;
  final String extensionId;

  /// BRC-42 child certId for this hat.  Scopes the contact book.
  /// Empty string for hats that haven't derived their cert yet.
  final String hatCertId;

  const HatContext({
    required this.domainFlag,
    required this.extensionId,
    this.hatCertId = '',
  });

  /// Default hat for the oddjobz extension (cert resolved at boot).
  static const oddjobz = HatContext(
    domainFlag: 0x000101,
    extensionId: 'oddjobz',
  );

  /// Returns a copy with the resolved [hatCertId] filled in.
  HatContext withCertId(String certId) => HatContext(
        domainFlag:  domainFlag,
        extensionId: extensionId,
        hatCertId:   certId,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HatContext &&
          domainFlag  == other.domainFlag  &&
          extensionId == other.extensionId &&
          hatCertId   == other.hatCertId;

  @override
  int get hashCode => Object.hash(domainFlag, extensionId, hatCertId);

  @override
  String toString() =>
      'HatContext(domainFlag: 0x${domainFlag.toRadixString(16).padLeft(6, '0')}, '
      'extensionId: $extensionId, hatCertId: ${hatCertId.isEmpty ? '<unresolved>' : hatCertId})';
}

```
