---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/operator_profile.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.236733+00:00
---

# runtime/semantos-brain/src/operator_profile.zig

```zig
// Operator profile cells — S1 (Semantos Sites 1.0).
//
// Typed in-memory representations of the strategy cells that power
// the operator's public-facing site.  These are deserialized from the
// operator's RELEVANT cell store (strategy.lbc, strategy.icp,
// strategy.services, strategy.pricing) and passed to the site renderer.
//
// Cell-store read and JSON deserialization are the caller's
// responsibility.  This module only defines the types and their
// free-functions (init / deinit / from_json).

const std = @import("std");

// ── Service entry (one card in the services grid) ────────────────────

pub const Service = struct {
    slug:        []const u8,   // "carpentry"
    label:       []const u8,   // "Carpentry"
    icon:        []const u8,   // "🔨"
    description: []const u8,   // "Decks, shelves, framing..."
};

// ── Pricing ──────────────────────────────────────────────────────────

pub const QuotePolicy = enum {
    free_onsite,
    paid_onsite,
    phone_only,
    chat_first,

    pub fn fromString(s: []const u8) QuotePolicy {
        if (std.mem.eql(u8, s, "free_onsite"))  return .free_onsite;
        if (std.mem.eql(u8, s, "paid_onsite"))  return .paid_onsite;
        if (std.mem.eql(u8, s, "phone_only"))   return .phone_only;
        return .chat_first;
    }

    /// WP-4 — round-trips with fromString for persistence.
    pub fn toString(self: QuotePolicy) []const u8 {
        return switch (self) {
            .free_onsite => "free_onsite",
            .paid_onsite => "paid_onsite",
            .phone_only => "phone_only",
            .chat_first => "chat_first",
        };
    }

    pub fn howItWorksStep4(self: QuotePolicy) []const u8 {
        return switch (self) {
            .free_onsite  => "Free on-site quote — we come out, take a proper look, and give you a firm number. No charge.",
            .paid_onsite  => "Paid site visit — we come out, measure up, and send you a detailed written quote.",
            .phone_only   => "Phone quote — give us a call and we'll work through the details together.",
            .chat_first   => "Chat to confirm — once we have the details we'll send you a firm written quote.",
        };
    }
};

pub const PricingLine = struct {
    label:    []const u8,
    amount:   u32,         // in whole currency units (AUD cents would need adjustment)
    currency: []const u8,  // "AUD"
};

pub const Pricing = struct {
    callout_fee:    ?PricingLine,
    hourly_rate:    ?PricingLine,
    emergency_rate: ?PricingLine,
    minimum_charge: ?PricingLine,
    quote_policy:   QuotePolicy,
    /// WP-4 — service radius (km) for the in-person site visit. Drives the
    /// conversation's qualify/quote (WP-6). null = unset. Managed via
    /// `do manage site pricing travel_km=…`.
    travel_distance_km: ?u32 = null,
};

// ── ICP tone ─────────────────────────────────────────────────────────

pub const Tone = enum {
    friendly,
    professional,
    expert,
    casual,

    pub fn fromString(s: []const u8) Tone {
        if (std.mem.eql(u8, s, "professional")) return .professional;
        if (std.mem.eql(u8, s, "expert"))       return .expert;
        if (std.mem.eql(u8, s, "casual"))       return .casual;
        return .friendly;
    }
};

// ── Full operator profile (assembled from multiple strategy cells) ────

pub const OperatorProfile = struct {
    // identity
    business_name: []const u8,
    trade_label:   []const u8,   // "Handyman" | "Plumber" | "Electrician" | …
    geography:     []const u8,   // "Sunshine Coast" | "Northern Beaches, Sydney"
    phone:         []const u8,
    abn:           []const u8,

    // from strategy.lbc
    problem:    []const u8,      // ToFu lede
    uvp:        []const u8,      // hero h1 source
    // derived fields (renderer computes)
    hero_h1:    []const u8,      // "Get a plumbing quote in minutes" — set at render time
    hero_lede:  []const u8,      // assembled from problem + geography

    // from strategy.icp
    trust_signals: [][]const u8, // checkmarks in hero
    tone:          Tone,
    segment:       []const u8,

    // from strategy.services
    services: []Service,

    // from strategy.pricing
    pricing: Pricing,

    // intake widget config (derived from icp + trade_label + geography)
    widget_title:       []const u8,
    widget_greeting:    []const u8,
    widget_placeholder: []const u8,
    widget_endpoint:    []const u8,  // "/api/v1/chat" always for hosted ops
    /// DO-2 — operator on/off switch for the public chat widget. When false the
    /// cartridge chat route declines (503 widget_disabled, DO-3). Default true so
    /// existing profiles (and the cartridge) keep the widget live. Managed via
    /// `do manage site widget enabled=false`.
    widget_enabled:     bool = true,
    /// WP-2 — operator governance knobs for the public widget. Defaults mirror the
    /// brain's built-ins (llm_complete_handler.DEFAULT_REQUESTS_PER_HOUR /
    /// DEFAULT_TOKENS_PER_DAY = 100 / 100_000; web_chat_http.DEFAULT_MAX_MESSAGE_CHARS
    /// = 4000). rate/budget are boot-seeded into llm_complete_handler (apply on
    /// (re)start); max_message_chars is read live by the cartridge chat route.
    /// Managed via `do manage site widget rate_limit=… daily_tokens=… max_chars=…`.
    widget_rate_limit_per_hour: u32 = 100,
    widget_tokens_per_day:      u32 = 100_000,
    widget_max_message_chars:   u32 = 4000,
    /// WP-3 — operator embed allowlist: comma-separated origins permitted to POST
    /// to the chat route (e.g. "https://acme.com,https://shop.acme.com"). Empty =
    /// no restriction (any origin). A server-side gate read live by the cartridge
    /// chat route: a cross-origin request (Origin header present) whose origin
    /// isn't listed → 403. Browser CORS (ACAO) stays site-config-driven; this is
    /// the operator's complementary embed policy. Managed via
    /// `do manage site widget origins=…`.
    widget_embed_origins:       []const u8 = "",
    /// WP-5 — active conversation-prompt version id (the operator-tunable system
    /// prompt; versions append to <site>/prompts.jsonl). 0 = none (use the built-in
    /// default). Managed via `do manage site prompt` / `do rollback site prompt`.
    widget_prompt_version:      u32 = 0,

    pub fn deinit(self: *OperatorProfile, allocator: std.mem.Allocator) void {
        _ = self;
        _ = allocator;
        // Strings are arena-owned; caller frees the arena.
    }
};

// ── Default profiles for testing / preview ───────────────────────────

// Compile-time constants for the default trust signals and services.
// We use @constCast so they fit the mutable-slice fields of OperatorProfile.
// These slices are only ever read by the renderer; callers must not mutate them.
const default_trust_signals = [_][]const u8{
    "Sunshine Coast based — Noosa to Caloundra",
    "Free on-site quote for most jobs",
    "No call centre — you talk directly to the tradie",
    "Same-day response on urgent jobs",
};
const default_services = [_]Service{
    .{ .slug = "carpentry",  .label = "Carpentry",       .icon = "🔨", .description = "Decks, shelves, framing, cabinets, pergolas" },
    .{ .slug = "plumbing",   .label = "Plumbing",        .icon = "🚿", .description = "Taps, drains, hot water, pipes, toilets" },
    .{ .slug = "electrical", .label = "Electrical",      .icon = "⚡", .description = "Power points, switches, light fittings" },
    .{ .slug = "painting",   .label = "Painting",        .icon = "🎨", .description = "Interior, exterior, feature walls, patching" },
    .{ .slug = "fencing",    .label = "Fencing",         .icon = "🏚️", .description = "Palings, panels, posts, gates" },
    .{ .slug = "doors",      .label = "Doors & Windows", .icon = "🪟", .description = "Hanging, adjusting, locks, frames" },
    .{ .slug = "gardening",  .label = "Gardening",       .icon = "🪴", .description = "Mowing, hedging, mulch, retaining walls" },
    .{ .slug = "general",    .label = "General",         .icon = "🔧", .description = "Assembly, hanging, TV mounts, odd jobs" },
};

pub fn defaultProfile(allocator: std.mem.Allocator) !OperatorProfile {
    _ = allocator;
    return OperatorProfile{
        .business_name = "Oddjobz",
        .trade_label   = "Handyman",
        .geography     = "Sunshine Coast",
        .phone         = "0412 345 678",
        .abn           = "00 000 000 000",

        .problem    = "You need something fixed but can't find a reliable tradie who shows up and communicates.",
        .uvp        = "Get a rough quote in minutes",
        .hero_h1    = "Get a rough quote in minutes",
        .hero_lede  = "Describe the job in the chat. We'll ask a couple of questions and give you a ballpark — no obligation.",

        .trust_signals = @constCast(@as([]const []const u8, &default_trust_signals)),
        .tone     = .friendly,
        .segment  = "homeowners",

        .services = @constCast(@as([]const Service, &default_services)),

        .pricing = .{
            .callout_fee    = .{ .label = "Service call", .amount = 120, .currency = "AUD" },
            .hourly_rate    = .{ .label = "Per hour",     .amount = 95,  .currency = "AUD" },
            .emergency_rate = .{ .label = "After hours",  .amount = 180, .currency = "AUD" },
            .minimum_charge = null,
            .quote_policy   = .free_onsite,
        },

        .widget_title       = "Get a rough quote",
        .widget_greeting    = "G'day! Tell me about the job and I'll give you a rough ballpark. What's going on?",
        .widget_placeholder = "Describe the job — e.g. 'dripping kitchen tap' or '3 fence panels need replacing'...",
        .widget_endpoint    = "/api/v1/chat",
    };
}

```
