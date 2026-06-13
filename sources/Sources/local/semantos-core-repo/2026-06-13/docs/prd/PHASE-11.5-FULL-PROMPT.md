---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-11.5-FULL-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.668846+00:00
---

# Phase 11.5 — Full Execution Prompt (Git Hygiene + Build + Errata)

> Paste this into a fresh Claude Code session. It handles git cleanup, Phase 11.5 execution, and errata — end to end.

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
```

### 0.2 Commit or discard uncommitted work

If uncommitted changes exist:
- Read each changed file. Is this Phase 11 work that should be committed, or stale junk?
- Commit real work in logical groups (stage files explicitly, never `git add -A`).
- Discard stale files: `git checkout -- <file>`.

### 0.3 Verify Phase 11 is complete

```bash
git log --oneline --all | grep -i "phase.11"
```

Phase 11 Lean proofs must be committed. Verify theorem files exist:

```bash
ls proofs/lean/Semantos/Theorems/LinearityK1.lean \
   proofs/lean/Semantos/Theorems/AuthSoundnessK2.lean \
   proofs/lean/Semantos/Theorems/DomainIsolationK3.lean \
   proofs/lean/Semantos/Theorems/FailureAtomicK4.lean \
   proofs/lean/Semantos/Theorems/TerminationK5.lean \
   proofs/lean/Semantos/Theorems/CellImmutabilityK7.lean
