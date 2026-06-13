---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/shell/cartridge_parity_wiring_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.131977+00:00
---

# apps/semantos/test/shell/cartridge_parity_wiring_test.dart

```dart
import 'package:betterment_experience/betterment_experience.dart';
import 'package:cartridge_sdk/cartridge_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oddjobz_experience/oddjobz_experience.dart';
import 'package:semantos_core/semantos_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CartridgeRegistry.instance.resetForTest();
    CustomVerbSurfaceRegistry.instance.resetForTest();
  });

  test('OddJobz and Betterment register user-visible cartridge entries', () {
    registerOddjobzCartridge();
    registerBettermentCartridge();

    final oddjobz = CartridgeRegistry.instance.byId('oddjobz');
    final betterment = CartridgeRegistry.instance.byId('betterment');

    expect(oddjobz, isNotNull);
    expect(oddjobz!.role, 'experience');
    expect(oddjobz.routePath, '/oddjobz');

    expect(betterment, isNotNull);
    expect(betterment!.role, 'experience');
    expect(betterment.routePath, '/betterment');

    expect(
      CustomVerbSurfaceRegistry.instance.has(kBettermentReleaseSurfaceKey),
      isTrue,
      reason: 'Betterment Release uses a custom cartridge-hosted field surface',
    );

    final served = CartridgeRegistry.instance.served({'oddjobz', 'betterment'});
    expect(
      served.map((entry) => entry.id),
      containsAll(['oddjobz', 'betterment']),
    );
  });

  test(
    'bundled OddJobz + Betterment manifests declare expected wired/unwired verbs',
    () async {
      final provisioner = ManifestProvisioner(
        verifier: const DevModeBundleVerifier(),
      );
      final provisioned = await Future.wait([
        OddjobzManifestLoader.provisionFromAsset(provisioner),
        BettermentManifestLoader.provisionFromAsset(provisioner),
      ]);
      final registry = GrammarRegistry.fromProvisioned(provisioned);

      expect(registry.byId('oddjobz'), isNotNull);
      expect(registry.byId('betterment'), isNotNull);

      final oddjobz = registry.byId('oddjobz')!;
      final oddjobzByIntent = {
        for (final v in oddjobz.uiVerbs) v.intentType: v,
      };
      expect(
        oddjobzByIntent.keys,
        containsAll(<String>[
          'oddjobz.job.create',
          'oddjobz.quote.create',
          'oddjobz.visit.create',
          'oddjobz.invoice.create',
          'oddjobz.customer.find',
          'oddjobz.job.find',
        ]),
      );
      for (final intentType in const [
        'oddjobz.job.create',
        'oddjobz.quote.create',
        'oddjobz.visit.create',
        'oddjobz.invoice.create',
      ]) {
        expect(
          oddjobzByIntent[intentType]?.dispatch,
          isNotNull,
          reason: '$intentType must be mint-wired from the manifest',
        );
      }
      expect(
        oddjobzByIntent['oddjobz.customer.find']?.dispatch,
        isNull,
        reason:
            'find verbs are visible read/query affordances, not mint verbs yet',
      );
      expect(oddjobzByIntent['oddjobz.job.find']?.dispatch, isNull);

      final betterment = registry.byId('betterment')!;
      final bettermentByIntent = {
        for (final v in betterment.uiVerbs) v.intentType: v,
      };
      expect(
        bettermentByIntent.keys,
        containsAll(<String>['Release', 'SetIntention', 'EveningReview']),
      );
      expect(bettermentByIntent['Release']?.dispatch, isNotNull);
      expect(
        bettermentByIntent['Release']?.inputShape?.customKey,
        kBettermentReleaseSurfaceKey,
        reason:
            'Release should route through Betterment custom capture surface',
      );
      expect(bettermentByIntent['SetIntention']?.dispatch, isNull);
      expect(bettermentByIntent['EveningReview']?.dispatch, isNull);
    },
  );

  test(
    'active cartridge scoping prevents OddJobz/Betterment verb bleed',
    () async {
      final provisioner = ManifestProvisioner(
        verifier: const DevModeBundleVerifier(),
      );
      final provisioned = await Future.wait([
        OddjobzManifestLoader.provisionFromAsset(provisioner),
        BettermentManifestLoader.provisionFromAsset(provisioner),
      ]);
      final registry = GrammarRegistry.fromProvisioned(provisioned);

      final oddjobzDo = registry.verbsForModalAndExtension(
        HelmVerbModal.do_,
        'oddjobz',
      );
      expect(
        oddjobzDo.map((b) => b.extensionId).toSet(),
        {'oddjobz'},
        reason: 'OddJobz scope must not surface Betterment field verbs',
      );
      expect(
        oddjobzDo.map((b) => b.verb.intentType),
        isNot(contains('Release')),
      );
      expect(
        oddjobzDo.map((b) => b.verb.intentType),
        containsAll([
          'oddjobz.job.create',
          'oddjobz.quote.create',
          'oddjobz.visit.create',
          'oddjobz.invoice.create',
        ]),
      );

      final bettermentDo = registry.verbsForModalAndExtension(
        HelmVerbModal.do_,
        'betterment',
      );
      expect(
        bettermentDo.map((b) => b.extensionId).toSet(),
        {'betterment'},
        reason: 'Betterment scope must not surface OddJobz field verbs',
      );
      expect(bettermentDo.map((b) => b.verb.intentType), contains('Release'));
      expect(
        bettermentDo.map((b) => b.verb.intentType),
        isNot(contains('oddjobz.job.create')),
      );

      final unscopedDo = registry.verbsForModal(HelmVerbModal.do_);
      expect(
        unscopedDo.map((b) => b.extensionId).toSet(),
        containsAll({'oddjobz', 'betterment'}),
        reason:
            'Unscoped helm intentionally aggregates default-mode field verbs; scoped helm must be used for hard boundaries.',
      );
    },
  );
}

```
