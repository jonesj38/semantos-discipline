---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/IMPLEMENTATION-PLAN-POST-HELM-MERGE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.685969+00:00
---

# Implementation Plan — Post-Helm Merge

**Date**: 2026-04-17
**Precondition**: `cleanup/helm-shell-redundancy` merged to `main` (commit `63f47a7`).
**Goal**: Execute Window 1 + launch two parallel tracks (paskian rename, IR extraction kickoff).

---

## Guiding Constraint

**Do not ship 38A without trust-tier fields in the same PR.**

Once `HOST_EXEC` exists, economic execution flows through a governance plane that cannot structurally distinguish cosmetic from authoritative patches. The fields must exist to gate against, even if initial values are conservative defaults. Landing them paired is cheap; unwinding after `host.exec` touches a non-dev environment is expensive.

The corollary from Todd's feedback: **half-enforcement is worse than no field**. The initial enforcement must be conservative-by-default — reject anything `authoritative` pending prover hookup in Window 7 — not a skeleton that reads the fields and enforces nothing.

---

## Track 1 (Hot Path): Window 1 — Phase 38A + Trust-Tier Schema

### Branch: `phase-38-voice-to-execution`

Cut from `main` at `63f47a7`.

### Step 1.1 — Trust-Tier Fields on ManifestGovernanceConfig

**Files to modify:**

1. `packages/protocol-types/src/governance.ts` — add to `ManifestGovernanceConfig`:

```typescript
/** Trust tier for patches produced under this manifest's grammar. */
trustClass: 'cosmetic' | 'interpretive' | 'authoritative';

/**
 * What proof obligation the trust class imposes on promotion.
 * 'none'       — cosmetic patches, no formal proof needed
 * 'attestation' — interpretive, requires facet attestation chain
 * 'formal'     — authoritative, requires Lean theorem reference (Window 7)
 */
proofRequirement: 'none' | 'attestation' | 'formal';

/**
 * Who/what can trigger execution on objects under this manifest.
 * 'local_facet' — only the owning facet (default, most conservative)
 * 'hat_scoped'  — any facet with the right hat cert (V2E model)
 * 'delegated'   — future federation, not implemented
 */
executionAuthority: 'local_facet' | 'hat_scoped' | 'delegated';
```

2. `packages/extraction/src/governance/constraint-engine.ts` — add **real enforcement** in `enforceL0Constraints`:

```typescript
// Trust-tier enforcement — conservative-by-default
const trustClass = manifest.governanceConfig?.trustClass;
const proofReq = manifest.governanceConfig?.proofRequirement;

if (trustClass === 'authoritative' && proofReq !== 'formal') {
  violations.push({
    level: 'L0',
    rule: 'authoritative-requires-formal-proof',
    message: 'Authoritative trust class requires proofRequirement "formal". ' +
      'Until Window 7 prover hookup, authoritative manifests cannot be published.',
  });
}

if (manifest.governanceConfig?.executionAuthority === 'delegated') {
  violations.push({
    level: 'L0',
    rule: 'delegated-execution-not-implemented',
    message: 'Delegated execution authority is not yet implemented. Use "local_facet" or "hat_scoped".',
  });
}
```

3. `packages/extraction/src/governance/manifest-publisher.ts` — enforce trust-tier fields are present before publication:

```typescript
// Trust-tier fields required for publication
if (!manifest.governanceConfig?.trustClass) {
  errors.push('Manifest governanceConfig must declare trustClass before publication.');
}
if (!manifest.governanceConfig?.proofRequirement) {
  errors.push('Manifest governanceConfig must declare proofRequirement before publication.');
}
if (!manifest.governanceConfig?.executionAuthority) {
  errors.push('Manifest governanceConfig must declare executionAuthority before publication.');
}
```

**Why this ordering**: The trust-tier types must exist before `host-ops.json` is written, because `host-ops.json` declares `governanceConfig` with `trustClass: "interpretive"`, `proofRequirement: "attestation"`, `executionAuthority: "hat_scoped"`.

**Commit**: `phase-38/D38A.0: trust-tier fields on ManifestGovernanceConfig with conservative-by-default enforcement`

### Step 1.2 — HostCommand Type + HOST_EXEC Capability

Per the Phase 38A prompt (`docs/prd/PHASE-38A-PROMPT.md`), with these specifics confirmed from codebase audit:

**Capability ID allocation**: Existing configs use IDs 1–10 (EDGE_CREATION through METERING). The `PlexusStandardFlags` in `packages/plexus-contracts/src/domain-flags.ts` reserve `0x01–0x0c`. The `ClientDomainFlags` use `0x00010001–0x0001000a`. HOST_EXEC gets:

