---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/BRANCHING-AND-CI-POLICY.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.335467+00:00
---

# Branching & CI Policy — semantos-core

**Date**: 2026-03-28
**Applies to**: All development from Phase 9 onward.

---

## Branch Strategy

### Branch Names

```
main                              ← Production. Always passes gate tests. Tagged releases.
phase-N-<slug>                    ← Phase work branch (e.g., phase-9-intent-classification)
phase-N-<slug>/D<deliverable>    ← Deliverable sub-branch if needed (e.g., phase-9-intent-classification/D9.1)
fix/<description>                 ← Bug fix branch
errata/<phase>                    ← Errata sprint (e.g., errata/phase-9)
```

### Rules

1. **Never commit directly to main.** All changes come through phase branches via fast-forward merge.
2. **One branch per phase.** Create `phase-9-intent-classification` from `main`. All deliverables for Phase 9 land here.
3. **Sub-branches are optional.** If a deliverable is large or risky, branch from the phase branch. Merge back to the phase branch (not main) when done.
4. **Merge to main only when all gate tests pass.** No exceptions.
5. **Tag after merge.** After merging phase-N to main: `git tag -a vN.0 -m "Phase N: <summary>"`.
6. **Errata branches** are for post-merge fixes. Create from main, merge back to main with tag `vN.1`.

### Workflow

```
main ─────────────────────────────────────────────────── main (tagged v9.0)
  │                                                       ↑
  └─── phase-9-intent-classification ─── gate passes ────┘
         │             │          │
         D9.1          D9.2       D9.3 (optional sub-branches)
```

---

## CI Gate Tests

### Gate Structure

Every phase defines its own gate test file: `packages/__tests__/phase<N>-gate.test.ts`.

Gate tests are **cumulative** — Phase 9 gate includes Phase 0 checks (constants consistency, WASM binary) plus Phase 9-specific checks. This prevents regressions.

```bash
# Run all gates
bun test packages/__tests__/

# Run specific phase gate
bun test packages/__tests__/phase9-gate.test.ts
```

### What Gate Tests MUST Verify

1. **No stubs.** Any function that returns a hardcoded value, throws "NOT_IMPLEMENTED", or returns `undefined` without doing real work is a gate failure.
2. **No mock data.** Tests must use real extension configs (trades-services.json, blockchain-risk.json). Test fixtures are acceptable only if they're clearly labeled and test edge cases, never as substitutes for real config.
3. **Round-trip integrity.** If a function serializes, deserialize must produce the original. If a function creates an object, inspecting it must show the correct state.
4. **Cross-layer consistency.** Constants in JSON = constants in TypeScript = constants in Zig WASM. Type hashes computed in TypeScript = type hashes in the cell header.
5. **Behavioral tests, not structural tests.** Don't test that a function exists — test that it does the right thing with real inputs.

### Anti-Bullshit Gates (Mandatory)

These run on every phase gate:

```typescript
// In every phase gate file:
describe("Anti-regression: no stubs or mocks", () => {
  test("no NOT_IMPLEMENTED in source files", () => {
    // Scan all .ts files in src/ and packages/loom/src/
    // Fail if any contain "NOT_IMPLEMENTED" or "TODO: implement"
    // Exception: comments that document future work are OK
  });

  test("no hardcoded test expectations that match default values", () => {
    // If a test expects "" or 0 or null, it's probably testing a stub
  });

  test("extension configs have non-empty typeHash values", () => {
    // Every ObjectTypeDefinition in every config must have a computed typeHash
  });
});
```

### Pre-Merge Checklist

Before merging any phase branch to main:

- [ ] `bun test` passes (all gate files)
- [ ] `bun run check` passes (TypeScript strict mode, zero errors)
- [ ] `bun run build` succeeds
- [ ] No `// TODO` or `// FIXME` in delivered code (move to errata doc if unresolvable)
- [ ] New files have JSDoc comments on exported functions
- [ ] Extension configs validate (`validateExtensionConfig()` passes for all 4 configs)
- [ ] README updated if public API changed

---

## CI/CD Pipeline (GitHub Actions)

### File: `.github/workflows/gate.yml`

```yaml
name: Gate Tests
on:
  push:
    branches: [main, "phase-*"]
  pull_request:
    branches: [main]

jobs:
  gate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v1
        with:
          bun-version: latest
      - run: bun install
      - run: bun run check
      - run: bun test packages/__tests__/
      - run: bun run build

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: oven-sh/setup-bun@v1
        with:
          bun-version: latest
      - run: bun install
      - name: No stubs in source
        run: |
          if grep -rn "NOT_IMPLEMENTED\|throw new Error.*not yet\|throw new Error.*stub" src/ packages/loom/src/ --include="*.ts" --include="*.tsx" | grep -v "node_modules" | grep -v "__tests__"; then
            echo "FAIL: Found stub/mock code in source files"
            exit 1
          fi
      - name: Extension configs valid
        run: bun -e "
          const { validateExtensionConfig } = require('./packages/loom/src/config/extensionConfig');
          const fs = require('fs');
          for (const f of fs.readdirSync('configs/extensions')) {
            const data = JSON.parse(fs.readFileSync('configs/extensions/' + f, 'utf-8'));
            validateExtensionConfig(data);
            console.log('PASS:', f);
          }
        "
```

