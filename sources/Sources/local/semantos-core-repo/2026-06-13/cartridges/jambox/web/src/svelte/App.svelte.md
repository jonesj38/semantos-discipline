---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/svelte/App.svelte
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.608267+00:00
---

# cartridges/jambox/web/src/svelte/App.svelte

```svelte
<script lang="ts">
  import './app.css';
  import TapOverlay from './components/TapOverlay.svelte';
  import BrandBar from './components/BrandBar.svelte';
  import Anchor from './components/Anchor.svelte';
  import RackButtons from './components/RackButtons.svelte';
  import StageHead from './components/StageHead.svelte';
  import PadGrid from './components/PadGrid.svelte';
  import SupportShelf from './components/SupportShelf.svelte';
  import PeerRail from './components/PeerRail.svelte';
  import HintStrip from './components/HintStrip.svelte';
  import TweaksPanel from './components/TweaksPanel.svelte';
  import AnchorModal from './components/AnchorModal.svelte';
  import { startAudio, playDrum, playNote } from '../audio.js';
  import type { DrumKind } from '../audio.js';
  import type { ScaleId, ScalePalette, LabelMode } from './lib/scale-colour.js';
  import { PhoenixSync, type PeerInfo } from './lib/phoenix-sync.js';
  import { intentReducer } from '../grid/intent-reducer.js';
  import { SCALE_INTERVALS } from './lib/scale-colour.js';

  type DrumTrack = 'kick'|'snare'|'hat'|'clap'|'cb'|'tom'|'sub'|'perc';

  const STARTER_KIT: Record<DrumTrack, number[]> = {
    kick:  [1,0,0,0, 1,0,0,0, 1,0,0,0, 1,0,0,0],
    snare: [0,0,0,0, 1,0,0,0, 0,0,0,0, 1,0,0,0],
    hat:   [1,0,1,0, 1,0,1,0, 1,0,1,0, 1,0,1,0],
    clap:  [0,0,0,0, 0,0,0,0, 0,0,0,0, 1,0,0,0],
    cb:    [0,0,0,0, 0,0,0,0, 0,0,0,1, 0,0,0,0],
    tom:   Array(16).fill(0),
    sub:   Array(16).fill(0),
    perc:  [0,0,1,0, 0,0,0,1, 0,0,1,0, 0,1,0,0],
  };

  const RACK_MODES: Record<string, string[]> = {
    rhythm: ['STEP','PARAM'],
    melody: ['NOTE','MIX'],
    bass:   ['BASS','MIX'],
    chord:  ['PLAY','SEQ'],
  };

  // ── Tweaks ────────────────────────────────────────────────────────────────
  interface Tweaks {
    palette: ScalePalette;
    labelMode: LabelMode;
    viewport: string;
    density: string;
    accent: string;
    scaleLock: boolean;
    scaleRemap: boolean;
    showJambox: boolean;
    aesthetic: string;
    anchorVariant: string;
    root: number;
    scale: ScaleId;
  }

  let tweaks = $state<Tweaks>({
    palette: 'boomwhacker',
    labelMode: 'number',
    viewport: 'desktop',
    density: 'standard',
    accent: 'amber',
    scaleLock: true,
    scaleRemap: false,
    showJambox: false,
    aesthetic: 'current',
    anchorVariant: 'orb',
    root: 0,
    scale: 'major',
  });

  function setTweak<K extends keyof Tweaks>(key: K, value: Tweaks[K]) {
    tweaks = { ...tweaks, [key]: value };
  }

  // ── Transport state ───────────────────────────────────────────────────────
  let tapped    = $state(false);
  let playing   = $state(false);
  let bpm       = $state(120);
  let scene     = $state('A');
  let recording = $state(false);

  // ── Rack state ────────────────────────────────────────────────────────────
  let activeRack = $state('rhythm');
  let modeIdx    = $state<Record<string, number>>({ rhythm:0, melody:0, bass:0 });

  // Step page for rhythm mode: 0 = steps 0–7, 1 = steps 8–15
  let stepPage = $state<0 | 1>(0);

  // Active drum track for sequencer shelf
  let activeTrack = $state('kick');

  // Overlay latch state (from intent reducer) — passed down to PadGrid for control pad tinting
  let overlayLatched = $state<string | null>(null);

  // ── Room / peer state ─────────────────────────────────────────────────────
  // Room ID from URL: /room/<id>  →  use that id; anything else → default room.
  // This lets world.semantos.me/room/my-band be a separate persistent room.
  function roomFromPath(): string {
    if (typeof location === 'undefined') return 'lobby';
    const m = location.pathname.match(/^\/room\/([a-z0-9][a-z0-9_-]{1,48}[a-z0-9])$/i);
    return m ? m[1].toLowerCase() : 'lobby';
  }
  const ROOM_ID = roomFromPath();
  const HANDLE  = typeof crypto !== 'undefined'
    ? 'guest-' + crypto.getRandomValues(new Uint8Array(3)).reduce((s,b) => s + b.toString(16).padStart(2,'0'), '')
    : 'guest';

  let connected    = $state(false);
  let peers        = $state<PeerInfo[]>([]);
  let showAnchor   = $state(false);

  const roomSync = new PhoenixSync(ROOM_ID, HANDLE, {
    onStatus(s) {
      connected = s === 'open';
    },
    onBeat(info) {
      // Snap beatFrac to server quarter-note position (×4 = 16th-note steps).
      // The rAF loop continues to run for smooth in-between animation.
      if (info.beat) {
        const serverStep = (info.beat * 4) % 16;
        const localStep  = Math.floor(beatFrac) % 16;
        const drift      = Math.abs(serverStep - localStep);
        if (drift > 0.5 && drift < 15.5) beatFrac = serverStep;
      }
      // Follow server bpm if it differs by more than 1%
      if (info.bpm && Math.abs(info.bpm - bpm) / bpm > 0.01) bpm = info.bpm;
    },
    onRemoteTrigger(track, vel) {
      try { playDrum(track as DrumKind, vel); } catch {}
    },
    onRemoteNote(pitch, vel, duration) {
      try {
        const hz = 440 * Math.pow(2, (pitch - 69) / 12);
        playNote(hz, vel, duration);
      } catch {}
    },
    onPresence(list) {
      peers = list;
    },
    onSnapshot(cells) {
      // Late-join replay: merge drum pattern cells from NATS into drumState.
      // A cell with kind:"drum" carries { track, steps } — last-write wins per track.
      const next = { ...drumState };
      let changed = false;
      for (const raw of cells) {
        const c = raw as Record<string, unknown>;
        if (c['kind'] !== 'drum') continue;
        const track  = c['track']  as string | undefined;
        const steps  = c['steps']  as number[] | undefined;
        if (track && Array.isArray(steps) && track in next) {
          (next as Record<string, number[]>)[track] = steps.slice(0, 16);
          changed = true;
        }
      }
      if (changed) drumState = next as typeof drumState;
    },
  });

  let drumState = $state<Record<DrumTrack, number[]>>({
    kick:  Array(16).fill(0), snare: Array(16).fill(0),
    hat:   Array(16).fill(0), clap:  Array(16).fill(0),
    cb:    Array(16).fill(0), tom:   Array(16).fill(0),
    sub:   Array(16).fill(0), perc:  Array(16).fill(0),
  });
  let melodyOn = $state<Record<string, number>>({});
  let bassOn   = $state<Record<string, number>>({});
  let chordOn  = $state<Record<string, number>>({}); // pitch → timestamp when lit
  let beat     = $state(0);

  // ── Transport loop ────────────────────────────────────────────────────────
  let rafId: number | null = null;
  let lastTick = 0;
  let beatFrac = 0;
  let lastStep = -1;

  function startLoop() {
    function tick(t: number) {
      if (!lastTick) lastTick = t;
      const dt = (t - lastTick) / 1000;
      lastTick = t;
      const stepsPerSec = (bpm / 60) * 4;
      beatFrac = (beatFrac + dt * stepsPerSec) % 16;
      beat = beatFrac;

      const cur = Math.floor(beatFrac) % 16;
      if (cur !== lastStep) {
        lastStep = cur;
        for (const [trk, steps] of Object.entries(drumState)) {
          if (steps[cur]) {
            try { playDrum(trk as DrumKind, 0.9); } catch {}
            // Broadcast to peers (no-op when not connected)
            roomSync.sendTrigger(trk, 0.9);
          }
        }
      }
      rafId = requestAnimationFrame(tick);
    }
    rafId = requestAnimationFrame(tick);
  }

  function stopLoop() {
    if (rafId !== null) { cancelAnimationFrame(rafId); rafId = null; }
    lastTick = 0;
  }

  function togglePlay() {
    startAudio();
    if (playing) { stopLoop(); playing = false; }
    else { playing = true; startLoop(); }
  }

  function handleTap() {
    startAudio();
    drumState = { ...STARTER_KIT };
    playing = true;
    beatFrac = 0; lastStep = -1;
    startLoop();
    // Attempt room connection — non-fatal if relay is unreachable
    try {
      roomSync.connect();
      // Start the server clock so all peers share the same beat grid.
      // Small delay to let the WS handshake complete first.
      setTimeout(() => roomSync.sendBpm(bpm), 800);
    } catch {}
    setTimeout(() => { tapped = true; }, 480);
  }

  const scenes = ['A','B','C','D'];
  function cycleScene() {
    const idx = scenes.indexOf(scene);
    scene = scenes[(idx + 1) % scenes.length];
  }

  // ── Control-pad intent routing ────────────────────────────────────────────
  function handleControlPad(selector: string) {
    // Build scale degree set for the current key/scale
    const intervals = SCALE_INTERVALS[tweaks.scale] ?? SCALE_INTERVALS.major;
    const degrees = new Set(intervals);

    const ev = {
      inputType: 'pad' as const,
      selector,
      value: 1,
      deviceName: 'pad-grid',
      ts: Date.now(),
    };

    intentReducer.trackHold(ev, true);
    const result = intentReducer.reduce(ev, activeMode, 'pad-grid', {
      root: tweaks.root,
      degrees,
    });

    // Update overlayLatched from the reducer's internal state after mutation
    const state = intentReducer.getOverlayState();
    overlayLatched = state.latched;

    // Momentary overlays also update the tint
    if (result.kind === 'momentary' && result.overlayId) {
      overlayLatched = result.overlayId;
    }

    // Simulate release for control pads (they don't hold)
    const releaseEv = { ...ev, value: 0 };
    intentReducer.trackHold(releaseEv, false);
  }

  // ── Derived live-state for rack mini-bars ─────────────────────────────────
  const racksLive = $derived({
    rhythm: drumState.kick.map((v, i) =>
      v || drumState.snare[i] || drumState.hat[i] || drumState.clap[i]
    ),
    melody: Array(16).fill(0) as number[],
    bass:   Array(16).fill(0) as number[],
    chord:  Array(16).fill(0) as number[],
  });

  const activeMode = $derived(RACK_MODES[activeRack]?.[modeIdx[activeRack] ?? 0] ?? '');

  // Keyboard shortcuts + cleanup
  import { onMount } from 'svelte';
  onMount(() => {
    function onKey(e: KeyboardEvent) {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLSelectElement) return;
      if (e.code === 'Space') { e.preventDefault(); if (tapped) togglePlay(); }
      if (e.key === '1') activeRack = 'rhythm';
      if (e.key === '2') activeRack = 'melody';
      if (e.key === '3') activeRack = 'bass';
    }
    window.addEventListener('keydown', onKey);
    return () => {
      window.removeEventListener('keydown', onKey);
      stopLoop();
      roomSync.disconnect();
    };
  });
</script>

<div
  class="app-root"
  data-viewport={tweaks.viewport}
  data-density={tweaks.density}
  data-accent={tweaks.accent}
  data-aesthetic={tweaks.aesthetic}
>
  {#if !tapped}
    <TapOverlay onTap={handleTap} />
  {/if}

  <BrandBar roomId={ROOM_ID} {connected} />

  <Anchor
    {playing}
    {bpm}
    {scene}
    {beat}
    {recording}
    density={racksLive.rhythm}
    anchorVariant={tweaks.anchorVariant as 'orb'|'dial'|'wave'}
    onTogglePlay={togglePlay}
    onBpmChange={(v) => { bpm = v; roomSync.sendBpm(v); roomSync.commitCell({ kind: 'bpm', bpm: v }); }}
    onSceneCycle={cycleScene}
    onToggleRec={() => { recording = !recording; }}
    onCapture={() => { showAnchor = true; }}
  />

  <RackButtons
    active={activeRack}
    {modeIdx}
    {racksLive}
    {beat}
    onSelect={(id) => { activeRack = id; }}
    onSecondary={(id) => { modeIdx = { ...modeIdx, [id]: ((modeIdx[id] ?? 0) + 1) % 2 }; }}
  />

  <div class="app-grid">
    <div>
      <div class="stage">
        <StageHead
          {activeRack}
          {activeMode}
          root={tweaks.root}
          scale={tweaks.scale}
          scaleLock={tweaks.scaleLock}
          scaleRemap={tweaks.scaleRemap}
          onRootChange={(v) => setTweak('root', v)}
          onScaleChange={(v) => setTweak('scale', v)}
          onScaleRemapToggle={() => setTweak('scaleRemap', !tweaks.scaleRemap)}
        />
        <PadGrid
          {activeRack}
          {modeIdx}
          palette={tweaks.palette}
          scale={tweaks.scale}
          root={tweaks.root}
          labelMode={tweaks.labelMode}
          scaleLock={tweaks.scaleLock}
          scaleRemap={tweaks.scaleRemap}
          {beat}
          {stepPage}
          setStepPage={(p) => { stepPage = p; }}
          {overlayLatched}
          {drumState}
          setDrumState={(s) => {
            // Persist whichever track changed to NATS
            const changed = (Object.keys(s) as DrumTrack[]).find(
              (t) => s[t] !== drumState[t]
            );
            drumState = s;
            if (connected && changed) {
              roomSync.commitCell({ kind: 'drum', track: changed, steps: s[changed] });
            }
          }}
          {melodyOn}
          setMelodyOn={(f) => { melodyOn = f(melodyOn); }}
          {bassOn}
          setBassOn={(f) => { bassOn = f(bassOn); }}
          {chordOn}
          setChordOn={(f) => { chordOn = f(chordOn); }}
          onNote={(pitch, vel, duration, mode) => roomSync.sendNote(pitch, vel, duration, mode)}
          onControlPad={handleControlPad}
        />
      </div>
      <HintStrip {connected} peerCount={peers.length} />
    </div>

    <div class="sidebar">
      <PeerRail {bpm} {peers} />
      <SupportShelf
        {activeRack}
        {beat}
        {stepPage}
        {activeTrack}
        setActiveTrack={(t) => { activeTrack = t; }}
        {drumState}
        setDrumState={(s) => { drumState = s; }}
      />
    </div>
  </div>

  {#if showAnchor}
    <AnchorModal
      {bpm}
      {scene}
      roomId={ROOM_ID}
      peers={peers.map(p => p.id)}
      onClose={() => { showAnchor = false; }}
    />
  {/if}

  <TweaksPanel {tweaks} onTweak={setTweak} />
</div>

<style>
  .app-root {
    min-height: 100vh;
    padding: 18px 24px 80px;
    max-width: 1480px;
    margin: 0 auto;
    position: relative;
  }
  [data-viewport="tablet"] { max-width: 900px; padding: 14px 16px 60px; }
  [data-viewport="mobile"] { max-width: 414px; padding: 10px 10px 80px; }

  .app-grid {
    display: grid;
    grid-template-columns: 1fr 240px;
    gap: 18px;
    align-items: start;
    margin-top: 0;
  }
  .stage {
    background: linear-gradient(180deg, var(--ink-2), var(--ink-1));
    border: 1px solid var(--line);
    border-radius: 16px;
    padding: 22px;
    position: relative;
  }
  .sidebar { display: flex; flex-direction: column; gap: 14px; }

  @media (max-width: 900px) {
    .app-grid { grid-template-columns: 1fr; }
    .sidebar { display: none; }
  }
</style>

```
