---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/BRAIN-DISPATCHER-UNIFICATION.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.722486+00:00
---

# brain — Dispatcher Unification (D-W1)

**Version**: 0.2 DRAFT
**Status**: Plan
**Authors**: Todd
**Date**: 2026-04-30 (v0.1), 2026-04-30 (v0.2)
**Changelog**:
- 0.2 — added §2.5 "the operator who is also a musician" as canonical motivating example for the multi-vertical case (carpenter + musician hats on one brain); added `llm.*` resource family to §3 inventory; clarified extension-defined resources are first-class.
- 0.1 — initial draft; resource inventory; five-phase migration; relation to oddjobz plan.

**Related**:
- `docs/design/WALLET-SHELL-VPS-SUBSTRATE.md` (the Semantos Brain substrate this doc refines)
- `docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md` (WSITE site_server, route types)
- `docs/design/ODDJOBZ-EXTENSION-PLAN.md` (consumes D-W1; the dispatcher is the substrate D-O1–D-O4 land on)
- `docs/EXTENSIONS-VS-TYPES.md` (four-tier model; hat-switching is per the §3 invariants)
- GitHub issues filed against `runtime/semantos-brain` after D-O5/O5a (bearer-token path divergence, log-not-watched, no OPTIONS, no directory route)

---

## 0. Headline

> brain today is a single binary that grew four operator-facing surfaces (CLI, interactive REPL, HTTP REPL, site server) by accretion. Each surface owns its own slice of state, mutates on its own schedule, and shares with the others through the filesystem. Bearer tokens issued by the CLI are invisible to the daemon until restart; the HTTP server doesn't speak OPTIONS; site_server has two route types because that's what the design needed in week one. These are not four bugs — they are the surface symptoms of one missing decision: **brain has not picked who owns state.**
>
> The unification: **one dispatcher, many transports.** A single dispatcher mediates every mutation against every brain-managed resource (bearer tokens, sites, modules, headers, sessions, capabilities, files, LLM operations). Transports — interactive shell, CLI-as-RPC-client, HTTP/1.1 + WSS, and (future) SignedBundle mesh peers — are thin adapters into that dispatcher, not parallel code paths.
>
> The motivating case is multi-vertical: an operator who is both a carpenter and a musician runs **two extensions** (`oddjobz` + `studio`) on the **same brain**, each with its own resources, capabilities, and helm views. Hat-switching makes the carpenter resources structurally invisible to the musician hat and vice versa — same VFS, same dispatcher, two operational worlds that don't bleed (§2.5). Path A (per-extension `host_llm` imports) re-implements LLM plumbing per extension. Path B (native chat route) locks the substrate into one LLM-call shape. Only the dispatcher composes — adding the music extension is six lines, not a refactor.
>
> Pick this seam now, before D-O1–D-O4 (substrate prep) and D-O5p (cert pairing) commit a generation of code to the current grafted-A-and-B compromise.

---

## 1. Where We Are

The four issues filed after D-O5/O5a all share a root cause:

| # | Issue | Root cause |
|---|---|---|
| 1 | CLI and daemon read bearer tokens from divergent paths | Both processes write/read directly to disk; no one chose the canonical root |
| 2 | Daemon doesn't pick up new bearer tokens until restart | Bearer issuance is fundamentally a runtime mutation; forcing it through "write a file, hope the daemon notices" is a category error |
| 3 | HTTP server returns 405 on OPTIONS | The HTTP listener implements exactly the verbs each route happened to need; CORS preflight wasn't on the path so it isn't there |
| 4 | site_server has no directory/glob route type | `RouteType` enum has the shapes WSITE1 needed (`static`, `dynamic`); SPAs need a third shape that nobody added |

Issues #1 and #2 are mostly retired by D-O5p (cert-based auth replaces bearer tokens), but the *pattern* survives: every future runtime-mutating operation (cert issuance during pairing, capability minting, session creation, payment claim posting, dispatch envelope acceptance from a peer) has the same shape and will hit the same wall. Issues #3 and #4 are independent transport-layer gaps that compound the harder issues #1 and #2 generalise into.

**The two state models living inside brain today:**

