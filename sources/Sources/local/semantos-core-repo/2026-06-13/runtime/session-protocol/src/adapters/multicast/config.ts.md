---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/config.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.064102+00:00
---

# runtime/session-protocol/src/adapters/multicast/config.ts

```ts
/**
 * config — pure config-resolution helpers for `MulticastAdapter`.
 *
 * Splitting the public/private config types and the defaulting
 * function out of the orchestrator keeps the adapter file focused on
 * lifecycle and dispatch.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ./multicast-adapter.ts — caller that consumes these helpers
 */

import type { UdpTransport } from "@semantos/protocol-types/adapters/udp-transport";
import type {
  HeartbeatSink,
  TopicToGroup,
  TxidProvider,
} from "../../types.js";
import type { BCAProvider } from "../bca-provider.js";

import {
  createDefaultCodec,
  type CodecPort,
} from "./ports/codec-port.js";
import { defaultTopicToGroup } from "../../topics.js";
import type { NodeMetadataProvider } from "./types.js";
import { HEADER_SIZE } from "./wire-header.js";

export const DEFAULT_PORT = 5683;
export const DEFAULT_MAX_PAYLOAD = 65507 - HEADER_SIZE;
export const DEFAULT_HEARTBEAT_MS = 5000;
export const DEFAULT_STALE_MS = 15000;
export const DEFAULT_PRIMARY_GROUP = "ff02::1";
export const DEFAULT_TOPIC = "tm_semantos_objects";

export interface MulticastAdapterConfig {
  identity: BCAProvider;
  transport: UdpTransport;
  txidProvider: TxidProvider;
  /** Pluggable codec for envelope bodies. Defaults to CBOR/JSON-fallback. */
  codec?: CodecPort;
  topicToGroup?: TopicToGroup;
  heartbeatSink?: HeartbeatSink;
  metadataProvider?: NodeMetadataProvider;
  port?: number;
  primaryGroup?: string;
  maxPayload?: number;
  heartbeatIntervalMs?: number;
  staleTimeoutMs?: number;
}

export interface ResolvedConfig {
  identity: BCAProvider;
  transport: UdpTransport;
  txidProvider: TxidProvider;
  codec: CodecPort;
  topicToGroup: TopicToGroup;
  heartbeatSink?: HeartbeatSink;
  metadataProvider?: NodeMetadataProvider;
  port: number;
  primaryGroup: string;
  maxPayload: number;
  heartbeatIntervalMs: number;
  staleTimeoutMs: number;
}

export function resolveConfig(c: MulticastAdapterConfig): ResolvedConfig {
  return {
    identity: c.identity,
    transport: c.transport,
    txidProvider: c.txidProvider,
    codec: c.codec ?? createDefaultCodec(),
    topicToGroup: c.topicToGroup ?? defaultTopicToGroup,
    heartbeatSink: c.heartbeatSink,
    metadataProvider: c.metadataProvider,
    port: c.port ?? DEFAULT_PORT,
    primaryGroup: c.primaryGroup ?? DEFAULT_PRIMARY_GROUP,
    maxPayload: c.maxPayload ?? DEFAULT_MAX_PAYLOAD,
    heartbeatIntervalMs: c.heartbeatIntervalMs ?? DEFAULT_HEARTBEAT_MS,
    staleTimeoutMs: c.staleTimeoutMs ?? DEFAULT_STALE_MS,
  };
}

```
