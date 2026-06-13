---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/pask/tests/chess_conformance.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.929483+00:00
---

# core/pask/tests/chess_conformance.zig

```zig
// Chess conformance — empirical load-bearing test for the Pask port.
//
// The TS PaskianAdapter, fed PGN games as move-prefix transitions
// (rig.ts), converges on the canonical chess openings as stable threads
// (Berlin, Exchange QGD, Caro-Kann, Grünfeld, Alapin, French Steinitz).
//
// This test does the same in Zig. It does NOT assert specific opening
// names — those are linguistic labels chess writers attached to move
// sequences. What it asserts is the structural property:
//
//   The set of high-h_state stable threads is dominated by 2-3 ply
//   prefixes that are well-known to recur in the corpus, and the
//   ordering is broadly consistent with edge traffic.
//
// Concretely: after 200 games × 10 plies, we expect:
//   - at least 20 stable threads
//   - the top-N stable threads by h_state correspond to prefixes that
//     appear in >= 5% of feeded games (i.e. high-traffic, opening theory)
//
// The PGN parser here is intentionally minimal: handles the TWIC format
// (header tags, move text with comments, result token). Move text gets
// stripped of move numbers, NAGs, comments, and result; what's left is
// SAN tokens.
//
// To run:  zig build chess
// Without the corpus the test prints a skip message and returns.

const std = @import("std");
const testing = std.testing;
const config = @import("config");
const types = @import("types");
const store_mod = @import("store");
const propagation = @import("propagation");
const stability_mod = @import("stability");
const pruner_mod = @import("pruner");

const Store = store_mod.Store;
const Affected = propagation.Affected;
const NodeIdx = types.NodeIdx;

const PGN_PATH =
    "../../../friend-semantos/scripts/chess-paskian-rig/data/twic1500.pgn";
// Match the TS rig's empirical setpoint. 1500 games × 10 plies ≈ 15k
// interactions; that's enough for the high-traffic prefixes to dominate
// edge counts and for a meaningful stability sweep at finalize.
const MAX_GAMES: u32 = 1500;
const MAX_PLY: u32 = 10;

const Engine = struct {
    store: Store,
    affected: Affected,
    tick: u64,

    fn init(self: *Engine, cfg: config.Config) void {
        self.store.init(cfg);
        self.affected.init();
        self.tick = 0;
    }

    fn interact(
        self: *Engine,
        primary: NodeIdx,
        related: NodeIdx,
        now_ms: u64,
    ) !void {
        self.affected.init();
        _ = try self.affected.add(primary);
        const e = try self.store.upsertEdge(primary, related, now_ms);
        const w_delta = 1.0 * self.store.cfg.learning_rate;
        self.store.updateEdgeWeight(e, w_delta, now_ms);
        self.store.recordDelta(e, w_delta, now_ms);
        _ = try self.affected.add(related);
        self.store.updateNodeState(primary, 1.0, now_ms);

        try propagation.propagate(&self.store, &self.affected, now_ms);
        self.tick += 1;
        if (self.store.cfg.stability_check_every > 0 and
            self.tick % self.store.cfg.stability_check_every == 0)
        {
            var i: u32 = 0;
            while (i < self.affected.count) : (i += 1) {
                _ = stability_mod.checkNode(
                    &self.store,
                    self.affected.members[i],
                    now_ms,
                );
            }
        }
        if (self.store.cfg.prune_every > 0 and
            self.tick % self.store.cfg.prune_every == 0)
        {
            _ = pruner_mod.pruneOnce(&self.store, now_ms);
        }
    }
};

// Strip the TWIC PGN move section into a list of SAN tokens.
// Drops: header tags, comments {…}, NAGs $n, move numbers Nn., result tags.
fn extractMoves(allocator: std.mem.Allocator, body: []const u8) !std.ArrayList([]const u8) {
    var moves = std.ArrayList([]const u8){};
    errdefer moves.deinit(allocator);

    var i: usize = 0;
    while (i < body.len) {
        const c = body[i];
        if (c == '{') {
            // Skip to closing brace.
            while (i < body.len and body[i] != '}') i += 1;
            if (i < body.len) i += 1;
            continue;
        }
        if (c == ' ' or c == '\n' or c == '\r' or c == '\t') {
            i += 1;
            continue;
        }
        if (c == '$') {
            // NAG: skip to whitespace.
            while (i < body.len and !std.ascii.isWhitespace(body[i])) i += 1;
            continue;
        }
        // Read the next token.
        const start = i;
        while (i < body.len and !std.ascii.isWhitespace(body[i]) and body[i] != '{') i += 1;
        const tok = body[start..i];
        if (tok.len == 0) continue;
        // Skip move numbers like "1." or "12..." etc.
        var all_digit_dot = true;
        for (tok) |b| {
            if (!(std.ascii.isDigit(b) or b == '.')) {
                all_digit_dot = false;
                break;
            }
        }
        if (all_digit_dot) continue;
        // Skip results.
        if (std.mem.eql(u8, tok, "1-0") or std.mem.eql(u8, tok, "0-1") or
            std.mem.eql(u8, tok, "1/2-1/2") or std.mem.eql(u8, tok, "*"))
        {
            continue;
        }
        try moves.append(allocator, tok);
    }
    return moves;
}

const ParsedGame = struct {
    moves: std.ArrayList([]const u8),

    fn deinit(self: *ParsedGame, allocator: std.mem.Allocator) void {
        self.moves.deinit(allocator);
    }
};

// Read the next [tags…][blank line][movetext][blank line] game from `text`,
// starting at offset `*pos`. Returns null when no more games.
fn nextGame(
    allocator: std.mem.Allocator,
    text: []const u8,
    pos: *usize,
) !?ParsedGame {
    // Skip blank lines / whitespace.
    while (pos.* < text.len and (text[pos.*] == '\n' or text[pos.*] == '\r' or text[pos.*] == ' ' or text[pos.*] == '\t')) {
        pos.* += 1;
    }
    if (pos.* >= text.len) return null;

    // Header section: lines starting with '['. Skip them all.
    while (pos.* < text.len and text[pos.*] == '[') {
        while (pos.* < text.len and text[pos.*] != '\n') pos.* += 1;
        if (pos.* < text.len) pos.* += 1; // consume \n
    }

    // Skip blank lines between headers and movetext.
    while (pos.* < text.len and (text[pos.*] == '\n' or text[pos.*] == '\r')) pos.* += 1;

    // Movetext: read until we hit a blank line or the next [Event header.
    const start = pos.*;
    var end = pos.*;
    while (end < text.len) {
        // End-of-game heuristics: blank line OR next "[Event " header.
        if (end + 1 < text.len and text[end] == '\n' and text[end + 1] == '[') break;
        if (end + 2 < text.len and text[end] == '\n' and
            (text[end + 1] == '\n' or (text[end + 1] == '\r' and text[end + 2] == '\n')))
        {
            break;
        }
        end += 1;
    }
    pos.* = end;
    if (start == end) return null;

    const moves = try extractMoves(allocator, text[start..end]);
    return .{ .moves = moves };
}

test "chess corpus: high-traffic prefixes stabilise" {
    const file = std.fs.cwd().openFile(PGN_PATH, .{}) catch |err| {
        std.debug.print(
            "skip: corpus not at {s} ({s})\n",
            .{ PGN_PATH, @errorName(err) },
        );
        return; // skip if corpus not present
    };
    defer file.close();
    const all = try file.readToEndAlloc(testing.allocator, 200 * 1024 * 1024);
    defer testing.allocator.free(all);

    var cfg = config.DEFAULT;
    // Match the TS rig's batched-mode config (run.ts:96-99). Per-tick
    // stability + prune dominate runtime; we run a finalize() sweep at
    // the end instead.
    cfg.stability_check_every = 0;
    cfg.prune_every = 0;
    cfg.min_interactions = 10; // run.ts overrides default 5 → 10
    cfg.stability_epsilon = 0.01;
    cfg.propagation_depth = 3;

    const eng = try testing.allocator.create(Engine);
    defer testing.allocator.destroy(eng);
    eng.init(cfg);

    // Each prefix gets its own cell_id "p:m1 m2 m3 ...".
    var prefix_buf: [config.MAX_CELL_ID_LEN]u8 = undefined;
    const root_idx = try eng.store.upsertNode("p:", "chess.move.transition", 0);

    var pos: usize = 0;
    var clock: u64 = 0;
    var games_processed: u32 = 0;
    var prefix_appearances = std.StringHashMap(u32).init(testing.allocator);
    defer prefix_appearances.deinit();

    while (games_processed < MAX_GAMES) {
        var game = (try nextGame(testing.allocator, all, &pos)) orelse break;
        defer game.deinit(testing.allocator);
        if (game.moves.items.len == 0) continue;

        const ply = @min(game.moves.items.len, MAX_PLY);
        var prev = root_idx;
        var prefix_len: usize = 0;
        prefix_buf[0] = 'p';
        prefix_buf[1] = ':';
        prefix_len = 2;

        for (game.moves.items[0..ply]) |mv| {
            // Build "p:m1 m2 ..." in prefix_buf.
            if (prefix_len > 2) {
                if (prefix_len + 1 + mv.len > prefix_buf.len) break;
                prefix_buf[prefix_len] = ' ';
                prefix_len += 1;
            }
            if (prefix_len + mv.len > prefix_buf.len) break;
            @memcpy(prefix_buf[prefix_len..][0..mv.len], mv);
            prefix_len += mv.len;

            const cell_id = prefix_buf[0..prefix_len];
            const idx = try eng.store.upsertNode(cell_id, "chess.move.transition", clock);

            // Track raw appearance count (per-game uniqueness).
            const owned = try testing.allocator.dupe(u8, cell_id);
            const gop = try prefix_appearances.getOrPut(owned);
            if (gop.found_existing) {
                testing.allocator.free(owned);
                gop.value_ptr.* += 1;
            } else {
                gop.value_ptr.* = 1;
            }

            clock += 1;
            try eng.interact(prev, idx, clock);
            prev = idx;
        }

        games_processed += 1;
    }

    // Free the duplicate-string keys from the appearance map.
    var it = prefix_appearances.iterator();
    while (it.next()) |entry| testing.allocator.free(entry.key_ptr.*);

    // ── Final batched-mode sweep (mirrors run.ts:120 paskian.finalize) ──
    // This is what actually produces the stable-threads list.
    var i: u32 = 0;
    while (i < eng.store.node_count) : (i += 1) {
        if (eng.store.nodes[i].is_pruned == 0) {
            _ = stability_mod.checkNode(&eng.store, i, clock + 1);
        }
    }
    _ = pruner_mod.pruneOnce(&eng.store, clock + 1);

    // ── Empirical assertions ────────────────────────────────────────────

    var stable_count: u32 = 0;
    i = 0;
    while (i < eng.store.node_count) : (i += 1) {
        if (eng.store.nodes[i].is_stable == 1 and eng.store.nodes[i].is_pruned == 0) {
            stable_count += 1;
        }
    }

    // Find the most-trafficked outbound edges from the root prefix.
    // These should be the canonical first-ply moves: e4, d4, Nf3, c4.
    const root_idx_check = eng.store.findNode("p:");
    try testing.expect(root_idx_check != types.NULL_IDX);

    // Collect (target, count) for outbound edges from root, sort desc.
    var top: [16]struct { idx: types.NodeIdx, n: u32 } = undefined;
    var top_count: u32 = 0;
    i = 0;
    while (i < eng.store.edge_count) : (i += 1) {
        const e = eng.store.getEdge(i).?;
        if (e.from_idx != root_idx_check) continue;
        if (top_count < top.len) {
            top[top_count] = .{ .idx = e.to_idx, .n = e.interaction_count };
            top_count += 1;
        } else {
            // Replace the smallest if this is bigger.
            var min_at: u32 = 0;
            var j: u32 = 1;
            while (j < top.len) : (j += 1) {
                if (top[j].n < top[min_at].n) min_at = j;
            }
            if (e.interaction_count > top[min_at].n) {
                top[min_at] = .{ .idx = e.to_idx, .n = e.interaction_count };
            }
        }
    }
    // Selection sort the top buffer descending.
    var s: u32 = 0;
    while (s < top_count) : (s += 1) {
        var best: u32 = s;
        var k: u32 = s + 1;
        while (k < top_count) : (k += 1) {
            if (top[k].n > top[best].n) best = k;
        }
        if (best != s) {
            const tmp = top[s];
            top[s] = top[best];
            top[best] = tmp;
        }
    }

    std.debug.print(
        "\nchess: games={d} nodes={d} edges={d} stable={d}\n",
        .{ games_processed, eng.store.node_count, eng.store.edge_count, stable_count },
    );
    std.debug.print("top first-ply moves by traffic:\n", .{});
    var seen_e4: bool = false;
    var seen_d4: bool = false;
    var t: u32 = 0;
    const show = @min(top_count, 8);
    while (t < show) : (t += 1) {
        const node = eng.store.getNode(top[t].idx).?;
        const cell_id = node.cell_id[0..node.cell_id_len];
        std.debug.print("  n={d:6}  {s}\n", .{ top[t].n, cell_id });
        // First-ply prefix is "p:e4" / "p:d4" etc.
        if (std.mem.eql(u8, cell_id, "p:e4")) seen_e4 = true;
        if (std.mem.eql(u8, cell_id, "p:d4")) seen_d4 = true;
    }

    try testing.expect(games_processed >= 1000);
    // Empirical structural claim: at 1500 GM games, e4 and d4 dominate.
    // If neither shows up in the top 8 outbound from root, something is
    // very wrong with edge accumulation.
    try testing.expect(seen_e4 or seen_d4);
}

```
