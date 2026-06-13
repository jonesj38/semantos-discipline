---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/services/src/host-exec-registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.087984+00:00
---

# runtime/services/src/host-exec-registry.ts

```ts
/**
 * Host-exec handler registry — allowlist-based dispatch for HOST_EXEC.
 *
 * Same shape as the verb registry next door: a neutral module both shell
 * and extensions can import without creating a dependency cycle. Lives
 * here in runtime-services so:
 *
 *   - extensions can register handlers without an extensions → shell dep
 *   - browser entries can import manifests without pulling node:child_process
 *   - server entries can attach the impl functions at load time
 *
 * Manifest / impl split
 * ---------------------
 *
 *   registerHandlerManifest(manifest)
 *       Called from a `*.manifest.ts` file that contains only pure data
 *       (no node:* imports). Both browser and server entries pull these
 *       in as side-effect imports to populate the allowlist the LLM and
 *       fallback extractor see.
 *
 *   attachHandlerFn(id, fn)
 *       Called from the sibling `*.ts` file which imports node:child_process
 *       or similar. Only server entries import these files.
 *
 *   registerHandler(manifest, fn)
 *       Convenience for callers that run in Node anyway (tests, internal
 *       shell handlers with no browser presence). Equivalent to the two
 *       calls above.
 *
 * Lifecycle
 * ---------
 *
 *   Browser boot → import the manifest barrel once; LLM/fallback extractor
 *   see the full manifest list; `invokeHandler` would return
 *   HANDLER_NOT_AVAILABLE in this runtime (browser never calls it —
 *   invocation goes through host.exec over the capability gate).
 *
 *   Server boot → import the handler barrel (which imports each handler
 *   .ts, which imports its .manifest sibling, so manifests register
 *   first, fns attach second). `invokeHandler` works.
 */

import type {
  Handler,
  HandlerArgs,
  HandlerContext,
  HandlerManifest,
  HandlerResult,
} from "./host-exec-types";

export type {
  Handler,
  HandlerArgs,
  HandlerContext,
  HandlerError,
  HandlerManifest,
  HandlerOk,
  HandlerResult,
} from "./host-exec-types";

/** Internal registry — handler id → { manifest, fn?: Handler }. */
interface RegistryEntry {
  manifest: HandlerManifest;
  fn?: Handler;
}
const registry = new Map<string, RegistryEntry>();

/**
 * Register a handler manifest. Browser-safe — call this from a
 * `*.manifest.ts` file containing only pure data.
 *
 * Throws on duplicate id (programmer bug, not runtime).
 */
export function registerHandlerManifest(manifest: HandlerManifest): void {
  const existing = registry.get(manifest.id);
  if (existing) {
    // Idempotent when the manifest object is literally the same reference
    // (e.g. HMR reloading the same module). Duplicate *different* manifests
    // are a bug.
    if (existing.manifest === manifest) return;
    throw new Error(
      `Handler manifest '${manifest.id}' is already registered — double-registration is a bug`,
    );
  }
  registry.set(manifest.id, { manifest });
}

/**
 * Attach an implementation fn to a previously-registered manifest.
 * Node-only — call this from a sibling `*.ts` that imports its
 * `*.manifest.ts` first and then the node built-ins it needs.
 *
 * Throws if no manifest is registered for `id` — means the .ts file
 * forgot to import its .manifest sibling.
 */
export function attachHandlerFn(id: string, fn: Handler): void {
  const entry = registry.get(id);
  if (!entry) {
    throw new Error(
      `attachHandlerFn('${id}'): no manifest registered — did you forget to import the .manifest file?`,
    );
  }
  if (entry.fn) {
    throw new Error(
      `Handler '${id}' already has an implementation attached — double-registration is a bug`,
    );
  }
  entry.fn = fn;
}

/**
 * Back-compat convenience: register manifest + attach fn in one call.
 * Use only from code paths that are Node-only anyway (tests, internal
 * shell handlers with no browser presence). For code that must run in
 * both tiers, use the split API.
 */
export function registerHandler(manifest: HandlerManifest, fn: Handler): void {
  registerHandlerManifest(manifest);
  attachHandlerFn(manifest.id, fn);
}

/** Look up a handler by id. Returns null if no manifest is registered. */
export function getHandler(
  id: string,
): { manifest: HandlerManifest; fn?: Handler } | null {
  const entry = registry.get(id);
  return entry ? { manifest: entry.manifest, fn: entry.fn } : null;
}

/** List all registered handler manifests. */
export function listHandlers(): HandlerManifest[] {
  return Array.from(registry.values()).map((entry) => entry.manifest);
}

/**
 * Invoke a handler by id. Every error path returns a structured result.
 *
 * 1. Unknown handler (no manifest) → UNKNOWN_HANDLER
 * 2. No impl attached in this runtime → HANDLER_NOT_AVAILABLE
 * 3. Missing required args → INVALID_ARGS
 * 4. Timeout exceeded → HANDLER_TIMEOUT
 * 5. Handler throws → HANDLER_CRASHED
 */
export async function invokeHandler(
  id: string,
  args: HandlerArgs,
  ctx: HandlerContext,
): Promise<HandlerResult> {
  const entry = registry.get(id);
  if (!entry) {
    return {
      ok: false,
      code: "UNKNOWN_HANDLER",
      message: `No handler registered for '${id}'`,
    };
  }
  if (!entry.fn) {
    return {
      ok: false,
      code: "HANDLER_NOT_AVAILABLE",
      message: `Handler '${id}' is registered (manifest only) but has no implementation in this runtime`,
    };
  }

  // Validate required args from manifest schema.
  const { argsSchema } = entry.manifest;
  for (const [key, schema] of Object.entries(argsSchema)) {
    if (
      schema.required &&
      (args[key] === undefined || args[key] === null)
    ) {
      return {
        ok: false,
        code: "INVALID_ARGS",
        message: `Missing required argument '${key}' for handler '${id}'`,
      };
    }
  }

  const fn = entry.fn;
  try {
    const timeout = ctx.timeoutMs ?? 10_000;
    const result = await Promise.race<HandlerResult>([
      fn(args, ctx),
      new Promise<HandlerResult>((resolve) =>
        setTimeout(
          () =>
            resolve({
              ok: false,
              code: "HANDLER_TIMEOUT",
              message: `Handler '${id}' timed out after ${timeout}ms`,
            }),
          timeout,
        ),
      ),
    ]);
    return result;
  } catch (err) {
    return {
      ok: false,
      code: "HANDLER_CRASHED",
      message: `Handler '${id}' threw: ${err instanceof Error ? err.message : String(err)}`,
    };
  }
}

/** Clear all registrations — for tests only. */
export function _clearHostExecRegistry(): void {
  registry.clear();
}

```
