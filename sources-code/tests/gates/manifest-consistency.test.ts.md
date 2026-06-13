---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/manifest-consistency.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.567507+00:00
---

# tests/gates/manifest-consistency.test.ts

```ts
/**
 * D-Manifest-canonical Gate: shell manifests stay in sync with the
 * canonical brain manifest.
 *
 * Per the D-Manifest-canonical resolution (one manifest = single source
 * of truth; the Flutter shell manifest + bundle are GENERATED from
 * extensions/<id>/manifest.json by tools/cartridge-manifest/generate.ts),
 * this gate fails if the committed shell assets have drifted from a
 * fresh regenerate.
 *
 * Same contract as the constants generator idempotency test
 * (core/constants/__tests__/constants.test.ts): the generated artifacts
 * are committed (the Flutter asset bundler needs them on disk), and CI
 * proves they were not hand-edited and are reproducible from the
 * canonical inputs (brain manifest + constants.json extensionPages +
 * lexicons.yml categories).
 *
 * If this fails: run `bun tools/cartridge-manifest/generate.ts` and
 * commit the regenerated packages/<id>_experience/assets/*.json.
 */

import { describe, test, expect } from "bun:test";
import { join } from "path";
import { execSync } from "child_process";

const ROOT = join(import.meta.dir, "../..");

describe("D-Manifest-canonical — generated shell manifests in sync", () => {
  test("`generate.ts --check` reports zero drift", () => {
    let output = "";
    let failed = false;
    try {
      output = execSync(
        "bun tools/cartridge-manifest/generate.ts --check",
        { cwd: ROOT, encoding: "utf-8", maxBuffer: 8 * 1024 * 1024 },
      );
    } catch (e) {
      failed = true;
      const err = e as { stdout?: string; stderr?: string };
      output = (err.stdout ?? "") + (err.stderr ?? "");
    }
    if (failed) {
      console.error(
        "Shell manifest drift detected — the committed " +
          "packages/<id>_experience/assets/*.json are out of sync with the " +
          "canonical extensions/<id>/manifest.json.\n" +
          "Fix: bun tools/cartridge-manifest/generate.ts && commit.\n\n" +
          output,
      );
    }
    expect(failed).toBe(false);
    expect(output).toContain("cartridge manifests in sync");
  });

  test("generator is idempotent — regenerate then re-check is clean", () => {
    execSync("bun tools/cartridge-manifest/generate.ts", {
      cwd: ROOT,
      encoding: "utf-8",
    });
    const check = execSync(
      "bun tools/cartridge-manifest/generate.ts --check",
      { cwd: ROOT, encoding: "utf-8" },
    );
    expect(check).toContain("no drift");
  });
});

```
