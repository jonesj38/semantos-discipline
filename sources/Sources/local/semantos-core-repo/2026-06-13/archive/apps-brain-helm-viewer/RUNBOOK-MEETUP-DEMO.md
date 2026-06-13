---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-brain-helm-viewer/RUNBOOK-MEETUP-DEMO.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.692124+00:00
---

# Meetup demo runbook — typed-NL on-device intent-cell pipeline

**Goal**: type a command on the phone (audience can't see it) → audience
watches the laptop where a card lands on the right panel and a job's
state pill flips on the left, all driven by **on-device llama, kernel-
verified locally, BSV-signed, no API keys**.

**Status of the pieces** (all landed on `main`):

- **#427** — LlamaService runs on a background isolate (UI doesn't freeze
  during the 5–30s 3B inference).
- **#428** — Mobile typed-NL pipeline: SIR extractor → kernel verify →
  cell envelope → outbox `oddjobz.intent_cell.v1`.
- **#429** — brain-side intake handler: validates the envelope, re-runs
  the kernel as defense-in-depth, persists JSONL row, publishes
  `intent_cell.created` to the broker.
- **#430-#433** — Brain-helm-viewer: live read-only laptop view at
  `https://brain.oddjobtodd.info/helm-viewer/` (same-origin → no CORS).
  Pulls 146 real jobs via `find jobs`, subscribes to the broker WSS
  stream, renders incoming intent cells live.
- **#435 (Tier 3)** — `intent_cell.created` → `jobs.transition` router
  on brain.  Gated behind `--enable-intent-action-router` (or env var
  `BRAIN_INTENT_ROUTER=1`).  When the daemon is restarted with the
  flag, the matching job actually moves state on the brain — the
  viewer's left panel auto-repaints from the `jobs.*` broker event.

  **Action mapping** (what shipped vs what was briefed — agent
  caught a Job FSM mismatch):

  ```
  "quote"    → "quoted"      ✓
  "schedule" → "scheduled"   ✓
  "invoice"  → "invoiced"    ✓
  "close"    → "closed"      ✓
  "accept"   → DROPPED       — `open` is not a state in the canonical
                               Job FSM (states: lead | quoted |
                               scheduled | in_progress | completed |
                               invoiced | paid | closed).
  ```

  **Eligible from-states**: `lead` ONLY.  Already-quoted/scheduled/
  etc. jobs are skipped (no regressions).  Pick a `LEAD` job in the
  viewer for the demo.

  **Latency**: transition fires on the next reactor tick (~100ms
  after the broker emits `intent_cell.created`).  Was a deadlock —
  agent resolved with queue+drain hooked into the existing reactor
  tick seam.

## At-the-venue setup (~15 min)

### 1. Confirm both halves are deployed

```sh
# Verify mobile build is up to date (should embed #428).
cd apps/oddjobz-mobile
git log --oneline -5
# Expect to see: feat(mobile): on-device L1→L4 typed-NL pipeline production wiring (#428)

# Pull latest on rbs.  This grabs #429 and #434 (the router).
ssh rbs '
  cd /opt/semantos-core
  sudo -u semantos git pull --ff-only
  # Build the Semantos Brain binary (Zig 0.15.2 on rbs).
  cd runtime/semantos-brain
  sudo -u semantos zig build -Doptimize=ReleaseFast -Dtarget=x86_64-linux-gnu -Dcpu=x86_64
'
```

### 2. Restart the Semantos Brain daemon with the router enabled

```sh
# Stop both brain services so the binary swap doesn't trip "Text file busy"
ssh rbs 'sudo systemctl stop semantos-shell semantos-headers'
ssh rbs 'sudo cp /opt/semantos-core/runtime/semantos-brain/zig-out/bin/brain /opt/semantos/brain'
ssh rbs 'sudo chmod +x /opt/semantos/brain'

# Patch the systemd unit override to add --enable-intent-action-router
ssh rbs '
  sudo tee /etc/systemd/system/semantos-shell.service.d/exec.conf > /dev/null <<EOF
[Service]
ExecStart=
ExecStart=/opt/semantos/brain serve \${BRAIN_DOMAIN} --enable-repl --enable-intent-action-router
EOF
  sudo systemctl daemon-reload
  sudo systemctl start semantos-headers
  sudo systemctl start semantos-shell
  sleep 2
  sudo systemctl status semantos-shell --no-pager -n 20
'
```

Look for the `--enable-intent-action-router` flag in the running command
line.  Confirm `Active: active (running)`.

### 3. Rebuild + reinstall the phone APK

```sh
cd apps/oddjobz-mobile
flutter build apk --release
flutter install -d RF8R11T6VDE
```

### 4. Open the viewer on the laptop

