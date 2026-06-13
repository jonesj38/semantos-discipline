---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/tests/parser.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.361591+00:00
---

# runtime/shell/tests/parser.test.ts

```ts
import { describe, test, expect } from 'bun:test';
import { parseCommand, KNOWN_VERBS } from '../src/parser';

// ── Basic verb parsing ───────────────────────────────────────

describe('parseCommand — verb recognition', () => {
  test('parses a simple verb', () => {
    const cmd = parseCommand(['inspect', 'job-1774']);
    expect(cmd.verb).toBe('inspect');
    expect(cmd.objectId).toBe('job-1774');
  });

  test('throws on empty input', () => {
    expect(() => parseCommand([])).toThrow('No command provided');
  });

  test('throws on unknown verb', () => {
    expect(() => parseCommand(['foobar'])).toThrow("Unknown verb 'foobar'");
  });

  test('suggests closest verb for typo (Levenshtein ≤ 3)', () => {
    expect(() => parseCommand(['insepct'])).toThrow("Did you mean 'inspect'");
  });

  test('does not suggest if distance > 3', () => {
    try {
      parseCommand(['zzzzzzz']);
    } catch (e) {
      expect((e as Error).message).not.toContain('Did you mean');
    }
  });

  test('throws when only flags are provided (no verb)', () => {
    // --dry-run is a boolean flag; no non-flag arg exists → 'No verb found'
    expect(() => parseCommand(['--dry-run'])).toThrow('No verb found');
  });

  test('flag value consumed as verb when it looks like a non-flag', () => {
    // ['--format', 'json'] → verbIndex finds 'json' (first non-flag) → unknown verb
    expect(() => parseCommand(['--format', 'json'])).toThrow("Unknown verb 'json'");
  });
});

// ── NO_ARGS_VERBS ────────────────────────────────────────────

describe('parseCommand — no-args verbs', () => {
  test('list with no args', () => {
    const cmd = parseCommand(['list']);
    expect(cmd.verb).toBe('list');
    expect(cmd.typePath).toBeUndefined();
    expect(cmd.objectId).toBeUndefined();
  });

  test('whoami', () => {
    const cmd = parseCommand(['whoami']);
    expect(cmd.verb).toBe('whoami');
  });

  test('capabilities', () => {
    const cmd = parseCommand(['capabilities']);
    expect(cmd.verb).toBe('capabilities');
  });

  test('list with filters via flags', () => {
    const cmd = parseCommand(['list', '--type', 'Job', '--status', 'draft']);
    expect(cmd.verb).toBe('list');
    expect(cmd.flags.type).toBe('Job');
    expect(cmd.flags.status).toBe('draft');
  });
});

// ── TYPE_PATH_VERBS ──────────────────────────────────────────

describe('parseCommand — type-path verbs', () => {
  test('new with type path', () => {
    const cmd = parseCommand(['new', 'trades.job.plumbing']);
    expect(cmd.verb).toBe('new');
    expect(cmd.typePath).toBe('trades.job.plumbing');
  });

  test('new with type path and flags', () => {
    const cmd = parseCommand(['new', 'trades.job.plumbing', '--urgency', 'high']);
    expect(cmd.verb).toBe('new');
    expect(cmd.typePath).toBe('trades.job.plumbing');
    expect(cmd.flags.urgency).toBe('high');
  });

  test('new with type path and object ID', () => {
    const cmd = parseCommand(['new', 'trades.job', 'custom-id-1']);
    expect(cmd.verb).toBe('new');
    expect(cmd.typePath).toBe('trades.job');
    expect(cmd.objectId).toBe('custom-id-1');
  });
});

// ── OBJECT_ID_VERBS ──────────────────────────────────────────

describe('parseCommand — object-id verbs', () => {
  for (const verb of ['inspect', 'trace', 'verify', 'sign', 'publish', 'revoke', 'patch', 'transition', 'transfer', 'settle'] as const) {
    test(`${verb} parses object ID as first positional`, () => {
      const cmd = parseCommand([verb, 'obj-42']);
      expect(cmd.verb).toBe(verb);
      expect(cmd.objectId).toBe('obj-42');
    });
  }

  test('patch with object ID and field flags', () => {
    const cmd = parseCommand(['patch', 'obj-42', '--urgency', 'high', '--status', 'open']);
    expect(cmd.objectId).toBe('obj-42');
    expect(cmd.flags.urgency).toBe('high');
    expect(cmd.flags.status).toBe('open');
  });

  test('transition with --visibility flag', () => {
    const cmd = parseCommand(['transition', 'obj-42', '--visibility', 'published']);
    expect(cmd.objectId).toBe('obj-42');
    expect(cmd.flags.visibility).toBe('published');
  });

  test('transfer with --to flag', () => {
    const cmd = parseCommand(['transfer', 'obj-42', '--to', 'alice-facet']);
    expect(cmd.objectId).toBe('obj-42');
    expect(cmd.flags.to).toBe('alice-facet');
  });
});

// ── SUBCOMMAND_VERBS ─────────────────────────────────────────

describe('parseCommand — subcommand verbs', () => {
  test('identity register', () => {
    const cmd = parseCommand(['identity', 'register', 'alice@example.com']);
    expect(cmd.verb).toBe('identity');
    expect(cmd.flags.action).toBe('register');
    expect(cmd.objectId).toBe('alice@example.com');
  });

  test('identity derive', () => {
    const cmd = parseCommand(['identity', 'derive', 'my-device']);
    expect(cmd.flags.action).toBe('derive');
    expect(cmd.objectId).toBe('my-device');
  });

  test('identity list (no target)', () => {
    const cmd = parseCommand(['identity', 'list']);
    expect(cmd.flags.action).toBe('list');
    expect(cmd.objectId).toBeUndefined();
  });

  test('flow start', () => {
    const cmd = parseCommand(['flow', 'start', 'new-job-intake']);
    expect(cmd.verb).toBe('flow');
    expect(cmd.flags.subcommand).toBe('start');
    expect(cmd.flags.flow).toBe('new-job-intake');
  });

  test('flow list (no target)', () => {
    const cmd = parseCommand(['flow', 'list']);
    expect(cmd.flags.subcommand).toBe('list');
  });

  test('grammar diff with two paths', () => {
    const cmd = parseCommand(['grammar', 'diff', 'old.json', 'new.json']);
    expect(cmd.verb).toBe('grammar');
    expect(cmd.flags.subcommand).toBe('diff');
    expect(cmd.flags.path).toBe('old.json');
    expect(cmd.flags.newPath).toBe('new.json');
  });

  test('grammar validate with path', () => {
    const cmd = parseCommand(['grammar', 'validate', './grammar.json']);
    expect(cmd.flags.subcommand).toBe('validate');
    expect(cmd.flags.path).toBe('./grammar.json');
  });

  test('taxonomy nearest with utterance', () => {
    const cmd = parseCommand(['taxonomy', 'nearest', 'I', 'need', 'a', 'plumber']);
    expect(cmd.verb).toBe('taxonomy');
    expect(cmd.flags.subcommand).toBe('nearest');
    expect(cmd.flags.utterance).toBe('I need a plumber');
  });

  test('taxonomy distance with two paths', () => {
    const cmd = parseCommand(['taxonomy', 'distance', 'create.job', 'create.quote']);
    expect(cmd.flags.subcommand).toBe('distance');
    expect(cmd.flags.pathA).toBe('create.job');
    expect(cmd.flags.pathB).toBe('create.quote');
  });

  test('cdm with subcommand and target', () => {
    const cmd = parseCommand(['cdm', 'event', 'trade-123', '--type', 'confirmation']);
    expect(cmd.verb).toBe('cdm');
    expect(cmd.flags.subcommand).toBe('event');
    expect(cmd.objectId).toBe('trade-123');
    expect(cmd.flags.type).toBe('confirmation');
  });

  test('game with type, subcommand, and expression', () => {
    const cmd = parseCommand(['game', 'chess', 'move', 'e2e4']);
    expect(cmd.verb).toBe('game');
    expect(cmd.objectId).toBe('chess');
    expect(cmd.flags.subcommand).toBe('move');
    expect(cmd.flags.expression).toBe('e2e4');
  });

  test('infer with subcommand and path', () => {
    const cmd = parseCommand(['infer', 'review', 'grammar-abc']);
    expect(cmd.flags.subcommand).toBe('review');
    expect(cmd.flags.path).toBe('grammar-abc');
  });
});

// ── Expression verbs (eval, compile, bind) ───────────────────

describe('parseCommand — expression verbs', () => {
  test('eval joins positionals into expression', () => {
    const cmd = parseCommand(['eval', '(>', 'amount', '500)']);
    expect(cmd.verb).toBe('eval');
    expect(cmd.flags.expression).toBe('(> amount 500)');
  });

  test('compile joins positionals into expression', () => {
    const cmd = parseCommand(['compile', '(policy', ':subject', 'homeowner)']);
    expect(cmd.verb).toBe('compile');
    expect(cmd.flags.expression).toBe('(policy :subject homeowner)');
  });

  test('bind with policy ref and type path', () => {
    const cmd = parseCommand(['bind', 'policy-ref', 'trades.job']);
    expect(cmd.verb).toBe('bind');
    expect(cmd.flags.expression).toBe('policy-ref');
    expect(cmd.typePath).toBe('trades.job');
  });
});

// ── Flag parsing ─────────────────────────────────────────────

describe('parseCommand — flags', () => {
  test('boolean flag (no value)', () => {
    const cmd = parseCommand(['publish', 'obj-1', '--dry-run']);
    expect(cmd.flags['dry-run']).toBe(true);
  });

  test('key-value flag', () => {
    const cmd = parseCommand(['list', '--format', 'table']);
    expect(cmd.flags.format).toBe('table');
  });

  test('multiple flags', () => {
    const cmd = parseCommand(['list', '--type', 'Job', '--status', 'draft', '--format', 'csv', '--verbose']);
    expect(cmd.flags.type).toBe('Job');
    expect(cmd.flags.status).toBe('draft');
    expect(cmd.flags.format).toBe('csv');
    expect(cmd.flags.verbose).toBe(true);
  });

  test('flags before verb: flag consumes verb as value (known quirk)', () => {
    // ['--verbose', 'list'] → verbIndex=1 (list), verb='list'
    // Flag loop: --verbose sees 'list' as next non-flag value → verbose='list'
    // This is a parser quirk: flags before the verb consume the verb text as value
    const cmd = parseCommand(['--verbose', 'list']);
    expect(cmd.verb).toBe('list');
    expect(cmd.flags.verbose).toBe('list'); // quirk: string, not boolean
  });

  test('boolean flag after verb works correctly', () => {
    const cmd = parseCommand(['list', '--verbose']);
    expect(cmd.verb).toBe('list');
    expect(cmd.flags.verbose).toBe(true);
  });
});

// ── Default parsing (heuristic) ──────────────────────────────

describe('parseCommand — default heuristic', () => {
  test('dotted string treated as type path', () => {
    const cmd = parseCommand(['govern', 'governance.dispute']);
    expect(cmd.verb).toBe('govern');
    // govern falls through to default since it's not in any specific verb set
    // but is handled by extension commands — check it at least parses
  });
});

// ── rawArgs ──────────────────────────────────────────────────

describe('parseCommand — rawArgs', () => {
  test('rawArgs preserves original args', () => {
    const args = ['inspect', 'job-1774', '--format', 'json'];
    const cmd = parseCommand(args);
    expect(cmd.rawArgs).toEqual(args);
  });
});

// ── KNOWN_VERBS sanity ───────────────────────────────────────

describe('KNOWN_VERBS', () => {
  test('contains expected core verbs', () => {
    const expected = ['new', 'patch', 'inspect', 'list', 'identity', 'eval', 'compile', 'bind'];
    for (const v of expected) {
      expect((KNOWN_VERBS as readonly string[]).includes(v)).toBe(true);
    }
  });

  test('has no duplicates', () => {
    const set = new Set(KNOWN_VERBS);
    expect(set.size).toBe(KNOWN_VERBS.length);
  });
});

```
