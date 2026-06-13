---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/state/src/__tests__/registry.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.016267+00:00
---

# core/state/src/__tests__/registry.test.ts

```ts
import { describe, test, expect } from "bun:test";
import { registry, RegistryMissingKeyError } from "../index.js";

describe("registry", () => {
  type Handler = (x: number) => number;

  test("register + require returns the handler", () => {
    const r = registry<Handler>();
    const double: Handler = (x) => x * 2;
    r.register("double", double);
    expect(r.require("double")).toBe(double);
    expect(r.require("double")(3)).toBe(6);
  });

  test("require throws RegistryMissingKeyError on missing key", () => {
    const r = registry<Handler>();
    r.register("a", (x) => x);
    r.register("b", (x) => x);
    let err: unknown;
    try {
      r.require("missing");
    } catch (e) {
      err = e;
    }
    expect(err).toBeInstanceOf(RegistryMissingKeyError);
    expect((err as RegistryMissingKeyError).key).toBe("missing");
    expect((err as Error).message).toContain("a");
    expect((err as Error).message).toContain("b");
  });

  test("get returns undefined for missing keys", () => {
    const r = registry<Handler>();
    expect(r.get("none")).toBeUndefined();
    r.register("id", (x) => x);
    expect(r.get("id")?.(5)).toBe(5);
  });

  test("has reflects registered keys", () => {
    const r = registry<Handler>();
    expect(r.has("x")).toBe(false);
    r.register("x", (v) => v);
    expect(r.has("x")).toBe(true);
  });

  test("keys returns all registered keys", () => {
    const r = registry<Handler>();
    r.register("a", (x) => x);
    r.register("b", (x) => x + 1);
    r.register("c", (x) => x + 2);
    expect(new Set(r.keys())).toEqual(new Set(["a", "b", "c"]));
  });

  test("re-registering a key overwrites the handler", () => {
    const r = registry<Handler>();
    r.register("k", (x) => x);
    r.register("k", (x) => x * 10);
    expect(r.require("k")(3)).toBe(30);
  });
});

```
