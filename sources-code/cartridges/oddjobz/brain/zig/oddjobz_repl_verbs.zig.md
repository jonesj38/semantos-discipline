---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/oddjobz_repl_verbs.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.478611+00:00
---

# cartridges/oddjobz/brain/zig/oddjobz_repl_verbs.zig

```zig
//! oddjobz REPL verb forms — C4 PR-R3b (jobs).
//!
//! The bespoke oddjobz REPL verbs (`find jobs`, `add job`, `jobs quote <id>`, …)
//! moved out of the brain into the cartridge. registerInto() registers each
//! `<cmd> <resource>` form into the brain's ReplVerbRegistry; the brain REPL's
//! handleLine dispatches to these handlers with no oddjobz verb code of its own.
//!
//! Each handler has the registry signature `(allocator, *Dispatcher, *const
//! Output, args)` — args is the line tail after `<cmd> <resource>`. Handlers
//! parse args + dispatch through the cartridge's typed `jobs` resource (same
//! in-process-root path the hardcoded branches used). This PR moves the JOBS
//! verbs; the other resources follow the same pattern in later PRs.

const std = @import("std");
const dispatcher_mod = @import("dispatcher");
const Output = @import("repl_output").Output;
const repl_verb_registry = @import("repl_verb_registry");

/// Register all jobs verb forms into the brain's REPL verb registry.
pub fn registerInto(reg: *repl_verb_registry.ReplVerbRegistry) void {
    reg.add(.{ .cmd = "find", .resource = "jobs", .handler = jobsFind });
    reg.add(.{ .cmd = "find", .resource = "job", .handler = jobsFindById });
    reg.add(.{ .cmd = "add", .resource = "job", .handler = jobsCreate });
    reg.add(.{ .cmd = "quote", .resource = "job", .handler = jobsQuote });
    reg.add(.{ .cmd = "schedule", .resource = "job", .handler = jobsSchedule });
    reg.add(.{ .cmd = "start", .resource = "job", .handler = jobsStart });
    reg.add(.{ .cmd = "complete", .resource = "job", .handler = jobsComplete });
    reg.add(.{ .cmd = "invoice", .resource = "job", .handler = jobsInvoice });
    reg.add(.{ .cmd = "mark", .resource = "job", .handler = jobsMarkPaid });
    reg.add(.{ .cmd = "close", .resource = "job", .handler = jobsClose });
    reg.add(.{ .cmd = "transition", .resource = "job", .handler = jobsTransition });
    reg.add(.{ .cmd = "find", .resource = "calendar", .handler = jobsFindCalendar });
    reg.add(.{ .cmd = "find", .resource = "attention", .handler = jobsFindAttention });
    // customers (C4 PR-R3c)
    reg.add(.{ .cmd = "find", .resource = "customers", .handler = customersFind });
    reg.add(.{ .cmd = "find", .resource = "customer", .handler = customersFindById });
    reg.add(.{ .cmd = "add", .resource = "customer", .handler = customersCreate });
    // visits (C4 PR-R3d)
    reg.add(.{ .cmd = "find", .resource = "visits", .handler = visitsFind });
    reg.add(.{ .cmd = "find", .resource = "visit", .handler = visitsFindById });
    reg.add(.{ .cmd = "add", .resource = "visit", .handler = visitsCreate });
    reg.add(.{ .cmd = "start", .resource = "visit", .handler = visitsStart });
    reg.add(.{ .cmd = "complete", .resource = "visit", .handler = visitsComplete });
    reg.add(.{ .cmd = "cancel", .resource = "visit", .handler = visitsCancel });
    reg.add(.{ .cmd = "transition", .resource = "visit", .handler = visitsTransition });
    // quotes (C4 PR-R3e)
    reg.add(.{ .cmd = "find", .resource = "quotes", .handler = quotesFind });
    reg.add(.{ .cmd = "find", .resource = "quote", .handler = quotesFindById });
    reg.add(.{ .cmd = "add", .resource = "quote", .handler = quotesCreate });
    reg.add(.{ .cmd = "present", .resource = "quote", .handler = quotesPresent });
    reg.add(.{ .cmd = "accept", .resource = "quote", .handler = quotesAccept });
    reg.add(.{ .cmd = "decline", .resource = "quote", .handler = quotesDecline });
    reg.add(.{ .cmd = "expire", .resource = "quote", .handler = quotesExpire });
    reg.add(.{ .cmd = "supersede", .resource = "quote", .handler = quotesSupersede });
    reg.add(.{ .cmd = "transition", .resource = "quote", .handler = quotesTransition });
    // invoices (C4 PR-R3f)
    reg.add(.{ .cmd = "find", .resource = "invoices", .handler = invoicesFind });
    reg.add(.{ .cmd = "find", .resource = "invoice", .handler = invoicesFindById });
    reg.add(.{ .cmd = "add", .resource = "invoice", .handler = invoicesCreate });
    reg.add(.{ .cmd = "send", .resource = "invoice", .handler = invoicesSend });
    reg.add(.{ .cmd = "mark", .resource = "invoice", .handler = invoicesMark });
    reg.add(.{ .cmd = "cancel", .resource = "invoice", .handler = invoicesCancel });
    reg.add(.{ .cmd = "void", .resource = "invoice", .handler = invoicesCancel }); // void = cancel alias
    reg.add(.{ .cmd = "transition", .resource = "invoice", .handler = invoicesTransition });
    // attachments (C4 PR-R3g) — final resource
    reg.add(.{ .cmd = "find", .resource = "attachments", .handler = attachmentsFind });
    reg.add(.{ .cmd = "find", .resource = "attachment", .handler = attachmentsFindById });
    reg.add(.{ .cmd = "add", .resource = "attachment", .handler = attachmentsCreate });
}

// ── read verbs ──────────────────────────────────────────────────────────────

fn jobsFind(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    // Optional `--state <state>` filter.
    var state_filter: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--state") and i + 1 < args.len) {
            state_filter = args[i + 1];
            i += 1;
        }
    }
    var args_buf: [256]u8 = undefined;
    const args_json: []const u8 = blk: {
        if (state_filter) |s| {
            break :blk std.fmt.bufPrint(&args_buf, "{{\"state\":\"{s}\"}}", .{s}) catch "{}";
        }
        break :blk "{}";
    };
    return dispatchJobs(allocator, disp, out, "find", args_json);
}

