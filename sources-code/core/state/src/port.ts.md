---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/port.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.013719+00:00
---

# core/state/src/port.ts

```ts
export class PortUnboundError extends Error {
  readonly portName: string;
  constructor(portName: string) {
    super(
      `Port "${portName}" is not bound. Call ${portName}.bind(impl) during app boot before reading it.`,
    );
    this.name = "PortUnboundError";
    this.portName = portName;
  }
}

export interface Port<T> {
  readonly name: string;
  bind(impl: T): void;
  get(): T;
  unbind(): void;
  isBound(): boolean;
}

export function port<T>(name: string): Port<T> {
  let impl: T | undefined;
  let bound = false;
  return {
    name,
    bind(next: T): void {
      if (bound) {
        console.warn(
          `Port "${name}" is being re-bound. The previous implementation will be replaced.`,
        );
      }
      impl = next;
      bound = true;
    },
    get(): T {
      if (!bound) throw new PortUnboundError(name);
      return impl as T;
    },
    unbind(): void {
      impl = undefined;
      bound = false;
    },
    isBound(): boolean {
      return bound;
    },
  };
}

```