- Config-level ID: `11` (next free after METERING=10)
- Plexus standard flag: `0x0d` (next free after MESSAGING=0x0c; note: 0x0b is ZONE_KEY)
- Client domain flag: `0x0001000b` (next free after ADMIN=0x0001000a)

**Files to create:**

1. `configs/extensions/host-ops.json` — per 38A prompt spec:
   - `HostCommand` objectType: LINEAR, archetype "action", visibility `["draft", "published"]`
   - `HOST_EXEC` capability: `{ "id": 11, "name": "HOST_EXEC", "scope": "Execute whitelisted host handlers" }`
   - `governanceConfig` with trust-tier: `trustClass: "interpretive"`, `proofRequirement: "attestation"`, `executionAuthority: "hat_scoped"`
   - coordinationModes: `do/transact` for command execution, `find/truth` for audit
   - typeHash: real sha256 of canonical type definition (not handwritten)

**Files to modify:**

2. `packages/plexus-contracts/src/domain-flags.ts` — add:
   ```typescript
   /** Phase 38: Execute whitelisted host handlers. */
   HOST_EXEC: 0x0d,
   ```
   to `PlexusStandardFlags` (0x0b is ZONE_KEY, 0x0c is MESSAGING, so HOST_EXEC = 0x0d), and:
   ```typescript
   HOST_EXEC: 0x0001000b,
   ```
   to `ClientDomainFlags`.

3. `packages/shell/src/capabilities.ts` — add HOST_EXEC verb mapping:
   ```typescript
   'host.exec': 0x0001000b,  // HOST_EXEC
   ```
   and in `FLAG_NAMES`:
   ```typescript
   0x0001000B: 'Host Execute',
   ```

4. `packages/shell/src/router.ts` — add case for `'host.exec'` verb (stub that returns "not yet implemented — see 38C"). The router already exists and this is a one-line addition to the switch.

**Commit**: `phase-38/D38A.1: HostCommand type, HOST_EXEC capability, host-ops extension config`

### Step 1.3 — Gate Tests

**File to create:**

`packages/__tests__/phase38-gate.test.ts`

Tests (per 38A prompt + trust-tier additions):

1. `host-ops.json` validates via `validateExtensionConfig()`
2. `HostCommand` typeHash is non-empty and matches re-computation
3. `HOST_EXEC` capability ID (11) does not collide with any other extension's capability
4. `HostCommand.linearity === "LINEAR"`
5. `HostCommand.visibility.states` contains exactly `["draft", "published"]`
6. `defaultCapabilities` on `HostCommand` includes HOST_EXEC id
7. Required fields: `handler`, `args`, `hatId`, `hatCertId`, `hatSig`, `requestedAt`
8. **Trust-tier gate**: `host-ops.json` `governanceConfig` declares `trustClass`, `proofRequirement`, `executionAuthority`
9. **Conservative enforcement**: manifest with `trustClass: "authoritative"` + `proofRequirement: "none"` fails `enforceL0Constraints`
10. **Delegated rejection**: manifest with `executionAuthority: "delegated"` fails `enforceL0Constraints`
11. All prior phase gates still pass (`bun test packages/__tests__/`)

**Commit**: `phase-38/D38A.3: gate tests for HostCommand, HOST_EXEC, and trust-tier enforcement`

### Step 1.4 — Verification

```bash
bun run check                    # tsc --noEmit across all packages
bun test packages/__tests__/     # all gate tests, cumulative
```

All green before pushing the branch.

---

## Track 2 (Parallel PR): packages/paskian Rename

### Branch: `rename/paskian-to-settlement`

Cut from `main` at `63f47a7`. Independent of Track 1 — no merge-order dependency.

### Why now

The `packages/paskian` name collides with the Paskian learning concept (adaptive grammar-patch proposer) which lives in `packages/extraction/src/inference`. The package actually contains the BSV settlement layer (border-router aggregator, CBOR encoding, WebSocket relay). The rename is cheap now and expensive after external contributors arrive. It blocks nothing and clarifies everything.

### Scope

**Package contents** (confirmed from `package.json` and source listing):
- `border-router.ts` — BSV aggregation relay
- `adapter.ts`, `store.ts`, `store/` — transaction store
- `grammar.ts`, `narrative-oracle.ts` — story/narrative settlement grammar
- `api/`, `ecs/`, `services/` — supporting infrastructure
- `__tests__/` — existing tests

**Imports to update** (grep for `@semantos/paskian`):
- Any cross-package imports (check `packages/shell/src/commands/settle.ts` and `packages/helm/`)
- Root `package.json` workspace entries
- `tsconfig.json` references
- `configs/extensions/paskian-story.json` — rename to `settlement-story.json`

