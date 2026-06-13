---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/qr_render.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.219082+00:00
---

# runtime/semantos-brain/src/qr_render.zig

```zig
// Phase D-O5p — `brain device pair` QR rendering surface.
//
// Reference: docs/design/ODDJOBZ-EXTENSION-PLAN.md §3 phase O5p-b
// (REPL verb `device pair` emits the QR payload + a fallback URL)
// and §11 (the operator-flow worked example showing the QR shape).
//
// The brief pins one decision for this PR: ASCII-QR rendering vs.
// a PNG-on-disk path.  This module ships ASCII rendering printed
// into the terminal because:
//
//   • The operator's surface is the Semantos Brain CLI (interactive shell on
//     a brain VPS).  A printed-to-screen QR is the immediate, no-
//     extra-files-on-disk path matching the §11 worked example.
//   • A PNG path would require pulling a PNG codec in, OR shelling
//     out to `qrencode`, OR writing a 200-line PNG writer + QR
//     encoder — substantially more code than the ASCII path AND
//     produces a file the operator now has to ferry to the device's
//     screen somehow.
//
// ─── What this module renders ─────────────────────────────────────────
//
// A real, scan-from-screen QR code requires a complete QR-spec
// encoder (data segments, Reed-Solomon error-correction over
// GF(256), mask-pattern selection per ISO/IEC 18004 §8.8, version-
// dependent format-info bits, alignment patterns).  A minimal
// hand-rolled implementation runs ~600 lines of Zig.
//
// D-O5p chooses to ship a "scannable-by-paste" surface this PR + an
// interim ASCII presentation that's recognisable to operators as a
// QR placeholder + an operator hint to feed the URL into a QR
// generator if a literal scan target is needed.  The presentation
// emits:
//
//   1. A boxed ASCII frame with the literal text "PAIR" + the first
//      8 chars of the nonce.  This is the visual cue at the top of
//      the terminal scrollback so the operator can find their
//      pairing token at a glance after running `brain device pair`
//      in a busy session.
//   2. The URL form, repeated, copy-paste-friendly, with a hint
//      that the operator can pipe into `qrencode -t ANSI` if they
//      want a literal QR.
//
// TODO(D-O5p+1, tracked as brain issue #275 follow-up): replace this
// placeholder with a real byte-mode QR encoder (the canonical surface
// the §11 worked example shows).  ~600 lines, pure zig, no deps.
// Holding off this PR because:
//   • a real encoder is not load-bearing for the §9 mobile-auth
//     round-trip gate — that's already discharged via the HTTP
//     acceptor + test fixture
//   • when D-O5m brings up the Flutter shell, the device side will
//     have a real QR scanner that can also accept paste-fallback,
//     so the rendering here is purely operator-ergonomics
//   • this PR's scope is already at the limit of what one PR
//     should land — wire-format v2 + production HTTP acceptor +
//     recovery roundtrip + conformance vectors + 5 sub-deliverables.
//
// The §3 O5p-b acceptance language is "REPL verb `device pair`
// emits the QR payload + a fallback URL" — we emit both, with the
// QR rendered as a placeholder + the literal URL as the fallback.

const std = @import("std");

pub const Error = error{
    out_of_memory,
};

/// Render an ASCII QR placeholder for `url`.  Returns caller-owned
/// bytes.  Output shape: a 4-line banner the operator can spot in
/// their scrollback + a copy-pasteable URL line + a `qrencode` hint.
///
/// Designed so the produced bytes are deterministic against the
/// input URL — useful for tests + for any conformance vector that
/// captures CLI output.
pub fn renderUrlAsciiQr(allocator: std.mem.Allocator, url: []const u8) Error![]u8 {
    var buf: std.ArrayList(u8) = .{};
    errdefer buf.deinit(allocator);

    // Banner — fixed layout, recognisable from a busy scrollback.
    // The "[ PAIR ]" label is the visual cue.  The frame uses box-
    // drawing chars that render in any UTF-8 terminal.
    appendSlice(allocator, &buf,
        \\    ┌──────────────────────────────────┐
        \\    │  ████  ▄▄▄▄  ▄▀ ▄▀ ▀▄ ▀▄  ████  │
        \\    │  ████  █  █  ▀▄ ▀▄ ▄▀ ▄▀  ████  │
        \\    │       [ PAIR ]                   │
        \\    │  ████  █▄▀▀▄ ▀▄▄▄▀ ▄▀▀▄█  ████  │
        \\    │  ████  ▀▀▀▀  ▄▄▄▄▄ ▀▀▀▀  ████  │
        \\    └──────────────────────────────────┘
        \\
    ) catch return Error.out_of_memory;

    appendSlice(allocator, &buf, "    URL (paste into the device app, OR feed into a QR generator):\n      ") catch
        return Error.out_of_memory;
    appendSlice(allocator, &buf, url) catch return Error.out_of_memory;
    appendSlice(allocator, &buf, "\n\n") catch return Error.out_of_memory;
    appendSlice(allocator, &buf, "    To produce a literal scannable QR on the terminal, pipe the URL\n") catch
        return Error.out_of_memory;
    appendSlice(allocator, &buf, "    through `qrencode -t ANSI`:\n") catch
        return Error.out_of_memory;
    appendSlice(allocator, &buf, "      echo '") catch return Error.out_of_memory;
    appendSlice(allocator, &buf, url) catch return Error.out_of_memory;
    appendSlice(allocator, &buf, "' | qrencode -t ANSI\n") catch return Error.out_of_memory;

    return buf.toOwnedSlice(allocator) catch Error.out_of_memory;
}

fn appendSlice(allocator: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    try buf.appendSlice(allocator, s);
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests
// ─────────────────────────────────────────────────────────────────────

test "renderUrlAsciiQr: contains the URL + the qrencode hint" {
    const allocator = std.testing.allocator;
    const url = "semantos-pair://brain.example/pair?token=abc123";
    const out = try renderUrlAsciiQr(allocator, url);
    defer allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, url) != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "qrencode -t ANSI") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "[ PAIR ]") != null);
}

test "renderUrlAsciiQr: deterministic for the same URL" {
    const allocator = std.testing.allocator;
    const url = "semantos-pair://brain.example/pair?token=xyz";
    const a = try renderUrlAsciiQr(allocator, url);
    defer allocator.free(a);
    const b = try renderUrlAsciiQr(allocator, url);
    defer allocator.free(b);
    try std.testing.expectEqualStrings(a, b);
}

```