fn jobsFindById(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 1) {
        try out.print("usage: find job <id>\n", .{});
        return;
    }
    var args_buf: [256]u8 = undefined;
    const args_json = std.fmt.bufPrint(&args_buf, "{{\"id\":\"{s}\"}}", .{args[0]}) catch "{}";
    return dispatchJobs(allocator, disp, out, "find_by_id", args_json);
}

fn jobsCreate(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 2) {
        try out.print("usage: add job <customer-name> <state> [scheduled-at]\n", .{});
        try out.print("       state ∈ lead, quoted, scheduled, in_progress, completed, invoiced, paid, closed\n", .{});
        return;
    }
    const customer_name = args[0];
    const state = args[1];
    const scheduled_at = if (args.len >= 3) args[2] else "";

    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"customer_name\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, customer_name, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.appendSlice(allocator, ",\"state\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, state, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (scheduled_at.len > 0) {
        try buf.appendSlice(allocator, ",\"scheduled_at\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, scheduled_at, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.append(allocator, '}');
    return dispatchJobs(allocator, disp, out, "create", buf.items);
}

fn jobsFindCalendar(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    var from_arg: ?[]const u8 = null;
    var to_arg: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--from") and i + 1 < args.len) {
            from_arg = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--to") and i + 1 < args.len) {
            to_arg = args[i + 1];
            i += 1;
        }
    }
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    if (from_arg == null and to_arg == null) {
        try buf.appendSlice(allocator, "{}");
    } else {
        try buf.append(allocator, '{');
        var emitted_one = false;
        if (from_arg) |s| {
            try buf.appendSlice(allocator, "\"from\":");
            const enc = try std.json.Stringify.valueAlloc(allocator, s, .{});
            defer allocator.free(enc);
            try buf.appendSlice(allocator, enc);
            emitted_one = true;
        }
        if (to_arg) |s| {
            if (emitted_one) try buf.append(allocator, ',');
            try buf.appendSlice(allocator, "\"to\":");
            const enc = try std.json.Stringify.valueAlloc(allocator, s, .{});
            defer allocator.free(enc);
            try buf.appendSlice(allocator, enc);
        }
        try buf.append(allocator, '}');
    }
    return dispatchJobs(allocator, disp, out, "find_calendar", buf.items);
}

fn jobsFindAttention(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    _ = args;
    return dispatchJobs(allocator, disp, out, "find_attention", "{}");
}

// ── FSM transition (sugar) verbs ─────────────────────────────────────────────

const FsmVerbSpec = struct {
    to_state: []const u8,
    cap: ?[]const u8,
    principal: []const u8,
    total_cents: ?i64 = null,
};

