---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/services/intent-classifier/__tests__/response-parsers.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.123913+00:00
---

# runtime/services/src/services/intent-classifier/__tests__/response-parsers.test.ts

```ts
import { describe, expect, test } from 'bun:test';
import {
  parseFastPathResponse,
  parseFlatClassification,
  parseLevelResponse,
} from '../response-parsers';

describe('parseFastPathResponse', () => {
  test('1. accepts a well-formed envelope', () => {
    expect(parseFastPathResponse('{"intent":"create.job","confidence":0.95}')).toEqual({
      intent: 'create.job',
      confidence: 0.95,
      flowId: undefined,
      extractedFields: undefined,
    });
  });

  test('2. clamps confidence to [0,1]', () => {
    expect(parseFastPathResponse('{"intent":"x","confidence":1.5}')?.confidence).toBe(1);
    expect(parseFastPathResponse('{"intent":"x","confidence":-0.2}')?.confidence).toBe(0);
  });

  test('3. forwards flowId + extractedFields when present', () => {
    const out = parseFastPathResponse(
      '{"intent":"x","confidence":0.9,"flowId":"f","extractedFields":{"a":1}}',
    );
    expect(out?.flowId).toBe('f');
    expect(out?.extractedFields).toEqual({ a: 1 });
  });

  test('4. rejects malformed JSON', () => {
    expect(parseFastPathResponse('not-json')).toBeNull();
  });

  test('5. rejects missing fields', () => {
    expect(parseFastPathResponse('{"intent":"x"}')).toBeNull();
  });
});

describe('parseLevelResponse', () => {
  test('6. accepts a well-formed envelope', () => {
    expect(parseLevelResponse('{"selected":"job","confidence":0.7}')).toEqual({
      selected: 'job',
      confidence: 0.7,
    });
  });

  test('7. rejects missing fields', () => {
    expect(parseLevelResponse('{"selected":"job"}')).toBeNull();
  });

  test('8. clamps confidence', () => {
    expect(parseLevelResponse('{"selected":"j","confidence":2}')?.confidence).toBe(1);
  });
});

describe('parseFlatClassification', () => {
  test('9. accepts the full envelope', () => {
    const out = parseFlatClassification(
      '{"intent":"create.job","confidence":0.9,"objectType":"Job","typePath":"trades.plumbing","flowId":"f","extractedFields":{"x":1}}',
    );
    expect(out.intent).toBe('create.job');
    expect(out.confidence).toBe(0.9);
    expect(out.objectType).toBe('Job');
    expect(out.typePath).toBe('trades.plumbing');
    expect(out.flowId).toBe('f');
    expect(out.extractedFields).toEqual({ x: 1 });
  });

  test('10. attaches parseError on missing fields', () => {
    const out = parseFlatClassification('{"intent":"x"}');
    expect(out.intent).toBe('unknown');
    expect(out.extractedFields).toMatchObject({ parseError: expect.any(String) });
  });

  test('11. attaches parseError on invalid JSON', () => {
    const out = parseFlatClassification('not json');
    expect(out.intent).toBe('unknown');
    expect(out.extractedFields).toMatchObject({ parseError: 'Invalid JSON' });
  });
});

```
