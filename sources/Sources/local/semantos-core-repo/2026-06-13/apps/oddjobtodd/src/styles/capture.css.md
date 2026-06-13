---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/oddjobtodd/src/styles/capture.css
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.053484+00:00
---

# apps/oddjobtodd/src/styles/capture.css

```css
/* v7 — Capture: triple-click mic → camera (photo / video switch).
   The mic FAB itself stays the same disc it always was; camera mode
   only changes the disc's glyph and adds a small switch above. */

/* Camera-mode disc */
.mic-fab.camera {
  border-color: var(--linear);
  color: var(--linear);
  font-size: 22px;
  box-shadow:
    0 0 0 1px rgba(255, 178, 74, 0.18),
    0 0 28px -4px var(--linear-glow),
    0 8px 16px -4px rgba(0,0,0,0.6);
}
.mic-fab.camera.video {
  /* recording shutter pulses */
  animation: pulse 1.4s ease-in-out infinite;
}

/* Segmented photo/video switch — sits directly above the disc, same right anchor */
.capture-switch {
  position: absolute;
  right: 22px;
  bottom: 168px;          /* mic-fab is at bottom: 100px, height 56 → switch sits 12px above */
  display: flex;
  align-items: stretch;
  gap: 1px;
  padding: 1px;
  background:
    linear-gradient(180deg, var(--shell-3), var(--shell-2));
  border: 1px solid var(--rule-bright);
  border-radius: 6px;
  box-shadow:
    0 0 18px -8px var(--linear-glow),
    0 6px 14px -4px rgba(0,0,0,0.6);
  z-index: 5;
  font-family: var(--mono);
  font-size: 10px;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  animation: capture-switch-in 220ms ease both;
}
@keyframes capture-switch-in {
  from { opacity: 0; transform: translateY(6px); }
  to   { opacity: 1; transform: translateY(0); }
}
.capture-switch button {
  appearance: none;
  -webkit-appearance: none;
  border: none;
  background: transparent;
  color: var(--ink-soft);
  padding: 7px 10px;
  cursor: pointer;
  font-family: inherit;
  font-size: inherit;
  letter-spacing: inherit;
  text-transform: inherit;
  border-radius: 4px;
  transition: color 160ms ease, background 160ms ease;
}
.capture-switch button:hover { color: var(--ink); }
.capture-switch button.on {
  color: var(--linear);
  background: rgba(255, 178, 74, 0.14);
}
.capture-switch .dismiss {
  color: var(--ink-faint);
  padding: 7px 8px;
  border-left: 1px solid var(--rule);
  border-radius: 0 4px 4px 0;
  font-size: 11px;
  letter-spacing: 0;
}
.capture-switch .dismiss:hover { color: var(--ink); background: transparent; }

```
