---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/store_registry.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.250509+00:00
---

# runtime/semantos-brain/src/store_registry.zig

```zig
//! Typed store registry — C4 PR-H1, the §6b store-carve seam.
//!
//! A pointer-bag of the oddjobz shared typed stores. The cartridge's
//! registerInto constructs + OWNS all nine stores once (over the shared entity
//! CellStore) and publishes their pointers here; the brain's remaining
//! consumers — the WSS query/attention/ratify handlers and the store-coupled
//! HTTP acceptors that still live in serve.zig — read them back through this
//! registry instead of holding serve-local store vars. This lets the store
//! CONSTRUCTION leave the brain (into the cartridge) while the consumers stay,
//! until they migrate to their own seams (route_registry for the acceptors, a
//! wss-backend seam for query/attention/ratify).
//!
//! It is the store analog of http_route_registry (#851) / MintContextRegistry
//! (#846): a substrate-owned struct on CartridgeDeps the cartridge fills in
//! registerInto, so the brain never constructs the cartridge's domain state.
//!
//! Borrowing contract: the registry holds BORROWED pointers. The cartridge owns
//! the store lifetimes (heap-allocated in registerInto, reclaimed at process
//! exit — same posture as the attachments handler/store). The stores are thin
//! typed VIEWS over the shared entity CellStore, whose LMDB env the brain owns
//! and outlives them. Consumers must treat null as "store not up" (the brain
//! booted without the entity store, or the cartridge isn't loaded) and degrade.
//!
//! Leaf deps: the nine store modules only — so cartridge_seam can expose the
//! registry on CartridgeDeps without pulling in serve/reactor (substrate
//! one-way dep gate, #847).

const jobs_store_fs = @import("jobs_store_fs");
const customers_store_fs = @import("customers_store_fs");
const sites_store_fs = @import("sites_store_fs");
const visits_store_fs = @import("visits_store_fs");
const quotes_store_fs = @import("quotes_store_fs");
const estimates_store_fs = @import("estimates_store_fs");
const invoices_store_fs = @import("invoices_store_fs");
const attachments_store_fs = @import("attachments_store_fs");
// C4 PR-H6 — the attachment blob store (filesystem-backed, not a cell-store view)
// is also cartridge-owned + published here so serve's still-present upload
// acceptor reads it until PR-H7 migrates upload too.
const attachment_blobs_fs = @import("attachment_blobs_fs");

/// Borrowed pointers to the oddjobz shared typed stores. All optional; null
/// means "not up". Default-null so a serve.zig `StoreRegistry = .{}` declares an
/// empty registry the cartridge fills field-by-field in registerInto.
pub const StoreRegistry = struct {
    jobs: ?*jobs_store_fs.JobsStore = null,
    customers: ?*customers_store_fs.CustomersStore = null,
    sites: ?*sites_store_fs.SitesStore = null,
    visits: ?*visits_store_fs.VisitsStore = null,
    quotes: ?*quotes_store_fs.QuotesStore = null,
    estimates: ?*estimates_store_fs.EstimatesStore = null,
    invoices: ?*invoices_store_fs.InvoicesStore = null,
    attachments: ?*attachments_store_fs.AttachmentsStore = null,
    /// Filesystem-backed attachment blob store (C4 PR-H6). Not a cell-store view;
    /// constructed by the cartridge over the brain data dir + published here.
    attachment_blobs: ?*attachment_blobs_fs.BlobStore = null,
};

const std = @import("std");

test "StoreRegistry default-inits all fields to null" {
    const reg: StoreRegistry = .{};
    try std.testing.expect(reg.jobs == null);
    try std.testing.expect(reg.customers == null);
    try std.testing.expect(reg.sites == null);
    try std.testing.expect(reg.visits == null);
    try std.testing.expect(reg.quotes == null);
    try std.testing.expect(reg.estimates == null);
    try std.testing.expect(reg.invoices == null);
    try std.testing.expect(reg.attachments == null);
    try std.testing.expect(reg.attachment_blobs == null);
}

```
