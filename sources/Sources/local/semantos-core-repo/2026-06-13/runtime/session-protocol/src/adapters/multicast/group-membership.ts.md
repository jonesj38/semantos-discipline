---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/adapters/multicast/group-membership.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.065240+00:00
---

# runtime/session-protocol/src/adapters/multicast/group-membership.ts

```ts
/**
 * group-membership — tracks which multicast groups we have asked the
 * underlying transport to join, and the topics that depend on each
 * group.
 *
 * Splitting this out lets the orchestrator stay focused on dispatch:
 * `ensureMembership(group)` is idempotent join, `maybeDropGroup(topic)`
 * leaves the group only if no remaining subscribed topic still maps to
 * it. The primary group (used for heartbeats) is never left.
 *
 * Cross-references:
 *   docs/prd/refactor-monoliths/38-multicast-adapter-split.md
 *   ../multicast-adapter.ts (legacy) — `joinedGroups` + `subscribedTopics`
 */

import type { UdpTransport } from "@semantos/protocol-types/adapters/udp-transport";
import type { TopicToGroup } from "../../types.js";

export interface GroupMembershipConfig {
  transport: UdpTransport;
  topicToGroup: TopicToGroup;
  primaryGroup: string;
}

export interface GroupMembership {
  /** Idempotent join. Errors are swallowed (see notes in legacy code). */
  ensureMembership(group: string): Promise<void>;
  /**
   * Leave the group derived from `topic` if no other still-subscribed
   * topic maps to that group, and the group is not the primary group.
   */
  maybeDropGroup(
    droppedTopic: string,
    stillSubscribedTopics: Iterable<string>,
  ): void;
  /** Snapshot of joined groups; used by tests + diagnostics. */
  joined(): ReadonlySet<string>;
  /** Mark a group as joined without calling the transport. */
  markJoined(group: string): void;
}

export function createGroupMembership(
  config: GroupMembershipConfig,
): GroupMembership {
  const joinedGroups = new Set<string>();

  return {
    async ensureMembership(group: string): Promise<void> {
      if (joinedGroups.has(group)) return;
      try {
        await config.transport.addMembership(group);
        joinedGroups.add(group);
      } catch {
        /* loopback transport is permissive; real transports surface elsewhere */
      }
    },
    maybeDropGroup(
      droppedTopic: string,
      stillSubscribedTopics: Iterable<string>,
    ): void {
      const droppedGroup = config.topicToGroup(droppedTopic);
      if (droppedGroup === config.primaryGroup) return;
      for (const t of stillSubscribedTopics) {
        if (config.topicToGroup(t) === droppedGroup) return;
      }
      joinedGroups.delete(droppedGroup);
      config.transport.dropMembership(droppedGroup).catch(() => {});
    },
    joined(): ReadonlySet<string> {
      return joinedGroups;
    },
    markJoined(group: string): void {
      joinedGroups.add(group);
    },
  };
}

```
