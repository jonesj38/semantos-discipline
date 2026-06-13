---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/prd/PHASE-30I-PROMPT.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.679396+00:00
---

# Phase 30I Execution Prompt — Offline Queue, Replay & Conflict Resolution

> Paste this prompt into a fresh session to execute Phase 30I.

## Context

### Key Rule

The kernel NEVER fails because there's no network. Local operations always succeed. Network-dependent operations are queued transparently. The user experience is: write data → it's saved locally → when signal returns, it syncs. No spinners, no "waiting for network," no data loss.

---

## CRITICAL: READ THESE FILES FIRST

1. `docs/prd/PHASE-30I-OFFLINE-QUEUE.md` — Phase 30I specification
2. `docs/prd/PHASE-30-FFI-MASTER.md` — Offline-first architecture, conflict resolution rules
3. `docs/BRANCHING-AND-CI-POLICY.md` — Commit naming
4. `packages/protocol-types/src/storage.ts` — StorageAdapter interface
5. `packages/protocol-types/src/constants.ts` — Linearity constants

---

## ANTI-BULLSHIT RULES (NON-NEGOTIABLE)

1. **NO STUBS** — Every function must have real implementation, not placeholders
2. **QUEUE IS PERSISTENT** — Survives crash/restart; never in-memory only
3. **REPLAY ORDER IS SACRED** — Monotonic sequence numbers; no reordering
4. **DEAD-LETTER IS NOT A TRASH CAN** — Items must be inspectable and actionable
5. **LINEAR WINS IS ABSOLUTE** — If LINEAR token consumed, no negotiation; loser's retry fails permanently
6. **NO EASY TESTS** — Tests must exercise actual persistence, replay, and conflict scenarios
7. **CONFLICT RESOLUTION IS PER-TYPE** — Not one-size-fits-all; strategies configured per field
8. **CONNECTIVITY IS HOST-PROVIDED** — Kernel doesn't detect network; host tells it via `set_connectivity()`

---

## PART 0: GIT HYGIENE

### 0.1 Assess

```bash
git status -u
git log --oneline -10
git branch -a
```

Expected state: clean working tree, on main, Phase 30G complete.

### 0.2 Commit or discard

If working tree is dirty:
- Stage explicitly: `git add src/... tests/...`
- Never use `git add -A`
- Commit: `git commit -m "..."`
- Or discard: `git checkout -- <files>`

Verify: `git status` shows "nothing to commit, working tree clean"

### 0.3 Verify prerequisites

All of these must exist:

```bash
ls docs/prd/PHASE-30G-DART-FFI-PACKAGE.md  # or PHASE-30F-XCFRAMEWORK-SWIFT.md
ls packages/protocol-types/src/storage.ts
ls packages/protocol-types/src/constants.ts
ls src/ffi/  # FFI implementation directory
zig build test  # gate tests pass on main
```

If any prerequisite is missing, **STOP**. Do not proceed.

### 0.4 Create branch

```bash
git checkout -b phase-30i-offline-queue
git push -u origin phase-30i-offline-queue
```

---

## Step 1: Offline Queue Persistence — D30I.1 & D30I.2

**Commit message**: `phase-30i/D30I.1: Operation queue with persistent storage via StorageAdapter`

Create `src/ffi/offline_queue.zig` (or equivalent in your language):

```zig
// Queue operation structure
const QueueOperation = struct {
    sequence: u32,
    operation_type: u32,  // anchor, publish, sync, capability_check
    args_json: []const u8,
    timestamp: i64,
};

// C ABI functions
pub export fn semantos_queue_operation(
    operation_type: u32,
    args_json: [*]const u8,
    args_len: usize,
) i32 {
    // 1. Get next sequence number from _queue/seq
    // 2. Serialise operation to JSON
    // 3. Write to StorageAdapter under _queue/operations/{seq}
    // 4. Increment _queue/seq
    // 5. Return sequence number or -1 on failure
}

pub export fn semantos_queue_count() u32 {
    // Return count of operations in _queue/ namespace
}

pub export fn semantos_queue_peek(
    index: u32,
    out_json: [*]u8,
    out_len: *usize,
) i32 {
    // Load _queue/operations/{index}
    // Copy JSON to out_json (up to out_len bytes)
    // Update out_len with actual length
    // Return 0 on success, -1 if out of bounds
}
```

Implementation requirements:
- Use StorageAdapter for all persistence (never in-memory)
- Sequence numbers are monotonic and never reused
- Each operation stored as `_queue/operations/{seq}` JSON
- `_queue/seq` tracks next available sequence number

**Test** (T1, T5):
```zig
test "queue persists operation to storage" {
    // 1. Queue operation while offline
    // 2. Verify StorageAdapter contains _queue/operations/{seq}
    // 3. Simulate app restart (reload from storage)
    // 4. Verify queue count unchanged
}
```

Commit and push.

---

## Step 2: Replay Engine — D30I.3

**Commit message**: `phase-30i/D30I.3: Queue replay on reconnect with sequence order`

Create `src/ffi/replay_engine.zig`:

