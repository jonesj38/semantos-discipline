---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/__tests__/coherence-checker.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.123625+00:00
---

# runtime/services/src/services/intent-classifier/__tests__/coherence-checker.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import { checkCoherence } from '../coherence-checker';
import { coherencePort } from '../ports';

afterEach(() => coherencePort.unbind());

describe('checkCoherence', () => {
  test('1. returns null when port is unbound', () => {
    expect(checkCoherence(['create', 'job'])).toBeNull();
  });

  test('2. returns null for short paths regardless of binding', () => {
    coherencePort.bind({
      checkNode: () => ({
        nodePath: 'a',
        embeddingNearest: 'b',
        severity: 'info',
      }),
    });
    expect(checkCoherence(['solo'])).toBeNull();
  });

  test('3. returns null when checker returns null', () => {
    coherencePort.bind({ checkNode: () => null });
    expect(checkCoherence(['create', 'job'])).toBeNull();
  });

  test('4. wraps misalignment into a CoherenceWarning with explanatory message', () => {
    coherencePort.bind({
      checkNode: () => ({
        nodePath: 'create.job',
        embeddingNearest: 'add.task',
        severity: 'warning',
      }),
    });
    const warn = checkCoherence(['create', 'job']);
    expect(warn?.severity).toBe('warning');
    expect(warn?.nodePath).toBe('create.job');
    expect(warn?.embeddingNearest).toBe('add.task');
    expect(warn?.message).toMatch(/govern\.challenge-classification/);
  });

  test('5. forwards severity tiers verbatim', () => {
    for (const severity of ['info', 'warning', 'critical'] as const) {
      coherencePort.unbind();
      coherencePort.bind({
        checkNode: () => ({ nodePath: 'a.b', embeddingNearest: 'c.d', severity }),
      });
      expect(checkCoherence(['a', 'b'])?.severity).toBe(severity);
    }
  });
});

```
