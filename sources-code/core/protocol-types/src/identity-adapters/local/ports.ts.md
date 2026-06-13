---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/identity-adapters/local/ports.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.915957+00:00
---

# core/protocol-types/src/identity-adapters/local/ports.ts

```ts
/**
 * Ports + injectable defaults for the LocalIdentityAdapter.
 *
 * Replaces the old `debugLogging` flag and the hard-coded
 * RECOVERY_CHALLENGES literal. Tests bind stubs through these ports
 * before constructing the adapter; production code calls
 * `bindDefaultLocalIdentityPorts()` at boot to wire the conventional
 * implementations.
 */

import { port, type Port } from '@semantos/state';

export interface IdentityLogger {
  debug(message: string, ...rest: unknown[]): void;
}

/** Default logger — silent. The pre-split `debugLogging` flag is
 *  recreated by binding the `console-debug` impl below. */
export const silentLogger: IdentityLogger = {
  debug: () => {},
};

export const consoleDebugLogger: IdentityLogger = {
  debug: (message, ...rest) => console.log(message, ...rest),
};

/** Single recovery challenge prompt. */
export interface RecoveryChallenge {
  id: string;
  prompt: string;
}

/** Default challenge bank — same prompts as the pre-split monolith. */
export const DEFAULT_RECOVERY_CHALLENGES: readonly RecoveryChallenge[] = [
  { id: 'c1', prompt: 'What is your recovery email?' },
  { id: 'c2', prompt: 'What is your favourite colour?' },
  { id: 'c3', prompt: 'What city were you born in?' },
  { id: 'c4', prompt: 'What is the name of your first pet?' },
];

export const loggerPort: Port<IdentityLogger> = port<IdentityLogger>('local-identity-logger');
export const recoveryChallengesPort: Port<readonly RecoveryChallenge[]> = port<
  readonly RecoveryChallenge[]
>('local-identity-recovery-challenges');

/** Resolve the active logger — bound port, or a silent default. */
export function getLogger(): IdentityLogger {
  return loggerPort.isBound() ? loggerPort.get() : silentLogger;
}

/** Resolve the active challenge bank. */
export function getRecoveryChallenges(): readonly RecoveryChallenge[] {
  return recoveryChallengesPort.isBound()
    ? recoveryChallengesPort.get()
    : DEFAULT_RECOVERY_CHALLENGES;
}

/** Bind the conventional defaults at app boot. Idempotent. */
export function bindDefaultLocalIdentityPorts(opts?: { debug?: boolean }): void {
  if (!loggerPort.isBound()) {
    loggerPort.bind(opts?.debug ? consoleDebugLogger : silentLogger);
  }
  if (!recoveryChallengesPort.isBound()) {
    recoveryChallengesPort.bind(DEFAULT_RECOVERY_CHALLENGES);
  }
}

```
