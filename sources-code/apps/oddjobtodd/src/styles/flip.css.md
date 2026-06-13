---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/oddjobtodd/src/styles/flip.css
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.053759+00:00
---

# apps/oddjobtodd/src/styles/flip.css

```css
/* helm-v4 — flippable object cards + analytics back */

.flip-card {
  perspective: 900px;
  position: relative;
}
.flip-inner {
  position: relative;
  transform-style: preserve-3d;
  transition: transform 520ms cubic-bezier(0.7, 0, 0.3, 1);
}
.flip-card.flipped .flip-inner {
  transform: rotateY(180deg);
}
.flip-face {
  backface-visibility: hidden;
  -webkit-backface-visibility: hidden;
}
.flip-face.back {
  position: absolute;
  inset: 0;
  transform: rotateY(180deg);
}

/* row-level flip for shelf items */
.shelf-action.flippable {
  cursor: pointer;
  position: relative;
  min-height: 44px;
}
.shelf-action.flippable .flip-inner {
  display: block;
  width: 100%;
}
.shelf-action.flippable .flip-face {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
}
.shelf-action.flippable .flip-face.back {
  flex-direction: column;
  align-items: stretch;
  gap: 6px;
  padding: 0;
}

/* analytics back */
.analytics {
  display: flex;
  flex-direction: column;
  gap: 4px;
  font-family: var(--mono);
  font-size: 10px;
  color: var(--ink-soft);
}
.analytics .a-hdr {
  font-size: 8.5px;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--activation);
  display: flex;
  justify-content: space-between;
  margin-bottom: 2px;
}
.analytics .a-row {
  display: flex;
  justify-content: space-between;
  padding: 1px 0;
}
.analytics .a-row b { color: var(--ink); font-weight: 500; }
.analytics .a-row .good { color: var(--hold); }
.analytics .a-row .warn { color: var(--linear); }
.analytics .bar-track {
  height: 3px;
  background: var(--rule);
  border-radius: 2px;
  overflow: hidden;
  margin: 4px 0 2px;
}
.analytics .bar-fill {
  height: 100%;
  background: var(--activation);
  box-shadow: 0 0 6px var(--activation-glow);
}

/* shelf header with lens toggle */
.shelf-hdr.with-lens {
  justify-content: space-between;
}
.lens-toggle {
  display: inline-flex;
  border: 1px solid var(--rule);
  border-radius: 3px;
  overflow: hidden;
  font-family: var(--mono);
  font-size: 8.5px;
  letter-spacing: 0.16em;
  text-transform: uppercase;
}
.lens-toggle button {
  background: transparent;
  border: none;
  color: var(--ink-faint);
  padding: 4px 9px;
  cursor: pointer;
  font: inherit;
  letter-spacing: inherit;
  text-transform: inherit;
}
.lens-toggle button.on {
  background: var(--activation-soft);
  color: var(--activation);
}

/* sparkline-ish row */
.spark {
  display: flex;
  align-items: flex-end;
  gap: 2px;
  height: 14px;
}
.spark span {
  flex: 1;
  background: var(--ink-dim);
  border-radius: 1px;
  min-height: 2px;
}
.spark span.now {
  background: var(--activation);
  box-shadow: 0 0 4px var(--activation-glow);
}
.spark span.bad {
  background: var(--linear);
}

/* hint to flip */
.flip-hint {
  position: absolute;
  top: 8px; right: 10px;
  font-family: var(--mono);
  font-size: 8px;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--ink-faint);
  opacity: 0.6;
}
.shelf-action.flippable:hover .flip-hint { opacity: 1; }

```
