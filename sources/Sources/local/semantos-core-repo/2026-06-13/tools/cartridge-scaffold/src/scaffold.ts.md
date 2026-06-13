---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tools/cartridge-scaffold/src/scaffold.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.561535+00:00
---

# tools/cartridge-scaffold/src/scaffold.ts

```ts
/**
 * RM-097 — voice → cartridge dogfood loop (scaffold half).
 *
 * Generates a working cartridge skeleton under `<targetDir>/<name>/`:
 *
 *   <name>/
 *     package.json
 *     src/
 *       cells.ts                 — sample typed cell using RM-096 signatures
 *       __fixtures__/
 *         intent-fixture.ts      — captured StageEvent fingerprint (RM-094)
 *       __tests__/
 *         cartridge.test.ts      — regression test asserting fingerprint
 *
 * The cells/ file uses RM-096 `defineCell` so the cartridge author
 * gets compile-time stack-shape checking from line one. The fixture
 * is the structural fingerprint of whatever trace the author hands
 * in — RM-094's `fingerprintTrace` output, embedded as a TS literal.
 *
 * No LLM. No voice capture in this module — that lives one layer up
 * (brain CLI) and feeds a JSONL trace file in. Keeps this tool
 * deterministic and unit-testable.
 */

import { fingerprintTrace, type FixtureEvent } from '../../intent-trace/src/to-fixture.js';
import { parseTrace } from '../../intent-trace/src/parse.js';

export interface ScaffoldInput {
  /** Cartridge name (kebab-case). Used as the directory name + the
   *  generated package's `name` field after a `@cartridges/` prefix. */
  name: string;
  /** Absolute target directory under which `<name>/` will be created. */
  targetDir: string;
  /** Optional captured JSONL trace. When supplied, the fixture is
   *  derived from the first correlation group in the trace. When
   *  omitted, a minimal placeholder fingerprint is emitted so the
   *  scaffolded test still runs (and fails meaningfully). */
  traceJsonl?: string;
  /** Reducer fixture name to assert against in the regression test.
   *  Default: `T1_REPORT_DRIPPING_TAP` — the canonical dogfood input. */
  inputFixtureName?: string;
}

export interface ScaffoldFile {
  /** Path relative to `targetDir/<name>/`. */
  path: string;
  contents: string;
}

export interface ScaffoldResult {
  /** Absolute root directory (`<targetDir>/<name>/`). */
  root: string;
  /** Files written during the scaffold. */
  files: ReadonlyArray<ScaffoldFile>;
}

const DEFAULT_INPUT_FIXTURE = 'T1_REPORT_DRIPPING_TAP';

/** Compute the list of files a scaffold would produce. Pure function —
 *  callers can use this to preview before writing to disk, or to assert
 *  scaffold contents in tests without touching the filesystem. */
export function planScaffold(input: ScaffoldInput): ReadonlyArray<ScaffoldFile> {
  if (!/^[a-z][a-z0-9-]*$/.test(input.name)) {
    throw new Error(
      `cartridge name must be kebab-case (lowercase + dashes), got '${input.name}'`,
    );
  }
  const inputFixtureName = input.inputFixtureName ?? DEFAULT_INPUT_FIXTURE;
  const fingerprint = deriveFingerprint(input.traceJsonl);

  return [
    { path: 'package.json', contents: renderPackageJson(input.name) },
    { path: 'src/cells.ts', contents: renderCells(input.name) },
    {
      path: 'src/__fixtures__/intent-fixture.ts',
      contents: renderFixture(fingerprint, inputFixtureName),
    },
    {
      path: 'src/__tests__/cartridge.test.ts',
      contents: renderTest(input.name, inputFixtureName),
    },
  ];
}

/** Materialise the scaffold to disk using Bun's file APIs. Idempotent
 *  in the sense that overwriting an existing file is allowed — but the
 *  function does NOT delete unrelated files. */
export async function writeScaffold(input: ScaffoldInput): Promise<ScaffoldResult> {
  const files = planScaffold(input);
  const root = `${input.targetDir}/${input.name}`;
  for (const f of files) {
    const full = `${root}/${f.path}`;
    // Bun.write creates intermediate directories on its own — no
    // explicit mkdir needed.
    await Bun.write(full, f.contents);
  }
  return { root, files };
}

// ─── File-content renderers ──────────────────────────────────────────

function renderPackageJson(name: string): string {
  return JSON.stringify(
    {
      name: `@cartridges/${name}`,
      version: '0.1.0',
      type: 'module',
      private: true,
      scripts: {
        test: 'bun test',
        check: 'tsc --noEmit',
      },
      dependencies: {
        '@semantos/cell-ops': 'workspace:*',
        '@semantos/intent': 'workspace:*',
      },
      devDependencies: {
        'bun-types': '^1.3.13',
        typescript: '~5.8.0',
      },
    },
    null,
    2,
  ) + '\n';
}

function renderCells(name: string): string {
  return `/**
 * ${name} — scaffolded cartridge cells (RM-097 dogfood loop).
 *
 * Edit \`mySampleCell\` to express the cartridge's first behaviour.
 * \`defineCell\` from @semantos/cell-ops enforces pre/post stack-shape
 * checking at compile time — composition errors fire at the call site,
 * not at runtime.
 */
