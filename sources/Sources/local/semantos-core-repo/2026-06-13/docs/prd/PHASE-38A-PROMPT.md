---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-38A-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.655451+00:00
---

# Phase 38A Execution Prompt — HostCommand Schema & HOST_EXEC Capability

> Paste this prompt into a fresh session. Foundation sub-phase for Phase 38 (Voice-to-Execution).

## Context

Phase 38 turns Helm into a hat-scoped audited execution substrate. Before any of that works, we need a first-class `HostCommand` object type and a capability (`HOST_EXEC`) that gates its creation.

This sub-phase is **the hot-path foundation.** 38B, 38C, and 38F all block on its schema.

The `HostCommand` type models a request to run a whitelisted, side-effecting host handler. It carries: which handler, the args, who authorized it (hat + cert), when it was requested, and — after execution — the outcome.

Read `docs/prd/PHASE-38-VOICE-TO-EXECUTION.md` for the full epic context before starting.

---

## CRITICAL: READ THESE FILES FIRST

- `docs/prd/PHASE-38-VOICE-TO-EXECUTION.md` — epic, acceptance test, non-goals
- `docs/BRANCHING-AND-CI-POLICY.md` — branch & commit conventions
- `packages/protocol-types/src/extension-config-types.ts` — `ObjectTypeDefinition`, capability, visibility
- `configs/extensions/core.json` — reference for capability IDs already in use
- `configs/extensions/trades-services.json` — reference for `objectTypes` + `coordinationModes` wiring
- `packages/loom/src/services/LoomStore.ts` — how types are registered; where linearity is enforced
- `packages/__tests__/phase37-gate.test.ts` (or latest) — gate test patterns, cumulative structure

---

## ANTI-BULLSHIT RULES

1. **No placeholder typeHash.** The `HostCommand` typeHash must be a real sha256 of the canonical type definition, not a handwritten string. Follow the computation used by existing types.
2. **LINEAR, not AFFINE.** `HostCommand` is LINEAR — once published, its outcome is evidence. A request object cannot be consumed.
3. **Capability ID is NOT recycled.** Scan all existing extension configs for used IDs. `HOST_EXEC` gets the next free ID. Document it in the capability block.
4. **No remote execution.** The schema must NOT carry a `targetNodeId` or `remoteHatId` field. Local execution only for Phase 38.
5. **Visibility: draft → published, no revoked.** A published HostCommand is evidence — revoking it would destroy audit. `revokePreservesEvidence` is moot; there is no revoke.
6. **host-ops is a new extension, not a core extension.** Create `configs/extensions/host-ops.json`. Do not modify `configs/extensions/core.json` beyond adding `HOST_EXEC` to its capability ledger if that's where capabilities are registered globally (read the file first to confirm).

---

## PART 0: GIT HYGIENE

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -5
git checkout main
git pull --ff-only origin main
git checkout -b phase-38-voice-to-execution
```

If a prior Phase 38 branch exists, rebase or abort — don't stack on stale state.

---

## Step 1: Define HostCommand Type (D38A.1)

### 1.1 Create `configs/extensions/host-ops.json`

Include a single `objectTypes` entry for `HostCommand`:

- `name: "HostCommand"`
- `linearity: "LINEAR"`
- `archetype: "action"`
- `conversationEnabled: false` (host commands aren't chat)
- `visibility.states: ["draft", "published"]`, `defaultState: "draft"`
- `visibility.publishTransition.requiredCapabilities: [<HOST_EXEC id>]`
- `accessPolicy.default: "facet-scoped"`, `overridable: false`
- `defaultCapabilities: [<HOST_EXEC id>]`

Fields:

| field | type | required | notes |
|---|---|---|---|
| `handler` | string | yes | dotted handler id, e.g. `process.killByPort` |
| `args` | string | yes | canonical JSON of args |
| `hatId` | string | yes | set at publish time |
| `hatCertId` | string | yes | BRC-100 cert id |
| `hatSig` | string | yes | signature over `sha256(handler || args || hatId || requestedAt)` |
| `requestedAt` | string | yes | ISO8601 |
| `startedAt` | string | no | filled by executor |
| `finishedAt` | string | no | filled by executor |
| `exitCode` | number | no | handler return |
| `stdout` | string | no | capped length, see 38B |
| `stderr` | string | no | capped length |
| `resultSig` | string | no | handler-side signature over outcome, if handler supports |

Compute `typeHash` the same way existing types do (see trades-services.json for reference pattern, or run the type-hash tool if one exists).

### 1.2 Add HOST_EXEC capability

In `host-ops.json`, declare:

```json
"capabilities": [
  { "id": <next-free-id>, "name": "HOST_EXEC", "scope": "Execute whitelisted host handlers on behalf of the active hat" }
]
```

Scan `configs/extensions/*.json` for the highest capability ID already used. Use `max + 1`.

### 1.3 Add coordinationModes

Wire `HostCommand` into the 1-3-5 pyramid:

```json
"coordinationModes": [
  { "mode": "do", "context": "transact", "objectTypes": ["HostCommand"], "label": "Host Commands" },
  { "mode": "find", "context": "truth", "objectTypes": ["HostCommand"], "label": "Command Audit" }
]
```

### 1.4 Commit

```bash
git add configs/extensions/host-ops.json
git commit -m "phase-38/D38A.1: HostCommand type and HOST_EXEC capability in host-ops extension"
```

---

## Step 2: Export Types From protocol-types (D38A.2)

### 2.1 If `HOST_EXEC` needs a TS constant

Check `packages/protocol-types/src/index.ts` for how existing capability IDs are exposed to code. If there's a `CAPABILITY_IDS` constant or similar, add `HOST_EXEC` there. If capabilities are only read from config, skip this step — do NOT speculate.

### 2.2 Commit (if 2.1 was needed)

```bash
git commit -m "phase-38/D38A.2: export HOST_EXEC capability constant"
```

---

## Step 3: Gate Tests (D38A.3)

### 3.1 Create `packages/__tests__/phase38-gate.test.ts`

Include these tests:

1. `host-ops.json` validates via `validateExtensionConfig()`.
2. `HostCommand` typeHash is non-empty and matches a re-computation.
3. `HOST_EXEC` capability ID does not collide with any capability in any other extension config.
4. `HostCommand.linearity === "LINEAR"`.
5. `HostCommand.visibility.states` contains exactly `["draft", "published"]`.
6. `defaultCapabilities` on `HostCommand` includes the `HOST_EXEC` id.
7. Required fields include `handler`, `args`, `hatId`, `hatCertId`, `hatSig`, `requestedAt`.

### 3.2 Run

```bash
bun test packages/__tests__/phase38-gate.test.ts
bun test packages/__tests__/
```

All must pass. No skipped tests.

### 3.3 Commit

```bash
git add packages/__tests__/phase38-gate.test.ts
git commit -m "phase-38/D38A.3: gate tests for HostCommand schema and HOST_EXEC capability"
```

---

## Exit Criteria

- [ ] `configs/extensions/host-ops.json` exists and validates.
- [ ] `HOST_EXEC` capability has a globally unique id.
- [ ] `HostCommand` has every required field; typeHash is real.
- [ ] `packages/__tests__/phase38-gate.test.ts` passes.
- [ ] All prior phase gates still pass (`bun test packages/__tests__/`).
- [ ] Branch: `phase-38-voice-to-execution`, 1–3 commits.

Do NOT merge to main. Hand off to 38B.
