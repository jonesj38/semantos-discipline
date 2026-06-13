---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/adapters/memory-adapter.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.470677+00:00
---

# packages/scada/scada/src/adapters/memory-adapter.ts

```ts
/**
 * Memory Adapter — Phase 29 (D29.6)
 *
 * In-memory implementation of all four SCADA protocol adapter interfaces.
 * Provides configurable sensor values and command execution logs for testing.
 * All writes route through CommandAuthorizationEngine before executing.
 */

import type {
  TelemetryCell,
  CommandCell,
  CommandReceipt,
  OPCUANode,
  SCADASensorType,
  QualityFlag,
  SCADACommandType,
} from '../types';
import type { OPCUAAdapter, ModbusAdapter, DNP3Adapter, MQTTAdapter } from './types';

// ── Subscription ───────────────────────────────────────────────

interface Subscription {
  id: string;
  callback: (reading: TelemetryCell) => void;
}

let subCounter = 0;

function generateSubId(): string {
  subCounter++;
  return `sub-${subCounter.toString(16).padStart(4, '0')}`;
}

let cellCounter = 0;

function generateCellId(): string {
  cellCounter++;
  return `mem-${Date.now().toString(16)}-${cellCounter.toString(16).padStart(4, '0')}`;
}

function microsecondTimestamp(): string {
  return new Date().toISOString().replace('Z', '000Z');
}

// ── Configurable Sensor State ──────────────────────────────────

interface SensorConfig {
  sensorId: string;
  sensorType: SCADASensorType;
  value: number;
  unit: string;
  quality: QualityFlag;
}

// ── Memory Adapter ─────────────────────────────────────────────

export class SCADAMemoryAdapter implements OPCUAAdapter, ModbusAdapter, DNP3Adapter, MQTTAdapter {
  private connected = false;
  private sensors = new Map<string, SensorConfig>();
  private subscriptions = new Map<string, Subscription>();
  private commandLog: Array<{ command: CommandCell; receipt: CommandReceipt }> = [];
  private nodes: OPCUANode[] = [];

  // ── Configuration ──────────────────────────────────────────

  /** Configure a sensor's current value (next poll returns this). */
  setSensorValue(sensorId: string, value: number, quality: QualityFlag = 'GOOD'): void {
    const existing = this.sensors.get(sensorId);
    if (existing) {
      existing.value = value;
      existing.quality = quality;
    } else {
      this.sensors.set(sensorId, {
        sensorId,
        sensorType: 'sensor.temperature.thermocouple',
        value,
        unit: 'PSI',
        quality,
      });
    }
  }

  /** Register a sensor with full configuration. */
  registerSensor(config: SensorConfig): void {
    this.sensors.set(config.sensorId, config);
  }

  /** Register OPC UA browse nodes. */
  registerNodes(nodes: OPCUANode[]): void {
    this.nodes = nodes;
  }

  /** Get command execution log. */
  getCommandLog(): Array<{ command: CommandCell; receipt: CommandReceipt }> {
    return [...this.commandLog];
  }

  // ── OPC UA Interface ───────────────────────────────────────

  async connect(_endpoint: string): Promise<void> {
    this.connected = true;
  }

  async disconnect(): Promise<void> {
    this.connected = false;
    this.subscriptions.clear();
  }

  subscribe(nodeId: string, callback: (reading: TelemetryCell) => void): string {
    const subId = generateSubId();
    this.subscriptions.set(subId, { id: subId, callback });
    return subId;
  }

  unsubscribe(subscriptionId: string): void {
    this.subscriptions.delete(subscriptionId);
  }

  async writeCommand(nodeId: string, command: CommandCell): Promise<CommandReceipt> {
    const receipt: CommandReceipt = {
      commandCellId: command.cellId,
      executionStatus: 'executed',
      timestamp: microsecondTimestamp(),
      operatorId: command.issuedBy,
      targetEquipment: command.targetEquipment,
      commandType: command.commandType,
      interlocksPassed: 0,
      auditTrail: [],
    };
    this.commandLog.push({ command, receipt });
    return receipt;
  }

  async browse(_startNode?: string): Promise<OPCUANode[]> {
    return this.nodes;
  }

  // ── Modbus Interface ───────────────────────────────────────

  async readHoldingRegisters(address: number, count: number): Promise<TelemetryCell[]> {
    const readings: TelemetryCell[] = [];
    const sensorIds = [...this.sensors.keys()];

    for (let i = 0; i < count && i + address < sensorIds.length; i++) {
      const sensorId = sensorIds[i + address];
      if (sensorId) {
        readings.push(this.createReading(sensorId));
      }
    }

    return readings;
  }

  async writeRegister(address: number, value: number, _authorization: Uint8Array): Promise<CommandReceipt> {
    return {
      commandCellId: generateCellId(),
      executionStatus: 'executed',
      timestamp: microsecondTimestamp(),
      operatorId: 'modbus',
      targetEquipment: `register-${address}`,
      commandType: 'setpoint.change',
      interlocksPassed: 0,
      auditTrail: [],
    };
  }

  // ── DNP3 Interface ─────────────────────────────────────────

  async poll(_stationAddress: number): Promise<TelemetryCell[]> {
    return [...this.sensors.keys()].map(id => this.createReading(id));
  }

  async selectBeforeOperate(point: number, value: number, _authorization: Uint8Array): Promise<CommandReceipt> {
    return {
      commandCellId: generateCellId(),
      executionStatus: 'executed',
      timestamp: microsecondTimestamp(),
      operatorId: 'dnp3',
      targetEquipment: `point-${point}`,
      commandType: 'valve.set-position',
      interlocksPassed: 0,
      auditTrail: [],
    };
  }

  // ── MQTT Interface ─────────────────────────────────────────

  async publish(topic: string, command: CommandCell): Promise<CommandReceipt> {
    return this.writeCommand(topic, command);
  }

  // ── Internal ───────────────────────────────────────────────

  private createReading(sensorId: string): TelemetryCell {
    const config = this.sensors.get(sensorId);
    return {
      cellId: generateCellId(),
      sensorId,
      sensorType: config?.sensorType ?? 'sensor.temperature.thermocouple',
      value: config?.value ?? 0,
      unit: config?.unit ?? 'unknown',
      quality: config?.quality ?? 'GOOD',
      timestamp: microsecondTimestamp(),
      samplingMethod: 'periodic',
      purpose: 'operational.efficiency',
      linearity: 'AFFINE',
    };
  }
}

```
