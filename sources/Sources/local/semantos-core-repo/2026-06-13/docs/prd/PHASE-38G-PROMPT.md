---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-38G-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.689316+00:00
---

# Phase 38G Execution Prompt — Helm UI Flow (Talk → Approval → Receipt)

> Paste into a fresh session. **Hot-path final integration.** Requires 38C, 38E, 38F on `phase-38-voice-to-execution`.

## Context

This is where the sprint becomes real. The user speaks. The words appear. An approval card renders the extracted command — handler, args, hat, capability — pre-expanded, one tap away. On approve, `host.exec` fires through `useShellDispatch`. When the result comes back, it slides into Do/Transact as a receipt card.

Everything before this phase built pieces. 38G wires them into a living loop.

---

## CRITICAL: READ THESE FILES FIRST

- `docs/prd/PHASE-38-VOICE-TO-EXECUTION.md` — epic and acceptance test
- `docs/prd/PHASE-38C-PROMPT.md` — the `host.exec` verb you dispatch to
- `docs/prd/PHASE-38E-PROMPT.md` — the `VoiceInput` component you mount
- `docs/prd/PHASE-38F-PROMPT.md` — `extractShellCommand()` you call
- `packages/loom/src/helm/hooks/useShellDispatch.ts` — the dispatch hook from the 1-3-5 pyramid PR
- `packages/loom/src/helm/TalkMode.tsx` — where VoiceInput already mounts (from 38E)
- `packages/loom/src/helm/DoMode.tsx` — Transact context where receipts render
- `packages/loom/src/services/AttentionEngine.ts` — how objects become AttentionItems and get routed to a context

---

## ANTI-BULLSHIT RULES

1. **No auto-dispatch.** The approval card is mandatory. Even with `confidence: 1.0`, the user taps Approve before anything signs. No "high-confidence auto-mode" this phase.
2. **Expanded by default.** The card shows: handler id, every arg, target hat, capability it will exercise, timeout. No collapsed "details" drawer. Approval fatigue is a stated risk (R4 in the epic) — beat it by being honest.
3. **Dispatch is a shell command, not a LoomStore call.** The approval handler fires through `useShellDispatch('host.exec', …)`, which goes through `route()`, which goes through the capability gate. Do not shortcut to `ctx.store.publishObject`.
4. **Receipt is not a new object type.** Receipts are just `HostCommand` objects in Do/Transact, filtered by `visibility === 'published'` and sorted by `requestedAt`. The `AttentionEngine` already routes them if 38A declared the `coordinationModes` entry.
5. **Deny path is visible.** If the capability check fails or the extractor returns `UNKNOWN_HANDLER`, the user sees the actual error code + message. Not "something went wrong". Not a toast that vanishes.
6. **No state leaks between utterances.** After Approve (or Cancel), the card state resets — no lingering transcript, no stale extracted command. The next utterance starts clean.

---

## PART 0: GIT HYGIENE

```bash
git checkout phase-38-voice-to-execution
git pull --ff-only
```

Confirm: `git log --oneline -20` shows commits from 38A–38F before starting. If any hot-path phase (38C) isn't here, stop.

---

## Step 1: `CommandApprovalCard` (D38G.1)

### 1.1 Create `packages/loom/src/helm/CommandApprovalCard.tsx`

Props:

```ts
interface CommandApprovalCardProps {
  extracted: ExtractedCommand;       // from 38F
  activeHat: { id: string; label: string };
  onApprove: () => void;             // fires host.exec
  onCancel: () => void;
  onEdit?: (edited: ExtractedCommand) => void;  // optional inline args editing
}
```

Render, **expanded by default**:

```
┌─────────────────────────────────────────────┐
│ Approve host command                        │
│                                             │
│ Handler:   process.killByPort               │
│ Args:      port=9000, signal=SIGTERM        │
│ Hat:       alice@dev (active)               │
│ Capability: HOST_EXEC                       │
│ Timeout:   10s                              │
│ Confidence: 94%                             │
│                                             │
│ Rationale: "User asked to free port 9000"   │
│                                             │
│      [ Cancel ]          [ Approve ]        │
└─────────────────────────────────────────────┘
```

If `confidence < 0.6`, show a subtle warning band above the Approve button. Do not disable it — the user is the authority.

### 1.2 Commit

```bash
git add packages/loom/src/helm/CommandApprovalCard.tsx
git commit -m "phase-38/D38G.1: CommandApprovalCard — expanded-by-default, hat + capability visible"
```

---

## Step 2: Wire VoiceInput → Extractor → ApprovalCard (D38G.2)

### 2.1 Update `packages/loom/src/helm/TalkMode.tsx`

Replace the stub `onUtterance` (from 38E) with real orchestration. Sketch:

```tsx
const [pending, setPending] = useState<ExtractedCommand | null>(null);
const [extractError, setExtractError] = useState<ExtractError | null>(null);
const dispatch = useShellDispatch();
const { identity } = useShellContext();
const activeHat = identity.getActiveFacet();

async function handleUtterance(text: string) {
  const result = await extractShellCommand(text, {
    handlers: listHandlers(),
    llm: llmClient, // null in CI
  });
  if (!result.ok) { setExtractError(result); return; }
  setPending(result);
}

async function handleApprove() {
  if (!pending) return;
  const flags: Record<string, string> = { 'facet': activeHat!.id };
  const argFlags = Object.entries(pending.args).map(([k, v]) => `${k}=${v}`);
  await dispatch('host.exec', {
    args: [pending.handler],
    flags,
    argPairs: argFlags,
  });
  setPending(null);
}
```

Render order in the Agent context pane:

1. `VoiceInput` (always visible).
2. `ExtractError` inline (if set) with error code + message + handler suggestions.
3. `CommandApprovalCard` modally over the pane (if `pending` set).

### 2.2 Commit

```bash
git add packages/loom/src/helm/TalkMode.tsx
git commit -m "phase-38/D38G.2: wire voice → extract → approve → dispatch in Talk/Agent"
```

---

## Step 3: Receipt Surface in Do/Transact (D38G.3)

### 3.1 Update `packages/loom/src/helm/DoMode.tsx` (or the Transact context panel)

The published `HostCommand` objects should already be routed to Do/Transact by the `coordinationModes` entry from 38A. Verify:

- In the Transact panel, list items filtered to `typeDefinition.name === 'HostCommand'` and `visibility === 'published'`.
- Each item renders: handler, args, exit code (if any), requestedAt, hatId.
- Clicking the item opens a detail panel with the full patch chain — handler call, result patch, timestamps.
- If the item's result patch has `ok: false`, the card shows the error code + message.

### 3.2 Live update

Subscribe to LoomStore changes so a newly-published `HostCommand` appears without a manual refresh. The existing AttentionEngine subscription pattern is the template; do not invent a new one.

### 3.3 Commit

```bash
git add packages/loom/src/helm/DoMode.tsx
git commit -m "phase-38/D38G.3: HostCommand receipts in Do/Transact — live list + detail patch chain"
```

---

## Step 4: Acceptance Test (D38G.4)

### 4.1 Add to `packages/__tests__/phase38-gate.test.ts`

Single end-to-end test that executes the epic's acceptance statement with mocks for the handler and LLM:

1. Seed an identity with an active hat that holds the `HOST_EXEC` capability.
2. Register a **mock** `process.killByPort` handler that records its invocation and returns `{ok: true, exitCode: 0, stdout: '12345', stderr: '', durationMs: 5}` — does not touch real processes.
3. Simulate an utterance `"kill the process on port 9000"` through `extractShellCommand` with the deterministic fallback.
4. Call `route()` with the resulting `host.exec` command.
5. Assert:
   - A `HostCommand` object exists with `visibility === 'published'`.
   - `hatId` matches the active hat, `hatSig` verifies against the canonical payload.
   - The mock handler was invoked exactly once with `{port: 9000}`.
   - A patch with `kind: 'evidence_append'` holding the handler result exists on the object.
6. Second attempt: revoke `HOST_EXEC` from the hat, repeat. Assert the route returns `{code: 'CAPABILITY_CHECK_FAILED'}` and no `HostCommand` was published and the handler was NOT invoked.

### 4.2 Commit

```bash
git commit -m "phase-38/D38G.4: acceptance test — voice → extract → approve → host.exec → receipt"
```

---

## Step 5: Manual Smoke (D38G.5)

Before handing off:

- Run `bun run dev` (or the Vite dev server for loom — note Node 18+ is required per the prior merge).
- Open Helm → Talk → Agent. Verify the mic appears.
- Say "kill the process on port 9000". The transcript fills, the approval card appears.
- Click Approve. The dev console shows the `host.exec` dispatch. Do/Transact shows a new receipt.
- Deny path: temporarily remove `HOST_EXEC` from the hat. Retry. Verify the error renders inline, no receipt appears.

No commit for manual smoke. Note the result in the PR description.

---

## Exit Criteria

- [ ] Voice utterance → approval card → `host.exec` dispatch → published receipt, end to end.
- [ ] Approval card is mandatory, expanded by default, shows hat + capability + args.
- [ ] Capability-denied path is visible to the user; no silent failures.
- [ ] Acceptance test in `phase38-gate.test.ts` passes.
- [ ] All prior phase gates still pass (`bun test packages/__tests__/`).

---

## Merge Procedure (entire Phase 38)

Only after 38A–38G are on the phase branch and all gates pass:

```bash
git checkout phase-38-voice-to-execution
bun run check
bun test packages/__tests__/

git checkout main
git pull --ff-only origin main
git merge --ff-only phase-38-voice-to-execution
git tag -a v38.0 -m "Phase 38: voice-to-execution"
git push origin main --tags
git branch -d phase-38-voice-to-execution
```

Then start the mandatory errata sprint per `docs/BRANCHING-AND-CI-POLICY.md`:

```bash
git checkout -b errata/phase-38
# adversarial scan, docs/prd/PHASE-38-ERRATA.md, fix sprint
# merge to main, tag v38.1
```

Hand off: done. Voice-to-execution is live.
