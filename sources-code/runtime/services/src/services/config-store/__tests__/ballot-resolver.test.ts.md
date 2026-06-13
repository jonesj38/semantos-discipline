---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/config-store/__tests__/ballot-resolver.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.126548+00:00
---

# runtime/services/src/services/config-store/__tests__/ballot-resolver.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { resolveTaxonomyBallot } from '../ballot-resolver';

const finalized = (over: Record<string, unknown> = {}) => ({
  status: 'finalized',
  votesFor: 5,
  votesAgainst: 1,
  motion: JSON.stringify({
    axis: 'what',
    parentPath: 'what.thing',
    nodeName: 'New Box',
    functionType: 'sample',
  }),
  ...over,
});

describe('resolveTaxonomyBallot', () => {
  test('1. returns null for non-finalized ballots', () => {
    expect(resolveTaxonomyBallot({ ...finalized(), status: 'open' }, 'b-1')).toBeNull();
  });

  test('2. returns null when votesFor ≤ votesAgainst', () => {
    expect(resolveTaxonomyBallot({ ...finalized(), votesFor: 1, votesAgainst: 1 }, 'b-1')).toBeNull();
    expect(resolveTaxonomyBallot({ ...finalized(), votesFor: 1, votesAgainst: 2 }, 'b-1')).toBeNull();
  });

  test('3. returns null when motion is missing', () => {
    const b = finalized();
    delete (b as { motion?: unknown }).motion;
    expect(resolveTaxonomyBallot(b, 'b-1')).toBeNull();
  });

  test('4. returns null when motion is malformed JSON', () => {
    expect(resolveTaxonomyBallot({ ...finalized(), motion: 'not-json' }, 'b-1')).toBeNull();
  });

  test('5. returns null when required motion fields are absent', () => {
    expect(
      resolveTaxonomyBallot(
        { ...finalized(), motion: JSON.stringify({ axis: 'what' }) },
        'b-1',
      ),
    ).toBeNull();
  });

  test('6. derives the new path from parentPath + slugged nodeName', () => {
    const overlay = resolveTaxonomyBallot(finalized(), 'b-1');
    expect(overlay?.taxonomyNodes?.[0]!.path).toBe('what.thing.new-box');
  });

  test('7. forwards motion metadata into the overlay node', () => {
    const overlay = resolveTaxonomyBallot(
      finalized({
        motion: JSON.stringify({
          axis: 'what',
          parentPath: 'what.thing',
          nodeName: 'Box',
          functionType: 'sample',
          rationale: 'we need it',
          primaryOutputs: ['a'],
          requiredInputs: ['b'],
        }),
      }),
      'b-2',
    );
    expect(overlay?.taxonomyNodes?.[0]!.metadata).toMatchObject({
      function_type: 'sample',
      rationale: 'we need it',
      primary_outputs: ['a'],
      required_inputs: ['b'],
    });
  });

  test('8. tags overlay with source=ballot and the supplied ballotId', () => {
    const overlay = resolveTaxonomyBallot(finalized(), 'b-9');
    expect(overlay?.source).toBe('ballot');
    expect(overlay?.ballotId).toBe('b-9');
  });
});

```
