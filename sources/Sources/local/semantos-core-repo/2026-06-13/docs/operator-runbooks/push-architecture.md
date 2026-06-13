---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/push-architecture.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.636036+00:00
---

# Push architecture — sovereign push (D.1)

This runbook explains the wake-only push flow that sovereign-push
Phase D.1 introduced.  It is the load-bearing reference for why
Google FCM and Apple APNs never see operator content.

## The architectural property

Mobile operating systems require a third-party push gateway to wake
a backgrounded app.  On iOS that's APNs; on Android (without
UnifiedPush) it's FCM.  Both are operator-controlled by Apple and
Google respectively — the operator does not own the wire.

The sovereign-push property says: **the wake-up loop is unavoidable
but the content path is not.**  The brain MUST be the only place
operator-readable content (lead summaries, customer names, prices,
voice transcripts, attachments) ever lands in plaintext.

D.1 enforces this by reducing every push payload to an **opaque
envelope** that carries no operator content:

```
{"event_id":"<16-hex>","ts":<unix-seconds>,"kind":"helm.event"}
```

The device decodes the envelope on wake, opens its bearer-
authenticated WSS to the brain, calls the new `helm.fetch_since`
RPC, and renders the notification banner locally from the result.
Apple and Google see only the wake signal + the opaque envelope.

## Sequence (steady state)

```
operator                 brain                       APNs/FCM        device
   |                       |                            |              |
   |-- helm action ------->|                            |              |
   |                       | broker.publish (opaque)    |              |
   |                       | event lands in ring        |              |
   |                       | + push hook fires          |              |
   |                       |--- wake-only payload ----->|              |
   |                       |  {aps:{content-available:1}|              |
   |                       |   event_id, ts, kind}      |              |
   |                       |                            |--- wake ---->|
   |                       |                            |              | OS hands
   |                       |                            |              | payload
   |                       |                            |              | to silent
   |                       |                            |              | handler
   |                       |                            |              |
   |                       |<------------------ helm.fetch_since ------|
   |                       |  {since_ts: <last-seen>}                  |
   |                       |                                           |
   |                       |---------- result -----------------------> |
   |                       |  events: [{event_id, ts, kind, payload}]  |
   |                       |  next_cursor_ts                           |
   |                       |                                           | local
   |                       |                                           | notification
   |                       |                                           | composed +
   |                       |                                           | shown
```

## Wire shapes (what crosses the operator boundary)

### APNs (wake-only background push)

Headers:
- `apns-topic: <bundle-id>`
- `apns-push-type: background`  (NOT `alert`)
- `apns-priority: 5`            (NOT `10`)
- `authorization: bearer <ES256 JWT>`

Body:
```json
{"aps":{"content-available":1},"event_id":"...","ts":...,"kind":"helm.event"}
```

The `content-available: 1` flag is the only contract Apple
guarantees for waking a backgrounded app silently.  No `alert`,
`sound`, or `badge` keys appear.

### FCM (data-only message)

URL: `https://fcm.googleapis.com/v1/projects/<project>/messages:send`

Body:
```json
{
  "message": {
    "token": "<device fcm token>",
    "android": {"priority": "high"},
    "apns": {
      "headers": {"apns-priority": "5", "apns-push-type": "background"},
      "payload": {"aps": {"content-available": 1}}
    },
    "data": {"event_id": "...", "ts": "...", "kind": "helm.event"}
  }
}
```

There is no top-level `notification` key — that's the contract that
keeps FCM from rendering a banner and forces the OS to wake the
app instead.  The `data` map is string→string (FCM's hard
constraint); the brain stringifies `ts` automatically.

The `android` and `apns` overrides ensure both platforms wake the
app immediately even though the message is data-only.

### Brain → device (after wake)

JSON-RPC 2.0 over the bearer-authenticated WSS:

Request:
```json
{"jsonrpc":"2.0","id":1,"method":"helm.fetch_since",
 "params":{"since_ts":1700000000,"limit":256}}
```

