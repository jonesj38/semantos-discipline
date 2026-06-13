---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/cli.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.249207+00:00
---

# runtime/semantos-brain/src/cli.zig

```zig
// Phase Brain 1 — Lifecycle CLI dispatcher (façade).
//
// Reference: docs/design/WALLET-SHELL-VPS-SUBSTRATE.md §3 (Brain 1 deliverable 5).
//
// This file used to be a 9067-line monolith.  The cli-modularize refactor
// (Moves 1-11) extracted every cmd verb into a per-cluster file under
// src/cli/.  What remains here is:
//
//   • the Command enum + parseCommand (the argv→verb mapping)
//   • a re-export block for each extracted module
//
// External callers (main.zig, tests/*.zig) continue to reach every verb
// and helper as `cli.X` via the re-exports.  Adding a new cmd verb:
//
//   1. Write `pub fn cmdFoo(...) !ExitCode` in src/cli/<cluster>.zig.
//   2. Add `pub const cmdFoo = cli_<cluster>.cmdFoo;` in the re-export
//      block below.
//   3. Add the verb to the Command enum + parseCommand if it's a
//      top-level brain subcommand.

const std = @import("std");

// Move 1 — common helpers (Output, ExitCode, path/JSON utility fns).
const cli_common = @import("cli/common.zig");
pub const ExitCode = cli_common.ExitCode;
pub const Output = cli_common.Output;
pub const resolveDataDirFromConfig = cli_common.resolveDataDirFromConfig;
pub const expandHome = cli_common.expandHome;

// Move 2 — lifecycle verbs (help/version/init/status/hash/start/stop +
// VERSION + HELP_TEXT).
const cli_lifecycle = @import("cli/lifecycle.zig");
pub const VERSION = cli_lifecycle.VERSION;
pub const HELP_TEXT = cli_lifecycle.HELP_TEXT;
pub const cmdHelp = cli_lifecycle.cmdHelp;
pub const cmdVersion = cli_lifecycle.cmdVersion;
pub const cmdInit = cli_lifecycle.cmdInit;
pub const cmdStatus = cli_lifecycle.cmdStatus;
pub const cmdHash = cli_lifecycle.cmdHash;
pub const cmdStart = cli_lifecycle.cmdStart;
pub const cmdStop = cli_lifecycle.cmdStop;

// Move 3 — site verbs (WSITE1: brain site init/validate/list).
const cli_site = @import("cli/site.zig");
pub const cmdSite = cli_site.cmdSite;

// Move 4 — bearer-token verbs (issue/list/revoke).
const cli_bearer = @import("cli/bearer.zig");
pub const cmdBearer = cli_bearer.cmdBearer;

// Move 5 — headers verbs (tip/sync/reset/serve).
const cli_headers = @import("cli/headers.zig");
pub const cmdHeaders = cli_headers.cmdHeaders;

// Move 6 — device verbs (init/pair/claim/list/revoke).
const cli_device = @import("cli/device.zig");
pub const cmdDevice = cli_device.cmdDevice;

// Move 7 — wallet/payment verbs (revenue/sweep/outputs/sessions/refund).
const cli_wallet = @import("cli/wallet.zig");
pub const cmdRevenue = cli_wallet.cmdRevenue;
pub const cmdSweep = cli_wallet.cmdSweep;
pub const cmdOutputs = cli_wallet.cmdOutputs;
pub const cmdSessions = cli_wallet.cmdSessions;
pub const cmdRefund = cli_wallet.cmdRefund;

// Move 8 — extension/signer/quarantine verbs (D-W2 Phases 1+3).
const cli_extension = @import("cli/extension.zig");
pub const cmdExtension = cli_extension.cmdExtension;
pub const cmdSigner = cli_extension.cmdSigner;

// Move 9 — operator-facing verbs (llm/provision-tenant/resign-pending/
// export-/exit-operator/orphan-streams/domain-allow/-disallow/caddy-ask/
// sni-map/wrapped-dek/site-preview/-publish).
const cli_operator = @import("cli/operator.zig");
pub const cmdLlm = cli_operator.cmdLlm;
pub const cmdProvisionTenant = cli_operator.cmdProvisionTenant;
pub const cmdResignPending = cli_operator.cmdResignPending;
pub const cmdExportOperator = cli_operator.cmdExportOperator;
pub const cmdExitOperator = cli_operator.cmdExitOperator;
pub const cmdOrphanStreams = cli_operator.cmdOrphanStreams;
pub const cmdDomainAllow = cli_operator.cmdDomainAllow;
pub const cmdDomainDisallow = cli_operator.cmdDomainDisallow;
pub const cmdCaddyAsk = cli_operator.cmdCaddyAsk;
pub const cmdSniMap = cli_operator.cmdSniMap;
pub const cmdWrappedDek = cli_operator.cmdWrappedDek;
pub const cmdSitePreview = cli_operator.cmdSitePreview;
pub const cmdSitePublish = cli_operator.cmdSitePublish;
pub const resignSites = cli_operator.resignSites;
pub const resignCustomers = cli_operator.resignCustomers;
pub const resignJobs = cli_operator.resignJobs;
pub const resignAttachments = cli_operator.resignAttachments;

// Move 10 — cmdRepl + ReplBackend (Brain 3 REPL boot).  Distinct from
// src/repl.zig, the REPL impl library.
const cli_repl = @import("cli/repl.zig");
pub const cmdRepl = cli_repl.cmdRepl;
pub const ReplBackend = cli_repl.ReplBackend;

// Move 11 — cmdServe (WSITE2 HTTP/WSS site server).
const cli_serve = @import("cli/serve.zig");
pub const cmdServe = cli_serve.cmdServe;

// Wave 9 follow-up — `brain intent <subcmd>` shims (capture / tail /
// cascade / show / fixturize). Wraps the TS `tools/intent-trace/` CLI
// + provides the canonical capture sink that maintains the last-trace
// pointer downstream verbs consume.
const cli_intent = @import("cli/intent.zig");
pub const cmdIntent = cli_intent.cmdIntent;

// Wave 9 follow-up — `brain cartridge <subcmd>`. Today: `cartridge
// new <name>` wraps `tools/cartridge-scaffold/bin/scaffold.ts` and
// resolves `--from-last` against the intent dir's pointer file.
const cli_cartridge = @import("cli/cartridge.zig");
pub const cmdCartridge = cli_cartridge.cmdCartridge;

