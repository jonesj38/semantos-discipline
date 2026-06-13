---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30I-OFFLINE-QUEUE.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.686786+00:00
---

# Phase 30I — Offline Queue, Replay & Conflict Resolution

**Version**: 1.0
**Date**: April 2026
**Status**: Ready for implementation
**Duration**: 1-2 weeks
**Prerequisites**: Phase 30G complete (Dart FFI package) or Phase 30F complete (Swift SDK)
**Master document**: `PHASE-30-FFI-MASTER.md`
**Branch**: `phase-30i-offline-queue`

---

## Context

### The Offline-First Rule

The kernel NEVER fails because there's no network. Local operations always succeed. Network-dependent operations are queued transparently. The user experience is: write data → it's saved locally → when signal returns, it syncs. No spinners, no "waiting for network," no data loss.

The mobile kernel operates disconnected-by-default. Every operation (cell write, capability check, linearity enforcement) works locally without network. Network operations (anchor, publish, sync) are queued and dispatched when connectivity returns. This phase implements the offline queue, replay mechanism, and conflict resolution — the features that make the app usable on job sites with no signal.

---

## Source Files / References

| Alias | Path | What to extract |
|-------|------|-----------------|
| `MASTER-FFI` | `docs/prd/PHASE-30-FFI-MASTER.md` | Offline-first architecture, conflict resolution rules |
| `PHASE-30G` | `docs/prd/PHASE-30G-DART-FFI-PACKAGE.md` | Dart adapter pattern for connectivity |
| `STORAGE-ADAPTER` | `packages/protocol-types/src/storage.ts` | StorageAdapter for queue persistence |
| `CONSTANTS` | `packages/protocol-types/src/constants.ts` | Linearity constants |
| `POLICY-BRANCH` | `docs/BRANCHING-AND-CI-POLICY.md` | Commit naming |

---

## Deliverables

### D30I.1 — Operation queue (kernel side)

In `src/ffi/` or `src/kernel/`:

When NetworkAdapter reports no connectivity, kernel writes operations to local queue via StorageAdapter under `_queue/` prefix. Each queued operation contains:
- Type (anchor, publish, sync, capability_check)
- Serialised arguments
- Monotonic sequence number (auto-increment per operation)
- Timestamp (when queued)

Operations queued immediately upon local success; no delay.

Functions exposed via C ABI:
- `semantos_queue_operation(type: u32, args_json: *const u8, args_len: usize) -> i32`
  - Returns: sequence number if successful, -1 if storage failure
- `semantos_queue_count() -> u32`
  - Returns current queue depth
- `semantos_queue_peek(index: u32, out_json: *mut u8, out_len: *mut usize) -> i32`
  - Returns: operation at index or -1 if out of bounds

### D30I.2 — Queue persistence

Queue operations persisted via StorageAdapter (not in-memory). Storage keys:
- `_queue/seq` — monotonic sequence counter (u32)
- `_queue/operations/{seq}` — JSON serialised operation

Queue survives:
- App restart
- App crash
- OS kill signal
- System power loss

On startup, kernel scans `_queue/` namespace and reconstructs queue from persistent storage.

No in-memory queue cache. Every read/write goes through StorageAdapter.

### D30I.3 — Replay engine

On reconnect (connectivity callback from host), queue replays in sequence-number order:

```
1. Fetch _queue/seq to get highest sequence number
2. Loop from seq=0 to max:
   a. Load _queue/operations/{seq}
   b. Attempt execution via NetworkAdapter
   c. If success: delete _queue/operations/{seq}, continue
   d. If failure: move to dead-letter queue, continue (do NOT stop)
3. When done, update _queue/seq to next available
```

Replay is **not** automatic; triggered by:
- `semantos_set_connectivity(connected: bool) -> i32` — when connected transitions from false to true
- Or via host connectivity callback registered during init

Replay is **blocking** (synchronous); host must not perform other operations during replay.

### D30I.4 — Dead-letter queue

Operations that fail replay: conflict, expired capability, double-consume attempt, etc.

Dead-letter storage:
- `_queue/deadletter/{seq}` — original operation + error details
- `_queue/deadletter/count` — u32 count

Dead-letter items surfaced to host via C ABI:
- `semantos_deadletter_count() -> u32`
  - Returns count of dead-lettered operations
- `semantos_deadletter_peek(index: u32, out_json: *mut u8, out_len: *mut usize) -> i32`
  - Returns: operation + error JSON at index, or -1 if out of bounds
  - JSON structure: `{ "operation": {...}, "error": "...", "timestamp": "..." }`
- `semantos_deadletter_discard(index: u32) -> i32`
  - Removes dead-letter item