### Steps

1. `git mv packages/paskian packages/settlement`
2. Update `packages/settlement/package.json`: `name: "@semantos/settlement"`
3. Find-and-replace `@semantos/paskian` → `@semantos/settlement` across all imports
4. Update workspace config, tsconfig references
5. Rename `configs/extensions/paskian-story.json` → `settlement-story.json`
6. Run `bun install` to relink workspace
7. `bun run check && bun test packages/__tests__/`
8. Single commit: `rename: @semantos/paskian → @semantos/settlement (settlement layer, not Paskian learning)`

### PR body note

> The "Paskian" name belongs to the adaptive grammar-patch proposer (packages/extraction/src/inference),
> not the BSV settlement layer. This rename removes the collision before external contributors
> encounter it. See docs/SHELL-ALIGNMENT-VS-ARCHITECTURE-VISION.md §4.8 for rationale.

---

## Track 3 (Parallel Branch): IR Extraction Kickoff

### Branch: `feat/semantos-ir`

Cut from `main` at `63f47a7`. Independent of Tracks 1 and 2.

### Why now

The IR is the unsexy unblocking dependency for Windows 4–5. Every peer-frontend (Rúnar, Lean-ish, TeX Profile) must target the same intermediate representation. Starting the IR extraction in parallel with Phase 38 work removes this from the critical path before it becomes a bottleneck.

### What exists today

`packages/shell/src/lisp/compiler.ts` contains the `LispCompiler` class that does the full transformation: s-expression → `ConstraintExpr` AST → opcode bytes. The compilation is already deterministic and pure (no I/O, no side effects). The relevant types in `lisp/types.ts`:

- `ConstraintExpr`: comparison | logical | capability | domainCheck | timeConstraint | hostCall | typeHashCheck | deref
- `PolicyForm`: subject + action + constraint + linearity
- `ScriptOutput`: scriptWords (human-readable) + scriptBytes (cell engine opcodes) + metadata

### What needs extracting

The IR lives between the AST (`ConstraintExpr`) and the opcode bytes. Currently the compiler goes straight from AST to opcodes in one pass. The Rúnar methodology (§5 of the alignment memo) tells us the shape:

1. **ANF (Administrative Normal Form)**: every sub-expression gets a name, every operation takes named inputs. This is the IR.
2. **Canonical serialization**: JSON RFC 8785 (deterministic key ordering) for the IR representation.
3. **Nanopass structure**: split `compileConstraint()` into discrete passes, each doing one transformation.

### Deliverables for this branch

This is a **kickoff**, not a completion. Scope is deliberately narrow:

1. **Create `packages/semantos-ir/`** as a new workspace package:
   - `src/types.ts` — ANF IR types: `IRNode`, `IRBinding`, `IRProgram`
   - `src/canonical.ts` — RFC 8785 canonical JSON serializer
   - `src/lower.ts` — `ConstraintExpr` → `IRProgram` (first nanopass)
   - `src/emit.ts` — `IRProgram` → opcode bytes (second nanopass)

2. **Golden-file test suite** (`packages/semantos-ir/src/__tests__/golden.test.ts`):
   - A handful of representative `ConstraintExpr` inputs
   - Expected IR output (JSON) and expected opcode bytes
   - The test asserts `lower(expr)` matches the golden IR, and `emit(lower(expr))` matches the golden bytes
   - This is the Rúnar differential-testing methodology: if a second frontend (e.g. Rúnar) produces the same IR for the same semantics, it's equivalent

3. **Do NOT modify `lisp/compiler.ts` yet.** The existing compiler continues to work. The IR package is a parallel path that proves the shape. Once golden tests pass, a follow-up PR rewires `LispCompiler.compile()` to go through the IR, and the golden tests become the regression suite.

### Commit structure

```
feat/semantos-ir: scaffold ANF IR types + canonical serializer
feat/semantos-ir: lower pass (ConstraintExpr → IRProgram)
feat/semantos-ir: emit pass (IRProgram → opcodes)
feat/semantos-ir: golden-file test suite (5 representative cases)
```

### What NOT to do

- Do not copy Rúnar's schema. The BSV script model doesn't have `ConstraintExpr` or `PolicyForm`. Take the **methodology** (ANF + canonical JSON + nanopass + golden files), not the types.
- Do not attempt to wire Rúnar as a frontend yet. That's Window 4 work, and Window 4 is gated on this IR existing.
- Do not add post-quantum signature support. That's an orthogonal strategic prize (WOTS+/SLH-DSA), not on the critical path.

---

## Sequencing Diagram

