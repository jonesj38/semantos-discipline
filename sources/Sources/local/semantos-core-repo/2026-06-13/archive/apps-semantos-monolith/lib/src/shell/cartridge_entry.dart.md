---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/lib/src/shell/cartridge_entry.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.900993+00:00
---

# archive/apps-semantos-monolith/lib/src/shell/cartridge_entry.dart

```dart
// Shell cartridge binding — the Flutter-facing half of CartridgeDescriptor.
//
// `CartridgeDescriptor` (in semantos_core) is Flutter-free: id, routePath,
// title, role.  `CartridgeEntry` composes it with the Flutter-specific
// bindings a cartridge must provide to participate in shell composition.
//
// See docs/design/SHELL-CARTRIDGE-MODEL.md for the architectural rationale
// (canonical UI grammar Home | Do | Talk | Find, presentation taxonomy,
// 1-3-5-3-1 CSD alignment).  This file is the contract surface that doc
// describes.
//
// Lifecycle:
//   CartridgeEntry instances are constructed once at boot and registered
//   with [ShellCartridgeRegistry]. The registry is immutable after boot.
//   Dynamic install (brain-pushed manifests) rebuilds the registry and hot-
//   swaps the shell; that's a future milestone — today everything is static.
//
// The `cartridge_sdk` Flutter package (platforms/flutter/cartridge_sdk) will
// eventually host this file so cartridges can import it without depending on
// the shell app.  For now it lives here while the shape stabilises.

import 'package:flutter/material.dart';
import 'package:semantos_core/semantos_core.dart' show CartridgeDescriptor;

import '../contacts/contacts_repository.dart';
import '../identity/child_cert_store.dart';
import '../pask/pask_session_service.dart';
import '../repl/repl_client.dart';
import '../talk/talk_surface_service.dart';

/// Dependencies the shell injects into every cartridge builder.
///
/// Carry-bag for things that are expensive to construct and must be
/// shared (connection pools, caches) or security-sensitive (bearer,
/// cert record).  Cartridges MUST NOT hold strong references past the
/// lifetime of the widget they build — the record can change on re-auth.
///
/// Shell-native services (talkSurface, contacts, paskSession) are
/// nullable: they're initialised asynchronously after boot (DB open,
/// pask restore, etc.) and arrive here as soon as they're ready.
/// Builders should handle null gracefully — show a loading indicator
/// or reduced-functionality UI until the service is available.
class ShellDeps {
  const ShellDeps({
    required this.record,
    required this.repl,
    required this.http,
    required this.baseUrl,
    this.talkSurface,
    this.contacts,
    this.paskSession,
  });

  /// Paired brain record — bearer, endpoint, child cert public key.
  final ChildCertRecord record;

  /// Pre-constructed REPL client for `POST /api/v1/repl`.
  final ReplClient repl;

  /// Dio instance with all shell interceptors already applied
  /// (capability-header interceptor, retry, logging).
  final dynamic http; // Dio — typed as dynamic to avoid Flutter test import chain.

  /// Brain base URL (e.g. `https://brain.example.com`).
  final String baseUrl;

  // ── Shell-native services ───────────────────────────────────────────

  /// Contextually-ranked conversation windows — shared by Talk tab and
  /// any cartridge that renders conversation surfaces (e.g. oddjobz
  /// job-thread screen).  Null until the hat-entity DB finishes opening.
  final TalkSurfaceService? talkSurface;

  /// Hat-scoped contact book.  Null until the contacts DB finishes
  /// opening (usually within 200 ms of auth).
  final ContactsRepository? contacts;

  /// Pask WASM graph session — snapshot-restore lifecycle, interact
  /// trigger.  Null until the pask DB finishes opening.
  final PaskSessionService? paskSession;

  /// Return a copy with updated nullable services (used by HomeScreen
  /// setState rebuilds as services become available).
  ShellDeps copyWith({
    TalkSurfaceService? talkSurface,
    ContactsRepository? contacts,
    PaskSessionService? paskSession,
  }) =>
      ShellDeps(
        record: record,
        repl: repl,
        http: http,
        baseUrl: baseUrl,
        talkSurface: talkSurface ?? this.talkSurface,
        contacts: contacts ?? this.contacts,
        paskSession: paskSession ?? this.paskSession,
      );
}

