---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/operator-runbooks/mobile-build-and-pair.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.637462+00:00
---

# Mobile build + pair (Android phone smoke test)

D-OPS.mobile-smoke-test — end-to-end walkthrough for plugging an
Android phone into the operator's Semantos Brain and exercising the full
voice → cell → outbox loop.  Pre-requisite for shipping any further
Phase O5m work; the runbook closes the gap between "419 dart tests
pass" and "the phone is in your hand showing the new job in real
time".

This runbook is **macOS-first** because that's the dev environment
the substrate ships against today.  Linux notes are inline where they
diverge; Windows needs a separate followup runbook.

> **Out of scope**: push notifications.  The Firebase wiring from
> D-O5m.followup-9 (#328) is a graceful placeholder — `Firebase
> .initializeApp()` is wrapped in try/catch so the app continues even
> when google-services.json is absent.  The sovereign push refactor
> (D-O5m.followup-9 Phase D) ships in a separate PR and removes the
> Firebase placeholder entirely.  Until then, every smoke-test
> scenario in §B11 below works without push — pull-to-refresh + the
> WSS live-tick stream cover the data flow this runbook validates.

## Sections

- B1. Prerequisites
- B2. One-time phone setup
- B3. Build the Semantos Brain
- B4. Build the native libs
- B5. Configure HTTPS for LAN testing
- B6. Start brain
- B7. Build + install the APK
- B8. Launch app + verify pair screen
- B9. Generate a pair token (LAST — 5-min TTL)
- B10. Pair the phone
- B11. Smoke test scenarios (REPL → live → voice)
- B12. Troubleshooting

> **Pacing — pair tokens expire in 5 minutes.**  Mint the pair
> token LAST, just before scanning it from the phone.  The first
> `flutter build apk --debug` takes 10+ min on a fresh checkout (SDK
> + NDK download), which is longer than the token TTL — so build the
> APK first, install it, launch it, verify the Pair screen is up,
> THEN run `brain device pair`.  Smoke-test pass #1 fix #15.

---

## B1. Prerequisites

| Tool | Version | Verify | Install (macOS) |
|------|---------|--------|-----------------|
| Flutter SDK | ≥ 3.41 | `flutter --version` | https://docs.flutter.dev/get-started/install/macos |
| Android Studio OR platform-tools | any | `adb --version` | `brew install --cask android-platform-tools` |
| Zig | 0.15.2 | `zig version` | `brew install zig` |
| Bun | latest | `bun --version` | `brew install oven-sh/bun/bun` |
| HTTPS tunnel | — | `cloudflared --version` | `brew install cloudflared` |
| QR helper (optional) | — | `qrencode --version` | `brew install qrencode` |

Why HTTPS specifically?  The `brain-device-pair-v2` token format
hardcodes `https://` on the brain pair endpoint and `wss://` on the
wallet endpoint — the device-pair handshake fails closed if either
URL has the wrong scheme.  This is a deliberate posture (the device
sends a BRC-42 child cert over the wire; cleartext would leak it).
For LAN dev work we punt on the cert by tunnelling localhost through
a third-party TLS termination layer (cloudflared) or installing a
local mkcert root cert on the phone.  See §B5 for both options.

Linux notes:
- `apt install android-tools-adb zig bun cloudflared qrencode`
- Flutter SDK install steps differ — see the upstream docs.

## B2. One-time phone setup

1. **Enable Developer options**: Settings → About phone → tap "Build
   number" 7 times.  A toast confirms "You are now a developer".
2. **Enable USB debugging**: Settings → System → Developer options →
   USB debugging.
3. Connect the phone over USB.  Accept the "Allow USB debugging?"
   dialog on the phone (tick "Always allow from this computer").
4. From the dev machine:
   ```bash
   adb devices
   ```
   The phone serial should appear with state `device` (not
   `unauthorized`).  If you see `unauthorized`, re-tap the dialog on
   the phone; if you see no device, try a different cable (some USB-A
   cables are charge-only and don't carry data lines).
5. Run `flutter doctor` on the dev machine.  Fix any "X" lines —
   "Android toolchain" and "Connected device" should both be green.
   Web, Linux desktop, Chrome — leave as-is, irrelevant.

## B3. Build the Semantos Brain

```bash
cd runtime/semantos-brain
zig build
```

The brain binary lands at `runtime/semantos-brain/zig-out/bin/brain`.  No NDK
toolchain needed; this is the host-arch build of the substrate.
First-time builds take ~3 min; incremental rebuilds are sub-second.

## B4. Build the native libs

```bash
./scripts/build-android-libs.sh
```

This produces `libsemantos.a` for the three Android ABIs the host
app's `abiFilters` declare:
- `arm64-v8a` — every modern Android phone (2018+)
- `armeabi-v7a` — legacy phones (Android < 8 era)
- `x86_64` — Android Studio emulator

Output paths (consumed by `platforms/flutter/semantos_ffi/android/
CMakeLists.txt`):

```
platforms/flutter/semantos_ffi/build/android/arm64-v8a/libsemantos.a
platforms/flutter/semantos_ffi/build/android/armeabi-v7a/libsemantos.a
platforms/flutter/semantos_ffi/build/android/x86_64/libsemantos.a
```

The script also writes a `CHANGES.txt` marker next to the libs so the
optional smoke-test script (§C, see `scripts/smoke-test-mobile.sh`)
can detect a fresh build.

Single-ABI rebuild (faster iteration when only the phone arch matters):

```bash
./scripts/build-android-libs.sh --abi arm64-v8a
```

Clean removed staged libs + Zig cache:

```bash
./scripts/build-android-libs.sh --clean
```

> **Why the FFI builds with `single_threaded = true` + `stack_check =
> false` on Android**: Zig's default native build emits
> `__tls_get_addr` and `__zig_probe_stack` references that the
> Android NDK linker won't resolve when wrapping the static archive
> in a SHARED `.so`.  `src/ffi/build.zig` detects an Android target
> and applies both flags automatically.  See the inline comment block
> on `static_mod` for the full rationale.  The kernel exports
> (`semantos_init`, `semantos_execute_script`, etc.) are byte-
> identical between the host build and the Android build.

## B5. Configure HTTPS for LAN testing

Three options, in order of recommended-for-dev:

1. **ngrok** — most reliable for sessions > 30 minutes (smoke-test
   pass #1, fix #14 added this; the previous default — cloudflared
   quick tunnels — exhibited zombie failures during the first end-to-
   end smoke test).
2. **cloudflared** — still useful for short demos but watch for
   zombies (alive process, dead tunnel, silent failure).
3. **mkcert + Android trust import** — fully offline, no third party.

### Option 1 (recommended for dev) — ngrok

```bash
brew install ngrok
ngrok config add-authtoken <your-token-from-ngrok.com>   # one-time
ngrok http 8080
```

ngrok prints something like:

```
Forwarding   https://1a2b-203-0-113-7.ngrok-free.app -> http://localhost:8080
```

Copy that `https://...ngrok-free.app` URL — it's the value you'll
feed to `brain device pair`'s `--brain-pair-endpoint` flag in §B9.

Why ngrok over cloudflared for dev: in the first end-to-end smoke
test (2026-05-02) we hit cloudflared zombies twice.  The cloudflared
process kept printing `[INFO] Connection registered` heartbeats while
HTTP requests through the tunnel just hung — no error log on either
end.  ngrok surfaces tunnel death as a 502 within seconds.

### Option 2 — cloudflared tunnel (quick)

```bash
cloudflared tunnel --url http://localhost:8080
```

cloudflared prints a line like:

```
Your quick Tunnel has been created! Visit it at:
https://feline-recon-pasta-galaxy.trycloudflare.com
```

Copy that URL; it's the value you'll feed to `brain device pair`'s
`--brain-pair-endpoint` flag in §B9.  Keep the cloudflared process
running in a separate terminal for the duration of the smoke test.

> **WARNING — cloudflared zombie tolerance**
>
> Quick tunnels (`cloudflared tunnel --url ...`) regularly stop
> forwarding HTTP after ~30 min of idle while the process keeps
> happily logging heartbeats.  Symptom: `curl https://<url>/...`
> hangs or returns `502 Bad Gateway` while `cloudflared` shows no
> errors.  Recovery: kill the cloudflared process and restart it.
> A new quick-tunnel URL is minted each time; you'll need to re-mint
> the pair token (§B9) because the brain endpoint URL has changed.
>
> For production stability use a NAMED cloudflared tunnel
> (`cloudflared tunnel create <name>`) backed by a configured route —
> see `docs/operator-runbooks/multi-tenant-deployment.md`.

The tunnel terminates TLS at Cloudflare's edge and proxies HTTP to
your local Semantos Brain.  Trade-off: every request transits Cloudflare's
network (fine for dev, NOT what you'd run in prod — see
`docs/operator-runbooks/multi-tenant-deployment.md` for the prod TLS
posture).

### Option 3 — mkcert + Android trust import (offline)

```bash
mkcert -install
mkcert your-dev-host.local
```

That produces `your-dev-host.local.pem` and `your-dev-host.local-key
.pem`.  Wire them into brain by adding the cert+key paths to your
`config.json` (see `docs/operator-runbooks/multi-tenant-deployment
.md` §TLS).

Push the mkcert root cert to the phone:

```bash
adb push "$(mkcert -CAROOT)/rootCA.pem" /sdcard/Download/
```

On the phone: Settings → Security → Encryption & credentials →
Install a certificate → CA certificate → pick `rootCA.pem` from
Downloads.  After install, the phone trusts any cert mkcert mints.

Use `https://your-dev-host.local:<port>` as the
`--brain-pair-endpoint` value.  The phone must be on the same LAN
and DNS for `your-dev-host.local` must resolve from the phone (mDNS
works on most home networks; otherwise add a Private DNS entry).

## B6. Start brain

```bash
cd runtime/semantos-brain

# First time only — initialise local config + tenant identity.
./zig-out/bin/brain init

# Then start serving.  Pick a domain; the helm SPA routes resolve
# against this string.  For LAN dev, "localhost" is fine.
./zig-out/bin/brain serve localhost --port 8080 --enable-repl
```

Flags:
- `--enable-repl` mounts the bearer-gated `POST /api/v1/repl`
  endpoint the phone helm uses for `find jobs`, `add job`, etc.
- `--port 8080` matches the cloudflared tunnel port from §B5.
- For multi-tenant production runs use `--tenant-manifest <path>`
  instead — see `docs/operator-runbooks/multi-tenant-deployment.md`.

You should see lines like:

```
[brain] http listening on 127.0.0.1:8080
[repl] enabled
[wss] /api/v1/wallet
```

Leave brain running.  Open a third terminal for §B7+.

## B7. Build + install the APK

> **Why this is before the pair token**: pair tokens expire in
> 5 minutes (smoke-test pass #1 fix #15).  The first APK build on a
> fresh checkout takes 10+ min because Flutter downloads the Android
> SDK + NDK + CMake.  Build + install + launch FIRST, verify the
> Pair screen is up, THEN mint the token.

```bash
cd apps/oddjobz-mobile
flutter build apk --debug
adb install build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n info.oddjobtodd.oddjobz_mobile/.MainActivity
```

Or for live debugging with hot reload + console attached:

```bash
flutter run -d $(adb devices | awk 'NR==2 {print $1}')
```

The first APK build downloads ~600 MB of Android SDK + NDK + CMake
artifacts to `~/Library/Android/sdk/`.  Subsequent builds are
~30 seconds.  If you see "License for package X not accepted" run
`yes | flutter doctor --android-licenses` once.

## B8. Launch app + verify pair screen

The app should launch directly into the **Pair device** screen
(because no paired identity exists yet).  Confirm:

- The screen shows a "Scan QR" button + a "Paste token" input.
- The wire-format banner at the bottom reads
  `Wire format: semantos-pair (vN)`.

If the app crashes on launch — check `adb logcat | grep -E
"(oddjobz|FATAL|AndroidRuntime)"` for the actual error.  Common
fresh-install issues: missing arch slice in `libsemantos.a`
(re-run §B4 with the correct ABI), missing Firebase placeholder
(safe to ignore — push degrades gracefully).

Once the pair screen is visibly up, move to §B9.

## B9. Generate a pair token (mint LAST — 5-min TTL)

Replace the tunnel URL with whatever §B5 printed:

```bash
cd runtime/semantos-brain
./zig-out/bin/brain device pair \
    --device-name "My Test Phone" \
    --caps minimal \
    --brain-pair-endpoint https://1a2b-203-0-113-7.ngrok-free.app/api/v1/device-pair \
    --brain-wss-endpoint  wss://1a2b-203-0-113-7.ngrok-free.app/api/v1/wallet \
    --qr ascii
```

The command:
1. Mints a 5-minute one-shot pairing payload signed by the operator
   root priv (lives at `<data_dir>/operator-root-priv.hex`).
2. Allocates a fresh BRC-42 context tag.
3. Renders the resulting `semantos-pair://...?token=<base64url>` URL
   as both plain text AND an ASCII QR (good enough to scan from a
   phone camera held up to your terminal).

The token expires in 5 minutes — scan it on the phone IMMEDIATELY
after this command returns.  If it expires, re-run the command;
each call allocates a fresh nonce + context tag.

`--caps minimal` mints a cap allowlist of just `cap.oddjobz.read_jobs`
+ `cap.oddjobz.transition_job` — the smallest set the smoke-test
flow needs.  `--caps full` mints every cap; `--caps cap.X,cap.Y`
mints exactly those.

## B10. Pair the phone

1. On the Pair device screen still open from §B8, tap "Scan QR" if
   your terminal QR is readable; or tap "Paste token" and paste
   either the bare `<base64url>` token OR the full
   `semantos-pair://...?token=<base64url>` URL the Semantos Brain CLI printed.
   Both forms are accepted (smoke-test pass #1 fix #16).
2. Confirm pairing.  The app:
   - Decodes the token, derives the BRC-42 child priv inside the
     platform secure store (Keychain on iOS / EncryptedSharedPrefs
     on Android — see `docs/operator-runbooks/secure-signing-key
     -migration.md`).
   - POSTs to `<brain-pair-endpoint>` with the child pubkey + a
     proof-of-possession.
   - Persists the returned child cert + bearer token.
3. The app lands on the **Home → Jobs** tab.  The list is empty
   because the tenant has no jobs yet.

If the dialog says "pair_token_expired" — re-run §B9; tokens have a
hard 5-minute TTL.  If the dialog says
"brain_pair_endpoint_unreachable" — verify the tunnel from §B5 is
still up and `curl -I <brain-pair-endpoint>` returns a 405 (the
pair endpoint refuses GET; that's the expected liveness signal).
If `curl` hangs, the tunnel is a zombie — see §B5's cloudflared
warning and restart it.

## B11. Smoke test scenarios

Run all three IN ORDER.  Each builds on the previous one's data.

### Test 1 — REPL data flow (one-shot pull)

Goal: prove the phone can fetch tenant data the operator created via
the dev-machine REPL.

1. On the dev machine (terminal 4):
   ```bash
   cd runtime/semantos-brain
   ./zig-out/bin/brain repl
   ```
2. At the `brain>` prompt:
   ```
   add job --customer "Acme Corp" --kind lead --due 2026-05-15
   ```
3. The REPL prints the new job's id.
4. On the phone: pull-to-refresh on the Jobs tab.
5. **Expected**: the new job appears in the list within ~1 second.

If nothing shows up — the phone is not hitting the brain.  Check
`adb logcat | grep oddjobz` for the actual error from the
`jobs_repository.dart` HTTP call.

### Test 2 — Live updates via WSS

Goal: prove the WSS stream pushes new jobs without the user
manually refreshing.

1. Phone is on the Jobs tab; do NOT background the app.
2. On the dev-machine REPL:
   ```
   add job --customer "Beta Industries" --kind lead --due 2026-05-16
   ```
3. **Expected**: the phone's Jobs list updates within ~2 seconds
   without any user input.

If the list doesn't update — check `adb logcat | grep wss_client`.
Common causes: cloudflared tunnel terminates idle WSS connections
after ~100s (re-pair if so); the brain's `--enable-repl` flag was
omitted (helm WSS depends on the same dispatcher mount).

### Test 3 — Voice command end-to-end

Goal: prove the phone can drive the voice → STT → SIR → 2-PDA →
signed-cell → outbox loop end-to-end.

> **Heads-up: model downloads**.  First time you tap "Voice command"
> the app downloads:
>   * **whisper.base.en** (~150 MB) for on-device STT.  WiFi
>     recommended; downloading on cellular will be slow.
>   * **llama 3B Q4** (~2 GB) for the L1 SIR layer.  WiFi REQUIRED;
>     budget ~5-10 minutes the first time.  Models cache to
>     `Android/data/info.oddjobtodd.oddjobz_mobile/files/` and only
>     download once.
>
> If you abort during a download the app retries on next tap; if it
> hangs (no progress for 30s+) clear the cache directory + restart
> the app.

1. On the phone: tap a Visit row in the Jobs tab, then tap "Voice
   command" on the Visit detail screen.
2. Wait for the model download (one-time) — progress bar with ETA.
3. Speak: **"Done the hot water system, two hours, parts needed for
   invoice"**
4. The app:
   - Streams audio → whisper STT → text "done the hot water…"
   - Runs L1 SIR (llama 3B) → L1 → L2 → L3 IR
   - 2-PDA executor materialises a signed cell
   - Cell enqueues to the outbox; on-device flush attempts to push
     it to the brain immediately
5. **Expected on phone**: "Job → invoiced" outcome card with the
   parsed parts list + 2-hour duration.
6. **Expected on dev machine REPL**:
   ```
   brain> find jobs
   ```
   The job state should be `invoiced` with a reference to the cell
   the phone just produced.
7. Verify the cell's operator cert is the phone's child cert (not
   the root):
   ```
   brain> find attachments --visit-id <visit-id>
   ```
   The cell's `signed_by_cert` should match the child cert the phone
   persisted in §B10, not the operator root.

If the cell rejects with a K-violation (K1 / K2 / K3 / K4):
- Check the helm transcript view (post-#335; `cd apps/loom-svelte
  && bun dev` then visit `/transcripts/repl`).  Brain-side rejection
  details land here.
- The most common cause is a stale outbox cell from an earlier test
  — the phone's "Outbox" tab in Settings shows queued cells; you can
  drop them.

## B12. Troubleshooting

### App crashes immediately after launch

Almost always missing `libsemantos.so`.  Verify with:

```bash
adb logcat | grep -E "oddjobz|libsemantos|UnsatisfiedLinkError"
```

Re-run `./scripts/build-android-libs.sh` then `flutter build apk
--debug` then re-install.

### `flutter build apk --debug` fails at kernel_snapshot with record_linux

Pre-existing pub.dev resolver bug — `record 5.x` declares loose
bounds on `record_linux` 0.7.x but the platform interface 1.5.0 API
broke compatibility.  Fixed by the `dependency_overrides:
record_linux: ^1.0.0` block in `apps/oddjobz-mobile/pubspec.yaml`.
If you bump `record` and the override no longer resolves, drop the
override and re-run `flutter pub get`.

### `flutter build apk --debug` fails at checkAarMetadata for desugaring

The `flutter_local_notifications` plugin (D-O5m.followup-9 Phase C)
requires Java 8 core library desugaring.  The
`isCoreLibraryDesugaringEnabled = true` block in
`apps/oddjobz-mobile/android/app/build.gradle.kts` enables it.  If
you're on a different `desugar_jdk_libs` version, bump the version
in the `coreLibraryDesugaring` dependency line to match.

### `flutter build apk --debug` fails with "META-INF/versions/9/OSGI-INF/MANIFEST.MF" duplicate

bouncycastle and jspecify both ship the same metadata file.  The
`packaging.resources.pickFirsts` block in `apps/oddjobz-mobile/
android/app/build.gradle.kts` resolves it.  If a new transitive dep
brings yet another duplicate, add its path to the same `pickFirsts`
list.

### Native lib link error: `__tls_get_addr` or `__zig_probe_stack`

The Android `single_threaded` + `stack_check = false` flags in `src/
ffi/build.zig` should prevent both.  If you bump Zig and these come
back, double-check the `target_is_android` branch in `static_mod`
still triggers (Zig's `target.result.abi.isAndroid()` API is the
stable check).

### App pairs but jobs never appear (no error toast)

The brain endpoint URL the pair token captured doesn't match the
URL you're hitting now.  Cloudflared tunnel URLs are random per run;
if you restarted cloudflared between §B5 and §B9, the token has a
stale URL baked in.  Re-run §B9 with the current tunnel URL and re-
pair from a fresh "Pair device" screen (Settings → Unpair, then
restart the pair flow).

### Voice command fails with "K1: replay protection" or "K3: hat_mismatch"

The phone is talking to the wrong tenant or the outbox has a stale
cell.  Drop the outbox queue from Settings → Outbox → Clear, then
re-do §B11 Test 3.  If it persists, check the helm REPL transcript
view (#335) for the brain-side rejection JSON.

### Voice command model downloads hang

App-local cache lives at:
```
Android/data/info.oddjobtodd.oddjobz_mobile/files/models/
```
(only readable via `adb shell run-as info.oddjobtodd.oddjobz_mobile`
on rooted devices, or `adb pull` after the app's `getFilesDir()`
returns it).  Easiest fix: uninstall + reinstall the APK to wipe app
data, then retry on a faster network.

### Push notifications don't fire when the app is backgrounded

**Expected** — push is intentionally OUT OF SCOPE for D-OPS.mobile-
smoke-test.  The Firebase placeholder (D-O5m.followup-9 Phase C) is
the only push transport today; without a real `google-services.json`
it never delivers messages.  The sovereign-push refactor (D-O5m.
followup-9 Phase D) will swap Firebase for a wake-only WSS pattern;
until then, the app must be foregrounded for the live-tick stream
to deliver updates.

---

## Optional: one-shot smoke-test script

`scripts/smoke-test-mobile.sh` automates §B3-B7 + half of §B10 in
order, then waits for you to scan the QR + complete pairing on the
phone.  See the script's `--help` for current usage.

> Note: the script may still mint the pair token before the APK
> install finishes — the §B7-B10 reorder above (smoke-test pass #1
> fix #15) is in the human runbook; the smoke-test script is being
> updated separately.  If you use the script and the token expires,
> re-run §B9 manually.

## Known time costs

- First-time `flutter build apk --debug` (with NDK + SDK download):
  ~10 minutes
- Repeat `flutter build apk --debug` (everything cached): ~30 sec
- Whisper model first download: ~30 sec on WiFi
- Llama 3B Q4 first download: ~5-10 min on WiFi
- Pair flow end-to-end: ~10 sec
- Voice command (after models cached): ~2 sec STT + 3 sec SIR + ~1
  sec PDA → outbox + ~500 ms outbox flush

If anything in this list doubles unexpectedly, check the §B12
troubleshooting matrix.