Response:
```json
{"jsonrpc":"2.0","id":1,"result":{
  "events":[
    {"event_id":"0000000000000001","ts":1700000001,
     "kind":"lead.created","payload":{"id":"L1","customer_name":"Alice",...}}
  ],
  "next_cursor_ts":1700000001
}}
```

`since_ts` MUST be non-negative.  `limit` defaults to 256 server-
side and is capped at 256 — devices wanting more must paginate via
`next_cursor_ts`.

## Storage model

The brain holds the recent-event ring buffer in
`helm_event_broker`'s `recent` ArrayList, capped at
`MAX_RECENT_EVENTS = 1024` entries.  When full, the oldest entry
is evicted on the next publish.  A device offline longer than that
window misses older events.

For v0.1 this is acceptable — a pure mobile shell that's been
offline that long is going to want to do a full helm sync via the
existing REPL endpoints anyway, not chase event deltas.  Phase
D.2+ may persist the ring to disk if operator deployments need a
larger window.

## What an operator configures

Nothing new.  The push-config.json from D-O5m.followup-9 Phase B
still drives APNs / FCM credentials.  The only operator-visible
change is that push notifications now appear with NO banner
content until Phase D.2 ships the device-side
`helm.fetch_since` consumer; that's flagged as the cross-phase
breaking change in the D.1 PR description.

## What a device implementor needs to know (Phase D.2)

When the silent handler fires:

1. Decode the wake-only envelope from APNs/FCM.  Extract `event_id`
   and `ts`.
2. Open (or reuse) the WSS to the brain.
3. Call `helm.fetch_since` with `since_ts = <last-seen-ts from
   SecureStore>`.
4. For each returned event whose `kind` warrants a banner, build a
   local notification from the operator content and render it via
   the platform local-notification API.
5. Persist `next_cursor_ts` to SecureStore as the new last-seen-ts.

The brain does not gate or re-authenticate this fetch beyond the
existing bearer token; the WSS itself is bearer-authenticated at
upgrade time.

## What's out of scope of D.1

- Mobile silent-handler glue (Phase D.2).
- `lastSeenTimestamp` SecureStore persistence (Phase D.2).
- UnifiedPush adapter as a Google-free alternative on Android
  (Phase D.3).
- Settings UI for the operator to pick between FCM and UnifiedPush
  (Phase D.3).

See `docs/canon/deliverables.yml` entry D-O5m.followup-9 for
phase tracking.

## Mobile silent-push flow (D.2)

D.2 lands the device-side consumer of the wake-only envelope.  The
device now runs the loop the D.1 sequence diagram described:

1. **Receive wake.**  FirebaseMessaging fires `onMessage` (foreground)
   or the top-level `_backgroundHandler` (backgrounded / terminated).
   The wake envelope (`event_id`, `ts`, `kind`) is read off
   `RemoteMessage.data`; no operator content is present.
2. **Open the WSS to the brain.**  The handler reads the persisted
   `ChildCertRecord` from SecureStorage to recover the brain's
   `brainWssEndpoint` + bearer, then constructs an ephemeral
   `HelmEventStream` (the foreground HomeScreen owns its own
   long-lived stream; the wake handler always builds a throwaway).
3. **Call `helm.fetch_since`.**  The handler sends
   `{"method":"helm.fetch_since","params":{"since_ts":<lastSeen>,
   "limit":256}}` and awaits the brain's reply (10s timeout).
4. **Render local notifications.**  For each returned event whose
   `kind` warrants a banner (`lead.created`, `job.transitioned`,
   plus a generic banner for unknown kinds so the operator still
   gets a wake), `composeBanner` builds a (title, body, tap-payload)
   triple and `flutter_local_notifications` shows it.
5. **Update the last-seen cursor.**  The handler advances
   `LastSeenStore` to the higher of (max event ts, brain's
   `next_cursor_ts` echo) so the next wake doesn't re-fetch the
   same events.  Cursor is per-brain endpoint
   (`helm.lastSeenTs.<fnv-of-endpoint>`) so re-pairings to a
   different brain start clean.
6. **Failures are silent.**  Connection refused / fetch timeout /
   broker error on the brain do NOT render a "fetch failed"
   notification.  The operator never sees a transient WSS hiccup;
   the next foregrounding of the app re-establishes the live
   `HelmEventStream` which back-fills any missed events through
   the same `helm.fetch_since` call (the live stream's `connect`
   path can also call fetchSince to catch up).

