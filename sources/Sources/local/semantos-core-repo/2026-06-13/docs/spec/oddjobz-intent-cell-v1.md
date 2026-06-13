---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/spec/oddjobz-intent-cell-v1.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.744159+00:00
---

# `oddjobz.intent_cell.v1` — typed natural-language intent cell envelope

**Status**: Draft (Phase 3 implementation 2026-05-07)
**Owner**: Phone (mobile) ⇄ Brain (brain) round-trip for typed natural-language commands.

## Purpose

Carries a fully on-device-extracted-and-kernel-verified intent cell from the
operator's phone to the brain for persistence and downstream dispatch.

The phone runs:
1. SIR extractor (llama.cpp) over the typed transcript → produces an Intent
   JSON.
2. SIR → OIR lowering (`sir_to_oir.dart`).
3. OIR → opcode bytes (`oir_to_bytes.dart`).
4. Kernel verification (`SemantosKernel.executeScript`) → `kernelOk: true`.
5. Cell-id derivation + envelope construction.
6. Outbox enqueue with `cellType = 'oddjobz.intent_cell.v1'`.

The brain brain receives the envelope via the REPL transport, re-runs kernel
verification (defence in depth), persists the cell into
`<data_dir>/oddjobz/intent-cells.jsonl`, emits a helm-broker event so the
phone's `AttentionService` wakes, and acks.

## Wire format

The envelope is a single JSON object, base64-encoded as the argument to the
REPL command `submit-intent-cell --envelope <base64>`. Total size is
expected to stay well under 10 KiB (kernel `MAX_SCRIPT_SIZE`); larger
envelopes fail validation.

```json
{
  "kind": "oddjobz.intent_cell.v1",
  "version": 1,
  "cellId": "cell-<sizeHex(6)>-<bytePrefix(8 hex)>-<uuidTail(8)>",
  "opcodeBytes": "<base64 of the OIR-emitted opcode bytes>",
  "hatId": "<32-hex operator-cert-id>",
  "certId": "<33-hex compressed child pub or 32-hex child cert id>",
  "correlationId": "<uuid v4>",
  "kernelResult": {
    "ok": true,
    "opcount": 12,
    "stackDepth": 3,
    "gasUsed": 17,
    "errorKind": null
  },
  "originalIntent": {
    "summary": "Find the job at wattle street",
    "action": "find",
    "taxonomyJson": "{\"what\":\"jobs\",\"how\":\"find\",\"why\":\"navigate\"}"
  }
}
```

### Field semantics

| Field | Type | Required | Notes |
|---|---|---|---|
| `kind` | string | yes | Must equal the literal `"oddjobz.intent_cell.v1"`. |
| `version` | integer | yes | Must equal `1`. Bumps on breaking shape changes. |
| `cellId` | string | yes | Format `cell-<sizeHex>-<bytePrefix>-<uuidTail>`. Deterministic from `(opcodeBytes, uuid)`. |
| `opcodeBytes` | string (base64) | yes | The OIR-emitted opcode stream. Decoded length must be ≤ 10 KiB (`MAX_SCRIPT_SIZE`). |
| `hatId` | string (32-hex) | yes | The operator's root-cert id. Must match the auth-bound identity on the brain side. |
| `certId` | string (hex) | yes | The child cert id under the operator's chain. Brain validates the chain binding. |
| `correlationId` | string (uuid) | yes | Threads through all stage events for the turn. |
| `kernelResult` | object | yes | Phone's claim — brain re-runs and overrides. See "kernel result reconciliation". |
| `kernelResult.ok` | bool | yes | Must be `true` on a submitted envelope (phone refused-rejected cells never reach the outbox). |
| `kernelResult.opcount` | integer | yes | Phone-reported opcode count. Brain stores its own value. |
| `kernelResult.stackDepth` | integer | yes | Same. |
| `kernelResult.gasUsed` | integer | yes | Same. |
| `kernelResult.errorKind` | string\|null | yes | `null` on `ok: true`. |
| `originalIntent.summary` | string | yes | Operator-readable summary; used for AttentionFeedSection rendering. |
| `originalIntent.action` | string | yes | One of the verbs in `ExtensionGrammar.oddjobz.actionVerbs`. |
| `originalIntent.taxonomyJson` | string | yes | Stringified `{what,how,why}` triple. Stored as-is, not re-parsed by brain. |
| `originalIntent.targetJson` | string | no | **Wave 9 follow-up; ROM-range canonicalised 2026-05-17.** Stringified producer-resolved entity + money refs, all optional. Canonical shape: `{jobId, customerId, costMin, costMax, currency}`. A ROM is a *range*, so `costMin`/`costMax` (both integers, smallest currency unit — cents for AUD/USD, sats for BSV) are the canonical money fields. `amount` (single integer) remains an accepted **point-collapse alias**: when `costMin`/`costMax` are absent but `amount` is present the brain treats it as `costMin == costMax == amount` (see `intent_action_router.parseTargetCost`, shipped `ae9eabb`). When present and parseable, `intent_action_router` honours the resolved ids directly — and, on an `accept_rom`-class action, mints an accepted `auto_rom` Estimate from the range — instead of running the `intent_summary` substring heuristic; when absent or malformed it falls back to the legacy heuristic. Maximum encoded length 1 KiB. |