fn jobsTransitionGeneric(
    allocator: std.mem.Allocator,
    disp: *dispatcher_mod.Dispatcher,
    out: *const Output,
    id: []const u8,
    spec: FsmVerbSpec,
    scheduled_at: ?[]const u8,
) anyerror!void {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"id\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, id, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.appendSlice(allocator, ",\"to_state\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, spec.to_state, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.appendSlice(allocator, ",\"principal_kind\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, spec.principal, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (spec.cap) |c| {
        try buf.appendSlice(allocator, ",\"presented_cap\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, c, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (scheduled_at) |s| {
        try buf.appendSlice(allocator, ",\"scheduled_at\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, s, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (spec.total_cents) |tc| {
        if (tc > 0) try buf.print(allocator, ",\"total_cents\":{d}", .{tc});
    }
    try buf.append(allocator, '}');
    return dispatchJobs(allocator, disp, out, "transition", buf.items);
}

fn requireId(out: *const Output, args: []const []const u8, usage: []const u8) ?[]const u8 {
    if (args.len < 1) {
        out.print("{s}\n", .{usage}) catch {};
        return null;
    }
    return args[0];
}

fn jobsQuote(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    const id = requireId(out, args, "usage: quote job <id>") orelse return;
    return jobsTransitionGeneric(allocator, disp, out, id, .{ .to_state = "quoted", .cap = "cap.oddjobz.quote", .principal = "operator" }, null);
}

fn jobsSchedule(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len == 0) {
        try out.print("usage: schedule job <id> [--at <ISO timestamp>]\n", .{});
        return;
    }
    const id = args[0];
    var scheduled_at: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--at") and i + 1 < args.len) {
            scheduled_at = args[i + 1];
            i += 1;
        }
    }
    return jobsTransitionGeneric(allocator, disp, out, id, .{ .to_state = "scheduled", .cap = "cap.oddjobz.dispatch", .principal = "operator" }, scheduled_at);
}

fn jobsStart(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    const id = requireId(out, args, "usage: start job <id>") orelse return;
    return jobsTransitionGeneric(allocator, disp, out, id, .{ .to_state = "in_progress", .cap = null, .principal = "service" }, null);
}

fn jobsComplete(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    const id = requireId(out, args, "usage: complete job <id>") orelse return;
    return jobsTransitionGeneric(allocator, disp, out, id, .{ .to_state = "completed", .cap = null, .principal = "operator" }, null);
}

fn jobsInvoice(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len == 0) {
        try out.print("usage: invoice job <id> [total_cents <n>]\n", .{});
        return;
    }
    const id = args[0];
    var total_cents: ?i64 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "total_cents") and i + 1 < args.len) {
            total_cents = std.fmt.parseInt(i64, args[i + 1], 10) catch null;
            i += 1;
        }
    }
    return jobsTransitionGeneric(allocator, disp, out, id, .{ .to_state = "invoiced", .cap = "cap.oddjobz.invoice", .principal = "operator", .total_cents = total_cents }, null);
}

/// `mark job paid <id>` → args = [paid, <id>] (the line tail after `mark job`).
fn jobsMarkPaid(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 2 or !std.mem.eql(u8, args[0], "paid")) {
        try out.print("usage: mark job paid <id>\n", .{});
        return;
    }
    return jobsTransitionGeneric(allocator, disp, out, args[1], .{ .to_state = "paid", .cap = null, .principal = "service" }, null);
}

fn jobsClose(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    const id = requireId(out, args, "usage: close job <id>") orelse return;
    return jobsTransitionGeneric(allocator, disp, out, id, .{ .to_state = "closed", .cap = "cap.oddjobz.close", .principal = "operator" }, null);
}

fn jobsTransition(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 2) {
        try out.print("usage: transition job <id> <to_state> [--cap X] [--principal X]\n", .{});
        return;
    }
    const id = args[0];
    const to_state = args[1];
    var cap: ?[]const u8 = null;
    var principal: []const u8 = "operator";
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--cap") and i + 1 < args.len) {
            cap = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--principal") and i + 1 < args.len) {
            principal = args[i + 1];
            i += 1;
        }
    }
    return jobsTransitionGeneric(allocator, disp, out, id, .{ .to_state = to_state, .cap = cap, .principal = principal }, null);
}

// ── dispatch helper ──────────────────────────────────────────────────────────