// ════════════════════════════════════════════════════════════════════════
// Presentation taxonomy
// ════════════════════════════════════════════════════════════════════════

/// How a cartridge presents itself within the shell.
///
/// The shell composes cartridges by role — each role claims a different
/// layer of the runtime, so multiple cartridges can be "in effect" at
/// the same time without UI conflict.  See SHELL-CARTRIDGE-MODEL §5.
enum ShellPresentation {
  /// Owns the screen when selected.  One foreground visible at a time.
  /// Appears in the cartridge switcher.  Examples: oddjobz, self,
  /// jam-room, welcome.
  foreground,

  /// Always-on infrastructure.  No screen.  No switcher entry.
  /// Many run in parallel.  Examples: wallet-headers, push-registration,
  /// attention-engine, pask-snapshot scheduler.
  background,

  /// Usually invisible.  Interrupts the foreground when a trigger fires
  /// (sheet / route / banner).  Returns control when dismissed.
  /// Examples: wallet-payment, ratification cards, incoming-call screens.
  latent,

  /// Augments a foreground cartridge by contributing widgets to its
  /// declared slot extension points (header.right, do.fab, talk.compose).
  /// Scoped by host cartridge id.  Example: a wallet-balance pill that
  /// lives in oddjobz's header.
  companion,
}

// ════════════════════════════════════════════════════════════════════════
// Scope types — declarative filters interpreted by shell-native services
// ════════════════════════════════════════════════════════════════════════

/// Declares which conversation threads belong to a cartridge.
///
/// Applied by TalkSurfaceService when the cartridge's Talk surface is
/// visible.  This is data-only; the filtering logic lives in the service
/// so the contract can stay narrow and services can evolve.
class TalkScope {
  const TalkScope({
    this.cartridgeId,
    this.threadKindAllowList,
    this.contactsScope,
  });

  /// Cartridge id this scope belongs to.  TalkSurfaceService can use this
  /// to filter threads whose primary cartridge tag matches.
  final String? cartridgeId;

  /// Allow-list of thread kinds (e.g. `['oddjobz.job-thread']`).
  /// Null = all thread kinds.
  final List<String>? threadKindAllowList;

  /// Defer to the cartridge's contact filter for thread participants.
  final ContactsScope? contactsScope;

  /// Matches everything — used by shell-admin surfaces that want global
  /// Talk visibility.
  static const TalkScope global = TalkScope();
}

/// Declares which cells a cartridge can find via FindService.
///
/// Type-path-prefix matching is the v1 mechanic; richer query shapes
/// (linearity filters, recency windows) will be added as the find UI
/// evolves.
class FindScope {
  const FindScope({
    this.cartridgeId,
    this.typePathPrefixAllowList,
  });

  final String? cartridgeId;

  /// Allow-list of type-path prefixes (e.g. `['oddjobz.', 'shell.']`).
  /// Null = all type paths.
  final List<String>? typePathPrefixAllowList;

  static const FindScope global = FindScope();
}

/// Declares which contacts count as counterparties for a cartridge.
///
/// Applied by ContactsRepository when the cartridge asks for "my contacts".
/// Each cartridge has its own notion of "who is a counterparty" — oddjobz
/// = customers, self = accountability partners, jam-room = collaborators.
class ContactsScope {
  const ContactsScope({
    this.cartridgeId,
    this.sourceAllowList,
    this.tagAllowList,
  });

  final String? cartridgeId;

  /// Allow-list of contact sources (e.g. `['oddjobz-customer',
  /// 'job-counterparty']`).
  final List<String>? sourceAllowList;

  /// Allow-list of contact tags (e.g. `['accountability', 'family']`).
  final List<String>? tagAllowList;

  static const ContactsScope global = ContactsScope();
}

// ════════════════════════════════════════════════════════════════════════
// Foreground composition
// ════════════════════════════════════════════════════════════════════════

