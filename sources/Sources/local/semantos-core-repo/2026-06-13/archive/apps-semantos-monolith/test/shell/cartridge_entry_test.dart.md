---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-semantos-monolith/test/shell/cartridge_entry_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.928802+00:00
---

# archive/apps-semantos-monolith/test/shell/cartridge_entry_test.dart

```dart
// Tests for the cartridge entry contract.
//
// Locks the presentation taxonomy + registry filtering shape against
// SHELL-CARTRIDGE-MODEL.md.  Pure-Dart tests (no Flutter binding) — the
// contract is data + closures only.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/src/identity/child_cert_store.dart';
import 'package:semantos/src/repl/repl_client.dart';
import 'package:semantos/src/shell/cartridge_entry.dart';
import 'package:semantos_core/semantos_core.dart' show CartridgeDescriptor;

void main() {
  group('CartridgeEntry presentation taxonomy', () {
    test('ForegroundEntry declares foreground presentation', () {
      final e = ForegroundEntry(
        descriptor: const CartridgeDescriptor(
          id: 'demo',
          routePath: '/demo',
          title: 'Demo',
          role: 'experience',
        ),
        icon: const IconData(0xe000),
        label: 'Demo',
        defaultNav: CartridgeDefaultNav(
          buildHome: (_, __) => const SizedBox.shrink(),
          buildDo: (_, __) => const SizedBox.shrink(),
          talkScope: const TalkScope(cartridgeId: 'demo'),
          contactsScope: const ContactsScope(cartridgeId: 'demo'),
        ),
      );
      expect(e.presentation, ShellPresentation.foreground);
      expect(e.defaultNav, isNotNull);
      expect(e.customSurface, isNull);
    });

    test('CustomSurfaceEntry has customSurface, no defaultNav', () {
      final e = CustomSurfaceEntry(
        descriptor: const CartridgeDescriptor(
          id: 'jam',
          routePath: '/jam',
          title: 'Jam',
          role: 'experience',
        ),
        icon: const IconData(0xe000),
        label: 'Jam',
        build: (_, __) => const SizedBox.shrink(),
      );
      expect(e.presentation, ShellPresentation.foreground);
      expect(e.defaultNav, isNull);
      expect(e.customSurface, isNotNull);
    });

    test('BackgroundEntry runs onActivate, has no UI surface', () async {
      var activated = false;
      var deactivated = false;
      final e = BackgroundEntry(
        descriptor: const CartridgeDescriptor(
          id: 'wallet-headers',
          routePath: '/_wallet-headers',
          title: 'Wallet Headers',
          role: 'infra',
        ),
        icon: const IconData(0xe000),
        label: 'WalletHdrs',
        activate: (_) async => activated = true,
        deactivate: (_) async => deactivated = true,
      );
      expect(e.presentation, ShellPresentation.background);
      expect(e.defaultNav, isNull);
      expect(e.customSurface, isNull);
      expect(e.headerBuilder, isNull);

      await e.onActivate(_fakeDeps);
      expect(activated, isTrue);

      await e.onDeactivate(_fakeDeps);
      expect(deactivated, isTrue);
    });

    test('LatentEntry arms on activate', () async {
      var armed = false;
      final e = LatentEntry(
        descriptor: const CartridgeDescriptor(
          id: 'ratify',
          routePath: '/ratify',
          title: 'Ratify',
          role: 'infra',
        ),
        icon: const IconData(0xe000),
        label: 'Ratify',
        arm: (_) async => armed = true,
      );
      expect(e.presentation, ShellPresentation.latent);
      await e.onActivate(_fakeDeps);
      expect(armed, isTrue);
    });

    test('CompanionEntry declares attachment to a host slot', () {
      final e = CompanionEntry(
        descriptor: const CartridgeDescriptor(
          id: 'wallet-balance-pill',
          routePath: '/_wallet-balance',
          title: 'Wallet Balance',
          role: 'experience',
        ),
        icon: const IconData(0xe000),
        label: 'Balance',
        attachment: CompanionAttachment(
          hostCartridgeId: 'oddjobz',
          slot: 'header.right',
          build: (_, __) => const SizedBox.shrink(),
        ),
      );
      expect(e.presentation, ShellPresentation.companion);
      expect(e.companionAttachment?.hostCartridgeId, 'oddjobz');
      expect(e.companionAttachment?.slot, 'header.right');
    });

    test('SimpleEntry stays backwards-compatible as foreground+customSurface',
        () {
      final e = SimpleEntry(
        descriptor: const CartridgeDescriptor(
          id: 'legacy',
          routePath: '/legacy',
          title: 'Legacy',
          role: 'experience',
        ),
        icon: const IconData(0xe000),
        label: 'Legacy',
        builder: (_, __) => const SizedBox.shrink(),
      );
      expect(e.presentation, ShellPresentation.foreground);
      expect(e.customSurface, isNotNull);
      expect(e.defaultNav, isNull);
    });
  });

  group('ShellCartridgeRegistry filtering', () {
    final foreground1 = ForegroundEntry(
      descriptor: const CartridgeDescriptor(
        id: 'fg1', routePath: '/fg1', title: 'FG1', role: 'experience'),
      icon: const IconData(0xe000),
      label: 'FG1',
      defaultNav: CartridgeDefaultNav(
        buildHome: (_, __) => const SizedBox.shrink(),
        buildDo: (_, __) => const SizedBox.shrink(),
        talkScope: const TalkScope(),
        contactsScope: const ContactsScope(),
      ),
    );
    final foreground2 = CustomSurfaceEntry(
      descriptor: const CartridgeDescriptor(
        id: 'fg2', routePath: '/fg2', title: 'FG2', role: 'experience'),
      icon: const IconData(0xe001),
      label: 'FG2',
      build: (_, __) => const SizedBox.shrink(),
    );
    final background1 = BackgroundEntry(
      descriptor: const CartridgeDescriptor(
        id: 'bg1', routePath: '/bg1', title: 'BG1', role: 'infra'),
      icon: const IconData(0xe002),
      label: 'BG1',
      activate: (_) async {},
    );
    final latent1 = LatentEntry(
      descriptor: const CartridgeDescriptor(
        id: 'lt1', routePath: '/lt1', title: 'LT1', role: 'infra'),
      icon: const IconData(0xe003),
      label: 'LT1',
      arm: (_) async {},
    );
    final companion1 = CompanionEntry(
      descriptor: const CartridgeDescriptor(
        id: 'cmp1', routePath: '/cmp1', title: 'CMP1', role: 'experience'),
      icon: const IconData(0xe004),
      label: 'CMP1',
      attachment: CompanionAttachment(
        hostCartridgeId: 'fg1',
        slot: 'header.right',
        build: (_, __) => const SizedBox.shrink(),
      ),
    );
    final companion2 = CompanionEntry(
      descriptor: const CartridgeDescriptor(
        id: 'cmp2', routePath: '/cmp2', title: 'CMP2', role: 'experience'),
      icon: const IconData(0xe005),
      label: 'CMP2',
      attachment: CompanionAttachment(
        hostCartridgeId: 'fg2',
        slot: 'do.fab',
        build: (_, __) => const SizedBox.shrink(),
      ),
    );

    final registry = ShellCartridgeRegistry([
      foreground1,
      foreground2,
      background1,
      latent1,
      companion1,
      companion2,
    ]);

    test('foregroundEntries filters to foreground only', () {
      expect(registry.foregroundEntries, [foreground1, foreground2]);
    });

    test('backgroundEntries filters to background only', () {
      expect(registry.backgroundEntries, [background1]);
    });

    test('latentEntries filters to latent only', () {
      expect(registry.latentEntries, [latent1]);
    });

    test('companionsFor returns only matching host attachments', () {
      expect(registry.companionsFor('fg1'), [companion1]);
      expect(registry.companionsFor('fg2'), [companion2]);
      expect(registry.companionsFor('nonexistent'), isEmpty);
    });

    test('byId looks up cartridge by descriptor id', () {
      expect(registry.byId('fg1'), foreground1);
      expect(registry.byId('bg1'), background1);
      expect(registry.byId('nope'), isNull);
    });
  });

  group('Scope types', () {
    test('TalkScope.global matches everything (null cartridgeId)', () {
      expect(TalkScope.global.cartridgeId, isNull);
      expect(TalkScope.global.threadKindAllowList, isNull);
    });

    test('FindScope.global has no type-path filter', () {
      expect(FindScope.global.typePathPrefixAllowList, isNull);
    });

    test('ContactsScope.global has no source/tag filter', () {
      expect(ContactsScope.global.sourceAllowList, isNull);
      expect(ContactsScope.global.tagAllowList, isNull);
    });

    test('cartridge-scoped TalkScope carries declared filters', () {
      const s = TalkScope(
        cartridgeId: 'oddjobz',
        threadKindAllowList: ['oddjobz.job-thread'],
      );
      expect(s.cartridgeId, 'oddjobz');
      expect(s.threadKindAllowList, ['oddjobz.job-thread']);
    });
  });
}

// Minimal fake deps for activate/deactivate tests.  We don't actually
// touch any of the real services — onActivate / onDeactivate hooks in
// these tests just record that they were called.
final _fakeDeps = ShellDeps(
  record: _FakeRecord(),
  repl: _FakeRepl(),
  http: null,
  baseUrl: 'https://example.test',
);

// noSuchMethod fakes so the contract tests don't need a paired brain.
class _FakeRecord implements ChildCertRecord {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRepl implements ReplClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

```