```
https://brain.oddjobtodd.info/helm-viewer/
```

Paste the bearer (`c1e3411c6d86c282a2992f7e5f4734f92f44403de3ade4c3323407f159973c0b`).
Status pill turns green ("subscribed").  146 jobs populate the left.

### 5. Pick a target job + smoke-test ONCE before the meetup starts

Click a `lead`-state job in the left panel — say the **Reminder to submit
a quote for roof repair work at 15 Wattle St, Tewantin** (`e77fc81…`).

Pick a distinctive substring of its summary.  Let's use **"wattle"**.

On phone, tap into the Talk node and type:

```
quote $500 for the roof at wattle street
```

Hit Send.  Watch:

- Phone: spinner ~5–30 seconds (llama inference + kernel verify).
- Phone: green "Cell xxx signed" check.
- Laptop right panel: card slides in with `quote`, your summary,
  kernel ✓, llama 3.2 3B, on-device ✓, no API keys ✓.
- **(Tier 3 magic)** Laptop left panel: the Wattle St job's state pill
  flips from `LEAD` → `QUOTED`.  The centre detail card updates too.

If the right panel updates but the left doesn't — the router didn't
fire.  Check `ssh rbs 'sudo journalctl -u semantos-shell -n 30'` for
`[intent_action_router]` lines.  Most likely cause: token-match was
ambiguous (multiple jobs contained "wattle" or "roof").  Try a more
distinctive token; or the job's current state isn't `lead`/`open`.

## Demo arc at the meetup

1. **Set the stage** — laptop's projector shows the viewer with 146
   real jobs from your gmail-ingested data.  Click the Wattle St
   roof repair to anchor.

2. **Hit the punchline** — *"This is my brain, running on a $5/month
   VPS.  Paired phone in my pocket, audience can't see it.  Watch
   what happens when I type a command…"*

3. **Type on phone** — `quote $500 for the roof at wattle street`.
   Hold for ~10–30 seconds while llama runs.

4. **Audience sees**:
   - Card slides in on the right with `action: quote`, your full
     summary, kernel ✓, llama 3.2 3B, on-device ✓, no API keys ✓.
   - Left state pill flips from `LEAD` to `QUOTED` with a glow.
   - Centre detail card updates.

5. **Land it** — *"That command was extracted by a 3B-parameter Llama
   running on a phone in offline mode.  The kernel that verified it
   is the same Zig 2-PDA the brain runs — defense in depth, brain
   re-ran the same opcode bytes locally before accepting.  The cell
   is signed by the device's BSV cert.  No API keys.  No cloud LLM.
   No data leaves my chain except the audited cell you just saw
   arrive.  And the entire round-trip — from speaking to my phone to
   the brain transitioning the job — runs on infrastructure I own."*

## Troubleshooting

### Phone says "voice pipeline still initialising or failed to initialise"

You're on a pre-#428 APK.  Rebuild:

```sh
cd apps/oddjobz-mobile && flutter build apk --release && flutter install -d RF8R11T6VDE
```

### Right panel never updates

The brain didn't accept the cell.  Check:

```sh
ssh rbs 'sudo tail -n 30 /var/lib/semantos/oddjobz/intent-cells.jsonl'
```

If empty: the outbox flush failed.  Check phone's flutter logs for
HTTP errors.

If lines exist but none are recent: the WSS subscription didn't fire.
Hard-refresh the laptop browser (Cmd-Shift-R).

### Left panel doesn't flip state (Tier 3)

The router didn't match a job.  Check:

```sh
ssh rbs 'sudo journalctl -u semantos-shell -n 50 | grep intent_action_router'
```

Look for `match_ambiguous` or `match_none` or `bad_state` lines.  Try
the demo with a more distinctive token in your command.

### Bearer expired / invalid

Issue a fresh one (the demo bearer expires ~22 days from issue):

```sh
ssh rbs 'sudo -u semantos BRAIN_DATA_DIR=/var/lib/semantos \
         /opt/semantos/brain bearer issue --label brain-helm-viewer-fresh'
```

Paste the new token in the viewer's setup overlay.

## Post-demo cleanup

Disable the router so it doesn't fire on accidental future commands:

```sh
ssh rbs '
  sudo tee /etc/systemd/system/semantos-shell.service.d/exec.conf > /dev/null <<EOF
[Service]
ExecStart=
ExecStart=/opt/semantos/brain serve \${BRAIN_DOMAIN} --enable-repl
EOF
  sudo systemctl daemon-reload
  sudo systemctl restart semantos-shell
'
```

The router default is OFF, so omitting the flag returns the brain to
audit-only mode — intent cells still log to JSONL but don't trigger
FSM transitions.
