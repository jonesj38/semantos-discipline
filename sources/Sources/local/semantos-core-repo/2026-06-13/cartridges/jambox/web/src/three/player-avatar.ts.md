---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/cartridges/jambox/web/src/three/player-avatar.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.616644+00:00
---

# cartridges/jambox/web/src/three/player-avatar.ts

```ts
/**
 * D-E.6 — Player avatars: one per jam.player in the room.
 *
 * Each avatar:
 *   - Updates position from jam.input.* cells (player near the rack they're driving).
 *   - Hover → identity HUD (rendered via contribution-hud or DOM overlay).
 *   - Raise-hand gesture → jam.gesture { kind: 'propose' }.
 *
 * Position interpolates with 200 ms easing; rapid rack switches debounced (§risks).
 * No shadow maps; no post-processing.
 */

import * as THREE from 'three';

// ─── Types ────────────────────────────────────────────────────────────────────

export interface PlayerAvatarData {
  /** Stable player id (jam.player semantic id). */
  id: string;
  displayName: string;
  /** Player colour hex. */
  colorHex: string;
  /** Whether the player is currently online. */
  online: boolean;
  /** Target world-space position (avatar moves here smoothly). */
  targetPosition: THREE.Vector3Like;
  /** Optional: the rack id this player is currently driving. */
  activeRackId?: string;
}

// ─── Constants ────────────────────────────────────────────────────────────────

const AVATAR_RADIUS = 0.2;
const LERP_SPEED = 5.0;          // higher = faster interpolation
const DEBOUNCE_MS = 200;          // position-change debounce
const BOB_SPEED = 1.8;
const BOB_AMPLITUDE = 0.045;

// ─── PlayerAvatar ─────────────────────────────────────────────────────────────

interface AvatarMesh {
  id: string;
  group: THREE.Group;
  body: THREE.Mesh<THREE.SphereGeometry, THREE.MeshStandardMaterial>;
  halo: THREE.Mesh<THREE.TorusGeometry, THREE.MeshStandardMaterial>;
  data: PlayerAvatarData;
  currentPos: THREE.Vector3;
  pendingTarget: THREE.Vector3 | null;
  debounceTimer: ReturnType<typeof setTimeout> | null;
  bobOffset: number;
}

export class PlayerAvatarSystem {
  /** Add this group to the scene. */
  readonly group = new THREE.Group();

  private avatars = new Map<string, AvatarMesh>();
  private elapsed = 0;

  /** All individual avatar meshes (for picker registration). */
  get pickableObjects(): THREE.Object3D[] {
    return [...this.avatars.values()].map((a) => a.group);
  }

  /** Replace avatar set (call when jam.player.* cells arrive). */
  setPlayers(players: PlayerAvatarData[]): void {
    const wanted = new Set(players.map((p) => p.id));

    // Remove gone players
    for (const [id, avatar] of this.avatars) {
      if (!wanted.has(id)) {
        this.group.remove(avatar.group);
        avatar.body.geometry.dispose();
        avatar.body.material.dispose();
        avatar.halo.geometry.dispose();
        avatar.halo.material.dispose();
        if (avatar.debounceTimer) clearTimeout(avatar.debounceTimer);
        this.avatars.delete(id);
      }
    }

    // Add / update
    for (const player of players) {
      let avatar = this.avatars.get(player.id);
      if (!avatar) {
        avatar = this.createAvatar(player);
        this.group.add(avatar.group);
        this.avatars.set(player.id, avatar);
      }
      this.updateAvatarData(avatar, player);
    }
  }

  /**
   * Animate — call from render loop.
   * @param dt - delta time in seconds
   */
  tick(dt: number): void {
    this.elapsed += dt;
    for (const avatar of this.avatars.values()) {
      // Smooth position interpolation
      const factor = Math.min(1, dt * LERP_SPEED);
      avatar.currentPos.lerp(
        new THREE.Vector3(
          avatar.data.targetPosition.x,
          avatar.data.targetPosition.y,
          avatar.data.targetPosition.z,
        ),
        factor,
      );

      // Bob
      const bob = Math.sin(this.elapsed * BOB_SPEED + avatar.bobOffset) * BOB_AMPLITUDE;
      avatar.group.position.copy(avatar.currentPos);
      avatar.group.position.y += bob;

      // Halo pulse when online
      avatar.halo.material.emissiveIntensity = avatar.data.online
        ? 0.3 + Math.sin(this.elapsed * 2.5 + avatar.bobOffset) * 0.2
        : 0.05;

      // Fade out offline avatars
      avatar.body.material.opacity = avatar.data.online ? 1.0 : 0.4;
    }
  }

  dispose(): void {
    for (const avatar of this.avatars.values()) {
      avatar.body.geometry.dispose();
      avatar.body.material.dispose();
      avatar.halo.geometry.dispose();
      avatar.halo.material.dispose();
      if (avatar.debounceTimer) clearTimeout(avatar.debounceTimer);
    }
    this.avatars.clear();
  }

  // ── private ──────────────────────────────────────────────────────────────

  private createAvatar(data: PlayerAvatarData): AvatarMesh {
    const grp = new THREE.Group();
    grp.name = data.id;
    grp.userData.objectKind = 'player-avatar';
    grp.userData.semanticId = data.id;

    const body = new THREE.Mesh(
      new THREE.SphereGeometry(AVATAR_RADIUS, 20, 14),
      new THREE.MeshStandardMaterial({
        color: new THREE.Color(data.colorHex),
        emissive: new THREE.Color(data.colorHex).multiplyScalar(0.2),
        roughness: 0.3,
        metalness: 0.4,
        transparent: true,
      }),
    );
    body.name = `${data.id}:body`;

    const halo = new THREE.Mesh(
      new THREE.TorusGeometry(AVATAR_RADIUS + 0.08, 0.015, 8, 36),
      new THREE.MeshStandardMaterial({
        color: new THREE.Color(data.colorHex),
        emissive: new THREE.Color(data.colorHex),
        emissiveIntensity: 0.3,
        roughness: 0.35,
        metalness: 0.4,
      }),
    );
    halo.rotation.x = Math.PI / 2;
    halo.name = `${data.id}:halo`;

    grp.add(body, halo);

    const startPos = new THREE.Vector3(
      data.targetPosition.x,
      data.targetPosition.y,
      data.targetPosition.z,
    );

    return {
      id: data.id,
      group: grp,
      body,
      halo,
      data,
      currentPos: startPos.clone(),
      pendingTarget: null,
      debounceTimer: null,
      bobOffset: Math.random() * Math.PI * 2,
    };
  }

  private updateAvatarData(avatar: AvatarMesh, data: PlayerAvatarData): void {
    avatar.data = data;

    // Debounce position changes to avoid oscillation on rapid rack switches
    const newTarget = new THREE.Vector3(
      data.targetPosition.x,
      data.targetPosition.y,
      data.targetPosition.z,
    );

    if (!avatar.currentPos.distanceTo(newTarget) || avatar.pendingTarget === null) {
      avatar.pendingTarget = newTarget;
      if (avatar.debounceTimer) clearTimeout(avatar.debounceTimer);
      avatar.debounceTimer = setTimeout(() => {
        if (avatar.pendingTarget) {
          avatar.data = { ...avatar.data, targetPosition: avatar.pendingTarget };
          avatar.pendingTarget = null;
        }
        avatar.debounceTimer = null;
      }, DEBOUNCE_MS);
    }

    // Update colour immediately
    avatar.body.material.color.set(data.colorHex);
    avatar.body.material.emissive.set(data.colorHex).multiplyScalar(0.2);
    avatar.halo.material.color.set(data.colorHex);
    avatar.halo.material.emissive.set(data.colorHex);
  }
}

```
