---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-demo-wasm-threejs/src/style.css
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.759613+00:00
---

# archive/apps-demo-wasm-threejs/src/style.css

```css
* { box-sizing: border-box; margin: 0; padding: 0; }

html, body {
  width: 100%;
  height: 100%;
  overflow: hidden;
  background: #0a0a0f;
  color: #e8e8f0;
  font: 13px/1.5 ui-monospace, "SF Mono", Menlo, Consolas, monospace;
}

#scene {
  position: fixed;
  inset: 0;
  width: 100%;
  height: 100%;
  display: block;
}

#hud {
  position: fixed;
  top: 16px;
  left: 16px;
  z-index: 10;
  pointer-events: none;
  max-width: 460px;
}

#title {
  font-size: 18px;
  font-weight: 600;
  letter-spacing: -0.01em;
  margin-bottom: 4px;
}

#hint {
  opacity: 0.6;
  margin-bottom: 16px;
}

#readout {
  font-size: 12px;
  white-space: pre-wrap;
  background: rgba(20, 20, 28, 0.85);
  padding: 12px;
  border-radius: 6px;
  border: 1px solid rgba(255, 255, 255, 0.08);
  display: none;
  pointer-events: none;
  max-width: 440px;
}
#readout.visible { display: block; }
#readout.violation {
  border-color: rgba(255, 90, 90, 0.45);
  background: rgba(50, 14, 14, 0.85);
}

/* ── legend ──────────────────────────────────────────────── */
#legend {
  position: fixed;
  top: 16px;
  right: 16px;
  z-index: 10;
  background: rgba(20, 20, 28, 0.85);
  padding: 10px 14px;
  border-radius: 6px;
  border: 1px solid rgba(255, 255, 255, 0.08);
  font-size: 11px;
  pointer-events: none;
}
#legend .lrow {
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 2px 0;
}
#legend .dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  display: inline-block;
}
#legend .dot.linear   { background: #4a9eff; }
#legend .dot.affine   { background: #888899; }
#legend .dot.relevant { background: #6ad08a; }
#legend .rule {
  opacity: 0.55;
  margin-left: auto;
  font-size: 10px;
}

/* ── controls ────────────────────────────────────────────── */
#controls {
  position: fixed;
  bottom: 16px;
  left: 16px;
  z-index: 10;
  display: flex;
  gap: 12px;
  align-items: center;
  background: rgba(20, 20, 28, 0.85);
  padding: 8px 12px;
  border-radius: 6px;
  border: 1px solid rgba(255, 255, 255, 0.08);
  font-size: 12px;
}
#controls .toggle {
  display: flex;
  align-items: center;
  gap: 6px;
  cursor: pointer;
  user-select: none;
}
#controls button {
  background: rgba(255, 255, 255, 0.08);
  color: inherit;
  border: 1px solid rgba(255, 255, 255, 0.12);
  padding: 4px 10px;
  border-radius: 4px;
  font: inherit;
  cursor: pointer;
}
#controls button:hover {
  background: rgba(255, 255, 255, 0.14);
}

/* ── identity panel ──────────────────────────────────────── */
#identity-panel {
  position: fixed;
  bottom: 16px;
  right: 16px;
  z-index: 10;
  width: 300px;
  max-height: calc(100vh - 100px);
  overflow-y: auto;
  background: rgba(14, 14, 22, 0.92);
  border: 1px solid rgba(255, 255, 255, 0.10);
  border-radius: 8px;
  font-size: 11px;
  color: #d0d0e0;
}

#identity-panel summary {
  cursor: pointer;
  padding: 8px 12px;
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: #a0a0c0;
  user-select: none;
  border-bottom: 1px solid rgba(255,255,255,0.06);
  list-style: none;
}
#identity-panel summary::-webkit-details-marker { display: none; }
#identity-panel details[open] summary {
  color: #c0c0e8;
  border-bottom-color: rgba(255,255,255,0.10);
}
#identity-panel summary::before {
  content: '+ ';
  opacity: 0.5;
}
#identity-panel details[open] summary::before {
  content: '- ';
}

.ip-section {
  padding: 10px 12px;
}
.ip-section + .ip-section {
  border-top: 1px solid rgba(255,255,255,0.06);
}

.ip-row {
  display: flex;
  gap: 6px;
  margin-bottom: 6px;
  align-items: center;
}
.ip-row input[type="text"],
.ip-row input[type="email"] {
  flex: 1;
  background: rgba(255,255,255,0.06);
  border: 1px solid rgba(255,255,255,0.12);
  border-radius: 4px;
  color: inherit;
  font: inherit;
  padding: 4px 7px;
  outline: none;
}
.ip-row input:focus {
  border-color: rgba(160,160,240,0.4);
}

.ip-btn {
  background: rgba(255,255,255,0.09);
  color: inherit;
  border: 1px solid rgba(255,255,255,0.14);
  padding: 4px 9px;
  border-radius: 4px;
  font: inherit;
  cursor: pointer;
  white-space: nowrap;
}
.ip-btn:hover { background: rgba(255,255,255,0.15); }

.ip-result {
  margin-top: 6px;
  padding: 6px 8px;
  background: rgba(255,255,255,0.04);
  border-radius: 4px;
  border: 1px solid rgba(255,255,255,0.07);
  white-space: pre-wrap;
  word-break: break-all;
  line-height: 1.55;
  display: none;
}
.ip-result.visible { display: block; }
.ip-result.ok { border-color: rgba(100,210,140,0.35); }
.ip-result.fail { border-color: rgba(255,90,90,0.35); }
.ip-result .hi { color: #6ad08a; }
.ip-result .stub-marker {
  display: inline-block;
  background: rgba(106,208,138,0.18);
  border: 1px solid rgba(106,208,138,0.4);
  border-radius: 3px;
  padding: 0 4px;
  color: #6ad08a;
  font-size: 10px;
}

.ip-challenge-list {
  display: flex;
  flex-direction: column;
  gap: 5px;
  margin-bottom: 6px;
}
.ip-challenge-item {
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.ip-challenge-label {
  opacity: 0.6;
  font-size: 10px;
}
.ip-challenge-item input {
  background: rgba(255,255,255,0.06);
  border: 1px solid rgba(255,255,255,0.12);
  border-radius: 4px;
  color: inherit;
  font: inherit;
  padding: 3px 7px;
  outline: none;
}
.ip-challenge-item input:focus {
  border-color: rgba(160,160,240,0.4);
}

```
