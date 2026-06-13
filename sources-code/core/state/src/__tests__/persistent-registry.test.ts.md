---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/__tests__/persistent-registry.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.015705+00:00
---

# core/state/src/__tests__/persistent-registry.test.ts

```ts
/**
 * Contract tests for `makeRegistry<K, V>` — the atom-backed value
 * registry with a declared persistence policy.
 *
 * The persistence behavior is exercised against a synchronous in-memory
 * "writer" so the tests don't depend on any real backend. Real bindings
 * (Plexus recovery, IDB) are out of scope here — the registry's job is
 * to call `persist` correctly, not to do the persisting.
 */

import { describe, test, expect, mock } from "bun:test";
import {
  makeRegistry,
  RegistryConfigError,
  subscribe,
  type PersistEvent,
  type PersistentRegistry,
} from "../index.js";

describe("makeRegistry — config", () => {
  test("'session' policy works without a persist callback", () => {
    const reg = makeRegistry<string, number>({
      name: "ephemeral",
      persistencePolicy: "session",
    });
    reg.set("a", 1);
    expect(reg.get("a")).toBe(1);
  });

  test("non-session policy without persist throws RegistryConfigError", () => {
    expect(() =>
      makeRegistry<string, number>({
        name: "must-throw",
        persistencePolicy: "snapshot",
      }),
    ).toThrow(RegistryConfigError);
    expect(() =>
      makeRegistry<string, number>({
        name: "must-throw",
        persistencePolicy: "plexus-recovered",
      }),
    ).toThrow(RegistryConfigError);
    expect(() =>
      makeRegistry<string, number>({
        name: "must-throw",
        persistencePolicy: "chain",
      }),
    ).toThrow(RegistryConfigError);
  });

  test("name and policy are exposed on the registry", () => {
    const reg = makeRegistry<string, number>({
      name: "exposed",
      persistencePolicy: "session",
    });
    expect(reg.name).toBe("exposed");
    expect(reg.persistencePolicy).toBe("session");
  });

  test("initial entries are loaded WITHOUT firing persist", () => {
    const persist = mock<(e: PersistEvent<string, number>) => void>(() => {});
    const reg = makeRegistry<string, number>({
      name: "init",
      persistencePolicy: "snapshot",
      persist,
      initial: [
        ["a", 1],
        ["b", 2],
      ],
    });
    expect(reg.get("a")).toBe(1);
    expect(reg.get("b")).toBe(2);
    expect(persist).not.toHaveBeenCalled();
  });
});

describe("makeRegistry — basic Map-shaped API", () => {
  function freshSession(): PersistentRegistry<string, number> {
    return makeRegistry<string, number>({
      name: "basic",
      persistencePolicy: "session",
    });
  }

  test("set / get / has", () => {
    const reg = freshSession();
    expect(reg.has("a")).toBe(false);
    expect(reg.get("a")).toBeUndefined();
    reg.set("a", 1);
    expect(reg.has("a")).toBe(true);
    expect(reg.get("a")).toBe(1);
  });

  test("delete returns true on hit, false on miss", () => {
    const reg = freshSession();
    reg.set("a", 1);
    expect(reg.delete("a")).toBe(true);
    expect(reg.delete("a")).toBe(false);
    expect(reg.has("a")).toBe(false);
  });

  test("size, keys, values, entries", () => {
    const reg = freshSession();
    reg.set("a", 1);
    reg.set("b", 2);
    reg.set("c", 3);
    expect(reg.size()).toBe(3);
    expect(new Set(reg.keys())).toEqual(new Set(["a", "b", "c"]));
    expect(new Set(reg.values())).toEqual(new Set([1, 2, 3]));
    expect(new Set(reg.entries())).toEqual(
      new Set([
        ["a", 1],
        ["b", 2],
        ["c", 3],
      ] as Array<[string, number]>),
    );
  });

  test("snapshot returns a fresh Map (caller mutation does not affect registry)", () => {
    const reg = freshSession();
    reg.set("a", 1);
    const snap = reg.snapshot();
    snap.set("a", 999);
    expect(reg.get("a")).toBe(1);
  });

  test("clear empties the registry", () => {
    const reg = freshSession();
    reg.set("a", 1);
    reg.set("b", 2);
    reg.clear();
    expect(reg.size()).toBe(0);
  });
});

describe("makeRegistry — atom + subscribe", () => {
  test("each set publishes a NEW Map (referential identity changes)", () => {
    const reg = makeRegistry<string, number>({
      name: "ref-id",
      persistencePolicy: "session",
    });
    const m1 = reg.snapshot();
    reg.set("a", 1);
    const m2 = reg.snapshot();
    expect(m1).not.toBe(m2);
  });

  test("subscribe fires on every set / delete with the post-mutation snapshot", () => {
    const reg = makeRegistry<string, number>({
      name: "sub",
      persistencePolicy: "session",
    });
    const calls: Array<ReadonlyMap<string, number>> = [];
    const dispose = reg.subscribe((s) => calls.push(s));
    reg.set("a", 1);
    reg.set("b", 2);
    reg.delete("a");
    expect(calls).toHaveLength(3);
    expect(calls[0]!.get("a")).toBe(1);
    expect(calls[1]!.get("b")).toBe(2);
    expect(calls[2]!.has("a")).toBe(false);
    dispose();
  });

  test("the underlying atom is observable via the standard subscribe export", () => {
    const reg = makeRegistry<string, number>({
      name: "atom-export",
      persistencePolicy: "session",
    });
    let last: ReadonlyMap<string, number> | undefined;
    const dispose = subscribe(reg.atom, (s) => {
      last = s;
    });
    reg.set("a", 1);
    expect(last?.get("a")).toBe(1);
    dispose();
  });
});

describe("makeRegistry — persistence callbacks", () => {
  test("snapshot policy fires persist once per set with kind='set'", () => {
    const persist = mock<(e: PersistEvent<string, number>) => void>(() => {});
    const reg = makeRegistry<string, number>({
      name: "snap",
      persistencePolicy: "snapshot",
      persist,
    });
    reg.set("a", 1);
    reg.set("b", 2);
    expect(persist).toHaveBeenCalledTimes(2);
    const first = persist.mock.calls[0]![0];
    expect(first.kind).toBe("set");
    expect(first.key).toBe("a");
    expect(first.value).toBe(1);
    expect(first.snapshot.get("a")).toBe(1);
  });

  test("delete fires persist with kind='delete' and no value", () => {
    const persist = mock<(e: PersistEvent<string, number>) => void>(() => {});
    const reg = makeRegistry<string, number>({
      name: "del",
      persistencePolicy: "snapshot",
      persist,
    });
    reg.set("a", 1);
    persist.mockClear();
    reg.delete("a");
    expect(persist).toHaveBeenCalledTimes(1);
    const ev = persist.mock.calls[0]![0];
    expect(ev.kind).toBe("delete");
    expect(ev.value).toBeUndefined();
    expect(ev.snapshot.has("a")).toBe(false);
  });

  test("clear fires persist once per removed key", () => {
    const persist = mock<(e: PersistEvent<string, number>) => void>(() => {});
    const reg = makeRegistry<string, number>({
      name: "clear",
      persistencePolicy: "snapshot",
      persist,
    });
    reg.set("a", 1);
    reg.set("b", 2);
    persist.mockClear();
    reg.clear();
    expect(persist).toHaveBeenCalledTimes(2);
    expect(persist.mock.calls.every((c) => c[0].kind === "delete")).toBe(true);
  });

  test("clear on empty registry does not fire persist", () => {
    const persist = mock<(e: PersistEvent<string, number>) => void>(() => {});
    const reg = makeRegistry<string, number>({
      name: "clear-empty",
      persistencePolicy: "snapshot",
      persist,
    });
    reg.clear();
    expect(persist).not.toHaveBeenCalled();
  });

  test("delete on missing key does NOT fire persist", () => {
    const persist = mock<(e: PersistEvent<string, number>) => void>(() => {});
    const reg = makeRegistry<string, number>({
      name: "del-miss",
      persistencePolicy: "snapshot",
      persist,
    });
    reg.delete("nope");
    expect(persist).not.toHaveBeenCalled();
  });

  test("persist throwing synchronously does NOT prevent the in-memory mutation", () => {
    const errs: unknown[] = [];
    const origConsole = console.error;
    console.error = (...a: unknown[]) => {
      errs.push(a);
    };
    try {
      const reg = makeRegistry<string, number>({
        name: "throwing",
        persistencePolicy: "snapshot",
        persist: () => {
          throw new Error("disk full");
        },
      });
      reg.set("a", 1);
      expect(reg.get("a")).toBe(1); // mutation still landed
      expect(errs.length).toBe(1); // error was logged
    } finally {
      console.error = origConsole;
    }
  });

  test("plexus-recovered policy is wireable: persist receives full snapshot for batch enrollment", () => {
    const enrolled: Array<{ key: string; value: number; size: number }> = [];
    const reg = makeRegistry<string, number>({
      name: "plexus",
      persistencePolicy: "plexus-recovered",
      persist: (e) => {
        if (e.kind === "set") {
          enrolled.push({ key: e.key, value: e.value!, size: e.snapshot.size });
        }
      },
    });
    reg.set("ctx-1", 100);
    reg.set("ctx-2", 200);
    expect(enrolled).toEqual([
      { key: "ctx-1", value: 100, size: 1 },
      { key: "ctx-2", value: 200, size: 2 },
    ]);
  });
});

```
