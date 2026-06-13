---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/PHASE-4-UPDATE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.330779+00:00
---

# Semantos Cell Engine — Phase 4 Complete

**Date**: 2026-03-27
**From**: Todd Price
**To**: Dusk Engineering + Leadership

---

## What we built

The Semantos cell engine now enforces linearity at the stack machine level. This is Phases 0 through 4 of the Zig/WASM kernel — a 28KB binary that executes Bitcoin Script with an optional type enforcement layer for semantic objects.

Phase 4 added two things: linearity enforcement on stack operations, and the Plexus custom opcodes (0xC0–0xC7).

**Linearity enforcement** means the 2-PDA itself — not application code, not middleware — rejects operations that violate a cell's resource semantics. A LINEAR cell cannot be duplicated (OP_DUP fails). A RELEVANT cell cannot be discarded (OP_DROP fails). This is enforced at execution time by the stack machine, toggled per-script via a single WASM export (`kernel_set_enforcement`). Disabled, the engine runs standard Bitcoin Script unchanged.

**Plexus opcodes** give scripts the ability to inspect cell headers and verify type constraints:

| Opcode | Name | What it checks |
|--------|------|----------------|
| 0xC0 | CHECKLINEARTYPE | Cell is LINEAR |
| 0xC1 | CHECKAFFINETYPE | Cell is AFFINE |
| 0xC2 | CHECKRELEVANTTYPE | Cell is RELEVANT |
| 0xC3 | CHECKCAPABILITY | Cell is LINEAR + has expected capability type |
| 0xC4 | CHECKIDENTITY | Cell's owner_id matches expected BRC-52 identity |
| 0xC5 | ASSERTLINEAR | Hard assertion — script fails if not LINEAR |
| 0xC6 | CHECKDOMAINFLAG | Cell's domain flag matches expected value |
| 0xC7 | CHECKTYPEHASH | Cell's type hash matches expected 32-byte hash |

The opcode mapping is reconciled with the SDK's `opcodes.ts` — 0xC3 and 0xC4 match the SDK's CHECKCAPABILITY and CHECKIDENTITY assignments. 0xC8–0xCF are reserved for future use.

## What's passing

- 240 Zig tests (0 regressions from Phases 0–3)
- 56 TypeScript cross-language tests through the WASM boundary
- Dedicated conformance suites for linearity rules and all 8 Plexus opcodes
- WASM binary at 28KB, well under the 50KB target

## What this enables right now

**Conformance testing against the SDK types.** The engine reads cell headers at the exact offsets defined in `constants.zig` — linearity at byte 16, domain flags at byte 24, type hash at byte 30, owner ID at byte 62, capability type at payload byte 0 (offset 256). Any TypeScript code that constructs cells using the `@semantos/core` types can push them through the WASM engine and verify that linearity rules, capability checks, identity bindings, and domain scoping all work end-to-end. This is your acceptance test harness for the Graph SDK's cell output — no network, no chain, just type correctness.

**Client-side verification.** The WASM binary can run in any browser, Node.js process, or edge runtime. A browser extension loading this module can independently verify semantic constraints on BSV transactions — linearity, capability type, identity ownership, domain scope — without trusting the application or platform serving the page. This makes the verification layer portable and decoupled from the Plexus network services.

**Domain-partitioned access control in script.** A three-opcode script like `<cell> OP_ASSERTLINEAR <owner_id> OP_CHECKIDENTITY <cap_type> OP_CHECKCAPABILITY` is a complete verification predicate: the resource is non-duplicable, belongs to this identity, and grants this specific capability. That's the core of role-based access control, identity-bound resource management, and capability scoping — implemented in the script engine itself, not in application middleware.

## What it doesn't do yet

The engine verifies constraints on cells it receives. It does not mint capability tokens, resolve BRC-52 certificates from the identity domain, perform ECDH key exchange for metering channels, or interact with the derivation registry. Those are application-layer concerns that sit above the kernel — the Graph SDK's territory.

The host cryptographic functions (SHA-256, CHECKSIG) are stubbed for native builds and delegated to host imports in WASM. Full crypto integration is Phase 5 (BEEF/BUMP + host functions).

## Integration surface for the Graph SDK

When the SDK is ready, the integration points are already defined:

- `kernel_set_enforcement(1)` — enable linearity enforcement for a script execution
- `kernel_get_type_class()` — returns 0 (LINEAR), 1 (AFFINE), 2 (RELEVANT), or -1 (UNCLASSIFIED) for the top-of-stack cell
- `kernel_load_script(ptr, len)` — load any script including Plexus opcodes
- `kernel_execute()` — run it

The SDK constructs cells and transactions. The engine verifies them. No shared state, no runtime coupling — just bytes in, result out.

## What's next

**Phase 5**: BEEF/BUMP host function integration and real cryptographic verification. This replaces the hash and signature stubs with working implementations, enabling full transaction verification through the WASM boundary.

**Phases 6–8**: TypeScript binding generation, CI/CD benchmarks, and embedded target support (ARM, RISC-V).

---

The full PRD, errata, and implementation prompts are in `semantos-core/docs/prd/`. The cell engine source is at `semantos-core/packages/cell-engine/`.
