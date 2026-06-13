---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-38-VOICE-TO-EXECUTION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.678834+00:00
---

# Phase 38 — Voice-to-Execution (V2E) Sprint

**Date**: 2026-04-16
**Epic**: Turn the Helm surface into a hat-scoped, audited execution substrate — spoken natural-language commands become signed, capability-gated shell actions with an append-only evidence trail.

---

## What & Why

Today: a user types `kill 3000` into a dumb terminal. No hat binding, no audit, no capability check, no receipt.

After Phase 38: a user says "kill the process on port 9000". Helm captures the utterance, an LLM extracts a structured `ShellCommand`, the user approves a draft `HostCommand` object, the active hat's BRC-100 cert signs the request cell, a whitelisted host handler executes, and the result is appended to an immutable patch chain. The receipt is queryable by hat, by handler, and by time.

This is not a new opcode. OP_CALL_HOST stays narrow (predicate oracle for cells). V2E lives at the **shell layer**, where side effects belong.

### Acceptance test (single sentence)

> From Helm Talk, the user utters "kill the process on port 9000". Within 3s, a Do/Transact receipt appears showing `HostCommand { command: "process.killByPort", args: {port: 9000}, hatId: <active>, exitCode: 0, stdout: <pid>, signedBy: <certId> }`. The patch chain verifies. A second attempt without `HOST_EXEC` capability returns an error object, no side effect executed, no receipt published.

### Non-goals

- **No new opcodes.** OP_CALL_HOST stays as-is. No OP_EMIT_COMMAND, no OP_HOST_EXEC.
- **No remote execution.** A hat cannot authorize a `HostCommand` on another machine. That's a future federation story.
- **No arbitrary shell.** The handler registry is a tight allowlist. Zero-arg eval of user strings is a non-starter.
- **No voice training.** Use the browser's Web Speech API or Whisper.cpp via wasm. No custom models.
- **No in-VM side effects.** K4 (failure-atomicity) and K5 (termination) stay provable.

---

## Phase Breakdown

| Sub-phase | Deliverable | Hot path? | Blocks |
|---|---|---|---|
| **38A** | `HostCommand` type, `HOST_EXEC` capability, `host-ops` extension config | **Yes** (foundation) | 38B, 38C, 38F |
| **38B** | Handler registry + `process.killByPort` reference handler | **Yes** | 38C |
| **38C** | `host.exec` shell verb — parser, router, capability gate, publish-then-execute semantics | **Yes** | 38G |
| **38D** | Audit verification CLI (`host audit <hostCommandId>`) | No (parallel after 38C) | — |
| **38E** | Voice capture adapter (Web Speech API → text) | No (parallel, pure UI) | 38G |
| **38F** | NL → `ShellCommand` extractor (LLM flow) | No (parallel after 38A) | 38G |
| **38G** | Helm UI wiring: Talk input → approval card → Do/Transact receipt | **Yes** (final integration) | — |

### Hot path (sequential, load-bearing)

```
38A ──► 38B ──► 38C ──► 38G ──► DONE
```

Each arrow is a merge to the phase branch. You cannot start `host.exec` (38C) without the type (38A) and a handler (38B) to dispatch to. You cannot wire UI (38G) without a working verb (38C) and the extractor (38F).

### Parallel tracks (can start as soon as their predecessor lands on the phase branch)

```
                                                ┌──► 38D (audit CLI)
                                                │
38A ──► 38B ──► 38C ───────────────────────────┤
                                                │
       ┌──► 38E (voice capture)  ───────────────┤
       │                                        │
38A ──►│                                        ├──► 38G
       └──► 38F (NL extractor)   ───────────────┘
```

- **38D** starts once 38C is merged to the phase branch — it only needs a published `HostCommand` to verify against.
- **38E** can start day one — it's a self-contained browser adapter.
- **38F** starts once 38A is merged — it only needs the schema to target.

### Session ownership (who does what, in parallel)

Run up to three sessions concurrently once 38A + 38B + 38C are on the phase branch:

- **Session 1** (hot path): 38A → 38B → 38C → 38G
- **Session 2** (UI track): 38E → (wait for 38F) → 38G
- **Session 3** (NL track): 38F → 38D

Single-session execution is also fine — just walk the hot path, then 38D/E/F in any order, then 38G.

---

## Branch Hygiene (No Worktrees)

### Rule: one phase branch, sub-branches only when risky

```
main
 └── phase-38-voice-to-execution          ← phase branch, cut from main
      ├── phase-38-voice-to-execution/D38A  (optional sub-branch, merge back before next)
      ├── phase-38-voice-to-execution/D38B
      ├── …
      └── phase-38-voice-to-execution/D38G
```

