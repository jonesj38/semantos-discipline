---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/oddjobtodd/src/styles/stages.css
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.053200+00:00
---

# apps/oddjobtodd/src/styles/stages.css

```css
/* helm-v3 additions — job-stage trail + composed job card + voice reference */

/* ===== job-stage trail ===== */
.stage-trail {
  display: flex;
  align-items: center;
  gap: 0;
  font-family: var(--mono);
  font-size: 8.5px;
  letter-spacing: 0.14em;
  text-transform: uppercase;
  color: var(--ink-faint);
  padding: 4px 0;
}
.stage-trail .stage {
  display: flex;
  align-items: center;
  gap: 6px;
  flex: 0 0 auto;
}
.stage-trail .stage .pip {
  width: 7px; height: 7px;
  border: 1px solid var(--ink-dim);
  border-radius: 50%;
  background: transparent;
  flex: 0 0 auto;
}
.stage-trail .stage.done .pip {
  background: var(--hold);
  border-color: var(--hold);
  box-shadow: 0 0 4px rgba(111, 214, 181, 0.5);
}
.stage-trail .stage.done .lbl { color: var(--ink-soft); }
.stage-trail .stage.now .pip {
  background: var(--activation);
  border-color: var(--activation);
  box-shadow: 0 0 8px var(--activation-glow);
  animation: pulse 1.6s ease-in-out infinite;
}
.stage-trail .stage.now .lbl { color: var(--activation); }
.stage-trail .conn {
  flex: 1;
  height: 1px;
  background: var(--rule);
  margin: 0 6px;
  min-width: 8px;
}
.stage-trail .conn.done { background: var(--hold); }

/* compact vertical version for the artifact */
.stage-trail-v {
  display: flex;
  flex-direction: column;
  gap: 2px;
  margin-top: 12px;
}
.stage-trail-v .stage {
  display: flex;
  align-items: center;
  gap: 10px;
  font-family: var(--mono);
  font-size: 10px;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  color: var(--ink-faint);
  padding: 3px 0;
  position: relative;
}
.stage-trail-v .stage .pip {
  width: 9px; height: 9px;
  border-radius: 50%;
  border: 1px solid var(--ink-dim);
  background: transparent;
  flex: 0 0 auto;
  z-index: 2;
}
.stage-trail-v .stage::before {
  content: "";
  position: absolute;
  left: 4px; top: 14px; bottom: -3px;
  width: 1px;
  background: var(--rule);
  z-index: 1;
}
.stage-trail-v .stage:last-child::before { display: none; }
.stage-trail-v .stage.done .pip {
  background: var(--hold);
  border-color: var(--hold);
  box-shadow: 0 0 5px rgba(111, 214, 181, 0.5);
}
.stage-trail-v .stage.done::before { background: var(--hold); }
.stage-trail-v .stage.done .lbl { color: var(--ink-soft); }
.stage-trail-v .stage.now .pip {
  background: var(--activation);
  border-color: var(--activation);
  box-shadow: 0 0 10px var(--activation-glow);
  animation: pulse 1.6s ease-in-out infinite;
}
.stage-trail-v .stage.now .lbl { color: var(--activation); }
.stage-trail-v .stage .when {
  margin-left: auto;
  font-size: 8.5px;
  color: var(--ink-faint);
  letter-spacing: 0.1em;
}

/* ===== verb-shelf (do/find sheets that bubble up) ===== */
.shelf {
  border: 1px solid var(--rule-bright);
  border-radius: 6px;
  padding: 12px;
  background: var(--shell-3);
  margin-top: 10px;
}
.shelf-hdr {
  font-family: var(--mono);
  font-size: 9px;
  color: var(--activation);
  letter-spacing: 0.18em;
  text-transform: uppercase;
  margin-bottom: 10px;
  display: flex;
  align-items: center;
  gap: 8px;
}
.shelf-hdr::before {
  content: "";
  width: 5px; height: 5px;
  background: var(--activation);
  box-shadow: 0 0 4px var(--activation-glow);
}
.shelf-actions {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.shelf-action {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 9px 10px;
  border: 1px solid var(--rule);
  border-radius: 4px;
  font-family: var(--mono);
  font-size: 11px;
  color: var(--ink);
  background: var(--shell-2);
}
.shelf-action .verb {
  color: var(--activation);
  font-weight: 700;
  letter-spacing: 0.04em;
  flex: 0 0 auto;
}
.shelf-action .obj {
  color: var(--ink-soft);
  flex: 1;
}
.shelf-action .kbd {
  font-size: 8.5px;
  color: var(--ink-faint);
  letter-spacing: 0.16em;
  text-transform: uppercase;
  margin-left: auto;
}

/* ===== composed job card (replaces FSM artifact) ===== */
.job-card {
  border: 1px solid var(--rule-bright);
  border-radius: 6px;
  padding: 14px;
  background:
    linear-gradient(180deg, rgba(127, 217, 255, 0.04), transparent 30%),
    var(--shell-3);
  position: relative;
}
.job-card::before {
  content: "";
  position: absolute;
  top: -1px; left: -1px;
  width: 14px; height: 14px;
  border-top: 2px solid var(--activation);
  border-left: 2px solid var(--activation);
}
.job-card::after {
  content: "";
  position: absolute;
  bottom: -1px; right: -1px;
  width: 14px; height: 14px;
  border-bottom: 2px solid var(--activation);
  border-right: 2px solid var(--activation);
}
.job-card .job-tag {
  font-family: var(--mono);
  font-size: 9px;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--activation);
  margin-bottom: 6px;
  display: flex;
  justify-content: space-between;
}
.job-card .job-tag .id {
  color: var(--ink-faint);
}
.job-card .who {
  font-family: var(--display);
  font-weight: 400;
  font-size: 19px;
  color: var(--ink);
  letter-spacing: -0.2px;
  margin-bottom: 2px;
}
.job-card .what {
  font-family: var(--sans);
  font-weight: 300;
  font-size: 13px;
  color: var(--ink-soft);
  margin-bottom: 6px;
}
.job-card .where-when {
  font-family: var(--mono);
  font-size: 10px;
  color: var(--ink-faint);
  letter-spacing: 0.06em;
  text-transform: uppercase;
}

/* ===== voice transcript with object reference ===== */
.utter-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin-top: 4px;
}
.utter {
  font-family: var(--mono);
  font-size: 13px;
  line-height: 1.5;
  color: var(--ink);
  padding: 10px 12px;
  border: 1px solid var(--rule);
  border-radius: 4px;
  background: rgba(13,16,20,0.5);
  position: relative;
}
.utter .speaker {
  font-size: 8.5px;
  color: var(--ink-faint);
  letter-spacing: 0.18em;
  text-transform: uppercase;
  margin-bottom: 4px;
  display: flex;
  align-items: center;
  gap: 6px;
}
.utter.live .speaker::before {
  content: "";
  width: 5px; height: 5px;
  border-radius: 50%;
  background: var(--linear);
  box-shadow: 0 0 6px var(--linear-glow);
  animation: pulse 1.4s ease-in-out infinite;
}
.utter .ref {
  background: var(--activation-soft);
  color: var(--activation);
  border-bottom: 1px solid var(--activation);
  padding: 0 4px;
  border-radius: 1px;
}
.utter .verb {
  color: var(--linear);
  font-weight: 700;
}
.utter.reply {
  border-color: var(--rule-bright);
  background: var(--shell-3);
}
.utter.reply .speaker { color: var(--activation); }

/* small object preview pulled from .ref */
.ref-preview {
  margin-top: 8px;
  padding: 10px;
  border: 1px dashed var(--activation);
  border-radius: 4px;
  background: rgba(127, 217, 255, 0.04);
  font-family: var(--mono);
  font-size: 11px;
  color: var(--ink);
  line-height: 1.5;
}
.ref-preview .ref-tag {
  font-size: 8.5px;
  color: var(--activation);
  letter-spacing: 0.18em;
  text-transform: uppercase;
  margin-bottom: 4px;
}
.ref-preview .ref-row {
  display: flex;
  justify-content: space-between;
  color: var(--ink-soft);
  padding: 2px 0;
}
.ref-preview .ref-row b { color: var(--ink); font-weight: 500; }

/* small "active jobs" list for home */
.jobs-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
  margin-top: 10px;
  flex: 1;
  overflow: hidden;
}
.job-row {
  border: 1px solid var(--rule);
  border-radius: 4px;
  padding: 10px 12px;
  background: var(--shell-3);
  position: relative;
}
.job-row.activated {
  border-color: var(--activation);
  background:
    linear-gradient(180deg, rgba(127, 217, 255, 0.06), transparent),
    var(--shell-3);
  box-shadow: 0 0 14px -4px var(--activation-glow);
}
.job-row .who {
  font-family: var(--display);
  font-weight: 400;
  font-size: 14px;
  color: var(--ink);
  margin-bottom: 2px;
}
.job-row .what {
  font-family: var(--mono);
  font-size: 10px;
  color: var(--ink-faint);
  letter-spacing: 0.06em;
  text-transform: uppercase;
}
.job-row .stage-tag {
  position: absolute;
  top: 10px; right: 10px;
  font-family: var(--mono);
  font-size: 8px;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  color: var(--activation);
}
.job-row .stage-tag.done { color: var(--hold); }

```
