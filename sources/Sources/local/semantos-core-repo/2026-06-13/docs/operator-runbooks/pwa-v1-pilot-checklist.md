---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/pwa-v1-pilot-checklist.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.639839+00:00
---

# PWA V1 Pilot Checklist — Odd Job Todd

**Status:** V1 acceptance gate per [`docs/REACTOR-PORT-TRACKER.md`](../REACTOR-PORT-TRACKER.md) "Definition of done — V1 — Odd Job Todd PWA pilot deployable".

**Audience:** the operator (Todd) executing the pilot smoke after the brain-side V1 reactor recovery (T0-T5 + T8a/T8b) and the APK build (per [`mobile-build-and-pair.md`](mobile-build-and-pair.md)).

**Purpose:** turn each of the five V1 endpoints into a concrete phone-side test. If every checkbox passes, V1 pilot is deployable.

---

## Pre-flight (no phone yet)

Before sideloading the APK, verify the brain's V1 surface is responsive. The script `scripts/pwa-v1-smoke.sh` exercises all five endpoints over HTTP/WSS:

```bash
# Against production:
BRAIN_URL=https://rbs.example.com \
    BEARER="$(ssh rbs cat /etc/semantos/bearer-tokens.log | head -1)" \
    ./scripts/pwa-v1-smoke.sh

# Against a local brain (after `brain serve --enable-repl`):
./scripts/pwa-v1-smoke.sh

# Without a bearer, expect 401 on bearer-gated endpoints — that's still
# proof the handler is wired:
./scripts/pwa-v1-smoke.sh
```

**Expected output:** all five endpoints report ✓ (handler running, 200/401/101 as appropriate). If any reports ✗, debug the brain side before continuing.

Common failure modes:
- 404 on `/api/v1/info` → T8a regression; check `cli/serve.zig` info_acceptor wiring (`6b7cb76`)
- 404 on `/api/v1/voice-extract` → T8b regression; check voice-extract acceptor wiring (`699e856`)
- 401 with valid bearer → token store empty or bearer-tokens.log out of date
- could-not-connect → brain not running, port wrong, tunnel broken

---

## Sideload + pair

Per [`mobile-build-and-pair.md`](mobile-build-and-pair.md):

- [ ] APK built at `apps/oddjobz-mobile/build/app/outputs/flutter-apk/app-debug.apk`
- [ ] Phone plugged in via USB with developer mode + USB debugging on
- [ ] `adb install -r apps/oddjobz-mobile/build/app/outputs/flutter-apk/app-debug.apk` succeeded
- [ ] Tunnel running (`cloudflared` or equivalent) — phone has a reachable URL for the brain
- [ ] Pairing QR displayed and scanned; phone shows "Paired with brain"
- [ ] Bearer token persisted on device (visible in phone secure storage logs if accessible)

---

## V1 Test 1 — `/api/v1/info` discovery

**V1 DoD:** *"PWA discovers brain config via `/api/v1/info`; no hardcoded URLs anywhere in `apps/oddjobz-mobile`."*

- [ ] PWA boots without showing a hardcoded brain URL anywhere
- [ ] On boot, the PWA fetches `/api/v1/info` and uses the returned `brain_pin_cert_id`, `pubkey_hex`, `shard_proxy` fields
- [ ] Hat switcher in the PWA shows the `available_hats` list from `/api/v1/info`
- [ ] Theme defaults applied from the `theme` field
- [ ] Server version visible in some "About" or settings panel matches `server_version`

**Verify on phone:**
```
1. Force-quit the app, clear cache, relaunch
2. Watch logs (adb logcat | grep -i 'info\|brain'):
   - Expect a single GET /api/v1/info round-trip on boot
   - Expect NO requests to a hardcoded fallback URL
3. Open hat switcher → list of hats matches /api/v1/info.available_hats
4. Open settings/about → server_version is shown
```

**Server-side verify:**
```bash
ssh rbs 'journalctl -u semantos-shell --since "5 min ago" | grep "GET /api/v1/info"'
# Should show one or two requests per phone launch.
```

---

## V1 Test 2 — Photo capture against a visit (not a job)

**V1 DoD:** *"Photo capture against jobs works end-to-end (PWA → brain → disk → retrieval)."*

