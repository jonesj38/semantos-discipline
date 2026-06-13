---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/three/jambox-world.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.617540+00:00
---

# cartridges/jambox/web/src/three/jambox-world.ts

```ts
/**
 * Three.js studio room for the jambox world.
 *
 * Pods = drum track instruments.  Click → select track, camera yaws smoothly
 * to face the pod.  Each pod has a 16-LED step ring showing its pattern.
 * Drag horizontally to orbit the room.
 *
 * Phase E extensions:
 *   - Instrument pods render one per registered rack (D-E.2)
 *   - LoopOrbSystem, SceneTileFloor, ArrangementWall, PlayerAvatarSystem
 *     integrated into the scene graph (D-E.3 – D-E.6)
 *   - Mixer rail + effect altar (D-E.7): fader meshes per rack
 *   - Picker + InteractionRouter wired to all canvas events (D-E.1)
 *   - Three.js bundle gated on viewportPlan.surfacedLayers.includes('L4')
 */

import * as THREE from 'three';
import type {
  JamboxDrumTrackPayload,
  JamboxInstrumentObject,
  JamboxPatchObject,
  JamboxSnapshotObject,
  JamboxWorldObject,
} from '../semantic/objects';
import type { TrackName } from '../sequencer';
import { Picker } from './picker';
import { InteractionRouter } from './interaction-router';
import type { ThreeRoomEvent, MappingHook } from './interaction-router';
import { LoopOrbSystem } from './loop-orb';
import type { OrbData } from './loop-orb';
import { SceneTileFloor, createDefaultTiles } from './scene-tile';
import type { SceneTileData } from './scene-tile';
import { ArrangementWall } from './arrangement-wall';
import type { ArrangementSection } from './arrangement-wall';
import { PlayerAvatarSystem } from './player-avatar';
import type { PlayerAvatarData } from './player-avatar';

/** Minimal interface pod-hud.ts needs to anchor its position. */
export interface JamboxWorld {
  projectToScreen(pos: { x: number; y: number; z: number }): { x: number; y: number };
}

export interface JamboxPeerView {
  identity: string;
  online: boolean;
  color: string;
}

export interface JamboxWorldFrame {
  world: JamboxWorldObject;
  instruments: JamboxInstrumentObject[];
  peers: JamboxPeerView[];
  patchCount: number;
  snapshotCount: number;
  lastPatch?: JamboxPatchObject;
  lastSnapshot?: JamboxSnapshotObject;
}

interface ModuleMesh {
  objectId: string;
  trackName: TrackName;
  mesh: THREE.Mesh<THREE.BoxGeometry, THREE.MeshStandardMaterial>;
  ring: THREE.Mesh<THREE.TorusGeometry, THREE.MeshStandardMaterial>;
  stepLeds: THREE.Mesh<THREE.CircleGeometry, THREE.MeshStandardMaterial>[];
}

interface PeerMesh {
  identity: string;
  mesh: THREE.Mesh<THREE.SphereGeometry, THREE.MeshStandardMaterial>;
}

// ── Phase E: mixer rail fader mesh ────────────────────────────────────────────

interface MixerFaderMesh {
  rackId: string;
  /** The draggable fader handle. */
  handle: THREE.Mesh<THREE.BoxGeometry, THREE.MeshStandardMaterial>;
  /** The fader track rail. */
  rail: THREE.Mesh<THREE.BoxGeometry, THREE.MeshStandardMaterial>;
  /** Current macro index this fader controls (default 5 = body/volume). */
  macroIndex: number;
  /** Current value 0-1. */
  value: number;
}

export class JamboxWorldView implements JamboxWorld {
  private readonly renderer: THREE.WebGLRenderer;
  private readonly scene = new THREE.Scene();
  private readonly camera: THREE.PerspectiveCamera;
  private readonly core: THREE.Mesh<THREE.IcosahedronGeometry, THREE.MeshStandardMaterial>;
  private readonly snapshotGroup = new THREE.Group();
  private readonly patchGroup = new THREE.Group();
  private readonly modules = new Map<string, ModuleMesh>();
  private readonly peers = new Map<string, PeerMesh>();
  private readonly clock = new THREE.Clock();
  private readonly resizeObserver: ResizeObserver;
  private readonly raycaster = new THREE.Raycaster();
  private readonly pointer = new THREE.Vector2();
  private frame: JamboxWorldFrame | null = null;
  private patchPulse = 0;
  private snapshotPulse = 0;
  private beatPulse = 0;
  private disposed = false;

  // Orbit camera state (spherical coords)
  private cameraPhi = 0;           // azimuthal (horizontal rotation)
  private readonly cameraTheta = 0.55; // elevation angle (fixed)
  private readonly cameraRadius = 10.3;
  private targetPhi = 0;           // lerp target for smooth yaw-to-pod
  private isDragging = false;
  private dragStartX = 0;
  private dragStartPhi = 0;

  // Pod selection
  selectedModuleId: string | null = null;

  /** Called when a pod is clicked: (trackName, screenPos). */
  onPodClick?: (track: TrackName, pos: { x: number; y: number }) => void;
  /** Called every animation frame — use to tick the HUD. */
  onFrame?: () => void;

  // ── Phase E systems ─────────────────────────────────────────────────────────

  /** D-E.1: picker and interaction router. */
  readonly picker: Picker;
  readonly interactionRouter: InteractionRouter;

  /** D-E.3: loop orb constellation (centre of room). */
  readonly orbSystem: LoopOrbSystem;
  /** D-E.4: scene tile floor. */
  readonly tileFLoor: SceneTileFloor;
  /** D-E.5: arrangement wall. */
  readonly arrangementWall: ArrangementWall;
  /** D-E.6: player avatars. */
  readonly avatarSystem: PlayerAvatarSystem;

  /** D-E.7: mixer rail faders (right wall). */
  private readonly mixerFaders = new Map<string, MixerFaderMesh>();
  private readonly mixerGroup = new THREE.Group();

  /** Called when any canonical three-room event is emitted. */
  onThreeRoomEvent?: (event: ThreeRoomEvent) => void;

  /** Clock phase 0..1 from jam.clock.tick, used for orb pulse. */
  private clockPhase = 0;

  /** Active rack id (for pod focus state sync — D-E.2). */
  activeRackId: string | null = null;

  constructor(private readonly canvas: HTMLCanvasElement) {
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, preserveDrawingBuffer: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

    this.camera = new THREE.PerspectiveCamera(40, 1, 0.1, 100);
    this.updateCameraOrbit();

    // ── Phase E: init picker + router ───────────────────────────────────────
    this.picker = new Picker(this.camera);
    this.interactionRouter = new InteractionRouter();
    this.interactionRouter.onEvent = (ev) => this.onThreeRoomEvent?.(ev);

    // ── Phase E: init scene systems ─────────────────────────────────────────
    this.orbSystem = new LoopOrbSystem();
    this.tileFLoor = new SceneTileFloor();
    this.arrangementWall = new ArrangementWall();
    this.avatarSystem = new PlayerAvatarSystem();

    canvas.addEventListener('mousedown', this.onMouseDown);
    canvas.addEventListener('click', this.onClick);
    canvas.addEventListener('pointerdown', this.onPointerDown);
    canvas.addEventListener('pointermove', this.onPointerMove);
    canvas.addEventListener('pointerup', this.onPointerUp);

    this.scene.background = new THREE.Color(0x0e1014);
    this.scene.add(new THREE.AmbientLight(0xffffff, 0.38));
    const key = new THREE.DirectionalLight(0xffffff, 1.0);
    key.position.set(4, 7, 5);
    this.scene.add(key);
    const rim = new THREE.DirectionalLight(0x65d6f5, 0.8);
    rim.position.set(-5, 3, -4);
    this.scene.add(rim);

    const floor = new THREE.Mesh(
      new THREE.CylinderGeometry(4.5, 5.2, 0.08, 80),
      new THREE.MeshStandardMaterial({
        color: 0x141923,
        roughness: 0.82,
        metalness: 0.1,
      }),
    );
    floor.position.y = -1.2;
    this.scene.add(floor);

    this.core = new THREE.Mesh(
      new THREE.IcosahedronGeometry(0.82, 1),
      new THREE.MeshStandardMaterial({
        color: 0x65d6f5,
        emissive: 0x123b44,
        roughness: 0.28,
        metalness: 0.2,
      }),
    );
    this.core.name = 'jambox-core';
    this.scene.add(this.core, this.snapshotGroup, this.patchGroup);

    // ── Phase E: add instanced systems to scene ─────────────────────────────
    this.scene.add(this.orbSystem.mesh, this.orbSystem.trailMesh);
    this.scene.add(this.tileFLoor.mesh);
    this.scene.add(this.arrangementWall.sectionMesh, this.arrangementWall.overlayGroup);
    this.scene.add(this.avatarSystem.group);
    this.mixerGroup.name = 'mixer-rail';
    this.scene.add(this.mixerGroup);

    // Default tile layout (32 tiles, placeholder scene ids)
    const defaultTiles = createDefaultTiles(
      Array.from({ length: 32 }, (_, i) => `scene-${i}`),
      [0x2a3a4a, 0x1a3a2a, 0x3a2a1a, 0x2a1a3a, 0x1a2a3a, 0x3a1a2a, 0x2a3a1a, 0x1a1a3a],
    );
    this.tileFLoor.setTiles(defaultTiles);

    // Register all pickable objects
    this.refreshPickableObjects();

    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(canvas);
    this.resize();
    this.animate();
  }

  update(frame: JamboxWorldFrame): void {
    this.frame = frame;
    this.syncModules(frame);
    this.syncPeers(frame.peers);
    this.syncSnapshots(frame.snapshotCount);
  }

  // ── Phase E: public API ───────────────────────────────────────────────────

  /**
   * D-E.3: Replace the set of loop orbs.
   * Called when jam.clip.* state changes.
   */
  setOrbs(orbs: OrbData[]): void {
    this.orbSystem.setOrbs(orbs);
    this.refreshPickableObjects();
  }

  /**
   * D-E.4: Flash a scene tile (call on jam.scene.launch cell).
   */
  flashSceneTile(sceneId: string): void {
    this.tileFLoor.flashTile(sceneId);
  }

  /**
   * D-E.4: Replace the tile layout.
   */
  setSceneTiles(tiles: SceneTileData[]): void {
    this.tileFLoor.setTiles(tiles);
    this.refreshPickableObjects();
  }

  /**
   * D-E.5: Replace arrangement sections.
   */
  setArrangementSections(sections: ArrangementSection[]): void {
    this.arrangementWall.setSections(sections);
    this.refreshPickableObjects();
  }

  /**
   * D-E.6: Replace player avatars.
   */
  setPlayers(players: PlayerAvatarData[]): void {
    this.avatarSystem.setPlayers(players);
    this.refreshPickableObjects();
  }

  /**
   * D-E.7: Sync mixer rail from rack states.
   * Reuses Phase B Mix mode macro bindings — no parallel audio path.
   */
  syncMixerRail(rackStates: Array<{ rackId: string; label: string; value: number }>): void {
    const wanted = new Set(rackStates.map((r) => r.rackId));

    // Remove old faders
    for (const [rackId, fader] of this.mixerFaders) {
      if (!wanted.has(rackId)) {
        this.mixerGroup.remove(fader.handle, fader.rail);
        fader.handle.geometry.dispose();
        fader.handle.material.dispose();
        fader.rail.geometry.dispose();
        fader.rail.material.dispose();
        this.mixerFaders.delete(rackId);
      }
    }

    rackStates.forEach((rs, i) => {
      let fader = this.mixerFaders.get(rs.rackId);
      if (!fader) {
        const rail = new THREE.Mesh(
          new THREE.BoxGeometry(0.06, 1.2, 0.06),
          new THREE.MeshStandardMaterial({ color: 0x333344, roughness: 0.7, metalness: 0.2 }),
        );
        const handle = new THREE.Mesh(
          new THREE.BoxGeometry(0.18, 0.08, 0.14),
          new THREE.MeshStandardMaterial({ color: 0x65d6f5, roughness: 0.3, metalness: 0.5 }),
        );
        handle.name = rs.rackId;
        handle.userData.objectKind = 'mixer-fader';
        handle.userData.semanticId = rs.rackId;
        handle.userData.macroIndex = 5; // macro 5 = body (volume proxy)
        this.mixerGroup.add(rail, handle);
        fader = { rackId: rs.rackId, handle, rail, macroIndex: 5, value: rs.value };
        this.mixerFaders.set(rs.rackId, fader);
      }
      fader.value = rs.value;
      const x = 4.5;                     // right wall X
      const z = -1.5 + i * 0.55;
      fader.rail.position.set(x, 0, z);
      fader.handle.position.set(x, -0.5 + rs.value, z);
    });

    this.refreshPickableObjects();
  }

  /**
   * D-E.1: Install a Phase C mapping hook so three-room events can be rewritten.
   */
  setMappingHook(hook: MappingHook | undefined): void {
    this.interactionRouter.mappingHook = hook;
  }

  /**
   * D-E.2: Sync active rack id for pod focus state (pod ring glows cyan when active).
   */
  setActiveRackId(rackId: string | null): void {
    this.activeRackId = rackId;
    // Find the module whose instrument track matches the rackId and select it.
    if (rackId) {
      for (const [id, module] of this.modules) {
        // Convention: rackId contains the track name e.g. 'jam.rack.drum-808'
        if (rackId.includes(module.trackName)) {
          this.selectedModuleId = id;
          this.yawToModule(id);
          return;
        }
      }
    }
  }

  /**
   * D-E.3 / D-E.4: Update clock phase from jam.clock.tick event.
   * Drives orb pulse and tile animations.
   */
  setClockPhase(phase: number): void {
    this.clockPhase = phase;
  }

  pulsePatch(patch: JamboxPatchObject): void {
    this.patchPulse = 1;
    this.addPatchTracer(patch);
  }

  pulseSnapshot(snapshot: JamboxSnapshotObject): void {
    this.snapshotPulse = 1;
    this.frame = this.frame ? { ...this.frame, lastSnapshot: snapshot } : this.frame;
    this.syncSnapshots((this.frame?.snapshotCount ?? 0) + 1);
  }

  /** Pulse the beat indicator on the core mesh. */
  pulseBeat(): void {
    this.beatPulse = Math.max(this.beatPulse, 0.4);
  }

  /** Update the 16-LED step ring for a drum track. */
  updateDrumTrack(track: TrackName, state: JamboxDrumTrackPayload): void {
    const module = [...this.modules.values()].find((m) => m.trackName === track);
    if (!module) return;

    module.stepLeds.forEach((led, i) => {
      const on = state.steps[i] ?? false;
      const vel = (state.velocities[i] ?? 100) / 127;
      led.material.emissiveIntensity = on ? 0.2 + vel * 0.8 : 0.03;
      led.material.color.set(on ? 0x65d6f5 : 0x223344);
      led.userData.on = on;
    });
    // Store mute state on mesh for animate loop
    module.mesh.userData.muted = state.mute;
  }

  /** Flash the playhead step on all step rings. */
  setPlayheadStep(step: number): void {
    const s = step % 16;
    for (const module of this.modules.values()) {
      module.stepLeds.forEach((led, i) => {
        if (i === s) {
          led.material.emissiveIntensity = 1;
          led.material.color.set(0xffffff);
        } else if (led.userData.on as boolean) {
          led.material.emissiveIntensity = 0.5;
          led.material.color.set(0x65d6f5);
        } else {
          led.material.emissiveIntensity = 0.03;
          led.material.color.set(0x223344);
        }
      });
    }
  }

  /** Project a 3-D world position to screen pixels. */
  projectToScreen(pos: { x: number; y: number; z: number }): { x: number; y: number } {
    const v = new THREE.Vector3(pos.x, pos.y, pos.z);
    v.project(this.camera);
    const rect = this.canvas.getBoundingClientRect();
    return {
      x: (v.x * 0.5 + 0.5) * rect.width + rect.left,
      y: (-v.y * 0.5 + 0.5) * rect.height + rect.top,
    };
  }

  dispose(): void {
    this.disposed = true;
    this.canvas.removeEventListener('mousedown', this.onMouseDown);
    this.canvas.removeEventListener('click', this.onClick);
    this.canvas.removeEventListener('pointerdown', this.onPointerDown);
    this.canvas.removeEventListener('pointermove', this.onPointerMove);
    this.canvas.removeEventListener('pointerup', this.onPointerUp);
    window.removeEventListener('mousemove', this.onMouseMove);
    window.removeEventListener('mouseup', this.onMouseUp);
    this.resizeObserver.disconnect();
    this.renderer.dispose();
    // Phase E cleanup
    this.orbSystem.dispose();
    this.tileFLoor.dispose();
    this.arrangementWall.dispose();
    this.avatarSystem.dispose();
  }

  // ── Phase E: pointer event handlers ────────────────────────────────────────

  private onPointerDown = (e: PointerEvent): void => {
    const isTouch = e.pointerType === 'touch';
    const hit = this.picker.pick(e.clientX, e.clientY, this.canvas, isTouch);
    this.interactionRouter.handlePointerDown(hit, e.clientX, e.clientY);
  };

  private onPointerMove = (e: PointerEvent): void => {
    if (e.buttons === 0) return;
    const isTouch = e.pointerType === 'touch';
    const hit = this.picker.pick(e.clientX, e.clientY, this.canvas, isTouch);
    this.interactionRouter.handlePointerMove(hit, e.clientX, e.clientY, isTouch);
  };

  private onPointerUp = (e: PointerEvent): void => {
    const isTouch = e.pointerType === 'touch';
    const hit = this.picker.pick(e.clientX, e.clientY, this.canvas, isTouch);
    this.interactionRouter.handlePointerUp(hit, e.clientX, e.clientY);
  };

  /** Rebuild the picker's pickable object list. Call when scene changes. */
  private refreshPickableObjects(): void {
    const objects: THREE.Object3D[] = [
      this.orbSystem.mesh,
      this.tileFLoor.mesh,
      this.arrangementWall.sectionMesh,
      ...this.arrangementWall.overlayGroup.children,
      ...this.avatarSystem.pickableObjects,
      ...this.mixerGroup.children,
      ...[...this.modules.values()].map((m) => m.mesh),
    ];
    this.picker.setPickableObjects(objects);
  }

  // ── Orbit camera ───────────────────────────────────────────────────────────

  private updateCameraOrbit(): void {
    const r = this.cameraRadius;
    const theta = this.cameraTheta;
    const phi = this.cameraPhi;
    this.camera.position.set(
      r * Math.sin(theta) * Math.sin(phi),
      r * Math.cos(theta),
      r * Math.sin(theta) * Math.cos(phi),
    );
    this.camera.lookAt(0, 0, 0);
  }

  private yawToModule(moduleId: string): void {
    const module = this.modules.get(moduleId);
    if (!module) return;
    const p = module.mesh.position;
    this.targetPhi = Math.atan2(p.x, p.z);
  }

  // ── Mouse handlers ─────────────────────────────────────────────────────────

  private onMouseDown = (e: MouseEvent): void => {
    this.isDragging = false;
    this.dragStartX = e.clientX;
    this.dragStartPhi = this.cameraPhi;
    window.addEventListener('mousemove', this.onMouseMove);
    window.addEventListener('mouseup', this.onMouseUp);
    this.canvas.style.cursor = 'grabbing';
  };

  private onMouseMove = (e: MouseEvent): void => {
    const dx = e.clientX - this.dragStartX;
    if (Math.abs(dx) > 3) this.isDragging = true;
    if (this.isDragging) {
      this.cameraPhi = this.dragStartPhi - dx * 0.008;
      this.targetPhi = this.cameraPhi;
      this.updateCameraOrbit();
    }
  };

  private onMouseUp = (): void => {
    window.removeEventListener('mousemove', this.onMouseMove);
    window.removeEventListener('mouseup', this.onMouseUp);
    this.canvas.style.cursor = 'grab';
  };

  private onClick = (e: MouseEvent): void => {
    if (this.isDragging) return;
    const rect = this.canvas.getBoundingClientRect();
    this.pointer.set(
      ((e.clientX - rect.left) / rect.width) * 2 - 1,
      -((e.clientY - rect.top) / rect.height) * 2 + 1,
    );
    this.raycaster.setFromCamera(this.pointer, this.camera);
    const meshes = [...this.modules.values()].map((m) => m.mesh);
    const hits = this.raycaster.intersectObjects(meshes);
    if (hits.length === 0) {
      // Deselect
      this.selectedModuleId = null;
      return;
    }
    const hit = hits[0].object as THREE.Mesh;
    const module = [...this.modules.values()].find((m) => m.mesh === hit);
    if (!module) return;
    this.selectedModuleId = module.objectId;
    this.yawToModule(module.objectId);
    const screen = this.projectToScreen(module.mesh.position);
    this.onPodClick?.(module.trackName, screen);
  };

  private syncModules(frame: JamboxWorldFrame): void {
    const wanted = new Set(frame.world.payload.modules.map((m) => m.id));
    for (const [id, module] of this.modules) {
      if (!wanted.has(id)) {
        this.scene.remove(module.mesh, module.ring, ...module.stepLeds);
        module.mesh.geometry.dispose(); module.mesh.material.dispose();
        module.ring.geometry.dispose(); module.ring.material.dispose();
        module.stepLeds.forEach((l) => { l.geometry.dispose(); l.material.dispose(); });
        this.modules.delete(id);
      }
    }

    for (const moduleDef of frame.world.payload.modules) {
      const instrument = frame.instruments.find((i) => i.id === moduleDef.instrumentObjectId);
      const color = colorForInstrument(instrument);
      let module = this.modules.get(moduleDef.id);
      if (!module) {
        const mesh = new THREE.Mesh(
          new THREE.BoxGeometry(0.68, 0.42, 0.68),
          new THREE.MeshStandardMaterial({
            color, emissive: new THREE.Color(color).multiplyScalar(0.12),
            roughness: 0.44, metalness: 0.25,
          }),
        );
        const ring = new THREE.Mesh(
          new THREE.TorusGeometry(0.56, 0.018, 8, 40),
          new THREE.MeshStandardMaterial({
            color: 0xffd166, emissive: 0x332300, roughness: 0.35, metalness: 0.4,
          }),
        );
        // 16 step LED discs arranged in a circle above the ring
        const stepLeds: THREE.Mesh<THREE.CircleGeometry, THREE.MeshStandardMaterial>[] = [];
        for (let i = 0; i < 16; i++) {
          const angle = (Math.PI * 2 * i) / 16 - Math.PI / 2;
          const ledR = 0.62;
          const led = new THREE.Mesh(
            new THREE.CircleGeometry(0.055, 8),
            new THREE.MeshStandardMaterial({
              color: 0x223344, emissive: 0x223344, emissiveIntensity: 0.03,
              roughness: 0.5, metalness: 0.1,
            }),
          );
          led.userData.angle = angle;
          led.userData.ledRadius = ledR;
          led.userData.on = false;
          led.name = `${moduleDef.id}:step-${i}`;
          stepLeds.push(led);
        }
        mesh.name = moduleDef.id;
        ring.name = `${moduleDef.id}:ring`;
        module = { objectId: moduleDef.id, trackName: moduleDef.track, mesh, ring, stepLeds };
        this.modules.set(moduleDef.id, module);
        this.scene.add(mesh, ring, ...stepLeds);
      }
      const [x, y, z] = moduleDef.position;
      module.mesh.position.set(x, y, z);
      module.ring.position.set(x, y - 0.05, z);
      module.ring.rotation.x = Math.PI / 2;
      // Position step LEDs in a circle around the module, facing outward
      module.stepLeds.forEach((led) => {
        const angle = (led.userData.angle as number);
        const r = led.userData.ledRadius as number;
        led.position.set(
          x + Math.cos(angle) * r,
          y - 0.04,
          z + Math.sin(angle) * r,
        );
        // Face upward (lie flat in XZ plane)
        led.rotation.x = -Math.PI / 2;
      });
      module.mesh.material.color.set(color);
      module.mesh.material.emissive.set(color).multiplyScalar(0.12);
      module.mesh.scale.setScalar(1);
    }
    // Phase E: keep picker up to date when modules change
    this.refreshPickableObjects();
  }

  private syncPeers(peers: JamboxPeerView[]): void {
    const wanted = new Set(peers.map((p) => p.identity));
    for (const [identity, peer] of this.peers) {
      if (!wanted.has(identity)) {
        this.scene.remove(peer.mesh);
        peer.mesh.geometry.dispose();
        peer.mesh.material.dispose();
        this.peers.delete(identity);
      }
    }

    peers.forEach((peer, index) => {
      let peerMesh = this.peers.get(peer.identity);
      if (!peerMesh) {
        const mesh = new THREE.Mesh(
          new THREE.SphereGeometry(0.18, 24, 16),
          new THREE.MeshStandardMaterial({
            color: new THREE.Color(peer.color),
            emissive: new THREE.Color(peer.color).multiplyScalar(0.2),
            roughness: 0.35,
            metalness: 0.35,
          }),
        );
        peerMesh = { identity: peer.identity, mesh };
        this.peers.set(peer.identity, peerMesh);
        this.scene.add(mesh);
      }
      const angle = (Math.PI * 2 * index) / Math.max(1, peers.length);
      const radius = 5;
      peerMesh.mesh.position.set(Math.cos(angle) * radius, 0.55, Math.sin(angle) * radius);
      peerMesh.mesh.scale.setScalar(peer.online ? 1.15 : 0.72);
      peerMesh.mesh.material.opacity = peer.online ? 1 : 0.45;
      peerMesh.mesh.material.transparent = true;
    });
  }

  private syncSnapshots(count: number): void {
    while (this.snapshotGroup.children.length < Math.min(count, 16)) {
      const i = this.snapshotGroup.children.length;
      const crystal = new THREE.Mesh(
        new THREE.OctahedronGeometry(0.14, 0),
        new THREE.MeshStandardMaterial({
          color: 0xffd166,
          emissive: 0x3a2800,
          roughness: 0.2,
          metalness: 0.35,
        }),
      );
      const angle = i * 0.72;
      crystal.position.set(Math.cos(angle) * 1.55, 1.15 + i * 0.035, Math.sin(angle) * 1.55);
      this.snapshotGroup.add(crystal);
    }
  }

  private addPatchTracer(patch: JamboxPatchObject): void {
    const target = patch.payload.appliesToObjectIds[0];
    const module = target ? this.modules.get(target) : undefined;
    const curve = new THREE.CatmullRomCurve3([
      new THREE.Vector3(0, 0.15, 0),
      new THREE.Vector3(0, 1.1, 0),
      module ? module.mesh.position.clone() : new THREE.Vector3(1.5, 0.2, 0),
    ]);
    const tube = new THREE.Mesh(
      new THREE.TubeGeometry(curve, 16, 0.025, 8, false),
      new THREE.MeshStandardMaterial({
        color: 0x65d6f5,
        emissive: 0x1d6572,
        roughness: 0.25,
        metalness: 0.2,
        transparent: true,
        opacity: 0.85,
      }),
    );
    tube.userData.life = 1;
    this.patchGroup.add(tube);
  }

  private resize(): void {
    const rect = this.canvas.getBoundingClientRect();
    const width = Math.max(1, Math.floor(rect.width));
    const height = Math.max(1, Math.floor(rect.height));
    this.renderer.setSize(width, height, false);
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
  }

  private animate = (): void => {
    if (this.disposed) return;
    const dt = this.clock.getDelta();
    const t = this.clock.elapsedTime;
    const bpm = this.frame?.world.payload.bpm ?? 120;
    const beat = Math.sin(t * (bpm / 60) * Math.PI * 2) * 0.5 + 0.5;

    // Smooth camera yaw toward targetPhi
    const phiDiff = this.targetPhi - this.cameraPhi;
    if (Math.abs(phiDiff) > 0.001) {
      this.cameraPhi += phiDiff * Math.min(1, dt * 5);
      this.updateCameraOrbit();
    }

    this.patchPulse = Math.max(0, this.patchPulse - dt * 1.8);
    this.snapshotPulse = Math.max(0, this.snapshotPulse - dt * 1.2);
    this.beatPulse = Math.max(0, this.beatPulse - dt * 8);

    this.core.rotation.y += dt * 0.45;
    this.core.rotation.x = Math.sin(t * 0.4) * 0.12;
    this.core.scale.setScalar(1 + beat * 0.05 + this.patchPulse * 0.22 + this.snapshotPulse * 0.12 + this.beatPulse * 0.15);
    this.core.material.emissiveIntensity = 0.45 + beat * 0.3 + this.patchPulse + this.beatPulse;

    for (const module of this.modules.values()) {
      const isSelected = module.objectId === this.selectedModuleId;
      const isMuted = module.mesh.userData.muted as boolean;
      module.mesh.rotation.y += dt * (isSelected ? 0.9 : 0.35);
      module.ring.rotation.z += dt * 0.5;
      // Selected pod ring glows cyan; muted ring dims
      module.ring.material.color.set(isSelected ? 0x65d6f5 : (isMuted ? 0x333333 : 0xffd166));
      module.ring.material.emissiveIntensity = isSelected ? 0.6 : (isMuted ? 0 : 0.1);
      // Scale on beat
      const scale = isSelected ? 1.08 + this.beatPulse * 0.12 : 1;
      module.mesh.scale.setScalar(scale);
    }
    for (const peer of this.peers.values()) {
      peer.mesh.position.y = 0.55 + Math.sin(t * 1.8 + peer.identity.length) * 0.06;
    }

    // Phase E: tick sub-systems
    this.orbSystem.tick(dt, this.clockPhase);
    this.tileFLoor.tick(dt);
    this.avatarSystem.tick(dt);

    for (const child of [...this.patchGroup.children]) {
      const mesh = child as THREE.Mesh<THREE.BufferGeometry, THREE.MeshStandardMaterial>;
      const life = Math.max(0, (mesh.userData.life as number) - dt * 0.55);
      mesh.userData.life = life;
      mesh.material.opacity = life;
      if (life <= 0) {
        this.patchGroup.remove(mesh);
        mesh.geometry.dispose();
        mesh.material.dispose();
      }
    }

    this.renderer.render(this.scene, this.camera);
    this.onFrame?.();
    requestAnimationFrame(this.animate);
  };
}

function colorForInstrument(instrument: JamboxInstrumentObject | undefined): THREE.Color {
  if (!instrument) return new THREE.Color(0x8b94a8);
  if (instrument.payload.family === 'drum') return new THREE.Color(0xff8b59);
  if (instrument.payload.family === 'acid') return new THREE.Color(0xf5648a);
  if (instrument.payload.family === 'sampler') return new THREE.Color(0x82e2a8);
  return new THREE.Color(0x65d6f5);
}

```
