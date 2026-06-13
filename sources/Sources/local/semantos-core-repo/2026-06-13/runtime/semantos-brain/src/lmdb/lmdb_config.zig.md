---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/lmdb/lmdb_config.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.280363+00:00
---

# runtime/semantos-brain/src/lmdb/lmdb_config.zig

```zig
// M1.9 — LMDB environment configuration.
//
// Central place for durability + sizing knobs so every call-site (cli.zig,
// test helpers, future tooling) uses the same documented defaults.
//
// Flag choices (see runtime/semantos-brain/LMDB-TUNING.md for the full rationale):
//
//   prod_flags  (default)
//     NOTLS | NOMETASYNC
//     • NOTLS:      required — we are single-threaded (WASM host, tokio-style
//                   async loop); TLS reader-lock slots would deadlock.
//     • NOMETASYNC: acceptable durability trade-off — data pages are flushed
//                   to disk on commit; only the meta page (B-tree root pointer)
//                   may lag by one transaction.  On crash LMDB recovers to the
//                   last fully committed transaction.  No data corruption risk.
//     • NOT NOSYNC: full NOSYNC is too risky for production — a power-loss
//                   event can corrupt arbitrary pages.
//
//   ci_flags
//     NOTLS | NOSYNC
//     • NOSYNC:     skips all fsyncs; safe in a CI sandbox where the OS
//                   flushes on normal process exit and data durability is
//                   not required.  Never use in production.

const EnvFlags = @import("lmdb").EnvFlags;

pub const LmdbConfig = struct {
    map_size: usize = 1024 * 1024 * 1024, // 1 GiB default
    max_dbs: c_uint = 16,
    flags: c_uint = prod_flags,
    mode: u16 = 0o644,

    /// Production default: safe durability, WASM-compatible threading.
    pub const prod_flags: c_uint = EnvFlags.NOTLS | EnvFlags.NOMETASYNC;

    /// CI / testing: skip all fsyncs for speed.  Do NOT use in production.
    pub const ci_flags: c_uint = EnvFlags.NOTLS | EnvFlags.NOSYNC;

    /// Convenience singleton with all defaults applied.
    pub const default: LmdbConfig = .{};
};

```
