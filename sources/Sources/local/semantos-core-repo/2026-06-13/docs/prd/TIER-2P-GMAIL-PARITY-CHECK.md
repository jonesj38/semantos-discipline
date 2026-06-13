---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/TIER-2P-GMAIL-PARITY-CHECK.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.666605+00:00
---

# Tier 2P Phase G — Gmail Patch Parity Check

**Outcome: A — Gmail already writes patches. No fix needed.**

Investigated on 2026-05-06 against commit `0e18eb3` ("feat(oddjobz): unify meta ingestion dispatch
and attention").

---

## Question answered

Does `legacy ingest gmail` feed into the unified turn-patch + dispatch pipeline
introduced in `0e18eb3`? Or is that pipeline Meta-only?

**Answer: Gmail already feeds the unified pipeline. Parity is complete.**

---

## Wire path (verified end-to-end)

### 1. Bootstrap wires the hook (`apps/legacy-cli/src/bootstrap.ts` lines 135-216)

```
messagePatchSink  = new JsonlConversationTurnPatchSink({
  root,
  onPatch: dispatchDecisionSink.append,   // <-- fires dispatch on every patch
});
dispatchDecisionSink = new JsonlConversationDispatchDecisionSink({
  root,
  router: dispatchRouter,                 // <-- ConversationDispatchRouter with graphResolver
});
worker = new IngestWorker({
  blobStore, cursorStore, grantResolver,
  onItemPersisted: messagePatchSink.appendRawItem,  // <-- hooked for ALL providers
});
```

### 2. IngestWorker fires for every persisted item (`ingest-worker.ts` line 152)

`IngestWorker.backfill()` calls `this.emitPersistedItem(full)` after every
raw blob is stored. This is provider-agnostic — gmail, meta, or any future
provider all pass through the same hook.

### 3. `rawItemToOddjobzMessagePatch` handles `email/rfc822` (`turn-patch-store.ts` lines 149-207)

`GmailProvider.fetchFull()` returns items with `contentType: 'email/rfc822'`.
`rawItemToOddjobzMessagePatch` explicitly branches on this content type:

- Parses the RFC-822 headers from `item.bytes`
- Constructs `sessionId: "email:<threadId>"` where `threadId` is taken from
  `item.metadata.threadId` (populated by `GmailProvider.listPage` from the
  Gmail API's `threadId` field)
- Sets `channel: 'email'`
- Sets `providerId: 'gmail'`
- Sets `role: 'operator'` if `From:` matches operator emails (checked against
  `todd.price.aus@gmail.com`, `todd@oddjobtodd.com.au`, and the
  `OPERATOR_EMAIL` env var); otherwise `'customer'`
- Writes the `oddjobz.message.v1` patch to
  `~/.semantos/data/oddjobz/messages.jsonl`

### 4. Dispatch fires automatically via `onPatch` (`dispatch-decision-store.ts` line 62-78)

After each patch is written, `dispatchDecisionSink.append(patch)` is called
(wired as `onPatch` in step 1). The dispatch router:

- External-sender emails (`role: 'customer'`): lane `direct`, confidence 0.82
- Operator-sent emails (`role: 'operator'`): heuristic on text body; defaults
  to lane `self` (confidence 0.62) unless text triggers squad/broadcast/agent
  keywords

Each dispatch decision is written to
`~/.semantos/data/oddjobz/dispatch-decisions.jsonl`.

---

## sessionId shape for Gmail

```
email:<gmailThreadId>
```

Example: `email:18e9abc123def456`

The `threadId` comes from `item.metadata.threadId` which `GmailProvider.listPage`
sets from the Gmail API's `threadId` field on each message object. This key is
stable across both backfill and any future webhook tail — Gmail guarantees
`threadId` is invariant for the lifetime of a thread.

---

## Files written by `legacy ingest gmail`

| File | Schema | Notes |
|------|--------|-------|
| `~/.semantos/data/oddjobz/messages.jsonl` | `oddjobz.message.v1` | One row per email message |
| `~/.semantos/data/oddjobz/dispatch-decisions.jsonl` | `oddjobz.dispatch.v1` | One row per email message |

The mobile attention surface (`OddjobzAttentionPaskProjector`) reads both files
in `attention-projector.ts` — `messageSignals()` surfaces customer-role messages,
`dispatchSignals()` surfaces high-confidence or ratification-needed dispatch
decisions.

---

## Operator's tonight run

`legacy ingest gmail --reextract --query "..."` will:

1. Fetch raw RFC-822 blobs from Gmail API
2. Store blobs in `LegacyBlobStore`
3. For each blob: append an `oddjobz.message.v1` patch to `messages.jsonl`
4. For each patch: append an `oddjobz.dispatch.v1` decision to `dispatch-decisions.jsonl`
5. Run the extraction pass (LLM → proposals → proposal-store) in a separate chain

Steps 3 and 4 are **not** gated on the LLM extractor being configured — they
fire even when `extract.skipped` is set. The mobile attention surface will see
all ingested property-manager emails immediately after the run completes,
regardless of LLM availability.

---

## Code locations

| Concern | File |
|---------|------|
| `onItemPersisted` hook wiring | `apps/legacy-cli/src/bootstrap.ts:211-216` |
| `rawItemToOddjobzMessagePatch` (email branch) | `runtime/legacy-ingest/src/conversation/turn-patch-store.ts:149-207` |
| Dispatch decision sink | `runtime/legacy-ingest/src/conversation/dispatch-decision-store.ts` |
| Dispatch router + lane inference | `runtime/legacy-ingest/src/conversation/dispatch-router.ts` |
| Attention projector (reads both files) | `runtime/legacy-ingest/src/attention-projector.ts` |
| Gmail provider (produces `email/rfc822`) | `runtime/legacy-ingest/src/providers/gmail.ts` |