/// The four canonical slots a foreground cartridge fills when it inherits
/// the shell's default nav.  See SHELL-CARTRIDGE-MODEL §4.
///
/// `buildHome` and `buildDo` are required — these are domain-specific by
/// definition.  `buildTalk` and `buildFind` are optional: when null, the
/// shell renders its default scope-aware Talk and Find surfaces using the
/// declared scopes.  Cartridges with rich domain-specific Find or Talk
/// surfaces (e.g. oddjobz's 5-tab Find) override the builders; most
/// cartridges leave them null and inherit the shell defaults.
class CartridgeDefaultNav {
  const CartridgeDefaultNav({
    required this.buildHome,
    required this.buildDo,
    required this.talkScope,
    required this.contactsScope,
    this.findScope,
    this.buildTalk,
    this.buildFind,
  });

  /// Attention surface — what this cartridge wants the operator to see
  /// right now (Pask-ranked items, in-progress work, due actions).
  final Widget Function(BuildContext, ShellDeps) buildHome;

  /// Actions / creation — start a new thing in this domain.
  final Widget Function(BuildContext, ShellDeps) buildDo;

  /// Optional: cartridge-specific Talk renderer.  Null = shell default
  /// (a generic TalkSurface widget filtered by [talkScope]).
  final Widget Function(BuildContext, ShellDeps)? buildTalk;

  /// Optional: cartridge-specific Find renderer.  Null = shell default
  /// (a generic FindSurface widget filtered by [findScope]).  When
  /// [findScope] is also null, the Find tab is omitted entirely.
  final Widget Function(BuildContext, ShellDeps)? buildFind;

  /// Filter applied to TalkSurfaceService for the cartridge's Talk tab.
  final TalkScope talkScope;

  /// Filter applied to ContactsRepository for the cartridge's
  /// counterparty list (used by Talk and Do).
  final ContactsScope contactsScope;

  /// Scope for the Find tab.  Null = omit the Find tab entirely (the
  /// FindService API is still callable from any cartridge widget).
  final FindScope? findScope;
}

/// Companion-only: where a companion cartridge attaches to its host.
class CompanionAttachment {
  const CompanionAttachment({
    required this.hostCartridgeId,
    required this.slot,
    required this.build,
  });

  /// The foreground cartridge id this companion augments.
  final String hostCartridgeId;

  /// Slot extension point on the host.  Convention:
  ///   `header.right` — trailing widget in the host's AppBar
  ///   `do.fab`       — floating action button on the Do tab
  ///   `talk.compose` — compose-affordance widget in the Talk surface
  final String slot;

  /// Widget builder for the slot contribution.
  final Widget Function(BuildContext, ShellDeps) build;
}

// ════════════════════════════════════════════════════════════════════════
// CartridgeEntry — the contract
// ════════════════════════════════════════════════════════════════════════

/// A cartridge contribution to the shell.
///
/// Implemented by cartridges; collected into [ShellCartridgeRegistry] at
/// boot.  How the cartridge presents (and whether it appears in the
/// switcher) is determined by [presentation].
///
/// **Foreground cartridges** must provide exactly one of:
///   * [defaultNav] — inherit the shell's canonical Home|Do|Talk|Find grammar
///   * [customSurface] — full-screen takeover, cartridge owns the whole body
///
/// **Background cartridges** use [onActivate] to register interceptors,
/// stream handlers, or any always-on infrastructure.  They have no UI
/// presence.
///
/// **Latent cartridges** use [onActivate] to arm trigger conditions.  When
/// the trigger fires, they push a modal route or sheet over the current
/// foreground.
///
/// **Companion cartridges** provide [companionAttachment] declaring which
/// foreground host they augment and which slot they fill.
abstract class CartridgeEntry {
  /// Flutter-free descriptor — matches the brain's `/api/v1/info` shape.
  CartridgeDescriptor get descriptor;

  /// Nav bar icon (filled variant).  Foreground cartridges use this in the
  /// cartridge switcher; other roles use it in admin surfaces.
  IconData get icon;