```zig
pub export fn semantos_set_connectivity(connected: bool) i32 {
    // 1. If connected == true and previous state was false:
    //    a. Get max sequence from _queue/seq
    //    b. For seq in 0..max:
    //       - Load _queue/operations/{seq}
    //       - Execute via NetworkAdapter
    //       - If success: delete _queue/operations/{seq}
    //       - If failure: move to dead-letter queue, continue
    //    c. Compact _queue/seq
    // 2. Update connectivity state
    // 3. Return 0 on success, -1 on error
}

pub export fn semantos_register_connectivity_callback(
    callback: *const fn (bool) void,
) i32 {
    // Store callback pointer
    // Invoke callback on connectivity state changes
    // Return 0 on success
}
```

Implementation requirements:
- Replay is **sequence-ordered**: always seq=0, seq=1, seq=2, etc.
- Replay is **non-stopping**: failure moves to dead-letter, continues
- Replay is **synchronous**: host waits for completion
- Connectivity callback invoked before returning from `set_connectivity()`

**Test** (T2, T3, T6):
```zig
test "replay executes queued operations in order" {
    // 1. Queue ops with seq=0,1,2
    // 2. Set connectivity to true
    // 3. Verify replay executed in order (check execution log)
    // 4. Verify successful ops removed from queue
}

test "failed replay moves operation to dead-letter" {
    // 1. Queue operation that will fail execution
    // 2. Mock NetworkAdapter to fail
    // 3. Set connectivity to true
    // 4. Verify operation in dead-letter queue
    // 5. Verify next operation executed (no stop)
}

test "connectivity callback triggered" {
    // 1. Register callback
    // 2. Set connectivity to true
    // 3. Verify callback invoked with true
}
```

Commit and push.

---

## Step 3: Dead-Letter Queue — D30I.4

**Commit message**: `phase-30i/D30I.4: Dead-letter queue for failed operations`

Extend `src/ffi/offline_queue.zig`:

```zig
pub export fn semantos_deadletter_count() u32 {
    // Return count of items in _queue/deadletter/
}

pub export fn semantos_deadletter_peek(
    index: u32,
    out_json: [*]u8,
    out_len: *usize,
) i32 {
    // Load _queue/deadletter/{index}
    // Return JSON: { operation: {...}, error: "...", timestamp: "..." }
    // Return 0 on success, -1 if out of bounds
}

pub export fn semantos_deadletter_discard(index: u32) i32 {
    // Delete _queue/deadletter/{index}
    // Return 0 on success
}

pub export fn semantos_deadletter_retry(index: u32) i32 {
    // Load _queue/deadletter/{index}
    // Move back to active queue with new sequence number
    // Delete from dead-letter
    // Return 0 on success
}
```

Dead-letter JSON structure:
```json
{
    "sequence": 5,
    "operation": {...},
    "error": "double_consume",
    "error_details": "LINEAR token already consumed at seq:3",
    "timestamp": "2026-04-02T14:30:00Z"
}
```

**Test** (T7):
```zig
test "dead-letter peek returns operation and error" {
    // 1. Queue and fail operation
    // 2. Call deadletter_peek
    // 3. Verify JSON contains operation + error details
}

test "dead-letter retry moves item back to queue" {
    // 1. Dead-letter an operation
    // 2. Call deadletter_retry
    // 3. Verify operation in active queue
    // 4. Verify removed from dead-letter
}
```

Commit and push.

---

## Step 4: Linearity Conflict Detection — D30I.5 (LINEAR wins)

**Commit message**: `phase-30i/D30I.5: Linearity conflict detection in queue replay`

In `src/ffi/replay_engine.zig`, add linearity check to replay:

```zig
fn replayOperation(op: QueueOperation) ReplayResult {
    // 1. Check if operation consumes LINEAR token
    // 2. If yes:
    //    a. Query server for token consumption via anchor/sync
    //    b. If server has consumed it:
    //       - Token consumed elsewhere (double-consume)
    //       - Move to dead-letter with error "linear_already_consumed"
    //       - Return failure
    //    c. If server hasn't consumed it:
    //       - Execute operation (consume token)
    //       - Return success
    // 3. Otherwise, execute normally
}
```

Linearity logic:
- LINEAR token can only be consumed once (globally)
- If queue queued offline, and server consumed in parallel → dead-letter
- Loser cannot re-create token; token is gone forever

**Test** (T4, T10):
```zig
test "linear consume queued offline and consumed on server = dead-letter" {
    // 1. Queue LINEAR consume operation
    // 2. Simulate server consuming same token
    // 3. Set connectivity to true (replay)
    // 4. Verify operation in dead-letter
    // 5. Verify error is "linear_already_consumed"
    // 6. Verify deadletter_retry fails or returns error
}

test "linear wins: consumed side wins unconditionally" {
    // 1. Object modified locally (LINEAR token consumed locally)
    // 2. Server also attempts to consume same token
    // 3. Sync detects conflict
    // 4. Consumed side (ours) wins; server's attempt fails
    // 5. Verify server gets error on next sync attempt
}
```

Commit and push.

---

## Step 5: Conflict Resolution Strategies — D30I.5 (LWW, Merge, Flag)

