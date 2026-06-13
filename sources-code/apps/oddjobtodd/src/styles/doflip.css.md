---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/oddjobtodd/src/styles/doflip.css
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.054916+00:00
---

# apps/oddjobtodd/src/styles/doflip.css

```css
/* v7 — do flip card, glyph key, custom palette */

/* ── Do flip ─────────────────────────────────────────────────────── */
/* Single-face cross-fade. Avoids 3D stacking-context bleed-through; the
   chip glyph carries the orientation-swap metaphor on its own. */
.do-flip-wrap {
  position: relative;
  width: 100%;
  height: 100%;
}
.do-fade {
  width: 100%;
  height: 100%;
  display: flex;
  flex-direction: column;
  animation: do-fade-in 220ms ease both;
}
@keyframes do-fade-in {
  from { opacity: 0; }
  to   { opacity: 1; }
}

/* The flip control — a small chip sitting just below the device ribbon,
   left-anchored so it can't collide with the ribbon's right-side signal text. */
.flip-chip {
  position: absolute;
  top: 70px;
  left: 14px;
  z-index: 10;
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 5px 10px 5px 8px;
  font-family: var(--mono);
  font-size: 10px;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--ink-soft);
  background: rgba(10, 18, 30, 0.78);
  border: 1px solid var(--rule);
  border-radius: 999px;
  cursor: pointer;
  transition: color 200ms ease, border-color 200ms ease, background 200ms ease;
  user-select: none;
  backdrop-filter: blur(6px);
  -webkit-backdrop-filter: blur(6px);
}
.flip-chip:hover {
  color: var(--activation);
  border-color: var(--activation);
  background: var(--activation-soft);
}
.flip-chip .glyph {
  font-size: 13px;
  line-height: 1;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 16px;
  height: 16px;
  color: var(--activation);
}
.flip-chip .lbl { line-height: 1; }
[data-mode="day"] .flip-chip { background: rgba(255, 255, 255, 0.86); }

/* ── Glyph key ───────────────────────────────────────────────────── */
.glyph-key {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 16px 28px;
  padding: 22px 26px;
  margin: 28px 0 0;
  border-top: 1px solid var(--rule);
  border-bottom: 1px solid var(--rule);
}
.glyph-key h4 {
  grid-column: 1 / -1;
  margin: 0 0 4px;
  font-size: 11px;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--ink-soft);
  font-family: var(--mono);
  font-weight: 400;
}
.glyph-key .row {
  display: grid;
  grid-template-columns: 28px 1fr;
  gap: 12px;
  align-items: baseline;
}
.glyph-key .gly {
  font-size: 18px;
  line-height: 1;
  color: var(--activation);
  text-align: center;
  font-family: var(--mono);
}
.glyph-key .copy { color: var(--ink); font-size: 13px; line-height: 1.5; }
.glyph-key .copy b { display: block; font-weight: 500; color: var(--ink); margin-bottom: 2px; }
.glyph-key .copy span { color: var(--ink-soft); }

/* ── Palette builder ─────────────────────────────────────────────── */
.palette-row {
  display: grid;
  grid-template-columns: 80px 1fr 56px;
  align-items: center;
  gap: 10px;
  padding: 6px 0;
  font-size: 12px;
  color: var(--ink-soft);
}
.palette-row label { font-family: var(--mono); font-size: 10.5px; letter-spacing: 0.06em; text-transform: uppercase; }
.palette-row input[type="color"] {
  appearance: none;
  -webkit-appearance: none;
  width: 100%;
  height: 26px;
  padding: 0;
  border: 1px solid var(--rule);
  border-radius: 6px;
  background: transparent;
  cursor: pointer;
}
.palette-row input[type="color"]::-webkit-color-swatch-wrapper { padding: 2px; }
.palette-row input[type="color"]::-webkit-color-swatch { border: none; border-radius: 4px; }
.palette-row input[type="color"]::-moz-color-swatch { border: none; border-radius: 4px; }
.palette-row .hex {
  font-family: var(--mono);
  font-size: 10.5px;
  color: var(--ink-soft);
  text-align: right;
}
.palette-hint {
  margin-top: 8px;
  padding-top: 8px;
  border-top: 1px dashed var(--rule);
  font-family: var(--mono);
  font-size: 10px;
  letter-spacing: 0.04em;
  color: var(--ink-faint);
  line-height: 1.5;
}

```
