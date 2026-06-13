---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-9.5-ERRATA.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.717935+00:00
---

# Phase 9.5 Errata — Publication + Visibility + Governance Types

Audit of the Phase 9.5 implementation: visibility field on ObjectTypeDefinition + LoomObject, publish/revoke flows in trades-services, governance types and flows in core.json, ConversationPanel transition handler, gate tests.

**Audited files**: `config/extensionConfig.ts`, `types/workbench.ts`, `state/objectFactory.ts`, `state/workbenchReducer.ts`, `services/LoomStore.ts`, `canvas/ConversationPanel.tsx`, `configs/extensions/core.json`, `configs/extensions/trades-services.json`, `configs/extensions/blockchain-risk.json`, `packages/__tests__/phase9.5-gate.test.ts`

---

## INC-1: Dispute visibility has `revokePreservesEvidence: true` but no "revoked" state

**Severity**: INCONSISTENCY
**File**: `configs/extensions/core.json`, Dispute objectType
**Details**: Dispute's visibility config is `{ states: ["draft", "published"], revokePreservesEvidence: true }`. Since "revoked" is not in the `states` array, `transitionVisibility()` will reject any attempt to revoke a Dispute. The `revokePreservesEvidence` flag is therefore dead config — it's set to true but can never apply.

This is arguably correct: disputes shouldn't be retractable once filed. But the presence of `revokePreservesEvidence: true` on a type that can't be revoked is misleading.

**Fix**: Set `revokePreservesEvidence: false` to accurately reflect that revocation is not supported for disputes. Alternatively, if disputes should be retractable, add "revoked" to the states array.

**Status**: FIXED (set to false)

---

## INC-2: cast-vote flow collects `voteDirection` but patches `votesFor`/`votesAgainst`

**Severity**: INCONSISTENCY (design limitation)
**File**: `configs/extensions/core.json`, cast-vote flow
**Details**: The `cast-vote` flow collects `{ voteDirection: "string" }` from the user. Its `onComplete` is `{ type: "patch", patchFields: ["votesFor", "votesAgainst"] }`. The patch handler in ConversationPanel loops through `patchFields` and checks if each field name exists in `collectedData`. Since `collectedData` has `voteDirection` (not `votesFor` or `votesAgainst`), the patch delta will be empty.

The fundamental issue: the current patch action model can set fields to collected values but cannot perform computed mutations (like incrementing `votesFor` based on `voteDirection === "for"`). This would require either:
- A computed-patch model in FlowAction (adds complexity)
- Custom vote-counting logic in the transition handler (violates "no governance services")
- A post-flow script that interprets `voteDirection` (cleanest, but scripting isn't implemented)

**Fix**: Not fixable within Phase 9.5's scope without introducing computed mutations. The flow definition is structurally correct — it will create the evidence chain patch with `voteDirection` data, which is the important part. Actual vote tallying is Phase 10+ work (scripted post-flow actions).

**Status**: NOTED (design limitation, deferred)

---

## INC-3: No success confirmation message for transition flow completions

**Severity**: INCONSISTENCY (minor)
**File**: `canvas/ConversationPanel.tsx`, executeFlowCompletion transition handler
**Details**: When a `create` action completes, a system message is posted: "Created X from flow Y." When a `transition` action completes (publish/revoke), only a `state_transition` patch is recorded — no user-visible conversation message confirms the operation succeeded. The state_transition patch appears in the evidence chain but not in the conversation view (it's filtered by `p.kind === 'conversation'`).

**Fix**: Add a completion message patch after successful visibility transitions.

**Status**: FIXED

---

## INC-4: `serializeCellHeader` imported but unused in objectFactory.ts

**Severity**: INCONSISTENCY (pre-existing, minor)
**File**: `state/objectFactory.ts`, line 1
**Details**: `import { serializeCellHeader } from '@semantos/protocol-types'` is present but `serializeCellHeader` is never called. This is a pre-existing issue from Phase 8, not introduced in Phase 9.5.

**Fix**: Remove the unused import.

**Status**: FIXED

---

## Scan Checklist Results

| # | Check | Result |
|---|-------|--------|
| 1 | Any ObjectTypeDefinition with `typeHash: ""`? | PASS — all 4 governance types have computed SHA256 hashes |
| 2 | Any visibility transition that skips validation? | PASS — all transitions go through LoomStore.transitionVisibility() |
| 3 | Any governance type that isn't just a plain entry in core.json? | PASS — no GovernanceEngine or similar classes |
| 4 | Any new service/engine/manager class? | PASS — zero new classes created |
| 5 | Any FlowAction type not handled in ConversationPanel? | PASS — create, patch, transition, navigate all handled |
| 6 | Any `as any` casts? | PASS — none in modified files |
| 7 | Any React imports in `src/services/`? | PASS — zero React imports |
| 8 | Any hardcoded capabilities? | PASS — no new hardcoded capability arrays |
| 9 | publish → revoke → cannot re-publish? | PASS — revoked→published throws error |
| 10 | LINEAR object cannot be published? | PASS — linearity===1 check throws |
| 11 | Stake enforces LINEAR consume-once? | PASS (at type level) — linearity=LINEAR, cell engine enforces |

---

## Summary

| ID | Category | Severity | Status |
|----|----------|----------|--------|
| INC-1 | Dead revokePreservesEvidence flag on Dispute | Low | FIXED |
| INC-2 | cast-vote patch model limitation | Medium | NOTED (design limitation) |
| INC-3 | No success message for transition completions | Low | FIXED |
| INC-4 | Unused serializeCellHeader import (pre-existing) | Low | FIXED |
