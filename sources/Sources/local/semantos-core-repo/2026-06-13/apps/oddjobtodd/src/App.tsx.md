---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/apps/oddjobtodd/src/App.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:19.051015+00:00
---

# apps/oddjobtodd/src/App.tsx

```tsx
import { useEffect } from 'react';
import { useTweaks, TweaksPanel, TweakSection, TweakSelect, TweakRadio, TweakToggle } from './components/TweaksPanel';
import { Frame, StageTrail } from './components/HelmPrimitives';
import {
  S1_Rest, S2_Activation, S3_Voice, S4_Thumb, S5_Gate, S6_Artifact,
  S7_Reference, S9_FindShelf, S2b_LiveClock, DoFlip, GlyphKey,
  PaletteBuilder, applyCustomPalette, type CustomPalette,
} from './components/HelmScreens';

const ACCENT_PRESETS: Record<string, { activation: string; soft: string }> = {
  ice:    { activation: '#7fd9ff', soft: 'rgba(127,217,255,0.16)' },
  pulse:  { activation: '#b18bff', soft: 'rgba(177,139,255,0.18)' },
  signal: { activation: '#6fd6b5', soft: 'rgba(111,214,181,0.18)' },
  ember:  { activation: '#ffb24a', soft: 'rgba(255,178,74,0.18)' },
  bone:   { activation: '#e7eef5', soft: 'rgba(231,238,245,0.10)' },
};

function applyAccent(name: string) {
  const p = ACCENT_PRESETS[name] || ACCENT_PRESETS.ice;
  document.documentElement.style.setProperty('--activation', p.activation);
  document.documentElement.style.setProperty('--activation-soft', p.soft);
}

const DEFAULT_PALETTE: CustomPalette = {
  activation: '#c9a96e',
  soft: 'rgba(201,169,110,0.18)',
  hold: '#5a6f8a',
  linear: '#ffb24a',
};

interface Tweaks extends Record<string, unknown> {
  showStates: string;
  voiceVariant: string;
  showVoiceVariations: boolean;
  linearGate: string;
  accent: string;
  mode: string;
  customPalette: CustomPalette;
}

const TWEAK_DEFAULTS: Tweaks = {
  showStates: 'all',
  voiceVariant: 'fab',
  showVoiceVariations: false,
  linearGate: 'slide',
  accent: 'ice',
  mode: 'night',
  customPalette: DEFAULT_PALETTE,
};

function StateRow({ title, sub, children }: { title: string; sub: string; children: React.ReactNode }) {
  return (
    <section className="section">
      <h2 className="section-title">{title}</h2>
      <div className="section-meta">{sub}</div>
      <div className="section-row">{children}</div>
    </section>
  );
}

export default function App() {
  const [tweaks, setTweak] = useTweaks<Tweaks>(TWEAK_DEFAULTS);

  useEffect(() => {
    if (tweaks.accent === 'custom') applyCustomPalette(tweaks.customPalette);
    else applyAccent(tweaks.accent);
  }, [tweaks.accent, tweaks.customPalette]);

  useEffect(() => {
    document.documentElement.setAttribute('data-mode', tweaks.mode || 'night');
  }, [tweaks.mode]);

  const voiceVariants = tweaks.showVoiceVariations
    ? ['fab', 'edge', 'bar', 'hidden']
    : [tweaks.voiceVariant];
  const gates = [tweaks.linearGate];
  const show = (k: string) => tweaks.showStates === 'all' || tweaks.showStates === k;

  return (
    <div className="canvas">
      <div className="mode-pill">
        <button className={tweaks.mode === 'night' ? 'on' : ''} onClick={() => setTweak('mode', 'night')}>night</button>
        <button className={tweaks.mode === 'day' ? 'on' : ''} onClick={() => setTweak('mode', 'day')}>day</button>
      </div>

      <header className="canvas-header">
        <div className="meta">oddjobz · helm v7 · the helm is a thumbable face on the REPL</div>
        <h1>Verbs against objects. Both ways round.</h1>
        <p>
          The CLI is the truth — <span style={{ fontFamily: 'var(--mono)' }}>start visit V-441</span>, <span style={{ fontFamily: 'var(--mono)' }}>mark invoice paid IV-309</span>.
          The helm just gives the thumb a way to walk it: <span style={{ fontFamily: 'var(--mono)' }}>do</span> picks a verb and offers the legal objects;
          <span style={{ fontFamily: 'var(--mono)' }}> find</span> picks an object and shows what's been done to it.
          Every transition stamps a timestamp; clocks running in <span style={{ fontFamily: 'var(--mono)' }}>do</span> feed the analytics on the back of the <span style={{ fontFamily: 'var(--mono)' }}>find</span> cards.
        </p>
      </header>

      {show('rest') && (
        <StateRow title="① Helm at rest" sub="presence, not demand">
          <Frame label="At rest" sub="presence, not progress"
            annotation="The breath is just a pulse. No tabs, no pinned objects, no FSMs. The dock is the only structure.">
            <S1_Rest voice={tweaks.voiceVariant} />
          </Frame>
        </StateRow>
      )}

      {show('activation') && (
        <StateRow title="② Loom activation · home is your live jobs" sub="each row is a job at its current stage · no notification, no badge">
          <Frame label="Home" sub="jobs at their stage"
            annotation="Stage tags (quoted / on-site / paid) replace tabs. The loom surfaces a candidate at the top — walk it or let it go.">
            <S2_Activation voice={tweaks.voiceVariant} />
          </Frame>
        </StateRow>
      )}

      {show('voice') && (
        <StateRow title="③ Talk · composing a new job" sub="voice resolves into the sentence · 3 of 5 held">
          {voiceVariants.map(v => (
            <Frame key={v} label={`Voice · ${v}`}
              sub={({ fab: 'always-present mic', edge: 'ambient swipe-up', bar: 'voice-default bar', hidden: 'hotword only' } as Record<string, string>)[v]}
              annotation="Same sentence shape voice fills and thumb walks.">
              <S3_Voice />
            </Frame>
          ))}
        </StateRow>
      )}

      {show('thumb') && (
        <StateRow title="④ Thumb · same sentence, deliberate selection" sub="never lost mid-articulation · topology unchanged">
          <Frame label="Thumb · resolving WHO" sub="grammar slot picker"
            annotation="Thumb walks the slots one at a time. Voice resolves them in any order. Same shape.">
            <S4_Thumb />
          </Frame>
        </StateRow>
      )}

      {show('gate') && (
        <StateRow title="⑤ Commit gate · cannot be undone" sub="economic action · no jargon, no FSM exposed">
          {gates.map(g => (
            <Frame key={g}
              label={({ hold: 'Hold to commit', slide: 'Slide to commit', twostep: 'Arm → commit', shift: 'Single tap' } as Record<string, string>)[g]}
              sub="LINEAR · cannot undo"
              annotation={({
                hold:    'Hold-ring fills over 1.2s. Generous, hard to fire by accident.',
                slide:   'Mechanical: the channel literally opens.',
                twostep: 'Arm decouples from commit. Two beats, one hand.',
                shift:   'Lowest friction. Use only when worth ≤ trust.',
              } as Record<string, string>)[g]}>
              <S5_Gate gate={g} />
            </Frame>
          ))}
        </StateRow>
      )}

      {show('artifact') && (
        <StateRow title="⑥ Composed job · stage trail" sub="no FSM, no channel state · just where the job is">
          <Frame label="Job in flight" sub="lead → … → paid"
            annotation="The 8-state metering FSM is hidden. The trail tradies recognise — quoted, scheduled, on-site, done, invoiced, paid — is the only surface.">
            <S6_Artifact voice={tweaks.voiceVariant} />
          </Frame>
          <Frame label="Stage trail · alone" sub="the only progress vocabulary"
            annotation="Same trail at full size. Each step is a place, not a state. The same shape works for every vertical.">
            <div className="screen">
              <div style={{ padding: '20px 4px' }}>
                <div className="label-mono" style={{ marginBottom: 16 }}>job · #OJ-2841 · stage trail</div>
                <StageTrail at="sched" withWhen={{ lead: '13:58', quote: '14:21', sched: '14:32 · now' }} />
              </div>
            </div>
          </Frame>
        </StateRow>
      )}

      {show('reference') && (
        <StateRow title="⑦ Talk · referencing existing objects" sub='"show me the quote for Sarah" · "add a line item to the quote for Sarah"'>
          <Frame label="Voice · find" sub="recall by reference"
            annotation="Voice reaches the quote object directly. No tab, no list, no menu. The reference highlight is the resolution.">
            <S7_Reference scenario="show" />
          </Frame>
          <Frame label="Voice · do" sub="verb against object"
            annotation="Same reference, but with a verb. The change is staged into a hold-to-confirm — LINEAR edits to live customer-facing objects still gate.">
            <S7_Reference scenario="edit" />
          </Frame>
        </StateRow>
      )}

      {show('doshelf') && (
        <StateRow title="⑧ Do · shelf ⇄ picker" sub="front: stage-aware shelf for this job · back: full verb→object grid · same actions, different framing">
          <Frame label="Do · shelf" sub="flip the chip (top-left) to swap orientation"
            annotation="Front: the shelf only shows what's possible from the current stage. Back: pick a verb, see legal objects. The chip glyph ⇄ means orientation-swap — same actions live on both sides.">
            <DoFlip />
          </Frame>
        </StateRow>
      )}

      {show('liveclock') && (
        <StateRow title="⑩ Live clock · hours feed analytics" sub="a clocked-in visit pulses on home · the REPL footer shows what fired">
          <Frame label="Home · clock live" sub="02:14 on Akande site"
            annotation="start visit V-441 stamped started_at at 11:46. The pip pulses on the row, the visit is in_progress, and every minute writes into hours-on-site → feeds back into the variance/margin numbers on the find card.">
            <S2b_LiveClock />
          </Frame>
        </StateRow>
      )}

      {show('findshelf') && (
        <StateRow title="⑨ Find · list-first · flip a row for performance" sub="results need to land somewhere · each card is two-sided">
          <Frame label="Find shelf · list" sub="tap a row to flip it"
            annotation="List is the default — the perf lens is per-row. Front face = the object reference. Back face = how this object is performing against the business: margin, time-to-pay, win likelihood, overrun risk.">
            <S9_FindShelf />
          </Frame>
        </StateRow>
      )}

      <div className="legend">
        <h4>The shift from v2</h4>
        <div className="item"><div className="swatch activation" /><div><b>Stages, not states</b>lead → quote → scheduled → on-site → done → invoiced → paid. The 8-state metering FSM is hidden plumbing.</div></div>
        <div className="item"><div className="swatch hold" /><div><b>Objects are nouns</b>jobs, quotes, visits, invoices, customers — reached via voice or via <em>find</em>. Never tabs.</div></div>
        <div className="item"><div className="swatch linear" /><div><b>Verbs compose</b>do / talk / find each address objects. Voice fires the same verbs the shelf shows the thumb.</div></div>
        <div className="item"><div className="swatch ink" /><div><b>Reference highlight</b>"the quote for Sarah" lights up as a resolved object — that highlight is the find result.</div></div>
        <div className="item"><div className="swatch dashed" /><div><b>Edits gate</b>verbs against live customer-facing objects still pass through hold-to-confirm. LINEAR rules apply.</div></div>
      </div>

      <GlyphKey />

      <div className="footer-note">
        <span>4-node topology</span>
        <span>voice ≡ thumb · verbs compose</span>
        <span>nouns reached, not pinned</span>
        <span>stages, not state machines</span>
      </div>

      <TweaksPanel title="Tweaks">
        <TweakSection title="States">
          <TweakSelect label="Show" value={tweaks.showStates} onChange={v => setTweak('showStates', v)}
            options={[
              ['all',        'All states'],
              ['rest',       '① At rest'],
              ['activation', '② Home / live jobs'],
              ['voice',      '③ Talk · composing'],
              ['thumb',      '④ Thumb · composing'],
              ['gate',       '⑤ Commit gate'],
              ['artifact',   '⑥ Composed job'],
              ['reference',  '⑦ Voice referencing'],
              ['doshelf',    '⑧ Do · shelf ⇄ picker'],
              ['findshelf',  '⑨ Find · list'],
              ['liveclock',  '⑩ Live clock'],
            ]}
          />
        </TweakSection>

        <TweakSection title="Voice affordance">
          <TweakToggle label="Show all 4 voice variations on ③"
            value={tweaks.showVoiceVariations}
            onChange={v => setTweak('showVoiceVariations', v)} />
          <TweakRadio label="Voice in other states" value={tweaks.voiceVariant}
            onChange={v => setTweak('voiceVariant', v)}
            options={[['fab', 'FAB'], ['edge', 'Edge'], ['bar', 'Bar'], ['hidden', 'Hidden']]} />
        </TweakSection>

        <TweakSection title="Commit gate">
          <TweakRadio label="Gate variant" value={tweaks.linearGate}
            onChange={v => setTweak('linearGate', v)}
            options={[['hold', 'Hold'], ['slide', 'Slide'], ['twostep', 'Arm/Commit'], ['shift', 'Shift']]} />
        </TweakSection>

        <TweakSection title="Mode">
          <TweakRadio label="Day / Night" value={tweaks.mode}
            onChange={v => setTweak('mode', v)}
            options={[['night', 'Night'], ['day', 'Day']]} />
        </TweakSection>

        <TweakSection title="Theme">
          <TweakSelect label="Accent overlay" value={tweaks.accent}
            onChange={v => setTweak('accent', v)}
            options={[
              ['ice',    'Ice cyan (default)'],
              ['pulse',  'Pulse violet'],
              ['signal', 'Signal green'],
              ['ember',  'Ember amber'],
              ['bone',   'Bone (mono)'],
              ['custom', 'Custom — use palette below'],
            ]}
          />
          <PaletteBuilder
            palette={tweaks.customPalette}
            onChange={p => {
              setTweak('customPalette', p);
              if (tweaks.accent === 'custom') applyCustomPalette(p);
            }}
          />
        </TweakSection>
      </TweaksPanel>
    </div>
  );
}

```
