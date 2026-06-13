---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/three/pod-hud.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.617237+00:00
---

# cartridges/jambox/web/src/three/pod-hud.ts

```ts
/**
 * PodHUD — floating fixed-position panel anchored to a selected drum pod.
 *
 * Shows type-specific controls for the selected drum track.  Every change
 * calls onParamChange so main.ts can pushCell + apply to audio in one place.
 * The HUD also has a step mini-strip showing the 16 steps for that track.
 */

import { DRUM_VOICE_PARAMS, type DrumVoiceType, type JamboxDrumTrackPayload } from '../semantic/objects';
import { PARAM_LABELS, paramNormalised } from '../grid/surface';
import type { ParamKey } from '../grid/surface';
import type { TrackName } from '../sequencer';
import type { JamboxWorld } from './jambox-world';

export interface PodHUDCallbacks {
  onStepToggle: (track: TrackName, stepIndex: number, on: boolean) => void;
  onParamChange: (track: TrackName, key: ParamKey, value: number) => void;
  onMuteToggle: (track: TrackName, mute: boolean) => void;
  onClose: () => void;
}

export class PodHUD {
  private el: HTMLDivElement;
  private track: TrackName | null = null;
  private podPos: { x: number; y: number; z: number } | null = null;
  private state: JamboxDrumTrackPayload | null = null;
  private world: JamboxWorld;
  private cb: PodHUDCallbacks;

  constructor(world: JamboxWorld, cb: PodHUDCallbacks) {
    this.world = world;
    this.cb = cb;
    this.el = this.build();
    document.body.appendChild(this.el);
  }

  private build(): HTMLDivElement {
    const el = document.createElement('div');
    el.className = 'pod-hud';
    el.innerHTML = `
      <div class="pod-hud-header">
        <span class="pod-hud-title">—</span>
        <button class="pod-hud-close">✕</button>
      </div>
      <div class="pod-hud-steps"></div>
      <div class="pod-hud-params"></div>
      <div class="pod-hud-channel">
        <label>VOL <input type="range" class="phud-vol" min="0" max="1" step="0.01" value="0.8"></label>
        <label>PAN <input type="range" class="phud-pan" min="-1" max="1" step="0.01" value="0"></label>
        <button class="phud-mute">MUTE</button>
      </div>
    `;

    el.querySelector('.pod-hud-close')!.addEventListener('click', () => {
      this.hide();
      this.cb.onClose();
    });

    return el;
  }

  show(track: TrackName, pos3d: { x: number; y: number; z: number }, state: JamboxDrumTrackPayload): void {
    this.track = track;
    this.podPos = pos3d;
    this.state = state;
    this.rebuildContent();
    this.el.classList.add('visible');
    this.updatePosition();
  }

  hide(): void {
    this.track = null;
    this.podPos = null;
    this.el.classList.remove('visible');
  }

  /** Called from main.ts animation frame to keep the HUD anchored to the pod. */
  tick(): void {
    if (this.el.classList.contains('visible')) this.updatePosition();
  }

  /** Refresh when a new cell arrives for the tracked track. */
  updateState(state: JamboxDrumTrackPayload): void {
    this.state = state;
    this.rebuildContent();
  }

  /** Called each sequencer step to highlight the active step. */
  setPlayheadStep(step: number): void {
    if (!this.el.classList.contains('visible')) return;
    const btns = this.el.querySelectorAll<HTMLButtonElement>('.phud-step');
    btns.forEach((b, i) => b.classList.toggle('active', i === step % 16));
  }

  private rebuildContent(): void {
    const state = this.state;
    const track = this.track;
    if (!state || !track) return;

    // Title
    (this.el.querySelector('.pod-hud-title') as HTMLElement).textContent =
      `${track.toUpperCase()} · ${state.voiceType}`;

    // Step strip
    const stepsEl = this.el.querySelector('.pod-hud-steps') as HTMLElement;
    stepsEl.innerHTML = '';
    for (let i = 0; i < 16; i++) {
      const btn = document.createElement('button');
      btn.className = 'phud-step' + (state.steps[i] ? ' on' : '');
      btn.dataset.step = String(i);
      const velBrightness = Math.round((state.velocities[i] / 127) * 100);
      btn.style.setProperty('--vel', `${velBrightness}%`);
      btn.addEventListener('click', () => {
        if (!this.track || !this.state) return;
        const on = !this.state.steps[i];
        this.state = { ...this.state, steps: this.state.steps.map((v, j) => j === i ? on : v) };
        btn.classList.toggle('on', on);
        this.cb.onStepToggle(this.track, i, on);
      });
      stepsEl.appendChild(btn);
    }

    // Voice params
    const paramsEl = this.el.querySelector('.pod-hud-params') as HTMLElement;
    paramsEl.innerHTML = '';
    const voiceParams = DRUM_VOICE_PARAMS[state.voiceType as DrumVoiceType] ?? [];
    // Exclude volume/pan — those are in the channel strip
    const displayParams = voiceParams.filter(k => k !== 'volume' && k !== 'pan');

    for (const key of displayParams) {
      const k = key as ParamKey;
      const rawValue = state[k] as number;
      const norm = paramNormalised(k, rawValue);

      const row = document.createElement('label');
      row.className = 'phud-param';

      const nameSpan = document.createElement('span');
      nameSpan.className = 'phud-param-name';
      nameSpan.textContent = PARAM_LABELS[k];

      const input = document.createElement('input');
      input.type = 'range';
      input.min = '0';
      input.max = '1';
      input.step = '0.01';
      input.value = String(norm);
      input.addEventListener('input', () => {
        if (!this.track) return;
        this.cb.onParamChange(this.track, k, parseFloat(input.value));
      });

      row.appendChild(nameSpan);
      row.appendChild(input);
      paramsEl.appendChild(row);
    }

    // Channel strip
    const volInput = this.el.querySelector<HTMLInputElement>('.phud-vol')!;
    volInput.value = String(state.volume);
    volInput.oninput = () => {
      if (this.track) this.cb.onParamChange(this.track, 'volume', parseFloat(volInput.value));
    };

    const panInput = this.el.querySelector<HTMLInputElement>('.phud-pan')!;
    panInput.value = String(state.pan);
    panInput.oninput = () => {
      if (this.track) this.cb.onParamChange(this.track, 'pan', parseFloat(panInput.value));
    };

    const muteBtn = this.el.querySelector<HTMLButtonElement>('.phud-mute')!;
    muteBtn.classList.toggle('on', state.mute);
    muteBtn.onclick = () => {
      if (!this.track || !this.state) return;
      const mute = !this.state.mute;
      this.state = { ...this.state, mute };
      muteBtn.classList.toggle('on', mute);
      this.cb.onMuteToggle(this.track, mute);
    };
  }

  private updatePosition(): void {
    if (!this.podPos) return;
    const screen = this.world.projectToScreen(this.podPos);
    const W = window.innerWidth;
    const H = window.innerHeight;
    const hudW = 240;
    const hudH = this.el.offsetHeight || 300;
    let x = screen.x + 24;
    let y = screen.y - hudH / 2;
    if (x + hudW > W - 8) x = screen.x - hudW - 24;
    y = Math.max(8, Math.min(H - hudH - 8, y));
    this.el.style.left = `${x}px`;
    this.el.style.top = `${y}px`;
  }

  dispose(): void {
    this.el.remove();
  }
}

```