fn dispatchJobs(
    allocator: std.mem.Allocator,
    disp: *dispatcher_mod.Dispatcher,
    out: *const Output,
    cmd: []const u8,
    args_json: []const u8,
) anyerror!void {
    _ = allocator;
    const ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "in_process" },
    };
    var result = disp.dispatch(&ctx, "jobs", cmd, args_json) catch |err| {
        try out.print("jobs.{s}: dispatch failed: {s}\n", .{ cmd, @errorName(err) });
        return;
    };
    defer result.deinit();
    if (result.payload.len > 0) try out.print("{s}\n", .{result.payload});
}

// ══ customers (C4 PR-R3c) ════════════════════════════════════════════════════

fn customersFind(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    var name_filter: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--name") and i + 1 < args.len) {
            name_filter = args[i + 1];
            i += 1;
        }
    }
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    if (name_filter) |s| {
        try buf.appendSlice(allocator, "{\"name\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, s, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
        try buf.append(allocator, '}');
    } else {
        try buf.appendSlice(allocator, "{}");
    }
    return dispatchCustomers(allocator, disp, out, "find", buf.items);
}

fn customersFindById(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 1) {
        try out.print("usage: find customer <id>\n", .{});
        return;
    }
    var args_buf: [256]u8 = undefined;
    const args_json = std.fmt.bufPrint(&args_buf, "{{\"id\":\"{s}\"}}", .{args[0]}) catch "{}";
    return dispatchCustomers(allocator, disp, out, "find_by_id", args_json);
}

fn customersCreate(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 1) {
        try out.print("usage: add customer <display-name> [--phone X] [--email X] [--address X] [--notes X]\n", .{});
        return;
    }
    const display_name = args[0];
    var phone: []const u8 = "";
    var email: []const u8 = "";
    var address: []const u8 = "";
    var notes: []const u8 = "";
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (i + 1 >= args.len) break;
        if (std.mem.eql(u8, arg, "--phone")) {
            phone = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--email")) {
            email = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--address")) {
            address = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, arg, "--notes")) {
            notes = args[i + 1];
            i += 1;
        }
    }
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"display_name\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, display_name, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (phone.len > 0) {
        try buf.appendSlice(allocator, ",\"phone\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, phone, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (email.len > 0) {
        try buf.appendSlice(allocator, ",\"email\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, email, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (address.len > 0) {
        try buf.appendSlice(allocator, ",\"address\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, address, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (notes.len > 0) {
        try buf.appendSlice(allocator, ",\"notes\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, notes, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.append(allocator, '}');
    return dispatchCustomers(allocator, disp, out, "create", buf.items);
}

fn dispatchCustomers(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, cmd: []const u8, args_json: []const u8) anyerror!void {
    _ = allocator;
    const ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "in_process" },
    };
    var result = disp.dispatch(&ctx, "customers", cmd, args_json) catch |err| {
        try out.print("customers.{s}: dispatch failed: {s}\n", .{ cmd, @errorName(err) });
        return;
    };
    defer result.deinit();
    if (result.payload.len > 0) try out.print("{s}\n", .{result.payload});
}

// ══ visits (C4 PR-R3d) ═══════════════════════════════════════════════════════

fn visitsFind(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    var job_id_filter: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--job-id") and i + 1 < args.len) {
            job_id_filter = args[i + 1];
            i += 1;
        }
    }
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    if (job_id_filter) |s| {
        try buf.appendSlice(allocator, "{\"job_id\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, s, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
        try buf.append(allocator, '}');
    } else {
        try buf.appendSlice(allocator, "{}");
    }
    return dispatchVisits(allocator, disp, out, "find", buf.items);
}

fn visitsFindById(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 1) {
        try out.print("usage: find visit <id>\n", .{});
        return;
    }
    var args_buf: [256]u8 = undefined;
    const args_json = std.fmt.bufPrint(&args_buf, "{{\"id\":\"{s}\"}}", .{args[0]}) catch "{}";
    return dispatchVisits(allocator, disp, out, "find_by_id", args_json);
}

fn visitsCreate(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 4) {
        try out.print("usage: add visit --job <job-id> --type <visit-type> [--notes \"...\"]\n", .{});
        try out.print("       visit-type ∈ inspection, quote_visit, scheduled_work, return_visit, emergency\n", .{});
        return;
    }
    var job_id: []const u8 = "";
    var visit_type: []const u8 = "";
    var notes: []const u8 = "";
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (i + 1 >= args.len) break;
        if (std.mem.eql(u8, args[i], "--job")) {
            job_id = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--type")) {
            visit_type = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--notes")) {
            notes = args[i + 1];
            i += 1;
        }
    }
    if (job_id.len == 0 or visit_type.len == 0) {
        try out.print("usage: add visit --job <job-id> --type <visit-type> [--notes \"...\"]\n", .{});
        return;
    }
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"job_id\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, job_id, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.appendSlice(allocator, ",\"visit_type\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, visit_type, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (notes.len > 0) {
        try buf.appendSlice(allocator, ",\"notes\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, notes, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.append(allocator, '}');
    return dispatchVisits(allocator, disp, out, "create", buf.items);
}

