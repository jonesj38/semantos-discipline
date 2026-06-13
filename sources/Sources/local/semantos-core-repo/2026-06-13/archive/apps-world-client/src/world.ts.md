---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/world.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.824466+00:00
---

# archive/apps-world-client/src/world.ts

```ts
import * as THREE from "three";
import { EntityMesh } from "./entity";
import { Shatter } from "./shatter";
import type { EntityDelta, EntityAction, Vec3 } from "./types";
import type { WorldSocket } from "./socket";
import { showAnnotation, ANN } from "./annotation";

export class World {
  public readonly entities = new Map<string, EntityMesh>();
  public selectedId: string | null = null;
  public tickSeq: number = 0;
  public regionId: string = "";
  public stateHash: string = "";

  /** Cheat mode — when true, the predictor optimistically applies DUP
   *  locally even though the server will reject. This makes divergence
   *  visible: a phantom cube appears next to the original, then snaps
   *  away on the next tick when the authoritative state contradicts it. */
  public cheatMode: boolean = false;

  private readonly shatters: Shatter[] = [];
  private readonly phantoms = new Map<string, THREE.Mesh>();
  private readonly pending = new Map<
    string,
    { entityId: string; op: string; cheating: boolean }
  >();

  constructor(
    private readonly scene: THREE.Scene,
    private readonly socket: () => WorldSocket,
  ) {}

  applySnapshot(tick: number, regionId: string, stateHash: string, deltas: EntityDelta[]) {
    this.tickSeq = tick;
    this.regionId = regionId;
    this.stateHash = stateHash;
    for (const d of deltas) this.upsertEntity(d);
  }

  applyTickDelta(tickSeq: number, stateHash: string, deltas: EntityDelta[]) {
    this.tickSeq = tickSeq;
    this.stateHash = stateHash;
    for (const d of deltas) this.upsertEntity(d);

    // After every tick where a phantom is in the air, the authoritative
    // state has not duplicated the cube — so the phantom is, by
    // definition, a divergence. Snap it away with feedback.
    if (this.phantoms.size > 0) {
      this.collapseAllPhantoms();
    }
  }

  spawnEntity(d: EntityDelta) { this.upsertEntity(d); }

  despawnEntity(id: string) {
    const em = this.entities.get(id);
    if (!em) return;
    this.scene.remove(em.mesh);
    em.dispose();
    this.entities.delete(id);
    if (this.selectedId === id) this.selectedId = null;
  }

  private upsertEntity(d: EntityDelta) {
    const existing = this.entities.get(d.entity_id);
    if (existing) {
      existing.applyAuthoritativeDelta(d);
    } else {
      const sock = this.socket();
      const ourCertId = sock.certId;
      // When the entity is controlled by our cert_id, bind the local cert so
      // the avatar color comes from the AVATAR_PALETTE. Other entities keep
      // server-supplied color.
      const certId = (d.controller && d.controller === ourCertId) ? ourCertId : null;
      const em = new EntityMesh(d.entity_id, d, certId);
      this.entities.set(d.entity_id, em);
      this.scene.add(em.mesh);
    }
  }

  select(id: string | null) {
    for (const em of this.entities.values()) em.setSelected(em.id === id);
    this.selectedId = id;
  }

  setCheatMode(on: boolean) {
    this.cheatMode = on;
    if (on) showAnnotation(ANN.cheatEnabled());
  }

  issueAction(op: EntityAction["op"], args: EntityAction["args"] = {}): void {
    const entityId = this.selectedId;
    if (!entityId) return;
    const em = this.entities.get(entityId);
    if (!em) return;

    const actionId = crypto.randomUUID();
    this.pending.set(actionId, { entityId, op, cheating: this.cheatMode && (op === "dup" || op === "drop") });

    if (op === "move") {
      const d = (args as { delta?: Vec3 }).delta ?? [0, 0, 0];
      em.predictMove(d);
    } else if (op === "dup" && this.cheatMode) {
      // Pretend DUP succeeded — spawn a visible phantom mesh.
      this.spawnPhantom(em);
    }

    const action: EntityAction = { entity_id: entityId, op, args, action_id: actionId };
    this.socket().sendAction(action).catch(() => {
      this.pending.delete(actionId);
    });
  }

  handleActionResult(actionId: string, ok: boolean, reason?: string) {
    const p = this.pending.get(actionId);
    this.pending.delete(actionId);
    if (!p) return;

    const em = this.entities.get(p.entityId);
    if (!em) return;

    if (ok) {
      showAnnotation(ANN.actionAccepted(p.op));
    } else {
      em.rejectFlash();
      if (reason === "linearity_violation") {
        showAnnotation(ANN.linearityViolation(p.op + " on LINEAR cube"));
        if (p.op === "dup") {
          this.shatters.push(new Shatter(this.scene, em.mesh.position.clone()));
        }
      }
    }
  }

  private spawnPhantom(em: EntityMesh) {
    const geom = new THREE.BoxGeometry(0.9, 0.9, 0.9);
    const mat = new THREE.MeshStandardMaterial({
      color: 0xf1c40f,
      transparent: true,
      opacity: 0.7,
      emissive: 0xf1c40f,
      emissiveIntensity: 0.4,
    });
    const phantom = new THREE.Mesh(geom, mat);
    phantom.position.copy(em.mesh.position);
    phantom.position.x += 1.2;
    phantom.userData.bornAt = performance.now();
    phantom.userData.phantomFor = em.id;
    this.scene.add(phantom);
    this.phantoms.set(crypto.randomUUID(), phantom);
  }

  private collapseAllPhantoms() {
    for (const phantom of this.phantoms.values()) {
      this.shatters.push(new Shatter(this.scene, phantom.position.clone(), 0xf1c40f));
      this.scene.remove(phantom);
      (phantom.geometry as THREE.BufferGeometry).dispose();
      (phantom.material as THREE.Material).dispose();
    }
    this.phantoms.clear();
    showAnnotation(ANN.divergence("predictor predicted DUP would succeed; kernel rejected"));
  }

  tick(dtMs: number) {
    for (const em of this.entities.values()) em.tick(dtMs);

    for (let i = this.shatters.length - 1; i >= 0; i--) {
      const done = this.shatters[i].tick(dtMs);
      if (done) {
        this.shatters[i].dispose(this.scene);
        this.shatters.splice(i, 1);
      }
    }

    // Phantoms wobble slightly so they read as "not real".
    const t = performance.now();
    for (const phantom of this.phantoms.values()) {
      const age = (t - (phantom.userData.bornAt as number)) / 1000;
      phantom.rotation.y = age * 1.5;
      phantom.position.y = 0.5 + Math.sin(age * 6) * 0.04;
    }
  }

  selectableMeshes(): THREE.Mesh[] {
    return Array.from(this.entities.values(), (em) => em.mesh);
  }
}

```
