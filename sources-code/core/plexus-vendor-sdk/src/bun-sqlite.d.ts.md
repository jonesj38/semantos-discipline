---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/plexus-vendor-sdk/src/bun-sqlite.d.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.019324+00:00
---

# core/plexus-vendor-sdk/src/bun-sqlite.d.ts

```ts
/**
 * Minimal type declarations for bun:sqlite.
 * Bun provides these at runtime; this file satisfies TypeScript.
 */
declare module 'bun:sqlite' {
  export class Database {
    constructor(filename?: string);
    exec(sql: string): void;
    prepare(sql: string): Statement;
    close(): void;
  }

  interface Statement {
    run(...params: unknown[]): void;
    get(...params: unknown[]): unknown;
    all(...params: unknown[]): unknown[];
  }
}

```