const VisitFsmVerbSpec = struct {
    to_state: []const u8,
    cap: ?[]const u8,
    principal: []const u8,
    outcome: ?[]const u8,
};

fn visitsTransitionGeneric(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, id: []const u8, spec: VisitFsmVerbSpec) anyerror!void {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"id\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, id, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.appendSlice(allocator, ",\"to_state\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, spec.to_state, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.appendSlice(allocator, ",\"principal_kind\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, spec.principal, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (spec.cap) |c| {
        try buf.appendSlice(allocator, ",\"presented_cap\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, c, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (spec.outcome) |o| {
        try buf.appendSlice(allocator, ",\"outcome\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, o, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.append(allocator, '}');
    return dispatchVisits(allocator, disp, out, "transition", buf.items);
}

fn visitsStart(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    const id = requireId(out, args, "usage: start visit <id>") orelse return;
    return visitsTransitionGeneric(allocator, disp, out, id, .{ .to_state = "in_progress", .cap = null, .principal = "service", .outcome = null });
}

fn visitsComplete(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len == 0) {
        try out.print("usage: complete visit <id> [--outcome <outcome>]\n", .{});
        return;
    }
    const id = args[0];
    var outcome: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--outcome") and i + 1 < args.len) {
            outcome = args[i + 1];
            i += 1;
        }
    }
    return visitsTransitionGeneric(allocator, disp, out, id, .{ .to_state = "completed", .cap = null, .principal = "operator", .outcome = outcome });
}

fn visitsCancel(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    const id = requireId(out, args, "usage: cancel visit <id>") orelse return;
    return visitsTransitionGeneric(allocator, disp, out, id, .{ .to_state = "cancelled", .cap = null, .principal = "operator", .outcome = null });
}

fn visitsTransition(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 2) {
        try out.print("usage: transition visit <id> <to_state> [--principal X] [--cap X]\n", .{});
        return;
    }
    const id = args[0];
    const to_state = args[1];
    var cap: ?[]const u8 = null;
    var principal: []const u8 = "operator";
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--cap") and i + 1 < args.len) {
            cap = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--principal") and i + 1 < args.len) {
            principal = args[i + 1];
            i += 1;
        }
    }
    return visitsTransitionGeneric(allocator, disp, out, id, .{ .to_state = to_state, .cap = cap, .principal = principal, .outcome = null });
}

fn dispatchVisits(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, cmd: []const u8, args_json: []const u8) anyerror!void {
    _ = allocator;
    const ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "in_process" },
    };
    var result = disp.dispatch(&ctx, "visits", cmd, args_json) catch |err| {
        try out.print("visits.{s}: dispatch failed: {s}\n", .{ cmd, @errorName(err) });
        return;
    };
    defer result.deinit();
    if (result.payload.len > 0) try out.print("{s}\n", .{result.payload});
}

// ══ quotes (C4 PR-R3e) ═══════════════════════════════════════════════════════

fn quotesFind(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    var job_id_filter: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--job-id") and i + 1 < args.len) {
            job_id_filter = args[i + 1];
            i += 1;
        }
    }
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    if (job_id_filter) |s| {
        try buf.appendSlice(allocator, "{\"job_id\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, s, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
        try buf.append(allocator, '}');
    } else {
        try buf.appendSlice(allocator, "{}");
    }
    return dispatchQuotes(allocator, disp, out, "find", buf.items);
}

fn quotesFindById(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 1) {
        try out.print("usage: find quote <id>\n", .{});
        return;
    }
    var args_buf: [256]u8 = undefined;
    const args_json = std.fmt.bufPrint(&args_buf, "{{\"id\":\"{s}\"}}", .{args[0]}) catch "{}";
    return dispatchQuotes(allocator, disp, out, "find_by_id", args_json);
}