```
                   ┌───────────────────────────────────────┐
                   │           Model A — disk-owned         │
                   │                                        │
    brain CLI  ◀────▶│  - site.json                           │
    (one-shot)     │  - module manifests                    │
                   │  - bearer-tokens.log                   │
                   │  - audit log                           │
    brain daemon  ◀──┤  - header store                        │
    (long-running) │  - slot stores                         │
                   │                                        │
                   │  Both processes read/write directly.   │
                   │  Concurrency: hope the OS handles it.  │
                   └───────────────────────────────────────┘

                   ┌───────────────────────────────────────┐
                   │       Model B — daemon-owned, RPC      │
                   │                                        │
    HTTP REPL ────▶│  POST /api/v1/repl  (bearer-gated)     │
    helm SPA       │  - status, find, do, talk verbs        │
    Flutter (TBD)  │  - exec'd in the daemon's address      │
                   │    space, audit logged                 │
                   │                                        │
                   │  Used for: REPL verbs, WSS wallet      │
                   │  endpoint, anything the helm UI needs. │
                   └───────────────────────────────────────┘
```

Model A is what the operator's hands touch. Model B is what the helm and (future) mobile peers touch. They were grafted together because the deployment story added each as a separate surface. Today they intersect through the filesystem, which is why issues #1 and #2 exist: the CLI does Model A on `bearer-tokens.log`, the daemon does Model A on the same file, and there's no Model B path for "issue a bearer token through the running daemon."

---

## 2. The Unification — One Dispatcher, Many Transports

```
┌───────────────────────────────────────────────────────────────────┐
│                       brain dispatcher                              │
│                                                                   │
│   Single source of truth for every mutation. Auth-gated,          │
│   capability-checked, audit-logged, atomic per-command.           │
│                                                                   │
│   handle(transport_ctx, command, args) → result                   │
│                                                                   │
│   Resources:                                                      │
│     - bearer_tokens   (issue, revoke, list, validate)             │
│     - sessions        (create, terminate, list)                   │
│     - sites           (init, list, route_add, signing_secret_*)   │
│     - modules         (verify, load, list, hash)                  │
│     - headers         (tip, byHeight, byHash, range, sync_state)  │
│     - capabilities    (mint, check, revoke, list)                 │
│     - identity_certs  (issue_child, list, revoke)                 │
│     - files           (read, write_dir, list_dir)                 │
│     - audit           (append-only; all of the above emit here)   │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
        ▲              ▲                ▲                  ▲
        │              │                │                  │
   ┌────┴────┐    ┌────┴─────┐    ┌─────┴──────┐    ┌──────┴───────┐
   │ in-proc │    │  Unix    │    │   HTTP/    │    │  SignedBundle│
   │  shell  │    │  socket  │    │   WSS      │    │   mesh peer  │
   │         │    │  CLI-RPC │    │            │    │   (future)   │
   └─────────┘    └──────────┘    └────────────┘    └──────────────┘
        ▲              ▲                ▲                  ▲
        │              │                │                  │
  brain repl       brain <cmd>          helm SPA          Flutter mobile
  (TUI/SSH)     from terminal       (browser)         shell, federated
                                                       tenant nodes
```

**Three properties the unification gives us for free:**

1. **The CLI and the helm UI execute the same code.** `brain bearer issue --label foo` and a helm-side `POST /api/v1/dispatch?cmd=bearer.issue&label=foo` flow through the dispatcher's identical `Bearer.issue(...)` resource handler. Path divergence (#1) is structurally impossible. Live updates (#2) are inherent because the dispatcher mutates in-memory state and persists the change as a single transaction.

2. **New transports compose; they don't fork business logic.** Adding the SignedBundle mesh transport for D-O5m (Flutter) is "wire envelope decode + auth-context construction → call dispatcher." Same for adding a TUI shell, an SSH transport, or anything else. The dispatcher doesn't know which transport invoked it; it just gets a `transport_ctx` describing the caller's authentication and capability scope.

3. **OPTIONS, ranges, directory routes, content negotiation become transport concerns.** The HTTP transport is one place. Add OPTIONS once. Add `Range:` once. Add gzip negotiation once. The dispatcher and the route handlers don't see HTTP plumbing. Issue #3 lives in one file and doesn't reappear.

---

## 2.5 The motivating example — the operator who is also a musician