- **No worktrees.** All work happens in the single working tree of `semantos-core`. Switch with `git checkout`.
- **Sub-branches are optional.** If a deliverable is small and isolated (e.g., 38E voice adapter), commit directly on the phase branch. If it's risky or parallel with another deliverable, cut a sub-branch and merge back with `--no-ff` (to preserve the parallel-track fact in history).
- **Sub-branch merges use `--no-ff`.** Phase-to-main uses fast-forward (per `docs/BRANCHING-AND-CI-POLICY.md`).
- **Never commit to main.** The phase merges once, at the end, after `bun test packages/__tests__/` passes and the acceptance test runs green.

### Creating the phase branch

```bash
git checkout main
git pull --ff-only origin main
git checkout -b phase-38-voice-to-execution
```

### Starting a sub-branch (e.g., parallel track)

```bash
git checkout phase-38-voice-to-execution
git checkout -b phase-38-voice-to-execution/D38E
# …work, commit…
git checkout phase-38-voice-to-execution
git merge --no-ff phase-38-voice-to-execution/D38E
git branch -d phase-38-voice-to-execution/D38E
```

### Commit message format

```
phase-38/D38A: add HostCommand type and HOST_EXEC capability

- ObjectTypeDefinition in host-ops extension config
- Capability ID 17 reserved for HOST_EXEC
- Round-trip validation test in phase38-gate.test.ts
```

### Merge to main (only when every sub-phase is done)

```bash
git checkout phase-38-voice-to-execution
bun run check
bun test packages/__tests__/
# acceptance test runs clean

git checkout main
git pull --ff-only origin main
git merge --ff-only phase-38-voice-to-execution
git tag -a v38.0 -m "Phase 38: voice-to-execution"
git push origin main --tags
git branch -d phase-38-voice-to-execution
```

---

## Gate Tests (Phase 38)

Create `packages/__tests__/phase38-gate.test.ts`. Must verify:

1. **Schema**: `HostCommand` validates via `validateExtensionConfig()`; `HOST_EXEC` capability ID is unique and registered.
2. **Handler registry**: `process.killByPort` is registered; unknown handler returns a structured error object (not exception).
3. **Capability gate**: `host.exec` without `HOST_EXEC` returns `CAPABILITY_CHECK_FAILED` error object; does NOT invoke the handler.
4. **Signing**: every published `HostCommand` has a non-empty `hatSig` field and `hatId` matches the active facet at publish time.
5. **Audit**: `host audit <id>` reconstructs the full patch chain and verifies `hatSig` over the request cell.
6. **Linearity**: the publish transition goes LINEAR; subsequent patches are append-only.
7. **NL extractor**: given the fixture utterance "kill the process on port 9000", the extractor returns `{verb: "host.exec", args: {handler: "process.killByPort", port: 9000}}`.
8. **End-to-end**: the acceptance test runs green in CI (with a mock handler that doesn't actually kill processes).

All gates cumulative per `docs/BRANCHING-AND-CI-POLICY.md`. Phase 37's gates must still pass.

---

## Risks & Escalations

- **R1: Handler spec creep.** Every PR will want to add a handler. **Mitigation**: the PR body must include a threat model. One handler in 38B (`process.killByPort`). Additional handlers land in Phase 38.x errata branches, not the main phase.
- **R2: Voice latency.** Web Speech API is spotty on non-Chromium. **Mitigation**: 38E ships Web Speech first, Whisper.cpp wasm as a fallback in a 38.x follow-up.
- **R3: LLM hallucinates a handler name.** **Mitigation**: 38F validates the extracted `handler` field against the registry at extract time, returns a structured error if unknown, and never dispatches silently.
- **R4: Approval fatigue.** If every command requires a hat-pin, users will thumb-print everything without reading. **Mitigation**: 38G shows the full command + args + handler in the approval card, pre-expanded. No collapsed defaults.

---

## Execution Prompts

Each sub-phase has a bulletproof prompt in `docs/prd/PHASE-38X-PROMPT.md`:

- `docs/prd/PHASE-38A-PROMPT.md` — HostCommand schema + capability
- `docs/prd/PHASE-38B-PROMPT.md` — Handler registry + reference handler
- `docs/prd/PHASE-38C-PROMPT.md` — `host.exec` shell verb
- `docs/prd/PHASE-38D-PROMPT.md` — Audit verification CLI
- `docs/prd/PHASE-38E-PROMPT.md` — Voice capture adapter
- `docs/prd/PHASE-38F-PROMPT.md` — NL extractor
- `docs/prd/PHASE-38G-PROMPT.md` — Helm UI flow

Paste each prompt into a fresh session. Each prompt is self-contained and lists the files to read first.

---

## Post-Merge

Mandatory errata sprint per `docs/BRANCHING-AND-CI-POLICY.md`:

1. Fresh session, adversarial scan of all Phase 38 code.
2. Output: `docs/prd/PHASE-38-ERRATA.md`.
3. Fix sprint on `errata/phase-38`, merge to main, tag `v38.1`.