  /// Short label.  Foreground cartridges use this in the cartridge switcher.
  String get label;

  /// How this cartridge presents.  Defaults to [ShellPresentation.foreground]
  /// for backwards compatibility with the original `buildTab`-only entries.
  ShellPresentation get presentation => ShellPresentation.foreground;

  /// Header content for the AppBar.  Cartridge-specific.
  ///   oddjobz   : calendar + mic + active conversation chip
  ///   self      : today's intention status + elevation gauge + mic
  ///   jam-room  : BPM + transport + project name
  /// Null = shell default (cartridge name + long-press handle).
  /// Only meaningful when [presentation] == [ShellPresentation.foreground].
  Widget Function(BuildContext, ShellDeps)? get headerBuilder => null;

  /// Inherit the shell's canonical Home|Do|Talk|Find nav.  Foreground only.
  /// Mutually exclusive with [customSurface].
  CartridgeDefaultNav? get defaultNav => null;

  /// Full-screen takeover.  Foreground only.  Mutually exclusive with
  /// [defaultNav].  Cartridges that don't fit the canonical grammar
  /// (jam-room, scada dashboards, immersive games) use this.
  Widget Function(BuildContext, ShellDeps)? get customSurface => null;

  /// Companion attachment — only meaningful when [presentation] ==
  /// [ShellPresentation.companion].  Declares which host cartridge to
  /// augment and which slot to fill.
  CompanionAttachment? get companionAttachment => null;

  /// Lifecycle hook fired when the cartridge becomes active.
  ///
  ///   * Background → register Dio interceptors, NATS subscriptions, etc.
  ///   * Latent     → arm trigger conditions (route handlers, push hooks).
  ///   * Companion  → register slot contribution against the host.
  ///   * Foreground → optionally warm caches before first paint.
  ///
  /// Default no-op so most cartridges don't have to implement it.
  Future<void> onActivate(ShellDeps deps) async {}

  /// Lifecycle hook fired when the cartridge is being torn down (auth
  /// changed, shell shutting down).  Background cartridges remove the
  /// interceptors they added in onActivate.
  Future<void> onDeactivate(ShellDeps deps) async {}

  // ── Legacy single-tab API ────────────────────────────────────────────

  /// Legacy single-tab builder.  Used by the pre-taxonomy flat nav so
  /// existing entries keep rendering during the migration.  New entries
  /// should use [defaultNav] or [customSurface] instead.
  ///
  /// When non-null and no [defaultNav] / [customSurface] is provided,
  /// [ShellNav] treats this as a [customSurface] equivalent.
  @Deprecated('Use defaultNav (inherit Home|Do|Talk|Find) or customSurface '
      '(full-screen takeover) instead.  See SHELL-CARTRIDGE-MODEL.md.')
  Widget Function(BuildContext, ShellDeps)? get legacyBuildTab => null;

  /// Optional: map from typeHashHex → cell renderer.
  ///
  /// The shell's Talk surface calls each registered cartridge in
  /// registration order; the first non-null builder wins.  Unknown hashes
  /// fall back to the generic cell card.
  Map<String, Widget Function(BuildContext, Map<String, Object?>)>
      get cellRenderers => const {};

  // ── Legacy single-tab body (transitional) ────────────────────────────

  /// Legacy compatibility shim: the original `buildTab` API.  New code
  /// should prefer [defaultNav] / [customSurface].  Subclasses that
  /// override this without overriding [legacyBuildTab] still render
  /// because [ShellNav] falls back to calling this method.
  @Deprecated('Override defaultNav or customSurface instead.')
  Widget buildTab(BuildContext context, ShellDeps deps) {
    final legacy = legacyBuildTab;
    if (legacy != null) return legacy(context, deps);
    final custom = customSurface;
    if (custom != null) return custom(context, deps);
    return const Scaffold(
      body: Center(child: Text('Cartridge has no buildable surface')),
    );
  }
}

