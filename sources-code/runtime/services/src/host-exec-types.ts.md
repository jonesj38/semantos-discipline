---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/host-exec-types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.087383+00:00
---

# runtime/services/src/host-exec-types.ts

```ts
/**
 * Host execution types — handler registry contracts.
 *
 * Kept in runtime-services (not runtime/shell) so both tiers can import
 * without a cycle. Mirrors the verb-registry layout.
 */

/** Arguments passed to a handler. Handlers interpret keys from their manifest's argsSchema. */
export type HandlerArgs = Record<string, unknown> & { dryRun?: boolean };

/** Successful handler execution. */
export interface HandlerOk {
  ok: true;
  exitCode: number;
  stdout: string;
  stderr: string;
  durationMs: number;
}

/** Failed handler execution — structured error, never thrown. */
export interface HandlerError {
  ok: false;
  code: string;
  message: string;
  details?: unknown;
}

/** Discriminated union: every handler invocation resolves to one of these. */
export type HandlerResult = HandlerOk | HandlerError;

/** Runtime context passed to every handler invocation. */
export interface HandlerContext {
  hatId: string;
  hatCertId: string;
  timeoutMs: number;
}

/** Handler function signature. */
export type Handler = (
  args: HandlerArgs,
  ctx: HandlerContext,
) => Promise<HandlerResult>;

/** Manifest describing a handler's identity, args schema, and required capability. */
export interface HandlerManifest {
  id: string;
  description: string;
  argsSchema: Record<string, { type: string; required?: boolean }>;
  capabilityId: number;
}

```
