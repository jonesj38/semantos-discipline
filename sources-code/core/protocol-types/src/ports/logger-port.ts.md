---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/protocol-types/src/ports/logger-port.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.902084+00:00
---

# core/protocol-types/src/ports/logger-port.ts

```ts
/**
 * Logger port — uniform logging surface so tests can capture calls
 * and production can route to console / pino / etc.
 */

import { port, type Port } from '@semantos/state';

export interface Logger {
  debug(message: string, ...rest: unknown[]): void;
  info(message: string, ...rest: unknown[]): void;
  warn(message: string, ...rest: unknown[]): void;
  error(message: string, ...rest: unknown[]): void;
}

/** A no-op logger — the default when nothing is bound. */
export const silentLogger: Logger = {
  debug: () => {},
  info: () => {},
  warn: () => {},
  error: () => {},
};

/** Console-backed logger — wired by `bindDefaultLoggerPort` at boot. */
export const consoleLogger: Logger = {
  debug: (message, ...rest) => console.debug(message, ...rest),
  info: (message, ...rest) => console.info(message, ...rest),
  warn: (message, ...rest) => console.warn(message, ...rest),
  error: (message, ...rest) => console.error(message, ...rest),
};

export const loggerPort: Port<Logger> = port<Logger>('logger');

/** Resolve the bound logger or fall back to silent. */
export function getLogger(): Logger {
  return loggerPort.isBound() ? loggerPort.get() : silentLogger;
}

```
