---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-brain-helm-viewer/README.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.691852+00:00
---

# brain-helm-viewer

Read-only laptop view onto the operator's brain.  Built for the
**2026-05-07 meetup demo** of the typed-NL on-device intent-cell
pipeline (PRs #427 + #428 + #429).

## Why

The phone's screen isn't projected at the meetup — only the laptop
is visible to the audience.  This page is what the audience sees.
It connects to the operator's brain over the same bearer-gated
HTTP+WSS surface the mobile app uses, lists the operator's actual
jobs, and renders incoming `intent_cell.created` events live as
projection-friendly cards.

Real data only.  No synthetic placeholders.

## What it shows

Three columns:
1. **Jobs · brain** (left) — every job from `find jobs --limit 200`
   on the brain, with current state pill + summary.  Click to focus.
2. **Selected job** (centre) — full detail card for the job clicked
   on the left.
3. **Live intent cells** (right) — every `intent_cell.created` event
   the brain publishes, slid in newest-first.  Each card shows the
   action, summary, kernel ✓, llama 3.2 3B, on-device ✓, no API
   keys ✓, plus the cell id.

The right panel is the wow moment for the demo: when you type or
speak a command on your phone, the audience watches a card slide in
on the laptop within 5–30 seconds (llama 3B inference time on the
S20 FE).

## Run

```sh
cd apps/brain-helm-viewer
python3 -m http.server 8000
# open http://localhost:8000 in a browser on the laptop
```

Or just open `index.html` directly — it's pure static HTML.

## Setup at the venue

1. **Issue a bearer for the laptop** (run on your dev machine):

   ```sh
   ssh rbs 'sudo -u semantos BRAIN_DATA_DIR=/var/lib/semantos \
            /opt/semantos/brain bearer issue --label brain-helm-viewer-meetup'
   ```

   Copy the 64-hex token it prints (it's only shown once — the
   brain stores the fingerprint, not the bearer itself).

2. **Open the page** and paste the brain HTTPS base URL +
   bearer into the setup overlay:

   - Brain HTTPS base URL: `https://brain.oddjobtodd.info` (default)
   - Bearer token: `<paste>`

   The page does a quick `status` smoke-test to validate the bearer
   before hiding the overlay; if it fails, the error surfaces in
   place and the overlay stays up.

3. **Click Connect.**  The page:
   - Calls `find jobs --limit 200` over `POST /api/v1/repl` and
     populates the left list.
   - Opens a WebSocket to `/api/v1/wallet?bearer=…` and sends
     `helm.subscribe` for topics `[intent_cell, jobs, attention]`.
   - Status pill turns green and reads `subscribed`.

4. **Click a job in the left list to focus it** in the centre panel
   (purely cosmetic — the centre detail is what the audience reads
   if they want context for the upcoming command).

## Demo arc

1. Audience sees: real jobs list on the left.  You click one — say
   the `lead`-state roof repair quote at 15 Wattle St — to anchor
   what's about to happen.
2. You type/speak on phone (audience can't see it).
3. Within ~5–30 seconds an intent cell card slides into the right
   panel: `quote`, your summary, kernel ✓, llama 3.2 3B, on-device
   ✓, no API keys ✓, signed cell id.
4. Punchline: *"That command came from a 3B-parameter Llama running
   on a phone in offline mode.  The kernel verifying it is the same
   Zig 2-PDA the brain runs — defense in depth, brain re-ran it
   locally before accepting.  The cell is signed by the device's
   BSV cert.  No API keys, no cloud, no data leaves my chain
   except the audited cell you just saw arrive."*

## What this viewer deliberately does NOT do

- **Does not animate state changes.**  When an intent cell arrives,
  the right panel updates.  The left panel's job state pill does
  NOT flip from `lead` → `quoted`.  That's because the brain hasn't
  yet wired `intent_cell.created` → oddjobz FSM transition — the
  intent cell is currently audit-only.  The next slice (Tier 3)
  builds a brain-side handler that subscribes to the same broker
  topic and routes by action into the existing `oddjobz.*`
  workflows.  Until that lands, faking the pill flip on the viewer
  would lie to the audience about what's actually happening on the
  brain.

  After Tier 3 lands, this viewer will pick up `jobs.*` broker
  events automatically — `loadJobs()` re-runs on those frames, so
  the left list will repaint with the new state and the centre
  detail card will follow.

## Files

- `index.html` — entire viewer.  Vanilla JS, no build, no deps.
- `README.md` — this file.
