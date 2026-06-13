---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/registry.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.013984+00:00
---

# core/state/src/registry.ts

```ts
export class RegistryMissingKeyError extends Error {
  readonly key: string;
  constructor(key: string, available: readonly string[]) {
    const hint = available.length
      ? ` Known keys: ${available.join(", ")}.`
      : " The registry is empty — register handlers at app boot.";
    super(`Registry has no handler for key "${key}".${hint}`);
    this.name = "RegistryMissingKeyError";
    this.key = key;
  }
}

export interface Registry<H> {
  register(key: string, handler: H): void;
  require(key: string): H;
  get(key: string): H | undefined;
  has(key: string): boolean;
  keys(): string[];
}

export function registry<H>(): Registry<H> {
  const map = new Map<string, H>();
  return {
    register(key, handler) {
      map.set(key, handler);
    },
    require(key) {
      const v = map.get(key);
      if (v === undefined) throw new RegistryMissingKeyError(key, [...map.keys()]);
      return v;
    },
    get(key) {
      return map.get(key);
    },
    has(key) {
      return map.has(key);
    },
    keys() {
      return [...map.keys()];
    },
  };
}

```