fn quotesCreate(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 2) {
        try out.print("usage: add quote --job <job-id> [--cost-min N] [--cost-max N] [--notes \"...\"]\n", .{});
        return;
    }
    var job_id: []const u8 = "";
    var notes: []const u8 = "";
    var cost_min: ?i64 = null;
    var cost_max: ?i64 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (i + 1 >= args.len) break;
        if (std.mem.eql(u8, args[i], "--job")) {
            job_id = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--notes")) {
            notes = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--cost-min")) {
            cost_min = std.fmt.parseInt(i64, args[i + 1], 10) catch null;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--cost-max")) {
            cost_max = std.fmt.parseInt(i64, args[i + 1], 10) catch null;
            i += 1;
        }
    }
    if (job_id.len == 0) {
        try out.print("usage: add quote --job <job-id> [--cost-min N] [--cost-max N] [--notes \"...\"]\n", .{});
        return;
    }
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"job_id\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, job_id, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (cost_min) |c| try buf.print(allocator, ",\"cost_min\":{d}", .{c});
    if (cost_max) |c| try buf.print(allocator, ",\"cost_max\":{d}", .{c});
    if (notes.len > 0) {
        try buf.appendSlice(allocator, ",\"notes\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, notes, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.append(allocator, '}');
    return dispatchQuotes(allocator, disp, out, "create", buf.items);
}

const QuoteFsmVerbSpec = struct { to_state: []const u8, cap: ?[]const u8, principal: []const u8 };

fn quotesTransitionGeneric(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, id: []const u8, spec: QuoteFsmVerbSpec) anyerror!void {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"id\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, id, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.appendSlice(allocator, ",\"to_state\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, spec.to_state, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.appendSlice(allocator, ",\"principal_kind\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, spec.principal, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (spec.cap) |c| {
        try buf.appendSlice(allocator, ",\"presented_cap\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, c, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.append(allocator, '}');
    return dispatchQuotes(allocator, disp, out, "transition", buf.items);
}

fn quotesPresent(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    const id = requireId(out, args, "usage: present quote <id>") orelse return;
    return quotesTransitionGeneric(allocator, disp, out, id, .{ .to_state = "presented", .cap = null, .principal = "operator" });
}

fn quotesAccept(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    const id = requireId(out, args, "usage: accept quote <id>") orelse return;
    return quotesTransitionGeneric(allocator, disp, out, id, .{ .to_state = "accepted", .cap = null, .principal = "service" });
}

fn quotesDecline(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    const id = requireId(out, args, "usage: decline quote <id> [--reason \"...\"]") orelse return;
    return quotesTransitionGeneric(allocator, disp, out, id, .{ .to_state = "rejected", .cap = null, .principal = "service" });
}

fn quotesExpire(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    const id = requireId(out, args, "usage: expire quote <id>") orelse return;
    return quotesTransitionGeneric(allocator, disp, out, id, .{ .to_state = "expired", .cap = null, .principal = "service" });
}

fn quotesSupersede(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    const id = requireId(out, args, "usage: supersede quote <id>") orelse return;
    return quotesTransitionGeneric(allocator, disp, out, id, .{ .to_state = "superseded", .cap = null, .principal = "operator" });
}

fn quotesTransition(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 2) {
        try out.print("usage: transition quote <id> <to_state> [--principal X] [--cap X]\n", .{});
        return;
    }
    const id = args[0];
    const to_state = args[1];
    var cap: ?[]const u8 = null;
    var principal: []const u8 = "operator";
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--cap") and i + 1 < args.len) {
            cap = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--principal") and i + 1 < args.len) {
            principal = args[i + 1];
            i += 1;
        }
    }
    return quotesTransitionGeneric(allocator, disp, out, id, .{ .to_state = to_state, .cap = cap, .principal = principal });
}

fn dispatchQuotes(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, cmd: []const u8, args_json: []const u8) anyerror!void {
    _ = allocator;
    const ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "in_process" },
    };
    var result = disp.dispatch(&ctx, "quotes", cmd, args_json) catch |err| {
        try out.print("quotes.{s}: dispatch failed: {s}\n", .{ cmd, @errorName(err) });
        return;
    };
    defer result.deinit();
    if (result.payload.len > 0) try out.print("{s}\n", .{result.payload});
}

// ══ invoices (C4 PR-R3f) ═════════════════════════════════════════════════════

fn invoicesFind(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    var job_id_filter: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--job-id") and i + 1 < args.len) {
            job_id_filter = args[i + 1];
            i += 1;
        }
    }
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    if (job_id_filter) |s| {
        try buf.appendSlice(allocator, "{\"job_id\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, s, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
        try buf.append(allocator, '}');
    } else {
        try buf.appendSlice(allocator, "{}");
    }
    return dispatchInvoices(allocator, disp, out, "find", buf.items);
}