### Tap routing

The local notification's payload carries `{screen, lead_id|job_id,
event_id, kind}` — `PushNotificationRouter.routeTap` consumes
exactly the same shape it consumed pre-D.2, so the existing
`/ratify` and `/job/<id>` deep links work unchanged.  No second
fetch is required at tap time; the payload is self-sufficient.

### In-foreground dedupe

When the app is foregrounded and the live `HelmEventStream` is
already pulling events via `helm.event` notifications, a wake
arriving for the same event would otherwise double-render.  The
silent handler dedupes via a process-shared `Set<String>` of
already-rendered event IDs (`LiveHelmEventDedupe`).  The set is
bounded to 1024 entries with a sliding-window eviction so a long-
running session doesn't grow unboundedly.  Background isolates
have their own memory and don't see this set — that's acceptable
because the live stream is only active in the main isolate (when
the app is foregrounded).

### Code map

| File                                                          | Role                                            |
|---------------------------------------------------------------|-------------------------------------------------|
| `lib/src/push/push_handlers.dart`                             | Flutter wiring: FirebaseMessaging callbacks    |
| `lib/src/push/silent_push_handler.dart`                       | Pure-Dart handler core + banner composer       |
| `lib/src/push/last_seen_store.dart`                           | SecureStorage-backed per-brain cursor          |
| `lib/src/repl/helm_event_stream.dart::fetchSince`             | WSS request/response client                    |
| `lib/src/push/push_notification_router.dart`                  | Tap → screen deep linking (unchanged from D.1) |

## Phase D.3: UnifiedPush

D.1 reduced every push payload to an opaque wake envelope.  D.2
shipped the device-side silent handler that turns each wake into a
WSS `helm.fetch_since` round-trip + a locally-rendered notification.
That closed the data-leak: Apple and Google can no longer see
operator content.

But the device still depends on Firebase (Android) or Apple's APNs
(iOS) for the wake mechanism itself.  Phase D.3 closes the Android
sovereignty gap by adding [UnifiedPush](https://unifiedpush.org/)
as a third backend.

### What UnifiedPush is

UnifiedPush (UP) is a libre push protocol.  The operator's device
picks a *distributor app* (ntfy, NextPush, Conversations, …); the
distributor mints a per-instance HTTPS endpoint URL; the brain POSTs
the wake envelope directly to that URL with no auth, no provider
wrapping, no key signing — the URL itself is the capability.

Because the operator chooses (and can self-host) the distributor,
the wake path can run entirely off Google.  Operators who run a
self-hosted ntfy alongside their brain reach a fully-sovereign push
loop: the brain wakes the device through their own infra,
fetch_since pulls the event content over WSS, and the device renders
the banner locally.

iOS operators stay on APNs.  The Apple sandbox prohibits alternative
wake mechanisms; UnifiedPush ships a paid-developer-account-only
shim for iOS that we intentionally don't depend on.

### Brain side (Zig)

`runtime/semantos-brain/src/identity_certs.zig` extends `PushPlatform` with a
fourth variant `unifiedpush` and the `CertRecord` with an
`up_endpoint` field that carries the distributor's URL.

`runtime/semantos-brain/src/push_register_http.zig` accepts
`platform=unifiedpush` in `POST /api/v1/push-register`; when the
platform is `unifiedpush` the `token` field is interpreted as the
endpoint URL and validated to start with `https://` (otherwise 400
`endpoint_invalid`).

`runtime/semantos-brain/src/unifiedpush_dispatcher.zig` is the dispatcher.
Mirrors the shape of `apns_dispatcher.zig` / `fcm_dispatcher.zig`
but is dramatically simpler:

- POST the wake envelope JSON directly to the cert's `up_endpoint`.
- Header: `Content-Type: application/json`.  No auth header, no
  signing.
- 2xx → ok.  410 Gone → clear the cert's `up_endpoint` (the
  distributor reports the endpoint is dead; mirrors APNs/FCM token
  expiry).  4xx → `unifiedpush_rejected`.  5xx → retry up to 3
  times then `transport_failed`.