The strongest argument for the dispatcher seam isn't any of the four brain issues; it's what the operator-surface looks like when a single human runs **two** extensions on the same brain. Carpenter Todd runs `oddjobz`. Musician Todd runs `studio`. They are the same person, the same root cert, the same Semantos Brain, the same VFS — and they want **two separate operational worlds that don't bleed into each other.**

Under Path A (per-extension `host_llm_complete` host imports), each extension's WASM handler wires its own LLM-call plumbing, retry logic, model selection, conversation-context handling. Two extensions = two parallel implementations of the same plumbing; three = three; the LLM-integration cost compounds per extension.

Under Path B (native chat route in `site_server`), the substrate locks itself into one LLM call shape (free-form chat). Music doesn't want a chat box — it wants `transcribe-this-hummed-melody`, `suggest-a-chord-progression`, `write-a-press-blurb`. Adding new shapes means adding new route types; you can't compose, only extend.

Under Path C (the dispatcher), the picture is:

```
dispatcher core
   │
   ├─ resource: llm.complete            (cap.llm.complete:<scope>)
   ├─ resource: llm.transcribe_audio    (cap.llm.transcribe:<scope>)
   ├─ resource: llm.embed               (cap.llm.embed:<scope>)
   │
   ├─ resource: oddjobz.lead_extract    (uses llm.complete with carpenter scope)
   ├─ resource: oddjobz.quote_draft     (uses llm.complete + trades lexicon)
   │
   ├─ resource: music.idea_capture      (uses llm.transcribe_audio with music scope)
   ├─ resource: music.chord_suggest     (uses llm.complete + music-theory prompt)
   ├─ resource: music.lyric_polish      (uses llm.complete + songwriter prompt)
   │
   └─ transports: helm desktop, Flutter mobile, public chat widget,
                  SignedBundle mesh, federated peer
```

Adding the music extension is purely additive: register new resource handlers under the `music.*` namespace, declare new capabilities (`cap.music.idea_capture`, `cap.music.chord_suggest`), drop a studio lexicon at `proofs/lean/.../Studio.lean`, ship the helm views. **None of `oddjobz` changes.** The dispatcher doesn't care that there's now a music vertical; it just routes more resources.

**Hat switching becomes structural, not advisory.** The operator's root cert derives two context-tagged child hats via BRC-42 BKDS — one for the carpenter context (e.g. tag `0x10`), one for the musician context (`0x11`). Capability mints under the carpenter hat produce UTXOs the musician hat literally cannot present, and vice versa. When carpenter Todd is the active hat, the policy evaluator filters dispatchable resources to those whose handlers consume `cap.oddjobz.*` capabilities; `music.*` resources are **structurally invisible** — not gated by a permission check, but by the fact that the active hat cannot produce the required cap UTXOs. Same brain, same substrate, same VFS, same dispatcher; two operational worlds that don't bleed. K3 (domain-flag isolation, per the kernel invariants) is what makes this structural rather than reliant on bug-free permission checks.

The desktop helm and Flutter mobile shell pick this up for free: both read "which resources can the active hat dispatch right now?" from the dispatcher and render the corresponding tier-3 popovers (per `docs/EXTENSIONS-VS-TYPES.md`). Switch hats; popovers change. Voice-shell grammar adapts: "do | quote | the deck job at three grand" parses under carpenter; "do | suggest | a chord progression in D minor" parses under musician. Same `do | find | talk` modal grammar, different vocabularies, different capability scopes, same engine.

The economics: Path A's apparent ~2-day saving over Path C is illusory once a second extension exists. Every LLM-using extension shipped after carpenter + musician (accountant, photographer, REA bridge, fitness coach, whatever) **reuses the dispatcher's `llm.*` resources** rather than re-implementing them. Per-scope capability gating (`cap.llm.complete:<extension>-only`) means a buggy extension cannot drain another's budget or read its prompts. Trust boundary is centralised; per-extension code stays vertical-shaped, not stack-shaped.

This is also the only path where "I'd like to drop in a music extension on my brain" is a six-line operation (manifest + capability declarations + resource registrations + helm views + cap mints via `device pair` + hat-switch in helm) rather than a substrate refactor. The dispatcher doesn't distinguish between "a new tenant's first extension" and "an existing tenant's second extension" — they're the same operation.

