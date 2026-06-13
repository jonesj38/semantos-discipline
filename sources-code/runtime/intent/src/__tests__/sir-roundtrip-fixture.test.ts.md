---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/intent/src/__tests__/sir-roundtrip-fixture.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.353133+00:00
---

# runtime/intent/src/__tests__/sir-roundtrip-fixture.test.ts

```ts
/**
 * D-O5m.followup-3 Phase 2 — cross-language SIR roundtrip parity.
 *
 * Reference: runtime/intent/scripts/gen-sir-roundtrip-fixture.ts
 *            (the fixture generator);
 *            apps/oddjobz-mobile/test/voice/sir_roundtrip_test.dart
 *            (the Dart-side parity test consuming the same fixture);
 *            runtime/intent/src/types.ts (the canonical Intent
 *            declaration order this canonicaliser mirrors).
 *
 * Asserts:
 *   (1) the fixture's canonicalIntentJson is byte-identical to the
 *       output of canonicaliseIntent() + JSON.stringify on the TS
 *       side -- this catches regressions where the canonicaliser
 *       grows a phantom field or reorders keys
 *   (2) the canonical key order matches the declaration order in
 *       runtime/intent/src/types.ts (decoupled here so a TS-only
 *       reorder doesn't silently break Dart parity)
 *
 * The Dart test (sir_roundtrip_test.dart) loads the same fixture
 * and runs canonicaliseIntent through encodeCanonicalIntent;
 * cross-language byte-parity falls out as long as both sides keep
 * the same ORDER constant + json encoding rules.
 */

import { describe, expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

interface Fixture {
  transcript: string;
  expectedIntent: Record<string, unknown>;
  canonicalIntentJson: string;
  canonicalKeyOrder: string[];
}

const FIXTURE_PATH = resolve(__dirname, '../../fixtures/sir-roundtrip-fixture.json');

const ORDER: ReadonlyArray<string> = [
  'id',
  'correlationId',
  'companionOf',
  'summary',
  'category',
  'taxonomy',
  'action',
  'constraints',
  'target',
  'transferTo',
  'fulfillment',
  'confidence',
  'source',
  'producerMeta',
];

function canonicaliseIntent(input: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const k of ORDER) {
    if (Object.prototype.hasOwnProperty.call(input, k) && input[k] != null) {
      out[k] = input[k];
    }
  }
  for (const [k, v] of Object.entries(input)) {
    if (!Object.prototype.hasOwnProperty.call(out, k) && v != null) {
      out[k] = v;
    }
  }
  return out;
}

describe('SIR roundtrip fixture (cross-language parity)', () => {
  const fixture = JSON.parse(readFileSync(FIXTURE_PATH, 'utf-8')) as Fixture;

  test('fixture canonicalIntentJson is reproducible from expectedIntent', () => {
    const got = JSON.stringify(canonicaliseIntent(fixture.expectedIntent));
    expect(got).toBe(fixture.canonicalIntentJson);
  });

  test('canonical key order in fixture matches the declared ORDER', () => {
    // Filter ORDER to keys actually present in the fixture's
    // expectedIntent -- the fixture only populates a subset of the
    // optional fields.
    const present = ORDER.filter((k) =>
      Object.prototype.hasOwnProperty.call(fixture.expectedIntent, k),
    );
    expect(fixture.canonicalKeyOrder).toEqual(present);
  });

  test('canonicalIntentJson keys appear in declaration order', () => {
    // Walk the JSON string and assert each ORDER key appears in
    // ascending position.  Catches a subtle bug where the
    // canonicaliser sorted alphabetically by accident.
    const positions = ORDER
      .filter((k) =>
        Object.prototype.hasOwnProperty.call(fixture.expectedIntent, k),
      )
      .map((k) => fixture.canonicalIntentJson.indexOf(`"${k}":`));
    for (let i = 1; i < positions.length; i++) {
      expect(positions[i]).toBeGreaterThan(positions[i - 1]!);
    }
  });

  test('every populated field passes through with non-null value', () => {
    for (const k of fixture.canonicalKeyOrder) {
      expect(fixture.expectedIntent[k]).not.toBeNull();
      expect(fixture.expectedIntent[k]).not.toBeUndefined();
    }
  });
});

```
