---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/semantos/test/shell/no_cert_banner_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.131705+00:00
---

# apps/semantos/test/shell/no_cert_banner_test.dart

```dart
// SemantosRouter: detect-only no-cert banner.
//
// The banner is the operator-visible side of "wallet paired but no
// identity cert provisioned." Detect-only by design — cert
// provisioning is parked in the phase-1b cluster, so the banner does
// not link to a remediation flow. This test gates the flag-flip
// behaviour:
//
//   - hasIdentity=false → banner present (Container with the
//     `no-cert-banner` key + the expected warning copy).
//   - hasIdentity=true  → banner absent, full screen for the route
//     content (`builder` hook not engaged).
//
// We don't drive a real IntentDispatcher; the router falls back to
// the _BootIncompleteScreen, which is enough surface to anchor the
// banner-presence assertion.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semantos/shell/semantos_router.dart';

void main() {
  group('SemantosRouter no-cert banner', () {
    testWidgets('renders banner when hasIdentity is false', (tester) async {
      await tester.pumpWidget(
        const SemantosRouter(
          dispatcher: null,
          hasIdentity: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('no-cert-banner')),
        findsOneWidget,
        reason: 'banner Container should be in the tree when hasIdentity=false',
      );
      expect(
        find.textContaining('No identity cert'),
        findsOneWidget,
        reason: 'banner copy should be visible to the operator',
      );
    });

    testWidgets('omits banner when hasIdentity is true', (tester) async {
      await tester.pumpWidget(
        const SemantosRouter(
          dispatcher: null,
          hasIdentity: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('no-cert-banner')),
        findsNothing,
        reason: 'banner must not appear when an identity cert is loaded',
      );
      expect(
        find.textContaining('No identity cert'),
        findsNothing,
      );
    });

    testWidgets('hasIdentity defaults to true (banner absent)', (tester) async {
      // Defensive: if a future caller forgets to pass hasIdentity, we
      // must not gratuitously banner the operator. The default has to
      // stay "assume identity present"; failure-to-load is the
      // only thing that should flip it.
      await tester.pumpWidget(
        const SemantosRouter(dispatcher: null),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('no-cert-banner')), findsNothing);
    });
  });
}

```
