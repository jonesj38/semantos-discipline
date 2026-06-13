---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/experience/test/cartridge_golden_path_test.dart
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.455976+00:00
---

# cartridges/oddjobz/experience/test/cartridge_golden_path_test.dart

```dart
// CC3 — oddjobz golden path, PWA half (Wave Canonical-Cartridge).
//
// The Brain-side half (resolver order, license gate consuming CC1's
// real SpvVerifier, manifest C3 binding) is proven in
// core/protocol-types/src/__tests__/cc3-oddjobz-golden-path.test.ts.
// This asserts the OTHER side of the cross-shell contract: the PWA
// CartridgeRegistry routes the SAME id the Brain serves
// (/api/v1/info cartridges[].id == 'oddjobz'), with the C3 binding.

import 'package:flutter_test/flutter_test.dart';
import 'package:cartridge_sdk/cartridge_sdk.dart';
import 'package:oddjobz_experience/oddjobz_experience.dart';

void main() {
  test('CC3: registerOddjobzCartridge wires the cross-shell contract', () {
    CartridgeRegistry.instance.resetForTest();
    registerOddjobzCartridge();

    final e = CartridgeRegistry.instance.byId('oddjobz');
    expect(e, isNotNull);
    // Same id the Brain manifest (extensions/oddjobz/manifest.json)
    // declares and serves at /api/v1/info — the cross-shell seam.
    expect(e!.id, 'oddjobz');
    expect(e.role, 'experience');
    expect(e.routePath, '/oddjobz');
    expect(e.descriptor.title, 'Oddjobz');

    // served() filter: only renders when the Brain advertises the id.
    expect(CartridgeRegistry.instance.served({'oddjobz'}).length, 1);
    expect(CartridgeRegistry.instance.served(<String>{}).length, 0);
  });
}

```
