---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-9.5-FULL-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.654910+00:00
---

# Phase 9.5 — Full Execution Prompt (Git Hygiene + Build + Errata)

> Paste this into a fresh Claude Code session. It handles git cleanup, Phase 9.5 execution, and errata — end to end.

---

## PART 0: GIT HYGIENE

Before writing any code, get the repo into a clean, known state.

### 0.1 Assess the mess

```bash
cd <path-to-semantos-core>
git status -u
git log --oneline -10
git branch -a
git stash list
```

Read the output. Understand what branch you're on, what's uncommitted, what's stale.

### 0.2 Commit or discard uncommitted work

If there are uncommitted changes:
- Read each changed file. Decide: is this Phase 9 work that should be committed, or stale junk?
- Commit real work in logical groups (stage files explicitly, never `git add -A`).
- Discard anything that's clearly stale or broken: `git checkout -- <file>`.

If there are untracked files in `.claude/worktrees/` — these are orphaned worktree artifacts. Ignore them (do NOT commit them).

### 0.3 Get to the right branch point

Phase 9 and its errata should already be committed. Verify:

```bash
git log --oneline --all | grep -i "phase.9"
```

You should see commits for Phase 9 implementation and Phase 9 errata. If they're on a branch that isn't main, that's fine — branch from wherever the latest Phase 9 errata commit lives.

### 0.4 Create the Phase 9.5 branch

```bash
git checkout -b phase-9.5-publication-governance
```

### 0.5 Verify prerequisites exist

These files MUST exist and be real implementations (not stubs) before you proceed. If any are missing, STOP.

```bash
ls packages/loom/src/services/LoomStore.ts \
   packages/loom/src/services/IdentityStore.ts \
   packages/loom/src/services/ConfigStore.ts \
   packages/loom/src/services/IntentClassifier.ts \
   packages/loom/src/services/FlowRegistry.ts \
   packages/loom/src/services/FlowRunner.ts \
   packages/loom/src/services/index.ts
```

All 7 must exist. If any are missing, Phase 9 is incomplete — do not proceed.

### 0.6 Set git identity if needed

```bash
git config user.email 2>/dev/null || git config user.email "dev@semantos.dev"
git config user.name 2>/dev/null || git config user.name "Semantos Dev"
```

**GATE**: Clean branch, clean working tree, Phase 9 services verified. Proceed.

---

## PART 1: READ BEFORE YOU WRITE

Now read the Phase 9.5 prompt and all prerequisite files it references:

```bash
cat docs/prd/PHASE-9.5-PROMPT.md
```

Follow EVERY "Read first / second / third / etc." instruction in that file. Read all listed files before writing any code. The prompt specifies:

1. The PRD: `docs/prd/SHOMEE-EXTRACTION-AUDIT-AND-ROADMAP.md`
2. All Phase 9 service files in `packages/loom/src/services/`
3. Existing loom types, config, reducer, factory, ConversationPanel
4. All 4 extension configs in `configs/extensions/`
5. Kernel types in `src/cell-engine/` and `packages/protocol-types/`
6. Branching policy: `docs/BRANCHING-AND-CI-POLICY.md`

**Do not skip any of these.** If you produce stubs or code that conflicts with existing implementations, it's because you didn't read.

---

## PART 2: EXECUTE PHASE 9.5

Follow the 4 steps defined in `docs/prd/PHASE-9.5-PROMPT.md` exactly:

- **Step 1 (D9.5.1)**: Visibility field on ObjectTypeDefinition + LoomObject + reducer + factory + extension configs + LoomStore.transitionVisibility()
- **Step 2 (D9.5.2)**: Publish and revoke conversation flows in trades-services.json + FlowAction.linearityTransition field + ConversationPanel handling
- **Step 3 (D9.5.3)**: Governance types (Dispute, Ballot, Stake, Resolution) in core.json with computed typeHash values
- **Step 4 (D9.5.4)**: Governance flows (file-dispute, cast-vote, stake) in core.json

**Commit after each step passes its gate test.** Use this format:

```
phase-9.5/D9.5.N: <what changed>
```

### Rules from Phase 9 that still apply:

1. **No stubs.** Every function does real work.
2. **No mocks.** Real LLM endpoint or real degradation.
3. **Renderer agnosticism.** Business logic in `src/services/`, not React components.
4. **Immutable state.** Never `this.state.field = value` — spread and replace.
5. **Real facet capabilities.** Never hardcode `[1..10]`.

### Rules new to Phase 9.5:

6. **Governance is not a service.** No GovernanceEngine, DisputeService, BallotCoordinator. Governance types are ordinary semantic objects with ordinary linearity transitions driven by ordinary conversation flows in the extension config.
7. **Visibility is a field, not a system.** No PublicationService, VisibilityManager, DraftPubService. Visibility is a field on ObjectTypeDefinition and a value on LoomObject.

If you find yourself creating a class with "governance" or "publication" in its name that isn't a type definition or flow, STOP. You are recreating Shomee's 93-package mistake.

---

## PART 3: ERRATA SPRINT

Immediately after Part 2, re-read all delivered code adversarially.

### 3.1 Files to audit

Every file you created or modified in Part 2, plus:
- All extension config JSONs (did typeHash get stamped? do flows validate?)
- `extensionConfig.ts` (are new interfaces validated?)
- `workbenchReducer.ts` (is the new action handled?)
- `objectFactory.ts` (does visibility default correctly?)
- `LoomStore.ts` (does transitionVisibility validate all edge cases?)
- `ConversationPanel.tsx` (does it handle ALL FlowAction types including the new ones?)

### 3.2 Scan checklist

1. Any ObjectTypeDefinition with `typeHash: ""`?
2. Any visibility transition that skips validation?
3. Any governance type that isn't just a plain entry in core.json?
4. Any new service/engine/manager class? (There should be ZERO new classes)
5. Any FlowAction type not handled in ConversationPanel's completion handler?
6. Any `as any` casts?
7. Any React imports in `src/services/`?
8. Any hardcoded capabilities?
9. Can publish → revoke → cannot re-publish? (evidence preserved)
10. Can a LINEAR object be published? (Must be rejected)
11. Does Stake enforce LINEAR consume-once?

### 3.3 Write errata doc

Create `docs/prd/PHASE-9.5-ERRATA.md` in the same format as `docs/prd/PHASE-9-ERRATA.md`.

### 3.4 Fix MUST FIX items and commit

```bash
git add <fixed files> docs/prd/PHASE-9.5-ERRATA.md
git commit -m "Phase 9.5 errata: audit doc + fix N issues

<list each fix>

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## COMPLETION CHECK

When done, `git log --oneline` from the branch point should show approximately:

```
<hash> Phase 9.5 errata: audit doc + fix N issues
<hash> phase-9.5/D9.5.4: governance conversation flows
<hash> phase-9.5/D9.5.3: governance types in core.json
<hash> phase-9.5/D9.5.2: publish and revoke flows
<hash> phase-9.5/D9.5.1: visibility states + reducer + config
```

Each commit compiles. The errata doc is thorough. No new service classes exist.
