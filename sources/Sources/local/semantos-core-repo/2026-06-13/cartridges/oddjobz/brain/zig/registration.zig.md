---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/oddjobz/brain/zig/registration.zig
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.479864+00:00
---

# cartridges/oddjobz/brain/zig/registration.zig

```zig
// oddjobz cartridge brain registration — C5 cartridge_seam entry-point.
//
// Reference: docs/design/BRAIN-EXTENSION-LOADER.md §6b
//   ("one-registerInto-per-cartridge convention") + §3 (registerInto
//    contract) + §8 (test strategy).
//
// ── What this module is ──────────────────────────────────────────────
//
// The cartridge-bootstrap entry-point for the oddjobz cartridge.
// Called once at brain boot by cartridge_seam.dispatchRegistrations
// when cartridges/oddjobz/cartridge.json declares
// `brain.handlers: [{ "module": "registration" }]`.
//
// C4 PR-H2b-1 scope (the §6b store carve — "dispatcher handlers first"):
// registerInto now constructs the EIGHT oddjobz shared typed stores
// (jobs/customers/sites/visits/quotes/estimates/invoices/attachments)
// + the SEVEN dispatcher handlers (the six FSM/affine resources +
// attachments), ONCE, with the FK pointers co-located. (C4 PR-J6: the
// orphaned `leads` store + handler were deleted — superseded by job.v2
// state:"lead".) The
// stores are published into deps.store_registry so the brain's remaining
// consumers (the WSS query/attention/ratify handlers + the store-coupled HTTP
// acceptors still in serve.zig) read them through the seam. serve.zig no longer
// constructs the cluster. The non-dispatcher consumers degrade transiently
// (they read the now-late-filled registry) until PR-H2b-2 relocates them past
// this dispatch point — the accepted "consumers after" phase.
//
// Why one registration.zig per cartridge (§6b convention): handlers
// sharing stores can't each construct their own copy without
// conflicting LMDB opens. ALL oddjobz shared infra construction
// happens here, ONCE. The eight typed stores are thin typed VIEWS over
// the shared entity CellStore (deps.cell_store) — one LMDB env the brain
// owns + outlives them; the heap-allocated views leak at process exit
// (matches the prior serve-scope + attachments posture).
//
// RESTORED here (was a tracked regression): the `find jobs` → emit
// attachments[] late-bind (`jh.setAttachmentsStore(as)`) — now that the
// jobs handler + the attachments store are co-located, the late-bind is
// internal to registerInto.

const std = @import("std");
const dispatcher = @import("dispatcher");
const cartridge_seam = @import("cartridge_seam");
const oddjobz_repl_verbs = @import("oddjobz_repl_verbs"); // C4 PR-R3b — REPL verb forms
const attachments_handler = @import("attachments_handler");
const attachments_store_fs = @import("attachments_store_fs");
// C4 PR-H2b-1 — the §6b store cluster: the eight other typed stores + their
// dispatcher handlers, migrated off cli/serve.zig into this registerInto.
const jobs_store_fs = @import("jobs_store_fs");
const customers_store_fs = @import("customers_store_fs");
const sites_store_fs = @import("sites_store_fs");
const visits_store_fs = @import("visits_store_fs");
const quotes_store_fs = @import("quotes_store_fs");
const estimates_store_fs = @import("estimates_store_fs");
const invoices_store_fs = @import("invoices_store_fs");
const jobs_handler = @import("jobs_handler");
const customers_handler = @import("customers_handler");
const visits_handler = @import("visits_handler");
const quotes_handler = @import("quotes_handler");
const estimates_handler = @import("estimates_handler");
const invoices_handler = @import("invoices_handler");
// C4 PR-G2 — customer-link-resolve route, migrated off the brain.
const http_route_registry = @import("http_route_registry");
const http_parser = @import("http_parser");
const propose_turn_http = @import("propose_turn_http");
// C4 PR-G3 — conversation-turns-query route, migrated off the brain.
const conv_turns_query_http = @import("conv_turns_query_http");
const events_stream_handler = @import("events_stream_handler");
// C4 PR-G5 — conv-approve route, migrated off the brain.
const conversation_approve_http = @import("conversation_approve_http");
// C4 PR-G6 — re-anchor route, migrated off the brain.
const re_anchor_http = @import("re_anchor_http");
// C4 PR-G7 — voice-note route, migrated off the brain.
const voice_note_http = @import("voice_note_http");
// C4 PR-H3 — search-contacts route, migrated off the brain (store-backed).
const search_contacts_http = @import("search_contacts_http");
const bearer_tokens_mod = @import("bearer_tokens");
// C4 PR-H6 — attachment blob store (cartridge constructs + owns it).
const attachment_blobs_fs = @import("attachment_blobs_fs");
// C4 PR-H7b — attachments-upload route (multipart + cell-sig verify).
const attachments_upload_http = @import("attachments_upload_http");
const identity_certs = @import("identity_certs");
const bkds = @import("bkds");
// C4 PR-I1 — conversation-send route (outbound SMS via Twilio).
const conversation_send_http = @import("conversation_send_http");
const twilio_adapter = @import("twilio_adapter");
// C4 PR-I2 — twilio-inbound route (form-encoded webhook → bun intake script).
const twilio_inbound_http = @import("twilio_inbound_http");
// C4 CW-1 — web chat widget route (JSON webhook → bun intake script). The
// cartridge-owned twin of the retired brain `intake` site-route + chat_http.
const web_chat_http = @import("web_chat_http");
const oddjobz_ingest_handler = @import("oddjobz_ingest_handler"); // LI-2 — `ingest` resource
const oddjobz_legacy_http = @import("oddjobz_legacy_http"); // LI-3c — legacy admin HTTP + OAuth callback
// DO-3 — read the operator profile's widget_enabled at request time for the live
// enable gate (the serve-held profile DO-2's widget_set mutates).
const operator_profile_mod = @import("operator_profile");
// C4 PR-J2 — generic cell.query decoders: register a per-cellType decoder so the
// brain's cell.query (cells_by_type index) renders oddjobz cells without naming us.
const cell_decoder_registry = @import("cell_decoder_registry");
const cell_store_mod = @import("cell_store");
const substrate_entity = @import("substrate_entity");

/// Millisecond clock — local to this cartridge (no cross-module
/// import on cli_common's realClock). Used by AttachmentsStore for
/// timestamps on stored attachment records.
fn realClock() i64 {
    return std.time.milliTimestamp();
}

/// Cartridge-bootstrap registerInto per §3 contract + §6b convention.
/// Called by cartridge_seam.dispatchRegistrations at brain boot.
///
/// Construction posture (matches the prior cli/serve.zig pattern):
///   - heap-alloc AttachmentsStore — lives for brain lifetime,
///     borrowed by the Handler via *AttachmentsStore pointer
///   - heap-alloc Handler — lives for brain lifetime, registered
///     against the dispatcher via resourceHandler() v-table
///   - intentional leak: brain process owns these for its full run;
///     no deinit path in this codepath (matches serve.zig posture
///     for the equivalent serve-scope objects pre-migration)
///
/// FK validation degraded posture: visits_store_fs = null. The
/// attachments store still validates length envelope on visit_id;
/// strict FK validation lands when visits_handler migrates and
/// both pointers are co-located in registration.zig (PR-4b-3-cont).
pub fn registerInto(
    disp: *dispatcher.Dispatcher,
    allocator: std.mem.Allocator,
    deps: *const cartridge_seam.CartridgeDeps,
) anyerror!void {
    // ── Step 1 — construct ALL EIGHT shared typed stores ONCE (§6b) ───────
    // Each is a thin typed view over the shared entity CellStore
    // (deps.cell_store). Heap-allocated so the pointer is stable for the
    // brain's lifetime — borrowed by the handlers + published into the store
    // registry for the brain's remaining consumers. Fail-fast per §3 #4: an
    // init error HALTS BOOT (cartridges are trusted code; a broken cartridge
    // is a deployment problem). No deinit path — process exit reclaims (the
    // brain owns + outlives the underlying LMDB env).
    const jobs_store = try allocator.create(jobs_store_fs.JobsStore);
    errdefer allocator.destroy(jobs_store);
    jobs_store.* = try jobs_store_fs.JobsStore.initWithContentStore(
        allocator,
        deps.cell_store,
        realClock,
        deps.content_store, // octave-1 overflow (null-degrades) — C4 PR-H1
    );
    // CC-3 — stamp the operator ownerId into minted job cells (owner-bound →
    // UTXO-binding-eligible). Null when no operator cert yet → unsigned default.
    if (deps.operator_owner_id) |owner| jobs_store.setOwnerId(owner);

    const customers_store = try allocator.create(customers_store_fs.CustomersStore);
    errdefer allocator.destroy(customers_store);
    customers_store.* = try customers_store_fs.CustomersStore.init(allocator, deps.cell_store, realClock);

    const sites_store = try allocator.create(sites_store_fs.SitesStore);
    errdefer allocator.destroy(sites_store);
    sites_store.* = try sites_store_fs.SitesStore.init(allocator, deps.cell_store, realClock);

    const visits_store = try allocator.create(visits_store_fs.VisitsStore);
    errdefer allocator.destroy(visits_store);
    visits_store.* = try visits_store_fs.VisitsStore.init(allocator, deps.cell_store, realClock);

    const quotes_store = try allocator.create(quotes_store_fs.QuotesStore);
    errdefer allocator.destroy(quotes_store);
    quotes_store.* = try quotes_store_fs.QuotesStore.init(allocator, deps.cell_store, realClock);

    const estimates_store = try allocator.create(estimates_store_fs.EstimatesStore);
    errdefer allocator.destroy(estimates_store);
    estimates_store.* = try estimates_store_fs.EstimatesStore.init(allocator, deps.cell_store, realClock);

    const invoices_store = try allocator.create(invoices_store_fs.InvoicesStore);
    errdefer allocator.destroy(invoices_store);
    invoices_store.* = try invoices_store_fs.InvoicesStore.init(allocator, deps.cell_store, realClock);

    const attachments_store = try allocator.create(attachments_store_fs.AttachmentsStore);
    errdefer allocator.destroy(attachments_store);
    attachments_store.* = try attachments_store_fs.AttachmentsStore.init(allocator, deps.cell_store, realClock);

    // C4 PR-H6 — the attachment blob store: filesystem-backed (not a cell-store
    // view), constructed over the brain data dir. Creates <data_dir>/oddjobz/
    // blobs/. Owned for the brain's lifetime; serves the blob-GET route below +
    // (until PR-H7) serve.zig's still-present upload acceptor via the registry.
    const blob_store = try allocator.create(attachment_blobs_fs.BlobStore);
    errdefer allocator.destroy(blob_store);
    blob_store.* = try attachment_blobs_fs.BlobStore.init(allocator, deps.site_data_dir);

    // Publish into the store registry (the §6b seam, C4 PR-H1) so the brain's
    // remaining store consumers read them. Null only in tests / a brain
    // without the registry.
    if (deps.store_registry) |reg| {
        reg.jobs = jobs_store;
        reg.customers = customers_store;
        reg.sites = sites_store;
        reg.visits = visits_store;
        reg.quotes = quotes_store;
        reg.estimates = estimates_store;
        reg.invoices = invoices_store;
        reg.attachments = attachments_store;
        reg.attachment_blobs = blob_store;
    }

    // cell.query decoders — SUBSTRATE-DIRECT (raw canonical payload, option A).
    // Each decoder reads the cell straight from deps.cell_store by content hash
    // and returns its raw payload JSON (with `cellHash` = the content hash
    // injected). NO view-store dependency, NO per-type *ToJson translation — the
    // cell IS the wire shape (Todd's "brain and PWA on the SAME cells, no
    // translation layer"). Candidate enumeration is the generic cells_by_type
    // index (every `put` writes it; prod is backfilled), so no `enumerate`
    // callback. job/attachment keep a `matches_filter` that parses the raw
    // payload's ref fields (site_ref / customer_refs[].cell_id / jobRef).
    if (deps.cell_decoder_registry) |cdr| {
        const cs_ctx: *anyopaque = @ptrCast(@constCast(deps.cell_store));
        cdr.add(.{
            .type_hash = substrate_entity.computeTypeHash(substrate_entity.SPEC_SITE),
            .alias = "oddjobz.site.v2",
            .collection_key = "sites",
            .singular_key = "site",
            .allow_unfiltered_list = true,
            .ctx = cs_ctx,
            .decode_one = substrateDecodeOne,
        });
        cdr.add(.{
            .type_hash = substrate_entity.computeTypeHash(substrate_entity.SPEC_CUSTOMER),
            .alias = "oddjobz.customer.v2",
            .collection_key = "customers",
            .singular_key = "customer",
            .allow_unfiltered_list = true,
            .ctx = cs_ctx,
            .decode_one = substrateDecodeOne,
        });
        cdr.add(.{
            .type_hash = substrate_entity.computeTypeHash(substrate_entity.SPEC_JOB),
            .alias = "oddjobz.job.v2",
            .collection_key = "jobs",
            .singular_key = "job",
            // List-all enabled: `query jobs` / `find jobs` is the operator Home
            // read (the app then resolves site_ref/customer_refs locally). The
            // optional siteRef/customerRef filter still narrows when supplied.
            .allow_unfiltered_list = true,
            .ctx = cs_ctx,
            .decode_one = substrateDecodeOne,
            .matches_filter = jobMatchesFilter,
        });
        cdr.add(.{
            .type_hash = substrate_entity.computeTypeHash(substrate_entity.SPEC_ATTACHMENT),
            .alias = "oddjobz.attachment.v2",
            .collection_key = "attachments",
            .singular_key = "attachment",
            .allow_unfiltered_list = false,
            .ctx = cs_ctx,
            .decode_one = substrateDecodeOne,
            .matches_filter = attachmentMatchesFilter,
        });
        std.log.info("oddjobz.registerInto: cell.query decoders registered (substrate-direct: site/customer/job/attachment)", .{});
    }

    // C4 PR-R3b — register the oddjobz REPL verb forms (jobs: find jobs / add job
    // / jobs quote|schedule|… ). The brain REPL's handleLine dispatches to these
    // via session.repl_verb_registry; no oddjobz verb code in the brain. Only the
    // REPL boot path passes this registry (null on the WSS serve path).
    if (deps.repl_verb_registry) |reg| {
        oddjobz_repl_verbs.registerInto(reg);
    }

    // ── Step 2 — construct the dispatcher handlers, FK pointers co-located ─
    // visits/quotes/estimates/invoices borrow the jobs store for FK validation;
    // the attachments handler borrows the visits store; the jobs handler
    // borrows the attachments store for `find jobs`→attachments[] (the
    // late-bind, RESTORED now that both pointers live here) + the NATS producer
    // for `job.transitioned` emit. broker + audit flow from deps (both ?* — the
    // handlers' initWithBroker take optionals, so they pass straight through).
    const jh = try allocator.create(jobs_handler.Handler);
    errdefer allocator.destroy(jh);
    jh.* = jobs_handler.Handler.initWithBroker(allocator, jobs_store, deps.broker, deps.audit_log);
    jh.setAttachmentsStore(attachments_store); // RESTORED — find jobs → attachments[]
    if (deps.nats_producer) |np| jh.attachNatsProducer(np);

    const ch = try allocator.create(customers_handler.Handler);
    errdefer allocator.destroy(ch);
    ch.* = customers_handler.Handler.initWithBroker(allocator, customers_store, deps.broker, deps.audit_log);

    const vh = try allocator.create(visits_handler.Handler);
    errdefer allocator.destroy(vh);
    vh.* = visits_handler.Handler.initWithBroker(allocator, visits_store, jobs_store, deps.broker, deps.audit_log);

    const qh = try allocator.create(quotes_handler.Handler);
    errdefer allocator.destroy(qh);
    qh.* = quotes_handler.Handler.initWithBroker(allocator, quotes_store, jobs_store, deps.broker, deps.audit_log);

    const eh = try allocator.create(estimates_handler.Handler);
    errdefer allocator.destroy(eh);
    eh.* = estimates_handler.Handler.initWithBroker(allocator, estimates_store, jobs_store, deps.broker, deps.audit_log);

    const ih = try allocator.create(invoices_handler.Handler);
    errdefer allocator.destroy(ih);
    ih.* = invoices_handler.Handler.initWithBroker(allocator, invoices_store, jobs_store, deps.broker, deps.audit_log);

    const ah = try allocator.create(attachments_handler.Handler);
    errdefer allocator.destroy(ah);
    ah.* = attachments_handler.Handler.initWithBroker(
        allocator,
        attachments_store,
        visits_store, // FK now co-located (was null — degraded — pre-H2b-1)
        deps.broker,
        deps.audit_log,
    );

    // ── Step 3 — register every dispatcher resource ──────────────────────
    // resourceHandler() v-tables capture each handler as state; the dispatcher
    // borrows them for the brain's lifetime. No boot-time dispatch occurs
    // before this point, so registering here (cartridge dispatch) rather than
    // inline in serve.zig is behaviour-equivalent (resources are invoked only
    // at request time, after the serve loop starts).
    try disp.register(jh.resourceHandler());
    try disp.register(ch.resourceHandler());
    try disp.register(vh.resourceHandler());
    try disp.register(qh.resourceHandler());
    try disp.register(eh.resourceHandler());
    try disp.register(ih.resourceHandler());
    try disp.register(ah.resourceHandler());

    // LI-2 — `ingest` resource + `do import legacy lead` verb: spawns the
    // cartridge-shipped legacy-ingest mint spine (LI-1) to mint a ratified
    // Proposal's full entity set as canonical owner-bound cells. Needs the
    // cartridge dir (to resolve the bun script); skip cleanly when absent.
    if (deps.cartridge_dir) |cdir| {
        const ingest_script = try std.fmt.allocPrint(
            allocator,
            "{s}/brain/src/legacy-ingest-handler.ts",
            .{cdir},
        );
        // operator ownerId → 32-hex ("" when unknown → bun handler zero-fills).
        var owner_hex: []const u8 = "";
        if (deps.operator_owner_id) |oid| {
            const hexc = "0123456789abcdef";
            const buf = try allocator.alloc(u8, 32);
            for (oid, 0..) |b, bi| {
                buf[bi * 2] = hexc[(b >> 4) & 0xF];
                buf[bi * 2 + 1] = hexc[b & 0xF];
            }
            owner_hex = buf;
        }
        const ingest_h = try allocator.create(oddjobz_ingest_handler.Handler);
        ingest_h.* = oddjobz_ingest_handler.Handler.init(
            allocator,
            ingest_script,
            deps.site_data_dir,
            owner_hex,
        );
        try disp.register(ingest_h.resourceHandler());
        if (deps.do_verb_registry) |reg| {
            reg.add(.{
                .verb = "import",
                .resource = "legacy",
                .target = "lead",
                .dispatch_resource = "ingest",
                .read_command = "import_lead",
                .write_command = "import_lead",
                .summary = "import a ratified legacy lead from <data_dir>/imports/<file=…> → mint canonical owner-bound cells",
            });
        }
        std.log.info(
            "oddjobz.registerInto: ingest resource + `do import legacy lead` registered → {s}",
            .{ingest_script},
        );
    }

    // Step 4 — C4 PR-G2: register the customer-link-resolve HTTP route on the
    // route registry (GET /api/v1/c/{token}), migrated off reactor.zig +
    // SiteServer + the operator CLI flag. Needs the route registry (site
    // server up) + cartridge_dir (to resolve the cartridge-shipped bun script);
    // skip cleanly if either is absent (REPL-only / no-manifest-dir deployments).
    if (deps.route_registry) |rr| {
        if (deps.cartridge_dir) |cdir| {
            const script_path = try std.fmt.allocPrint(
                allocator,
                "{s}/brain/src/conversation/customer-link-resolve-script.ts",
                .{cdir},
            );
            const cl_state = try allocator.create(CustomerLinkState);
            cl_state.* = .{ .script_path = script_path };
            rr.add(.{
                .method = "GET",
                .path_prefix = "/api/v1/c/",
                .state = cl_state,
                .handle = customerLinkRouteHandler,
            });
            std.log.info(
                "oddjobz.registerInto: customer-link-resolve route registered (GET /api/v1/c/) → {s}",
                .{script_path},
            );

            // C4 PR-G3 — conversation-turns-query (GET /api/v1/conversation/turns),
            // migrated off reactorHandleConvTurnsQuery. Bearer-forwarded to the
            // script (the script authorises). path_prefix matches with or without
            // the query string appended to req.path.
            const ctq_script_path = try std.fmt.allocPrint(
                allocator,
                "{s}/brain/src/conversation/conversation-turns-query-script.ts",
                .{cdir},
            );
            const ctq_state = try allocator.create(ConvTurnsQueryState);
            ctq_state.* = .{ .script_path = ctq_script_path };
            rr.add(.{
                .method = "GET",
                .path_prefix = "/api/v1/conversation/turns",
                .state = ctq_state,
                .handle = convTurnsQueryRouteHandler,
            });
            std.log.info(
                "oddjobz.registerInto: conversation-turns-query route registered (GET /api/v1/conversation/turns) → {s}",
                .{ctq_script_path},
            );

            // C4 PR-G4 — propose-turn (POST /api/v1/conversation/turn/propose),
            // migrated off reactorHandleProposeTurn. POST body → parseRequest →
            // callProposeScript (both already in propose_turn_http). HTTP-only
            // (no REPL tail). Exact path; the /approve + /re-anchor routes use
            // endsWith, so they don't catch /propose.
            const pt_script_path = try std.fmt.allocPrint(
                allocator,
                "{s}/brain/src/conversation/propose-turn-script.ts",
                .{cdir},
            );
            const pt_state = try allocator.create(ProposeTurnState);
            pt_state.* = .{ .script_path = pt_script_path };
            rr.add(.{
                .method = "POST",
                .path_exact = "/api/v1/conversation/turn/propose",
                .state = pt_state,
                .handle = proposeTurnRouteHandler,
            });
            std.log.info(
                "oddjobz.registerInto: propose-turn route registered (POST /api/v1/conversation/turn/propose) → {s}",
                .{pt_script_path},
            );

            // C4 PR-G5 — conv-approve (POST /api/v1/conversation/turn/:id/approve),
            // migrated off reactorHandleConversationApprove. prefix+suffix Route
            // (the /propose exact route is registered above so it wins; /re-anchor
            // is still a hardcoded reactor branch, checked before the registry).
            // Needs deps.site_data_dir (callApproveScript forwards it).
            const ca_script_path = try std.fmt.allocPrint(
                allocator,
                "{s}/brain/src/conversation/conversation-approve-script.ts",
                .{cdir},
            );
            const ca_state = try allocator.create(ConvApproveState);
            ca_state.* = .{ .script_path = ca_script_path, .site_data_dir = deps.site_data_dir };
            rr.add(.{
                .method = "POST",
                .path_prefix = "/api/v1/conversation/turn/",
                .path_suffix = "/approve",
                .state = ca_state,
                .handle = convApproveRouteHandler,
            });
            std.log.info(
                "oddjobz.registerInto: conv-approve route registered (POST /api/v1/conversation/turn/:id/approve) → {s}",
                .{ca_script_path},
            );

            // C4 PR-G6 — re-anchor (POST /api/v1/conversation/turn/:id/re-anchor),
            // migrated off reactorHandleReAnchor. prefix+suffix Route (distinct
            // suffix from /approve). POST body → parseBodyRequest → callReAnchorScript.
            const ra_script_path = try std.fmt.allocPrint(
                allocator,
                "{s}/brain/src/conversation/re-anchor-script.ts",
                .{cdir},
            );
            const ra_route_state = try allocator.create(ReAnchorState);
            ra_route_state.* = .{ .script_path = ra_script_path };
            rr.add(.{
                .method = "POST",
                .path_prefix = "/api/v1/conversation/turn/",
                .path_suffix = "/re-anchor",
                .state = ra_route_state,
                .handle = reAnchorRouteHandler,
            });
            std.log.info(
                "oddjobz.registerInto: re-anchor route registered (POST /api/v1/conversation/turn/:id/re-anchor) → {s}",
                .{ra_script_path},
            );

            // C4 PR-G7 — voice-note (POST /api/v1/voice-note), migrated off
            // reactorHandleVoiceNote. Exact path; bearer REQUIRED; POST body →
            // parseVoiceNoteRequest; needs site_data_dir. Script ships under
            // brain/tools/ (not brain/src/conversation/).
            const vn_script_path = try std.fmt.allocPrint(
                allocator,
                "{s}/brain/tools/voice-note-intake.ts",
                .{cdir},
            );
            const vn_state = try allocator.create(VoiceNoteState);
            vn_state.* = .{ .script_path = vn_script_path, .site_data_dir = deps.site_data_dir };
            rr.add(.{
                .method = "POST",
                .path_exact = "/api/v1/voice-note",
                .state = vn_state,
                .handle = voiceNoteRouteHandler,
            });
            std.log.info(
                "oddjobz.registerInto: voice-note route registered (POST /api/v1/voice-note) → {s}",
                .{vn_script_path},
            );

            // C4 PR-I2 — twilio-inbound (POST /api/v1/twilio/inbound), the inbound
            // SMS webhook. Migrated off reactorHandleTwilioInbound + the SiteServer
            // acceptor. Form-encoded (not JSON), no bearer (Twilio webhook), TwiML
            // response. Reads the cartridge-owned customers + jobs stores; execs the
            // cartridge-SHIPPED intake script (intake-handler.ts) via cartridge_dir
            // (was operator-config cfg.routes[].intake_script — now cartridge-owned,
            // same as the other bun-script conversation routes). method=null so a
            // non-POST reaches the handler (→ 405, matching the prior behaviour).
            const ti_script_path = try std.fmt.allocPrint(
                allocator,
                "{s}/brain/src/intake-handler.ts",
                .{cdir},
            );
            const ti_state = try allocator.create(TwilioInboundState);
            ti_state.* = .{
                .ctx = .{ .customers_store = customers_store, .jobs_store = jobs_store },
                .intake_script = ti_script_path,
                .site_data_dir = deps.site_data_dir,
            };
            rr.add(.{
                .method = null,
                .path_exact = "/api/v1/twilio/inbound",
                .state = ti_state,
                .handle = twilioInboundRouteHandler,
            });
            std.log.info(
                "oddjobz.registerInto: twilio-inbound route registered (POST /api/v1/twilio/inbound) → {s}",
                .{ti_script_path},
            );

            // C4 CW-1 — public web chat widget (POST /api/v1/chat). The visitor
            // browser's chat widget POSTs {message, session_id} here; we exec the
            // cartridge-SHIPPED intake-handler.ts (same script as twilio-inbound).
            // Replaces the generic brain `intake` site-route + the retired LLM-only
            // chat_http (D-O6a) that previously squatted /api/v1/chat. The
            // route_registry is matched before any site-config route, so this
            // cleanly owns the path.
            const wc_state = try allocator.create(WebChatState);
            wc_state.* = .{
                .script_path = ti_script_path, // same cartridge-shipped intake-handler.ts
                .site_data_dir = deps.site_data_dir,
                // DO-3 — borrow the serve-held profile for the live enable gate.
                .operator_profile = deps.operator_profile,
            };
            // C4 CW-3 — bind the chat endpoint to operator policy: take the path
            // from the operator profile's `widget_endpoint` (the same field the
            // landing renderer emits as the widget's data-endpoint, so route +
            // widget stay in lockstep). Falls back to /api/v1/chat when there's no
            // profile or it leaves the field empty. Duped into the cartridge
            // allocator so it outlives the profile arena for the brain's lifetime.
            const chat_endpoint: []const u8 = blk: {
                if (deps.operator_profile) |prof| {
                    if (prof.widget_endpoint.len > 0)
                        break :blk try allocator.dupe(u8, prof.widget_endpoint);
                }
                break :blk "/api/v1/chat";
            };
            rr.add(.{
                .method = "POST",
                .path_exact = chat_endpoint,
                .state = wc_state,
                .handle = chatRouteHandler,
            });
            std.log.info(
                "oddjobz.registerInto: web-chat route registered (POST {s}) → {s}",
                .{ chat_endpoint, ti_script_path },
            );

            // C4 CW-2 — serve the chat widget assets from the cartridge's own
            // public dir (was copied into each operator site's content_root by
            // operator_site_renderer). GET-only, path_exact; the route registry
            // is matched before site-config static routes so these own the path.
            const wjs_state = try allocator.create(StaticAssetState);
            wjs_state.* = .{
                .file_path = try std.fmt.allocPrint(allocator, "{s}/brain/public/chat-widget/chat-widget.js", .{cdir}),
                .content_type = "application/javascript",
            };
            rr.add(.{
                .method = "GET",
                .path_exact = "/chat-widget/chat-widget.js",
                .state = wjs_state,
                .handle = staticAssetRouteHandler,
            });
            const wcss_state = try allocator.create(StaticAssetState);
            wcss_state.* = .{
                .file_path = try std.fmt.allocPrint(allocator, "{s}/brain/public/chat-widget/chat-widget.css", .{cdir}),
                .content_type = "text/css",
            };
            rr.add(.{
                .method = "GET",
                .path_exact = "/chat-widget/chat-widget.css",
                .state = wcss_state,
                .handle = staticAssetRouteHandler,
            });
            std.log.info(
                "oddjobz.registerInto: chat-widget assets registered (GET /chat-widget/chat-widget.js + .css)",
                .{},
            );

            // LI-3c — legacy ingestion admin HTTP + public OAuth callback. Wraps
            // the cartridge-shipped legacy-host.ts (LI-3) so the operator drives
            // OAuth onboarding over a URL or the PWA (admin-bearer-gated), and
            // Google completes the grant via the PUBLIC callback (no localhost
            // loopback / manual code-paste). Needs bearer_tokens for admin auth;
            // it's present whenever route_registry is (the serve boot path).
            if (deps.bearer_tokens) |lbt| {
                const lh_script_path = try std.fmt.allocPrint(
                    allocator,
                    "{s}/brain/src/legacy-host.ts",
                    .{cdir},
                );
                const lh_state = try allocator.create(oddjobz_legacy_http.State);
                lh_state.* = .{
                    .allocator = allocator,
                    .script_path = lh_script_path,
                    .bearer_tokens = lbt,
                };
                rr.add(.{ .method = "POST", .path_exact = "/api/v1/legacy/register-client", .state = lh_state, .handle = oddjobz_legacy_http.registerClientRoute });
                rr.add(.{ .method = "POST", .path_exact = "/api/v1/legacy/connect", .state = lh_state, .handle = oddjobz_legacy_http.connectRoute });
                rr.add(.{ .method = "GET", .path_prefix = "/api/v1/legacy/oauth/callback", .state = lh_state, .handle = oddjobz_legacy_http.callbackRoute });
                rr.add(.{ .method = "GET", .path_exact = "/api/v1/legacy/status", .state = lh_state, .handle = oddjobz_legacy_http.statusRoute });
                std.log.info(
                    "oddjobz.registerInto: legacy ingestion routes registered (POST register-client/connect, GET status + PUBLIC oauth/callback) → {s}",
                    .{lh_script_path},
                );
            }
        } else {
            std.log.info(
                "oddjobz.registerInto: no cartridge_dir — customer-link-resolve route skipped",
                .{},
            );
        }

        // C4 PR-H5a — the store-backed routes validate the bearer via the
        // substrate token store; gate them on it. It's present whenever
        // route_registry is (i.e. the serve boot path); the REPL boot path has
        // neither, so these simply aren't registered there.
        if (deps.bearer_tokens) |bt| {
            // C4 PR-H3 — search-contacts (POST /api/v1/search/contacts), migrated off
            // reactorHandleSearchContacts + the SiteServer acceptor. STORE-backed (not
            // script-backed): the handler reads the cartridge-owned customers + sites
            // stores and validates the bearer via the token store.
            const sc_state = try allocator.create(SearchContactsState);
            sc_state.* = .{
                .customers_store = customers_store,
                .sites_store = sites_store,
                .bearer_tokens = bt,
            };
            rr.add(.{
                .method = "POST",
                .path_exact = "/api/v1/search/contacts",
                .state = sc_state,
                .handle = searchContactsRouteHandler,
            });
            std.log.info(
                "oddjobz.registerInto: search-contacts route registered (POST /api/v1/search/contacts)",
                .{},
            );

            // WP-1 — anonymous LLM proxy: the widget's bun conversation engine
            // calls this (loopback) instead of Anthropic directly, so funnel LLM
            // spend runs through the brain's governed llm.complete. Bearer-gated.
            const lc_state = try allocator.create(LlmCompleteState);
            lc_state.* = .{ .disp = disp, .bearer_tokens = bt };
            rr.add(.{
                .method = "POST",
                .path_exact = "/api/v1/llm/complete",
                .state = lc_state,
                .handle = llmCompleteRouteHandler,
            });
            std.log.info(
                "oddjobz.registerInto: widget LLM proxy registered (POST /api/v1/llm/complete) scope={s}",
                .{WIDGET_LLM_SCOPE},
            );

            // C4 PR-H6 — attachments-blob (GET /api/v1/attachments/{id}/blob),
            // migrated off reactorHandleAttachmentsBlob + the SiteServer acceptor.
            // STORE-backed: reads the cartridge-owned attachments + blob stores;
            // bearer-validated. method=null so GET + HEAD both match (the handler
            // enforces); prefix+suffix matcher.
            const ab_state = try allocator.create(AttachmentsBlobState);
            ab_state.* = .{
                .attachments_store = attachments_store,
                .blob_store = blob_store,
                .bearer_tokens = bt,
            };
            rr.add(.{
                .method = null,
                .path_prefix = "/api/v1/attachments/",
                .path_suffix = "/blob",
                .state = ab_state,
                .handle = attachmentsBlobRouteHandler,
            });
            std.log.info(
                "oddjobz.registerInto: attachments-blob route registered (GET /api/v1/attachments/:id/blob)",
                .{},
            );

            // C4 PR-H7b — attachments-upload (POST /api/v1/attachments/upload),
            // migrated off reactorHandleAttachmentsUpload + the SiteServer acceptor.
            // Multipart (parsed from req.body) + ECDSA cell-signature verify against
            // the capturing device's cert. Additionally gated on deps.cert_store (the
            // sig-verify needs it) — absent → the route isn't registered (404).
            if (deps.cert_store) |certs| {
                const au_state = try allocator.create(AttachmentsUploadState);
                au_state.* = .{
                    .attachments_store = attachments_store,
                    .visits_store = visits_store,
                    .blob_store = blob_store,
                    .cert_store = certs,
                    .bearer_tokens = bt,
                };
                rr.add(.{
                    .method = "POST",
                    .path_exact = "/api/v1/attachments/upload",
                    .state = au_state,
                    .handle = attachmentsUploadRouteHandler,
                });
                std.log.info(
                    "oddjobz.registerInto: attachments-upload route registered (POST /api/v1/attachments/upload)",
                    .{},
                );
            } else {
                std.log.info(
                    "oddjobz.registerInto: no cert store — attachments-upload route skipped (operator priv not configured)",
                    .{},
                );
            }

            // C4 PR-I1 — conversation-send (POST /api/v1/conversation/:id/send),
            // outbound SMS via Twilio. Migrated off reactorHandleConversationSend.
            // The Twilio config is loaded ONCE here (best-effort: absent → the
            // endpoint 503s, same as before); the ProdSender (std.http.Client) +
            // its buffer ctx are heap-allocated for the brain's lifetime. The
            // handler builds a per-request conversation_send_http.Acceptor over the
            // cartridge-owned customers store + this config/sender + the substrate
            // token store. prefix+suffix route (the /conversation/turn/* routes use
            // distinct suffixes, so they don't collide with /send).
            const cs_owned = twilio_adapter.loadConfig(allocator, TWILIO_CONFIG_PATH) catch null;
            const cs_cfg: ?twilio_adapter.TwilioConfig = if (cs_owned) |oc| oc.config else null;
            const cs_default_cc: []const u8 = if (cs_cfg) |c| c.default_country_code else "+61";
            const cs_sender_ctx = try allocator.create(ProdSenderCtx);
            cs_sender_ctx.* = .{ .allocator = allocator };
            const send_state = try allocator.create(ConvSendState);
            send_state.* = .{
                .bearer_tokens = bt,
                .twilio_config = cs_cfg,
                .prod_sender_ctx = cs_sender_ctx,
                .lookup = .{ .customers_store = customers_store, .default_country_code = cs_default_cc },
            };
            rr.add(.{
                .method = "POST",
                .path_prefix = "/api/v1/conversation/",
                .path_suffix = "/send",
                .state = send_state,
                .handle = conversationSendRouteHandler,
            });
            std.log.info(
                "oddjobz.registerInto: conversation-send route registered (POST /api/v1/conversation/:id/send; twilio_configured={})",
                .{cs_cfg != null},
            );
        } else {
            std.log.info(
                "oddjobz.registerInto: no bearer-token store — store-backed routes skipped",
                .{},
            );
        }
    }

    std.log.info(
        "oddjobz.registerInto: §6b cluster registered — 8 stores + 7 dispatcher handlers (FK co-located; find jobs→attachments[] late-bind restored)",
        .{},
    );
}

/// State for the customer-link-resolve route: the resolved absolute path to the
/// cartridge-shipped bun script. Heap-allocated at registerInto; the route
/// registry borrows it for the brain's lifetime.
const CustomerLinkState = struct {
    script_path: []const u8,
};

/// GET /api/v1/c/{token} — resolve a customer-link token to a conversation.
/// Migrated from reactorHandleCustomerLinkResolve (C4 PR-G2): the brain no
/// longer hardcodes this route; the oddjobz cartridge serves it via the route
/// registry, exec'ing its OWN shipped script (resolved via cartridge_dir).
/// Method is GET-filtered by the Route; behaviour mirrors the prior handler.
fn customerLinkRouteHandler(
    state_any: *anyopaque,
    req: *const http_parser.HttpRequest,
    alloc: std.mem.Allocator,
) anyerror!http_route_registry.RouteResponse {
    const st: *CustomerLinkState = @ptrCast(@alignCast(state_any));

    const prefix = "/api/v1/c/";
    if (!std.mem.startsWith(u8, req.path, prefix)) {
        return .{ .status = 400, .status_text = "Bad Request", .body = "{\"error\":\"bad_request\"}" };
    }
    const token = req.path[prefix.len..];
    if (token.len == 0 or token.len > 64) {
        return .{ .status = 404, .status_text = "Not Found", .body = "{\"error\":\"not_found\"}" };
    }

    var result = propose_turn_http.callResolveScript(alloc, st.script_path, token) catch {
        return .{ .status = 500, .status_text = "Internal Server Error", .body = "{\"error\":\"script_error\"}" };
    };
    defer result.deinit(alloc);

    const status: std.http.Status = result.kind.httpStatus();
    const status_u16: u16 = @intCast(@intFromEnum(status));
    const status_text: []const u8 = status.phrase() orelse "Error";

    return switch (result.kind) {
        // allocPrint copies conversation_id + entity_title into a fresh buffer,
        // so it survives result.deinit; the reactor copies it into write_buf and
        // the per-request arena frees it.
        .found => .{
            .status = status_u16,
            .status_text = status_text,
            .body = try std.fmt.allocPrint(
                alloc,
                "{{\"ok\":true,\"conversationId\":\"{s}\",\"entityTitle\":\"{s}\"}}",
                .{ result.conversation_id, result.entity_title },
            ),
        },
        .not_found => .{ .status = status_u16, .status_text = status_text, .body = "{\"error\":\"not_found\"}" },
        .db_error => .{ .status = status_u16, .status_text = status_text, .body = "{\"error\":\"db_error\"}" },
        .script_error => .{ .status = status_u16, .status_text = status_text, .body = "{\"error\":\"script_error\"}" },
    };
}

// ─────────────────────────────────────────────────────────────────────
// Inline tests — registerInto smoke. The full handler conformance
// (dispatcher round-trip with real cell_store) lives in tests/ as
// it needs fixtures we don't construct here.
// ─────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "realClock returns a positive millisecond timestamp" {
    const t = realClock();
    try testing.expect(t > 0);
}

// ─── C4 PR-G3 — conversation-turns-query route handler ────────────────────

/// State for the conversation-turns-query route: resolved path to the
/// cartridge-shipped bun script. Heap-allocated at registerInto.
const ConvTurnsQueryState = struct {
    script_path: []const u8,
};

/// Extract a 64-hex bearer token from the Authorization header (reimplements
/// the reactor's bearerHex64 — the cartridge can't import reactor.zig). The
/// token is FORWARDED to the script, which authorises.
fn bearerHex64(req: *const http_parser.HttpRequest) ?[]const u8 {
    const authz = req.header("authorization") orelse return null;
    const prefix = "Bearer ";
    if (authz.len <= prefix.len) return null;
    if (!std.ascii.eqlIgnoreCase(authz[0..prefix.len], prefix)) return null;
    const tok = std.mem.trim(u8, authz[prefix.len..], " \t");
    if (tok.len != 64) return null;
    for (tok) |c| {
        const ok = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
        if (!ok) return null;
    }
    return tok;
}

/// GET /api/v1/conversation/turns — query canonical conversation turns.
/// Migrated from reactorHandleConvTurnsQuery (C4 PR-G3). Parses query params,
/// forwards the bearer to the cartridge-shipped script, returns a structured
/// RouteResponse. Method is GET-filtered by the Route.
fn convTurnsQueryRouteHandler(
    state_any: *anyopaque,
    req: *const http_parser.HttpRequest,
    alloc: std.mem.Allocator,
) anyerror!http_route_registry.RouteResponse {
    const st: *ConvTurnsQueryState = @ptrCast(@alignCast(state_any));

    const entity_ref = events_stream_handler.queryParam(req.query, "entityRef");
    const conversation_id = events_stream_handler.queryParam(req.query, "conversationId");
    const direction = events_stream_handler.queryParam(req.query, "direction");
    const outbound_state = events_stream_handler.queryParam(req.query, "outboundState");

    var limit_val: ?u32 = null;
    if (events_stream_handler.queryParam(req.query, "limit")) |lv| {
        limit_val = std.fmt.parseInt(u32, lv, 10) catch null;
    }
    var before_val: ?u64 = null;
    if (events_stream_handler.queryParam(req.query, "before")) |bv| {
        before_val = std.fmt.parseInt(u64, bv, 10) catch null;
    }

    const bearer = bearerHex64(req);

    var result = conv_turns_query_http.callQueryScript(
        alloc,
        st.script_path,
        bearer,
        entity_ref,
        conversation_id,
        limit_val,
        before_val,
        direction,
        outbound_state,
    ) catch {
        return .{ .status = 500, .status_text = "Internal Server Error", .body = "{\"error\":\"script_error\"}" };
    };
    defer result.deinit(alloc);

    const status: std.http.Status = result.kind.httpStatus();
    const status_u16: u16 = @intCast(@intFromEnum(status));
    const status_text: []const u8 = status.phrase() orelse "Error";

    return switch (result.kind) {
        .ok => .{
            .status = status_u16,
            .status_text = status_text,
            .body = try std.fmt.allocPrint(alloc, "{{\"ok\":true,\"turns\":{s}}}", .{result.turns_json}),
        },
        .db_error => .{ .status = status_u16, .status_text = status_text, .body = "{\"error\":\"db_error\"}" },
        .unauthorised => .{ .status = status_u16, .status_text = status_text, .body = "{\"error\":\"unauthorized\"}" },
        .script_error => .{ .status = status_u16, .status_text = status_text, .body = "{\"error\":\"script_error\"}" },
    };
}

// ─── C4 PR-G4 — propose-turn route handler (POST) ─────────────────────────

/// State for the propose-turn route: resolved path to the cartridge-shipped
/// bun script. Heap-allocated at registerInto.
const ProposeTurnState = struct {
    script_path: []const u8,
};

/// POST /api/v1/conversation/turn/propose — propose an outbound AI reply.
/// Migrated from reactorHandleProposeTurn (C4 PR-G4). Parses the POST body,
/// forwards the bearer, execs the cartridge-shipped script, returns a
/// structured RouteResponse. Method is POST-filtered by the Route.
fn proposeTurnRouteHandler(
    state_any: *anyopaque,
    req: *const http_parser.HttpRequest,
    alloc: std.mem.Allocator,
) anyerror!http_route_registry.RouteResponse {
    const st: *ProposeTurnState = @ptrCast(@alignCast(state_any));

    const propose_req = propose_turn_http.parseRequest(alloc, req.body) catch |err| switch (err) {
        error.missing_field => return .{ .status = 400, .status_text = "Bad Request", .body = "{\"error\":\"missing_field\"}" },
        error.malformed => return .{ .status = 400, .status_text = "Bad Request", .body = "{\"error\":\"malformed_body\"}" },
        error.out_of_memory => return .{ .status = 500, .status_text = "Internal Server Error", .body = "{\"error\":\"out_of_memory\"}" },
    };
    defer propose_req.deinit(alloc);

    const bearer = bearerHex64(req);

    var result = propose_turn_http.callProposeScript(alloc, st.script_path, bearer, propose_req) catch {
        return .{ .status = 500, .status_text = "Internal Server Error", .body = "{\"error\":\"script_error\"}" };
    };
    defer result.deinit(alloc);

    const status: std.http.Status = result.kind.httpStatus();
    const status_u16: u16 = @intCast(@intFromEnum(status));
    const status_text: []const u8 = status.phrase() orelse "Error";

    return switch (result.kind) {
        .proposed => .{
            .status = status_u16,
            .status_text = status_text,
            .body = try std.fmt.allocPrint(alloc, "{{\"ok\":true,\"turnId\":\"{s}\",\"state\":\"proposed\"}}", .{result.turn_id}),
        },
        .missing_fields => .{ .status = status_u16, .status_text = status_text, .body = "{\"error\":\"missing_fields\"}" },
        .db_error => .{ .status = status_u16, .status_text = status_text, .body = "{\"error\":\"db_error\"}" },
        .unauthorised => .{ .status = status_u16, .status_text = status_text, .body = "{\"error\":\"unauthorized\"}" },
        .script_error => .{ .status = status_u16, .status_text = status_text, .body = "{\"error\":\"script_error\"}" },
    };
}

// ─── C4 PR-G5 — conv-approve route handler (POST, prefix+suffix) ──────────

/// State for the conv-approve route: resolved script path + the brain data dir
/// (callApproveScript forwards it to the script). Heap-allocated at registerInto.
const ConvApproveState = struct {
    script_path: []const u8,
    site_data_dir: []const u8,
};

/// POST /api/v1/conversation/turn/:turnId/approve — operator approves a proposed
/// AI reply + triggers send. Migrated from reactorHandleConversationApprove
/// (C4 PR-G5). Extracts turnId from the path, forwards bearer + site_data_dir to
/// the cartridge-shipped script, returns a structured RouteResponse. Method is
/// POST-filtered + suffix-filtered by the Route.
fn convApproveRouteHandler(
    state_any: *anyopaque,
    req: *const http_parser.HttpRequest,
    alloc: std.mem.Allocator,
) anyerror!http_route_registry.RouteResponse {
    const st: *ConvApproveState = @ptrCast(@alignCast(state_any));

    const prefix = "/api/v1/conversation/turn/";
    const suffix = "/approve";
    if (req.path.len <= prefix.len + suffix.len) {
        return .{ .status = 400, .status_text = "Bad Request", .body = "{\"error\":\"missing_turn_id\"}" };
    }
    const turn_id = req.path[prefix.len .. req.path.len - suffix.len];
    if (turn_id.len == 0) {
        return .{ .status = 400, .status_text = "Bad Request", .body = "{\"error\":\"missing_turn_id\"}" };
    }

    const bearer = bearerHex64(req);

    var result = conversation_approve_http.callApproveScript(
        alloc,
        st.script_path,
        bearer,
        turn_id,
        "operator", // operator_cert_id sentinel — logged by the TS, not verified here
        st.site_data_dir,
    ) catch {
        return .{ .status = 500, .status_text = "Internal Server Error", .body = "{\"error\":\"script_error\"}" };
    };
    defer result.deinit(alloc);

    const status: std.http.Status = result.kind.httpStatus();
    const status_u16: u16 = @intCast(@intFromEnum(status));
    const status_text: []const u8 = status.phrase() orelse "Error";

    const body: []const u8 = switch (result.kind) {
        .sent => if (result.surface_message_id.len > 0)
            try std.fmt.allocPrint(alloc, "{{\"state\":\"sent\",\"surfaceMessageId\":\"{s}\"}}", .{result.surface_message_id})
        else
            "{\"state\":\"sent\"}",
        .failed => if (result.error_msg.len > 0)
            try std.fmt.allocPrint(alloc, "{{\"state\":\"failed\",\"error\":\"{s}\"}}", .{result.error_msg})
        else
            "{\"state\":\"failed\"}",
        .not_proposed => if (result.current_state.len > 0)
            try std.fmt.allocPrint(alloc, "{{\"error\":\"not_proposed\",\"currentState\":\"{s}\"}}", .{result.current_state})
        else
            "{\"error\":\"not_proposed\"}",
        .not_found => "{\"error\":\"not_found\"}",
        .unauthorised => "{\"error\":\"unauthorised\"}",
        .script_error => "{\"error\":\"script_error\"}",
    };

    return .{ .status = status_u16, .status_text = status_text, .body = body };
}

// ─── C4 PR-G6 — re-anchor route handler (POST, prefix+suffix) ─────────────

/// State for the re-anchor route: resolved script path. Heap-allocated at
/// registerInto.
const ReAnchorState = struct {
    script_path: []const u8,
};

/// POST /api/v1/conversation/turn/:turnId/re-anchor — re-anchor a turn to a
/// different entity (SUPERSEDES pattern). Migrated from reactorHandleReAnchor
/// (C4 PR-G6). Extracts turnId, parses the POST body, forwards bearer, execs
/// the cartridge-shipped script. Method + suffix filtered by the Route.
fn reAnchorRouteHandler(
    state_any: *anyopaque,
    req: *const http_parser.HttpRequest,
    alloc: std.mem.Allocator,
) anyerror!http_route_registry.RouteResponse {
    const st: *ReAnchorState = @ptrCast(@alignCast(state_any));

    const prefix = "/api/v1/conversation/turn/";
    const suffix = "/re-anchor";
    if (req.path.len <= prefix.len + suffix.len) {
        return .{ .status = 400, .status_text = "Bad Request", .body = "{\"error\":\"missing_turn_id\"}" };
    }
    const turn_id = req.path[prefix.len .. req.path.len - suffix.len];
    if (turn_id.len == 0) {
        return .{ .status = 400, .status_text = "Bad Request", .body = "{\"error\":\"missing_turn_id\"}" };
    }

    const body_req = re_anchor_http.parseBodyRequest(alloc, req.body) catch |err| switch (err) {
        error.missing_field => return .{ .status = 400, .status_text = "Bad Request", .body = "{\"error\":\"missing_field\"}" },
        error.malformed => return .{ .status = 400, .status_text = "Bad Request", .body = "{\"error\":\"malformed_body\"}" },
        error.out_of_memory => return .{ .status = 500, .status_text = "Internal Server Error", .body = "{\"error\":\"out_of_memory\"}" },
    };
    defer body_req.deinit(alloc);

    const ra_req = re_anchor_http.ReAnchorRequest{
        .turn_id = turn_id,
        .new_entity_cell_hash = body_req.new_entity_cell_hash,
        .new_entity_kind = body_req.new_entity_kind,
        .operator_cert_id = body_req.operator_cert_id,
    };

    const bearer = bearerHex64(req);

    var result = re_anchor_http.callReAnchorScript(alloc, st.script_path, bearer, ra_req) catch {
        return .{ .status = 500, .status_text = "Internal Server Error", .body = "{\"error\":\"script_error\"}" };
    };
    defer result.deinit(alloc);

    const status: std.http.Status = result.kind.httpStatus();
    const status_u16: u16 = @intCast(@intFromEnum(status));
    const status_text: []const u8 = status.phrase() orelse "Error";

    const body: []const u8 = switch (result.kind) {
        .reanchored => try std.fmt.allocPrint(
            alloc,
            "{{\"ok\":true,\"newRelationId\":\"{s}\",\"supersededRelationId\":\"{s}\"}}",
            .{ result.new_relation_id, result.superseded_relation_id },
        ),
        .already_anchored => "{\"ok\":true,\"alreadyAnchored\":true}",
        .turn_not_found => "{\"error\":\"turn_not_found\"}",
        .entity_not_found => "{\"error\":\"entity_not_found\"}",
        .no_existing_anchor => "{\"error\":\"no_existing_anchor\"}",
        .db_error => "{\"error\":\"db_error\"}",
        .script_error => "{\"error\":\"script_error\"}",
        .unauthorised => "{\"error\":\"unauthorized\"}",
    };

    return .{ .status = status_u16, .status_text = status_text, .body = body };
}

// ─── C4 PR-G7 — voice-note route handler (POST, bearer-required) ──────────

/// State for the voice-note route: resolved script path + brain data dir
/// (callVoiceNoteScript forwards it). Heap-allocated at registerInto.
const VoiceNoteState = struct {
    script_path: []const u8,
    site_data_dir: []const u8,
};

/// POST /api/v1/voice-note — ingest a voice note into a conversation turn.
/// Migrated from reactorHandleVoiceNote (C4 PR-G7). Bearer is REQUIRED (401 if
/// missing). Parses the body, forwards bearer + site_data_dir to the
/// cartridge-shipped script. Method POST-filtered by the Route.
fn voiceNoteRouteHandler(
    state_any: *anyopaque,
    req: *const http_parser.HttpRequest,
    alloc: std.mem.Allocator,
) anyerror!http_route_registry.RouteResponse {
    const st: *VoiceNoteState = @ptrCast(@alignCast(state_any));

    const bearer = bearerHex64(req) orelse return .{
        .status = 401,
        .status_text = "Unauthorized",
        .body = "{\"error\":\"bearer_invalid\"}",
    };

    var parsed_req = voice_note_http.parseVoiceNoteRequest(alloc, req.body) catch |e| {
        const hint: []const u8 = switch (e) {
            error.missing_transcript => "transcript required",
            error.missing_entity_id => "entity_id required",
            error.missing_entity_kind => "entity_kind required",
            error.missing_captured_at => "captured_at required",
            error.invalid_entity_kind => "entity_kind must be job|site|customer",
            error.malformed => "malformed JSON",
            error.out_of_memory => "out_of_memory",
        };
        return .{
            .status = 400,
            .status_text = "Bad Request",
            .body = try std.fmt.allocPrint(alloc, "{{\"error\":\"invalid_payload\",\"hint\":\"{s}\"}}", .{hint}),
        };
    };
    defer parsed_req.deinit(alloc);

    var result = voice_note_http.callVoiceNoteScript(alloc, st.script_path, bearer, parsed_req, st.site_data_dir) catch {
        return .{ .status = 500, .status_text = "Internal Server Error", .body = "{\"error\":\"script_error\"}" };
    };
    defer result.deinit(alloc);

    const status: std.http.Status = result.kind.httpStatus();
    const status_u16: u16 = @intCast(@intFromEnum(status));
    const status_text: []const u8 = status.phrase() orelse "Error";

    const body: []const u8 = switch (result.kind) {
        .created => try std.fmt.allocPrint(alloc, "{{\"turn_id\":\"{s}\"}}", .{result.turn_id}),
        .invalid_payload => if (result.detail.len > 0)
            try std.fmt.allocPrint(alloc, "{{\"error\":\"invalid_payload\",\"hint\":\"{s}\"}}", .{result.detail})
        else
            "{\"error\":\"invalid_payload\"}",
        .unauthorised => "{\"error\":\"bearer_invalid\"}",
        .script_unavailable => "{\"error\":\"script_unavailable\"}",
        .script_failed => if (result.detail.len > 0)
            try std.fmt.allocPrint(alloc, "{{\"error\":\"script_failed\",\"detail\":\"{s}\"}}", .{result.detail})
        else
            "{\"error\":\"script_failed\"}",
    };

    return .{ .status = status_u16, .status_text = status_text, .body = body };
}

// ─── C4 CW-1 — web chat widget route handler (POST, public) ────────────────

/// State for the public web chat route: the cartridge-shipped intake-handler
/// script path + the brain-owned site_data_dir (where the script reads/writes
/// per-session conversation state). Heap-allocated at registerInto.
const WebChatState = struct {
    script_path: []const u8,
    site_data_dir: []const u8,
    /// DO-3 — the serve-held operator profile (borrowed; the same instance the
    /// `site widget_set` verb mutates). Read at request time for the live enable
    /// gate. Null when no profile loaded → the widget stays enabled (default).
    operator_profile: ?*const operator_profile_mod.OperatorProfile = null,
};

/// POST /api/v1/chat — the public visitor chat widget funnel. Carved from the
/// generic brain `intake` site-route (reactorHandleIntake) + the retired LLM-only
/// chat_http (D-O6a). Parses {message, session_id} (+ optional ?j=<cellId>), execs
/// the cartridge-shipped intake-handler.ts, returns its {reply,...} JSON. Public
/// (no bearer) for v0.5; operator-policy scope/cap gating lands in CW-3.
fn chatRouteHandler(
    state_any: *anyopaque,
    req: *const http_parser.HttpRequest,
    alloc: std.mem.Allocator,
) anyerror!http_route_registry.RouteResponse {
    const st: *WebChatState = @ptrCast(@alignCast(state_any));

    if (!std.mem.eql(u8, req.method, "POST")) {
        return .{ .status = 405, .status_text = "Method Not Allowed", .body = "{\"error\":\"POST required\"}" };
    }

    // DO-3 — operator enable gate (closes CW-3b). Read live: the operator can flip
    // it via `do manage site widget enabled=false` and this 503s without a restart
    // (the profile instance is shared with the site widget_set handler).
    if (st.operator_profile) |prof| {
        if (!prof.widget_enabled) {
            return .{ .status = 503, .status_text = "Service Unavailable", .body = "{\"error\":\"widget_disabled\"}" };
        }
        // WP-3 — operator embed-origin gate. When the allowlist is set, a
        // cross-origin POST (Origin header present) whose origin isn't listed is
        // rejected. Same-origin / no-Origin (direct, curl) requests pass. Read
        // live from the shared profile (`do manage site widget origins=…`).
        if (prof.widget_embed_origins.len > 0) {
            if (req.header("origin")) |origin| {
                if (!originAllowed(prof.widget_embed_origins, origin)) {
                    return .{ .status = 403, .status_text = "Forbidden", .body = "{\"error\":\"origin_not_allowed\"}" };
                }
            }
        }
    }

    const parsed = web_chat_http.parseIntakeRequest(alloc, req.body) catch |err| {
        const msg: []const u8 = switch (err) {
            error.missing_message => "{\"error\":\"missing required field: message\"}",
            error.malformed => "{\"error\":\"body must be JSON {message:string, session_id?:string}\"}",
            else => "{\"error\":\"failed to parse body\"}",
        };
        return .{ .status = 400, .status_text = "Bad Request", .body = msg };
    };
    defer parsed.deinit(alloc);

    // WP-2 — operator-set max message length, read live from the profile (the
    // shared instance `do manage site widget max_chars=…` mutates); falls back to
    // the substrate default when no profile / unset.
    const max_chars: usize = blk: {
        if (st.operator_profile) |prof| {
            if (prof.widget_max_message_chars > 0) break :blk prof.widget_max_message_chars;
        }
        break :blk web_chat_http.DEFAULT_MAX_MESSAGE_CHARS;
    };
    if (parsed.message.len > max_chars) {
        return .{ .status = 413, .status_text = "Payload Too Large", .body = "{\"error\":\"message exceeds max_message_chars\"}" };
    }

    // Optional `?j=<cellId>` — anchors the ConversationTurn to a job cell.
    // Validated: exactly 64 hex chars or ignored (mirrors reactorHandleIntake).
    var j_param: ?[]const u8 = null;
    if (events_stream_handler.queryParam(req.query, "j")) |j| {
        if (j.len == 64) {
            var all_hex = true;
            for (j) |c| {
                if (!((c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F'))) {
                    all_hex = false;
                    break;
                }
            }
            if (all_hex) j_param = j;
        }
    }

    const response_body = web_chat_http.callScript(alloc, st.script_path, parsed, st.site_data_dir, j_param) catch {
        return .{ .status = 500, .status_text = "Internal Server Error", .body = "{\"error\":\"intake subprocess failed\"}" };
    };
    // response_body is alloc'd with the per-request allocator; the reactor copies
    // it into the write buffer, so we return it directly (no free here).
    if (response_body.len == 0) {
        return .{ .status = 502, .status_text = "Bad Gateway", .body = "{\"error\":\"intake script returned empty response\"}" };
    }

    return .{ .status = 200, .status_text = "OK", .content_type = "application/json", .body = response_body };
}

// ─── WP-1 — anonymous LLM proxy for the widget conversation ────────────────

/// The anonymous budget/rate-limit scope all public-widget LLM traffic is keyed
/// to in llm_complete_handler (one bucket per brain; single-domain serve).
const WIDGET_LLM_SCOPE = "anonymous-widget";

/// State for POST /api/v1/llm/complete: the dispatcher (to reach the substrate
/// `llm.complete` resource) + the bearer-token store (to validate the operator-
/// pinned bearer the bun intake script sends).
const LlmCompleteState = struct {
    disp: *dispatcher.Dispatcher,
    bearer_tokens: *bearer_tokens_mod.TokenStore,
};

/// POST /api/v1/llm/complete — WP-1. The cartridge's bun conversation engine
/// (intake-handler.ts buildReplyLlm) calls this over loopback instead of hitting
/// Anthropic directly, so the public funnel's LLM spend runs through the brain's
/// `llm.complete` — inheriting the per-scope rate-limit + daily token-budget +
/// audit (llm_complete_handler), keyed to WIDGET_LLM_SCOPE. Bearer-validated;
/// dispatched in_process_root (the per-scope cap-check is bypassed, but the
/// rate/budget gates still bind — see llm_complete_handler.handleComplete).
/// Body: { system_prompt, prompt, max_tokens? } → llm.complete's { text, … }.
fn llmCompleteRouteHandler(
    state_any: *anyopaque,
    req: *const http_parser.HttpRequest,
    alloc: std.mem.Allocator,
) anyerror!http_route_registry.RouteResponse {
    const st: *LlmCompleteState = @ptrCast(@alignCast(state_any));

    if (!std.mem.eql(u8, req.method, "POST")) {
        return .{ .status = 405, .status_text = "Method Not Allowed", .body = "{\"error\":\"POST required\"}" };
    }
    const bearer = bearerHex64(req) orelse return .{
        .status = 401,
        .status_text = "Unauthorized",
        .body = "{\"error\":\"bearer_invalid\"}",
    };
    _ = st.bearer_tokens.verifyHex(bearer) catch return .{
        .status = 401,
        .status_text = "Unauthorized",
        .body = "{\"error\":\"bearer_invalid\"}",
    };

    // Parse { system_prompt, prompt, max_tokens? } from the bun engine.
    const parsed = std.json.parseFromSlice(std.json.Value, alloc, req.body, .{}) catch
        return .{ .status = 400, .status_text = "Bad Request", .body = "{\"error\":\"bad_json\"}" };
    defer parsed.deinit();
    if (parsed.value != .object) return .{ .status = 400, .status_text = "Bad Request", .body = "{\"error\":\"bad_json\"}" };
    const obj = parsed.value.object;
    const prompt_v = obj.get("prompt") orelse return .{ .status = 400, .status_text = "Bad Request", .body = "{\"error\":\"prompt required\"}" };
    if (prompt_v != .string) return .{ .status = 400, .status_text = "Bad Request", .body = "{\"error\":\"prompt required\"}" };
    const system_prompt: []const u8 = if (obj.get("system_prompt")) |v| (if (v == .string) v.string else "") else "";
    const max_tokens: i64 = if (obj.get("max_tokens")) |v| (if (v == .integer) v.integer else 512) else 512;

    // Build the llm.complete args, injecting the fixed anonymous scope.
    var args_buf: std.ArrayList(u8) = .{};
    defer args_buf.deinit(alloc);
    try args_buf.appendSlice(alloc, "{\"scope\":\"" ++ WIDGET_LLM_SCOPE ++ "\",\"system_prompt\":");
    try appendJsonString(alloc, &args_buf, system_prompt);
    try args_buf.appendSlice(alloc, ",\"prompt\":");
    try appendJsonString(alloc, &args_buf, prompt_v.string);
    try args_buf.print(alloc, ",\"max_tokens\":{d}}}", .{max_tokens});

    const ctx: dispatcher.DispatchContext = .{
        .auth = .in_process_root,
        .capabilities = dispatcher.CapabilitySet.empty(),
        .meta = .{ .request_id = "", .transport_label = "widget_llm" },
    };
    var result = st.disp.dispatch(&ctx, "llm", "complete", args_buf.items) catch |err| {
        const status: u16 = switch (err) {
            error.rate_limit_exceeded, error.budget_exhausted => 429,
            error.backend_unavailable => 503,
            error.prompt_too_long => 413,
            else => 500,
        };
        return .{ .status = status, .status_text = "Error", .body = try std.fmt.allocPrint(alloc, "{{\"error\":\"{s}\"}}", .{@errorName(err)}) };
    };
    defer result.deinit();
    // result.payload is alloc'd by the per-request allocator → return directly.
    return .{ .status = 200, .status_text = "OK", .content_type = "application/json", .body = try alloc.dupe(u8, result.payload) };
}

fn appendJsonString(alloc: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    const enc = try std.json.Stringify.valueAlloc(alloc, s, .{});
    defer alloc.free(enc);
    try buf.appendSlice(alloc, enc);
}

/// WP-3 — is `origin` in the comma-separated `allowlist`? Exact per-entry match
/// (whitespace trimmed); empty entries ignored.
fn originAllowed(allowlist: []const u8, origin: []const u8) bool {
    var it = std.mem.splitScalar(u8, allowlist, ',');
    while (it.next()) |raw| {
        const entry = std.mem.trim(u8, raw, " \t");
        if (entry.len == 0) continue;
        if (std.mem.eql(u8, entry, origin)) return true;
    }
    return false;
}

// ─── C4 CW-2 — cartridge-served chat widget static assets ──────────────────

const asset_cache_headers = [_]std.http.Header{
    .{ .name = "Cache-Control", .value = "public, max-age=3600" },
};

/// State for a cartridge-served static asset: an absolute file path under the
/// cartridge's OWN public dir + its content-type. Heap-allocated at registerInto.
const StaticAssetState = struct {
    file_path: []const u8,
    content_type: []const u8,
};

/// GET a cartridge-shipped static asset (the chat widget JS/CSS) from the
/// cartridge's OWN public dir, so the widget is served by the cartridge rather
/// than copied into each operator site's content_root. The reactor matches the
/// route registry before the site-config static routes, so these shadow any
/// per-site copy. C4 CW-2.
fn staticAssetRouteHandler(
    state_any: *anyopaque,
    req: *const http_parser.HttpRequest,
    alloc: std.mem.Allocator,
) anyerror!http_route_registry.RouteResponse {
    const st: *StaticAssetState = @ptrCast(@alignCast(state_any));
    if (!std.mem.eql(u8, req.method, "GET")) {
        return .{ .status = 405, .status_text = "Method Not Allowed", .body = "{\"error\":\"GET required\"}" };
    }
    const bytes = std.fs.cwd().readFileAlloc(alloc, st.file_path, 1024 * 1024) catch {
        return .{ .status = 404, .status_text = "Not Found", .body = "{\"error\":\"asset_not_found\"}" };
    };
    return .{
        .status = 200,
        .status_text = "OK",
        .content_type = st.content_type,
        .body = bytes,
        .extra_headers = &asset_cache_headers,
    };
}

// ─── C4 PR-H3 — search-contacts route handler (POST, store-backed) ─────────

/// State for the search-contacts route: borrowed pointers to the cartridge-owned
/// customers + sites stores + the substrate bearer-token store (for auth). Heap-
/// allocated at registerInto; the route registry borrows it for the brain's
/// lifetime.
const SearchContactsState = struct {
    customers_store: *customers_store_fs.CustomersStore,
    sites_store: *sites_store_fs.SitesStore,
    bearer_tokens: *bearer_tokens_mod.TokenStore,
};

/// is_bearer_valid callback — validates the 64-hex bearer against the substrate
/// token store (any error → invalid). Mirrors serve.zig's convSendIsBearerValid.
fn scBearerValid(ctx: ?*anyopaque, bearer_hex: []const u8) bool {
    const ts: *bearer_tokens_mod.TokenStore = @ptrCast(@alignCast(ctx.?));
    _ = ts.verifyHex(bearer_hex) catch return false;
    return true;
}

/// list_customers callback — all customers from the cartridge-owned store.
fn scListCustomers(ctx: ?*anyopaque, alloc: std.mem.Allocator) anyerror![]customers_store_fs.Customer {
    const cs: *customers_store_fs.CustomersStore = @ptrCast(@alignCast(ctx.?));
    return cs.listAll(alloc);
}

/// list_sites callback — all sites from the cartridge-owned store.
fn scListSites(ctx: ?*anyopaque, alloc: std.mem.Allocator) anyerror![]sites_store_fs.Site {
    const ss: *sites_store_fs.SitesStore = @ptrCast(@alignCast(ctx.?));
    return ss.listAll(alloc);
}

/// POST /api/v1/search/contacts — case-insensitive contact search over the live
/// customers + sites. Migrated from reactorHandleSearchContacts (C4 PR-H3): the
/// brain no longer hardcodes this route or carries a SiteServer acceptor field;
/// the oddjobz cartridge serves it via the route registry, reading its OWN stores.
/// Builds a per-request Acceptor (allocator = the request arena, so the response
/// JSON it allocates is arena-owned — the reactor copies it then frees the arena).
fn searchContactsRouteHandler(
    state_any: *anyopaque,
    req: *const http_parser.HttpRequest,
    alloc: std.mem.Allocator,
) anyerror!http_route_registry.RouteResponse {
    const st: *SearchContactsState = @ptrCast(@alignCast(state_any));

    var acc = search_contacts_http.Acceptor{
        .allocator = alloc,
        .is_bearer_valid = scBearerValid,
        .is_bearer_valid_ctx = st.bearer_tokens,
        .list_customers = scListCustomers,
        .list_customers_ctx = st.customers_store,
        .list_sites = scListSites,
        .list_sites_ctx = st.sites_store,
    };

    var result = search_contacts_http.acceptSearch(&acc, bearerHex64(req), req.body) catch {
        return .{ .status = 500, .status_text = "Internal Server Error", .body = "{\"error\":\"upstream_error\"}" };
    };

    const status: std.http.Status = result.kind.httpStatus();
    const status_u16: u16 = @intCast(@intFromEnum(status));
    const status_text: []const u8 = status.phrase() orelse "Error";

    // On .matched the response_body is arena-allocated (acc.allocator == alloc):
    // hand it straight back — the reactor copies it into the write buffer and the
    // request arena frees it. Non-matched kinds carry no body (static error JSON).
    return switch (result.kind) {
        .matched => .{ .status = status_u16, .status_text = status_text, .body = result.response_body },
        .unauthorised => .{ .status = status_u16, .status_text = status_text, .body = "{\"error\":\"unauthorized\"}" },
        .malformed_body => .{ .status = status_u16, .status_text = status_text, .body = "{\"error\":\"malformed_body\"}" },
        .empty_query => .{ .status = status_u16, .status_text = status_text, .body = "{\"error\":\"empty_query\"}" },
        .upstream_error => .{ .status = status_u16, .status_text = status_text, .body = "{\"error\":\"upstream_error\"}" },
    };
}

// ─── C4 PR-H6 — attachments-blob route handler (GET, binary body) ──────────

/// State for the attachments-blob route: borrowed pointers to the cartridge-owned
/// attachments store (for mime + content hash) + blob store (for bytes) + the
/// substrate bearer-token store (auth). Heap-allocated at registerInto.
const AttachmentsBlobState = struct {
    attachments_store: *attachments_store_fs.AttachmentsStore,
    blob_store: *attachment_blobs_fs.BlobStore,
    bearer_tokens: *bearer_tokens_mod.TokenStore,
};

/// GET /api/v1/attachments/{id}/blob — return an attachment's binary blob with
/// its stored mime_type as Content-Type + a private cache-control + a
/// content-hash echo. Migrated from reactorHandleAttachmentsBlob (C4 PR-H6).
/// Bearer REQUIRED. The blob bytes are read with the request arena, so the body
/// + the extra-header slice are arena-owned (the reactor copies + frees them).
fn attachmentsBlobRouteHandler(
    state_any: *anyopaque,
    req: *const http_parser.HttpRequest,
    alloc: std.mem.Allocator,
) anyerror!http_route_registry.RouteResponse {
    const st: *AttachmentsBlobState = @ptrCast(@alignCast(state_any));

    // Extract the id from "/api/v1/attachments/{id}/blob" (defensive — the
    // prefix+suffix matcher already gated the path).
    const prefix = "/api/v1/attachments/";
    const suffix = "/blob";
    if (!std.mem.startsWith(u8, req.path, prefix) or !std.mem.endsWith(u8, req.path, suffix)) {
        return .{ .status = 404, .status_text = "Not Found", .body = "{\"error\":\"not_found\"}" };
    }
    const after_prefix = req.path[prefix.len..];
    const id = after_prefix[0 .. after_prefix.len - suffix.len];
    if (id.len == 0 or id.len > 64) {
        return .{ .status = 404, .status_text = "Not Found", .body = "{\"error\":\"not_found\"}" };
    }

    // GET/HEAD only (method=null on the route lets both through).
    if (!std.mem.eql(u8, req.method, "GET") and !std.mem.eql(u8, req.method, "HEAD")) {
        return .{ .status = 405, .status_text = "Method Not Allowed", .body = "{\"error\":\"method_not_allowed\",\"hint\":\"GET required\"}" };
    }

    // Bearer REQUIRED.
    const bearer = bearerHex64(req) orelse return .{
        .status = 401,
        .status_text = "Unauthorized",
        .body = "{\"error\":\"bearer_invalid\"}",
    };
    _ = st.bearer_tokens.verifyHex(bearer) catch return .{
        .status = 401,
        .status_text = "Unauthorized",
        .body = "{\"error\":\"bearer_invalid\"}",
    };

    const att = st.attachments_store.findById(id) orelse return .{
        .status = 404,
        .status_text = "Not Found",
        .body = "{\"error\":\"not_found\"}",
    };
    const blob = st.blob_store.read(alloc, att.content_hash) catch return .{
        .status = 404,
        .status_text = "Not Found",
        .body = "{\"error\":\"not_found\"}",
    };

    // cache-control + content-hash echo, arena-allocated so they outlive the
    // return + are freed with the request arena (RouteResponse.extra_headers).
    const hdrs = try alloc.alloc(std.http.Header, 2);
    hdrs[0] = .{ .name = "cache-control", .value = "private, max-age=300" };
    hdrs[1] = .{ .name = "x-attachment-content-hash", .value = att.content_hash };

    return .{
        .status = 200,
        .status_text = "OK",
        .content_type = att.mime_type,
        .body = blob,
        .extra_headers = hdrs,
    };
}

// ─── C4 PR-H7b — attachments-upload route handler (POST, multipart) ────────

/// State for the attachments-upload route: the cartridge-owned attachments +
/// visits + blob stores, plus the substrate cert + bearer-token stores. Heap-
/// allocated at registerInto. Only registered when deps.cert_store is present.
const AttachmentsUploadState = struct {
    attachments_store: *attachments_store_fs.AttachmentsStore,
    visits_store: *visits_store_fs.VisitsStore,
    blob_store: *attachment_blobs_fs.BlobStore,
    cert_store: *identity_certs.CertStore,
    bearer_tokens: *bearer_tokens_mod.TokenStore,
};

/// Small JSON error RouteResponse helper (static body).
fn auErr(status: u16, status_text: []const u8, body: []const u8) http_route_registry.RouteResponse {
    return .{ .status = status, .status_text = status_text, .body = body };
}

/// POST /api/v1/attachments/upload — multipart upload of an attachment blob +
/// signed metadata cell. Migrated from reactorHandleAttachmentsUpload (C4 PR-H7b):
/// the brain no longer hardcodes this route or carries a SiteServer acceptor. The
/// cartridge builds a per-request Acceptor over its OWN stores (allocator = the
/// request arena) and reproduces the verify-then-persist flow, returning a
/// RouteResponse. Method POST-filtered by the Route; bearer REQUIRED. The
/// multipart body is parsed from req.body (the reactor pre-buffers it).
fn attachmentsUploadRouteHandler(
    state_any: *anyopaque,
    req: *const http_parser.HttpRequest,
    alloc: std.mem.Allocator,
) anyerror!http_route_registry.RouteResponse {
    const st: *AttachmentsUploadState = @ptrCast(@alignCast(state_any));

    // Bearer REQUIRED.
    const bearer = bearerHex64(req) orelse return auErr(401, "Unauthorized", "{\"error\":\"bearer_invalid\"}");
    _ = st.bearer_tokens.verifyHex(bearer) catch return auErr(401, "Unauthorized", "{\"error\":\"bearer_invalid\"}");

    // Content-type → multipart boundary.
    const ct = req.header("content-type") orelse
        return auErr(400, "Bad Request", "{\"error\":\"payload_invalid_format\",\"hint\":\"missing content-type\"}");
    const boundary = attachments_upload_http.boundaryFromContentType(ct) orelse
        return auErr(400, "Bad Request", "{\"error\":\"payload_invalid_format\",\"hint\":\"missing multipart boundary\"}");

    // Per-request Acceptor over the cartridge-owned stores.
    var acc = attachments_upload_http.Acceptor{
        .allocator = alloc,
        .blobs = st.blob_store,
        .attachments = st.attachments_store,
        .visits = st.visits_store,
        .certs = st.cert_store,
        .bearer_tokens = st.bearer_tokens,
    };

    // Parse multipart (body pre-buffered by the reactor).
    var parts = attachments_upload_http.parseMultipart(alloc, req.body, boundary) catch |err| switch (err) {
        attachments_upload_http.Error.boundary_missing,
        attachments_upload_http.Error.payload_invalid_format,
        => return auErr(400, "Bad Request", "{\"error\":\"payload_invalid_format\"}"),
        attachments_upload_http.Error.out_of_memory => return auErr(500, "Internal Server Error", "{\"error\":\"out_of_memory\"}"),
        else => return auErr(500, "Internal Server Error", "{\"error\":\"multipart_parse_failed\"}"),
    };
    defer parts.deinit(alloc);

    const metadata_json = parts.metadata orelse
        return auErr(400, "Bad Request", "{\"error\":\"payload_invalid_format\",\"hint\":\"missing metadata part\"}");
    const blob_bytes = parts.blob orelse
        return auErr(400, "Bad Request", "{\"error\":\"payload_invalid_format\",\"hint\":\"missing blob part\"}");
    if (blob_bytes.len > acc.max_blob_bytes) return auErr(413, "Payload Too Large", "{\"error\":\"too_large\"}");

    // Parse metadata.
    var meta = attachments_upload_http.parseMetadata(alloc, metadata_json) catch
        return auErr(400, "Bad Request", "{\"error\":\"payload_invalid_format\"}");
    defer meta.deinit(alloc);

    // Verify SHA-256(blob) matches the claimed content hash.
    var blob_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(blob_bytes, &blob_hash, .{});
    var blob_hash_hex: [64]u8 = undefined;
    bkds.hexEncode(&blob_hash, &blob_hash_hex);
    if (!std.mem.eql(u8, meta.content_hash, &blob_hash_hex))
        return auErr(400, "Bad Request", "{\"error\":\"hash_mismatch\"}");

    // Look up the capturing device's cert + verify the cell signature.
    const cert = acc.certs.get(meta.captured_by_cert_id) catch
        return auErr(401, "Unauthorized", "{\"error\":\"cert_unknown\"}");

    const canonical_bytes = attachments_upload_http.canonicaliseCellPayload(alloc, meta.cell_payload_root) catch
        return auErr(400, "Bad Request", "{\"error\":\"payload_invalid_format\",\"hint\":\"failed to canonicalise cell_payload\"}");
    defer alloc.free(canonical_bytes);

    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(canonical_bytes, &digest, .{});
    if (!attachments_upload_http.verifyCellSignatureRecoveryLoop(meta.signature, digest, cert.pubkey))
        return auErr(401, "Unauthorized", "{\"error\":\"signature_invalid\"}");

    // Persist blob + metadata.
    acc.blobs.write(&blob_hash_hex, blob_bytes) catch
        return auErr(500, "Internal Server Error", "{\"error\":\"blob_write_failed\"}");

    const created_at = attachments_upload_http.renderIsoTimestamp(alloc, std.time.timestamp()) catch
        return auErr(500, "Internal Server Error", "{\"error\":\"out_of_memory\"}");
    defer alloc.free(created_at);

    const create_result = attachments_upload_http.createMetadataInline(&acc, meta, created_at) catch |err| switch (err) {
        attachments_upload_http.InsertError.visit_not_found => {
            var vb: std.ArrayList(u8) = .{};
            errdefer vb.deinit(alloc);
            vb.appendSlice(alloc, "{\"error\":\"visit_not_found\",\"visit_id\":") catch
                return auErr(500, "Internal Server Error", "{\"error\":\"out_of_memory\"}");
            attachments_upload_http.writeJsonString(alloc, &vb, meta.visit_id) catch
                return auErr(500, "Internal Server Error", "{\"error\":\"out_of_memory\"}");
            vb.append(alloc, '}') catch
                return auErr(500, "Internal Server Error", "{\"error\":\"out_of_memory\"}");
            const body = vb.toOwnedSlice(alloc) catch
                return auErr(500, "Internal Server Error", "{\"error\":\"out_of_memory\"}");
            return .{ .status = 404, .status_text = "Not Found", .body = body };
        },
        attachments_upload_http.InsertError.attachment_id_in_use_with_different_contents => return auErr(409, "Conflict", "{\"error\":\"attachment_id_in_use_with_different_contents\"}"),
        else => return auErr(500, "Internal Server Error", "{\"error\":\"store_error\"}"),
    };

    // Success — escape the client-supplied attachment id (writeJsonString).
    var resp_buf: std.ArrayList(u8) = .{};
    errdefer resp_buf.deinit(alloc);
    const oom = auErr(500, "Internal Server Error", "{\"error\":\"out_of_memory\"}");
    resp_buf.appendSlice(alloc, "{\"id\":") catch return oom;
    attachments_upload_http.writeJsonString(alloc, &resp_buf, meta.attachment_id) catch return oom;
    resp_buf.appendSlice(alloc, ",\"status\":\"") catch return oom;
    resp_buf.appendSlice(alloc, switch (create_result) {
        .created => "created",
        .already_exists => "already_exists",
    }) catch return oom;
    resp_buf.appendSlice(alloc, "\"}") catch return oom;
    const body = resp_buf.toOwnedSlice(alloc) catch return oom;
    return .{ .status = 200, .status_text = "OK", .body = body };
}

// ─── C4 PR-I1 — conversation-send route handler (POST, outbound SMS) ────────

/// Operator-config path for the Twilio creds (same as the prior serve path).
const TWILIO_CONFIG_PATH = "/var/lib/semantos/twilio.json";

/// Reused HTTP-client context for the prod Twilio sender. Holds the last
/// response body so it can be freed on the next call (the brain reactor is
/// single-threaded, so one shared ctx is safe). Heap-allocated at registerInto.
const ProdSenderCtx = struct {
    allocator: std.mem.Allocator,
    last_body: []u8 = &.{},
};

/// lookup_contact ctx — resolve a conversation_id (== customer_id) to an E.164
/// phone via the cartridge-owned customers store.
const ConvSendLookupCtx = struct {
    customers_store: *customers_store_fs.CustomersStore,
    default_country_code: []const u8,
};

/// State for the conversation-send route. Heap-allocated at registerInto.
const ConvSendState = struct {
    bearer_tokens: *bearer_tokens_mod.TokenStore,
    twilio_config: ?twilio_adapter.TwilioConfig,
    prod_sender_ctx: *ProdSenderCtx,
    lookup: ConvSendLookupCtx,
};

/// lookup_contact callback — conversation_id is treated as a customer_id; return
/// the customer's E.164 phone (normalised, or formatted from raw). Null → 404.
fn convSendLookupContact(ctx: ?*anyopaque, alloc: std.mem.Allocator, conversation_id: []const u8) anyerror!?[]u8 {
    const st: *ConvSendLookupCtx = @ptrCast(@alignCast(ctx.?));
    const customer = st.customers_store.findById(conversation_id) orelse return null;
    if (customer.normalisedPhone) |np| {
        if (np.len > 0) return try alloc.dupe(u8, np);
    }
    if (customer.phone.len == 0) return null;
    return twilio_adapter.formatE164(alloc, customer.phone, st.default_country_code) catch null;
}

/// persist_message callback — stub (the local message record lands in a later
/// pass; the SMS already went out). Mirrors the prior serve stub.
fn convSendPersistMessage(ctx: ?*anyopaque, conversation_id: []const u8, body: []const u8, sid: []const u8) anyerror!void {
    _ = ctx;
    _ = conversation_id;
    _ = body;
    _ = sid;
}

/// sender callback — the real Twilio REST POST via std.http.Client. Mirrors the
/// prior serve convSendProdSender.
fn convSendProdSender(req: twilio_adapter.SendRequest, ctx: ?*anyopaque) anyerror!twilio_adapter.SendResponse {
    const self: *ProdSenderCtx = @ptrCast(@alignCast(ctx.?));
    if (self.last_body.len > 0) {
        self.allocator.free(self.last_body);
        self.last_body = &.{};
    }
    var hdrs = [_]std.http.Header{
        .{ .name = "Authorization", .value = req.auth_header },
        .{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" },
    };
    var resp_writer = std.io.Writer.Allocating.init(self.allocator);
    defer resp_writer.deinit();
    var client = std.http.Client{ .allocator = self.allocator };
    defer client.deinit();
    const result = client.fetch(.{
        .location = .{ .url = req.url },
        .method = .POST,
        .payload = req.body,
        .extra_headers = hdrs[0..],
        .response_writer = &resp_writer.writer,
    }) catch return error.transport_error;
    const body_bytes = resp_writer.written();
    if (body_bytes.len > 0) {
        self.last_body = try self.allocator.dupe(u8, body_bytes);
    }
    return twilio_adapter.SendResponse{
        .status_code = @intFromEnum(result.status),
        .body = self.last_body,
    };
}

/// POST /api/v1/conversation/:id/send — send an outbound SMS to the conversation's
/// contact via Twilio. Migrated from reactorHandleConversationSend (C4 PR-I1).
/// Bearer-gated; builds a per-request Acceptor over the cartridge-owned customers
/// store + the registerInto-loaded Twilio config + the shared prod sender.
fn conversationSendRouteHandler(
    state_any: *anyopaque,
    req: *const http_parser.HttpRequest,
    alloc: std.mem.Allocator,
) anyerror!http_route_registry.RouteResponse {
    const st: *ConvSendState = @ptrCast(@alignCast(state_any));

    // Extract conversation id between "/api/v1/conversation/" and "/send".
    const prefix = "/api/v1/conversation/";
    const suffix = "/send";
    if (req.path.len <= prefix.len + suffix.len)
        return .{ .status = 400, .status_text = "Bad Request", .body = "{\"error\":\"missing_conversation_id\"}" };
    const conv_id = req.path[prefix.len .. req.path.len - suffix.len];
    if (conv_id.len == 0)
        return .{ .status = 400, .status_text = "Bad Request", .body = "{\"error\":\"missing_conversation_id\"}" };

    var acc = conversation_send_http.Acceptor{
        .allocator = alloc,
        .is_bearer_valid = scBearerValid,
        .is_bearer_valid_ctx = st.bearer_tokens,
        .twilio_config = st.twilio_config,
        .sender = convSendProdSender,
        .sender_ctx = st.prod_sender_ctx,
        .lookup_contact = convSendLookupContact,
        .lookup_contact_ctx = &st.lookup,
        .persist_message = convSendPersistMessage,
        .persist_message_ctx = null,
    };

    var result = conversation_send_http.acceptSend(&acc, bearerHex64(req), conv_id, req.body) catch
        return .{ .status = 500, .status_text = "Internal Server Error", .body = "{\"error\":\"out_of_memory\"}" };
    defer result.deinit(alloc);

    const status: std.http.Status = result.kind.httpStatus();
    const status_u16: u16 = @intCast(@intFromEnum(status));
    const status_text: []const u8 = status.phrase() orelse "Error";

    if (result.kind == .sent) {
        const body = std.fmt.allocPrint(alloc, "{{\"sent\":true,\"sid\":\"{s}\",\"status\":\"{s}\"}}", .{ result.sid, result.twilio_status }) catch
            return .{ .status = 500, .status_text = "Internal Server Error", .body = "{\"error\":\"out_of_memory\"}" };
        return .{ .status = status_u16, .status_text = status_text, .body = body };
    }

    const err_wire: []const u8 = switch (result.kind) {
        .sent => unreachable,
        .unauthorised => "unauthorised",
        .not_found => "conversation_not_found",
        .twilio_disabled => "twilio_not_configured",
        .malformed_body => "malformed_body",
        .invalid_recipient => "invalid_recipient",
        .rate_limited => "rate_limited",
        .upstream_error => "upstream_error",
    };
    const body = std.fmt.allocPrint(alloc, "{{\"error\":\"{s}\"}}", .{err_wire}) catch
        return .{ .status = 500, .status_text = "Internal Server Error", .body = "{\"error\":\"out_of_memory\"}" };
    return .{ .status = status_u16, .status_text = status_text, .body = body };
}

// ─── C4 PR-I2 — twilio-inbound route handler (POST, form-encoded webhook) ───

/// Ctx for the inbound find/authorize callbacks: the cartridge-owned customers +
/// jobs stores. Embedded in the route State (stable address).
const TwilioInboundCtx = struct {
    customers_store: *customers_store_fs.CustomersStore,
    jobs_store: *jobs_store_fs.JobsStore,
};

/// State for the twilio-inbound route. Heap-allocated at registerInto. The intake
/// script is cartridge-shipped (resolved via cartridge_dir).
const TwilioInboundState = struct {
    ctx: TwilioInboundCtx,
    intake_script: []const u8,
    site_data_dir: []const u8,
};

/// find_customer_by_phone callback — dedupe-key lookup by normalised phone.
fn twilioInboundFindCustomer(ctx: ?*anyopaque, normalised_phone: []const u8) ?[32]u8 {
    const self: *TwilioInboundCtx = @ptrCast(@alignCast(ctx.?));
    const customer = self.customers_store.findByDedupeKey(.{ .phone = normalised_phone }) orelse return null;
    return customer.cellId;
}

/// find_open_job_cell_id callback — most-recent open (lead/quoted/scheduled) job
/// for the customer, as a 64-hex cell id.
fn twilioInboundFindOpenJob(ctx: ?*anyopaque, allocator: std.mem.Allocator, customer_cell_id: [32]u8) anyerror!?[64]u8 {
    const self: *TwilioInboundCtx = @ptrCast(@alignCast(ctx.?));
    const jobs = try self.jobs_store.listForCustomer(allocator, customer_cell_id);
    defer allocator.free(jobs);
    var best: ?jobs_store_fs.Job = null;
    for (jobs) |j| {
        const is_open = std.mem.eql(u8, j.state, "lead") or
            std.mem.eql(u8, j.state, "quoted") or
            std.mem.eql(u8, j.state, "scheduled");
        if (!is_open) continue;
        if (best == null) {
            best = j;
        } else if (std.mem.order(u8, j.created_at, best.?.created_at) == .gt) {
            best = j;
        }
    }
    const job = best orelse return null;
    const cell_id = job.cellId orelse return null;
    return std.fmt.bytesToHex(cell_id, .lower);
}

/// authorize_job callback (P4b) — customer YES on a quoted job → quoted→authorized.
/// Non-fatal: logs on error, the intake turn is already recorded.
fn twilioInboundAuthorizeJob(ctx: ?*anyopaque, allocator: std.mem.Allocator, entity_cell_id: [32]u8) anyerror!void {
    _ = allocator;
    const self: *TwilioInboundCtx = @ptrCast(@alignCast(ctx.?));
    const job = self.jobs_store.getById(entity_cell_id) orelse {
        std.log.warn("twilio_inbound/P4b: no job found for cell_id", .{});
        return;
    };
    if (!std.mem.eql(u8, job.state, "quoted")) {
        std.log.info("twilio_inbound/P4b: job {s} is in state '{s}' — skipping authorize", .{ job.id, job.state });
        return;
    }
    _ = try self.jobs_store.updateState(job.id, "authorized", null);
    std.log.info("twilio_inbound/P4b: job {s} quoted → authorized via customer SMS", .{job.id});
}

/// POST /api/v1/twilio/inbound — inbound SMS webhook (form-encoded; no bearer —
/// Twilio webhook). Migrated from reactorHandleTwilioInbound (C4 PR-I2). Builds a
/// per-request twilio_inbound_http.Acceptor over the cartridge-owned stores + the
/// cartridge-shipped intake script; acceptInbound parses the form, resolves
/// phone→customer→open-job, routes to the bun intake pipeline, and (P4b) may
/// auto-authorize. Always returns 200 + empty TwiML on success (Twilio won't
/// retry); 405 for non-POST.
fn twilioInboundRouteHandler(
    state_any: *anyopaque,
    req: *const http_parser.HttpRequest,
    alloc: std.mem.Allocator,
) anyerror!http_route_registry.RouteResponse {
    const st: *TwilioInboundState = @ptrCast(@alignCast(state_any));
    var acc = twilio_inbound_http.Acceptor{
        .find_customer_by_phone_fn = twilioInboundFindCustomer,
        .find_customer_by_phone_ctx = &st.ctx,
        .find_open_job_cell_id_fn = twilioInboundFindOpenJob,
        .find_open_job_cell_id_ctx = &st.ctx,
        .intake_script = st.intake_script,
        .authorize_job_fn = twilioInboundAuthorizeJob,
        .authorize_job_ctx = &st.ctx,
    };
    const result = twilio_inbound_http.acceptInbound(&acc, alloc, req.method, req.body, st.site_data_dir);
    return switch (result) {
        .not_post => .{ .status = 405, .status_text = "Method Not Allowed", .body = "{\"error\":\"POST required\"}" },
        .ok, .missing_body => .{
            .status = 200,
            .status_text = "OK",
            .content_type = "application/xml",
            .body = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Response></Response>",
        },
    };
}

// ─── cell.query decoders — SUBSTRATE-DIRECT (raw canonical payload) ──────────
//
// decode_one loads the cell by its content hash from the entity cell store and
// returns its raw payload JSON with `cellHash` (= the content hash) injected as
// the first key. NO view-store, NO per-type translation — the cell IS the wire
// shape. matches_filter parses the same raw payload for ref predicates. ctx is
// the shared *const CellStore (cast from *anyopaque).
//
// NOTE: octave-1-escalated payloads are not dereferenced here (the census shows
// every canonical oddjobz cell is ≤767B inline); an escalated cell would decode
// to its pointer descriptor. Add a content_store deref if fat cells appear.

/// Load a cell by content hash; return its substrate payload (a slice into
/// `cell_buf`, which the caller MUST keep alive). Null when absent/invalid.
fn loadCellPayload(
    cs: *const cell_store_mod.CellStore,
    cell_hash: *const [32]u8,
    cell_buf: *[substrate_entity.CELL_BYTES]u8,
) ?[]const u8 {
    cell_buf.* = (cs.getCell(cell_hash) catch return null) orelse return null;
    const decoded = substrate_entity.decodeEntity(cell_buf);
    if (!decoded.magic_ok) return null;
    return decoded.payload;
}

fn substrateDecodeOne(ctx: *anyopaque, cell_hash: *const [32]u8, alloc: std.mem.Allocator) anyerror!?[]u8 {
    const cs: *const cell_store_mod.CellStore = @ptrCast(@alignCast(ctx));
    var cell_buf: [substrate_entity.CELL_BYTES]u8 = undefined;
    const payload = loadCellPayload(cs, cell_hash, &cell_buf) orelse return null;
    return try injectCellHash(alloc, payload, cell_hash);
}

/// Emit `payload` (a JSON object) with `"cellHash":"<hex>"` spliced in as the
/// first key — the cell's content-addressed identity, distinct from any payload
/// field (incl. the attachment payload's own `cellId` = blob sha). Non-object /
/// empty payloads degrade to a minimal `{"cellHash":"<hex>"}`.
fn injectCellHash(alloc: std.mem.Allocator, payload: []const u8, cell_hash: *const [32]u8) anyerror![]u8 {
    const hex = std.fmt.bytesToHex(cell_hash.*, .lower); // [64]u8
    if (payload.len < 1 or payload[0] != '{') {
        return try std.fmt.allocPrint(alloc, "{{\"cellHash\":\"{s}\"}}", .{hex[0..]});
    }
    // Skip whitespace after '{' to detect an empty object.
    var i: usize = 1;
    while (i < payload.len) : (i += 1) {
        switch (payload[i]) {
            ' ', '\t', '\n', '\r' => {},
            else => break,
        }
    }
    if (i >= payload.len or payload[i] == '}') {
        return try std.fmt.allocPrint(alloc, "{{\"cellHash\":\"{s}\"}}", .{hex[0..]});
    }
    return try std.fmt.allocPrint(alloc, "{{\"cellHash\":\"{s}\",{s}", .{ hex[0..], payload[1..] });
}

/// jobs filter: {"siteRef":"<hex>"} → payload.site_ref match; {"customerRef":
/// "<hex>"} → payload.customer_refs[].cell_id contains it. Raw-payload fields.
fn jobMatchesFilter(ctx: *anyopaque, cell_hash: *const [32]u8, filter_json: []const u8, alloc: std.mem.Allocator) anyerror!bool {
    const cs: *const cell_store_mod.CellStore = @ptrCast(@alignCast(ctx));
    var cell_buf: [substrate_entity.CELL_BYTES]u8 = undefined;
    const payload = loadCellPayload(cs, cell_hash, &cell_buf) orelse return false;

    const pj = std.json.parseFromSlice(std.json.Value, alloc, payload, .{}) catch return false;
    defer pj.deinit();
    if (pj.value != .object) return false;
    const job = pj.value.object;

    const fj = std.json.parseFromSlice(std.json.Value, alloc, filter_json, .{}) catch return false;
    defer fj.deinit();
    if (fj.value != .object) return false;
    const obj = fj.value.object;

    if (obj.get("siteRef")) |v| {
        if (v != .string) return false;
        const sr = job.get("site_ref") orelse return false;
        if (sr != .string) return false;
        return std.mem.eql(u8, sr.string, v.string);
    }
    if (obj.get("customerRef")) |v| {
        if (v != .string) return false;
        const refs = job.get("customer_refs") orelse return false;
        if (refs != .array) return false;
        for (refs.array.items) |el| {
            if (el != .object) continue;
            const cid = el.object.get("cell_id") orelse continue;
            if (cid == .string and std.mem.eql(u8, cid.string, v.string)) return true;
        }
        return false;
    }
    return false;
}

/// attachments filter: {"jobRef":"<hex>"} → payload.jobRef match. Raw-payload.
fn attachmentMatchesFilter(ctx: *anyopaque, cell_hash: *const [32]u8, filter_json: []const u8, alloc: std.mem.Allocator) anyerror!bool {
    const cs: *const cell_store_mod.CellStore = @ptrCast(@alignCast(ctx));
    var cell_buf: [substrate_entity.CELL_BYTES]u8 = undefined;
    const payload = loadCellPayload(cs, cell_hash, &cell_buf) orelse return false;

    const pj = std.json.parseFromSlice(std.json.Value, alloc, payload, .{}) catch return false;
    defer pj.deinit();
    if (pj.value != .object) return false;
    const att = pj.value.object;

    const fj = std.json.parseFromSlice(std.json.Value, alloc, filter_json, .{}) catch return false;
    defer fj.deinit();
    if (fj.value != .object) return false;
    const obj = fj.value.object;

    if (obj.get("jobRef")) |v| {
        if (v != .string) return false;
        const jr = att.get("jobRef") orelse return false;
        if (jr != .string) return false;
        return std.mem.eql(u8, jr.string, v.string);
    }
    return false;
}

// ── cell.query substrate-decode tests (option A — raw canonical payload) ─────

const lmdb = @import("lmdb");
const lmdb_cell_store_test_mod = @import("lmdb_cell_store");

fn openRegTestEnv(dir: []const u8) !lmdb.Env {
    return lmdb.Env.open(dir, .{
        .max_dbs = 8,
        .map_size = 8 * 1024 * 1024,
        .open_flags = lmdb.EnvFlags.NOSYNC,
    });
}

test "injectCellHash: splices cellHash first; empty/non-object degrade" {
    const a = std.testing.allocator;
    var h: [32]u8 = [_]u8{0xab} ** 32;

    const r1 = try injectCellHash(a, "{\"name\":\"x\"}", &h);
    defer a.free(r1);
    try std.testing.expectEqualStrings("{\"cellHash\":\"" ++ ("ab" ** 32) ++ "\",\"name\":\"x\"}", r1);

    const r2 = try injectCellHash(a, "{}", &h);
    defer a.free(r2);
    try std.testing.expectEqualStrings("{\"cellHash\":\"" ++ ("ab" ** 32) ++ "\"}", r2);

    const r3 = try injectCellHash(a, "not-json", &h);
    defer a.free(r3);
    try std.testing.expectEqualStrings("{\"cellHash\":\"" ++ ("ab" ** 32) ++ "\"}", r3);
}

test "substrateDecodeOne + jobMatchesFilter: raw canonical payload from the substrate" {
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var pb: [std.fs.max_path_bytes]u8 = undefined;
    const dir = try tmp.dir.realpath(".", &pb);
    var env = try openRegTestEnv(dir);
    defer env.close();
    var cs_impl = try lmdb_cell_store_test_mod.LmdbCellStore.init(&env, a);
    const cs = cs_impl.store();
    const ctx: *anyopaque = @ptrCast(@constCast(&cs));

    // A canonical ingest-shape customer cell — name/role, NO view translation.
    const cust_payload = "{\"name\":\"Tanya Healy\",\"role\":\"agent\",\"email\":\"t@c.com\"}";
    const cust_cell = try substrate_entity.encodeEntity(.{
        .spec = substrate_entity.SPEC_CUSTOMER,
        .linearity = .affine,
        .owner_id = [_]u8{0} ** 16,
        .payload_json = cust_payload,
    });
    const cust_hash = try cs.put(&cust_cell);

    const decoded = (try substrateDecodeOne(ctx, &cust_hash, a)) orelse return error.DecodeReturnedNull;
    defer a.free(decoded);
    // Raw canonical fields are emitted verbatim (no display_name translation).
    try std.testing.expect(std.mem.indexOf(u8, decoded, "\"name\":\"Tanya Healy\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, decoded, "\"role\":\"agent\"") != null);
    // cellHash = the content hash, injected first.
    try std.testing.expect(std.mem.startsWith(u8, decoded, "{\"cellHash\":\""));
    const ch_hex = std.fmt.bytesToHex(cust_hash, .lower);
    try std.testing.expect(std.mem.indexOf(u8, decoded, ch_hex[0..]) != null);

    // A job cell with raw site_ref + customer_refs[].cell_id.
    const job_payload =
        "{\"intent\":\"work_order\",\"site_ref\":\"" ++ ("11" ** 32) ++
        "\",\"customer_refs\":[{\"cell_id\":\"" ++ ("22" ** 32) ++
        "\",\"role\":\"agent\"}],\"summary\":\"leak\"}";
    const job_cell = try substrate_entity.encodeEntity(.{
        .spec = substrate_entity.SPEC_JOB,
        .linearity = .affine,
        .owner_id = [_]u8{0} ** 16,
        .payload_json = job_payload,
    });
    const job_hash = try cs.put(&job_cell);

    // matches_filter parses the RAW payload fields.
    try std.testing.expect(try jobMatchesFilter(ctx, &job_hash, "{\"siteRef\":\"" ++ ("11" ** 32) ++ "\"}", a));
    try std.testing.expect(try jobMatchesFilter(ctx, &job_hash, "{\"customerRef\":\"" ++ ("22" ** 32) ++ "\"}", a));
    try std.testing.expect(!(try jobMatchesFilter(ctx, &job_hash, "{\"siteRef\":\"" ++ ("33" ** 32) ++ "\"}", a)));

    // A missing cell → decode null (the generic query skips it).
    var absent: [32]u8 = [_]u8{0xee} ** 32;
    try std.testing.expect((try substrateDecodeOne(ctx, &absent, a)) == null);
}

```
