---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/grammar/__tests__/error-collector.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.925341+00:00
---

# core/protocol-types/src/grammar/__tests__/error-collector.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  ValidationErrorCollector,
  requireString,
} from '../error-collector';

describe('ValidationErrorCollector', () => {
  test('starts empty with empty path', () => {
    const c = ValidationErrorCollector.create();
    expect(c.path).toBe('');
    expect(c.snapshot()).toHaveLength(0);
  });

  test('withPath returns NEW instance and never mutates parent', () => {
    const root = ValidationErrorCollector.create();
    const child = root.withPath('source');
    expect(root.path).toBe('');
    expect(child.path).toBe('source');
    expect(child).not.toBe(root);
  });

  test('numeric segment is rendered as [N]', () => {
    const c = ValidationErrorCollector.create()
      .withPath('entityMappings')
      .withPath(2);
    expect(c.path).toBe('entityMappings[2]');
  });

  test('writes through child collector are visible from parent snapshot', () => {
    const root = ValidationErrorCollector.create();
    const child = root.withPath('source');
    child.push({ field: 'protocol', message: 'bad' });
    expect(root.snapshot()).toHaveLength(1);
    expect(root.snapshot()[0].path).toBe('source.protocol');
  });

  test('default severity is error', () => {
    const c = ValidationErrorCollector.create();
    c.push({ message: 'oops' });
    expect(c.snapshot()[0].severity).toBe('error');
  });

  test('explicit severity is preserved', () => {
    const c = ValidationErrorCollector.create();
    c.push({ message: 'maybe', severity: 'warning' });
    expect(c.snapshot()[0].severity).toBe('warning');
  });

  test('toResult marks valid=true when only warnings', () => {
    const c = ValidationErrorCollector.create();
    c.push({ message: 'just fyi', severity: 'warning' });
    const r = c.toResult();
    expect(r.valid).toBe(true);
    expect(r.errors).toHaveLength(1);
  });

  test('toResult marks valid=false when any error', () => {
    const c = ValidationErrorCollector.create();
    c.push({ message: 'bad' });
    expect(c.toResult().valid).toBe(false);
  });

  test('explicit path overrides scope', () => {
    const c = ValidationErrorCollector.create().withPath('source');
    c.push({ path: 'override', message: 'm' });
    expect(c.snapshot()[0].path).toBe('override');
  });

  test('path is immutable on the collector itself', () => {
    const c = ValidationErrorCollector.create().withPath('a');
    // No setter — this would be a TS error if attempted. Verify
    // identity-based: pushing on the same instance never changes path.
    c.push({ message: 'm1' });
    c.push({ field: 'x', message: 'm2' });
    expect(c.path).toBe('a');
  });
});

describe('requireString helper', () => {
  test('passes silently on a non-empty string', () => {
    const c = ValidationErrorCollector.create();
    requireString({ name: 'x' }, 'name', c);
    expect(c.snapshot()).toHaveLength(0);
  });

  test('fails on missing field', () => {
    const c = ValidationErrorCollector.create();
    requireString({}, 'name', c);
    expect(c.snapshot()).toHaveLength(1);
    expect(c.snapshot()[0].path).toBe('name');
  });

  test('fails on empty string', () => {
    const c = ValidationErrorCollector.create();
    requireString({ name: '' }, 'name', c);
    expect(c.snapshot()).toHaveLength(1);
  });

  test('fails on wrong type', () => {
    const c = ValidationErrorCollector.create();
    requireString({ name: 42 }, 'name', c);
    expect(c.snapshot()).toHaveLength(1);
  });

  test('uses scoped path', () => {
    const c = ValidationErrorCollector.create().withPath('author');
    requireString({}, 'name', c);
    expect(c.snapshot()[0].path).toBe('author.name');
  });
});

```
