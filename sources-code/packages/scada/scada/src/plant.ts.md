---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/plant.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.469669+00:00
---

# packages/scada/scada/src/plant.ts

```ts
/**
 * Plant Model — Phase 29 (D29.5)
 *
 * Hierarchical plant topology following ISA-95 / IEC 62264:
 * Enterprise > Site > Area > Unit > Equipment
 *
 * Equipment cells are RELEVANT — they cannot be deleted, only
 * decommissioned (new cell with OFFLINE status).
 */

import type {
  EquipmentCell,
  TelemetryCell,
  AlarmCell,
  PlantStatusSummary,
  OperatorRole,
} from './types';

// ── Plant Model ────────────────────────────────────────────────

export class PlantModel {
  /** Equipment cells indexed by equipment ID. */
  private equipment = new Map<string, EquipmentCell>();

  /** Parent → children relationships. */
  private children = new Map<string, Set<string>>();

  /** Child → parent relationship. */
  private parent = new Map<string, string>();

  /** Equipment → sensor associations. */
  private sensors = new Map<string, Set<string>>();

  /** Active alarms (reference — updated externally). */
  private alarmSource?: () => AlarmCell[];

  /** Active operators (reference — updated externally). */
  private operatorSource?: () => Array<{ id: string; role: OperatorRole; shiftEnd: string }>;

  /**
   * Register equipment in the plant hierarchy.
   * Equipment cells are RELEVANT — once registered, they cannot be deleted.
   */
  registerEquipment(equipment: EquipmentCell, parentId?: string): string {
    this.equipment.set(equipment.equipmentId, equipment);

    if (parentId) {
      this.parent.set(equipment.equipmentId, parentId);
      const siblings = this.children.get(parentId) ?? new Set();
      siblings.add(equipment.equipmentId);
      this.children.set(parentId, siblings);
    }

    // Initialize child equipment references
    if (equipment.childEquipment) {
      const childSet = this.children.get(equipment.equipmentId) ?? new Set();
      for (const childId of equipment.childEquipment) {
        childSet.add(childId);
        this.parent.set(childId, equipment.equipmentId);
      }
      this.children.set(equipment.equipmentId, childSet);
    }

    return equipment.equipmentId;
  }

  /** Get equipment by tag number. */
  getEquipment(equipmentId: string): EquipmentCell | null {
    return this.equipment.get(equipmentId) ?? null;
  }

  /** Get all child equipment. */
  getChildren(equipmentId: string): EquipmentCell[] {
    const childIds = this.children.get(equipmentId);
    if (!childIds) return [];
    return [...childIds]
      .map(id => this.equipment.get(id))
      .filter((e): e is EquipmentCell => e !== undefined);
  }

  /** Get equipment hierarchy path (root → leaf). */
  getPath(equipmentId: string): EquipmentCell[] {
    const path: EquipmentCell[] = [];
    let currentId: string | undefined = equipmentId;

    while (currentId) {
      const equip = this.equipment.get(currentId);
      if (equip) {
        path.unshift(equip);
      }
      currentId = this.parent.get(currentId);
    }

    return path;
  }

  /** Associate a sensor with equipment. */
  associateSensor(equipmentId: string, sensorId: string): void {
    const sensorSet = this.sensors.get(equipmentId) ?? new Set();
    sensorSet.add(sensorId);
    this.sensors.set(equipmentId, sensorSet);
  }

  /** Get all sensor IDs associated with equipment. */
  getSensors(equipmentId: string): string[] {
    const sensorSet = this.sensors.get(equipmentId);
    return sensorSet ? [...sensorSet] : [];
  }

  /** Get all interlock policy cell IDs installed on equipment. */
  getInterlocks(equipmentId: string): string[] {
    const equip = this.equipment.get(equipmentId);
    return equip?.installedPolicies ?? [];
  }

  /** Set alarm source for plant status. */
  setAlarmSource(source: () => AlarmCell[]): void {
    this.alarmSource = source;
  }

  /** Set operator source for plant status. */
  setOperatorSource(source: () => Array<{ id: string; role: OperatorRole; shiftEnd: string }>): void {
    this.operatorSource = source;
  }

  /** Get plant-wide status summary. */
  getPlantStatus(): PlantStatusSummary {
    let healthy = 0;
    let degraded = 0;
    let faulted = 0;
    let offline = 0;

    for (const equip of this.equipment.values()) {
      switch (equip.healthStatus) {
        case 'HEALTHY': healthy++; break;
        case 'DEGRADED': degraded++; break;
        case 'FAULTED': faulted++; break;
        case 'OFFLINE': offline++; break;
      }
    }

    // Alarm counts
    const alarms = this.alarmSource?.() ?? [];
    const activeAlarms = { low: 0, medium: 0, high: 0, critical: 0 };
    let unacknowledgedAlarms = 0;

    for (const alarm of alarms) {
      if (!alarm.consumed) {
        switch (alarm.severity) {
          case 'LOW': activeAlarms.low++; break;
          case 'MEDIUM': activeAlarms.medium++; break;
          case 'HIGH': activeAlarms.high++; break;
          case 'CRITICAL': activeAlarms.critical++; break;
        }
        unacknowledgedAlarms++;
      }
    }

    return {
      totalEquipment: this.equipment.size,
      healthy,
      degraded,
      faulted,
      offline,
      activeAlarms,
      unacknowledgedAlarms,
      activeOperators: this.operatorSource?.() ?? [],
    };
  }

  /** Get all registered equipment. */
  getAllEquipment(): EquipmentCell[] {
    return [...this.equipment.values()];
  }
}

```
