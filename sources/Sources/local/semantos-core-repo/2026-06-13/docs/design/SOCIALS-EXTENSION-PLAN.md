---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/design/SOCIALS-EXTENSION-PLAN.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.737154+00:00
---

# Socials Extension — Plan

**Version**: 0.1 DRAFT
**Status**: Plan
**Author**: Todd
**Date**: 2026-04-29
**Related**: `docs/canon/README.md` (canon discipline), `docs/EXTENSIONS-VS-TYPES.md` (the four-tier model), `docs/textbook/27-boot-a-sovereign-node.md` (the 15-step boot), `docs/textbook/28-build-your-first-adapter-kanban.md` (adapter template), `docs/design/WALLET-MOBILE-AUTH-FLOW.md` (ratification channel), `docs/design/HELM-ATTENTION-SURFACE.md` (desktop ratification channel), `docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md` (HTTP outbound precedent).

---

## 0. Headline

> An extension that lets the user's sovereign node draft, store, ratify, and publish copy across X, Bluesky, LinkedIn, Mastodon, Threads, and Instagram — every published post gated by a `cap.social.publish` capability token only the user's hat can spend, every approval flowing through the existing BRC-100 mobile-auth channel, every credential encrypted under a key derived from the root seed, every published post + edit + engagement event recorded as a hash chain on the user's own node. The agent drafts; the user ratifies; the substrate enforces.

---

## 1. The Pattern

```
┌────────────────────────────────────────────────────────────────────┐
│ user's sovereign node                                              │
│                                                                    │
│   ┌────────┐  draft   ┌─────────────────┐                          │
│   │ agent  │─────────►│ social.post.v1  │ state = draft            │
│   │ (LLM)  │  cell    │  LINEAR cell    │ cap.social.draft spent   │
│   └────────┘          └────────┬────────┘                          │
│                                │ user inspects + accepts           │
│                                ▼                                   │
│                       ┌─────────────────┐                          │
│                       │ awaiting_       │                          │
│                       │ ratification    │                          │
│                       └────────┬────────┘                          │
│                                │ approval prompt                   │
│                                ▼                                   │
│   ┌─────────────┐  BRC-100  ┌─────────────────┐                    │
│   │ user's hat  │──signs───►│ ratified         │                   │
│   │ (phone)     │  approval │ cap.social.      │                   │
│   └─────────────┘  payload  │ publish CONSUMED │                   │
│                             │ ratifier_cert_id │                   │
│                             │ stamped          │                   │
│                             └────────┬────────┘                    │
│                                      │ outbound HTTP               │
│                                      ▼                             │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ platform sub-adapter (bluesky | x | linkedin | mastodon |   │   │
│  │ threads | instagram)                                        │   │
│  │                                                             │   │
│  │   OAuth credential (encrypted under root-seed key)          │   │
│  │   POST → platform API                                       │   │
│  │   idempotency key = SHA-256(cell hash)                      │   │
│  └────────────────────────────┬────────────────────────────────┘   │
│                               │ success                            │
│                               ▼                                    │
│                      ┌─────────────────┐                           │
│                      │ published        │ platform_post_id stamped │
│                      │  (immutable)     │                          │
│                      └────────┬────────┘                           │
│                               │ later                              │
│                               ▼                                    │
│              ┌────────────────────────────────┐                    │
│              │ social.engagement.v1 (PATCH)   │ webhook in         │
│              │ likes, reposts, replies, views │ each event = cell  │
│              └────────────────────────────────┘                    │
└────────────────────────────────────────────────────────────────────┘
```

The shape is identical to chapter 28's kanban example: a LINEAR cell whose state advances under capability-token consumption, with the hash chain serving as audit trail. The only differences from kanban are the column labels, the capability tokens minted, and the fact that the final transition (`ratified → published`) calls outbound HTTP instead of just emitting an internal event. K1 (LINEAR consumed exactly once) means a post cannot be ratified twice; K2 (identity verification on every state change) means a draft cannot be ratified without the user's hat signature; K4 (failed opcodes leave PDA state byte-for-byte unchanged) means a failed platform API call is safely retryable without partial-publish corruption.

---

## 2. Where We Are

### What the substrate already provides

The substrate provides almost every primitive this extension needs. The work is composition, not invention.