fn invoicesFindById(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 1) {
        try out.print("usage: find invoice <id>\n", .{});
        return;
    }
    var args_buf: [256]u8 = undefined;
    const args_json = std.fmt.bufPrint(&args_buf, "{{\"id\":\"{s}\"}}", .{args[0]}) catch "{}";
    return dispatchInvoices(allocator, disp, out, "find_by_id", args_json);
}

fn invoicesCreate(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 2) {
        try out.print("usage: add invoice --job <job-id> [--amount N] [--notes \"...\"]\n", .{});
        return;
    }
    var job_id: []const u8 = "";
    var notes: []const u8 = "";
    var amount: ?i64 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (i + 1 >= args.len) break;
        if (std.mem.eql(u8, args[i], "--job")) {
            job_id = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--notes")) {
            notes = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--amount")) {
            amount = std.fmt.parseInt(i64, args[i + 1], 10) catch null;
            i += 1;
        }
    }
    if (job_id.len == 0) {
        try out.print("usage: add invoice --job <job-id> [--amount N] [--notes \"...\"]\n", .{});
        return;
    }
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"job_id\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, job_id, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (amount) |a| try buf.print(allocator, ",\"amount\":{d}", .{a});
    if (notes.len > 0) {
        try buf.appendSlice(allocator, ",\"notes\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, notes, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.append(allocator, '}');
    return dispatchInvoices(allocator, disp, out, "create", buf.items);
}

const InvoiceFsmVerbSpec = struct { to_state: []const u8, cap: ?[]const u8, principal: []const u8, amount_paid: ?i64 = null };

fn invoicesTransitionGeneric(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, id: []const u8, spec: InvoiceFsmVerbSpec) anyerror!void {
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"id\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, id, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.appendSlice(allocator, ",\"to_state\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, spec.to_state, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.appendSlice(allocator, ",\"principal_kind\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, spec.principal, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (spec.cap) |c| {
        try buf.appendSlice(allocator, ",\"presented_cap\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, c, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (spec.amount_paid) |ap| try buf.print(allocator, ",\"amount_paid\":{d}", .{ap});
    try buf.append(allocator, '}');
    return dispatchInvoices(allocator, disp, out, "transition", buf.items);
}

fn invoicesSend(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    const id = requireId(out, args, "usage: send invoice <id>") orelse return;
    return invoicesTransitionGeneric(allocator, disp, out, id, .{ .to_state = "sent", .cap = null, .principal = "operator" });
}

fn invoicesMark(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 2) {
        try out.print("usage: mark invoice <paid|partial|viewed|overdue> <id> [--amount N]\n", .{});
        return;
    }
    const new_state = args[0];
    const id = args[1];
    var amount: ?i64 = null;
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--amount") and i + 1 < args.len) {
            amount = std.fmt.parseInt(i64, args[i + 1], 10) catch null;
            i += 1;
        }
    }
    if (!std.mem.eql(u8, new_state, "paid") and !std.mem.eql(u8, new_state, "partial") and
        !std.mem.eql(u8, new_state, "viewed") and !std.mem.eql(u8, new_state, "overdue"))
    {
        try out.print("mark invoice: unknown state '{s}'.  Try paid|partial|viewed|overdue.\n", .{new_state});
        return;
    }
    return invoicesTransitionGeneric(allocator, disp, out, id, .{ .to_state = new_state, .cap = null, .principal = "service", .amount_paid = amount });
}

fn invoicesCancel(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    const id = requireId(out, args, "usage: cancel invoice <id>") orelse return;
    return invoicesTransitionGeneric(allocator, disp, out, id, .{ .to_state = "cancelled", .cap = null, .principal = "operator" });
}

fn invoicesTransition(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 2) {
        try out.print("usage: transition invoice <id> <to_state> [--principal X] [--cap X]\n", .{});
        return;
    }
    const id = args[0];
    const to_state = args[1];
    var cap: ?[]const u8 = null;
    var principal: []const u8 = "operator";
    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--cap") and i + 1 < args.len) {
            cap = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--principal") and i + 1 < args.len) {
            principal = args[i + 1];
            i += 1;
        }
    }
    return invoicesTransitionGeneric(allocator, disp, out, id, .{ .to_state = to_state, .cap = cap, .principal = principal });
}

fn dispatchInvoices(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, cmd: []const u8, args_json: []const u8) anyerror!void {
    _ = allocator;
    const ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "in_process" },
    };
    var result = disp.dispatch(&ctx, "invoices", cmd, args_json) catch |err| {
        try out.print("invoices.{s}: dispatch failed: {s}\n", .{ cmd, @errorName(err) });
        return;
    };
    defer result.deinit();
    if (result.payload.len > 0) try out.print("{s}\n", .{result.payload});
}

