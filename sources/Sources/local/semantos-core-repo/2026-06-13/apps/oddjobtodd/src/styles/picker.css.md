---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/oddjobtodd/src/styles/picker.css
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.054639+00:00
---

# apps/oddjobtodd/src/styles/picker.css

```css
/* helm-v5 — do verb-picker walking to objects, REPL footer, live clock */

.do-pick {
  display: grid;
  grid-template-columns: 1fr 1.4fr;
  gap: 8px;
  margin-top: 4px;
  flex: 1;
  min-height: 0;
}
.do-col {
  border: 1px solid var(--rule);
  border-radius: 5px;
  background: var(--shell-3);
  display: flex;
  flex-direction: column;
  min-height: 0;
}
.do-col-hdr {
  font-family: var(--mono);
  font-size: 8.5px;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--ink-faint);
  padding: 8px 10px;
  border-bottom: 1px solid var(--rule);
  display: flex;
  justify-content: space-between;
}
.do-col-hdr .accent { color: var(--activation); }
.do-col-body {
  padding: 6px;
  display: flex;
  flex-direction: column;
  gap: 3px;
  overflow: auto;
}
.verb-row {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 7px 8px;
  border: 1px solid transparent;
  border-radius: 3px;
  font-family: var(--mono);
  font-size: 11px;
  color: var(--ink);
  cursor: pointer;
}
.verb-row .v {
  color: var(--activation);
  font-weight: 700;
  letter-spacing: 0.04em;
}
.verb-row .o {
  color: var(--ink-faint);
  font-size: 9.5px;
  letter-spacing: 0.06em;
}
.verb-row .ct {
  margin-left: auto;
  font-size: 8.5px;
  color: var(--ink-faint);
  letter-spacing: 0.16em;
  text-transform: uppercase;
}
.verb-row.selected {
  border-color: var(--activation);
  background: var(--activation-soft);
}
.verb-row.selected .o { color: var(--ink-soft); }

.obj-row {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 9px;
  border: 1px solid var(--rule);
  border-radius: 3px;
  background: var(--shell-2);
  font-family: var(--mono);
  font-size: 10.5px;
  color: var(--ink);
  position: relative;
}
.obj-row .who { color: var(--ink); }
.obj-row .meta { color: var(--ink-faint); font-size: 9px; letter-spacing: 0.06em; }
.obj-row .live-clock {
  margin-left: auto;
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 9.5px;
  color: var(--linear);
  letter-spacing: 0.06em;
}
.obj-row .live-clock::before {
  content: "";
  width: 5px; height: 5px;
  border-radius: 50%;
  background: var(--linear);
  box-shadow: 0 0 6px var(--linear-glow);
  animation: pulse 1.4s ease-in-out infinite;
}
.obj-row.dim { opacity: 0.4; pointer-events: none; }
.obj-row.target {
  border-color: var(--activation);
  box-shadow: 0 0 12px -4px var(--activation-glow);
}

.repl-foot {
  margin-top: 8px;
  margin-bottom: 56px; /* clear .mic-fab.bar at bottom: 100px */
  padding: 9px 10px;
  border: 1px solid var(--rule-bright);
  border-radius: 4px;
  background: rgba(13,16,20,0.7);
  font-family: var(--mono);
  font-size: 11px;
  color: var(--ink);
  display: flex;
  align-items: center;
  gap: 8px;
}
.repl-foot::before {
  content: "›";
  color: var(--activation);
  font-weight: 700;
  font-size: 13px;
}
.repl-foot .cmd { color: var(--linear); }
.repl-foot .arg { color: var(--ink); }
.repl-foot .ghost { color: var(--ink-faint); margin-left: auto; font-size: 8.5px; letter-spacing: 0.18em; text-transform: uppercase; }

/* live-clock pip on home rows */
.job-row.live-clock-on::after {
  content: "";
  position: absolute;
  top: 12px; right: 60px;
  width: 6px; height: 6px;
  border-radius: 50%;
  background: var(--linear);
  box-shadow: 0 0 6px var(--linear-glow);
  animation: pulse 1.4s ease-in-out infinite;
}

/* hours-feed annotation under analytics */
.feed-arrow {
  display: flex;
  align-items: center;
  gap: 6px;
  margin-top: 6px;
  font-family: var(--mono);
  font-size: 8.5px;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--ink-faint);
}
.feed-arrow .arr {
  color: var(--activation);
}

```