/// Concrete entry backed by a closure.
///
/// **Legacy shape** — preserved so the existing flat-nav HomeScreen
/// keeps building during the migration.  Treats the entry as a
/// foreground cartridge whose body is the closure.  New code should
/// prefer [ForegroundEntry] (default-nav grammar) or one of the typed
/// constructors below.
class SimpleEntry implements CartridgeEntry {
  SimpleEntry({
    required this.descriptor,
    required this.icon,
    required this.label,
    required Widget Function(BuildContext, ShellDeps) builder,
    this.cellRenderers = const {},
  }) : _builder = builder;

  final Widget Function(BuildContext, ShellDeps) _builder;

  @override
  final CartridgeDescriptor descriptor;
  @override
  final IconData icon;
  @override
  final String label;
  @override
  final Map<String, Widget Function(BuildContext, Map<String, Object?>)>
      cellRenderers;

  @override
  ShellPresentation get presentation => ShellPresentation.foreground;

  @override
  Widget Function(BuildContext, ShellDeps)? get headerBuilder => null;

  @override
  CartridgeDefaultNav? get defaultNav => null;

  @override
  Widget Function(BuildContext, ShellDeps)? get customSurface => _builder;

  @override
  CompanionAttachment? get companionAttachment => null;

  @override
  Future<void> onActivate(ShellDeps deps) async {}

  @override
  Future<void> onDeactivate(ShellDeps deps) async {}

  @override
  Widget Function(BuildContext, ShellDeps)? get legacyBuildTab => _builder;

  @override
  Widget buildTab(BuildContext context, ShellDeps deps) =>
      _builder(context, deps);
}

/// Foreground cartridge using the canonical Home|Do|Talk|Find grammar.
///
/// This is the common case — most cartridges inherit the shell's default
/// nav and contribute only the slot contents.
class ForegroundEntry implements CartridgeEntry {
  ForegroundEntry({
    required this.descriptor,
    required this.icon,
    required this.label,
    required this.defaultNav,
    this.headerBuilder,
    this.cellRenderers = const {},
    Future<void> Function(ShellDeps)? onActivate,
    Future<void> Function(ShellDeps)? onDeactivate,
  })  : _onActivate = onActivate,
        _onDeactivate = onDeactivate;

  @override
  final CartridgeDescriptor descriptor;
  @override
  final IconData icon;
  @override
  final String label;
  @override
  final Widget Function(BuildContext, ShellDeps)? headerBuilder;
  @override
  final CartridgeDefaultNav defaultNav;
  @override
  final Map<String, Widget Function(BuildContext, Map<String, Object?>)>
      cellRenderers;

  final Future<void> Function(ShellDeps)? _onActivate;
  final Future<void> Function(ShellDeps)? _onDeactivate;

  @override
  ShellPresentation get presentation => ShellPresentation.foreground;

  @override
  Widget Function(BuildContext, ShellDeps)? get customSurface => null;

  @override
  CompanionAttachment? get companionAttachment => null;

  @override
  Widget Function(BuildContext, ShellDeps)? get legacyBuildTab => null;

  @override
  Future<void> onActivate(ShellDeps deps) =>
      _onActivate?.call(deps) ?? Future.value();

  @override
  Future<void> onDeactivate(ShellDeps deps) =>
      _onDeactivate?.call(deps) ?? Future.value();

  @override
  Widget buildTab(BuildContext context, ShellDeps deps) =>
      defaultNav.buildHome(context, deps);
}

/// Foreground cartridge that opts out of the canonical grammar and owns
/// the whole body (jam-room, scada dashboards, immersive games).
class CustomSurfaceEntry implements CartridgeEntry {
  CustomSurfaceEntry({
    required this.descriptor,
    required this.icon,
    required this.label,
    required Widget Function(BuildContext, ShellDeps) build,
    this.headerBuilder,
    this.cellRenderers = const {},
    Future<void> Function(ShellDeps)? onActivate,
    Future<void> Function(ShellDeps)? onDeactivate,
  })  : _build = build,
        _onActivate = onActivate,
        _onDeactivate = onDeactivate;

  final Widget Function(BuildContext, ShellDeps) _build;
  final Future<void> Function(ShellDeps)? _onActivate;
  final Future<void> Function(ShellDeps)? _onDeactivate;