This is the canonical motivating example for D-W1. Every section that follows (resource set, dispatcher interface, transports, capabilities) is shaped to make the carpenter-and-musician case land in six lines.

---

## 3. Resource Set (initial inventory)

Every brain-mutable thing is a resource with a typed handler. The handler is the only code that mutates the underlying storage. v0.1 enumerates the resources that exist today; future deliverables (D-O5p pairing, D-O8 tenant manifests, D-O11 federation) add resources to this table without touching the dispatcher core.

| Resource | Mutating ops | Read ops | Persistence |
|---|---|---|---|
| `bearer_tokens` | `issue`, `revoke` | `list`, `validate` (internal) | append-only log + in-memory index |
| `sessions` | `create`, `terminate` | `list` | in-memory + disk for resume |
| `sites` | `init`, `route_add`, `route_remove`, `set_listen_port` | `list`, `get_config`, `validate` | per-domain `site.json` |
| `modules` | `register`, `unregister` | `list`, `get_hash`, `verify` | `brain.json` modules section |
| `headers` | `append_validated` *(headers-verifier WASM only)* | `tip`, `byHeight`, `byHash`, `range`, `sync_state` | LMDB header store |
| `capabilities` | `mint`, `revoke` | `list`, `check` | identity-cert capability scope (BRC-52 cert chain) |
| `identity_certs` | `issue_child`, `revoke` *(operator root only)* | `list`, `verify` | cert chain store |
| `files` | `write` *(under site content_root only, path-traversal rejected)* | `read`, `list_dir`, `stat` | filesystem (sandboxed to data_dir / site dirs) |
| `llm.complete` | `complete` *(cap-scoped; rate-limited per-scope)* | — | stateless; calls `llm_http_adapter` under operator's enabled backend config |
| `llm.transcribe_audio` | `transcribe` *(cap-scoped; bytes in, text out)* | — | stateless; future-Brain 5.x — placeholder until backend lands |
| `llm.embed` | `embed` *(cap-scoped; text in, vector out)* | — | stateless; future-Brain 5.x — placeholder |
| `audit` | `append` *(internal-only; every other resource calls this)* | `tail`, `query` | append-only log |

Extension-defined resources (e.g. `oddjobz.lead_extract`, `oddjobz.quote_draft`, `music.idea_capture`, `music.chord_suggest`) register at extension load time with their declared capability requirements. They are first-class citizens of the dispatcher; the substrate has no special case for "core" vs "extension" resources. The carpenter+musician example in §2.5 is what this row of the table looks like in practice.

A resource handler signature in Zig pseudocode:

```zig
const ResourceHandler = struct {
    name: []const u8,                // "bearer_tokens"
    handle: *const fn (
        ctx: *DispatchContext,        // who's calling, what cap scope
        cmd: Command,                 // tagged union of ops
    ) anyerror!Result,                // typed result OR audit-logged failure
};
```

`Command` is per-resource (`bearer_tokens.Command = enum { issue: IssueArgs, revoke: RevokeArgs, list, validate: ValidateArgs }`). `Result` is per-resource. The dispatcher routes `(resource_name, command_tag) → handler` and is itself ~50 lines of Zig.

---

## 4. Dispatcher Interface

The single entry point every transport calls:

```zig
pub const DispatchContext = struct {
    /// Who is calling — populated by the transport.
    auth: AuthContext,
    /// What capability scope they're acting under.
    capabilities: CapabilitySet,
    /// Transport-specific metadata (request id, peer info, timestamp).
    meta: TransportMeta,
};

pub const AuthContext = union(enum) {
    /// In-process call from the Semantos Brain binary itself (e.g. interactive
    /// REPL on the operator's terminal, or first-boot init before any
    /// identity is enrolled). Treated as root cap scope.
    in_process_root,

    /// Local Unix-socket CLI client. The socket has Unix peer creds; the
    /// dispatcher only accepts connections from the same uid as the daemon,
    /// so this also gets root cap scope.
    local_uid: u32,

    /// Remote caller authenticated by an identity cert (post-D-O5p).
    /// Capabilities derived from the cert's scope.
    cert: IdentityCert,

    /// Legacy bearer (pre-D-O5p; deprecated once cert auth lands).
    bearer: BearerToken,

    /// Unauthenticated (visitor on the public chat endpoint, etc.).
    /// Cap scope is whatever the per-site config grants the anonymous role.
    anonymous: AnonymousCtx,
};

pub fn dispatch(
    self: *Dispatcher,
    ctx: *DispatchContext,
    resource: []const u8,
    cmd: anytype,
) !Result {
    const handler = self.handlers.get(resource) orelse return error.unknown_resource;
    try self.checkCapabilities(ctx, resource, @tagName(cmd));
    const before_audit = try self.audit.beginEntry(ctx, resource, cmd);
    const result = handler.handle(ctx, cmd) catch |err| {
        try self.audit.complete(before_audit, .{ .err = err });
        return err;
    };
    try self.audit.complete(before_audit, .{ .ok = result });
    return result;
}
```

