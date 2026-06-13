---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/tessera/brain/demo/tessera_demo.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.640660+00:00
---

# cartridges/tessera/brain/demo/tessera_demo.zig

```zig
// tessera_demo — grape-to-glass narrative demo.
//
// Runs the SAME walker / store code paths the brain uses, but
// in-memory and standalone — no brain process required. Emits a
// "wine life" narrative for a non-technical sommelier audience.
//
// Modes:
//   tessera-demo               → CLI narrative (Unicode borders)
//   tessera-demo --html        → HTML wine card (stdout; redirect to file)
//
// The substance is identical in both modes:
//   • One bottle's full life — harvest → rack → blend → bottle →
//     case → transfer → confirm → cold-chain temp log → consumer scan.
//   • Real cell_ids minted by the same encoder the brain uses; care-
//     event cell payloads carry temperature / location / observer.
//   • A Care Score derivation that names the heat excursion: WHERE
//     in the supply chain a bottle was cooked.
//   • Three "the substrate refuses" demonstrations: tamper-twice,
//     bottle-twice, blend-not-conserved.
//
// The wedge for a sommelier (e.g. at a Dan Murphy's): cooked bottles
// arrive constantly. The current world has no proof of WHERE the
// damage happened — so the vintner gets blamed. Tessera makes the
// transit segment that cooked the wine specifically identifiable.

const std = @import("std");
const verb_dispatcher = @import("verb_dispatcher");
const tessera_store = @import("tessera_store");
const tessera_walkers = @import("tessera_walkers");

const Format = enum { cli, html };

const Mint = struct {
    domain: []const u8,
    label: []const u8,
};

/// One row of the care-chain temperature log. The substrate cell
/// minted by each care-event carries `temperature_c` + `location` in
/// its JSON payload (the brain walker only validates `containerId`;
/// extra fields ride along inside the cell, recoverable on scan).
const CareCheckpoint = struct {
    when: []const u8,
    /// Empty string when no temperature was logged (a thermo-sticker
    /// observation has no reading — just a visual confirmation).
    temperature_c: ?u8,
    location: []const u8,
    /// "" → normal, "EXCURSION" → above threshold, "CONFIRMED" →
    /// sticker-flipped corroborating reading.
    flag: []const u8,
};

const THERMO_THRESHOLD_C: u8 = 28;
const CARE_SCORE_MAX: u8 = 10;
/// Each excursion or sticker-flip subtracts 2 from the perfect score.
const PENALTY_PER_EXCURSION: u8 = 2;

fn computeCareScore(log: []const CareCheckpoint) u8 {
    var score: i32 = CARE_SCORE_MAX;
    for (log) |c| {
        const flagged = !std.mem.eql(u8, c.flag, "");
        if (flagged) score -= PENALTY_PER_EXCURSION;
    }
    if (score < 0) score = 0;
    return @intCast(score);
}

const DemoCtx = struct {
    allocator: std.mem.Allocator,
    reg: *verb_dispatcher.Registry,
    store: *tessera_store.Store,
    out: *std.Io.Writer,
    format: Format,
    /// HTML state — true between `narrate()` (opens `<li>`) and the
    /// next `narrate()` / section close (which both close it). Lets a
    /// single step carry multiple dispatches + a trailing note without
    /// the `<li>` element getting tangled.
    li_open: bool = false,

    fn closeOpenLi(self: *DemoCtx) !void {
        if (self.format != .html or !self.li_open) return;
        try self.out.writeAll("    </li>\n");
        self.li_open = false;
    }

    fn openDoc(self: *DemoCtx) !void {
        switch (self.format) {
            .cli => {},
            .html => try self.out.writeAll(HTML_HEADER),
        }
    }

    fn closeDoc(self: *DemoCtx) !void {
        switch (self.format) {
            .cli => {},
            .html => try self.out.writeAll(HTML_FOOTER),
        }
    }

    fn openVintage(self: *DemoCtx) !void {
        switch (self.format) {
            .cli => {
                try self.out.writeAll("\n");
                try self.out.writeAll("═══════════════════════════════════════════════════════════════\n");
                try self.out.writeAll("    Bottle #7 of Lot 2024-PINOT-1 · Alice's North Block\n");
                try self.out.writeAll("    the verifiable life of a wine\n");
                try self.out.writeAll("═══════════════════════════════════════════════════════════════\n\n");
            },
            .html => try self.out.writeAll(
                \\<section class="vintage">
                \\  <h1>Bottle #7 of Lot 2024-PINOT-1</h1>
                \\  <h2>Alice's North Block · the verifiable life of a wine</h2>
                \\  <ol class="chain">
                \\
            ),
        }
    }

    fn closeVintage(self: *DemoCtx) !void {
        try self.closeOpenLi();
        switch (self.format) {
            .cli => try self.out.writeAll("\n"),
            .html => try self.out.writeAll("  </ol>\n</section>\n"),
        }
    }

    fn openRefusalsSection(self: *DemoCtx) !void {
        switch (self.format) {
            .cli => {
                try self.out.writeAll("\n");
                try self.out.writeAll("───────────────────────────────────────────────────────────────\n");
                try self.out.writeAll("    what the substrate refuses\n");
                try self.out.writeAll("───────────────────────────────────────────────────────────────\n\n");
            },
            .html => try self.out.writeAll(
                \\<section class="refusals">
                \\  <h2>what the substrate refuses</h2>
                \\  <ol class="chain">
                \\
            ),
        }
    }

    fn closeRefusalsSection(self: *DemoCtx) !void {
        try self.closeOpenLi();
        switch (self.format) {
            .cli => try self.out.writeAll("\n"),
            .html => try self.out.writeAll("  </ol>\n</section>\n"),
        }
    }

    fn openColdChainSection(self: *DemoCtx) !void {
        try self.closeOpenLi();
        switch (self.format) {
            .cli => {
                try self.out.writeAll("\n");
                try self.out.writeAll("───────────────────────────────────────────────────────────────\n");
                try self.out.writeAll("    the cold chain · every checkpoint logged\n");
                try self.out.writeAll("───────────────────────────────────────────────────────────────\n\n");
            },
            .html => try self.out.writeAll(
                \\<section class="cold-chain">
                \\  <h2>the cold chain · every checkpoint logged</h2>
                \\  <ol class="chain">
                \\
            ),
        }
    }

    fn closeColdChainSection(self: *DemoCtx) !void {
        try self.closeOpenLi();
        switch (self.format) {
            .cli => try self.out.writeAll("\n"),
            .html => try self.out.writeAll("  </ol>\n</section>\n"),
        }
    }

    /// Emit a CareScore summary block derived from `log`. The score is
    /// computed by the demo (the substrate does not yet expose a
    /// care-score query verb) but the inputs are the same payloads the
    /// substrate cells carry — temperature, location, thermo-flag.
    fn careScore(self: *DemoCtx, log: []const CareCheckpoint) !void {
        try self.closeOpenLi();
        const score = computeCareScore(log);
        var excursion_loc: []const u8 = "";
        var excursion_when: []const u8 = "";
        for (log) |c| {
            if (std.mem.eql(u8, c.flag, "EXCURSION")) {
                excursion_loc = c.location;
                excursion_when = c.when;
                break;
            }
        }

        switch (self.format) {
            .cli => {
                try self.out.print("───────────────────── Care Score · {d} / {d} ─────────────────────\n", .{ score, CARE_SCORE_MAX });
                if (excursion_loc.len > 0) {
                    try self.out.print("    One heat excursion detected · {s}, {s}\n\n", .{ excursion_loc, excursion_when });
                } else {
                    try self.out.writeAll("    Cold chain clean · no excursions\n\n");
                }
                for (log) |c| {
                    if (c.temperature_c) |t| {
                        const flag = if (std.mem.eql(u8, c.flag, "EXCURSION"))
                            "⚠ EXCURSION"
                        else if (std.mem.eql(u8, c.flag, "CONFIRMED"))
                            "⚠ confirmed"
                        else
                            "✓";
                        try self.out.print("    {s:<10} {d: >3} °C   {s: <40} {s}\n", .{ c.when, t, c.location, flag });
                    } else {
                        const flag = if (std.mem.eql(u8, c.flag, "")) "—" else "⚠ confirmed";
                        try self.out.print("    {s:<10}    —    {s: <40} {s}\n", .{ c.when, c.location, flag });
                    }
                }
                try self.out.writeAll("\n");
                if (excursion_loc.len > 0) {
                    try self.out.writeAll("    If this bottle tastes oxidised, the chain proves WHERE.\n");
                    try self.out.print("    The damage happened at {s} on {s} — not at\n", .{ excursion_loc, excursion_when });
                    try self.out.writeAll("    Alice's vineyard, not at Dan Murphy's. Carrier liability.\n\n");
                }
                try self.out.writeAll("───────────────────────────────────────────────────────────────\n\n");
            },
            .html => {
                try self.out.writeAll(
                    \\<section class="care-score">
                    \\
                );
                try self.out.print("  <h2>Care Score · <span class=\"score\">{d} / {d}</span></h2>\n", .{ score, CARE_SCORE_MAX });
                if (excursion_loc.len > 0) {
                    try self.out.print("  <p class=\"verdict warn\">One heat excursion detected · {s}, {s}</p>\n", .{ excursion_loc, excursion_when });
                } else {
                    try self.out.writeAll("  <p class=\"verdict ok\">Cold chain clean · no excursions</p>\n");
                }
                try self.out.writeAll("  <table class=\"temp-log\">\n");
                try self.out.writeAll("    <thead><tr><th>date</th><th>temp</th><th>location</th><th></th></tr></thead>\n");
                try self.out.writeAll("    <tbody>\n");
                for (log) |c| {
                    const row_class = if (std.mem.eql(u8, c.flag, "EXCURSION"))
                        " class=\"excursion\""
                    else if (std.mem.eql(u8, c.flag, "CONFIRMED"))
                        " class=\"confirmed\""
                    else
                        "";
                    try self.out.print("      <tr{s}>", .{row_class});
                    try self.out.print("<td>{s}</td>", .{c.when});
                    if (c.temperature_c) |t| {
                        try self.out.print("<td>{d} °C</td>", .{t});
                    } else {
                        try self.out.writeAll("<td>—</td>");
                    }
                    try self.out.print("<td>{s}</td>", .{c.location});
                    const symbol = if (std.mem.eql(u8, c.flag, "EXCURSION"))
                        "⚠ EXCURSION"
                    else if (std.mem.eql(u8, c.flag, "CONFIRMED"))
                        "⚠ confirmed"
                    else
                        "✓";
                    try self.out.print("<td>{s}</td>", .{symbol});
                    try self.out.writeAll("</tr>\n");
                }
                try self.out.writeAll("    </tbody>\n  </table>\n");
                if (excursion_loc.len > 0) {
                    try self.out.print(
                        \\  <p class="conclusion">If this bottle tastes oxidised, the chain proves WHERE. The damage happened at <strong>{s}</strong> on <strong>{s}</strong> — not at Alice's vineyard, not at Dan Murphy's. Carrier liability.</p>
                        \\
                    , .{ excursion_loc, excursion_when });
                }
                try self.out.writeAll("</section>\n");
            },
        }
    }

    fn narrate(self: *DemoCtx, when: []const u8, headline: []const u8, body: []const u8) !void {
        try self.closeOpenLi();
        switch (self.format) {
            .cli => {
                try self.out.print("  {s} · {s}\n", .{ when, headline });
                try self.out.print("    {s}\n", .{body});
            },
            .html => {
                try self.out.writeAll("    <li class=\"step\">\n");
                try self.out.print("      <div class=\"when\">{s}</div>\n", .{when});
                try self.out.print("      <div class=\"headline\">{s}</div>\n", .{headline});
                try self.out.print("      <div class=\"body\">{s}</div>\n", .{body});
                self.li_open = true;
            },
        }
    }

    fn note(self: *DemoCtx, line: []const u8) !void {
        switch (self.format) {
            .cli => try self.out.print("    ↪ {s}\n\n", .{line}),
            .html => {
                try self.out.print("      <div class=\"note\">{s}</div>\n", .{line});
            },
        }
    }

    fn dispatch(self: *DemoCtx, verb: []const u8, params_json: []const u8, mint: Mint) !void {
        const body = try self.reg.dispatch(self.allocator, "tessera", verb, params_json);
        defer self.allocator.free(body);

        const ok = std.mem.indexOf(u8, body, "\"ok\":true") != null;
        if (!ok) {
            try self.out.print("    ⚠ unexpected refusal: {s}\n", .{body});
            return;
        }
        const cell_hex = cellIdOfBody(body);
        const display = if (cell_hex.len > 12) cell_hex[0..12] else cell_hex;

        switch (self.format) {
            .cli => {
                try self.out.print("    ✓ minted {s} · {s}\n", .{ mint.label, mint.domain });
                try self.out.print("      cell_id: {s}…\n\n", .{display});
            },
            .html => {
                try self.out.writeAll("      <div class=\"mint\">\n");
                try self.out.print("        <span class=\"verb\">✓ minted</span> {s}<br>\n", .{mint.label});
                try self.out.print("        <span class=\"domain\">domain id:</span> <code>{s}</code><br>\n", .{mint.domain});
                try self.out.print("        <span class=\"cellid\">substrate cell:</span> <code>{s}…</code>\n", .{display});
                try self.out.writeAll("      </div>\n");
            },
        }
    }

    fn dispatchExpectingRefusal(
        self: *DemoCtx,
        verb: []const u8,
        params_json: []const u8,
        explanation: []const u8,
    ) !void {
        const result = self.reg.dispatch(self.allocator, "tessera", verb, params_json) catch |e| {
            try self.out.print("    ⚠ dispatch error ({s})\n", .{@errorName(e)});
            return;
        };
        defer self.allocator.free(result);
        const refused = std.mem.indexOf(u8, result, "\"ok\":false") != null;
        const reason = reasonOfBody(result);
        if (!refused) {
            try self.out.print("    ⚠ expected refusal, got: {s}\n", .{result});
            return;
        }
        switch (self.format) {
            .cli => {
                try self.out.print("    ✗ REFUSED · reason=\"{s}\"\n", .{reason});
                try self.out.print("      {s}\n\n", .{explanation});
            },
            .html => {
                try self.out.writeAll("      <div class=\"refusal\">\n");
                try self.out.print("        <span class=\"verb refused\">✗ REFUSED</span> reason: <code>{s}</code><br>\n", .{reason});
                try self.out.print("        <div class=\"body\">{s}</div>\n", .{explanation});
                try self.out.writeAll("      </div>\n");
            },
        }
    }

    fn footer(self: *DemoCtx) !void {
        switch (self.format) {
            .cli => {
                try self.out.writeAll("───────────────────────────────────────────────────────────────\n");
                try self.out.writeAll("    Every cell above was minted by the same code path that\n");
                try self.out.writeAll("    runs in production. The IDs are real SHA-256 hashes of\n");
                try self.out.writeAll("    the substrate cell bytes — verifiable, unforgeable.\n");
                try self.out.writeAll("\n");
                try self.out.writeAll("    Tessera · care-chain provenance · grape to glass\n");
                try self.out.writeAll("───────────────────────────────────────────────────────────────\n");
            },
            .html => try self.out.writeAll(
                \\<footer>
                \\  <p>Every cell above was minted by the same code path that runs in
                \\  production. The IDs are real SHA-256 hashes of the substrate cell
                \\  bytes — verifiable, unforgeable.</p>
                \\  <p class="brand">Tessera · care-chain provenance · grape to glass</p>
                \\</footer>
                \\
            ),
        }
    }
};

// ─── main ────────────────────────────────────────────────────────────

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var format: Format = .cli;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--html")) format = .html;
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp();
            return;
        }
    }

    var store = tessera_store.Store.init(allocator);
    defer store.deinit();
    var state = tessera_walkers.State{ .store = &store };
    var reg = verb_dispatcher.Registry.init(allocator);
    defer reg.deinit();
    try tessera_walkers.registerAll(&reg, &state);

    var stdout_buf: [4096]u8 = undefined;
    var stdout_w = std.fs.File.stdout().writer(&stdout_buf);
    const out = &stdout_w.interface;

    var ctx = DemoCtx{
        .allocator = allocator,
        .reg = &reg,
        .store = &store,
        .out = out,
        .format = format,
    };

    try ctx.openDoc();
    try runStory(&ctx);
    try ctx.closeDoc();
    try out.flush();
}

fn printHelp() !void {
    var stdout_buf: [1024]u8 = undefined;
    var stdout_w = std.fs.File.stdout().writer(&stdout_buf);
    const out = &stdout_w.interface;
    try out.writeAll(
        \\tessera-demo — grape-to-glass narrative demo
        \\
        \\Usage:
        \\  tessera-demo            CLI narrative (formatted for terminal)
        \\  tessera-demo --html     HTML wine card to stdout
        \\
        \\Examples:
        \\  tessera-demo                    # read on the terminal
        \\  tessera-demo --html > card.html # leave-behind for a sommelier
        \\
    );
    try out.flush();
}

// ─── The story ───────────────────────────────────────────────────────

fn runStory(ctx: *DemoCtx) !void {
    try ctx.openVintage();

    try ctx.narrate(
        "March 2024",
        "Alice harvests her north block",
        "Lot 2024-PINOT-1 · 230 litres of Pinot Noir, hand-picked from a single block on Alice's small Mornington Peninsula vineyard.",
    );
    try ctx.dispatch(
        "tessera.harvest",
        "{\"lotId\":\"L2024-PINOT-1\",\"grower\":\"alice\",\"volumeMl\":230000,\"region\":\"Mornington Peninsula, VIC\"}",
        .{ .domain = "L2024-PINOT-1", .label = "grape-lot · 230 L" },
    );

    try ctx.narrate(
        "April 2024",
        "racked into two barriques",
        "Alice splits the lot across two oak regimes — half French, half American — for the malolactic fermentation.",
    );
    try ctx.dispatch(
        "tessera.rack",
        "{\"lotId\":\"L2024-PINOT-1\",\"barrelId\":\"Barrel-A\",\"volumeMl\":113000,\"cooperage\":\"French oak, 2nd-fill\"}",
        .{ .domain = "Barrel-A", .label = "barrel · 113 L · French oak (2nd-fill)" },
    );
    try ctx.dispatch(
        "tessera.rack",
        "{\"lotId\":\"L2024-PINOT-1\",\"barrelId\":\"Barrel-B\",\"volumeMl\":112000,\"cooperage\":\"American oak, new\"}",
        .{ .domain = "Barrel-B", .label = "barrel · 112 L · American oak (new)" },
    );
    try ctx.note("Five litres lost to pressings. The grape-lot is committed to oak.");

    try ctx.narrate(
        "October 2024",
        "blended into the final cuvée",
        "Six months in oak. Alice tastes both barrels, blends them into a single barrique to settle for bottling.",
    );
    try ctx.dispatch(
        "tessera.blend",
        "{\"outBarrelId\":\"Barrel-C\",\"inBarrelIds\":[\"Barrel-A\",\"Barrel-B\"],\"declaredOutMl\":225000,\"cuveeName\":\"Pinot Noir 2024 · North Block\"}",
        .{ .domain = "Barrel-C", .label = "cuvée barrique · 225 L = 113 + 112 ✓" },
    );
    try ctx.note("Barrels A and B are spent. The cuvée exists only in Barrel C.");

    try ctx.narrate(
        "March 2025",
        "bottled · sealed with tamper-evident NFC chips",
        "300 bottles of 750 ml from the 225 L barrique. We follow 12 of them (Bottle #7 is the one your sommelier friend will scan).",
    );
    try ctx.dispatch(
        "tessera.bottle",
        "{\"barrelId\":\"Barrel-C\",\"bottleIds\":[\"B1\",\"B2\",\"B3\",\"B4\",\"B5\",\"B6\",\"B7\",\"B8\",\"B9\",\"B10\",\"B11\",\"B12\"],\"format\":\"750ml\"}",
        .{ .domain = "B7", .label = "Bottle #7 · 750 ml · NFC-sealed" },
    );
    try ctx.note("Barrel C is now spent. Each bottle has a unique, unforgeable identity.");

    try ctx.narrate(
        "March 2025",
        "assembled into a sample case for Dan Murphy's",
        "Six bottles (B1..B6) go into Case-Alpha — destined for Dan Murphy's Cellar Reserve program, Perth.",
    );
    try ctx.dispatch(
        "tessera.assemble-case",
        "{\"caseId\":\"Case-Alpha\",\"holder\":\"alice\",\"bottleIds\":[\"B1\",\"B2\",\"B3\",\"B4\",\"B5\",\"B6\"],\"destination\":\"Dan Murphy's Perth\"}",
        .{ .domain = "Case-Alpha", .label = "case · 6 bottles · holder=alice" },
    );

    try ctx.narrate(
        "April 2025",
        "Alice transfers custody to Bob (Melbourne distributor)",
        "The case leaves the vineyard. Bob's logistics chain will take it across the country to Perth.",
    );
    try ctx.dispatch(
        "tessera.transfer-custody",
        "{\"id\":\"Case-Alpha\",\"from\":\"alice\",\"to\":\"bob-melbourne-dist\"}",
        .{ .domain = "Case-Alpha", .label = "case · in-flight (alice → bob)" },
    );

    try ctx.narrate(
        "April 2025",
        "Bob confirms receipt at his Melbourne climate-controlled warehouse",
        "Bob's signature closes the first custody hop. From here, road haul: Melbourne → Adelaide → across the Nullarbor → Perth (~3,400 km).",
    );
    try ctx.dispatch(
        "tessera.confirm-receipt",
        "{\"id\":\"Case-Alpha\",\"who\":\"bob-melbourne-dist\"}",
        .{ .domain = "Case-Alpha", .label = "case · holder=bob (settled)" },
    );

    try ctx.closeVintage();

    // ── The cold chain ──────────────────────────────────────────────
    try ctx.openColdChainSection();

    try ctx.narrate(
        "Apr 14, 2025",
        "logger reading · Alice's cellar (pre-pickup)",
        "Datalogger sealed inside Case-Alpha records ambient at Alice's underground cellar.",
    );
    try ctx.dispatch(
        "tessera.record-care-event",
        "{\"containerId\":\"Case-Alpha\",\"temperatureC\":14,\"location\":\"Alice's cellar, Mornington Peninsula\",\"observedAt\":\"2025-04-14T07:00:00+10:00\",\"loggerSerial\":\"TEMP-A12\"}",
        .{ .domain = "Case-Alpha", .label = "care-event · 14 °C · normal" },
    );

    try ctx.narrate(
        "Apr 18, 2025",
        "logger reading · Bob's Melbourne warehouse",
        "Climate-controlled storage. Reading is stable.",
    );
    try ctx.dispatch(
        "tessera.record-care-event",
        "{\"containerId\":\"Case-Alpha\",\"temperatureC\":16,\"location\":\"Bob's Melbourne climate-controlled warehouse\",\"observedAt\":\"2025-04-18T11:00:00+10:00\",\"loggerSerial\":\"TEMP-A12\"}",
        .{ .domain = "Case-Alpha", .label = "care-event · 16 °C · normal" },
    );

    try ctx.narrate(
        "Apr 21, 2025",
        "loaded onto the cross-country freight",
        "Case-Alpha goes on a road train bound for Perth via the Nullarbor. Bob's last touchpoint until Perth receives.",
    );

    try ctx.narrate(
        "Apr 23, 2025",
        "logger reading · mid-Nullarbor truck stop",
        "The trailer's refrigeration unit failed somewhere west of Eucla. By the time the next checkpoint reads, the case has been at peak afternoon temperatures.",
    );
    try ctx.dispatch(
        "tessera.record-care-event",
        "{\"containerId\":\"Case-Alpha\",\"temperatureC\":33,\"location\":\"Mid-Nullarbor truck stop (Eucla, WA)\",\"observedAt\":\"2025-04-23T15:42:00+08:00\",\"loggerSerial\":\"TEMP-A12\",\"severity\":\"high\"}",
        .{ .domain = "Case-Alpha", .label = "care-event · 33 °C · EXCURSION" },
    );

    try ctx.narrate(
        "Apr 24, 2025",
        "thermo-sticker flipped orange · dock-handler confirms by eye",
        "Tessera ships every case with a heat-indicator dye sticker (irreversible above 28 °C). The driver notices it at the next stop and flags the load.",
    );
    try ctx.dispatch(
        "tessera.thermo-flag",
        "{\"containerId\":\"Case-Alpha\",\"stickerThresholdC\":28,\"observedAt\":\"2025-04-24T09:15:00+08:00\",\"observer\":\"driver-jb-roadtrain-77\",\"note\":\"sticker visibly flipped orange\"}",
        .{ .domain = "Case-Alpha", .label = "care-event · sticker flipped · CONFIRMED" },
    );

    try ctx.narrate(
        "Apr 27, 2025",
        "logger reading · Dan Murphy's Perth DC",
        "Back inside climate control. The case is in spec from here on — but the damage is recorded.",
    );
    try ctx.dispatch(
        "tessera.record-care-event",
        "{\"containerId\":\"Case-Alpha\",\"temperatureC\":17,\"location\":\"Dan Murphy's Perth distribution centre\",\"observedAt\":\"2025-04-27T08:30:00+08:00\",\"loggerSerial\":\"TEMP-A12\"}",
        .{ .domain = "Case-Alpha", .label = "care-event · 17 °C · normal" },
    );

    try ctx.closeColdChainSection();

    // ── Consumer scan + care score ──────────────────────────────────
    try ctx.openVintage();
    try ctx.narrate(
        "May 2025",
        "the sommelier scans Bottle #7",
        "At Dan Murphy's Perth, your friend taps her phone to the NFC seal. The full chain materialises — including every cold-chain reading.",
    );
    try ctx.dispatch(
        "tessera.consumer-scan",
        "{\"bottleId\":\"B7\",\"scannedAt\":\"2025-05-02T18:10:00+08:00\",\"location\":\"Dan Murphy's Perth · tasting bench\"}",
        .{ .domain = "B7", .label = "scan-event · sommelier viewed the chain" },
    );
    try ctx.closeVintage();

    const care_log = [_]CareCheckpoint{
        .{ .when = "Apr 14",   .temperature_c = 14, .location = "Alice's cellar, Mornington Peninsula",   .flag = "" },
        .{ .when = "Apr 18",   .temperature_c = 16, .location = "Bob's Melbourne climate-controlled WH",  .flag = "" },
        .{ .when = "Apr 23",   .temperature_c = 33, .location = "Mid-Nullarbor truck stop (Eucla, WA)",   .flag = "EXCURSION" },
        .{ .when = "Apr 24",   .temperature_c = null, .location = "thermo-sticker flipped orange",        .flag = "CONFIRMED" },
        .{ .when = "Apr 27",   .temperature_c = 17, .location = "Dan Murphy's Perth distribution centre", .flag = "" },
    };
    try ctx.careScore(care_log[0..]);

    // ── What the substrate refuses ────────────────────────────────
    try ctx.openRefusalsSection();

    try ctx.narrate(
        "Demonstration #1",
        "the tamper-loop is one-shot",
        "Once a tamper-evident seal breaks, it cannot be 'un-broken' — and a second tamper claim is refused outright.",
    );
    try ctx.dispatch(
        "tessera.tamper",
        "{\"bottleId\":\"B8\"}",
        .{ .domain = "B8", .label = "tamper-event · seal broken (one and only)" },
    );
    try ctx.dispatchExpectingRefusal(
        "tessera.tamper",
        "{\"bottleId\":\"B8\"}",
        "Already tampered. The substrate refuses to record a second break of the same seal.",
    );

    try ctx.narrate(
        "Demonstration #2",
        "no phantom inventory",
        "What if a fraudster tries to bottle Barrel-C a second time, conjuring 12 more bottles out of nothing?",
    );
    try ctx.dispatchExpectingRefusal(
        "tessera.bottle",
        "{\"barrelId\":\"Barrel-C\",\"bottleIds\":[\"X1\",\"X2\",\"X3\"]}",
        "Refused. Barrel-C's wine is already in the original 12 bottles. The substrate enforces single-use.",
    );

    try ctx.narrate(
        "Demonstration #3",
        "blend conservation",
        "What about declaring more wine than the inputs justify? Two 100ml barrels claiming 999ml of blended cuvée?",
    );
    // Set up two small barrels in the FSM (without narrating — just stage).
    {
        const x1 = try ctx.reg.dispatch(ctx.allocator, "tessera", "tessera.harvest", "{\"lotId\":\"L-test\",\"grower\":\"g\",\"volumeMl\":200}");
        ctx.allocator.free(x1);
        const x2 = try ctx.reg.dispatch(ctx.allocator, "tessera", "tessera.rack", "{\"lotId\":\"L-test\",\"barrelId\":\"Test-A\",\"volumeMl\":100}");
        ctx.allocator.free(x2);
        const x3 = try ctx.reg.dispatch(ctx.allocator, "tessera", "tessera.rack", "{\"lotId\":\"L-test\",\"barrelId\":\"Test-B\",\"volumeMl\":100}");
        ctx.allocator.free(x3);
    }
    try ctx.dispatchExpectingRefusal(
        "tessera.blend",
        "{\"outBarrelId\":\"Test-C\",\"inBarrelIds\":[\"Test-A\",\"Test-B\"],\"declaredOutMl\":999}",
        "Refused. Inputs total 200ml; a 999ml output cannot be conserved. The substrate refuses invented wine.",
    );

    try ctx.closeRefusalsSection();
    try ctx.footer();
}

// ─── Body parsing helpers ────────────────────────────────────────────

fn cellIdOfBody(body: []const u8) []const u8 {
    const key = "\"cellId\":\"";
    if (std.mem.indexOf(u8, body, key)) |at| {
        const start = at + key.len;
        if (std.mem.indexOfScalarPos(u8, body, start, '"')) |end| {
            return body[start..end];
        }
    }
    const key2 = "\"cellIds\":[\"";
    if (std.mem.indexOf(u8, body, key2)) |at| {
        const start = at + key2.len;
        if (std.mem.indexOfScalarPos(u8, body, start, '"')) |end| {
            return body[start..end];
        }
    }
    return "";
}

fn reasonOfBody(body: []const u8) []const u8 {
    const key = "\"reason\":\"";
    if (std.mem.indexOf(u8, body, key)) |at| {
        const start = at + key.len;
        if (std.mem.indexOfScalarPos(u8, body, start, '"')) |end| {
            return body[start..end];
        }
    }
    return "unknown";
}

// ─── HTML chrome ─────────────────────────────────────────────────────

const HTML_HEADER =
    \\<!DOCTYPE html>
    \\<html lang="en">
    \\<head>
    \\<meta charset="utf-8">
    \\<title>Tessera · the verifiable life of a wine</title>
    \\<style>
    \\  body { font-family: 'Iowan Old Style', 'Palatino Linotype', Palatino, Georgia, serif;
    \\         max-width: 720px; margin: 3em auto; padding: 0 1.5em; color: #2a1810;
    \\         line-height: 1.55; background: #faf6ef; }
    \\  h1 { font-size: 1.8em; letter-spacing: 0.02em; margin-bottom: 0.2em; font-weight: 600; }
    \\  h2 { font-size: 1.0em; font-weight: 400; font-style: italic; color: #7a5a40;
    \\       margin: 0.2em 0 2em 0; border-bottom: 1px solid #d4c4a8; padding-bottom: 1em; }
    \\  .chain { list-style: none; padding: 0; counter-reset: step; }
    \\  .step { margin-bottom: 1.6em; padding-left: 3em; position: relative; counter-increment: step; }
    \\  .step::before { content: counter(step, decimal); position: absolute; left: 0; top: 0;
    \\                  width: 2em; height: 2em; border-radius: 50%; background: #fff;
    \\                  border: 1px solid #d4c4a8; text-align: center; line-height: 2em;
    \\                  font-family: Georgia, serif; color: #7a5a40; font-size: 0.9em; }
    \\  .when { font-size: 0.85em; color: #7a5a40; text-transform: uppercase; letter-spacing: 0.1em; }
    \\  .headline { font-size: 1.15em; font-weight: 600; margin: 0.15em 0; }
    \\  .body { color: #4a3828; }
    \\  .mint, .refusal { margin-top: 0.6em; padding: 0.8em 1em;
    \\                    background: #fff; border-left: 3px solid #6a4a2a;
    \\                    border-radius: 0 4px 4px 0; font-size: 0.92em; }
    \\  .refusal { border-left-color: #a02020; background: #fff7f5; }
    \\  .verb { font-weight: 600; color: #4a2a0a; }
    \\  .verb.refused { color: #a02020; }
    \\  .domain, .cellid { color: #7a5a40; font-size: 0.85em; }
    \\  code { font-family: 'SF Mono', 'Consolas', monospace; font-size: 0.85em;
    \\         background: #f0e7d4; padding: 0.1em 0.4em; border-radius: 3px; color: #4a2a0a; }
    \\  .note { font-style: italic; color: #6a4a2a; margin-top: 0.4em; font-size: 0.95em; }
    \\  .refusals { margin-top: 4em; padding-top: 1em; border-top: 1px dashed #c0a880; }
    \\  .refusals h2 { font-style: normal; text-transform: uppercase;
    \\                 letter-spacing: 0.15em; font-size: 0.9em; color: #a02020; }
    \\  .cold-chain { margin-top: 3em; padding-top: 1em; border-top: 1px dashed #c0a880; }
    \\  .cold-chain h2 { font-style: normal; text-transform: uppercase;
    \\                   letter-spacing: 0.15em; font-size: 0.9em; color: #2a5a40; }
    \\  .care-score { margin-top: 3em; padding: 1.5em 1.8em; border-radius: 8px;
    \\                background: #fff; border: 1px solid #d4c4a8;
    \\                box-shadow: 0 1px 6px rgba(80, 60, 30, 0.06); }
    \\  .care-score h2 { font-size: 1.15em; text-transform: none; letter-spacing: 0;
    \\                   border: none; padding: 0; margin: 0 0 0.4em 0; color: #2a1810;
    \\                   font-weight: 600; }
    \\  .care-score .score { color: #7a5a40; font-variant-numeric: tabular-nums; }
    \\  .care-score .verdict { margin: 0 0 1.2em 0; font-style: italic; font-size: 0.95em; }
    \\  .care-score .verdict.warn { color: #a02020; font-style: normal; font-weight: 500; }
    \\  .care-score .verdict.ok   { color: #2a5a40; font-style: normal; font-weight: 500; }
    \\  table.temp-log { width: 100%; border-collapse: collapse; font-size: 0.9em;
    \\                   margin-bottom: 1.2em; }
    \\  table.temp-log th, table.temp-log td { padding: 0.45em 0.6em; text-align: left;
    \\                                          border-bottom: 1px solid #e7dcc4; }
    \\  table.temp-log th { color: #7a5a40; text-transform: uppercase;
    \\                      letter-spacing: 0.08em; font-size: 0.78em; font-weight: 600; }
    \\  table.temp-log tr.excursion { background: #fff3ee; color: #8a2020; }
    \\  table.temp-log tr.confirmed { background: #fff7ee; color: #8a4a20; }
    \\  .care-score .conclusion { margin-top: 0.5em; color: #4a3828; font-size: 0.95em;
    \\                            border-left: 3px solid #6a4a2a; padding-left: 1em; }
    \\  footer { margin-top: 4em; padding-top: 2em; border-top: 1px solid #d4c4a8;
    \\           font-size: 0.9em; color: #6a4a2a; }
    \\  footer .brand { font-style: italic; text-align: center; margin-top: 1em; color: #7a5a40; }
    \\</style>
    \\</head>
    \\<body>
    \\
;

const HTML_FOOTER =
    \\</body>
    \\</html>
    \\
;

```