- `semantos_deadletter_retry(index: u32) -> i32`
  - Moves dead-letter item back to active queue for retry on next reconnect

Dead-letter items are **inspectable and actionable**. Host can display them to user, log them, or retry.

### D30I.5 — Conflict resolution

When two nodes modify same object while disconnected, kernel detects conflict at sync via append-only patch log with facet provenance.

Resolution strategies (configured per object type in vertical config):

1. **LWW (Last-Writer-Wins)** — default for most fields
   - Later timestamp wins unconditionally
   - Loser's changes discarded
   - No user action needed

2. **Merge** — for array fields (photos[], comments[])
   - Both sides' additions included
   - Duplicates removed via object identity
   - Final array = union of both sides' changes

3. **Flag** — for status fields (status, approved)
   - Conflicting transitions flagged for operator review
   - Not auto-resolved; added to dead-letter with "needs_review" error
   - Operator must call `semantos_deadletter_retry()` after reviewing

4. **LINEAR wins** — for linear-token-consuming operations
   - If LINEAR token consumed on one side, that side wins unconditionally
   - Loser's changes reverted
   - Token CANNOT be re-created; loser's attempt to reclaim fails permanently

Vertical config example:
```json
{
  "objects": {
    "photo": {
      "conflict_resolution": {
        "title": "lww",
        "tags": "merge",
        "approved": "flag"
      }
    }
  }
}
```

### D30I.6 — Connectivity callback

Host informs kernel of connectivity changes via:

```c
semantos_set_connectivity(connected: bool) -> i32
```

Returns: 0 on success, -1 on error.

When connected transitions from false to true:
- Kernel immediately begins replay
- Returns control to host
- Replay happens synchronously; host must wait for completion or poll

Alternatively, host can register a callback:
```c
typedef void (*ConnectivityCallback)(bool connected);
semantos_register_connectivity_callback(callback: ConnectivityCallback) -> i32
```

Callback invoked when connectivity changes. Kernel begins replay automatically.

### D30I.7 — Offline queue tests

Comprehensive test suite in `tests/offline_queue_test.zig` or `tests/offline_queue.test.ts`:

**Persistence Tests**:
- Queue operation persists to StorageAdapter
- Queue survives simulated app restart (reload from storage)
- Multiple queued operations maintain order
- Queue count matches actual items

**Replay Tests**:
- Replay executes operations in sequence-number order
- Successful operations removed from queue
- Failed operations moved to dead-letter
- Replay continues on failure (doesn't stop)
- Empty queue on reconnect is no-op

**Dead-Letter Tests**:
- Dead-letter count accurate
- Dead-letter peek returns correct operation + error
- Dead-letter discard removes item
- Dead-letter retry moves item back to active queue

**Linearity Tests**:
- Operation queued offline with LINEAR token
- Same object consumed on server while queued
- Replay detects double-consume, moves to dead-letter
- Dead-letter error message indicates linearity conflict
- Token cannot be re-created

**Conflict Resolution Tests**:
- LWW: later timestamp wins, loser discarded
- Merge: both sides' array additions included
- Flag: conflicting status transitions added to dead-letter with "needs_review"
- LINEAR wins: consumed side wins, loser reverted

**Connectivity Tests**:
- `set_connectivity(false)` → subsequent operations queued
- `set_connectivity(true)` → replay begins automatically
- Callback registered and invoked on connectivity change
- Rapid false→true→false transitions handled correctly

---

## TDD Gate Tests

- **T1**: Operations queued while offline are persisted in StorageAdapter under `_queue/` prefix
- **T2**: On reconnect, queue replays in sequence-number order (seq=0, seq=1, etc.)
- **T3**: Failed replay moves operation to dead-letter queue, continues with next
- **T4**: LINEAR consume queued offline + consumed on server = dead-letter (no double-consume)
- **T5**: Queue survives simulated app restart (persisted, not in-memory)
- **T6**: Connectivity false→true transition triggers replay automatically
- **T7**: Dead-letter peek returns correct operation details (operation + error JSON)
- **T8**: LWW resolution: later timestamp wins, loser discarded
- **T9**: Merge resolution: both sides' array additions included (union of changes)
- **T10**: LINEAR wins resolution: consumed side wins unconditionally, loser reverted
- **T11**: Flag resolution: conflicting status transitions flagged for review (added to dead-letter)
- **T12**: Empty queue on reconnect: no-op, no errors

---

## Completion Criteria

- Queue operations persisted and survive restart
- Replay executes in order and handles failures gracefully
- Dead-letter queue functional and inspectable
- All conflict resolution strategies implemented and tested
- Connectivity callback triggers replay
- No data loss; all operations either succeed, deadletter, or remain queued
- Comprehensive test suite with TDD gate tests passing