Three things this shape enforces:

- **Auth precedes audit precedes mutation.** Capability check first (failures audit-log without revealing why); audit entry begin/complete brackets the mutation; failures are logged. No code path mutates a resource without a corresponding audit pair.
- **Resources don't know about transports.** A resource handler sees `DispatchContext.auth.cert` or `.local_uid` and applies its policy; it has no awareness of HTTP headers, Unix peer creds, or websocket frames.
- **Transports don't know about resources.** The HTTP transport parses one of `/api/v1/dispatch/<resource>/<cmd>` (or whatever wire format §6 picks), constructs a `DispatchContext`, and calls `dispatcher.dispatch(...)`. New resources don't require HTTP-server changes.

---

## 5. Transports

### 5.1 In-process (interactive shell, first-boot init)

`brain repl` (current) and `brain init` (current) call `dispatcher.dispatch(...)` directly. `AuthContext = .in_process_root`. No serialisation. Same dispatcher binary, no transport overhead.

### 5.2 Unix socket (CLI-as-RPC-client)

Replaces the current "CLI does Model A directly" pattern. New shape:

- Daemon binds a Unix socket at `$BRAIN_DATA_DIR/brain.sock` on startup, mode `0600`, owned by the daemon's uid.
- CLI commands (`brain bearer issue`, `brain site init`, etc.) check for the socket. If present, connect, send the command in §6's wire format, render the response.
- If absent (e.g. running `brain init` before the daemon exists, or running on a host where the daemon isn't installed), CLI falls back to **embedded mode**: spins up a dispatcher in-process, opens the data_dir directly, executes the command, exits. This preserves the "single-binary, no-services-required" first-boot story.
- The Unix socket transport's auth is Unix peer creds: only the daemon's own uid can connect, which gives root cap scope.

This is the seam where issues #1 and #2 die. The CLI never writes `bearer-tokens.log` directly; it asks the daemon to issue, the daemon mutates its own log + in-memory index, returns the new token. The operator pastes the token into the helm; the helm hits the dispatcher over HTTP; the daemon recognises it because it's the same dispatcher's index.

### 5.3 HTTP / WSS (helm SPA, future webhooks)

Keeps the existing `/api/v1/repl` and `/api/v1/wallet` endpoints but reframes them:

- `/api/v1/repl` becomes `/api/v1/dispatch/<resource>/<cmd>` (or, if backward-compat matters, `/api/v1/repl` keeps the old shape and the dispatcher accepts a "REPL command string" alias).
- WSS endpoints are HTTP transport with a websocket upgrade; the same `DispatchContext` flows through, but the response is streamed.
- OPTIONS preflight: handled in one place at the top of the HTTP handler. CORS allowed-origins read from per-site config.
- Range, gzip, content-type — all transport-level, not in dispatcher scope.

### 5.4 SignedBundle / mesh (future, D-O5m + D-O11)

Mobile Flutter peer and federated tenant nodes send `SignedBundle` envelopes (the BRC-52 / cell-engine envelope shape) over their available transport (BLE / multicast / Plexus push). The receiving brain decodes the envelope, verifies the cert chain, constructs a `DispatchContext` with `auth.cert = <peer's cert>`, calls the dispatcher. Capability check enforces what the peer is allowed to do.

This is how a tradie's phone proposing a state transition on a `Job` cell ends up authoritatively persisted on the brain: the transition is wrapped in a SignedBundle, mesh-synced to the brain, decoded by the SignedBundle transport, dispatched, persisted, audit-logged. The phone's brain and the brain's brain both run identical dispatchers; they trust each other through cert chains, not through implicit shared state.

---

## 6. Wire Format

The wire format is shared between the Unix socket transport (§5.2) and the HTTP transport (§5.3). One JSON-shaped envelope, isomorphic across transports:

```json
// Request
{
  "v": 1,
  "resource": "bearer_tokens",
  "cmd": "issue",
  "args": { "label": "helm-dev", "ttl_seconds": 86400 },
  "request_id": "req-9f8a..."
}

// Response (success)
{
  "v": 1,
  "request_id": "req-9f8a...",
  "result": {
    "id": "4e51d201bf42...",
    "token": "85f36690a3fa...",
    "expires_at": 1778148499
  }
}

// Response (failure)
{
  "v": 1,
  "request_id": "req-9f8a...",
  "error": {
    "kind": "capability_denied",
    "message": "bearer_tokens.issue requires cap.brain.admin",
    "details": null
  }
}
```

Constraints:
- `request_id` echoed in response (transport-agnostic correlation).
- Errors are typed (`kind: "capability_denied" | "unknown_resource" | "validation_failed" | ...`); messages are human-readable but `kind` is the parseable contract.
- Same envelope on the WSS transport (one JSON message per frame). Streaming responses use `chunk` envelopes and a final `complete` envelope.

---

## 7. Auth & Capabilities — Where They Live

**Capability checks live inside the dispatcher**, not in the transports. Three reasons:

1. **Single audit point.** A capability denial is an audit event; if transports check, half the denials happen pre-dispatcher and never get logged.
2. **Transport-honest delegation.** The transport produces a `DispatchContext.auth` describing what it knows (cert hash, bearer fingerprint, Unix peer uid, anonymous-with-rate-limit). The dispatcher applies policy. No transport has the temptation to say "I'll just allow this because the route looked safe."
3. **Future capability scopes compose.** When tenant manifests arrive (D-O8) with per-tenant capability mints (e.g. `cap.oddjobz.write_customer` granted to a child cert), the dispatcher's check is `does this auth context's cert chain include cap.X?` — one place.

The capability set is a flat list of strings (cap.* dotted namespace) with implicit hierarchy: `cap.brain.admin` implies all sub-scopes; `cap.oddjobz.*` is a wildcard. Resources declare which capability each command requires:

```zig
const bearer_tokens_caps = .{
    .issue   = "cap.brain.admin",      // root or operator
    .revoke  = "cap.brain.admin",
    .list    = "cap.brain.admin",
    .validate = null,                 // anyone with a token can self-validate
};
```

Anonymous transports (visitor chat) get their cap scope from per-site config: a `site.json` declaring `anonymous_caps: ["cap.oddjobz.public_chat.write"]` is what lets a visitor's POST land in the visitor-chat dynamic route without auth. Removed from config = endpoint becomes 401.

---

## 8. Migration Path

This is not a single PR. The dispatcher unification is the architectural backbone that D-O1–D-O4 (substrate prep), D-O5p (cert pairing), and D-O6 v1.0 (canon-aligned chat persistence) land on. Migration happens incrementally as those deliverables touch each subsystem.

**Phase 0 — design + scaffold (this doc + ~3 days Zig)**
- Land `runtime/semantos-brain/src/dispatcher.zig` with the core `Dispatcher`, `DispatchContext`, `AuthContext`, capability check.
- Land `runtime/semantos-brain/src/wire.zig` with the §6 envelope codec.
- Land the in-process transport (§5.1) by routing the existing interactive-REPL command parser through the dispatcher.
- No resources moved yet. Scaffold + tests.

**Phase 1 — bearer tokens + identity certs + llm.complete (parallel with D-O5p, D-O6a)**
- Move bearer issuance behind the dispatcher.
- Stand up Unix socket transport (§5.2).
- CLI's `brain bearer issue` becomes a Unix-socket client; embedded fallback for first-boot.
- Issues #1 and #2 close as side effects.
- D-O5p inherits the same resource shape for `identity_certs.issue_child` (cert pairing).
- **Add the `llm.complete` resource handler** wrapping the existing `llm_http_adapter`. Per-scope rate limits + budget tracking land here. This is what unblocks D-O6a — the visitor-chat dynamic route becomes a thin transport adapter that calls `dispatcher.dispatch(llm.complete, ...)` with anonymous-cap + tenant-prompt context. `llm.transcribe_audio` and `llm.embed` get stubbed handlers in Phase 1 with `not_yet_implemented` errors so extensions targeting future audio/embedding flows can declare their resource deps now without breaking.

**Phase 2 — sites + modules + headers (parallel with D-O1–D-O4)**
- `brain site init` / `brain site validate` / `brain site list` go through dispatcher.
- `brain hash` / module verification go through dispatcher.
- `brain headers tip` / `brain headers sync` / `brain headers serve` go through dispatcher (the long-running `headers serve` HTTP listener becomes the headers transport, calling `dispatcher.dispatch(headers.byHeight, ...)`).

**Phase 3 — HTTP transport rewrite**
- Replace the hand-rolled HTTP listener with a complete HTTP/1.1 transport (or use a lightweight Zig HTTP library if appropriate).
- OPTIONS preflight, Range support, gzip negotiation, per-site CORS config.
- Issues #3 and #4 (the latter via a `directory` route handler in the file resource) close.

**Phase 4 — SignedBundle transport (D-O5m + D-O11)**
- Decode SignedBundle envelopes, verify cert chains, construct `DispatchContext`.
- Mobile Flutter peers and federated tenant nodes plug in here.

Each phase is independently shippable. Phase 0 + Phase 1 is the minimum that retires bearer-token pain in time for D-O5p. Phase 3 is the cleanest moment to land issues #3 and #4.

---

## 9. Non-Goals

- **Not** an RPC framework rewrite (no gRPC, no protocol buffers, no schema-language). The wire format is hand-rolled JSON, ~200 lines of Zig codec. The shape is small enough that "schema is the resource handler signatures + a code-generated TS client for the helm" is the entire story.
- **Not** a permission system overhaul. Capability scopes are flat strings with implicit hierarchy; there is no role-based access control, no group membership, no RBAC matrix. Cert chain → cap set → check.
- **Not** a daemon-only architecture. The CLI's embedded-mode fallback (open data_dir directly when no socket exists) is first-class. brain stays a single binary that works without a running daemon for first-boot, recovery, and offline operations.
- **Not** a replacement for the Semantos Brain ↔ WASM module host_import boundary. The dispatcher is the operator-surface seam; the broker (`runtime/semantos-brain/src/broker.zig`) remains the WASM-host-import seam. They talk to each other (the broker calls dispatcher resource handlers for storage/network), but they're separate concerns.

---

## 10. Risks

- **Migration tax** — moving each subsystem behind the dispatcher is real work. The phased migration in §8 amortises it across deliverables that were going to touch those subsystems anyway, but a "moved everything to dispatcher" PR per phase still has to land cleanly.
- **In-process vs Unix-socket subtle divergence** — if the embedded-mode fallback drifts from the daemon-mode dispatcher, the CLI behaviour stops being deterministic across deployment shapes. Mitigation: shared dispatcher code; no transport-specific logic inside resource handlers; CI suite that runs the same command set against both modes.
- **Capability-check correctness regressions during migration** — the current code has implicit "this CLI command runs as root; it can do anything" assumptions. Moving to explicit cap checks means every resource handler has to declare its required cap correctly. Mitigation: deny-by-default in the dispatcher (`return error.capability_required` if no cap declared for a command), so missing declarations fail loud rather than silently allowing.
- **Audit log volume** — every dispatch emits an audit pair (begin + complete). For high-frequency reads (`headers.byHeight` from a peer SPV client) this is wasteful. Mitigation: per-resource opt-out for read ops that don't mutate (`audit_reads = false` in the resource registration; reads still get rate-limited via transport-layer middleware).

---

## 11. Relation to Other Work

| Deliverable | Relationship |
|---|---|
| **The four scheduled brain issues** (bearer paths, log-not-watched, OPTIONS, directory routes) | All four close as side effects of the migration phases (#1+#2 in Phase 1, #3+#4 in Phase 3). Filing them as separate issues remains valuable for tracking; the implementation lands inside the unification PRs. |
| **D-O6a** (chat widget v0.5, LLM passthrough, no persistence) | Depends on D-W1 Phase 1 (specifically the `llm.complete` resource handler). The visitor-chat route is a thin native transport adapter that calls `dispatcher.dispatch(llm.complete, {scope: "anonymous-oddjobz", prompt: ...})`. v0.5 doesn't persist canonical cells, so canon-misalignment risk is zero — it's the cleanest demo of the dispatcher pattern carrying an LLM resource end-to-end. Originally specced as half-day independent work, but Path A's missing `host_llm` import + Path B's lack of composition make Phase-1-first the right ordering. |
| **D-O5p** (child-cert pairing) | Depends on Phase 1 of D-W1. Pairing is the first feature whose runtime mutation pattern (issue child cert + grant capabilities + register, all atomic, all immediately visible) cannot ship cleanly under the grafted Model-A/B compromise. |
| **D-O1–D-O4** (substrate prep — lexicon, cell types, capability mints, state machines) | Lands on top of Phase 0 + Phase 1, in parallel with Phase 2. The capability mint deliverable (D-O3) explicitly populates the dispatcher's per-resource cap declarations. |
| **D-O6 v1.0** (chat lead extraction + ratification + canon cells) | Depends on D-O2 (cell types) and Phase 2 of D-W1 (`files` resource for chat persistence + `capabilities` resource for the per-tenant chat-handler cap scope). |
| **D-O5m** (Flutter mobile shell) | Depends on Phase 4 of D-W1 (SignedBundle transport). The peer-node mesh story is the SignedBundle envelope crossing transports; without the dispatcher, every mesh-synced state transition needs a custom code path on the receiving side. |
| **D-O7** (substrate cutover from Drizzle/Postgres to brain-native) | Depends on Phase 2 of D-W1 (`files` + per-site storage handlers). The cutover writes to brain-managed storage exclusively, mediated by dispatcher resource handlers. |
| **D-O8** (tenant manifest schema), **D-O9** (per-tenant systemd template), **D-O10** (provisioning CLI) | All depend on the dispatcher — provisioning is a sequence of dispatcher commands (`sites.init`, `identity_certs.issue_child`, `capabilities.mint`, `modules.register`). The provisioning CLI is the second consumer of the wire format after the helm. |
| **D-O11** (cross-vertical federation smoke test) | Depends on Phase 4 (SignedBundle transport). The dispatch envelope from chapter 29 of the textbook is decoded by the SignedBundle transport, just like a mobile peer's local mutation. Federation is mesh-sync between two Semantos Brain nodes; symmetric. |

---

## 12. Acceptance Criteria

D-W1 is "done" when:

- [ ] `runtime/semantos-brain/src/dispatcher.zig` lands with the core dispatcher, audit integration, capability check, and tests covering deny-by-default, unknown-resource, unknown-command, and the ok/err audit pair invariants.
- [ ] `wire.zig` lands with codec round-trip tests for the §6 envelope, including streaming-response chunks.
- [ ] Unix socket transport (§5.2) ships; `brain bearer issue` is a socket client when the daemon is running and an embedded-mode call when it isn't, with CI proving both modes produce identical post-state.
- [ ] HTTP transport (§5.3) is rewired to call the dispatcher; existing `/api/v1/repl` requests behave identically from the helm's perspective; OPTIONS preflight returns 204 with appropriate ACAO; per-site CORS config in `site.json` is honoured.
- [ ] Issues #1, #2, #3, #4 from the post-D-O5/O5a backlog are closed (comment with the migration PR that retired each).
- [ ] At least three resources (`bearer_tokens`, `sites`, `headers`) are fully migrated; remaining resources have stubs that delegate to the existing implementations and a TODO referencing this doc.
- [ ] `docs/textbook/` gets a chapter on the unified dispatcher (substrate-level, peer with chapter 29 on cross-vertical dispatch) so the operator-surface unification is teachable, not just buried in this design doc.

---

## 13. Next Step

Open a `feat/brain-dispatcher` branch off main. Land Phase 0 as the first PR — dispatcher core + wire codec + in-process transport, no resources moved yet. Use the existing `brain repl` interactive shell as the smoke test: every command the operator can type should round-trip through the dispatcher and produce identical output. Then sequence Phase 1 alongside D-O5p so the cert-pairing flow inherits the new shape on day one rather than being retrofitted.