  @override
  final CartridgeDescriptor descriptor;
  @override
  final IconData icon;
  @override
  final String label;
  @override
  final Widget Function(BuildContext, ShellDeps)? headerBuilder;
  @override
  final Map<String, Widget Function(BuildContext, Map<String, Object?>)>
      cellRenderers;

  @override
  ShellPresentation get presentation => ShellPresentation.foreground;

  @override
  CartridgeDefaultNav? get defaultNav => null;

  @override
  Widget Function(BuildContext, ShellDeps)? get customSurface => _build;

  @override
  CompanionAttachment? get companionAttachment => null;

  @override
  Widget Function(BuildContext, ShellDeps)? get legacyBuildTab => null;

  @override
  Future<void> onActivate(ShellDeps deps) =>
      _onActivate?.call(deps) ?? Future.value();

  @override
  Future<void> onDeactivate(ShellDeps deps) =>
      _onDeactivate?.call(deps) ?? Future.value();

  @override
  Widget buildTab(BuildContext context, ShellDeps deps) => _build(context, deps);
}

/// Background cartridge — no UI, always-on.  Registers interceptors,
/// subscriptions, or other infrastructure in [onActivate].
///
/// Examples: wallet-headers, push-registration.
class BackgroundEntry implements CartridgeEntry {
  BackgroundEntry({
    required this.descriptor,
    required this.icon,
    required this.label,
    required Future<void> Function(ShellDeps) activate,
    Future<void> Function(ShellDeps)? deactivate,
  })  : _activate = activate,
        _deactivate = deactivate;

  final Future<void> Function(ShellDeps) _activate;
  final Future<void> Function(ShellDeps)? _deactivate;

  @override
  final CartridgeDescriptor descriptor;
  @override
  final IconData icon;
  @override
  final String label;

  @override
  ShellPresentation get presentation => ShellPresentation.background;

  @override
  Widget Function(BuildContext, ShellDeps)? get headerBuilder => null;
  @override
  CartridgeDefaultNav? get defaultNav => null;
  @override
  Widget Function(BuildContext, ShellDeps)? get customSurface => null;
  @override
  CompanionAttachment? get companionAttachment => null;
  @override
  Widget Function(BuildContext, ShellDeps)? get legacyBuildTab => null;
  @override
  Map<String, Widget Function(BuildContext, Map<String, Object?>)>
      get cellRenderers => const {};

  @override
  Future<void> onActivate(ShellDeps deps) => _activate(deps);

  @override
  Future<void> onDeactivate(ShellDeps deps) =>
      _deactivate?.call(deps) ?? Future.value();

  /// Background cartridges have no visible surface.  Called by accident
  /// (e.g. an admin surface listing them) returns a placeholder.
  @override
  Widget buildTab(BuildContext context, ShellDeps deps) =>
      const SizedBox.shrink();
}

/// Latent cartridge — usually invisible, interrupts the foreground when
/// a trigger fires.  Uses [onActivate] to arm the trigger.
///
/// Examples: wallet-payment (fires on Do action requiring sats),
/// ratification cards (fires on brain-pushed consent request).
class LatentEntry implements CartridgeEntry {
  LatentEntry({
    required this.descriptor,
    required this.icon,
    required this.label,
    required Future<void> Function(ShellDeps) arm,
    Future<void> Function(ShellDeps)? disarm,
  })  : _arm = arm,
        _disarm = disarm;

  final Future<void> Function(ShellDeps) _arm;
  final Future<void> Function(ShellDeps)? _disarm;

  @override
  final CartridgeDescriptor descriptor;
  @override
  final IconData icon;
  @override
  final String label;

  @override
  ShellPresentation get presentation => ShellPresentation.latent;

  @override
  Widget Function(BuildContext, ShellDeps)? get headerBuilder => null;
  @override
  CartridgeDefaultNav? get defaultNav => null;
  @override
  Widget Function(BuildContext, ShellDeps)? get customSurface => null;
  @override
  CompanionAttachment? get companionAttachment => null;
  @override
  Widget Function(BuildContext, ShellDeps)? get legacyBuildTab => null;
  @override
  Map<String, Widget Function(BuildContext, Map<String, Object?>)>
      get cellRenderers => const {};