## Kernel result reconciliation

The phone reports its kernel verdict in `kernelResult`. The brain re-executes
the same opcode bytes through its own kernel binary (`core/cell-engine/src/
executor.zig`). Phase 1 policy:

- **Required**: brain's local execution returns `ok: true`. If the brain's
  kernel rejects, the envelope is rejected with `kernel_rejected_locally`
  and the phone's `kernelResult` plus the brain's local result are both
  surfaced in the response `detail` for operator triage.
- **Not required**: opcount / stackDepth / gasUsed exact equality. Stored
  values come from the brain's local result; the phone's claimed numbers
  are recorded alongside in the JSONL for drift analysis.
- **Future tightening (Phase 2)**: once we have field data on legitimate
  drift (model-version skew, kernel-binary version skew), require exact
  equality and reject divergence as `kernel_result_drift`.

## Cell-id determinism

`cellId` is derived from `(opcodeBytes, uuid)` via:

```
deriveCellId(opcodeBytes, uuid) =
  "cell-{sizeHex(6)}-{bytePrefix(8hex)}-{uuidTail(8)}"
```

where `sizeHex` is the opcode-bytes length in hex (left-padded to 6),
`bytePrefix` is the first 4 bytes of `opcodeBytes` in lower-case hex,
`uuidTail` is the last 8 chars of a fresh UUID v4.

The Dart implementation lives at `apps/oddjobz-mobile/lib/src/gradient/
cell_id.dart`. The brain side does not re-derive — it accepts the phone's
`cellId` verbatim and uses it as the JSONL primary key.

This is a **non-cryptographic** id. A future change will replace it with a
type-hashed cell-id derived from `core/cell-engine/src/cell.zig::packCell`.

## Idempotency

`submit-intent-cell` is idempotent on `cellId`:

- Same `cellId` + same envelope contents → `{"status":"already_exists","cellId":"..."}` (no error).
- Same `cellId` + different envelope contents → error `cell_id_in_use_with_different_contents` (first-write-wins; the second submission is rejected; operator triages via the ratification queue).

## Error response shape

On error, the Semantos Brain handler returns a dispatcher `Result` whose payload is:

```json
{
  "error": "<kind>",
  "hint": "<human-readable message>",
  "detail": { /* optional structured fields */ }
}
```

### Error kinds

| `error` | Meaning | Mobile retry semantics |
|---|---|---|
| `envelope_invalid` | Shape wrong / required field missing / size > 10 KiB / version bump unrecognised | discard (`OutboxFailureKind.validationFailed`) |
| `cert_unknown` | `certId` not in the brain's cert store | discard + flag pairing |
| `cert_binding_mismatch` | `hatId` doesn't match the chain binding for `certId` | discard + flag pairing |
| `kernel_rejected_locally` | Brain's local kernel re-execution returned `ok: false`. `detail` includes both the envelope's claimed result and the brain's local result. | discard, surface to operator |
| `kernel_local_exec_failed` | Brain-side kernel infrastructure error (FFI panic, OOM in arena) | retry (`networkError`) |
| `cell_id_in_use_with_different_contents` | Idempotency conflict | discard, surface to operator |
| `cell_already_exists` | (Not an error — returned as `status: "already_exists"`) | dequeue (success) |
| `persistence_failed` | JSONL append / fsync failed | retry |
| `unauthorised` | Bearer token invalid | reuses existing `ReplUnauthorisedError` path |

