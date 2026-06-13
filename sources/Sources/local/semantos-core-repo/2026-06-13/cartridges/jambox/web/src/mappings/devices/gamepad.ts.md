---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/mappings/devices/gamepad.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.631385+00:00
---

# cartridges/jambox/web/src/mappings/devices/gamepad.ts

```ts
/**
 * D-C.2 Gamepad device adapter.
 *
 * Uses the Gamepad API (polling via requestAnimationFrame).
 * Hard rule: only emits DeviceEvent — never jam.* cells directly.
 */

import type { DeviceEvent } from '../router';

export type GamepadDeviceListener = (event: DeviceEvent) => void;

export interface GamepadAdapterOptions {
  onEvent: GamepadDeviceListener;
  onDeviceConnect?: (deviceName: string) => void;
  onDeviceDisconnect?: (deviceName: string) => void;
  /** Dead zone for axes (0..1). Default 0.1. */
  deadZone?: number;
}

interface GamepadState {
  buttons: boolean[];
  axes: number[];
}

export class GamepadAdapter {
  private readonly prevState = new Map<number, GamepadState>();
  private rafId: number | null = null;
  private readonly deadZone: number;

  constructor(private readonly opts: GamepadAdapterOptions) {
    this.deadZone = opts.deadZone ?? 0.1;
  }

  start(): void {
    window.addEventListener('gamepadconnected', this.onConnect);
    window.addEventListener('gamepaddisconnected', this.onDisconnect);
    this.poll();
  }

  stop(): void {
    if (this.rafId !== null) cancelAnimationFrame(this.rafId);
    window.removeEventListener('gamepadconnected', this.onConnect);
    window.removeEventListener('gamepaddisconnected', this.onDisconnect);
    this.rafId = null;
  }

  private readonly onConnect = (e: GamepadEvent) => {
    const name = e.gamepad.id;
    this.opts.onDeviceConnect?.(name);
    this.prevState.set(e.gamepad.index, { buttons: [], axes: [] });
  };

  private readonly onDisconnect = (e: GamepadEvent) => {
    this.opts.onDeviceDisconnect?.(e.gamepad.id);
    this.prevState.delete(e.gamepad.index);
  };

  private poll = (): void => {
    const gamepads = navigator.getGamepads ? navigator.getGamepads() : [];
    const ts = Date.now();

    for (const gp of gamepads) {
      if (!gp) continue;
      const prev = this.prevState.get(gp.index) ?? { buttons: [], axes: [] };
      const name = gp.id;

      // Buttons
      for (let i = 0; i < gp.buttons.length; i++) {
        const pressed = gp.buttons[i]!.pressed;
        const wasPrev = prev.buttons[i] ?? false;
        if (pressed !== wasPrev) {
          this.opts.onEvent({
            kind: pressed ? 'gamepad.button.on' : 'gamepad.button.off',
            selector: `btn${i}`,
            value: pressed ? gp.buttons[i]!.value : 0,
            deviceName: name,
            ts,
          });
        }
      }

      // Axes
      for (let i = 0; i < gp.axes.length; i++) {
        const raw = gp.axes[i]!;
        const value = Math.abs(raw) < this.deadZone ? 0 : raw;
        const prevAxis = prev.axes[i] ?? 0;
        if (Math.abs(value - prevAxis) > 0.01) {
          this.opts.onEvent({
            kind: 'gamepad.axis',
            selector: `axis${i}`,
            value,
            deviceName: name,
            ts,
          });
        }
      }

      this.prevState.set(gp.index, {
        buttons: gp.buttons.map((b) => b.pressed),
        axes: [...gp.axes],
      });
    }

    this.rafId = requestAnimationFrame(this.poll);
  };
}

/** Convenience: create and start a gamepad adapter. Returns stop() function. */
export function attachGamepadAdapter(opts: GamepadAdapterOptions): () => void {
  const adapter = new GamepadAdapter(opts);
  adapter.start();
  return () => adapter.stop();
}

```
