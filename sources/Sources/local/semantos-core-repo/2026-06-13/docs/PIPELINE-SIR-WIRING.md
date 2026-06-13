---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/PIPELINE-SIR-WIRING.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.329759+00:00
---

# SIR wiring — design note for the seam

Written before the wiring lands so the choice and its constraints are documented separately from the code.

## Status

- **OIR** (`@semantos/semantos-ir`): `lower()`, `emit()`, `canonicalize()` all implemented; **no caller** in the Lisp compiler today.
- **SIR** (`@semantos/semantos-sir`): `lowerSIR()` implemented with trust-tier and allowed-emit-op enforcement; **no caller** outside its own golden-file test.
- **Lisp compiler** ([packages/shell/src/lisp/compiler.ts](../packages/shell/src/lisp/compiler.ts)): emits opcode bytes directly from `ConstraintExpr`, bypassing both IRs.

## Goal

Establish the SIR → OIR seam so that:

1. Every Lisp program first lowers to a trivial SIR program, then through `lowerSIR()` to OIR, then via `emit()` to opcode bytes.
2. The bytes produced are α-equivalent to what the existing direct compiler emits today (no observable change for the existing test corpus).
3. The seam exists — so that the next surface grammar (LaTeX, Lean-ish, Ricardian) plugs in at the SIR layer without requiring a re-architecture under deadline pressure.

## What "trivial identity lowering" means

The Lisp compiler doesn't know about jural categories, trust class, proof requirements, or governance context — those are SIR concepts that surface grammars carrying domain semantics will populate. So for the Lisp path, every SIR field gets a default that means "no claim".

| SIR field | Default for Lisp |
|---|---|
| `juralCategory` | `"plain"` (or whichever neutral category exists in `JuralCategory`) |
| `trustClass` | `"informal"` (lowest tier — no formal-proof requirement triggered) |
| `proofRequirement` | `"none"` |
| `executionAuthority` | `"local"` (not delegated; avoids the `DELEGATED_NOT_IMPLEMENTED` rejection) |
| `governance` | A `GovernanceContext` populated from the four fields above |

Top-level forms map to SIR `declaration` nodes; guards inside `(if …)` or `(when …)` map to `condition` nodes. The structure of the SIR program mirrors the structure of the `ConstraintExpr` 1:1.

## Implementation sketch

One new function in the Lisp compiler, two new pipelines:

```ts
// packages/shell/src/lisp/compileToSIR.ts (new)
import type { SIRProgram } from "@semantos/semantos-sir";
import type { ConstraintExpr } from "./types";

export function compileToSIR(expr: ConstraintExpr): SIRProgram {
  // recursive walk of ConstraintExpr, producing SIR nodes with neutral
  // governance context (informal / none / local). Structure-preserving.
}

// packages/shell/src/lisp/compiler.ts (modified)
import { lowerSIR } from "@semantos/semantos-sir";
import { emit } from "@semantos/semantos-ir";
import { compileToSIR } from "./compileToSIR";

export function compileViaSIR(expr: ConstraintExpr): Uint8Array {
  const sir = compileToSIR(expr);
  const result = lowerSIR(sir);
  if (!result.ok) throw new Error(result.message);
  return emit(result.program);
}
```

The existing `compile()` stays in place during transition. `compileViaSIR()` is added side-by-side. A feature flag (or just a config) chooses the path; once the golden tests pass under both, the direct path is removed.

## Test plan

A new test file in `packages/shell/src/lisp/__tests__/sir-equivalence.test.ts` (or wherever fits the existing golden-test convention):

```ts
import { compile, compileViaSIR } from "../compiler";
import { GOLDEN_CORPUS } from "./golden-corpus"; // existing fixture

for (const { name, source } of GOLDEN_CORPUS) {
  test(`${name} — direct === via-SIR`, () => {
    const direct = compile(parse(source));
    const viaSIR = compileViaSIR(parse(source));
    expect(viaSIR).toEqual(direct);
  });
}
```

If byte-identical equality fails because OIR's `lower()` rearranges bindings into ANF (it does), the assertion weakens to **α-equivalence after canonicalization**:

```ts
import { canonicalize } from "@semantos/semantos-ir";

expect(canonicalize(compileToIR(parse(source))))
  .toEqual(canonicalize(lowerSIR(compileToSIR(parse(source))).program));
```

`canonicalize()` already exists in `@semantos/semantos-ir/src/canonical.ts` for exactly this purpose.

## What this seam buys

| Buys | How |
|---|---|
| A single attachment point for new surface grammars | Each new grammar implements `compileToSIR<T>(input: T): SIRProgram`; the rest of the pipeline is shared |
| Trust-tier enforcement for free, when grammars start populating it | `lowerSIR()` already refuses to lower `authoritative` claims without `formal` proofs. Lisp won't trigger this (informal/none defaults), but a Ricardian grammar would |
| Test contract that proves "compression is real, not just labelling" | The α-equivalence assertion across grammars is the closest thing to a formal claim about compression-gradient |

## Out of scope for the wiring

- Populating non-trivial governance context from Lisp programs. Lisp doesn't carry that semantics.
- Building any second surface grammar. That's a future branch — the seam exists so it has somewhere to land.
- Performance: SIR + OIR adds two passes. Compilation isn't on the hot path (runtime is opcode execution, which is unchanged).

## Risks

| Risk | Mitigation |
|---|---|
| `lower()` and `emit()` produce bytes that aren't byte-identical to the direct compiler's output even after canonicalization | Investigate whichever divergence shows up; either fix the equivalence or weaken the test contract to "behavioural equivalence" — execute both byte streams in the cell engine and assert the same final stack state |
| Trust-tier defaults trigger an unexpected rejection in `lowerSIR()` | Run the test corpus before wiring the production path; adjust defaults if needed |
| Adding two passes makes compilation noticeably slower | Unlikely to matter (compile is rare; execute is hot) — but if it does, the direct-compile path can be retained as a fast path with a feature flag |
