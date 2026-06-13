---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/shell/src/vfs/path-resolver/__tests__/path-parser.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.393562+00:00
---

# runtime/shell/src/vfs/path-resolver/__tests__/path-parser.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import { jsonContent, parseSegments, parseVfsPath } from '../path-parser';

describe('parseSegments', () => {
  test('1. strips leading + trailing slashes', () => {
    expect(parseSegments('/objects/foo/')).toEqual(['objects', 'foo']);
  });

  test('2. drops empty segments produced by double slashes', () => {
    expect(parseSegments('//a///b/')).toEqual(['a', 'b']);
  });

  test('3. empty path → empty list', () => {
    expect(parseSegments('')).toEqual([]);
    expect(parseSegments('/')).toEqual([]);
  });
});

describe('parseVfsPath', () => {
  test('4. recognized prefix yields prefix + tail', () => {
    expect(parseVfsPath('/objects/foo/payload.json')).toEqual({
      segments: ['objects', 'foo', 'payload.json'],
      prefix: 'objects',
      tail: ['foo', 'payload.json'],
    });
  });

  test('5. unknown prefix has prefix=null', () => {
    expect(parseVfsPath('/garbage/x').prefix).toBeNull();
  });

  test('6. root path has empty segments + null prefix', () => {
    const out = parseVfsPath('/');
    expect(out.segments).toEqual([]);
    expect(out.prefix).toBeNull();
  });

  test('7. each known prefix is identified', () => {
    for (const p of ['objects', 'identities', 'taxonomy', 'governance', 'flows']) {
      expect(parseVfsPath(`/${p}`).prefix).toBe(p as never);
    }
  });
});

describe('jsonContent', () => {
  test('8. emits formatted JSON with trailing newline', () => {
    const out = jsonContent({ foo: 1 });
    expect(out.data.toString('utf-8')).toBe('{\n  "foo": 1\n}\n');
    expect(out.size).toBe(out.data.length);
  });

  test('9. handles arrays', () => {
    const out = jsonContent([1, 2]);
    expect(out.data.toString('utf-8')).toBe('[\n  1,\n  2\n]\n');
  });
});

```