```

All 6 must exist. If missing, Phase 11 is incomplete — STOP.

Verify no sorry:
```bash
grep -rn "sorry" proofs/lean/Semantos/Theorems/ --include="*.lean" && echo "FAIL: sorry found" || echo "PASS: no sorry"
```

### 0.4 Create Phase 11.5 branch

```bash
git checkout -b phase-11.5-tla-protocol
```

### 0.5 Install TLA+ toolbox

```bash
# Check if TLC is available
java -cp tla2tools.jar tlc2.TLC 2>/dev/null && echo "TLC available" || echo "NEED TLC"
```

If TLC is not available, download:
```bash
mkdir -p tools
curl -L -o tools/tla2tools.jar https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar
# Verify
java -jar tools/tla2tools.jar -h 2>&1 | head -3
```

### 0.6 Set git identity

```bash
git config user.email 2>/dev/null || git config user.email "dev@semantos.dev"
git config user.name 2>/dev/null || git config user.name "Semantos Dev"
```

**GATE**: Clean branch, Phase 11 proofs verified, TLC available. Proceed.

---

## PART 1: READ BEFORE YOU WRITE

**Read first** (requirements):
- `docs/prd/PHASE-11.5-TLA-PROTOCOL.md` — deliverables D11.5.0–D11.5.7
- `docs/FORMAL-VERIFICATION-STRATEGY.md` — compliance test → proof obligation mapping (Section 6)

**Read second** (the code you are modeling):
- `src/types/semantic-objects.ts` — SemanticObject, LinearObject, AffineObject, RelevantObject, ConsumptionProof, RevocationProof
- `src/compiler/validator.ts` — validateConsumption, validateRevocation, isConsumed, canConsume
- `src/metering/channel-fsm.ts` — ChannelState enum, transition table, tick()
- `src/types/domain-flags.ts` — DomainFlag enum, flag values
- `src/types/capability.ts` — CapabilityToken, CapabilityType

**Read third** (what the Lean proofs already established):
- `proofs/lean/Semantos/Linearity.lean` — K1 proved at kernel level
- `proofs/lean/Semantos/Theorems/` — all theorem files (understand what's already proved)

**Read fourth**:
- `docs/BRANCHING-AND-CI-POLICY.md`

**After reading**: Know the exact FSM transition table. Know the exact domain flag values. Know what K1–K5, K7 already cover (kernel level, Lean-proved) vs. what this phase covers (protocol level, TLA+ model-checked for bounded state spaces). Understand that TLA+ properties provide the kernel's contribution to regulatory requirement satisfaction, not direct proofs of compliance.

---

## PART 2: EXECUTE PHASE 11.5

Follow deliverables in `docs/prd/PHASE-11.5-TLA-PROTOCOL.md` in order.

### D11.5.0: TLA+ scaffold + base types

1. Create `proofs/tla/` directory.
2. Write `SemanticTypes.tla` with CONSTANTS, VARIABLES, type definitions.
3. Write model config files (MC_*.cfg) for each spec with initial bounds.
4. Write `README.md` with instructions for running TLC.

**Commit**: `phase-11.5/D11.5.0: TLA+ scaffold + base types`

### D11.5.1: Evidence chain integrity

1. Read `src/types/semantic-objects.ts` again. Note prevStateHash field.
2. Write `EvidenceChain.tla` — append-only chain with hash linking.
3. Include adversary TamperEvidence action.
4. Write MC_EvidenceChain.cfg.
5. Run TLC. ChainIntegrity and TemporalOrdering must hold.

**Commit**: `phase-11.5/D11.5.1: evidence chain integrity + temporal ordering`

### D11.5.2: Replay prevention

1. Read `src/compiler/validator.ts` — validateConsumption logic.
2. Write `ReplayPrevention.tla` — concurrent actors consuming LINEAR objects.
3. Include ReplayAttack adversary action.
4. Run TLC. SingleConsumption and ReplayAlwaysFails must hold.

**Commit**: `phase-11.5/D11.5.2: replay prevention + concurrent consumption model`

### D11.5.3: Cert revocation

1. Read `src/types/semantic-objects.ts` — RelevantObject, RevocationProof.
2. Write `CertRevocation.tla` — revocation as state transition.
3. Run TLC. RevocationImmediate must hold.

**Commit**: `phase-11.5/D11.5.3: cert revocation immediacy model`

### D11.5.4: Metering FSM

1. Read `src/metering/channel-fsm.ts` cover to cover. Copy the exact transition table.
2. Write `MeteringFSM.tla` — all 8 states, all transitions.
3. Run TLC. ValidTransitionsOnly and TickOnlyInActive must hold. EventualSettlement under fairness.

**Commit**: `phase-11.5/D11.5.4: metering FSM correctness model`

### D11.5.5: Zone boundaries

1. Read `src/types/domain-flags.ts` — exact flag values.
2. Write `ZoneBoundary.tla` — multi-zone with domain flag checking.
3. Run TLC. ZoneEnforcement must hold.

**Commit**: `phase-11.5/D11.5.5: zone boundary enforcement model`

### D11.5.6: Partition resilience

1. Write `PartitionResilience.tla` — network partition, local ops, reconciliation.
2. This is the most complex spec. Include:
   - Partition creation
   - Local evidence chain accumulation
   - Healing + reconciliation
   - Conflict detection for split-brain LINEAR consumption
3. Run TLC. LocalContinuity and ReconciliationComplete must hold.

**Commit**: `phase-11.5/D11.5.6: partition resilience model`

### D11.5.7: Gate test + CI

1. Write `packages/__tests__/phase11.5-gate.test.ts`
2. Update `.github/workflows/gate.yml`
3. Run gate test.

**Commit**: `phase-11.5/D11.5.7: gate test + CI for TLA+ model checking`

---

## PART 3: ERRATA SPRINT

### 3.1 Files to audit

Every `.tla` and `.cfg` file in `proofs/tla/`.

### 3.2 Scan checklist

1. **TLC completes for every spec?** Each must finish in < 30 minutes.
2. **Adversary actions present?** Each security-relevant spec must include at least one adversary action.
3. **FSM transition table matches code?** Line-by-line comparison of `MeteringFSM.tla` vs `channel-fsm.ts`.
4. **No vacuous truth?** For each property, verify the precondition is satisfied in at least one reachable state.
5. **Hash abstraction documented?** TLA+ can't compute SHA-256. Is the injective function abstraction documented?
6. **Domain flag values match?** Compare TLA+ constants against `domain-flags.ts`.
7. **Partition model handles LINEAR correctly?** Does it prevent split-brain consumption?
8. **Model bounds sufficient?** Are bounds large enough to exercise all interesting interleavings?

### 3.3 Write errata doc

Create `docs/prd/PHASE-11.5-ERRATA.md`.

### 3.4 Fix and commit

```bash
git add <fixed files> docs/prd/PHASE-11.5-ERRATA.md
git commit -m "Phase 11.5 errata: audit doc + fix N issues

<list fixes>

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## ANTI-BULLSHIT RULES

1. **TLC must terminate and report "No error found."** A model that times out is not a proof.
2. **Include adversaries.** Honest-only models prove nothing about security.
3. **No vacuous truth.** If a property's precondition is never true, the property is meaningless.
4. **Match the code.** FSM transitions, flag values, linearity types — all from the source, not from memory.
5. **Document abstractions.** Hash-as-injection, time-as-counter, etc.
6. **Commit after each gate.**

---

## Completion Check

```
<hash> Phase 11.5 errata: audit doc + fix N issues
<hash> phase-11.5/D11.5.7: gate test + CI for TLA+ model checking
<hash> phase-11.5/D11.5.6: partition resilience model
<hash> phase-11.5/D11.5.5: zone boundary enforcement model
<hash> phase-11.5/D11.5.4: metering FSM correctness model
<hash> phase-11.5/D11.5.3: cert revocation immediacy model
<hash> phase-11.5/D11.5.2: replay prevention + concurrent consumption model
<hash> phase-11.5/D11.5.1: evidence chain integrity + temporal ordering
<hash> phase-11.5/D11.5.0: TLA+ scaffold + base types
```

All TLC runs pass. All adversary actions modeled. Transition tables match source.
