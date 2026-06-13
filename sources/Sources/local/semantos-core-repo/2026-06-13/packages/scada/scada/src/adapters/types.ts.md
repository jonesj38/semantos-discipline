---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/packages/scada/scada/src/adapters/types.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.470386+00:00
---

# packages/scada/scada/src/adapters/types.ts

```ts
/**
 * Protocol Adapter Interfaces — Phase 29 (D29.6)
 *
 * Interface definitions for four standard SCADA protocols.
 * These are interface stubs — concrete implementations require
 * hardware testing and are out of scope for this phase.
 *
 * All reads produce TelemetryCell objects.
 * All writes consume CommandCell objects and route through
 * the CommandAuthorizationEngine before executing.
 */

import type {
  TelemetryCell,
  CommandCell,
  CommandReceipt,
  OPCUANode,
} from '../types';

/** OPC UA adapter — the modern industrial standard. */
export interface OPCUAAdapter {
  connect(endpoint: string): Promise<void>;
  disconnect(): Promise<void>;
  subscribe(nodeId: string, callback: (reading: TelemetryCell) => void): string;
  unsubscribe(subscriptionId: string): void;
  writeCommand(nodeId: string, command: CommandCell): Promise<CommandReceipt>;
  browse(startNode?: string): Promise<OPCUANode[]>;
}

/** Modbus adapter — legacy but ubiquitous. */
export interface ModbusAdapter {
  connect(host: string, port: number): Promise<void>;
  disconnect(): Promise<void>;
  readHoldingRegisters(address: number, count: number): Promise<TelemetryCell[]>;
  writeRegister(address: number, value: number, authorization: Uint8Array): Promise<CommandReceipt>;
}

/** DNP3 adapter — power grid / water treatment. */
export interface DNP3Adapter {
  connect(host: string, port: number): Promise<void>;
  disconnect(): Promise<void>;
  poll(stationAddress: number): Promise<TelemetryCell[]>;
  selectBeforeOperate(point: number, value: number, authorization: Uint8Array): Promise<CommandReceipt>;
}

/** MQTT adapter — IIoT telemetry. */
export interface MQTTAdapter {
  connect(broker: string): Promise<void>;
  disconnect(): Promise<void>;
  subscribe(topic: string, callback: (reading: TelemetryCell) => void): string;
  unsubscribe(subscriptionId: string): void;
  publish(topic: string, command: CommandCell): Promise<CommandReceipt>;
}

```