> **Correction (2026-05-13 post-deploy):** capture is **visit-scoped**, not
> job-scoped. The "Capture photo" CTA renders on the **Visit detail
> screen** only when the visit FSM is in `in_progress` state (per
> `apps/oddjobz-mobile/lib/src/helm/visit_detail_screen.dart:329,
> 351-365`). Job detail itself only exposes job-level FSM increments
> (`lead → quoted → ...`). The earlier "Open a job → Add photo"
> instruction was wrong about the UI shape — the capability
> (`cap.attach.photo`) and the brain endpoint
> (`/api/v1/attachments/upload`) both work; the button just lives one
> level deeper in the navigation tree.

- [ ] Open the Jobs screen
- [ ] Tap a job that has at least one visit (or create one for it)
- [ ] Tap into the visit → Visit detail screen
- [ ] If visit is `scheduled`, tap "Start" → FSM transitions to `in_progress`
- [ ] Three CTAs now render on the visit detail (per `cap.attach.*` caps):
  - **Capture photo** (always rendered when `captureService` is wired)
  - **Drop GPS pin** (hidden when `geolocator` adapter null)
  - **Voice memo** (hidden when `voiceRecorderFactory` null)
- [ ] Tap "Capture photo" → phone camera opens; capture
- [ ] PWA shows upload-in-progress indicator
- [ ] Upload completes within ~5 seconds (network-dependent)
- [ ] Photo appears in the visit's attachments list
- [ ] Refresh / re-open visit → photo still there (persisted, not in-memory)
- [ ] Tap thumbnail → full-resolution photo loads via `/api/v1/attachments/<id>/blob`

**Server-side verify:**
```bash
# Upload + blob retrieval pair should appear in the journal:
ssh rbs 'journalctl -u semantos-shell --since "5 min ago" | grep -E "attachments/upload|attachments/.*/blob"'
# Check the attachment landed on disk:
ssh rbs 'ls -la /var/lib/semantos/attachments/ | tail'
```

**Failure modes:**
- 12 MB body cap (T1 hardcoded) — phone photo > 12 MB will reject; reduce camera quality on phone
- Signed-metadata mismatch — check that the PWA's device cert matches what brain stores

---

## V1 Test 3 — Live job-state updates (WSS)

**V1 DoD:** *"Live job-state updates appear in the PWA without polling."*

**Pre-condition:** `/api/v1/events` is either ported (T3 done) OR the PWA polls `/api/v1/repl` on a 5-second interval (per T3 deferral note in REACTOR-PORT-TRACKER D12).

### If T3 (WSS events) is shipped:

- [ ] PWA's job-list view is open and visible on phone
- [ ] From the brain side, trigger a state transition:
  ```bash
  ssh rbs 'echo "{\"method\":\"job.transition\",\"params\":{\"job_id\":\"smoke-job-T3\",\"from\":\"lead\",\"to\":\"quoted\"}}" | brain repl-client'
  ```
- [ ] Phone PWA receives the transition WITHIN 1 SECOND — job's status indicator updates without manual refresh
- [ ] PWA log shows incoming WS frame with `event_id`, `job_id`, `from_state`, `to_state`

### If T3 is deferred (polling fallback):

- [ ] PWA polls `/api/v1/repl` every 5 seconds (visible in logs)
- [ ] State change becomes visible on phone within 5–10 seconds (one poll interval + render)
- [ ] Acceptable for V1 pilot; T3 port lands later (see REACTOR-PORT-TRACKER)

**Server-side verify:**
```bash
ssh rbs 'journalctl -u semantos-shell --since "1 min ago" | grep -E "events|fsm_transition"'
```

---

## V1 Test 4 — Voice notes feeding the quoting flow

**V1 DoD:** *"Voice notes against jobs produce intent records that feed the quoting flow."*

- [ ] Open a job in the PWA; tap the "Voice note" button
- [ ] Phone microphone activates; speak a quote estimate, e.g. "Quote estimate: $850 for materials, $400 for labour, half day"
- [ ] PWA shows transcribing indicator
- [ ] Within ~3 seconds, transcript appears under the job
- [ ] Quote draft fields populate from the extracted intent (materials $850, labour $400, est. 4hr)
- [ ] User confirms the quote draft → quote saved
- [ ] Refresh job → quote draft persisted