| Need | Existing primitive | Where |
|---|---|---|
| Outbound transmission with signed envelope | `chain-broadcast` extension | `extensions/chain-broadcast/` |
| Encrypted secret storage under root-seed-derived key | `wallet-toolbox` pattern | `~/.semantos/wallet.json` (boot step 6) |
| Approval prompt → user's phone | BRC-100 mobile-auth flow | `docs/design/WALLET-MOBILE-AUTH-FLOW.md` |
| Approval prompt → user's desktop | Helm attention surface | `docs/design/HELM-ATTENTION-SURFACE.md` |
| Policy enforcement at transitions | `policy-runtime` extension | `extensions/policy-runtime/` |
| Schedule-and-publish-later | `calendar` extension | `extensions/calendar/` |
| Rate-limit / budget gating | `metering` extension (MFP) | `extensions/metering/` |
| Backup / restore of credentials | `recovery` extension | `extensions/recovery/` |
| Multicast publication to peers | mesh + session-protocol | `runtime/session-protocol/` |
| Linearity enforcement at the bytecode gate | cell engine + K1 | `core/cell-engine/` |
| Capability-token UTXO model | BRC-108 + capability domain | core; minted at boot step 6 |
| Hat-based signing identity | BRC-52 + hats | `extensions/calendar/src/domain/hat.ts` |
| Outbound HTTP server precedent | site-as-sovereign-node (WSITE) | `docs/design/WALLET-SITE-AS-SOVEREIGN-NODE.md` |

### What the socials extension adds

Net-new code:

- **An `extensions/socials/` package** with the standard extension manifest from `EXTENSIONS-VS-TYPES.md` §"Extension Manifest".
- **Four cell types** (`social.credential.v1`, `social.post.v1`, `social.thread.v1`, `social.engagement.v1`) registered in the canonical type registry with stable type-hashes and conformance vectors.
- **Three (or four) capability-token classes** (`cap.social.draft`, `cap.social.publish`, `cap.social.delete`, optionally `cap.social.config_credential`) minted alongside `cap.recovery`/`cap.permission`/`cap.data_access` at boot step 6 when the socials extension is enabled.
- **A SocialPost state machine** with kernel-level transition enforcement: `draft → awaiting_ratification → ratified → published | failed`, plus `published → revoked` for take-downs.
- **A `SpeechActPolicy` class in `policy-runtime`** for brand-voice enforcement and prohibited-topic gating, evaluated at the `awaiting_ratification → ratified` step before the user is asked to sign.
- **Per-platform adapter modules** (`bluesky`, `x`, `linkedin`, `mastodon`, `threads`, `instagram`) implementing a common `PlatformAdapter` interface.
- **A new approval-payload type** for the BRC-100 mobile-auth channel: `social.publish.approve` carrying the post body, brand-voice check result, and target platforms; signing it consumes `cap.social.publish`.
- **A pending-approvals widget** in Helm composing the desktop ratification path.
- **An engagement webhook receiver** wired into the node daemon's HTTP server, converting platform webhook payloads into `social.engagement.v1` patch cells.
- **A recovery-payload extension** ensuring `social.credential.v1` cells round-trip through the existing recovery flow.

The four-tier model in `docs/EXTENSIONS-VS-TYPES.md` places this work cleanly: socials is a new **extension** (workspace), it registers four new **types**, those types surface in existing **contexts** (Broadcast, Direct, Memory), and the user interacts through the existing **Helm** attention surface. No tier of the model is altered; only its contents grow.

---

## 3. Phases

The plan splits into substrate-level work (Phases S1–S4, sequential) and per-platform expansion (Phases S5–S10, mostly parallel after S4 lands). Total estimated duration is ~3 weeks of focused engineering for the v1 set (Bluesky + X + the Helm/mobile ratification UX); LinkedIn, Mastodon, Threads, Instagram each take a further ~3 days of independent adapter work.

### Phase S1 — Cell types & conformance vectors (1–2 days, sequential prerequisite)

Define the four cell types with stable type-hashes:

| Type | Type-hash key | Linearity | Purpose |
|---|---|---|---|
| `social.credential.v1` | `social.credential.v1` | LINEAR (rotation-class) | Encrypted OAuth tokens per (platform, account) |
| `social.post.v1` | `social.post.v1` | LINEAR | A single post; advances through the state machine |
| `social.thread.v1` | `social.thread.v1` | PERSISTENT | An ordered grouping of posts (threads, multi-post campaigns) |
| `social.engagement.v1` | `social.engagement.v1` | PATCH | Engagement events patched onto a published post |

Deliverable shape: a `packages/socials-types/` package mirroring the convention used by `core/protocol-types/`. Conformance vectors live at `packages/socials-types/tests/vectors/social_*.json` and assert byte-identical encoding under canonical packing per `core/cell-engine`'s discipline.

Acceptance:
- Each type is round-trippable (pack → unpack → pack produces identical bytes).
- Each type carries the correct linearity flag in its packed header.
- Type-hashes are recorded in `docs/canon/glossary.yml` alongside `cell-header`, `linearity`, and the existing typed cells.

### Phase S2 — Capability mint integration (1 day, sequential)

Modify `apps/node-installer/src/first-boot.ts` so that when the extensions array includes `"socials"`, boot step 6 also mints:

- `cap.social.publish` — held in `~/.semantos/state.json` under the user's root hat.
- `cap.social.delete` — held in `~/.semantos/state.json` under the user's root hat.
- `cap.social.config_credential` — held in `~/.semantos/state.json` under the user's root hat.