**Commit message**: `phase-30i/D30I.5: Conflict resolution (LWW, Merge, Flag) per object type`

Create `src/ffi/conflict_resolver.zig`:

```zig
pub const ConflictStrategy = enum {
    lww,      // Last-Writer-Wins
    merge,    // For arrays
    flag,     // For status (needs review)
    linear_wins,  // For LINEAR tokens
};

pub fn resolveConflict(
    object_type: []const u8,
    field_name: []const u8,
    local_value: []const u8,
    remote_value: []const u8,
    config: VerticalConfig,
) ResolutionResult {
    // 1. Look up strategy in config for object_type.field_name
    // 2. If lww:
    //    a. Compare timestamps
    //    b. Return newer value
    // 3. If merge:
    //    a. Parse both as JSON arrays
    //    b. Merge unique items
    //    c. Return union
    // 4. If flag:
    //    a. Return { conflict: true, values: [local, remote], needs_review: true }
    // 5. If linear_wins:
    //    a. Check which side has LINEAR token
    //    b. Return that side's value; revoke loser's changes
}
```

Integration:
- Vertical config defines strategy per field: `"title": "lww"`, `"photos": "merge"`, `"status": "flag"`
- On sync, when conflict detected, resolution applied
- If flag: move to dead-letter with `"needs_review": true`; operator reviews and retries

**Test** (T8, T9, T11):
```zig
test "lww resolution: later timestamp wins" {
    // 1. Create conflict: local=title1 (ts=100), remote=title2 (ts=200)
    // 2. Resolve with lww strategy
    // 3. Verify result is title2
}

test "merge resolution: array union" {
    // 1. Create conflict: local=[photo1, photo2], remote=[photo2, photo3]
    // 2. Resolve with merge strategy
    // 3. Verify result is [photo1, photo2, photo3] (deduplicated)
}

test "flag resolution: conflict flagged for review" {
    // 1. Create conflict: local=status:approved, remote=status:rejected
    // 2. Resolve with flag strategy
    // 3. Verify result includes needs_review: true
    // 4. Verify moved to dead-letter with "needs_review" error
}
```

Commit and push.

---

## Step 6: Comprehensive Test Suite

**Commit message**: `phase-30i/D30I.7: Comprehensive offline queue and conflict tests`

Create `tests/offline_queue_test.zig` or `tests/offline_queue.test.ts`:

Coverage:

1. **Persistence** (T1, T5):
   - Queue persists to StorageAdapter
   - Survives app restart
   - Multiple operations maintain order

2. **Replay** (T2, T3, T6):
   - Executes in sequence order
   - Continues on failure
   - Connectivity callback triggers

3. **Dead-Letter** (T7):
   - Count, peek, discard, retry all work

4. **Linearity** (T4, T10):
   - Double-consume detected
   - Dead-letter on conflict

5. **Conflict Resolution** (T8, T9, T11):
   - LWW: later timestamp wins
   - Merge: union of arrays
   - Flag: flagged for review
   - LINEAR wins: unconditional

6. **Edge Cases** (T12):
   - Empty queue on reconnect
   - Rapid connectivity changes
   - Multiple dead-letter items
   - Retry of dead-letter operation

Run full test suite:

```bash
zig build test -Dtarget=native
```

All tests pass before moving on.

Commit and push.

---

## Step 7: Integration & Final Gate Tests

**Commit message**: `phase-30i/D30I.7: Integration tests for offline queue`

Create `tests/offline_integration_test.zig`:

Integration scenarios:

1. **Job site scenario**: No connectivity for 2 hours
   - Queue 10 operations (cell writes, capability checks, publishes)
   - Verify all queued
   - Set connectivity true
   - Verify all replayed in order
   - Verify successful ones removed

2. **Partial failure scenario**: Some operations fail on replay
   - Queue 5 operations: [ok, ok, fail, ok, ok]
   - Set connectivity true
   - Verify ops 0,1,3,4 succeed and removed
   - Verify op 2 in dead-letter
   - Verify deadletter_count() == 1

3. **Conflict + dead-letter scenario**: Offline write conflicts with server change
   - Queue write to field with flag strategy
   - Server modifies same field
   - Set connectivity true
   - Verify operation dead-lettered with needs_review: true
   - Operator reviews and calls deadletter_retry()

4. **Multi-client scenario**: Two phones sync
   - Phone A queues operation
   - Phone B consumes LINEAR token
   - Phone A reconnects
   - Verify Phone A's operation dead-lettered
   - Verify deadletter_retry fails (can't reclaim token)

Run integration tests:

```bash
zig build test
```

All pass before completion.

Commit and push.

---

## Completion Criteria

- Queue operations persisted and survive restart
- Replay executes in sequence order and handles failures
- Dead-letter queue functional and inspectable
- All conflict resolution strategies implemented (LWW, Merge, Flag, LINEAR wins)
- Connectivity callback triggers replay
- Linearity conflicts detected and dead-lettered
- No data loss; all operations either succeed, dead-letter, or remain queued
- All TDD gate tests (T1-T12) passing
- Comprehensive integration test suite passing
- Code review: no stubs, no in-memory-only queues, no easy tests