```
main (63f47a7)
 │
 ├──► Track 1: phase-38-voice-to-execution
 │      Step 1.1  trust-tier fields + enforcement
 │      Step 1.2  HostCommand + HOST_EXEC + host-ops.json
 │      Step 1.3  phase38-gate.test.ts
 │      Step 1.4  verify all gates green
 │      ─── merge when green ───
 │      │
 │      └──► Window 2 begins (38B handler registry → 38C host.exec → 38G Helm wiring)
 │
 ├──► Track 2: rename/paskian-to-settlement  (parallel, small, independent)
 │      Single commit: git mv + import updates
 │      ─── merge independently ───
 │
 └──► Track 3: feat/semantos-ir  (parallel, independent)
        Scaffold → lower → emit → golden tests
        ─── merge independently ───
        │
        └──► Window 4 begins (Rúnar frontend targeting Semantos IR)
```

### Merge order

Tracks 2 and 3 can merge to `main` in any order, at any time — they don't touch the same files as Track 1. Track 1 merges when all phase-38 gate tests pass. If Track 2 merges first, Track 1 rebases on the rename (trivial — `settle.ts` import path changes).

---

## Window 2 Preview (What Follows Track 1)

Once Window 1 lands, the hot path continues per `docs/prd/PHASE-38-VOICE-TO-EXECUTION.md`:

| Sub-phase | What | Blocks on |
|---|---|---|
| **38B** | Handler registry + `process.killByPort` reference handler | 38A (Track 1) |
| **38C** | `host.exec` shell verb — parser, router, capability gate, publish-then-execute | 38B |
| **38G** | Helm UI: Talk input → approval card → Do/Transact receipt | 38C + 38F |

PRDs for each exist on main (`PHASE-38B-PROMPT.md`, `PHASE-38C-PROMPT.md`, `PHASE-38G-PROMPT.md`). Each is self-contained and lists its read-first files.

Parallel Window 2 tracks (can start immediately after Track 1 merges):

- **38D** (audit CLI: `host audit <id>`) — needs a published HostCommand to verify against
- **38E** (voice capture adapter) — pure UI, can even start now
- **38F** (NL → ShellCommand extractor) — needs 38A schema to target

---

## What This Plan Does NOT Do

1. **No Window 3 DomainRiskTier + SCADA hard-block.** That's after Window 2 and requires the handler registry (38B) to exist so SCADA samples can be classified before InferenceAgent sees them.
2. **No Rúnar frontend wiring (Window 4).** Gated on Track 3 IR extraction completing and proving out via golden tests.
3. **No Lean-ish frontend, TeX Profile, ricardian, or EDI packages (Window 5).** All gated on IR.
4. **No continuous Paskian monitor (Window 6).** The InferenceAgent in `packages/extraction/src/inference` is one-shot today. Continuous monitoring is a separate architecture conversation.
5. **No Lean gating via enforceProofObligations() (Window 7).** The conservative-by-default enforcement in Step 1.1 holds the door: authoritative manifests are rejected until this exists. That's the correct interim state.

---

## Risk Register

| Risk | Mitigation |
|---|---|
| **Trust-tier enforcement is too conservative** — blocks legitimate `interpretive` manifests | `interpretive` + `proofRequirement: "attestation"` passes. Only `authoritative` + `proofRequirement !== "formal"` is blocked. The default for `host-ops.json` is `interpretive`. |
| **Capability ID dual-numbering confusion** | Config-level ID `11` and Plexus standard flag `0x0d` refer to the same capability. The `capabilities.ts` mapping uses `ClientDomainFlags` (0x0001000b) for router gating. Document the triple in the `host-ops.json` header comment. |
| **paskian rename breaks CI** | The `@semantos/workbench → @semantos/loom` rename (PR #69) is the exact template. Same pattern: git mv, find-and-replace imports, `bun install`, run tests. |
| **IR extraction scope creep** | Scope is 4 files + golden tests. No LispCompiler modification. No Rúnar wiring. The branch ships a proof-of-shape, not a completed subsystem. |
| **Track 1 and Track 2 merge conflict** | Only overlap is `settle.ts` import path. Trivial rebase. |

---

## Exit Criteria

- [ ] `phase-38-voice-to-execution` branch: trust-tier fields + HostCommand + HOST_EXEC + gate tests all green
- [ ] `rename/paskian-to-settlement` PR merged (or ready to merge)
- [ ] `feat/semantos-ir` branch: golden-file tests pass for 5+ representative constraint expressions
- [ ] No regressions: `bun test packages/__tests__/` passes on each branch before merge
- [ ] `docs/SHELL-ALIGNMENT-VS-ARCHITECTURE-VISION.md` remains accurate (no contradictions introduced)