// ══ attachments (C4 PR-R3g) ══════════════════════════════════════════════════

fn attachmentsFind(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    var visit_id_filter: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--visit-id") and i + 1 < args.len) {
            visit_id_filter = args[i + 1];
            i += 1;
        }
    }
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    if (visit_id_filter) |s| {
        try buf.appendSlice(allocator, "{\"visit_id\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, s, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
        try buf.append(allocator, '}');
    } else {
        try buf.appendSlice(allocator, "{}");
    }
    return dispatchAttachments(allocator, disp, out, "find", buf.items);
}

fn attachmentsFindById(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    if (args.len < 1) {
        try out.print("usage: find attachment <id>\n", .{});
        return;
    }
    var args_buf: [256]u8 = undefined;
    const args_json = std.fmt.bufPrint(&args_buf, "{{\"id\":\"{s}\"}}", .{args[0]}) catch "{}";
    return dispatchAttachments(allocator, disp, out, "find_by_id", args_json);
}

fn attachmentsCreate(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, args: []const []const u8) anyerror!void {
    const usage =
        "usage: add attachment --visit <id> --kind <kind> --content-hash <hex64> " ++
        "--size <bytes> --mime <type> --captured-at <iso> --by-cert <hex32> " ++
        "[--caption \"...\"]\n" ++
        "       kind ∈ photo, voice_memo, gps_pin, file_other\n";
    if (args.len < 14) {
        try out.print("{s}", .{usage});
        return;
    }
    var visit_id: []const u8 = "";
    var kind: []const u8 = "";
    var content_hash: []const u8 = "";
    var size_str: []const u8 = "";
    var mime: []const u8 = "";
    var captured_at: []const u8 = "";
    var by_cert: []const u8 = "";
    var caption: []const u8 = "";
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (i + 1 >= args.len) break;
        if (std.mem.eql(u8, args[i], "--visit")) {
            visit_id = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--kind")) {
            kind = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--content-hash")) {
            content_hash = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--size")) {
            size_str = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--mime")) {
            mime = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--captured-at")) {
            captured_at = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--by-cert")) {
            by_cert = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--caption")) {
            caption = args[i + 1];
            i += 1;
        }
    }
    if (visit_id.len == 0 or kind.len == 0 or content_hash.len == 0 or
        size_str.len == 0 or mime.len == 0 or captured_at.len == 0 or by_cert.len == 0)
    {
        try out.print("{s}", .{usage});
        return;
    }
    const content_size = std.fmt.parseInt(i64, size_str, 10) catch {
        try out.print("add attachment: --size must be a non-negative integer\n", .{});
        return;
    };
    var buf: std.ArrayList(u8) = .{};
    defer buf.deinit(allocator);
    try buf.appendSlice(allocator, "{\"visit_id\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, visit_id, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.appendSlice(allocator, ",\"kind\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, kind, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.appendSlice(allocator, ",\"content_hash\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, content_hash, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.print(allocator, ",\"content_size\":{d}", .{content_size});
    try buf.appendSlice(allocator, ",\"mime_type\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, mime, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.appendSlice(allocator, ",\"captured_at\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, captured_at, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.appendSlice(allocator, ",\"captured_by_cert_id\":");
    {
        const enc = try std.json.Stringify.valueAlloc(allocator, by_cert, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    if (caption.len > 0) {
        try buf.appendSlice(allocator, ",\"caption\":");
        const enc = try std.json.Stringify.valueAlloc(allocator, caption, .{});
        defer allocator.free(enc);
        try buf.appendSlice(allocator, enc);
    }
    try buf.append(allocator, '}');
    return dispatchAttachments(allocator, disp, out, "create_metadata", buf.items);
}

fn dispatchAttachments(allocator: std.mem.Allocator, disp: *dispatcher_mod.Dispatcher, out: *const Output, cmd: []const u8, args_json: []const u8) anyerror!void {
    _ = allocator;
    const ctx: dispatcher_mod.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher_mod.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "in_process" },
    };
    var result = disp.dispatch(&ctx, "attachments", cmd, args_json) catch |err| {
        try out.print("attachments.{s}: dispatch failed: {s}\n", .{ cmd, @errorName(err) });
        return;
    };
    defer result.deinit();
    if (result.payload.len > 0) try out.print("{s}\n", .{result.payload});
}

```