**Server-side verify:**
```bash
ssh rbs 'journalctl -u semantos-shell --since "5 min ago" | grep voice-extract'
# Should show: POST /api/v1/voice-extract → 200 with the parsed intent payload
```

**Path A vs Path B (per REACTOR-PORT-TRACKER D5):**
- This tests **Path A** — capture-time-bound: tap voice-note inside a job view → audio tagged with `scope: job/<id>` in signed Transcript metadata → brain ratifies on that job.
- Path B (free-form `talk | self`) is **not** in V1 pilot; landing later.

---

## V1 Test 5 — No orphaned dead-code HTTP endpoints

**V1 DoD:** *"No orphaned dead-code HTTP endpoints in `runtime/semantos-brain/src/` that aren't reachable from `reactor.zig`."*

This is a code-level check, not a phone test. Verified by T5 of REACTOR-PORT-TRACKER (commit `c931c8c` deleted request.zig + connection.zig + auth.zig + dispatch.zig + static.zig + 5 delegate methods).

- [ ] `grep -rn "fn handle" runtime/semantos-brain/src/site_server/reactor.zig` shows the dispatch slots T0–T5+T8 wired
- [ ] No HTTP handler function exists in `runtime/semantos-brain/src/` that isn't reachable from `reactor.zig` via the dispatch table
- [ ] `zig build test -j1 --summary all` is green (verified by CI gate.yml)

---

## V1 Test 6 — Test suite green

**V1 DoD:** *"`zig build test -j1 --summary all` is green."*

```bash
cd runtime/semantos-brain
zig build test -j1 --summary all
```

- [ ] All tests pass (last verified count from T8b commit: 1519/1563 passing, no regressions)
- [ ] Cell-engine fuzz harnesses compile (`zig build fuzz-linearity fuzz-opcodes fuzz-stack fuzz-plexus`)
- [ ] Lean proofs build (`cd proofs/lean && lake build Semantos`)
- [ ] TLA+ model-checks pass (`cd proofs/tla && make check`)

---

## V1 acceptance — what success looks like

When every box above is checked:

✅ The PWA boots without hardcoded URLs (discovers via `/api/v1/info`)
✅ Photos upload + retrieve end-to-end
✅ Live state updates reach the phone (WSS or 5s polling)
✅ Voice notes turn into quote drafts
✅ No dead code in the HTTP surface
✅ All tests green

**Sign-off:** mark this checklist with the commit SHA of the brain binary used (`ssh rbs 'systemctl status semantos-shell | grep ActiveState'` shows current binary; combine with `/opt/semantos/brain.pre-*` backups to identify version).

---

## V2 gate (Oddjobz tenant sales)

Not part of V1. Tracked separately:

- [ ] T6 push-register port (`/api/v1/push-register`) — APNs/FCM token registration; synthetic push to test device succeeds
- [ ] Multi-tradie deployment per [`multi-tenant-deployment.md`](multi-tenant-deployment.md)
- [ ] Settlement integration (per refactor Prompt 44)

V1 acceptance does NOT block on V2 work.

---

## Rollback

If any V1 test fails on production, the rollback path is documented in `docs/SESSION-JOURNAL-2026-05-13.md`:

```bash
# List backup binaries on rbs:
ssh rbs 'ls -la /opt/semantos/brain.pre-*'

# Roll back to the pre-T8a binary (V1 ports but no info_acceptor wiring):
ssh rbs 'install /opt/semantos/brain.pre-t8a-2026-05-13-0833 /opt/semantos/brain && systemctl restart semantos-shell'

# Verify endpoint state:
ssh rbs 'curl -sw "%{http_code}\\n" http://localhost:8080/api/v1/info -o /dev/null'
```

Five backup binaries on rbs from today's deploys; roll back to whichever layer was last known-good.

---

## References

- [`docs/REACTOR-PORT-TRACKER.md`](../REACTOR-PORT-TRACKER.md) — V1 task matrix
- [`docs/SESSION-JOURNAL-2026-05-13.md`](../SESSION-JOURNAL-2026-05-13.md) — A+B deploy record
- [`docs/operator-runbooks/mobile-build-and-pair.md`](mobile-build-and-pair.md) — APK build + pair flow
- [`scripts/pwa-v1-smoke.sh`](../../scripts/pwa-v1-smoke.sh) — automated pre-flight
- Memory `brain_reactor_v1_recovery_complete.md` — V1 reactor recovery summary
