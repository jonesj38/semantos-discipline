---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tools/sx/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.993151+00:00
---

# `.sx` Zig dialect — toolchain port of bitcoinsx `SxCompiler`

**Status:** PR-1 skeleton (lexer + AST node types + first parity test). Lands
the structure; full lexer coverage / parser / lowerer follow in PR-2/3.

**Target:** byte-for-byte drop-in replacement for
[`bitcoinsx/src/sx/src/`](https://github.com/wallCalendarClubOfficial/bitcoinsx/tree/main/src/sx/src)
(`tokeniser.ts` + `parser.ts` + `compiler.ts`), built in Zig 0.15.2, with a
WASM build (PR-4) exposing a JS API that matches `SxCompiler` exactly.

**Why:** see `docs/prd/RUNAR-ZIG-INTEGRATION-EVAL.md` §11.10 task 4c. This
port + the existing Rúnar integration (task 4b) together register two
dialects in `dialect.zig` that lower to the same cell-engine bytecode — the
foundation for the cleavage manifest's per-section `dialect` field and for
turning bitcoinsx's IDE into a substrate-native cartridge.

## Scope (this PR family)

| PR | Module | LOC est | Acceptance |
|----|--------|---------|-----------|
| 1 (this) | `lex.zig` + `node.zig` + `error.zig` + first parity test | ~600 | Tokens emitted match his `tokeniseTypes.test.ts` cases — type, value, pos/line/col |
| 2 | `parse.zig` | ~900 | AST JSON-serialized matches his AST on the full `src/sx/contracts/` corpus |
| 3 | `lower.zig` + `opcodes_camelcase.zig` + `bigint.zig` | ~1000 | All `.sx` files in his corpus produce byte-identical hex |
| 4 | `wasm/` (WASM target + JS shim + npm `@semantos/sx`) | ~400 | Existing Next.js consumers can swap import path with no other changes |
| 5 | CI: run his Jest suite against our WASM build | (glue) | Green badge tracking his upstream |

## Fidelity discipline

Every numeric tag, property name, error message string, and edge case
behaviour comes from his code, not from any "cleaner" Zig redesign:

- `NodeType` enum values match his `nodeTypes` object (root=0..pushCodeData=17)
- `Node` field names match `SxNode` field names
- `TokeniserError` field shape matches his interface exactly
- shortOps table is verbatim from `src/sx/src/lib/utils.ts`
- Error message strings will match what his tests assert

This is load-bearing. The whole "swap one import" pitch falls over if our
output diverges in ways downstream code notices.

## Out of scope

- `simulator.ts` (1822 LOC) — substituted by the cell-engine executor; no JS shadow
- Extended vocabulary (0xB0+ Craig macros, Plexus, hostcall, routing) — Phase 2
- Cleavage manifest exporter — needs PR-3 to land first
- Disassembler — useful, not load-bearing for drop-in

## Upstream we track

Pinned to bitcoinsx commit-SHA (TODO once PR-2 picks the snapshot). CI will
diff against upstream and open a PR if his corpus grows.

## Coordinate with

- `core/cell-engine/tools/asm.zig` — the canonical assembler we share a backend with
- `docs/design/LOCKSCRIPT-CLEAVAGE.md` — the cleavage discipline the manifest sections enforce
- `docs/prd/RUNAR-ZIG-INTEGRATION-EVAL.md` — Rúnar, the sibling dialect
