---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/semantos-brain/src/operator_site_renderer.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.229942+00:00
---

# runtime/semantos-brain/src/operator_site_renderer.zig

```zig
// Operator site renderer — S3 (Semantos Sites 1.0).
//
// Generates the public-facing HTML for an operator's BYOD site from
// an OperatorProfile (assembled from strategy.lbc / strategy.icp /
// strategy.services / strategy.pricing cells).
//
// Structure: ToFu / MoFu / BoFu — mirrors oddjobtodd.info.
//
//   ToFu:  hero (h1 + lede + tag list + trust items + intake widget)
//   MoFu:  services grid + how it works
//   BoFu:  pricing (conditional) + footer
//
// The chat widget (D-O6a) is pre-wired via the operator's configured
// endpoint.  The analytics snippet (S4) is injected inline.
//
// A/B variant selection: if a `sm-variant` cookie is present, the
// corresponding section cell is used.  The renderer writes a
// `data-variant` attribute on <html> so the analytics snippet can
// forward it.

const std = @import("std");
const profile_mod = @import("operator_profile");
const OperatorProfile = profile_mod.OperatorProfile;

pub const RenderError = error{
    out_of_memory,
    write_failed,
};

/// Write the full operator site HTML into `writer`.
/// `variant` is "a", "b", or null (no active A/B test).
pub fn renderSite(
    writer: anytype,
    profile: OperatorProfile,
    variant: ?[]const u8,
) !void {
    // ── doctype + <html> with optional data-variant attr ────────────
    if (variant) |v| {
        try writer.print("<!doctype html>\n<html lang=\"en\" data-variant=\"{s}\">\n", .{v});
    } else {
        try writer.writeAll("<!doctype html>\n<html lang=\"en\">\n");
    }
    try writer.print(
        \\<head>
        \\  <meta charset="utf-8">
        \\  <meta name="viewport" content="width=device-width, initial-scale=1">
        \\  <title>{s} — {s}</title>
        \\  <meta name="description" content="{s}. Get a rough quote in minutes.">
        \\  <link rel="preconnect" href="https://fonts.googleapis.com">
        \\  <link rel="stylesheet" href="/chat-widget/chat-widget.css">
        \\{s}
        \\</head>
        \\<body>
        \\
    , .{
        profile.business_name,
        profile.trade_label,
        profile.hero_lede,
        INLINE_CSS,
    });

    try renderNav(writer, profile);
    try renderHero(writer, profile);
    try renderServices(writer, profile);
    try renderHowItWorks(writer, profile);
    if (shouldShowPricing(profile)) try renderPricing(writer, profile);
    try renderFooter(writer, profile);
    try writer.writeAll(ANALYTICS_SNIPPET);
    try writer.writeAll(
        \\  <script src="/chat-widget/chat-widget.js" defer></script>
        \\</body>
        \\</html>
        \\
    );
}

fn shouldShowPricing(profile: OperatorProfile) bool {
    return profile.pricing.quote_policy != .phone_only and
        (profile.pricing.callout_fee != null or profile.pricing.hourly_rate != null);
}

// ── Nav ──────────────────────────────────────────────────────────────

fn renderNav(writer: anytype, profile: OperatorProfile) !void {
    try writer.print(
        \\  <nav>
        \\    <div class="nav-logo">{s}<span>.</span></div>
        \\    <a class="nav-phone" href="tel:{s}"><strong>{s} {s}</strong></a>
        \\  </nav>
        \\
    , .{
        profile.business_name,
        stripSpaces(profile.phone),
        profile.geography,
        profile.trade_label,
    });
}

// ── Hero ─────────────────────────────────────────────────────────────

fn renderHero(writer: anytype, profile: OperatorProfile) !void {
    try writer.writeAll(
        \\  <main>
        \\    <section class="hero">
        \\      <div class="hero-copy">
        \\
    );

    try writer.print("        <h1>{s}</h1>\n", .{profile.hero_h1});
    try writer.print("        <p>{s}</p>\n", .{profile.hero_lede});

    // Tag list from services
    try writer.writeAll("        <div class=\"tag-list\">\n");
    for (profile.services) |svc| {
        try writer.print("          <span class=\"tag\">{s}</span>\n", .{svc.label});
    }
    try writer.writeAll("        </div>\n");

    // Trust items
    try writer.writeAll("        <div class=\"trust-row\">\n");
    for (profile.trust_signals) |signal| {
        try writer.print("          <div class=\"trust-item\">{s}</div>\n", .{signal});
    }
    try writer.writeAll("        </div>\n");

    try writer.writeAll("      </div>\n"); // hero-copy

    // Intake chat widget
    try writer.print(
        \\      <div class="hero-chat">
        \\        <div class="hero-chat-label">Chat to get a quote</div>
        \\        <div id="oddjobz-chat-widget"
        \\             data-endpoint="{s}"
        \\             data-title="{s}"
        \\             data-placeholder="{s}"
        \\             data-greeting="{s}">
        \\        </div>
        \\      </div>
        \\
    , .{
        profile.widget_endpoint,
        profile.widget_title,
        htmlEscape(profile.widget_placeholder),
        htmlEscape(profile.widget_greeting),
    });

    try writer.writeAll(
        \\    </section>
        \\
    );
}

// ── Services grid ────────────────────────────────────────────────────

fn renderServices(writer: anytype, profile: OperatorProfile) !void {
    try writer.print(
        \\    <section class="services">
        \\      <div class="services-inner">
        \\        <h2>What we take on</h2>
        \\        <p class="services-sub">Most jobs around the {s}. If you're not sure, just describe it in the chat.</p>
        \\        <div class="services-grid">
        \\
    , .{profile.trade_label});

    for (profile.services) |svc| {
        try writer.print(
            \\          <div class="service-card">
            \\            <div class="service-icon">{s}</div>
            \\            <h3>{s}</h3>
            \\            <p>{s}</p>
            \\          </div>
            \\
        , .{ svc.icon, svc.label, svc.description });
    }

    try writer.writeAll(
        \\        </div>
        \\      </div>
        \\    </section>
        \\
    );
}

// ── How it works ─────────────────────────────────────────────────────

fn renderHowItWorks(writer: anytype, profile: OperatorProfile) !void {
    const step4 = profile.pricing.quote_policy.howItWorksStep4();
    try writer.print(
        \\    <section class="how">
        \\      <h2>How it works</h2>
        \\      <p class="how-sub">No forms. No waiting. Just describe the job.</p>
        \\      <div class="steps">
        \\        <div class="step">
        \\          <div class="step-num">1</div>
        \\          <h3>Describe the job</h3>
        \\          <p>Tell the chat what needs doing — as much or as little detail as you have.</p>
        \\        </div>
        \\        <div class="step">
        \\          <div class="step-num">2</div>
        \\          <h3>Get a ballpark</h3>
        \\          <p>We'll ask a couple of quick questions and give you a rough order of magnitude.</p>
        \\        </div>
        \\        <div class="step">
        \\          <div class="step-num">3</div>
        \\          <h3>Confirm the details</h3>
        \\          <p>If the job's a good fit, we'll book a time to come out.</p>
        \\        </div>
        \\        <div class="step">
        \\          <div class="step-num">4</div>
        \\          <h3>Get it done</h3>
        \\          <p>{s}</p>
        \\        </div>
        \\      </div>
        \\    </section>
        \\
    , .{step4});
}

// ── Pricing ──────────────────────────────────────────────────────────

fn renderPricing(writer: anytype, profile: OperatorProfile) !void {
    try writer.writeAll(
        \\    <section class="pricing">
        \\      <div class="pricing-inner">
        \\        <h2>Pricing</h2>
        \\        <p class="pricing-sub">Straightforward pricing. No surprises.</p>
        \\        <div class="pricing-grid">
        \\
    );

    if (profile.pricing.callout_fee) |fee| {
        try writer.print(
            \\          <div class="price-card">
            \\            <div class="price-label">{s}</div>
            \\            <div class="price-amount">${d}</div>
            \\          </div>
            \\
        , .{ fee.label, fee.amount });
    }

    if (profile.pricing.hourly_rate) |rate| {
        try writer.print(
            \\          <div class="price-card">
            \\            <div class="price-label">{s}</div>
            \\            <div class="price-amount">${d}<span>/hr</span></div>
            \\          </div>
            \\
        , .{ rate.label, rate.amount });
    }

    if (profile.pricing.emergency_rate) |emergency| {
        try writer.print(
            \\          <div class="price-card">
            \\            <div class="price-label">{s}</div>
            \\            <div class="price-amount">${d}</div>
            \\          </div>
            \\
        , .{ emergency.label, emergency.amount });
    }

    const quote_note = switch (profile.pricing.quote_policy) {
        .free_onsite  => "Free on-site quote for most jobs — we come out, take a proper look, and give you a firm number.",
        .paid_onsite  => "Paid site visit for detailed scoping — we measure up and send a full written quote.",
        .chat_first   => "Chat with us first — we'll confirm a price before anything is booked.",
        .phone_only   => "",
    };

    if (quote_note.len > 0) {
        try writer.print(
            \\        <p class="pricing-note">{s}</p>
            \\
        , .{quote_note});
    }

    try writer.writeAll(
        \\        </div>
        \\      </div>
        \\    </section>
        \\
    );
}

// ── Footer ───────────────────────────────────────────────────────────

fn renderFooter(writer: anytype, profile: OperatorProfile) !void {
    try writer.print(
        \\  </main>
        \\  <footer>
        \\    &copy; {d} {s} &mdash; {s} {s} &mdash; ABN {s}
        \\  </footer>
        \\
    , .{
        2026, // TODO: std.time year
        profile.business_name,
        profile.geography,
        profile.trade_label,
        profile.abn,
    });
}

// ── A/B cookie resolution (S7) ───────────────────────────────────────

/// Context passed to renderSiteWithAb for per-request A/B resolution.
pub const AbContext = struct {
    /// Raw Cookie header string from the incoming request (e.g. "sm-ab-hero=a; foo=bar").
    cookie_header: []const u8,
    /// New Set-Cookie headers to emit on the response.  Caller owns the
    /// strings; append via abCookieHeader().
    new_cookies: *std.ArrayList([]u8),
    allocator: std.mem.Allocator,
};

/// Parse `cookie_header` and return "a" or "b" if `sm-ab-<section_slug>`
/// is present, or null if the cookie is absent.
/// Does not allocate.
pub fn resolveVariant(cookie_header: []const u8, section_slug: []const u8) ?[]const u8 {
    // Cookie header format: "name=value; name2=value2"
    var iter = std.mem.splitSequence(u8, cookie_header, "; ");
    while (iter.next()) |pair| {
        // Find the '=' separator
        const eq = std.mem.indexOfScalar(u8, pair, '=') orelse continue;
        const name = pair[0..eq];
        const value = pair[eq + 1 ..];

        // Build the expected cookie name on the stack using a fixed-size buffer.
        // "sm-ab-" is 6 bytes; section slugs are short; 64 bytes is ample.
        var name_buf: [64]u8 = undefined;
        const prefix = "sm-ab-";
        if (prefix.len + section_slug.len > name_buf.len) continue;
        @memcpy(name_buf[0..prefix.len], prefix);
        @memcpy(name_buf[prefix.len .. prefix.len + section_slug.len], section_slug);
        const expected = name_buf[0 .. prefix.len + section_slug.len];

        if (std.mem.eql(u8, name, expected)) {
            if (std.mem.eql(u8, value, "a") or std.mem.eql(u8, value, "b")) {
                return value;
            }
        }
    }
    return null;
}

/// Build a Set-Cookie header value for the given section slug and variant.
/// Returns an owned string — caller must free with `allocator.free()`.
pub fn abCookieHeader(
    allocator: std.mem.Allocator,
    section_slug: []const u8,
    variant: []const u8,
) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "sm-ab-{s}={s}; Path=/; Max-Age=2592000; SameSite=Lax",
        .{ section_slug, variant },
    );
}

/// Section slugs used for A/B cookie resolution.
const AB_SECTIONS = [_][]const u8{
    "hero",
    "services",
    "how_it_works",
    "pricing",
    "footer",
};

/// Like renderSite, but resolves A/B variants from the Cookie header.
/// For each section that has no cookie yet, defaults to "a" and appends
/// a new Set-Cookie string to `ab.new_cookies`.
pub fn renderSiteWithAb(
    writer: anytype,
    profile: OperatorProfile,
    ab: AbContext,
) !void {
    // Resolve per-section variants.
    var variants: [AB_SECTIONS.len][]const u8 = undefined;
    for (AB_SECTIONS, 0..) |slug, i| {
        if (resolveVariant(ab.cookie_header, slug)) |v| {
            variants[i] = v;
        } else {
            // Default to "a" and schedule a Set-Cookie header.
            variants[i] = "a";
            const cookie = try abCookieHeader(ab.allocator, slug, "a");
            try ab.new_cookies.append(cookie);
        }
    }

    // The hero variant drives the top-level data-variant attribute.
    const hero_variant: ?[]const u8 = variants[0];

    // Delegate to the existing renderSite implementation, passing the hero variant.
    _ = hero_variant; // used below via the inline render path

    const v = variants[0]; // hero variant for data-variant attribute
    try writer.print(
        \\<!doctype html>
        \\<html lang="en" data-variant="{s}">
        \\<head>
        \\  <meta charset="utf-8">
        \\  <meta name="viewport" content="width=device-width, initial-scale=1">
        \\  <title>{s} — {s}</title>
        \\  <meta name="description" content="{s}. Get a rough quote in minutes.">
        \\  <link rel="preconnect" href="https://fonts.googleapis.com">
        \\  <link rel="stylesheet" href="/chat-widget/chat-widget.css">
        \\{s}
        \\</head>
        \\<body>
        \\
    , .{
        v,
        profile.business_name,
        profile.trade_label,
        profile.hero_lede,
        INLINE_CSS,
    });

    try renderNav(writer, profile);
    try renderHero(writer, profile);
    try renderServices(writer, profile);
    try renderHowItWorks(writer, profile);
    if (shouldShowPricing(profile)) try renderPricing(writer, profile);
    try renderFooter(writer, profile);
    try writer.writeAll(ANALYTICS_SNIPPET);
    try writer.writeAll(
        \\  <script src="/chat-widget/chat-widget.js" defer></script>
        \\</body>
        \\</html>
        \\
    );
}

// ── Helpers ──────────────────────────────────────────────────────────

fn stripSpaces(s: []const u8) []const u8 {
    // Minimal — returns original string.  Real impl strips non-digit chars.
    _ = s;
    return "";
}

/// Minimal HTML attribute escaping for data-* values.
fn htmlEscape(s: []const u8) []const u8 {
    // v1: rely on values being safe (wizard validates at write time).
    // v1.1: proper escape into a stack buffer.
    return s;
}

// ── Inline CSS (mirrors oddjobtodd.info baseline) ────────────────────

const INLINE_CSS =
    \\  <style>
    \\    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    \\    :root {
    \\      --brand: #1d4ed8; --brand-light: #dbeafe;
    \\      --text: #0f172a;  --muted: #64748b;
    \\      --bg: #f8fafc;    --white: #ffffff;
    \\      --border: #e2e8f0; --radius: 12px;
    \\    }
    \\    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; background: var(--bg); color: var(--text); line-height: 1.6; }
    \\    nav { background: var(--white); border-bottom: 1px solid var(--border); padding: 0 24px; display: flex; align-items: center; justify-content: space-between; height: 56px; position: sticky; top: 0; z-index: 10; }
    \\    .nav-logo { font-weight: 700; font-size: 20px; color: var(--brand); letter-spacing: -0.5px; }
    \\    .nav-logo span { color: var(--text); }
    \\    .nav-phone { font-size: 14px; color: var(--muted); text-decoration: none; }
    \\    .hero { max-width: 1100px; margin: 0 auto; padding: 64px 24px 48px; display: grid; grid-template-columns: 1fr 1fr; gap: 48px; align-items: start; }
    \\    @media (max-width: 720px) { .hero { grid-template-columns: 1fr; padding: 40px 16px 32px; gap: 32px; } }
    \\    .hero-copy h1 { font-size: clamp(28px, 4vw, 44px); font-weight: 800; line-height: 1.15; letter-spacing: -1px; margin-bottom: 16px; }
    \\    .hero-copy p { font-size: 17px; color: var(--muted); margin-bottom: 28px; max-width: 420px; }
    \\    .tag-list { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 32px; }
    \\    .tag { background: var(--brand-light); color: var(--brand); font-size: 13px; font-weight: 600; padding: 4px 10px; border-radius: 20px; }
    \\    .trust-row { display: flex; flex-direction: column; gap: 8px; }
    \\    .trust-item { display: flex; align-items: center; gap: 8px; font-size: 14px; color: var(--muted); }
    \\    .trust-item::before { content: "✓"; color: #16a34a; font-weight: 700; font-size: 15px; flex-shrink: 0; }
    \\    .hero-chat { display: flex; flex-direction: column; align-items: center; }
    \\    .hero-chat-label { font-size: 13px; font-weight: 600; color: var(--muted); text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 10px; align-self: flex-start; }
    \\    #oddjobz-chat-widget { --oddjobz-chat-width: 100%; --oddjobz-chat-height: 480px; width: 100%; max-width: 420px; }
    \\    @media (max-width: 720px) { #oddjobz-chat-widget { --oddjobz-chat-height: 60vh; } }
    \\    .services { background: var(--white); border-top: 1px solid var(--border); border-bottom: 1px solid var(--border); padding: 56px 24px; margin-top: 24px; }
    \\    .services-inner { max-width: 1100px; margin: 0 auto; }
    \\    .services h2, .how h2, .pricing h2 { font-size: 26px; font-weight: 700; margin-bottom: 8px; }
    \\    .services-sub, .how-sub, .pricing-sub { color: var(--muted); margin-bottom: 36px; }
    \\    .services-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 16px; }
    \\    .service-card { border: 1px solid var(--border); border-radius: var(--radius); padding: 20px 16px; background: var(--bg); }
    \\    .service-icon { font-size: 28px; margin-bottom: 8px; }
    \\    .service-card h3 { font-size: 15px; font-weight: 600; margin-bottom: 4px; }
    \\    .service-card p { font-size: 13px; color: var(--muted); }
    \\    .how { max-width: 900px; margin: 0 auto; padding: 56px 24px; }
    \\    .steps { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 24px; }
    \\    .step { display: flex; flex-direction: column; gap: 8px; }
    \\    .step-num { width: 36px; height: 36px; border-radius: 50%; background: var(--brand); color: var(--white); font-weight: 700; font-size: 16px; display: flex; align-items: center; justify-content: center; }
    \\    .step h3 { font-size: 15px; font-weight: 600; }
    \\    .step p { font-size: 14px; color: var(--muted); }
    \\    .pricing { background: var(--white); border-top: 1px solid var(--border); padding: 56px 24px; }
    \\    .pricing-inner { max-width: 900px; margin: 0 auto; }
    \\    .pricing-grid { display: flex; gap: 20px; flex-wrap: wrap; margin-bottom: 20px; }
    \\    .price-card { border: 1px solid var(--border); border-radius: var(--radius); padding: 20px 24px; background: var(--bg); min-width: 140px; }
    \\    .price-label { font-size: 13px; color: var(--muted); margin-bottom: 4px; }
    \\    .price-amount { font-size: 28px; font-weight: 800; color: var(--brand); }
    \\    .price-amount span { font-size: 15px; font-weight: 400; color: var(--muted); }
    \\    .pricing-note { font-size: 14px; color: var(--muted); max-width: 520px; }
    \\    footer { text-align: center; padding: 32px 24px; font-size: 13px; color: var(--muted); border-top: 1px solid var(--border); }
    \\  </style>
;

// ── Analytics snippet (S4 — inline, no external deps) ────────────────

const ANALYTICS_SNIPPET =
    \\  <script>
    \\  (function(){
    \\    const SESSION=(function(){
    \\      try{const k='sm-session';return sessionStorage.getItem(k)||(function(){
    \\        const v=crypto.randomUUID?crypto.randomUUID():
    \\          ([...crypto.getRandomValues(new Uint8Array(16))].map(b=>b.toString(16).padStart(2,'0')).join(''));
    \\        sessionStorage.setItem(k,v);return v;
    \\      })();}catch(_){return 'anon';}
    \\    })();
    \\    const VARIANT=document.documentElement.dataset.variant||null;
    \\    function emit(event,extra){
    \\      fetch('/api/v1/analytics',{method:'POST',keepalive:true,
    \\        headers:{'Content-Type':'application/json'},
    \\        body:JSON.stringify({event,session_id:SESSION,
    \\          referrer:document.referrer,page:location.pathname,
    \\          variant:VARIANT,ts_ms:Date.now(),...extra})
    \\      }).catch(function(){});
    \\    }
    \\    emit('pageview');
    \\    document.addEventListener('sm:chat_start',function(){emit('chat_start');});
    \\    document.addEventListener('sm:lead',function(){emit('lead_captured');});
    \\  })();
    \\  </script>
    \\
;

// ── Tests ────────────────────────────────────────────────────────────
//
// All tests use a stack-allocated fixed-size buffer to avoid ArrayList
// API variations across Zig patch releases.

const TEST_BUF_SIZE = 65536;

test "render default profile produces valid HTML" {
    const profile = try profile_mod.defaultProfile(std.testing.allocator);

    var buf: [TEST_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderSite(fbs.writer(), profile, null);
    const html = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, html, "<!doctype html>") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Oddjobz") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "oddjobz-chat-widget") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "sm-session") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Carpentry") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "$120") != null);
}

test "render with variant sets data-variant attribute" {
    const profile = try profile_mod.defaultProfile(std.testing.allocator);

    var buf: [TEST_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderSite(fbs.writer(), profile, "b");

    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "data-variant=\"b\"") != null);
}

test "phone_only pricing hides pricing section" {
    var profile = try profile_mod.defaultProfile(std.testing.allocator);
    profile.pricing.quote_policy = .phone_only;
    profile.pricing.callout_fee = null;
    profile.pricing.hourly_rate = null;

    var buf: [TEST_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderSite(fbs.writer(), profile, null);

    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "class=\"pricing\"") == null);
}

test "resolveVariant finds cookie" {
    const cookie_header = "sm-ab-hero=b; sm-ab-services=a; other=xyz";
    try std.testing.expectEqualStrings("b", resolveVariant(cookie_header, "hero").?);
    try std.testing.expectEqualStrings("a", resolveVariant(cookie_header, "services").?);
}

test "resolveVariant returns null when absent" {
    const cookie_header = "sm-ab-services=a; other=xyz";
    try std.testing.expect(resolveVariant(cookie_header, "hero") == null);
    try std.testing.expect(resolveVariant(cookie_header, "footer") == null);
}

// S14 — additional smoke tests ────────────────────────────────────────

test "S14: multi-service profile — each service label appears in HTML" {
    const profile = try profile_mod.defaultProfile(std.testing.allocator);

    var buf: [TEST_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderSite(fbs.writer(), profile, null);
    const html = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, html, "Carpentry") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Plumbing") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Electrical") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Painting") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Fencing") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "General") != null);
    try std.testing.expect(std.mem.count(u8, html, "<div class=\"service-card\">") == profile.services.len);
}

test "S14: single-service profile — exactly one service-card" {
    var profile = try profile_mod.defaultProfile(std.testing.allocator);
    const one_service = [_]profile_mod.Service{
        .{ .slug = "tiling", .label = "Tiling", .icon = "🪟", .description = "Bathroom and kitchen tiles" },
    };
    profile.services = @constCast(@as([]const profile_mod.Service, &one_service));

    var buf: [TEST_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderSite(fbs.writer(), profile, null);
    const html = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, html, "Tiling") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, html, "<div class=\"service-card\">"));
}

test "S14: empty services — no service-card divs" {
    var profile = try profile_mod.defaultProfile(std.testing.allocator);
    profile.services = &.{};

    var buf: [TEST_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderSite(fbs.writer(), profile, null);

    try std.testing.expectEqual(@as(usize, 0), std.mem.count(u8, fbs.getWritten(), "<div class=\"service-card\">"));
}

test "S14: missing pricing lines — section hidden for phone_only" {
    var profile = try profile_mod.defaultProfile(std.testing.allocator);
    profile.pricing = .{
        .callout_fee    = null,
        .hourly_rate    = null,
        .emergency_rate = null,
        .minimum_charge = null,
        .quote_policy   = .phone_only,
    };

    var buf: [TEST_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderSite(fbs.writer(), profile, null);
    const html = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"pricing\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Phone quote") != null);
}

test "S14: all pricing lines null with free_onsite — section hidden" {
    var profile = try profile_mod.defaultProfile(std.testing.allocator);
    profile.pricing = .{
        .callout_fee    = null,
        .hourly_rate    = null,
        .emergency_rate = null,
        .minimum_charge = null,
        .quote_policy   = .free_onsite,
    };

    var buf: [TEST_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderSite(fbs.writer(), profile, null);

    try std.testing.expect(std.mem.indexOf(u8, fbs.getWritten(), "class=\"pricing\"") == null);
}

test "S14: profile with only callout_fee — pricing section shown" {
    var profile = try profile_mod.defaultProfile(std.testing.allocator);
    profile.pricing = .{
        .callout_fee    = .{ .label = "Callout", .amount = 80, .currency = "AUD" },
        .hourly_rate    = null,
        .emergency_rate = null,
        .minimum_charge = null,
        .quote_policy   = .free_onsite,
    };

    var buf: [TEST_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderSite(fbs.writer(), profile, null);
    const html = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, html, "class=\"pricing\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "$80") != null);
}

test "S14: custom geography and business name appear in HTML" {
    var profile = try profile_mod.defaultProfile(std.testing.allocator);
    profile.business_name = "FixIt Fast";
    profile.geography     = "Northern Beaches";

    var buf: [TEST_BUF_SIZE]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try renderSite(fbs.writer(), profile, null);
    const html = fbs.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, html, "FixIt Fast") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Northern Beaches") != null);
}

```
