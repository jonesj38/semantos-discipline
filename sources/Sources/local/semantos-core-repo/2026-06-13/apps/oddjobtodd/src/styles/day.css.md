---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/oddjobtodd/src/styles/day.css
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.054365+00:00
---

# apps/oddjobtodd/src/styles/day.css

```css
/* helm-v6 — day mode override.
   The base palette in helm-v2.css is night-cool. This overrides only the
   tokens that need to flip when [data-mode="day"] is set on <html>.
   Keep the same accent (ice cyan default) but invert the surfaces:
   bright shell, dark ink, calmer glows. */

html[data-mode="day"] {
  --void: #f1f3f6;
  --shell:  #ffffff;
  --shell-2:#f5f7fa;
  --shell-3:#eaeef3;
  --rule:        #d4dae2;
  --rule-bright: #b9c2cd;
  --grid: rgba(20, 40, 70, 0.05);

  --ink:       #0d1014;
  --ink-soft:  #3a4555;
  --ink-faint: #6b7889;
  --ink-dim:   #aab6c4;

  --activation: #0a8fd1;          /* deeper cyan reads on white */
  --activation-soft: rgba(10, 143, 209, 0.10);
  --activation-glow: rgba(10, 143, 209, 0.32);

  --hold: #2a9d7e;
  --hold-soft: rgba(42, 157, 126, 0.12);

  --linear: #c47218;
  --linear-soft: rgba(196, 114, 24, 0.10);
  --linear-glow: rgba(196, 114, 24, 0.35);
}

/* Day-mode visual quietening — drop the heavy retro effects */
html[data-mode="day"] body {
  background: #f1f3f6;
}
html[data-mode="day"] .canvas {
  background: transparent;
}
html[data-mode="day"] .canvas::before {
  /* lighter grid + scanlines */
  opacity: 0.5;
}
html[data-mode="day"] .device {
  background:
    radial-gradient(ellipse at 50% 0%, rgba(10, 143, 209, 0.04), transparent 60%),
    linear-gradient(180deg, #ffffff, #f5f7fa) !important;
  border: 1px solid #c5cdd8 !important;
  box-shadow: 0 12px 32px -16px rgba(13, 16, 20, 0.18) !important;
}
html[data-mode="day"] .device::before {
  /* drop scanlines */
  display: none;
}
html[data-mode="day"] .device .notch {
  background: #d4dae2;
  border-color: #b9c2cd;
}
html[data-mode="day"] .repl-foot {
  background: #1a1f27;
  color: #e7eef5;
}
html[data-mode="day"] .repl-foot .arg { color: #e7eef5; }
html[data-mode="day"] .canvas-header {
  border-bottom-color: #c5cdd8;
}
html[data-mode="day"] .frame-card { color: var(--ink); }
html[data-mode="day"] .annot { color: var(--ink-soft); }

/* Soften pulses + glows in day mode */
html[data-mode="day"] [class*="glow"],
html[data-mode="day"] .activation-card {
  box-shadow: 0 8px 24px -12px rgba(10, 143, 209, 0.25) !important;
}

/* Mode toggle button (top-right floating) */
.mode-pill {
  position: fixed;
  top: 18px; right: 18px;
  z-index: 50;
  display: inline-flex;
  border: 1px solid var(--rule-bright);
  border-radius: 999px;
  background: var(--shell-2);
  font-family: var(--mono);
  font-size: 9.5px;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  overflow: hidden;
}
.mode-pill button {
  background: transparent;
  border: none;
  color: var(--ink-faint);
  padding: 7px 14px;
  font: inherit;
  letter-spacing: inherit;
  text-transform: inherit;
  cursor: pointer;
}
.mode-pill button.on {
  background: var(--activation-soft);
  color: var(--activation);
}

```
