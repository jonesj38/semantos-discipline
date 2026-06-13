---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/predictor.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.822220+00:00
---

# archive/apps-world-client/src/predictor.test.ts

```ts
import { describe, it, expect, beforeAll } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { Predictor } from "./predictor";

describe("Predictor — substructural op prediction via WASM", () => {
  let predictor: Predictor;

  beforeAll(async () => {
    const wasmPath = resolve(
      __dirname,
      "../../../core/cell-engine/zig-out/bin/cell-engine.wasm",
    );
    const bytes = readFileSync(wasmPath);
    predictor = await Predictor.init(bytes);
  });

  it("LINEAR DUP → rc 22", () => {
    expect(predictor.predictSubstructural("linear", "dup")).toEqual({ rc: 22, accepted: false });
  });

  it("LINEAR DROP → rc 23", () => {
    expect(predictor.predictSubstructural("linear", "drop")).toEqual({ rc: 23, accepted: false });
  });

  it("AFFINE DUP → rc 24", () => {
    expect(predictor.predictSubstructural("affine", "dup")).toEqual({ rc: 24, accepted: false });
  });

  it("AFFINE DROP → rc 0", () => {
    expect(predictor.predictSubstructural("affine", "drop")).toEqual({ rc: 0, accepted: true });
  });

  it("RELEVANT DUP → rc 0", () => {
    expect(predictor.predictSubstructural("relevant", "dup")).toEqual({ rc: 0, accepted: true });
  });

  it("RELEVANT DROP → rc 25", () => {
    expect(predictor.predictSubstructural("relevant", "drop")).toEqual({ rc: 25, accepted: false });
  });
});

```