`cap.social.draft` is *not* minted at boot. Drafts are runtime-cheap; the agent that drafts requests a `cap.social.draft` UTXO on demand, derived under the existing `cap.permission` delegation mechanism. This keeps the boot-time mint set small and reserves on-chain mint events for the high-stakes capabilities only.

Modify `scripts/install.sh` to add a prompt:

```
prompt_with_default "Install socials extension? (y/n)" "n" INSTALL_SOCIALS
```

If `y`, the extensions array becomes `["sovereignty", "socials"]` (and `["sovereignty", "trades", "socials"]` if trades is also selected).

Acceptance:
- A clean install with `INSTALL_SOCIALS=y` produces three social capability UTXOs in the post-boot state.
- A clean install with `INSTALL_SOCIALS=n` produces none, and `social.post.v1` cell creation is rejected at the type-registry layer.

### Phase S3 — State machine + kernel-gated transitions (2 days, sequential)

Implement the post state machine in `extensions/socials/src/state-machine.ts`. Each transition is gated structurally:

| From | To | Token spent | Signing principal |
|---|---|---|---|
| ∅ | `draft` | `cap.social.draft` | drafting agent (delegated) |
| `draft` | `awaiting_ratification` | none | drafting agent |
| `awaiting_ratification` | `ratified` | `cap.social.publish` | user's hat |
| `ratified` | `published` | none | node daemon (recorded only) |
| `ratified` | `failed` | none (idempotent retry permitted) | node daemon |
| `published` | `revoked` | `cap.social.delete` | user's hat |

The transition gate is enforced by `OP_ASSERTLINEAR` (`0xC5`) on the post cell and `OP_CHECKDOMAINFLAG` (`0xC6`) on the capability token's domain flag, exactly as chapter 28 describes for the kanban move opcode. K4 (failed opcodes leave PDA state byte-for-byte unchanged) ensures a failed platform API call cannot leave the cell in a half-published state — the `ratified → published` step is one atomic write that either fully lands or doesn't.

Acceptance:
- A unit test attempting `awaiting_ratification → ratified` without spending `cap.social.publish` is refused at the kernel gate (K2).
- A unit test attempting two `ratified` transitions on the same post fails on the second (K1, the post cell is already consumed into its successor).
- A unit test inducing an HTTP failure on `ratified → published` confirms cell state is byte-for-byte unchanged (K4) and a retry succeeds.

### Phase S4 — SpeechActPolicy in policy-runtime (1–2 days, sequential)

Add a `SpeechActPolicy` class to `extensions/policy-runtime/`. The policy evaluates a `social.post.v1` cell against:

- A brand-voice rubric (configurable; tone parameters, prohibited topics, required disclaimers).
- A length cap per platform (X 280 chars, Bluesky 300, LinkedIn 3000, etc.).
- A media-attachment policy (allowed mime types, alt-text required for images on X / Bluesky).
- A scheduling-window policy (no posts to LinkedIn outside business hours, optional).

The policy runs at `awaiting_ratification → ratified`, *before* the approval prompt is sent. A failed policy check halts the transition and surfaces the failure to the user with a "policy violation" annotation rather than asking them to ratify a non-conformant post.

Acceptance:
- Policy violations halt at the substrate gate, never reach the approval prompt.
- Policy results are stamped onto the post cell as a `brand_voice_check_result` field (visible to the user during ratification).
- Policy rules are themselves cells (typed `policy.speechact.v1`), versioned and signed by the user — changing brand voice is itself a cap-gated transition.

### Phase S5 — Bluesky adapter (3 days, parallel after S4)

Bluesky first because its API (AT Protocol) is open, OAuth is standard, no paid tier is required for posting, and the Bluesky team explicitly supports automated clients with appropriate user consent.

Deliverables:

- `extensions/socials/src/platforms/bluesky/oauth.ts` — DPoP-based OAuth flow per AT Protocol spec.
- `extensions/socials/src/platforms/bluesky/publish.ts` — `app.bsky.feed.post` record creation with idempotency-key dedupe.
- `extensions/socials/src/platforms/bluesky/delete.ts` — record deletion via `com.atproto.repo.deleteRecord`.
- `extensions/socials/src/platforms/bluesky/poll.ts` — engagement polling (Bluesky doesn't yet support push webhooks; v1 polls every 5 min).

Acceptance:
- End-to-end test: draft a post, ratify on test mobile-auth fixture, observe Bluesky test account receives the post, observe `platform_post_id` stamped onto the cell.
- OAuth-credential round-trip: connect Bluesky account → credential cell created → restart node → cell decrypts under root-seed-derived key → adapter publishes successfully.

### Phase S6 — Mobile-auth ratification payload (2 days, parallel)

Extend the BRC-100 mobile-auth flow with a new approval-payload type:

```ts
interface SocialPublishApproval {
  kind: 'social.publish.approve';
  postCellHash: string;       // 32 bytes hex
  bodyPreview: string;        // first 200 chars for display
  platforms: PlatformId[];
  brandVoiceCheck: 'pass' | 'pass-with-warnings';
  brandVoiceWarnings?: string[];
  scheduledAt?: string;
  estimatedReach?: { platform: PlatformId; followers: number }[];
}
```

The mobile app renders a card showing the full post body, the brand-voice result, the target platforms, and any scheduling window. The user signs with their hat → the signature is sent back to the node → the node verifies, consumes `cap.social.publish`, and advances the post to `ratified`.

Acceptance:
- The mobile app correctly displays a 280-char Twitter post and a 3000-char LinkedIn post on the same approval card without truncation issues.
- A signed approval is verifiable by the node and consumes exactly one `cap.social.publish` UTXO.
- A user-rejected approval (Decline button) leaves the post in `awaiting_ratification` and consumes no token.

### Phase S7 — Helm pending-approvals panel (2 days, parallel)

Add a "Pending approvals" widget to Helm. Lists every post in `awaiting_ratification` state across all platforms, with the same content the mobile card shows. Clicking "Approve" on the desktop produces the same signed payload the mobile flow produces, via the local hat.

This is mostly UI work composing existing Helm primitives. The substrate-level enforcement is identical between mobile and desktop signing paths.

Acceptance:
- A post appearing in mobile's queue also appears in Helm's queue.
- Approving via either channel removes it from both.
- Approval state is consistent across re-renders (no double-approve race).

### Phase S8 — Engagement webhook receiver (2 days, parallel)

Add an HTTP handler at `/.well-known/socials/webhook/<platform>` to the node daemon. Each platform that supports webhooks (X, Threads, Instagram via Meta Graph) registers its webhook to point at this endpoint during the OAuth dance. Each incoming event is verified against the platform's signing secret, mapped to a `social.engagement.v1` cell, and patched onto the corresponding `social.post.v1`.

For platforms without webhook support (Bluesky, Mastodon, LinkedIn for engagement), a polling worker ingests engagement on the same cell schema. Polling uses the `metering` extension to budget API calls per platform per hour.

Acceptance:
- A like on a published Bluesky post produces a `social.engagement.v1` patch cell within 5 minutes (polling).
- A reply on a published X post produces a `social.engagement.v1` patch cell within 30 seconds (webhook).
- Engagement compaction: after 1000 patches on a single post, a summary cell is written and patches >30 days old are pruned.

### Phase S9 — X adapter (3 days, parallel after S5 lands as template)

X is structurally similar to Bluesky but with three additional concerns:

- **Paid tier**. The X API v2 Basic tier (~USD$100/month at time of writing) is required for posting via API. The install prompt must surface this cost so users opt in with eyes open.
- **Idempotency keys are critical**. X has known issues with retried POSTs producing duplicate tweets. Every publish call carries `Idempotency-Key: SHA-256(cellHash)`.
- **Rate limits are aggressive and per-endpoint**. The metering extension's rate-lane mechanism gates publish calls to stay within the per-15-minute window.

Acceptance: same as Bluesky, plus an idempotency test (induced retry produces zero duplicate tweets on the platform).

### Phase S10 — LinkedIn / Mastodon / Threads / Instagram (~3 days each, parallel)

Each follows the proven shape:

- **LinkedIn**: stable OAuth 2.0, w_member_social scope. Long-form text + images first; native video and document posts in a v2 pass.
- **Mastodon**: per-instance OAuth (the user supplies their home instance URL during connection). API is consistent across instances; minor variants between Pleroma/Akkoma forks need adapter-level shims.
- **Threads**: Meta Graph API, Threads scope. App review required for production access; v1 ships with development-mode credentials and surfaces the app-review status to the user.
- **Instagram**: Meta Graph API, instagram_basic + instagram_content_publish. Photo and Reels publishing; Stories not supported by the API as of last review.

### Phase S11 — Editorial calendar composition (2 days, optional, last)

Compose with the `calendar` extension. A scheduled post is a `calendar.event.v1` cell whose payload references a `social.post.v1` cell-hash and whose fire-time is the desired publish time. At fire-time, the calendar's tick handler triggers the post's `ratified → published` transition. Ratification is still required *before* scheduling — the user ratifies once at draft time, the schedule simply delays the platform call.

Acceptance: scheduling a ratified post for `now + 1 hour` results in publication exactly at that time (±30 seconds), with the post cell's full chain intact (draft → awaiting_ratification → ratified → published).

### Phase S12 — Recovery-payload extension (1 day, parallel)

Modify `extensions/recovery/` to include `social.credential.v1` cells in the recovery payload's encrypted blob. The credential cells are already encrypted under a key derived from the root seed; the recovery payload simply needs to know to enumerate them when serialising. On restoration, the credentials decrypt under the freshly-derived root seed and the platform adapters resume operation.

Acceptance: a recovery round-trip on a node with three connected platforms restores all three credentials byte-identically; OAuth tokens that haven't expired during the recovery window remain valid; expired tokens trigger the standard refresh flow on first use.

---

## 4. Cell schemas (detailed)

### `social.credential.v1`

```ts
interface SocialCredentialPayload {
  platform: PlatformId;         // 'x' | 'bluesky' | 'linkedin' | 'mastodon' | 'threads' | 'instagram'
  accountHandle: string;        // user-visible handle (e.g. '@toddprice.bsky.social')
  accountId: string;            // platform-internal stable ID
  encryptedToken: Uint8Array;   // AES-GCM, key derived from root seed
  encryptedRefresh?: Uint8Array;
  scopes: string[];             // OAuth scopes granted
  expiresAt: number;            // unix ms; Infinity for non-expiring
  rotatedFromHash?: string;     // prevStateHash for rotation linearity
  webhookSecret?: Uint8Array;   // encrypted; used to verify inbound webhooks
}
```

Header values: `linearity = LINEAR` with rotation-class flag (a credential cell is consumed when rotated; the new credential cell carries `prevStateHash` pointing back). `pipelinePhase = RELEVANT`.

### `social.post.v1`

```ts
interface SocialPostPayload {
  platform: PlatformId;
  body: string;                 // text content; UTF-8
  mediaRefs: UHRPRef[];         // images, videos hosted on UHRP
  replyToExternalId?: string;   // platform's ID of the post being replied to
  state: PostState;             // 'draft' | 'awaiting_ratification' | 'ratified' | 'published' | 'failed' | 'revoked'
  scheduledAt?: number;         // unix ms; absent = publish immediately on ratification
  brandVoiceCheckResult?: BrandVoiceResult;
  ratifierCertId?: string;      // stamped at ratified
  ratifiedAt?: number;
  platformPostId?: string;      // stamped at published
  publishedAt?: number;
  failureReason?: string;       // stamped at failed; cleared on retry
  idempotencyKey: string;       // SHA-256(cellHash); stable across retries
}

type PostState =
  | 'draft'
  | 'awaiting_ratification'
  | 'ratified'
  | 'published'
  | 'failed'
  | 'revoked';
```

Header values: `linearity = LINEAR`, `pipelinePhase = RELEVANT` until `published`, then `pipelinePhase = SETTLED`.

### `social.thread.v1`

```ts
interface SocialThreadPayload {
  platform: PlatformId;
  title?: string;                // optional human label
  postRefs: string[];            // ordered cell-hashes of social.post.v1 cells
  status: 'drafting' | 'publishing' | 'published' | 'paused';
}
```

Header values: `linearity = PERSISTENT`, `pipelinePhase = RELEVANT`. Threads aren't consumed; they accumulate posts.

### `social.engagement.v1`

```ts
interface SocialEngagementPayload {
  kind: 'like' | 'repost' | 'reply' | 'quote' | 'view' | 'click' | 'save';
  sourcePlatformId: string;     // platform ID of the engaging entity, where exposed
  count?: number;               // for aggregate kinds (views, clicks)
  observedAt: number;
  isAggregate: boolean;         // true for periodic snapshots, false for individual events
}
```

Header values: `linearity = PATCH`, `parentHash` points to the parent `social.post.v1`. The kernel allows unbounded patch cells; compaction reduces them periodically per Phase S8.

---

## 5. Capability tokens

| Token | Mint event | Domain flag | Held by | Spent at |
|---|---|---|---|---|
| `cap.social.draft` | runtime, on-demand | `0x10` | drafting agent (delegated) | post creation |
| `cap.social.publish` | first-boot step 6 | `0x11` | user's root hat | `awaiting_ratification → ratified` |
| `cap.social.delete` | first-boot step 6 | `0x12` | user's root hat | `published → revoked` |
| `cap.social.config_credential` | first-boot step 6 | `0x13` | user's root hat | credential cell create / rotate |

Domain flags `0x10–0x13` are reserved here; the canonical reservation needs a one-line addition to the domain-flag registry in the protocol spec (a small change against `docs/spec/protocol-v0.5.md` §6 — propose alongside the first PR of this work).

`cap.social.draft` is intentionally low-friction: an agent that holds `cap.permission` can derive a `cap.social.draft` UTXO at runtime without user involvement. This means Claude or another agent can draft freely; only ratification — the consequential gate — requires the user's signature.

---

## 6. State machine (formal)

```
                  cap.social.draft
                       spent
              ┌─────────────────────┐
              ▼                     │
        ┌─────────┐  no token   ┌───┴────────────────┐
   ──►  │  draft  │─────────────►  awaiting_         │
        └────┬────┘             │  ratification      │
             │                  └────────┬───────────┘
             │ no token                  │
             │ (cancel)                  │ cap.social.publish spent
             ▼                           │ + hat signature
        ┌─────────┐                      ▼
        │cancelled│              ┌────────────┐
        └─────────┘              │  ratified  │
                                 └─────┬──────┘
                                       │ no token
                                       │ (outbound HTTP)
                              ┌────────┴────────┐
                              ▼                 ▼
                       ┌──────────┐       ┌──────────┐
                       │  failed  │       │published │
                       └────┬─────┘       └─────┬────┘
                            │                   │
                            │ retry             │ cap.social.delete spent
                            │ (no token)        │ + hat signature
                            ▼                   ▼
                       (back to              ┌─────────┐
                        ratified)            │ revoked │
                                             └─────────┘
```

Every edge that consumes a capability token is structurally enforced at the kernel gate. Every edge that doesn't is either a pure state-record (publish success/failure) or a recoverable retry (failed → ratified for replay).

---

## 7. Per-platform adapter interface

```ts
interface PlatformAdapter {
  readonly id: PlatformId;
  readonly maxBodyLength: number;
  readonly supportsMedia: boolean;
  readonly supportsWebhooks: boolean;
  readonly pollIntervalMs: number;

  authorize(): Promise<OAuthFlowResult>;
  refreshCredential(cred: SocialCredential): Promise<SocialCredential>;
  publish(post: RatifiedPost, cred: SocialCredential): Promise<PublishResult>;
  delete(externalId: string, cred: SocialCredential): Promise<void>;
  fetchEngagement(post: PublishedPost, cred: SocialCredential): Promise<EngagementEvent[]>;
  handleWebhook?(req: Request): Promise<EngagementEvent[]>;
  rateLimitState(): RateLimitSnapshot;
}
```

A platform adapter is fungible: adding a new platform is a single new module implementing this interface plus its OAuth specifics. The kernel-level work — cell schemas, state machine, capability tokens — does not change per-platform.

---

## 8. Composition with existing extensions

This work composes; it does not duplicate. Concretely:

| Where socials extension would otherwise re-invent | Existing extension it composes with |
|---|---|
| Outbound HTTP signed-envelope protocol | `chain-broadcast` (HTTP-transport variant) |
| Encrypted credential at rest | `wallet-toolbox` pattern (key derivation from root seed) |
| Mobile approval signing | BRC-100 mobile-auth flow (new payload type only) |
| Desktop approval UI | Helm attention surface (new widget only) |
| Brand-voice / topic policy | `policy-runtime` (new policy class only) |
| Schedule a future publish | `calendar` (new event subtype only) |
| Rate-limit budget per platform | `metering` (new MFP rate-lane only) |
| Backup of OAuth credentials | `recovery` (existing payload extended) |
| Audience targeting / segments | `navigator` / `navigation` (optional, v2) |
| Engagement audit trail | hash chain (no new mechanism) |

---

## 9. Lexicon decision

The substrate has eight lexicons (jural, CDM, circuit, project-mgmt, property-mgmt, risk-assessment, bills-of-lading, control-systems). A "speech act" lexicon for socials is plausible — publication is structurally a Hohfeldian power-act, retraction is a power-revocation, amplification (repost) is a transferred power, etc.

For v1, **reuse `jural`**. Publication maps cleanly to `power` (the user holds the power to publish), retraction to `power-revocation`, prohibited-topic blocks to `prohibition`, and a brand-voice exception to `liability` (the user assumes liability for an out-of-rubric post by overriding). Chapter 28's kanban example uses the jural lexicon without inventing a new one; we follow the same pattern.

Revisit in v2 if a finer-grained speech-act taxonomy proves necessary — for example, if a moderation use-case wants to distinguish "assert" from "amplify" from "endorse" with different capability tokens. The substrate is designed for that elaboration to be additive (a new lexicon at `proofs/lean/Semantos/Lexicons/Publication.lean` plus a vocabulary in `extensions/socials/src/lexicon.ts`) without breaking the v1 work.

---

## 10. Boot-sequence integration

The 15-step boot in `docs/textbook/27-boot-a-sovereign-node.md` § The 15-Step Boot Sequence is the integration point. Three steps need a small addition; no step needs restructuring.

| Step | Today | With socials extension enabled |
|---|---|---|
| 1 — Email + challenges | unchanged | unchanged |
| 6 — Capability domain mints initial UTXOs | mints `cap.recovery`, `cap.permission`, `cap.data_access` | additionally mints `cap.social.publish`, `cap.social.delete`, `cap.social.config_credential` |
| 7 — Cell engine boots; `kernel_set_enforcement(1)` | unchanged | unchanged |
| 12 — Adapters subscribe to feeds | adapters subscribe to identity, capability, tick feeds | socials adapters additionally subscribe to platform-engagement webhook feeds |
| 13 — Recovery payload backed up | payload includes wallet, certs, derivation states | additionally includes `social.credential.v1` cells (encrypted) |

No new boot step. The socials work fits inside the existing scaffolding, which is the architectural test that confirms it's the right shape — anything that requires a new top-level boot step would indicate the work has crossed from extension into substrate, which it does not.

---

## 11. Deliverables (D-S1 through D-S12)

Following the canon's deliverable-ID convention. Existing prefixes occupy D-V (verifier), D-A (identity axis), D-B (storage axis), D-C (transport axis), D-D (type axis), D-E (time axis), D-F (recovery), D-G (metering). Reserve **D-S** for socials.

| ID | Title | Phase | Deps | Est. days |
|---|---|---|---|---|
| D-S1 | Cell type definitions + conformance vectors | S1 | — | 2 |
| D-S2 | Capability mint integration with first-boot | S2 | D-S1 | 1 |
| D-S3 | SocialPost state machine + kernel-gated transitions | S3 | D-S1, D-S2 | 2 |
| D-S4 | SpeechActPolicy in policy-runtime | S4 | D-S3 | 2 |
| D-S5 | Bluesky adapter (OAuth + publish + delete + poll) | S5 | D-S3 | 3 |
| D-S6 | Mobile-auth ratification payload type | S6 | D-S3 | 2 |
| D-S7 | Helm pending-approvals widget | S7 | D-S6 | 2 |
| D-S8 | Engagement webhook receiver + patch-cell schema | S8 | D-S5 | 2 |
| D-S9 | X adapter | S9 | D-S5 (template) | 3 |
| D-S10 | LinkedIn adapter | S10 | D-S5 (template) | 3 |
| D-S11 | Editorial-calendar composition | S11 | D-S6, calendar extension | 2 |
| D-S12 | Recovery-payload extension for OAuth credentials | S12 | D-S1, D-F* | 1 |

**Sequential prerequisites**: D-S1 → D-S2 → D-S3 → D-S4. About 7 days of focused engineering before parallelism unlocks.

**Parallel after D-S4 lands**: D-S5, D-S6, D-S7, D-S8, D-S12. About 1 week to first end-to-end Bluesky publish.

**Parallel after D-S5 lands as template**: D-S9, D-S10, D-S11, plus Mastodon/Threads/Instagram analogues. ~3 days each.

**Total v1 (Bluesky + X end-to-end with mobile + Helm ratification + recovery)**: ~3 weeks.

Add 3 days per additional platform.

---

## 12. Acceptance gates (binding for every deliverable)

Every PR in this commission MUST pass the following before merge:

1. **Canon discipline**: only canonical glossary terms used. The PR description includes `Canon discipline: passed`. Run: `bun docs/canon/render/glossary-to-md.ts` → grep deliverable for non-canonical aliases.
2. **K1 enforcement test**: a unit test attempts to publish the same post twice and confirms the kernel refuses the second call.
3. **K2 enforcement test**: a unit test attempts a `draft → ratified` transition without spending `cap.social.publish` and confirms the kernel refuses.
4. **K4 enforcement test**: a unit test induces an HTTP failure on the `ratified → published` step and confirms cell state is byte-for-byte unchanged after the failure.
5. **Conformance vectors** for any new cell type round-trip byte-identically.
6. **Recovery round-trip**: encrypt a credential under a root-seed-derived key, encode in recovery payload, decode, decrypt — bytes match input.
7. **Mobile-auth round-trip**: emit `social.publish.approve` payload, sign with a hat fixture, verify on the node, confirm `cap.social.publish` UTXO is consumed in the verifying transaction.
8. **No new top-level boot step**: confirmed by the absence of changes outside steps 6, 12, 13 in `apps/node-installer/src/first-boot.ts`.
9. **Updates `docs/canon/deliverables.yml`**: status `pending → in_progress` on PR open, `in_progress → merged` on PR merge, with the PR URL recorded.

---

## 13. Risks & open questions

- **Platform terms-of-service**. Most platforms' TOS allow user-instructed automated posting but disallow fully autonomous posting. The ratification model aligns with this — every post is user-instructed by signature — but each platform's specific clauses need a one-paragraph review per adapter PR. Bluesky's automated-account guidelines are the most permissive; X's are the strictest.
- **OAuth refresh failures while user is offline**. If a refresh token expires while the user is offline and several ratified posts are queued, all queued posts will fail with auth errors at publish time. Need a "credential expired" state surfaced through the existing wallet-recovery channel. Resolution: a credential-rotation prompt analogous to the wallet-rotation prompt the recovery extension already supports.
- **Idempotency under platform retry**. A published post that errors on the response side (network blip after the platform accepted the post) may double-publish on naive retry. Each adapter MUST store the idempotency key (= cell hash) and reuse it on retry. X enforces idempotency keys natively; Bluesky requires record-create-with-known-CID; LinkedIn requires the X-Restli-Protocol-Version header pattern.
- **Engagement at scale**. A viral post creates tens of thousands of patch cells. Compaction strategy: every 1000 patches, write a summary cell and prune patches older than 30 days. Acceptable because engagement detail is recoverable from the platform itself — the local hash chain need only carry the user's authorised actions plus aggregate engagement, not a forensic copy of every external interaction.
- **Multi-account per platform**. One user, multiple Bluesky accounts (personal, work, alt). Credentials are already keyed by `(platform, accountId)`, but the UI needs to surface account selection at draft time. Defer the multi-account UX to v2; v1 ships with one account per platform per node.
- **Cross-posting**. One ratified intent should be publishable to multiple platforms in one action. Two architectural options: (a) the post cell carries a multi-platform list and the publish step fans out; (b) one ratified-master cell spawns N platform-specific child cells. **Recommend (b)** — each platform copy is its own cell with its own engagement chain, its own platform-specific length cap, its own brand-voice variant. Cleaner under K1 (each platform copy is its own LINEAR resource) and cleaner for analytics.
- **Lexicon decision**. Reuse `jural` v1; revisit if moderation use-cases need finer speech-act vocabulary. Documented above in §9.
- **Pricing**. X API v2 Basic tier is ~USD$100/month for posting access. LinkedIn and Bluesky are free. Mastodon is free per instance. Threads/Instagram require Meta app review, free in development. Surface these costs in the install prompt so users opt in with eyes open.
- **App-review timelines**. Threads and Instagram require Meta app review for production access (typically 4–8 weeks). Recommend dispatching the app-review process in parallel with D-S1, so production credentials are available by the time those adapter PRs are ready to merge.
- **Webhook signature verification**. Each platform signs webhooks with its own secret. The webhook receiver must verify before persisting. A misconfigured secret produces an unverifiable webhook, which is silently dropped — needs a metric and an alert.

---

## 14. What success looks like

After v1 lands, the following sequence works end-to-end:

```bash
# install (or upgrade) with socials enabled
$ INSTALL_SOCIALS=y bash scripts/install.sh
[semantos] Detected: Ubuntu 22.04
[semantos] Bun installed: v1.1.x
...
[semantos] Generated capability UTXOs: cap.recovery, cap.permission,
           cap.data_access, cap.social.publish, cap.social.delete,
           cap.social.config_credential
[semantos] Service active. Workbench: http://<host>:3000

# connect a Bluesky account (consumes cap.social.config_credential, signed by hat)
$ semantos socials connect bluesky
Opening browser to https://bsky.social/oauth/authorize?...
... [user completes OAuth] ...
Connected: @toddprice.bsky.social
Credential stored as social.credential.v1 (cellhash=8f3a...)

# draft a post (Claude, an MCP, or any agent holding cap.permission)
$ semantos socials draft --platform bluesky \
    "Just shipped the socials extension on Semantos. \
     Every post is capability-token-gated; my hat is the \
     ratification key. Demo thread incoming."
Drafted social.post.v1 (cellhash=2c4e...)
Brand-voice check: pass
Awaiting ratification — push sent to phone.

# user's phone shows: "Approve this post for @toddprice.bsky.social? [Approve] [Decline]"
# user taps Approve, signs with hat
# node receives signature, consumes cap.social.publish, advances to ratified
# adapter publishes immediately

$ semantos socials history 2c4e...
draft                     2026-04-29T14:02:13Z  agent
awaiting_ratification     2026-04-29T14:02:13Z  agent
ratified                  2026-04-29T14:02:47Z  hat=todd-root  cap.social.publish spent
published                 2026-04-29T14:02:48Z  bsky_id=at://did:plc:.../app.bsky.feed.post/3kxxx
engagement                2026-04-29T14:08:12Z  like (1)
engagement                2026-04-29T14:11:33Z  repost (1)
engagement                2026-04-29T14:24:01Z  reply (1)
```

The defining property: at no point in this flow does the user trust an external service with the authority to publish on their behalf. Every published post carries a cryptographic chain back to a hat signature on a specific approval payload at a specific time, and the chain is replayable from the user's own node without any external dependency.

---

## 15. Recommended next step

Open Wave 2 commission at `docs/canon/commissions/wave-2-socials.md`, modeled on Wave 1.5: 12 deliverables (D-S1 through D-S12), sequential prereqs S1 → S2 → S3 → S4, then parallel adapter work after S4 lands. Land Bluesky first as the integration template (analogous to how D-V3 wired the verifier sidecar into World Host as the template for subsequent surfaces). Subsequent platforms reuse the proven adapter shape — same as the 7+7 monolith refactor wave that's already been proven.

The substrate work (D-S1 through D-S4) is ~7 focused days. End-to-end Bluesky publishing with mobile + Helm ratification (through D-S8) is ~3 weeks. Each additional platform is ~3 days. The bottleneck for full coverage is Meta app review (Threads + Instagram), ~4–8 weeks calendar time, dispatchable in parallel with all other work.

This is the next adapter the textbook is set up to teach. Chapter 28 builds the kanban; the analogous chapter for socials follows the identical structure — only the column labels and the capability-token names change.

---
