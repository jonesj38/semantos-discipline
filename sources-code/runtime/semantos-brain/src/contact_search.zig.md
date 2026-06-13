---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/contact_search.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.217647+00:00
---

# runtime/semantos-brain/src/contact_search.zig

```zig
// Contact search — pure-logic substring matcher over Customer +
// optional Site slices.
//
// Backs `POST /api/v1/search/contacts` (Todd's talk|direct UI:
// "type a name, address, or suburb → matching contacts surface").
//
// Designed to take slices, not stores, so unit tests use plain arrays
// and production callers pass `customers_store.listAll(allocator)` +
// `sites_store.listAll(allocator)` results.
//
// W3.1 RED: stub returns empty slice for every query.
// W3.2 GREEN: name substring + suburb/address substring matchers,
//              de-duplicated by customer.id.

const std = @import("std");
const customers_store_fs = @import("customers_store_fs");
const sites_store_lmdb = @import("sites_store_lmdb");

pub const Error = error{
    empty_query,
    out_of_memory,
};

// ────────────────────────────────────────────────────────────────────
// searchContacts — case-insensitive substring search.
//
// Match if EITHER:
//   1. customer.display_name contains query (case-insensitive)
//   2. customer.siteRef points to a site whose suburb or fullAddress
//      contains query (case-insensitive)
//
// De-duped by customer.id. Order: name matches first, then site
// matches (stable within each bucket).
//
// W3.1 RED: returns empty slice for every input.
// W3.2 GREEN: real matcher.
// ────────────────────────────────────────────────────────────────────

pub fn searchContacts(
    allocator: std.mem.Allocator,
    customers: []const customers_store_fs.Customer,
    sites: []const sites_store_lmdb.Site,
    query: []const u8,
) Error![]customers_store_fs.Customer {
    if (query.len == 0) return Error.empty_query;

    var out = std.ArrayList(customers_store_fs.Customer){};
    errdefer out.deinit(allocator);

    // 1. Name matches first (stable preserves customer order).
    for (customers) |c| {
        if (containsIgnoreCase(c.display_name, query)) {
            out.append(allocator, c) catch return Error.out_of_memory;
        }
    }

    // 2. Site-mediated matches: find sites whose suburb or fullAddress
    //    matches, then customers with siteRef pointing at those sites.
    //    Dedupe by customer.id against bucket 1.
    for (sites) |s| {
        const suburb_hit = if (s.suburb) |sb| containsIgnoreCase(sb, query) else false;
        if (!suburb_hit and !containsIgnoreCase(s.fullAddress, query)) continue;
        for (customers) |c| {
            const cref = c.siteRef orelse continue;
            if (!std.mem.eql(u8, cref[0..], s.cellId[0..])) continue;
            if (containsId(out.items, c.id)) continue;
            out.append(allocator, c) catch return Error.out_of_memory;
        }
    }

    return out.toOwnedSlice(allocator) catch return Error.out_of_memory;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    const limit = haystack.len - needle.len + 1;
    var i: usize = 0;
    while (i < limit) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(needle[j])) break;
        }
        if (j == needle.len) return true;
    }
    return false;
}

fn containsId(slice: []const customers_store_fs.Customer, id: []const u8) bool {
    for (slice) |c| if (std.mem.eql(u8, c.id, id)) return true;
    return false;
}

// ────────────────────────────────────────────────────────────────────
// Tests
// ────────────────────────────────────────────────────────────────────

const testing = std.testing;

fn mkCustomer(id: []const u8, name: []const u8, siteRef: ?[32]u8) customers_store_fs.Customer {
    return .{
        .id = id,
        .display_name = name,
        .phone = "",
        .email = "",
        .address = "",
        .notes = "",
        .created_at = "2026-05-14T00:00:00Z",
        .siteRef = siteRef,
    };
}

fn mkSite(cellId: [32]u8, fullAddress: []const u8, suburb: ?[]const u8) sites_store_lmdb.Site {
    return .{
        .cellId = cellId,
        .typeHash = .{0} ** 32,
        .normalisedAddress = fullAddress,
        .keyNumber = null,
        .lookupKey = fullAddress,
        .fullAddress = fullAddress,
        .suburb = suburb,
        .postcode = null,
        .state = null,
        .signedBy = null,
        .signature = null,
        .createdAt = 0,
    };
}

test "searchContacts — empty query rejected" {
    try testing.expectError(Error.empty_query, searchContacts(testing.allocator, &.{}, &.{}, ""));
}

test "searchContacts — name substring match (case-insensitive)" {
    const customers = [_]customers_store_fs.Customer{
        mkCustomer("c1", "John Smith", null),
        mkCustomer("c2", "Jane Doe", null),
        mkCustomer("c3", "Alice SMITHSON", null),
    };
    const hits = try searchContacts(testing.allocator, customers[0..], &.{}, "smith");
    defer testing.allocator.free(hits);
    try testing.expectEqual(@as(usize, 2), hits.len);
    try testing.expectEqualStrings("c1", hits[0].id);
    try testing.expectEqualStrings("c3", hits[1].id);
}

test "searchContacts — no matches returns empty slice (not error)" {
    const customers = [_]customers_store_fs.Customer{
        mkCustomer("c1", "John Smith", null),
    };
    const hits = try searchContacts(testing.allocator, customers[0..], &.{}, "zzz");
    defer testing.allocator.free(hits);
    try testing.expectEqual(@as(usize, 0), hits.len);
}

test "searchContacts — suburb match returns customers on matching sites" {
    var site_id: [32]u8 = .{0} ** 32;
    site_id[0] = 0xAA;
    const sites = [_]sites_store_lmdb.Site{
        mkSite(site_id, "12 Smith St", "Mascot"),
    };
    const customers = [_]customers_store_fs.Customer{
        mkCustomer("c1", "Tenant A", site_id),
        mkCustomer("c2", "Tenant B", site_id),
        mkCustomer("c3", "Unrelated", null),
    };
    const hits = try searchContacts(testing.allocator, customers[0..], sites[0..], "Mascot");
    defer testing.allocator.free(hits);
    try testing.expectEqual(@as(usize, 2), hits.len);
}

test "searchContacts — full address match returns customers on matching sites" {
    var site_id: [32]u8 = .{0} ** 32;
    site_id[0] = 0xBB;
    const sites = [_]sites_store_lmdb.Site{
        mkSite(site_id, "12 Bond Street", "Sydney"),
    };
    const customers = [_]customers_store_fs.Customer{
        mkCustomer("c1", "Tenant A", site_id),
    };
    const hits = try searchContacts(testing.allocator, customers[0..], sites[0..], "Bond Street");
    defer testing.allocator.free(hits);
    try testing.expectEqual(@as(usize, 1), hits.len);
}

test "searchContacts — name + suburb dedupes by customer.id" {
    var site_id: [32]u8 = .{0} ** 32;
    site_id[0] = 0xCC;
    const sites = [_]sites_store_lmdb.Site{
        mkSite(site_id, "1 Mascot Rd", "Mascot"),
    };
    const customers = [_]customers_store_fs.Customer{
        // matches BOTH name "Mascot" (improbable but tests dedupe) AND siteRef
        mkCustomer("c1", "Mascot Property Trust", site_id),
    };
    const hits = try searchContacts(testing.allocator, customers[0..], sites[0..], "Mascot");
    defer testing.allocator.free(hits);
    try testing.expectEqual(@as(usize, 1), hits.len);
}

test "searchContacts — name matches surface before suburb matches" {
    var site_id: [32]u8 = .{0} ** 32;
    site_id[0] = 0xDD;
    const sites = [_]sites_store_lmdb.Site{
        mkSite(site_id, "1 Smith Lane", "Smithtown"),
    };
    const customers = [_]customers_store_fs.Customer{
        mkCustomer("c-site", "Site Resident", site_id),
        mkCustomer("c-name", "Mary Smith", null),
    };
    const hits = try searchContacts(testing.allocator, customers[0..], sites[0..], "smith");
    defer testing.allocator.free(hits);
    try testing.expectEqual(@as(usize, 2), hits.len);
    // name match first
    try testing.expectEqualStrings("c-name", hits[0].id);
    try testing.expectEqualStrings("c-site", hits[1].id);
}

```
