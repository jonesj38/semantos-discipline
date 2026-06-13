---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/three/loop-orb.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.615294+00:00
---

# cartridges/jambox/web/src/three/loop-orb.ts

```ts
/**
 * D-E.3 — Loop orbs: instanced rendering of jam.clip / jam.pattern objects.
 *
 * Visual language (§E.4):
 *   size    = pattern length / energy  (uniform scale of the instance)
 *   colour  = owning track / player / instrument
 *   pulse   = current playback phase (driven by jam.clock.tick)
 *   orbit   = ownership / collaboration (multiple owners = orbiting pair)
 *   trail   = last 8 changes (ghost trail meshes)
 *
 * All orbs share a single InstancedMesh — O(1) draw call regardless of count.
 * Trail ghosts are separate, low-opacity instanced spheres.
 *
 * Interactions (via InteractionRouter):
 *   Click   → jam.clip.launch.queue { quantum: 'immediate' }
 *   Drag    → jam.input.touch { target: orbId }
 *   Drop on scene tile  → jam.scene.add-clip
 *   Drop on arrangement → jam.arrangement.section.add
 */

import * as THREE from 'three';

// ─── Public API ───────────────────────────────────────────────────────────────

export interface OrbData {
  /** Stable semantic id (maps to jam.clip id). */
  id: string;
  /** World-space position (centre). */
  position: THREE.Vector3Like;
  /** 0..1 — controls sphere scale (small = short/quiet, large = long/loud). */
  energyNorm: number;
  /** Hex or CSS colour for the track / player / instrument. */
  color: string | number;
  /** 0..1 playback phase; drives pulse animation via jam.clock.tick. */
  phase: number;
  /** If > 1 orb shares this clip, they orbit each other. Orbit radius factor. */
  orbitFactor: number;
  /** Last 8 change positions for trail rendering. */
  trail: THREE.Vector3Like[];
}

// ─── Constants ────────────────────────────────────────────────────────────────

const BASE_ORB_RADIUS = 0.22;
const MAX_ORB_SCALE = 1.8;
const MIN_ORB_SCALE = 0.55;
const TRAIL_OPACITY = 0.18;
const TRAIL_SCALE_DECAY = 0.72; // each successive ghost is smaller
const MAX_ORBS = 128;
const MAX_TRAIL = 8;

const _dummy = new THREE.Object3D();
const _color = new THREE.Color();

// ─── LoopOrbSystem ────────────────────────────────────────────────────────────

export class LoopOrbSystem {
  /** The primary instanced orb mesh — add to scene. */
  readonly mesh: THREE.InstancedMesh<THREE.SphereGeometry, THREE.MeshStandardMaterial>;
  /** Trail ghost mesh — add to scene. */
  readonly trailMesh: THREE.InstancedMesh<THREE.SphereGeometry, THREE.MeshStandardMaterial>;

  private orbs: OrbData[] = [];
  private animPhase = 0;

  constructor() {
    const geo = new THREE.SphereGeometry(BASE_ORB_RADIUS, 14, 10);

    // Primary orb mesh
    const mat = new THREE.MeshStandardMaterial({
      roughness: 0.25,
      metalness: 0.45,
      emissive: new THREE.Color(0x223344),
      emissiveIntensity: 0.4,
    });
    this.mesh = new THREE.InstancedMesh(geo, mat, MAX_ORBS);
    this.mesh.name = 'loop-orb-instanced';
    this.mesh.userData.objectKind = 'loop-orb';
    this.mesh.count = 0;
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);

    // Trail ghost mesh — same geo, transparent
    const trailMat = new THREE.MeshStandardMaterial({
      roughness: 0.5,
      metalness: 0.1,
      transparent: true,
      opacity: TRAIL_OPACITY,
      depthWrite: false,
    });
    const trailCount = MAX_ORBS * MAX_TRAIL;
    this.trailMesh = new THREE.InstancedMesh(geo, trailMat, trailCount);
    this.trailMesh.name = 'loop-orb-trail';
    this.trailMesh.userData.objectKind = 'loop-orb-trail';
    this.trailMesh.count = 0;
    this.trailMesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
  }

  /** Replace the full set of orbs (call on jam.clip.* state change). */
  setOrbs(orbs: OrbData[]): void {
    this.orbs = orbs.slice(0, MAX_ORBS);
    this.syncInstances();
  }

  /**
   * Tick animation.  Call from the render loop.
   * @param dt      - delta time in seconds
   * @param clockPhase - 0..1 global beat phase (from jam.clock.tick)
   */
  tick(dt: number, clockPhase: number): void {
    this.animPhase = clockPhase;
    this.syncInstances(true);
    void dt;
  }

  /**
   * Resolve which orb (if any) was hit by an instance intersection.
   * Use with raycaster.intersectObject(mesh).
   */
  resolveInstance(instanceId: number): OrbData | null {
    return this.orbs[instanceId] ?? null;
  }

  dispose(): void {
    this.mesh.geometry.dispose();
    (this.mesh.material as THREE.MeshStandardMaterial).dispose();
    this.trailMesh.geometry.dispose();
    (this.trailMesh.material as THREE.MeshStandardMaterial).dispose();
  }

  // ── private ──────────────────────────────────────────────────────────────

  private syncInstances(animate = false): void {
    const count = this.orbs.length;
    this.mesh.count = count;

    let trailIdx = 0;

    for (let i = 0; i < count; i++) {
      const orb = this.orbs[i]!;
      const phase = animate ? (orb.phase + this.animPhase) % 1 : orb.phase;
      const pulse = 1 + Math.sin(phase * Math.PI * 2) * 0.12;
      const scale = THREE.MathUtils.clamp(
        MIN_ORB_SCALE + orb.energyNorm * (MAX_ORB_SCALE - MIN_ORB_SCALE),
        MIN_ORB_SCALE,
        MAX_ORB_SCALE,
      ) * pulse;

      _dummy.position.set(orb.position.x, orb.position.y, orb.position.z);
      _dummy.scale.setScalar(scale);
      _dummy.updateMatrix();
      this.mesh.setMatrixAt(i, _dummy.matrix);

      _color.set(orb.color as THREE.ColorRepresentation);
      this.mesh.setColorAt(i, _color);

      // Trail
      const trail = orb.trail;
      for (let t = 0; t < trail.length && trailIdx < MAX_ORBS * MAX_TRAIL; t++) {
        const tp = trail[t]!;
        const trailScale = scale * Math.pow(TRAIL_SCALE_DECAY, t + 1);
        _dummy.position.set(tp.x, tp.y, tp.z);
        _dummy.scale.setScalar(trailScale);
        _dummy.updateMatrix();
        this.trailMesh.setMatrixAt(trailIdx, _dummy.matrix);
        _color.set(orb.color as THREE.ColorRepresentation);
        this.trailMesh.setColorAt(trailIdx, _color);
        trailIdx++;
      }
    }

    // Hide remaining trail slots
    for (; trailIdx < this.trailMesh.count; trailIdx++) {
      _dummy.scale.setScalar(0);
      _dummy.updateMatrix();
      this.trailMesh.setMatrixAt(trailIdx, _dummy.matrix);
    }
    this.trailMesh.count = trailIdx;

    this.mesh.instanceMatrix.needsUpdate = true;
    this.trailMesh.instanceMatrix.needsUpdate = true;
    if (this.mesh.instanceColor) this.mesh.instanceColor.needsUpdate = true;
    if (this.trailMesh.instanceColor) this.trailMesh.instanceColor.needsUpdate = true;
  }
}

```
