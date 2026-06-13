---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/mfp_metering.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.232774+00:00
---

# runtime/semantos-brain/src/mfp_metering.zig

```zig
// M4.3 — MfpMeter: per-fetch MFP metering with budget tracking.
//
// Wraps MfpTickProducer to charge a configurable sats cost per octave-1+
// fetch and emit a tick on each successful charge.  Budget is decremented
// after the tick is emitted; if the budget reaches zero, subsequent calls
// return error.BudgetExhausted and the fetch is blocked.
//
// Emit failures (e.g. Pravega HTTP error) are intentionally non-fatal: the
// budget is still decremented and the fetch is allowed to proceed.  This
// keeps the hot path unblocked when the metering back-end is unavailable.
//
// Usage:
//   var meter = MfpMeter.init(config, &producer);
//   try meter.chargeAndEmit(std.time.milliTimestamp());

const std = @import("std");
const mfp_tick_producer = @import("mfp_tick_producer");
const MfpTickProducer = mfp_tick_producer.MfpTickProducer;

pub const MfpMeteringConfig = struct {
    /// Sats cost per octave-1+ fetch (default 1).
    cost_per_fetch_sats: u64 = 1,
    /// Initial budget (0 = unlimited for tests).
    initial_budget_sats: u64,
    /// 32-byte HMAC secret.
    secret: [32]u8,
    /// channel_id string (not owned; caller keeps alive).
    channel_id: []const u8,
};

pub const MfpMeter = struct {
    config: MfpMeteringConfig,
    budget_remaining_sats: u64,
    /// Non-owning pointer — caller keeps MfpTickProducer alive.
    producer: *MfpTickProducer,

    pub fn init(config: MfpMeteringConfig, producer: *MfpTickProducer) MfpMeter {
        return .{
            .config = config,
            .budget_remaining_sats = config.initial_budget_sats,
            .producer = producer,
        };
    }

    /// Attempt to charge for one fetch and emit a tick.
    ///
    /// Returns error.BudgetExhausted if budget_remaining_sats == 0.
    /// On success decrements budget and calls producer.emitTick().
    /// Emit failures are non-fatal: budget is still decremented and the
    /// function returns successfully so the fetch is allowed to proceed.
    pub fn chargeAndEmit(self: *MfpMeter, now_ms: u64) !void {
        if (self.budget_remaining_sats == 0) {
            return error.BudgetExhausted;
        }

        // Decrement budget before emitting so the counter is accurate even
        // if emitTick fails.
        self.budget_remaining_sats -= self.config.cost_per_fetch_sats;

        // Emit the tick; failures are intentionally swallowed (non-fatal).
        self.producer.emitTick(
            &self.config.secret,
            self.config.cost_per_fetch_sats,
            now_ms,
        ) catch {};
    }
};

```