// D-network-messagebox-first-class — `brain msg <subcmd>` thin HTTP
// wrapper around /api/v1/messages/{send,list,ack} for shell-driven
// brain-to-brain messaging.
const cli_msg = @import("cli/msg.zig");
pub const cmdMsg = cli_msg.cmdMsg;

pub const Command = enum {
    init,
    status,
    hash,
    start,
    stop,
    repl,
    site,
    serve,
    revenue,
    sweep,
    outputs,
    sessions,
    refund,
    headers,
    bearer,
    device,
    llm,
    @"provision-tenant",
    extension,
    signer,
    @"resign-pending",
    @"export-operator",
    @"exit-operator",
    @"orphan-streams",
    @"domain-allow",
    @"domain-disallow",
    @"caddy-ask",
    @"sni-map",
    @"wrapped-dek",
    @"site-preview",
    @"site-publish",
    intent,
    cartridge,
    msg,
    help,
    version,
};

pub fn parseCommand(arg: []const u8) ?Command {
    if (std.mem.eql(u8, arg, "init")) return .init;
    if (std.mem.eql(u8, arg, "status")) return .status;
    if (std.mem.eql(u8, arg, "hash")) return .hash;
    if (std.mem.eql(u8, arg, "start")) return .start;
    if (std.mem.eql(u8, arg, "stop")) return .stop;
    if (std.mem.eql(u8, arg, "repl")) return .repl;
    if (std.mem.eql(u8, arg, "site")) return .site;
    if (std.mem.eql(u8, arg, "serve")) return .serve;
    if (std.mem.eql(u8, arg, "revenue")) return .revenue;
    if (std.mem.eql(u8, arg, "sweep")) return .sweep;
    if (std.mem.eql(u8, arg, "outputs")) return .outputs;
    if (std.mem.eql(u8, arg, "sessions")) return .sessions;
    if (std.mem.eql(u8, arg, "refund")) return .refund;
    if (std.mem.eql(u8, arg, "headers")) return .headers;
    if (std.mem.eql(u8, arg, "bearer")) return .bearer;
    if (std.mem.eql(u8, arg, "device")) return .device;
    if (std.mem.eql(u8, arg, "llm")) return .llm;
    if (std.mem.eql(u8, arg, "provision-tenant")) return .@"provision-tenant";
    if (std.mem.eql(u8, arg, "extension")) return .extension;
    if (std.mem.eql(u8, arg, "signer")) return .signer;
    if (std.mem.eql(u8, arg, "resign-pending")) return .@"resign-pending";
    if (std.mem.eql(u8, arg, "export-operator")) return .@"export-operator";
    if (std.mem.eql(u8, arg, "exit-operator")) return .@"exit-operator";
    if (std.mem.eql(u8, arg, "orphan-streams")) return .@"orphan-streams";
    if (std.mem.eql(u8, arg, "domain-allow")) return .@"domain-allow";
    if (std.mem.eql(u8, arg, "domain-disallow")) return .@"domain-disallow";
    if (std.mem.eql(u8, arg, "caddy-ask")) return .@"caddy-ask";
    if (std.mem.eql(u8, arg, "sni-map")) return .@"sni-map";
    if (std.mem.eql(u8, arg, "wrapped-dek")) return .@"wrapped-dek";
    if (std.mem.eql(u8, arg, "site-preview")) return .@"site-preview";
    if (std.mem.eql(u8, arg, "site-publish")) return .@"site-publish";
    if (std.mem.eql(u8, arg, "intent")) return .intent;
    if (std.mem.eql(u8, arg, "cartridge")) return .cartridge;
    if (std.mem.eql(u8, arg, "msg")) return .msg;
    if (std.mem.eql(u8, arg, "help") or std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) return .help;
    if (std.mem.eql(u8, arg, "version") or std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-V")) return .version;
    return null;
}

```
