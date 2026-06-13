---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/local/__tests__/ports.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.917811+00:00
---

# core/protocol-types/src/identity-adapters/local/__tests__/ports.test.ts

```ts
/**
 * Port wiring tests — logger and recovery challenges.
 */

import { afterEach, describe, expect, test } from 'bun:test';
import {
  bindDefaultLocalIdentityPorts,
  consoleDebugLogger,
  DEFAULT_RECOVERY_CHALLENGES,
  getLogger,
  getRecoveryChallenges,
  loggerPort,
  recoveryChallengesPort,
  silentLogger,
} from '../ports';

afterEach(() => {
  loggerPort.unbind();
  recoveryChallengesPort.unbind();
});

describe('loggerPort', () => {
  test('1. defaults to silent when unbound', () => {
    expect(loggerPort.isBound()).toBe(false);
    const logger = getLogger();
    expect(logger).toBe(silentLogger);
    expect(() => logger.debug('hi')).not.toThrow();
  });

  test('2. bound stub receives debug calls', () => {
    const seen: string[] = [];
    loggerPort.bind({ debug: (msg: string) => seen.push(msg) });
    getLogger().debug('hello');
    expect(seen).toEqual(['hello']);
  });

  test('3. consoleDebugLogger is exported as a no-op-safe handle', () => {
    expect(typeof consoleDebugLogger.debug).toBe('function');
  });
});

describe('recoveryChallengesPort', () => {
  test('4. unbound returns the canonical 4-prompt bank', () => {
    const out = getRecoveryChallenges();
    expect(out).toBe(DEFAULT_RECOVERY_CHALLENGES);
    expect(out.map((c) => c.id).sort()).toEqual(['c1', 'c2', 'c3', 'c4']);
  });

  test('5. bound stub overrides the bank', () => {
    recoveryChallengesPort.bind([{ id: 'x', prompt: 'why?' }]);
    expect(getRecoveryChallenges()).toEqual([{ id: 'x', prompt: 'why?' }]);
  });
});

describe('bindDefaultLocalIdentityPorts', () => {
  test('6. wires defaults when unbound', () => {
    bindDefaultLocalIdentityPorts();
    expect(loggerPort.isBound()).toBe(true);
    expect(recoveryChallengesPort.isBound()).toBe(true);
  });

  test('7. is idempotent — does not overwrite a pre-bound port', () => {
    const customLogger = { debug: () => {} };
    loggerPort.bind(customLogger);
    bindDefaultLocalIdentityPorts({ debug: true });
    expect(loggerPort.get()).toBe(customLogger);
  });

  test('8. debug:true wires consoleDebugLogger', () => {
    bindDefaultLocalIdentityPorts({ debug: true });
    expect(getLogger()).toBe(consoleDebugLogger);
  });
});

```