### Future: Zig WASM Gate (When Cell Engine Is Real)

```yaml
  wasm:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.13.0
      - run: cd packages/cell-engine && zig build
      - run: cd packages/cell-engine && zig build test
      - name: WASM binary under 20KB
        run: |
          SIZE=$(stat -c%s packages/cell-engine/zig-out/bin/cell-engine.wasm)
          if [ "$SIZE" -gt 20480 ]; then
            echo "FAIL: WASM binary is $SIZE bytes (max 20480)"
            exit 1
          fi
```

---

## Commit Message Convention

```
phase-9/D9.1: implement OpenRouter LLM bridge

- IntentClassifier service with IntentClassification return type
- BYOK API key configuration in loom settings
- Tests against trades-services and blockchain-risk extensions
```

Format: `<branch-context>: <what changed>`

Body: bullet points of deliverables addressed. Reference gate tests that now pass.

---

## Emergency Procedures

### Broken main

If main is broken (gate tests fail after merge):

1. `git revert <merge-commit>` on main immediately.
2. Fix on the phase branch.
3. Re-merge when gates pass.

Do not force-push main. Do not amend merged commits.

### Errata Discovery

If a shipped phase has a bug discovered later:

1. Create `errata/phase-N` from main.
2. Fix + add regression test to the phase gate.
3. Merge to main, tag `vN.1`.

---

## Post-Phase Deep Scan & Errata Sprint Protocol

**Every phase merge to main MUST be followed by an errata sprint.** This is not optional. The pattern proven in earlier phases (Phase 3 errata identified 5 critical bugs in shipped code) is now mandatory.

### Deep Scan Procedure

After merging `phase-N-<slug>` to main and before starting Phase N+1:

1. **Open a fresh session.** Do not reuse the implementation session — it has blind spots from building the code.

2. **Paste the errata prompt** (template below). The fresh session reads all delivered code with adversarial intent.

3. **The scan checks for:**
   - Stubs or TODO markers left in source
   - Tests that pass by checking default values or undefined
   - Hardcoded values that should come from config
   - Type errors masked by `any` casts
   - React coupling in services (imports from React in `src/services/`)
   - Empty typeHash values in extension configs
   - Functions that silently swallow errors
   - State mutations outside the store pattern
   - Missing facet provenance on patches
   - Linearity transitions without gate checks
   - Conversation flows that skip required capabilities

4. **Output:** An errata document at `docs/prd/PHASE-N-ERRATA.md` listing each bug with:
   - File and line number
   - What's wrong
   - What the fix should be
   - Regression test to add

5. **Fix sprint:** Create `errata/phase-N` branch, apply fixes, run all gates, merge to main, tag `vN.1`.

### Errata Scan Prompt Template

Paste this into a fresh session after each phase merge:

```
# Phase N Errata Scan

You are auditing Phase N of @semantos/core. The code was just merged to main.
Your job is to find bugs, not to praise the implementation.

## Read first
- docs/prd/PHASE-N-PROMPT.md — the requirements this code was supposed to meet
- docs/BRANCHING-AND-CI-POLICY.md — the quality gates it was supposed to pass

## Then read ALL delivered code
[list the specific files delivered in Phase N]

## Scan for
1. Any function body that is a stub, returns hardcoded values, or throws "not implemented"
2. Any test that passes by checking .toBeDefined() or comparing to default values
3. Any `as any` cast that masks a type error
4. Any import from 'react' in files under src/services/
5. Any empty typeHash in extension configs
6. Any createObject() call that doesn't propagate typeHash
7. Any patch created without facet provenance (facetId + facetCapabilities)
8. Any linearity transition without checking current state
9. Any flow that doesn't verify requiredCapabilities before executing
10. Any error path that returns undefined instead of throwing

## Output
For each bug found, write:
- **File**: exact path
- **Line**: approximate line number
- **Bug**: what's wrong
- **Fix**: what it should be
- **Test**: regression test to add to the phase gate

If you find zero bugs, explain what you checked and why you're confident.
Do NOT say "the code looks good" without evidence.
```

### Errata Sprint Timeline

The errata sprint should take 1-2 hours per phase. If it takes longer, the phase was shipped prematurely.

```
Phase N merge → Deep scan session (1h) → Errata doc → Fix sprint (1-2h) → vN.1 tag → Phase N+1 starts
```