  @override
  Future<void> onActivate(ShellDeps deps) => _arm(deps);

  @override
  Future<void> onDeactivate(ShellDeps deps) =>
      _disarm?.call(deps) ?? Future.value();

  @override
  Widget buildTab(BuildContext context, ShellDeps deps) =>
      const SizedBox.shrink();
}

/// Companion cartridge — augments a foreground host by contributing a
/// widget into one of the host's declared slot extension points.
class CompanionEntry implements CartridgeEntry {
  CompanionEntry({
    required this.descriptor,
    required this.icon,
    required this.label,
    required CompanionAttachment attachment,
  }) : _attachment = attachment;

  final CompanionAttachment _attachment;

  @override
  final CartridgeDescriptor descriptor;
  @override
  final IconData icon;
  @override
  final String label;

  @override
  ShellPresentation get presentation => ShellPresentation.companion;

  @override
  Widget Function(BuildContext, ShellDeps)? get headerBuilder => null;
  @override
  CartridgeDefaultNav? get defaultNav => null;
  @override
  Widget Function(BuildContext, ShellDeps)? get customSurface => null;
  @override
  CompanionAttachment? get companionAttachment => _attachment;
  @override
  Widget Function(BuildContext, ShellDeps)? get legacyBuildTab => null;
  @override
  Map<String, Widget Function(BuildContext, Map<String, Object?>)>
      get cellRenderers => const {};

  @override
  Future<void> onActivate(ShellDeps deps) async {}

  @override
  Future<void> onDeactivate(ShellDeps deps) async {}

  @override
  Widget buildTab(BuildContext context, ShellDeps deps) =>
      _attachment.build(context, deps);
}

// ════════════════════════════════════════════════════════════════════════
// Registry
// ════════════════════════════════════════════════════════════════════════

/// Immutable registry built once at boot from all registered cartridges.
///
/// Filtering by presentation role is the canonical way to ask "give me
/// all foreground cartridges for the switcher" or "give me all companion
/// cartridges attached to oddjobz".
class ShellCartridgeRegistry {
  ShellCartridgeRegistry(List<CartridgeEntry> entries)
      : _entries = List.unmodifiable(entries);

  final List<CartridgeEntry> _entries;

  List<CartridgeEntry> get entries => _entries;

  /// All foreground cartridges — the ones that appear in the cartridge
  /// switcher and can be selected as the current screen.
  List<CartridgeEntry> get foregroundEntries => _entries
      .where((e) => e.presentation == ShellPresentation.foreground)
      .toList(growable: false);

  /// All background cartridges — always-on, no UI presence.
  List<CartridgeEntry> get backgroundEntries => _entries
      .where((e) => e.presentation == ShellPresentation.background)
      .toList(growable: false);

  /// All latent cartridges — armed at activate, fire on trigger.
  List<CartridgeEntry> get latentEntries => _entries
      .where((e) => e.presentation == ShellPresentation.latent)
      .toList(growable: false);

  /// All companion cartridges attached to a specific host.
  List<CartridgeEntry> companionsFor(String hostCartridgeId) => _entries
      .where((e) =>
          e.presentation == ShellPresentation.companion &&
          e.companionAttachment?.hostCartridgeId == hostCartridgeId)
      .toList(growable: false);

  /// Look up a cell renderer across all cartridges.
  Widget Function(BuildContext, Map<String, Object?>)? rendererFor(
      String typeHashHex) {
    for (final e in _entries) {
      final fn = e.cellRenderers[typeHashHex];
      if (fn != null) return fn;
    }
    return null;
  }

  /// Look up a cartridge by descriptor id.  Useful for the switcher's
  /// "open this cartridge" path and for companions resolving their host.
  CartridgeEntry? byId(String id) {
    for (final e in _entries) {
      if (e.descriptor.id == id) return e;
    }
    return null;
  }
}

```
