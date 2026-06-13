---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/three/interaction-router.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.617856+00:00
---

# cartridges/jambox/web/src/three/interaction-router.ts

```ts
/**
 * D-E.1 — InteractionRouter: translates picker hits into canonical jam.* cells.
 *
 * Architecture (per §E.2):
 *   Pointer/touch/gamepad → Picker → InteractionRouter → MappingRegistry hook
 *   → canonical jam.* cell emission → CellRelay
 *
 * ALL canvas events flow through here with surfaceShape: 'three-room'.
 * The router never short-circuits the mapping system.
 *
 * Drag state machine:
 *   pointerdown → dragStart
 *   pointermove  → dragMove  (after threshold)
 *   pointerup    → dragEnd → resolve drop target
 *
 * Drop targets:
 *   loop-orb over scene-tile  → jam.scene.add-clip
 *   loop-orb over arrangement-block → jam.arrangement.section.add
 */

import type { PickHit } from './picker';
import type {
  JamInputTouch,
  JamInputGamepad,
  JamClipLaunchQueue,
  JamSceneLaunch,
  JamArrangementSectionAdd,
  JamRackMacroSet,
  JamControlGesture,
} from '../semantic/events';

// ─── Surface shape tag ────────────────────────────────────────────────────────

export const THREE_ROOM_SURFACE_ID = 'three-room';

// ─── Output event union ───────────────────────────────────────────────────────

export type ThreeRoomEvent =
  | JamInputTouch
  | JamInputGamepad
  | JamClipLaunchQueue
  | JamSceneLaunch
  | { family: 'jam.scene.add-clip'; sceneId: string; clipId: string }
  | JamArrangementSectionAdd
  | { family: 'jam.arrangement.section.move'; arrangementId: string; sectionId: string; to: number }
  | { family: 'jam.arrangement.take.promote'; arrangementId: string; takeId: string }
  | JamRackMacroSet
  | JamControlGesture
  | { family: 'jam.gesture'; kind: string; playerId: string; ts: number };

// ─── Mapping registry hook ────────────────────────────────────────────────────

/**
 * Hook called before final emission so Phase C mappings can rewrite or
 * suppress three-room events.  Return null to suppress, or a new event
 * to replace.
 */
export type MappingHook = (event: ThreeRoomEvent) => ThreeRoomEvent | null;

// ─── Drag state ───────────────────────────────────────────────────────────────

interface DragState {
  startHit: PickHit;
  startX: number;
  startY: number;
  lastX: number;
  lastY: number;
  active: boolean;   // true after threshold
}

const DRAG_THRESHOLD_PX = 6;

// ─── InteractionRouter ────────────────────────────────────────────────────────

export class InteractionRouter {
  /** Called for every emitted canonical event. */
  onEvent?: (event: ThreeRoomEvent) => void;

  /** Phase C mapping registry hook. Install to intercept/rewrite events. */
  mappingHook?: MappingHook;

  private drag: DragState | null = null;

  // ── Pointer input ─────────────────────────────────────────────────────────

  /**
   * Call on pointerdown.
   * If the hit is a click-only object (scene-tile, pod), hold until pointerup.
   */
  handlePointerDown(hit: PickHit | null, x: number, y: number): void {
    if (!hit) { this.drag = null; return; }
    this.drag = {
      startHit: hit,
      startX: x,
      startY: y,
      lastX: x,
      lastY: y,
      active: false,
    };
  }

  /**
   * Call on pointermove (with buttons held).
   * Emits jam.input.touch for every movement once drag threshold crossed.
   */
  handlePointerMove(
    _hit: PickHit | null,
    x: number,
    y: number,
    isTouch: boolean,
  ): void {
    if (!this.drag) return;
    this.drag.lastX = x;
    this.drag.lastY = y;

    const dx = x - this.drag.startX;
    const dy = y - this.drag.startY;
    const dist = Math.sqrt(dx * dx + dy * dy);

    if (!this.drag.active && dist > DRAG_THRESHOLD_PX) {
      this.drag.active = true;
    }
    if (!this.drag.active) return;

    // Emit jam.input.touch for the dragged object
    const touchEvent: JamInputTouch = {
      family: 'jam.input.touch',
      surfaceId: THREE_ROOM_SURFACE_ID,
      x: x / window.innerWidth,
      y: y / window.innerHeight,
      pressure: isTouch ? 0.8 : 1.0,
      area: isTouch ? 0.02 : 0.001,
      target: this.drag.startHit.semanticId,
    };
    this.emit(touchEvent);
  }

  /**
   * Call on pointerup.
   * Resolves click vs drag and emits the appropriate canonical event.
   */
  handlePointerUp(
    hit: PickHit | null,
    x: number,
    y: number,
  ): void {
    const drag = this.drag;
    this.drag = null;
    if (!drag) return;

    if (!drag.active) {
      // Click — dispatch based on start-hit object kind
      this.dispatchClick(drag.startHit);
      return;
    }

    // Drag ended — resolve drop target
    if (hit) {
      this.dispatchDrop(drag.startHit, hit, x, y);
    }
  }

  // ── Gamepad input ─────────────────────────────────────────────────────────

  handleGamepadAxis(axisOrButton: string, value: number): void {
    const ev: JamInputGamepad = {
      family: 'jam.input.gamepad',
      surfaceId: THREE_ROOM_SURFACE_ID,
      axisOrButton,
      value,
    };
    this.emit(ev);
  }

  // ── Mixer fader ───────────────────────────────────────────────────────────

  handleFaderDrag(rackId: string, macroIndex: number, value: number): void {
    const ev: JamRackMacroSet = {
      family: 'jam.rack.macro.set',
      rackId,
      index: macroIndex,
      value,
    };
    this.emit(ev);
  }

  // ── Player raise-hand gesture ─────────────────────────────────────────────

  handleRaiseHand(playerId: string): void {
    const ev = {
      family: 'jam.gesture' as const,
      kind: 'propose',
      playerId,
      ts: Date.now(),
    };
    this.emit(ev);
  }

  // ── private ──────────────────────────────────────────────────────────────

  private dispatchClick(hit: PickHit): void {
    switch (hit.kind) {
      case 'loop-orb': {
        // Click on orb = preview via jam.clip.launch.queue { quantum: 'immediate' }
        const ev: JamClipLaunchQueue = {
          family: 'jam.clip.launch.queue',
          clipId: hit.semanticId,
          quantum: 0,   // 0 = immediate per spec
          ts: Date.now(),
        };
        this.emit(ev);
        break;
      }

      case 'scene-tile': {
        // Step on = jam.scene.launch
        const ev: JamSceneLaunch = {
          family: 'jam.scene.launch',
          sceneId: hit.semanticId,
          quantum: 1,
          ts: Date.now(),
        };
        this.emit(ev);
        break;
      }

      case 'instrument-pod': {
        // Click on pod = emit touch targeting the pod (surface maps it to rack focus)
        const ev: JamInputTouch = {
          family: 'jam.input.touch',
          surfaceId: THREE_ROOM_SURFACE_ID,
          x: 0,
          y: 0,
          pressure: 1,
          area: 0,
          target: hit.semanticId,
        };
        this.emit(ev);
        break;
      }

      case 'player-avatar': {
        // Hover click on avatar = identity gesture
        const ev: JamControlGesture = {
          family: 'jam.control.gesture',
          gestureId: `gesture-${hit.semanticId}-${Date.now()}`,
          kind: 'identity-reveal',
          params: { playerId: hit.semanticId },
          ts: Date.now(),
        };
        this.emit(ev);
        break;
      }

      case 'arrangement-block': {
        // Click promote button — userData carries action
        const action = (hit.object.userData.action as string | undefined) ?? '';
        if (action === 'promote') {
          const ev: ThreeRoomEvent = {
            family: 'jam.arrangement.take.promote',
            arrangementId: (hit.object.userData.arrangementId as string | undefined) ?? '',
            takeId: hit.semanticId,
          };
          this.emit(ev);
        }
        break;
      }

      default:
        break;
    }
  }

  private dispatchDrop(
    source: PickHit,
    target: PickHit,
    _x: number,
    _y: number,
  ): void {
    if (source.kind === 'loop-orb') {
      if (target.kind === 'scene-tile') {
        // Drop orb on tile = jam.scene.add-clip
        const ev = {
          family: 'jam.scene.add-clip' as const,
          sceneId: target.semanticId,
          clipId: source.semanticId,
        };
        this.emit(ev);
        return;
      }

      if (target.kind === 'arrangement-block') {
        // Drop orb on arrangement wall = jam.arrangement.section.add
        const ev: JamArrangementSectionAdd = {
          family: 'jam.arrangement.section.add',
          arrangementId:
            (target.object.userData.arrangementId as string | undefined) ?? 'default',
          section: {
            patternObjectId: source.semanticId,
            startBar: (target.object.userData.startBar as number | undefined) ?? 0,
            lengthBars: (target.object.userData.lengthBars as number | undefined) ?? 4,
          },
        };
        this.emit(ev);
        return;
      }
    }

    if (source.kind === 'arrangement-block') {
      // Drag arrangement block = jam.arrangement.section.move
      const ev: ThreeRoomEvent = {
        family: 'jam.arrangement.section.move',
        arrangementId:
          (source.object.userData.arrangementId as string | undefined) ?? 'default',
        sectionId: source.semanticId,
        to: (target.object.userData.startBar as number | undefined) ?? 0,
      };
      this.emit(ev);
    }
  }

  private emit(event: ThreeRoomEvent): void {
    const mapped = this.mappingHook ? this.mappingHook(event) : event;
    if (mapped) this.onEvent?.(mapped);
  }
}

```
