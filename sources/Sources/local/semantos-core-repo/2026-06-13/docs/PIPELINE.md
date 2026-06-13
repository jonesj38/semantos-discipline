---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/PIPELINE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.336294+00:00
---

# Pipeline — NL → SIR → OIR → opcodes → cell engine

The compilation pipeline that lowers high-level intent down to bytes the WASM kernel can execute. This doc is the single source of truth for what's built, what's wired, and what's planned.

## Live flow today

What actually runs when you type a Lisp policy expression into `semantos-shell` (`compile (op …)`):

```
Lisp source text
        │
        ▼  runtime/shell/src/lisp/parser.ts
        │
   SExpression (parse tree)
        │
        ▼  runtime/shell/src/lisp/types.ts: interpretConstraint() / interpretPolicy()
        │
   ConstraintExpr (AST)
        │
        ▼  runtime/shell/src/lisp/compiler.ts: compile()
        │
   Uint8Array (opcode bytes 0x4C–0xD0)
        │
        ▼
   Cell engine (Zig/WASM 2-PDA)
```

The Lisp compiler skips IR/SIR and emits opcodes directly. This is fine — it works, has golden-file test coverage, and ships.

## Intended flow (after Phase 3 wiring)

```
Surface grammar
       Lisp ✓        LaTeX ✗      Lean-ish ✗     Ricardian ✗     EDI ✗
              \         |              |              |          /
               \________|______________|______________|_________/
                                    │
                                    ▼
                        SIR  (semantic IR)
                  core/semantos-sir/src/types.ts
                        │
                        ▼  lowerSIR()      ← core/semantos-sir/src/lower-sir.ts
                        │
                        ▼
                        OIR  (opcode IR, ANF)
                  core/semantos-ir/src/types.ts
                        │
                        ▼  emit()          ← core/semantos-ir/src/emit.ts
                        │
                  Opcode bytes (0x4C–0xD0)
                        │
                        ▼
                  Cell engine (Zig/WASM 2-PDA)
                  core/cell-engine/
```

## Component status

| Component | Built? | Wired? | File |
|---|---|---|---|
| Lisp parser (text → SExpression) | ✓ | ✓ | [runtime/shell/src/lisp/parser.ts](../runtime/shell/src/lisp/parser.ts) |
| Lisp compiler (CExpr → opcodes) | ✓ | ✓ | [runtime/shell/src/lisp/compiler.ts](../runtime/shell/src/lisp/compiler.ts) |
| OIR types (ANF) | ✓ | unused | [core/semantos-ir/src/types.ts](../core/semantos-ir/src/types.ts) |
| OIR `lower(CExpr → IRProgram)` | ✓ | unused | [core/semantos-ir/src/lower.ts](../core/semantos-ir/src/lower.ts) |
| OIR `emit(IRProgram → bytes)` | ✓ | unused | [core/semantos-ir/src/emit.ts](../core/semantos-ir/src/emit.ts) |
| SIR types (jural categories, trust class, governance) | ✓ | unused | [core/semantos-sir/src/types.ts](../core/semantos-sir/src/types.ts) |
| SIR `lowerSIR(SIRProgram → IRProgram)` with trust-tier enforcement | ✓ | unused | [core/semantos-sir/src/lower-sir.ts](../core/semantos-sir/src/lower-sir.ts) |
| LaTeX surface | ✗ | ✗ | future |
| Lean-ish surface | ✗ | ✗ | future |
| Ricardian-contract surface | ✗ | ✗ | future |
| EDI surface | ✗ | ✗ | future |
| Cell engine (Zig/WASM 2-PDA) | ✓ | ✓ | [core/cell-engine/src/](../core/cell-engine/src/) |

The OIR and SIR packages are both **fully implemented** but **bypassed by the Lisp compiler**. Phase 3 of the restructure wires them in. Design note: [PIPELINE-SIR-WIRING.md](PIPELINE-SIR-WIRING.md).

## Why a dual IR (SIR above OIR)

Each layer compresses the previous and adds something new:

| Layer | What it adds | Why it has to exist |
|---|---|---|
| SIR | Jural categories, trust class, proof requirement, execution authority, governance context | These are *semantic* claims — they constrain what computations are even legal before lowering to mechanical predicates. `lowerSIR()` refuses to produce OIR if (e.g.) an `authoritative` claim has no `formal` proof. |
| OIR (ANF) | Named bindings, explicit data flow, computational predicates | This is the lingua franca of compilation — once everything is in ANF, multiple back-ends (currently just opcode bytes; later WASM directly?) can target it without parsing again. |
| Opcode bytes | Concrete VM instructions in 0x4C–0xD0 range | This is what the cell engine executes. |

The compression-gradient claim: the same intent expressed in two different surface grammars (e.g. Lisp and LaTeX) should produce OIR programs that are α-equivalent. That equivalence is what makes "semantic compression" a real claim rather than a marketing line — and what makes paid extension grammars viable as a commercial direction (they all lower into the same OIR; the kernel doesn't care which surface produced it).

## What "compression" means concretely

A small example. Say the policy "any party with the SIGNING capability for protocol 0x02 may perform this action". 

| Stage | Approx. size | Notes |
|---|---|---|
| Natural language | ~14 words | "any party with the SIGNING capability for protocol 0x02 …" |
| Lisp surface | ~3 forms | `(check-cap SIGNING 0x02)` |
| OIR (ANF) | 1 binding | `$0 := check-cap(SIGNING, 0x02)` |
| Opcode bytes | 4 bytes | `0xC3 0x01 0x02` (OP_CHECKCAPABILITY + 2-byte protocol id) |

The dramatic compression at the bottom is what makes the kernel small (185 KB full / 29 KB embedded). The dramatic compression at the top — from NL through SIR — is what makes domain-specific grammars feasible without forking the kernel.

## Test corpus

Golden-file tests anchor each pass:

- Lisp compiler: [runtime/shell/src/lisp/__tests__/](../runtime/shell/src/lisp/__tests__/) (if present, otherwise inline within the package's test directory)
- OIR lower + emit: [core/semantos-ir/src/__tests__/](../core/semantos-ir/src/__tests__/)
- SIR lower with trust-tier enforcement: [core/semantos-sir/src/__tests__/golden.test.ts](../core/semantos-sir/src/__tests__/golden.test.ts)

When wiring SIR into the Lisp compiler (Phase 3), the test that anchors the seam is:

> For every program in the existing Lisp golden corpus,  
> `compile(src)` must produce bytes byte-identical (or α-equivalent) to `emit(lowerSIR(compileToSIR(src)))`.

That equivalence is the contract — adding SIR must not change observable behaviour for the existing corpus.

## Related docs

- [PIPELINE-SIR-WIRING.md](PIPELINE-SIR-WIRING.md) — how the SIR seam will be wired in Phase 3
- [SHELL.md](SHELL.md) — `semantos-shell` entry point and how to drive the pipeline interactively
- [SHELL-VERBS.md](SHELL-VERBS.md) — verb reference (incl. `compile`, `eval`, `bind`)
- [RESTRUCTURING-PLAN.md](RESTRUCTURING-PLAN.md) — strategic plan; this doc is the implementation reference