`runtime/semantos-brain/src/push_dispatcher.zig` fans out by `cert.push_platform`
across `apns` / `fcm` / `unifiedpush`.  `cmdServe` always constructs
the UP dispatcher when push is enabled at all (it has no signing
material to gate on); APNs and FCM are still lazy-init'd from
`push-config.json`.

### Device side (Flutter)

`pubspec.yaml` pulls in `unifiedpush ^6.2.0`.  The `unifiedpush_android`
plugin auto-registers the
`org.unifiedpush.android.connector.PUSH_EVENT` service receiver via
its own merged manifest — no manual `AndroidManifest.xml` edits.

`lib/src/push/unified_push_adapter.dart` wraps the plugin behind the
existing `PushPlatformAdapter` interface used by the FCM adapter.
On `register()` it calls `UnifiedPush.register()` and waits (with a
30s timeout) for the distributor to deliver an endpoint via the
`onNewEndpoint` callback — that URL becomes the "device token" that
gets POSTed to `/api/v1/push-register`.  Push messages arrive
through the plugin's `onMessage` callback as raw bytes (the brain's
JSON envelope verbatim) which the adapter parses and forwards to
the silent-push handler from D.2.

`lib/src/push/push_registration_service.dart` adds a
`PushBackendPreference` enum (`unifiedpush` | `fcm`) plus an optional
`fallbackAdapter` constructor parameter.  On Android the default
preference for new installs is `unifiedpush` (sovereignty-first);
when the primary adapter returns no token (no distributor installed
yet) the service silently falls back to FCM and exposes
`lastUsedFallback` so the SettingsScreen can render an "install a
distributor" hint.

### Operator-facing UI

Settings → Notifications → "Push backend":

- iOS: read-only "Apple Push (APNs)" with a tooltip explaining the
  sandbox limitation.
- Android: dropdown {UnifiedPush (sovereign), Firebase Cloud
  Messaging}.  Selecting UnifiedPush surfaces the list of installed
  distributors with "Use" buttons that persist the operator's
  choice via `UnifiedPush.saveDistributor()`.
- "Apply" persists the preference, swaps the registration service's
  adapters, and re-runs `registerOnPair()` so the new backend lands
  on the brain immediately.

If no UP distributor is installed, the apply path falls back to FCM
and shows a hint suggesting the operator install one (see
<https://unifiedpush.org/users/distributors/> for the full list —
ntfy and NextPush are the most common).

### Switching an existing operator over

1. Install a UnifiedPush distributor (e.g. ntfy from F-Droid or
   Play; or self-host from <https://docs.ntfy.sh/install/>).
2. Open the helm → Settings → Notifications → Push backend.
3. Pick "UnifiedPush (sovereign)", pick the distributor, tap Apply.
4. The brain now POSTs every wake to the distributor's URL — no
   Firebase round-trip.

To return to FCM: pick "Firebase Cloud Messaging", tap Apply.

### Code map (D.3 additions)

| File                                                              | Role                                                  |
|-------------------------------------------------------------------|-------------------------------------------------------|
| `runtime/semantos-brain/src/unifiedpush_dispatcher.zig`                      | Brain → distributor HTTP POST                         |
| `runtime/semantos-brain/src/identity_certs.zig::PushPlatform/up_endpoint`    | Schema bump (4-variant enum + new field)              |
| `runtime/semantos-brain/src/push_register_http.zig`                          | `endpoint_invalid` validation                         |
| `runtime/semantos-brain/src/push_dispatcher.zig::dispatchTo`                 | Adds `unifiedpush` arm to the routing switch          |
| `apps/oddjobz-mobile/lib/src/push/unified_push_adapter.dart`      | Device-side adapter wrapping the `unifiedpush` plugin |
| `apps/oddjobz-mobile/lib/src/push/push_registration_service.dart` | Backend preference + prefer-UP-fallback-FCM logic     |
| `apps/oddjobz-mobile/lib/src/helm/settings_screen.dart`           | Operator-facing backend picker                        |
