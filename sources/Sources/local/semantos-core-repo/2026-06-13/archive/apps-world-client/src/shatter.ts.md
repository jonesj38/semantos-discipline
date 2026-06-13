---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-world-client/src/shatter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.821327+00:00
---

# archive/apps-world-client/src/shatter.ts

```ts
import * as THREE from "three";

export class Shatter {
  private readonly group: THREE.Group;
  private readonly shards: {
    mesh: THREE.Mesh;
    velocity: THREE.Vector3;
    angVelocity: THREE.Vector3;
  }[] = [];
  private readonly startTime: number;
  private readonly durationMs: number;

  constructor(parent: THREE.Scene, origin: THREE.Vector3, color = 0xe74c3c) {
    this.startTime = performance.now();
    this.durationMs = 700;

    this.group = new THREE.Group();
    this.group.position.copy(origin);
    parent.add(this.group);

    const shardGeom = new THREE.BoxGeometry(0.22, 0.22, 0.22);
    const shardMat = new THREE.MeshStandardMaterial({
      color,
      emissive: new THREE.Color(color).multiplyScalar(0.6),
      transparent: true,
      opacity: 1,
    });

    for (let i = 0; i < 16; i++) {
      const mesh = new THREE.Mesh(shardGeom, shardMat.clone());
      const dir = new THREE.Vector3(
        Math.random() - 0.5,
        Math.random() * 0.8,
        Math.random() - 0.5,
      ).normalize();
      const speed = 2 + Math.random() * 3;
      this.shards.push({
        mesh,
        velocity: dir.multiplyScalar(speed),
        angVelocity: new THREE.Vector3(
          (Math.random() - 0.5) * 10,
          (Math.random() - 0.5) * 10,
          (Math.random() - 0.5) * 10,
        ),
      });
      this.group.add(mesh);
    }
  }

  tick(dtMs: number): boolean {
    const dt = dtMs / 1000;
    const age = performance.now() - this.startTime;
    const t = Math.min(age / this.durationMs, 1);

    for (const s of this.shards) {
      s.velocity.y -= 9.81 * dt;
      s.mesh.position.x += s.velocity.x * dt;
      s.mesh.position.y += s.velocity.y * dt;
      s.mesh.position.z += s.velocity.z * dt;
      s.mesh.rotation.x += s.angVelocity.x * dt;
      s.mesh.rotation.y += s.angVelocity.y * dt;
      s.mesh.rotation.z += s.angVelocity.z * dt;
      (s.mesh.material as THREE.MeshStandardMaterial).opacity = 1 - t;
    }

    return t >= 1;
  }

  dispose(parent: THREE.Scene) {
    parent.remove(this.group);
    for (const s of this.shards) {
      (s.mesh.geometry as THREE.BufferGeometry).dispose();
      (s.mesh.material as THREE.Material).dispose();
    }
  }
}

```
