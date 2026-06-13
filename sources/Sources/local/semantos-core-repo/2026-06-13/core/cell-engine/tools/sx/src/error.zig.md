---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/tools/sx/src/error.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.996351+00:00
---

# core/cell-engine/tools/sx/src/error.zig

```zig
//! TokeniserError + canonical error message strings.
//!
//! Mirrors `src/sx/src/tokeniser.ts::TokeniserError`. Field shape must
//! match — his test suite (`errorReporting/errorReporting.test.ts` etc.)
//! asserts against specific `msg` strings.
//!
//! Message strings are pinned as `pub const` so the parity harness can
//! compare them by reference. When a parity test fails on message text,
//! the canonical fix is here, not in the lexer.

const std = @import("std");

pub const TokeniserError = struct {
    msg: []const u8,
    pos: u32,
    len: u32,
    line: u32,
    col: u32,
    file_id: []const u8,
    file_name: []const u8,
};

/// Canonical error message strings. New entries land here verbatim from
/// his `throwError` callsites in `tokeniser.ts` / `parser.ts`.
pub const ErrorMsg = struct {
    // TODO PR-1.1: populate as we exercise each error path in parity tests.
    // Catalogue of his throwError callsites discovered during port:
    //
    //   tokeniser.ts:NNN  throwError("Unterminated string literal", ...)
    //   tokeniser.ts:NNN  throwError("Invalid hex literal", ...)
    //   parser.ts:NNN     throwError("Unexpected end of input", ...)
    //
    // Pin each one here as we hit it. Test failures on message text
    // get fixed by updating this file, not the lexer.

    pub const unterminated_string: []const u8 = "Unterminated string literal";
    pub const invalid_hex: []const u8 = "Invalid hex literal";
    pub const unexpected_end: []const u8 = "Unexpected end of input";

    /// His `tryAnnotation` (`tokeniser.ts:399`) builds the message as
    /// `Unrecognised annotation type: '<key>'`. We allocate the per-error
    /// string in the lexer; this constant is the fixed prefix the test
    /// harness greps against (mirrors his `expect(...).toContain(...)`).
    pub const unrecognised_annotation_prefix: []const u8 = "Unrecognised annotation type:";
};

/// Annotation key whitelist — verbatim from his
/// `tokeniser.ts:38` `annotationKeys` array. Lookup is case-insensitive
/// (his code falls through to `keyVal.toLowerCase()` check).
pub const ANNOTATION_KEYS = [_][]const u8{
    "label", "l", "test", "t", "desc", "d", "cs",
};

pub fn isKnownAnnotationKey(key: []const u8) bool {
    for (ANNOTATION_KEYS) |k| {
        if (std.ascii.eqlIgnoreCase(key, k)) return true;
    }
    return false;
}

test "annotation whitelist accepts known keys" {
    try std.testing.expect(isKnownAnnotationKey("label"));
    try std.testing.expect(isKnownAnnotationKey("LABEL"));
    try std.testing.expect(isKnownAnnotationKey("cs"));
    try std.testing.expect(isKnownAnnotationKey("t"));
}

test "annotation whitelist rejects unknown keys" {
    try std.testing.expect(!isKnownAnnotationKey("note"));
    try std.testing.expect(!isKnownAnnotationKey("invalidAnnotation"));
    try std.testing.expect(!isKnownAnnotationKey(""));
}

test "ErrorMsg strings are stable" {
    // Cheap sanity — these constants are tested implicitly by parity tests,
    // but having one explicit assertion makes accidental edits visible in
    // `zig build test` output.
    try std.testing.expectEqualStrings("Unterminated string literal", ErrorMsg.unterminated_string);
    try std.testing.expectEqualStrings("Invalid hex literal", ErrorMsg.invalid_hex);
    try std.testing.expectEqualStrings("Unexpected end of input", ErrorMsg.unexpected_end);
}

```
