---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/tests/intent-adapters/shell-to-intent.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.368476+00:00
---

# runtime/shell/tests/intent-adapters/shell-to-intent.test.ts

```ts
import { afterEach, describe, expect, test } from 'bun:test';
import {
  shellCommandToIntent,
  isShellVerbMutation,
} from '../../src/intent-adapters/shell-to-intent';
import type { ShellCommand, ShellVerb } from '../../src/parser';
import {
  registerVerb,
  _clearVerbRegistry,
} from '@semantos/runtime-services';

const mkCmd = (over: Partial<ShellCommand> = {}): ShellCommand => ({
  verb: 'transition',
  flags: {},
  rawArgs: [],
  ...over,
});

const opts = { generateId: () => 'intent-test-1' };

describe('shellCommandToIntent — null for read-only verbs', () => {
  const readOnly: ShellVerb[] = [
    'inspect',
    'trace',
    'verify',
    'list',
    'whoami',
    'capabilities',
    'taxonomy',
  ];
  for (const verb of readOnly) {
    test(`verb=${verb} returns null (bypasses pipeline)`, () => {
      expect(shellCommandToIntent(mkCmd({ verb }), opts)).toBeNull();
      expect(isShellVerbMutation(verb)).toBe(false);
    });
  }
});

describe('shellCommandToIntent — mutation verbs', () => {
  test('transition maps to jural/power', () => {
    const intent = shellCommandToIntent(
      mkCmd({ verb: 'transition', objectId: 'obj-42' }),
      opts,
    )!;
    expect(intent.category).toEqual({ lexicon: 'jural', category: 'power' });
    expect(intent.action).toBe('transition');
    expect(intent.target).toEqual({ objectId: 'obj-42' });
  });

  test('new maps to jural/declaration with typePath target', () => {
    const intent = shellCommandToIntent(
      mkCmd({ verb: 'new', typePath: 'core.Document' }),
      opts,
    )!;
    expect(intent.category).toEqual({ lexicon: 'jural', category: 'declaration' });
    expect(intent.action).toBe('new');
    expect(intent.target).toEqual({ typePath: 'core.Document' });
  });

  test('transfer maps to jural/transfer', () => {
    const intent = shellCommandToIntent(
      mkCmd({ verb: 'transfer', objectId: 'obj-1' }),
      opts,
    )!;
    expect(intent.category).toEqual({ lexicon: 'jural', category: 'transfer' });
  });

  test('stake, settle also map to jural/transfer', () => {
    expect(
      shellCommandToIntent(mkCmd({ verb: 'stake', objectId: 'o' }), opts)!.category,
    ).toEqual({ lexicon: 'jural', category: 'transfer' });
    expect(
      shellCommandToIntent(mkCmd({ verb: 'settle', objectId: 'o' }), opts)!.category,
    ).toEqual({ lexicon: 'jural', category: 'transfer' });
  });

  test('publish, revoke, share map to jural/power', () => {
    for (const verb of ['publish', 'revoke', 'share'] as const) {
      const intent = shellCommandToIntent(
        mkCmd({ verb, objectId: 'obj-1' }),
        opts,
      )!;
      expect(intent.category).toEqual({ lexicon: 'jural', category: 'power' });
    }
  });
});

// ── Registry-backed verbs (non-jural lexicon) ──────────────────

describe('shellCommandToIntent — verb registry produces non-jural TaggedCategory', () => {
  // `registerVerb` persists across tests in the same process; clear
  // after each so fixtures don't leak into later tests.
  afterEach(() => {
    _clearVerbRegistry();
  });

  test('ControlSystems-registered verb produces control-systems/acknowledgement Intent', () => {
    registerVerb({
      name: 'acknowledge_alarm',
      category: { lexicon: 'control-systems', category: 'acknowledgement' },
      action: 'acknowledge_alarm',
      mutation: true,
      // Handler doesn't matter for intent building; the adapter never
      // calls it. Shell's router is what invokes the handler.
      handler: async () => ({ ok: true }),
    });

    // `verb` is typed as ShellVerb (a fixed union in parser.ts), so
    // we cast our registered verb through for the test fixture.
    const intent = shellCommandToIntent(
      mkCmd({ verb: 'acknowledge_alarm' as unknown as ShellVerb }),
      opts,
    );

    expect(intent).not.toBeNull();
    expect(intent!.category).toEqual({
      lexicon: 'control-systems',
      category: 'acknowledgement',
    });
    expect(intent!.action).toBe('acknowledge_alarm');
  });

  test('registered read-only verb (mutation: false) returns null', () => {
    registerVerb({
      name: 'read_measurement',
      category: { lexicon: 'control-systems', category: 'measurement' },
      action: 'read_measurement',
      mutation: false,
      handler: async () => ({ ok: true }),
    });

    const out = shellCommandToIntent(
      mkCmd({ verb: 'read_measurement' as unknown as ShellVerb }),
      opts,
    );
    expect(out).toBeNull();
  });
});

describe('shellCommandToIntent — flag extraction', () => {
  test('--capability N becomes an SIRConstraint', () => {
    const intent = shellCommandToIntent(
      mkCmd({
        verb: 'transition',
        objectId: 'obj-1',
        flags: { capability: '5' },
      }),
      opts,
    )!;
    expect(intent.constraints).toEqual([
      { kind: 'capability', required: 5, name: 'cap-5' },
    ]);
  });

  test('--domain N becomes an SIRConstraint', () => {
    const intent = shellCommandToIntent(
      mkCmd({
        verb: 'transition',
        objectId: 'obj-1',
        flags: { domain: '7' },
      }),
      opts,
    )!;
    expect(intent.constraints).toEqual([{ kind: 'domain', flag: 7 }]);
  });

  test('unknown flags ride in producerMeta.flags, not constraints', () => {
    const intent = shellCommandToIntent(
      mkCmd({
        verb: 'new',
        typePath: 'trades.job',
        flags: { urgency: 'high', reason: 'drip' },
      }),
      opts,
    )!;
    expect(intent.constraints).toEqual([]);
    expect(intent.producerMeta?.flags).toEqual({ urgency: 'high', reason: 'drip' });
  });

  test('mixed known + unknown flags split correctly', () => {
    const intent = shellCommandToIntent(
      mkCmd({
        verb: 'transition',
        objectId: 'obj-1',
        flags: { capability: '5', urgency: 'high' },
      }),
      opts,
    )!;
    expect(intent.constraints).toHaveLength(1);
    expect(intent.constraints[0]!.kind).toBe('capability');
    expect(intent.producerMeta?.flags).toEqual({ urgency: 'high' });
  });

  test('non-numeric --capability value is ignored (not a valid constraint)', () => {
    const intent = shellCommandToIntent(
      mkCmd({
        verb: 'transition',
        objectId: 'obj-1',
        flags: { capability: 'SIGNING' },
      }),
      opts,
    )!;
    expect(intent.constraints).toEqual([]);
    expect(intent.producerMeta?.flags).toEqual({ capability: 'SIGNING' });
  });
});

describe('shellCommandToIntent — invariants', () => {
  test('source is always "shell" and confidence is always 1.0', () => {
    const intent = shellCommandToIntent(
      mkCmd({ verb: 'transition', objectId: 'obj-1' }),
      opts,
    )!;
    expect(intent.source).toBe('shell');
    expect(intent.confidence).toBe(1.0);
  });

  test('id comes from the injected generator', () => {
    const intent = shellCommandToIntent(
      mkCmd({ verb: 'transition', objectId: 'obj-1' }),
      { generateId: () => 'deterministic-123' },
    )!;
    expect(intent.id).toBe('deterministic-123');
  });

  test('taxonomy.how encodes the verb', () => {
    const intent = shellCommandToIntent(
      mkCmd({ verb: 'publish', objectId: 'obj-1', typePath: 'core.Document' }),
      opts,
    )!;
    expect(intent.taxonomy.how).toBe('shell.publish');
    expect(intent.taxonomy.what).toBe('core.Document');
    expect(intent.taxonomy.why).toBe('shell-invocation');
  });

  test('correlationId is passed through when supplied', () => {
    const intent = shellCommandToIntent(
      mkCmd({ verb: 'transition', objectId: 'obj-1' }),
      { generateId: () => 'i1', correlationId: 'corr-REPL-session-1' },
    )!;
    expect(intent.correlationId).toBe('corr-REPL-session-1');
  });

  test('rawArgs always persisted in producerMeta for replay', () => {
    const intent = shellCommandToIntent(
      mkCmd({
        verb: 'transition',
        objectId: 'obj-1',
        rawArgs: ['transition', 'obj-1', '--capability', '5'],
      }),
      opts,
    )!;
    expect(intent.producerMeta?.rawArgs).toEqual([
      'transition',
      'obj-1',
      '--capability',
      '5',
    ]);
  });
});

```
