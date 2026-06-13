---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/oddjobtodd/src/components/HelmScreens.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.052545+00:00
---

# apps/oddjobtodd/src/components/HelmScreens.tsx

```tsx
import { useState } from 'react';
import { Dock, Ribbon, Mic, Sentence, StageTrail } from './HelmPrimitives';

// ── State 1: helm at rest ────────────────────────────────────────────
export function S1_Rest({ voice }: { voice: string }) {
  return (
    <div className="screen">
      <Ribbon hat="Iolo · ⌂" signal="" />
      <div className="anchor-empty">
        <div className="breath" />
        <div className="line1">Nothing pulling at you.</div>
      </div>
      <Mic variant={voice} />
      <Dock active="home" />
    </div>
  );
}

// ── State 2: activation — home shows live jobs at their stage ────────
export function S2_Activation({ voice }: { voice: string }) {
  return (
    <div className="screen">
      <Ribbon hat="Iolo · ⌂" signal="" />
      <div className="activation-card">
        <h3>Wendy K. — burst pipe, two streets away.</h3>
        <p>4 min away · you've worked her block before · plumber cert valid 11d.</p>
        <div className="actions">
          <div className="walk">walk it →</div>
          <div className="dismiss">let go</div>
        </div>
      </div>
      <div className="jobs-list">
        <div className="job-row">
          <div className="stage-tag">quoted</div>
          <div className="who">Sarah O.</div>
          <div className="what">kitchen re-pipe · awaiting accept</div>
        </div>
        <div className="job-row">
          <div className="stage-tag">on-site</div>
          <div className="who">Akande Plumbing</div>
          <div className="what">commercial site · day 2 of 3</div>
        </div>
        <div className="job-row">
          <div className="stage-tag done">paid</div>
          <div className="who">Mr. Davies</div>
          <div className="what">tap replace · settled 11:02</div>
        </div>
      </div>
      <Mic variant={voice} />
      <Dock active="home" activated={['home']} />
    </div>
  );
}

// ── State 3: voice mid-path — composing a new job ───────────────────
export function S3_Voice() {
  return (
    <div className="screen">
      <Ribbon hat="Iolo · ⌂" signal="talk · composing" />
      <div className="label-mono" style={{ marginBottom: 6 }}>
        <span className="accent">composing</span> · 3 of 5 held
      </div>
      <Sentence
        filled={{ what: 'burst-pipe fix', where: '27 Beach Rd', when: 'within the hour' }}
        live="who"
      />
      <div className="utter-list">
        <div className="utter live">
          <div className="speaker">you · live</div>
          burst pipe at 27 Beach Road, soon as possible — someone certified, doesn't matter the…
        </div>
      </div>
      <Mic variant="fab" live />
      <Dock active="talk" activated={['home']} />
    </div>
  );
}

// ── State 4: thumb mid-path — deliberate selection ──────────────────
export function S4_Thumb() {
  return (
    <div className="screen">
      <Ribbon hat="Iolo · ⌂" signal="thumb · composing" />
      <div className="label-mono" style={{ marginBottom: 6 }}>
        <span className="accent">composing</span> · 3 of 5 held
      </div>
      <Sentence
        filled={{ what: 'burst-pipe fix', where: '27 Beach Rd', when: 'within the hour' }}
        live="who"
      />
      <div className="label-mono" style={{ marginTop: 14 }}>WHO — pick the kind of person</div>
      <div className="node-options">
        <div className="opt">
          <div className="check" />
          <div>anyone in network</div>
          <div className="meta">12 NEAR</div>
        </div>
        <div className="opt selected">
          <div className="check" />
          <div>certified plumber</div>
          <div className="meta">3 NEAR</div>
        </div>
        <div className="opt">
          <div className="check" />
          <div>worked w/ me before</div>
          <div className="meta">1 NEAR</div>
        </div>
      </div>
      <Mic variant="fab" />
      <Dock active="do" activated={['home']} />
    </div>
  );
}

// ── State 5: LINEAR gate ─────────────────────────────────────────────
export function S5_Gate({ gate }: { gate: string }) {
  return (
    <div className="screen">
      <Ribbon hat="Iolo · ⌂" signal="about to commit" />
      <div className="label-mono" style={{ marginBottom: 6 }}>
        intent fully resolved · 5 of 5
      </div>
      <Sentence
        filled={{
          what:  'burst-pipe fix',
          where: '27 Beach Rd',
          when:  'within the hour',
          who:   'certified plumber',
          worth: '£140 fixed',
        }}
      />
      <div className="gate" style={{ marginTop: 'auto' }}>
        <div className="gate-hdr">commit · cannot be undone</div>
        <div className="summary">
          You'll dispatch <b>£140</b> to 3 plumbers within 4km. First to accept wins the job.
        </div>
        {gate === 'hold' && (
          <div className="gate-hold">
            <div className="ring" />
            <span>hold to commit · 60%</span>
          </div>
        )}
        {gate === 'slide' && (
          <div className="gate-slide">
            <div className="knob">→</div>
            <div className="track-text">slide to commit £140</div>
          </div>
        )}
        {gate === 'twostep' && (
          <div className="gate-twostep">
            <div className="arm on">armed</div>
            <div className="commit">commit £140</div>
          </div>
        )}
        {gate === 'shift' && (
          <div className="gate-shift">
            commit £140
            <small>tap once · cannot undo</small>
          </div>
        )}
      </div>
      <Dock active="do" />
    </div>
  );
}

// ── State 6: composed job card — stage trail ─────────────────────────
export function S6_Artifact({ voice }: { voice: string }) {
  return (
    <div className="screen">
      <Ribbon hat="Iolo · ⌂" signal="job in flight" />
      <div className="job-card">
        <div className="job-tag">
          <span>job · scheduled</span>
          <span className="id">#OJ-2841</span>
        </div>
        <div className="who">Wendy Khumalo</div>
        <div className="what">burst-pipe fix · plumber dispatched · £140</div>
        <div className="where-when">27 Beach Rd · arriving 14:48</div>
        <StageTrail at="sched" withWhen={{ lead: '13:58', quote: '14:21', sched: '14:32' }} />
      </div>
      <Mic variant={voice} />
      <Dock active="home" activated={['home']} />
    </div>
  );
}

// ── State 7: voice referencing an existing object ────────────────────
export function S7_Reference({ scenario = 'show' }: { scenario?: 'show' | 'edit' }) {
  if (scenario === 'show') {
    return (
      <div className="screen">
        <Ribbon hat="Iolo · ⌂" signal="talk · resolving reference" />
        <div className="label-mono" style={{ marginBottom: 8 }}>
          <span className="accent">find</span> via voice — no menu dive
        </div>
        <div className="utter-list">
          <div className="utter">
            <div className="speaker">you</div>
            show me the <span className="ref">quote for Sarah</span>
          </div>
          <div className="utter reply">
            <div className="speaker">helm · resolved</div>
            <div className="ref-preview">
              <div className="ref-tag">quote · Sarah Okafor · #Q-118</div>
              <div className="ref-row"><span>kitchen re-pipe</span><b>3 lines</b></div>
              <div className="ref-row"><span>materials</span><b>£420</b></div>
              <div className="ref-row"><span>labour</span><b>6h · £390</b></div>
              <div className="ref-row"><span>total</span><b>£810</b></div>
              <div className="ref-row"><span>state</span><b>sent · awaiting</b></div>
            </div>
          </div>
        </div>
        <Mic variant="bar" />
        <Dock active="talk" />
      </div>
    );
  }
  return (
    <div className="screen">
      <Ribbon hat="Iolo · ⌂" signal="talk · editing object" />
      <div className="label-mono" style={{ marginBottom: 8 }}>
        <span className="accent">do</span> via voice — verb against object
      </div>
      <div className="utter-list">
        <div className="utter live">
          <div className="speaker">you · live</div>
          <span className="verb">add a line item</span> and a 15% variance to the <span className="ref">quote for Sarah</span>
        </div>
        <div className="utter reply">
          <div className="speaker">helm · staged</div>
          <div className="ref-preview">
            <div className="ref-tag">edit · #Q-118 · pending hold</div>
            <div className="ref-row"><span>+ line</span><b>"new isolation valve"</b></div>
            <div className="ref-row"><span>+ variance</span><b>15% · £121.50</b></div>
            <div className="ref-row"><span>new total</span><b>£931.50</b></div>
          </div>
          <div style={{
            marginTop: 10, fontFamily: 'var(--mono)', fontSize: 9,
            letterSpacing: '0.18em', textTransform: 'uppercase',
            color: 'var(--linear)', display: 'flex', alignItems: 'center', gap: 6,
          }}>
            <span style={{ width: 6, height: 6, background: 'var(--linear)', boxShadow: '0 0 6px var(--linear-glow)', display: 'inline-block' }} />
            hold to confirm change to live quote
          </div>
        </div>
      </div>
      <Mic variant="fab" live />
      <Dock active="talk" activated={['home']} />
    </div>
  );
}

// ── State 8: do-shelf ────────────────────────────────────────────────
export function S8_DoShelf() {
  return (
    <div className="screen">
      <Ribbon hat="Iolo · ⌂" signal="do · stage = on-site" />
      <div className="job-card" style={{ marginBottom: 0 }}>
        <div className="job-tag">
          <span>job · on-site</span>
          <span className="id">#OJ-2783</span>
        </div>
        <div className="who">Akande Plumbing</div>
        <div className="what">commercial · day 2 of 3</div>
        <StageTrail at="onsite" compact />
      </div>
      <div className="shelf">
        <div className="shelf-hdr">advance the stage</div>
        <div className="shelf-actions">
          {[
            { verb: 'log',     obj: 'a visit · capture photos / notes',  kbd: 'tap · or "log visit"' },
            { verb: 'mark',    obj: 'done — triggers invoice draft',       kbd: 'tap · or "mark done"' },
            { verb: 'raise',   obj: 'a variance against the quote',        kbd: 'tap · or "raise variance"' },
            { verb: 'message', obj: 'customer — confirm tomorrow\'s slot', kbd: 'tap · or "message Akande"' },
          ].map(a => (
            <div key={a.verb} className="shelf-action">
              <span className="verb">{a.verb}</span>
              <span className="obj">{a.obj}</span>
              <span className="kbd">{a.kbd}</span>
            </div>
          ))}
        </div>
      </div>
      <Mic variant="bar" />
      <Dock active="do" />
    </div>
  );
}

// ── State 9: find shelf with flippable analytics rows ────────────────
function Spark({ bars, nowIdx, badIdx = -1 }: { bars: number[]; nowIdx: number; badIdx?: number }) {
  return (
    <div className="spark">
      {bars.map((h, i) => (
        <span key={i} className={i === nowIdx ? 'now' : i === badIdx ? 'bad' : ''} style={{ height: `${h}%` }} />
      ))}
    </div>
  );
}

function FlipRow({ front, back }: { front: React.ReactNode; back: React.ReactNode }) {
  const [flipped, setFlipped] = useState(false);
  return (
    <div
      className={`shelf-action flippable ${flipped ? 'flipped' : ''}`}
      onClick={() => setFlipped(f => !f)}
      style={{ flexDirection: flipped ? 'column' : 'row' }}
    >
      {!flipped ? front : back}
      <div className="flip-hint">{flipped ? 'front ↺' : 'flip ↻'}</div>
    </div>
  );
}

export function S9_FindShelf() {
  return (
    <div className="screen">
      <Ribbon hat="Iolo · ⌂" signal="find · recall" />
      <div className="label-mono" style={{ marginBottom: 8 }}>
        <span className="accent">find</span> · tap any row to flip
      </div>
      <div className="shelf">
        <div className="shelf-hdr">recently touched</div>
        <div className="shelf-actions">
          <FlipRow
            front={<><span className="verb">quote</span><span className="obj">Sarah Okafor — kitchen re-pipe</span><span className="kbd">2h ago</span></>}
            back={<div className="analytics">
              <div className="a-hdr"><span>quote · #Q-118</span><span>perf</span></div>
              <div className="a-row"><span>margin if won</span><b className="good">38%</b></div>
              <div className="a-row"><span>vs your avg quote</span><b>+6 pts</b></div>
              <div className="a-row"><span>variance risk</span><b className="warn">med · re-pipes 1.4×</b></div>
              <div className="bar-track"><div className="bar-fill" style={{ width: '62%' }} /></div>
              <div className="a-row"><span>win likelihood</span><b>62%</b></div>
            </div>}
          />
          <FlipRow
            front={<><span className="verb">visit</span><span className="obj">Akande site — day 2/3</span><span className="kbd">today</span></>}
            back={<div className="analytics">
              <div className="a-hdr"><span>visit · day 2/3</span><span>perf</span></div>
              <div className="a-row"><span>hours vs quoted</span><b className="warn">11.5 / 14 · burning fast</b></div>
              <div className="a-row"><span>materials used</span><b>£312 / £420</b></div>
              <Spark bars={[40, 55, 70, 80, 95]} nowIdx={4} badIdx={4} />
              <div className="a-row"><span>projected margin</span><b className="warn">9% (was 22%)</b></div>
            </div>}
          />
          <FlipRow
            front={<><span className="verb">invoice</span><span className="obj">Mr. Davies — £180 · paid</span><span className="kbd">11:02</span></>}
            back={<div className="analytics">
              <div className="a-hdr"><span>invoice · #IV-307</span><span>perf</span></div>
              <div className="a-row"><span>time to pay</span><b className="good">6h · fastest 5%</b></div>
              <div className="a-row"><span>job margin</span><b className="good">44%</b></div>
              <div className="a-row"><span>tap-replace avg</span><b>£165 · this above</b></div>
            </div>}
          />
          <FlipRow
            front={<><span className="verb">customer</span><span className="obj">Wendy Khumalo — 3 jobs</span><span className="kbd">14:32</span></>}
            back={<div className="analytics">
              <div className="a-hdr"><span>customer · 3 jobs · 18mo</span><span>perf</span></div>
              <div className="a-row"><span>lifetime value</span><b>£1,240</b></div>
              <div className="a-row"><span>avg pay time</span><b className="good">2.1d</b></div>
              <div className="a-row"><span>repeat rate</span><b className="good">100% · 3/3</b></div>
              <Spark bars={[30, 45, 60]} nowIdx={2} />
            </div>}
          />
        </div>
      </div>
      <div className="shelf">
        <div className="shelf-hdr">or just ask</div>
        <div className="utter-list">
          <div className="utter">
            <div className="speaker">say</div>
            "show me the <span className="ref">quote for Sarah</span>"
          </div>
          <div className="utter">
            <div className="speaker">or</div>
            "how am I doing on <span className="ref">re-pipe jobs</span> this month?"
          </div>
        </div>
      </div>
      <Mic variant="bar" />
      <Dock active="find" />
    </div>
  );
}

// ── State 10: live clock ──────────────────────────────────────────────
export function S2b_LiveClock() {
  return (
    <div className="screen">
      <Ribbon hat="Iolo · ⌂" signal="visit live · 02:14" />
      <div className="label-mono" style={{ marginBottom: 6 }}>
        clocked in · hours feeding analytics in real time
      </div>
      <div className="jobs-list">
        <div className="job-row activated live-clock-on">
          <div className="stage-tag">on-site</div>
          <div className="who">Akande Plumbing</div>
          <div className="what">visit V-441 · 02:14 · clocked in 11:46</div>
        </div>
        <div className="job-row">
          <div className="stage-tag">scheduled</div>
          <div className="who">Wendy Khumalo</div>
          <div className="what">burst-pipe · 14:48</div>
        </div>
        <div className="job-row">
          <div className="stage-tag">quoted</div>
          <div className="who">Sarah Okafor</div>
          <div className="what">kitchen re-pipe · awaiting accept</div>
        </div>
      </div>
      <div className="repl-foot">
        <span><span className="cmd">start visit</span> <span className="arg">V-441</span> <span style={{ color: 'var(--ink-faint)' }}>· 11:46:02</span></span>
        <span className="ghost">› clock running</span>
      </div>
      <Mic variant="bar" />
      <Dock active="home" activated={['home']} />
    </div>
  );
}

// ── Do picker (verb→object) ───────────────────────────────────────────
const VERBS = [
  { id: 'clock-in',   v: 'clock-in',   o: 'a visit',          cmd: 'start visit',       kind: 'visit',   from: ['scheduled'],                          stamps: 'started_at' },
  { id: 'clock-out',  v: 'clock-out',  o: 'the live visit',   cmd: 'complete visit',    kind: 'visit',   from: ['in_progress'],                        stamps: 'ended_at → hours' },
  { id: 'complete',   v: 'mark done',  o: 'a job',            cmd: 'complete job',      kind: 'job',     from: ['in_progress'],                        stamps: 'completed_at' },
  { id: 'raise-var',  v: 'raise',      o: 'a quote variance', cmd: 'supersede quote',   kind: 'quote',   from: ['draft', 'presented'],                 stamps: '—' },
  { id: 'send-quote', v: 'send',       o: 'a quote',          cmd: 'present quote',     kind: 'quote',   from: ['draft'],                              stamps: 'presented_at' },
  { id: 'invoice',    v: 'invoice',    o: 'a job',            cmd: 'invoice job',       kind: 'job',     from: ['completed'],                          stamps: 'invoiced_at' },
  { id: 'ratify',     v: 'ratify',     o: 'a lead',           cmd: 'ratify lead',       kind: 'lead',    from: ['pending'],                            stamps: 'ratified_at' },
  { id: 'mark-paid',  v: 'mark paid',  o: 'an invoice',       cmd: 'mark invoice paid', kind: 'invoice', from: ['sent', 'viewed', 'overdue', 'partial'], stamps: 'paid_at → time-to-pay' },
] as const;

type VerbKind = typeof VERBS[number]['kind'];

const OBJECTS: Record<VerbKind, { id: string; who: string; meta: string; state: string }[]> = {
  visit: [
    { id: 'V-441', who: 'Akande site',  meta: 'day 2/3 · scheduled 14:00', state: 'scheduled' },
    { id: 'V-440', who: 'Wendy K.',     meta: 'burst-pipe · 14:48',         state: 'scheduled' },
    { id: 'V-438', who: 'Sarah O.',     meta: 'kitchen survey',             state: 'completed' },
  ],
  job: [
    { id: 'OJ-2783', who: 'Akande Plumbing', meta: 'commercial · in progress', state: 'in_progress' },
    { id: 'OJ-2841', who: 'Wendy Khumalo',   meta: 'burst-pipe · scheduled',   state: 'scheduled' },
    { id: 'OJ-2710', who: 'Mr. Davies',      meta: 'tap replace · completed',  state: 'completed' },
  ],
  quote: [
    { id: 'Q-118', who: 'Sarah Okafor', meta: 'kitchen re-pipe · presented', state: 'presented' },
    { id: 'Q-117', who: 'M. Roberts',   meta: 'boiler swap · draft',         state: 'draft' },
  ],
  invoice: [
    { id: 'IV-309', who: 'Akande Plumbing', meta: 'milestone · sent · 9d', state: 'overdue' },
    { id: 'IV-307', who: 'Mr. Davies',      meta: '£180 · paid 11:02',     state: 'paid' },
  ],
  lead: [
    { id: 'L-22', who: 'J. Carmichael', meta: 'voice intake · 22m ago', state: 'pending' },
    { id: 'L-21', who: 'Old Bell pub',  meta: 'chat intake · 1h',       state: 'ratified' },
  ],
};

export function S10_DoPicker() {
  const [verbId, setVerbId] = useState<string>('clock-in');
  const [objId,  setObjId]  = useState<string>('V-441');
  const verb = VERBS.find(x => x.id === verbId)!;
  const objs = OBJECTS[verb.kind as VerbKind] || [];
  const target = objs.find(o => o.id === objId) || objs.find(o => (verb.from as readonly string[]).includes(o.state));

  return (
    <div className="screen">
      <Ribbon hat="Iolo · ⌂" signal="do · verb → object" />
      <div className="label-mono" style={{ marginBottom: 6 }}>
        <span className="accent">do</span> · pick a verb · the object falls into place
      </div>
      <div className="do-pick">
        <div className="do-col">
          <div className="do-col-hdr"><span>verbs</span><span className="accent">{VERBS.length}</span></div>
          <div className="do-col-body">
            {VERBS.map(x => (
              <div key={x.id}
                className={`verb-row ${verbId === x.id ? 'selected' : ''}`}
                onClick={() => {
                  setVerbId(x.id);
                  const next = (OBJECTS[x.kind as VerbKind] || []).find(o => (x.from as readonly string[]).includes(o.state));
                  if (next) setObjId(next.id);
                }}>
                <span className="v">{x.v}</span>
                <span className="o">{x.o}</span>
                <span className="ct">{(OBJECTS[x.kind as VerbKind] || []).filter(o => (x.from as readonly string[]).includes(o.state)).length}</span>
              </div>
            ))}
          </div>
        </div>
        <div className="do-col">
          <div className="do-col-hdr">
            <span><span className="accent">{verb.kind}</span>s · only {(verb.from as readonly string[]).join(' / ')} are legal</span>
            <span>{objs.filter(o => (verb.from as readonly string[]).includes(o.state)).length} valid</span>
          </div>
          <div className="do-col-body">
            {objs.map(o => {
              const legal = (verb.from as readonly string[]).includes(o.state);
              const isTarget = target && o.id === target.id;
              return (
                <div key={o.id}
                  className={`obj-row ${legal ? '' : 'dim'} ${isTarget ? 'target' : ''}`}
                  onClick={() => legal && setObjId(o.id)}>
                  <div>
                    <div className="who">{o.who}</div>
                    <div className="meta">{o.meta} · <span style={{ color: 'var(--ink-soft)' }}>{o.state}</span></div>
                  </div>
                  {o.state === 'in_progress' && verb.kind === 'visit' && (
                    <div className="live-clock">02:14 on site</div>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      </div>
      <div className="repl-foot">
        <span><span className="cmd">{verb.cmd}</span> <span className="arg">{target ? target.id : '—'}</span></span>
        <span className="ghost">stamps · {verb.stamps}</span>
      </div>
      <Mic variant="bar" />
      <Dock active="do" />
    </div>
  );
}

// ── DoFlip: shelf ⇄ picker card flip ─────────────────────────────────
export function DoFlip() {
  const [side, setSide] = useState<'shelf' | 'picker'>('shelf');
  const flipped = side === 'picker';
  return (
    <div className="do-flip-wrap">
      <div
        className="flip-chip"
        onClick={() => setSide(flipped ? 'shelf' : 'picker')}
        title={flipped ? 'back to the shelf for this job' : 'open the full verb→object picker'}
      >
        <span className="glyph" aria-hidden="true">⇄</span>
        <span className="lbl">{flipped ? 'shelf' : 'picker'}</span>
      </div>
      <div key={side} className="do-fade">
        {flipped ? <S10_DoPicker /> : <S8_DoShelf />}
      </div>
    </div>
  );
}

// ── Glyph key ─────────────────────────────────────────────────────────
export function GlyphKey() {
  const items = [
    { g: '⇄', t: 'Flip orientation',    d: 'On the do face: swap between the stage-shelf for this job and the full verb→object picker. Same actions, different framing.' },
    { g: '·', t: 'Soft separator',       d: 'Reads as breath, not punctuation. Used between meta fragments — "quoted · 14:21".' },
    { g: '—', t: 'Resolved value',       d: 'Anywhere a slot has been filled in the sentence-shaped grammar. Never decorative.' },
    { g: '▎', t: 'Pulse',               d: 'Quiet breath. Pulses on rest, on a clocked-in row, never anywhere else.' },
    { g: '→', t: 'Stage advance',        d: 'Used in stage trails (lead → quoted → on-site). Direction of progress, never navigation.' },
    { g: '⏵', t: 'Live clock',           d: 'Visit in_progress. Pip pulses · row writes minutes into hours-on-site.' },
  ];
  return (
    <div className="glyph-key">
      <h4>Glyph key</h4>
      {items.map((x, i) => (
        <div key={i} className="row">
          <div className="gly">{x.g}</div>
          <div className="copy">
            <b>{x.t}</b>
            <span>{x.d}</span>
          </div>
        </div>
      ))}
    </div>
  );
}

// ── Palette builder ───────────────────────────────────────────────────
export interface CustomPalette {
  activation: string;
  soft: string;
  hold: string;
  linear: string;
}

export function applyCustomPalette(c: CustomPalette) {
  const r = document.documentElement.style;
  r.setProperty('--activation', c.activation);
  r.setProperty('--activation-soft', c.soft);
  r.setProperty('--hold', c.hold);
  r.setProperty('--linear', c.linear);
}

export function PaletteBuilder({ palette, onChange }: {
  palette: CustomPalette;
  onChange: (p: CustomPalette) => void;
}) {
  const update = (key: keyof CustomPalette) => (e: React.ChangeEvent<HTMLInputElement>) => {
    const next = { ...palette, [key]: e.target.value };
    if (key === 'activation') {
      const m = e.target.value.match(/^#([0-9a-f]{6})$/i);
      if (m) {
        const r2 = parseInt(m[1].slice(0, 2), 16);
        const g  = parseInt(m[1].slice(2, 4), 16);
        const b  = parseInt(m[1].slice(4, 6), 16);
        next.soft = `rgba(${r2},${g},${b},0.18)`;
      }
    }
    onChange(next);
  };
  const rows: { key: keyof CustomPalette; label: string }[] = [
    { key: 'activation', label: 'Activation' },
    { key: 'hold',       label: 'Hold' },
    { key: 'linear',     label: 'Linear' },
  ];
  return (
    <div>
      {rows.map(({ key, label }) => (
        <div key={key} className="palette-row">
          <label>{label}</label>
          <input type="color" value={palette[key].startsWith('rgba') ? '#7fd9ff' : palette[key]} onChange={update(key)} />
          <span className="hex">{palette[key]}</span>
        </div>
      ))}
      <div className="palette-hint">
        select <b>custom</b> in the accent dropdown above to apply.<br />
        values persist into the design file.
      </div>
    </div>
  );
}

```
