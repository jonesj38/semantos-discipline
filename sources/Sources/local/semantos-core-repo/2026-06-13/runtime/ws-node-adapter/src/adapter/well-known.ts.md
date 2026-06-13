---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/ws-node-adapter/src/adapter/well-known.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.335878+00:00
---

# runtime/ws-node-adapter/src/adapter/well-known.ts

```ts
/**
 * adapter/well-known.ts — `/.well-known/semantos-node` JSON builder.
 *
 * Pure, async, no socket. The transport layer routes the HTTP request
 * here and serialises the returned object as the response body. The
 * facade also exposes this to callers who want the same data without
 * round-tripping through HTTP (e.g. an admin API).
 */

import type { License } from "@semantos/protocol-types/license";

export interface WellKnownArgs {
  bca: string;
  license: License;
  licenseCertId: string;
  /** Optional caller-supplied extras merged on top of the auto-filled fields. */
  extras?: () => Record<string, unknown> | Promise<Record<string, unknown>>;
}

/**
 * Build the JSON body for `/.well-known/semantos-node`. Auto-fills
 * `{ bca, pubkeyHex, licenseCertId }`; merges any caller-supplied
 * extras on top.
 */
export async function buildWellKnownBody(
  args: WellKnownArgs,
): Promise<Record<string, unknown>> {
  const base: Record<string, unknown> = {
    bca: args.bca,
    pubkeyHex: bytesToHex(args.license.pubkey),
    licenseCertId: args.licenseCertId,
  };
  const extras = args.extras ? await args.extras() : {};
  return { ...base, ...extras };
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

function bytesToHex(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i++) {
    s += bytes[i]!.toString(16).padStart(2, "0");
  }
  return s;
}

```
