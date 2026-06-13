---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/runtime/session-protocol/src/handoff-policy.ts
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.037393+00:00
---

# runtime/session-protocol/src/handoff-policy.ts

```ts
/**
 * Handoff-policy layer — per-object authorization for cross-party
 * bundle transfers.
 *
 * Slice 5a proved that bundles can be signed + verified.
 * Slice 5b proved that the signer's identity can be resolved against
 * a cert allowlist.
 * Slice 5c (this module) answers the remaining question on import:
 * "yes, I trust this signer — but are they allowed to send me
 * **this particular** object?"
 *
 * Concrete motivating use case: OJT has a maintenance.job for
 * property A. OJT trusts REA-1 and REA-2 as signers generally. But
 * REA-1 is the assigned agent for property A; REA-2 has nothing to
 * do with it. When REA-2 tries to send a patch for property A,
 * cert-trust passes (REA-2 is a known signer) — but the handoff
 * policy rejects because REA-2 isn't on the ACL for this object.
 *
 * The policy is two-sided by design:
 *   - canSend: sender asks "may I share this with recipientX?"
 *   - canReceive: receiver asks "may I accept this from senderX?"
 *
 * Both are evaluated at the respective party's node. A well-behaved
 * sender checks canSend before exporting; the receiver always
 * checks canReceive on import. Either check failing drops the
 * handoff cleanly.
 *
 * The policy is caller-supplied. This module ships a default
 * `allowlistHandoffPolicy` that takes plain `{objectId → allowedCertIds}`
 * maps for each direction. Production will plug in richer
 * implementations (role-based, capability-token, reputation) through
 * the same interface.
 */

// ── Input + decision shape ────────────────────────────────────

export interface HandoffContext {
  /** The object being handed off. */
  objectId: string;
  /** Optional type-path for type-level rules ("trades.job", "scada.alarm"). */
  objectType?: string;
  /** The sender's cert id. For canSend this is the local hat; for canReceive it's the remote peer. */
  senderCertId: string;
  /** The recipient's cert id. Mirror of senderCertId. */
  recipientCertId: string;
  /** Lexicon the object is being handed off under (5-4 attribution). */
  lexicon?: string;
}

export type HandoffDecision =
  | { allowed: true }
  | { allowed: false; reason: string };

/**
 * Caller-supplied handoff policy. Both methods return a
 * discriminated decision — they don't throw, even if the policy
 * needs to consult external state (a database, a revocation list,
 * a reputation service). Failed lookups should surface as
 * `{ allowed: false, reason }` so the caller knows why.
 */
export interface HandoffPolicy {
  /** Sender-side check: "am I allowed to send this to the recipient?" */
  canSend(ctx: HandoffContext): Promise<HandoffDecision>;
  /** Receiver-side check: "am I allowed to accept this from the sender?" */
  canReceive(ctx: HandoffContext): Promise<HandoffDecision>;
}

// ── Default in-memory allowlist policy ────────────────────────

export interface AllowlistHandoffPolicyConfig {
  /**
   * Per-direction ACL maps. Each entry is `{ objectId: Set<certId> }`.
   * If an objectId is missing from the map, the policy defaults to
   * deny (explicit allowlist model — safer default than implicit
   * allow).
   *
   * `canSend[objectId]` = cert ids of recipients this node is
   *   allowed to send the object to.
   * `canReceive[objectId]` = cert ids of senders this node is
   *   allowed to accept the object from.
   */
  canSend?: Map<string, Set<string>>;
  canReceive?: Map<string, Set<string>>;
  /**
   * Global fallback for objects not listed in either map. Defaults
   * to deny. Set to `"allow"` for sandboxes / early-stage test rigs
   * where every policy decision wants to default-allow.
   */
  fallback?: "deny" | "allow";
}

export function createAllowlistHandoffPolicy(
  config: AllowlistHandoffPolicyConfig = {},
): HandoffPolicy & {
  /** Add a cert to the send-ACL for an object. Idempotent. */
  allowSend(objectId: string, recipientCertId: string): void;
  /** Add a cert to the receive-ACL for an object. Idempotent. */
  allowReceive(objectId: string, senderCertId: string): void;
  /** Introspection — returns a snapshot copy of the internal state. */
  snapshot(): {
    canSend: Record<string, string[]>;
    canReceive: Record<string, string[]>;
    fallback: "deny" | "allow";
  };
} {
  const canSendAcl = new Map<string, Set<string>>(
    Array.from(config.canSend ?? new Map<string, Set<string>>(), ([k, v]): [
      string,
      Set<string>,
    ] => [k, new Set(v)]),
  );
  const canReceiveAcl = new Map<string, Set<string>>(
    Array.from(config.canReceive ?? new Map<string, Set<string>>(), ([k, v]): [
      string,
      Set<string>,
    ] => [k, new Set(v)]),
  );
  const fallback = config.fallback ?? "deny";

  const lookup = (
    acl: Map<string, Set<string>>,
    objectId: string,
    cert: string,
    label: "canSend" | "canReceive",
  ): HandoffDecision => {
    const set = acl.get(objectId);
    if (!set) {
      if (fallback === "allow") return { allowed: true };
      return {
        allowed: false,
        reason: `${label}: object ${objectId} has no ACL entries and fallback is deny`,
      };
    }
    if (set.has(cert)) return { allowed: true };
    return {
      allowed: false,
      reason: `${label}: cert ${cert} is not in the ACL for object ${objectId}`,
    };
  };

  return {
    async canSend(ctx) {
      return lookup(canSendAcl, ctx.objectId, ctx.recipientCertId, "canSend");
    },
    async canReceive(ctx) {
      return lookup(canReceiveAcl, ctx.objectId, ctx.senderCertId, "canReceive");
    },
    allowSend(objectId, recipientCertId) {
      const set = canSendAcl.get(objectId) ?? new Set<string>();
      set.add(recipientCertId);
      canSendAcl.set(objectId, set);
    },
    allowReceive(objectId, senderCertId) {
      const set = canReceiveAcl.get(objectId) ?? new Set<string>();
      set.add(senderCertId);
      canReceiveAcl.set(objectId, set);
    },
    snapshot() {
      return {
        canSend: Object.fromEntries(
          Array.from(canSendAcl, ([k, v]) => [k, Array.from(v).sort()]),
        ),
        canReceive: Object.fromEntries(
          Array.from(canReceiveAcl, ([k, v]) => [k, Array.from(v).sort()]),
        ),
        fallback,
      };
    },
  };
}

```