## Auth + cap

The REPL command is dispatched under the resource `intent_cells`. `submit`
requires `cap.oddjobz.write_customer` (Phase 1; will become a dedicated
`cap.oddjobz.submit_intent` in a follow-up). `find` and `find_by_id` require
`cap.oddjobz.read_jobs`.

The bearer-token gate at `repl_http.zig` continues to handle session-level
auth; the cap check happens inside the dispatcher resource handler.

## Helm broker emission

On a successful submit, the handler publishes:

```json
{
  "topic": "intent_cell.created",
  "cell_id": "...",
  "hat_id": "...",
  "intent_summary": "...",
  "intent_action": "...",
  "requires_operator_attention": true,
  "ts": <unix ms>
}
```

Mobile's `AttentionService` adds a subscription for this topic so the
typed-NL turn surfaces in the AttentionFeedSection alongside messages and
dispatch decisions.

## Storage

Persisted into `<data_dir>/oddjobz/intent-cells.jsonl`. JSONL row schema:

```json
{
  "ts": 1710000000000,
  "kind": "created",
  "cell_id": "...",
  "hat_id": "...",
  "cert_id": "...",
  "correlation_id": "...",
  "opcount": 12,
  "stack_depth": 3,
  "gas_used": 17,
  "kernel_ok": true,
  "phone_kernel_result_json": "{...}",  // raw envelope kernelResult for drift analysis
  "opcode_bytes_b64": "...",
  "intent_summary": "...",
  "intent_action": "...",
  "intent_taxonomy_json": "...",
  "received_at": "2026-05-07T14:36:00.123Z"
}
```

Replay on startup mirrors the leads/messages pattern (`oddjobz_jsonl_*`).

## Cross-language fixture

A canonical fixture lives at `apps/oddjobz-mobile/test/fixtures/
intent_cell_envelope_fixture.json` — the Dart pipeline must produce a
byte-identical envelope; the Semantos Brain handler test asserts identical decode
against the same fixture. Both sides reference this file.

## Phase plan

- **Phase 3**: REPL transport, lenient kernel-result matching,
  re-use of `cap.oddjobz.write_customer`, first-write-wins idempotency.
- **Phase 4 (this slice)**: brain-side `intent_action_router` —
  subscribes to the helm broker's `intent_cell.created` events,
  maps the verb → canonical Job FSM state, finds a matching job
  by `customer_name` substring search, and drives `jobs.transition`
  through the dispatcher.  Gated behind
  `--enable-intent-action-router` (or `BRAIN_INTENT_ROUTER=1`); OFF
  by default.  Source: `runtime/semantos-brain/src/intent_action_router.zig`,
  conformance: `runtime/semantos-brain/tests/intent_action_router_conformance.zig`.
  - Supported verbs: `quote → quoted`, `schedule → scheduled`,
    `invoice → invoiced`, `close → closed`.  (The brief listed
    `accept → open` but the canonical Job FSM has no `open` state;
    `accept` is dropped.)
  - Eligibility gate: only jobs in state `lead` are routable.
    Already-quoted/scheduled/etc. jobs are left alone so a misfire
    never regresses operator data.
  - Match heuristic: tokenize the intent_summary on whitespace +
    punctuation, lowercase + drop tokens shorter than 4 bytes,
    then substring-match against each job's `customer_name`.
    Exactly one match → transition; zero or multiple → audit-skip.
  - Threading: the broker's mutex is held during subscriber fan-
    out, so the router's callback only enqueues; the dispatch
    happens on the next reactor poll tick (`Router.tick()`),
    which runs outside the broker mutex and lets `jobs.transition`
    re-publish `job.transitioned` without deadlock.
- **Phase 5+**: Strict kernel-result equality, dedicated `cap.oddjobz.
  submit_intent` cap, mesh `payload_type_router` dispatch, type-hashed
  cell-id derivation.
