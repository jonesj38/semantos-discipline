---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/tests/gates/no-tessera-in-brain-core.test.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.580909+00:00
---

# tests/gates/no-tessera-in-brain-core.test.ts

```ts
/**
 * Greenfield Discipline Gate: No tessera in brain-core
 *
 * Per `docs/prd/TESSERA-CARTRIDGE.md` §0.1 (Greenfield discipline) and
 * `docs/canon/commissions/wave-tessera.md` §4 (binding voice/style):
 *
 *   "The literal string `tessera` does not appear in any path under
 *    `runtime/semantos-brain/src/`. CI gate `tests/gates/no-tessera-in-brain-core.test.ts`
 *    (landed in V0.1) enforces this; every PR re-runs the gate."
 *
 * Tessera is a substrate-native cartridge. Its surface lives entirely at
 * `cartridges/tessera/`. Brain-core (the substrate) is unaware of tessera;
 * brain-core sees only:
 *   - the generic cartridge loader (DLO.1, post-loader cohort)
 *   - the four Phase-26 adapter interfaces in `core/protocol-types/`
 *   - the verb dispatcher's walker registry (`extensionId="tessera"` is a
 *     runtime string, not a hardcoded brain-core identifier)
 *
 * This gate is the machine-checkable enforcement of that discipline.
 * Initially passes vacuously (V0.1); remains green across the entire wave.
 *
 * If a deliverable seems to require putting tessera code in brain-core, the
 * agent submits a `BLOCKED:` PR per §4 — it does NOT work around this gate.
 */

import { describe, test, expect } from "bun:test";
import { join } from "path";
import { execSync } from "child_process";

const ROOT = join(import.meta.dir, "../..");
const BRAIN_CORE_SRC = join(ROOT, "runtime/semantos-brain/src");

function grepBrainCore(pattern: string): string[] {
  try {
    const result = execSync(
      `grep -rni "${pattern}" ${BRAIN_CORE_SRC}`,
      { encoding: "utf-8", maxBuffer: 16 * 1024 * 1024 },
    );
    return result.trim().split("\n").filter(Boolean);
  } catch {
    // grep returns exit code 1 when no matches; that's a passing state.
    return [];
  }
}

describe("Greenfield discipline — tessera is not baked into brain-core", () => {
  test("no occurrence of the literal string 'tessera' under runtime/semantos-brain/src/", () => {
    const hits = grepBrainCore("tessera");
    if (hits.length > 0) {
      console.error(
        [
          "Greenfield discipline violated — tessera identifier(s) found in brain-core:",
          ...hits,
          "",
          "Per TESSERA-CARTRIDGE.md §0.1, all tessera code lives at cartridges/tessera/.",
          "The brain-core surface tessera touches is the cartridge contract only",
          "(generic loader, walker dispatcher, four Phase-26 adapter interfaces).",
          "If a deliverable seems to require touching brain-core, submit a BLOCKED: PR",
          "rather than working around this gate.",
        ].join("\n"),
      );
    }
    expect(hits.length).toBe(0);
  });
});

```