import { defineCell, compose } from '@semantos/cell-ops';

/** Pushes a capability token reference on the stack. Replace with the
 *  capability your cartridge actually needs. */
export const pushCapability = defineCell({
  name: 'pushCapability',
  pre: [] as const,
  post: ['capability'] as const,
  body: { op: 'OP_PUSH', value: 'capability-placeholder' },
});

/** Verifies the capability is unspent. */
export const checkCapability = defineCell({
  name: 'checkCapability',
  pre: ['capability'] as const,
  post: ['bool'] as const,
  body: { op: 'OP_CHECKCAPABILITY' },
});

/** Asserts the bool — kernel rejects on false. */
export const verifyBool = defineCell({
  name: 'verifyBool',
  pre: ['bool'] as const,
  post: [] as const,
  body: { op: 'OP_VERIFY' },
});

/** The cartridge's entry composition. TS type-checks the stack shapes
 *  across the chain — swap a cell out for one with the wrong pre and
 *  the editor underlines the mismatch immediately. */
export const ${camelCase(name)}Entry = compose(
  compose(pushCapability, checkCapability),
  verifyBool,
);
`;
}

function renderFixture(fingerprint: ReadonlyArray<FixtureEvent>, inputFixtureName: string): string {
  return `/**
 * Auto-generated intent fingerprint for the cartridge's regression
 * test. Captured from a real reducer run of \`${inputFixtureName}\`.
 * Refresh by re-running the dogfood loop:
 *
 *   intent-trace fixturize trace.jsonl --input ${inputFixtureName} \\
 *     > src/__fixtures__/intent-fixture.ts
 *
 * Do not edit by hand.
 */
import type { FixtureEvent } from '../../../../tools/intent-trace/src/to-fixture';

export const CAPTURED_FINGERPRINT: FixtureEvent[] = ${JSON.stringify(fingerprint, null, 2)};

export const INPUT_FIXTURE_NAME = '${inputFixtureName}' as const;
`;
}

function renderTest(name: string, inputFixtureName: string): string {
  return `/**
 * ${name} — cartridge regression test (RM-097 dogfood loop).
 *
 * Asserts the structural fingerprint of \`${inputFixtureName}\` against
 * a fresh reducer run. Fails with a meaningful diff naming the
 * offending pass when behaviour drifts.
 */
import { describe, expect, test } from 'bun:test';
import { reduceToIntent } from '@semantos/intent/reducer';
import { createInMemoryLogger } from '@semantos/intent';
import type { CorrelationId } from '@semantos/intent';
import { ${inputFixtureName} } from '../../../../runtime/intent/src/reducer/__fixtures__/trades-fixtures';
import { fingerprintTrace } from '../../../../tools/intent-trace/src/to-fixture';
import { parseTrace } from '../../../../tools/intent-trace/src/parse';
import { CAPTURED_FINGERPRINT } from '../__fixtures__/intent-fixture';
import { ${camelCase(name)}Entry } from '../cells';

describe('${name} cartridge', () => {
  test('typed cells export the expected composition entry', () => {
    expect(${camelCase(name)}Entry.pre).toEqual([]);
    expect(${camelCase(name)}Entry.post).toEqual([]);
  });

  test('intent fingerprint matches the captured trace', async () => {
    const logger = createInMemoryLogger();
    await reduceToIntent(${inputFixtureName}.input, ${inputFixtureName}.grammar, {
      logger,
      correlationId: 'corr-${name}-test' as CorrelationId,
    });
    const jsonl = logger.events.map((e) => JSON.stringify(e)).join('\\n');
    const live = fingerprintTrace(parseTrace(jsonl));
    expect(live).toEqual(CAPTURED_FINGERPRINT);
  });
});
`;
}

// ─── Helpers ─────────────────────────────────────────────────────────

function deriveFingerprint(jsonl?: string): ReadonlyArray<FixtureEvent> {
  if (!jsonl || jsonl.trim().length === 0) {
    // Placeholder — the scaffold runs even without a captured trace.
    // The test will then fail meaningfully on first run, prompting the
    // author to re-fixturize.
    return [];
  }
  const events = parseTrace(jsonl);
  if (events.length === 0) return [];
  // Use the first correlation group's fingerprint.
  const firstCorr = events[0]!.correlationId;
  const group = events.filter((e) => e.correlationId === firstCorr);
  return fingerprintTrace(group);
}

function camelCase(kebab: string): string {
  return kebab.replace(/-([a-z0-9])/g, (_, c) => c.toUpperCase());
}

```
