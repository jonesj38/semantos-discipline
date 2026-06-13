---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/PIGGYBANK-KID-IDENTITY-MODEL.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.332788+00:00
---

# Kid identity model for BitPiggy

Status: design report, not yet applied to code.

## What you said

> kids don't have an email. I can designate a key under my key universe
> that I instantiate with a gated challenge, so I can recover my key,
> then theirs with their challenge recover it off my email.
> That should be in the plexus sdk.

So: the parent is the only email-anchored Plexus identity. Each kid is
a child certificate under the parent's DAG, with its own challenge set
that gates access to the kid's subtree. Disaster recovery is two hops:

1. Parent recovers their own root via email OTP + parent challenges
   (canonical Plexus flow).
2. Parent then unlocks each kid's subtree by answering that kid's
   challenges.

## What the Plexus spec already gives us

From `Plexus Technical Requirements Draft v1.3` pages 9–13:

- **§9 Identity Domain** — identities are BRC-52 certs anchored by
  email + OTP. Challenge sets must have ≥3 questions; answers are
  normalised and stored as SHA-256 hashes. Hierarchical authority is
  explicit: "child certificates [can] be issued and cryptographically
  signed by their parent." Root seed is always PBKDF2(email, salt,
  100 000) computed client-side.
- **§11 Recovery Service** — a four-phase flow: Email OTP → Challenge
  Response → Metadata Export → Client-Side Key Reconstruction. The
  service never reconstructs raw keys.
- **§12 Edge Domain** — native edge policies include
  `PARENT_MANAGED`, meaning the parent context is the custodian of the
  edge. This is precisely the flag we want on the parent→kid edge.

The spec does not explicitly describe "sub-identities that have their
own challenge sets but no email." Kids fit in as **child certificates
under a parent root**, plus an extra **per-kid challenge set** that
gates local access to that kid's subtree. The per-kid challenges are a
local-client construct, not a new global recovery flow — they never
involve the Plexus email OTP service.

## Proposed API

Live shape of what needs to go into `@plexus/vendor-sdk`. Nothing here
is implemented yet; this is a spec for review.

```ts
/** A challenge question with its normalised-answer hash. */
export interface GatedChallenge {
  id: string;
  prompt: string;
  /** SHA-256(normalise(answer) || perChildSalt). Never the plaintext. */
  answerHash: string;
}

/** Metadata about a kid cert that the vendor SDK can load without unlocking it. */
export interface GatedChildSummary {
  certId: string;
  localName: string;        // "Mia", "Kai" — display only, no PII
  parentCertId: string;
  challengePrompts: { id: string; prompt: string }[]; // prompts only
  createdAt: number;
}

export class VendorSDK {
  /**
   * Create a new child certificate under `parentCertId` with a
   * gated challenge set. The resulting cert is stored with its
   * derivation metadata, but the child's private-key universe is
   * only *reconstructible* when the caller later provides answers
   * that match `challenges[].answerHash`.
   *
   * Returns the certId so the parent can reference it in edges.
   * Does NOT return a private key.
   */
  createGatedChild(opts: {
    parentCertId: string;
    localName: string;
    /**
     * ≥3 challenges. Answers are normalised + hashed client-side
     * before being passed in, matching §9 constraint.
     */
    challenges: GatedChallenge[];
    /**
     * Which resource_id / domain_flag this child's subtree is rooted at.
     * For BitPiggy: resourceId='kid', domainFlag=PIGGYBANK.
     */
    resourceId: string;
    domainFlag: number;
  }): GatedChildSummary;

  /**
   * Unlock a previously created gated child. Answers are hashed
   * client-side and compared to the stored answerHashes. On success
   * the SDK derives and caches the child's private-key universe for
   * the life of the handle; on failure it throws and the attempt
   * counter on the summary is bumped (mirrors §9's account lockout).
   */
  unlockGatedChild(
    childCertId: string,
    answers: { challengeId: string; answer: string }[],
  ): GatedChildHandle;

  /**
   * List all gated children under a parent. Safe to call without
   * having unlocked anything; returns prompts + metadata only.
   */
  listGatedChildren(parentCertId: string): GatedChildSummary[];
}

/**
 * Once unlocked, acts like the parent SDK but scoped to the child's
 * subtree. Device provisioning, edge creation, signing all go through
 * the handle so the child's private-key universe never leaks to
 * callers that only have the parent root.
 */
export interface GatedChildHandle {
  certId: string;
  publicKey: string;
  deriveChild(resourceId: string, domainFlag: number):
    { certId: string; childIndex: number; publicKey: string };
  sign(messageBytes: Uint8Array): string;
  lock(): void; // wipes cached derived keys
}
```

### Derivation details

The kid's "root" inside the parent's universe is a pair of BRC-42
derivations chained together, with the kid's answer hash mixed into
the second invoice number so the child key is **not** reconstructible
by anyone who only has the parent root:

```
parentRootKey = PBKDF2(parentEmail, salt, 100 000)
kidRootKey    = deriveChildKey(
                  parentRootKey,
                  `gated-child:${kidChildIndex}:${combinedAnswerHash}`
                )
```

where `combinedAnswerHash = SHA-256(sort(answerHashes).join('|'))`
binds the kid key to the challenge answers. Forgetting the answers
means the subtree is **not recoverable from the parent root alone**,
which is the correct security property — the parent is custodian of
the cert but not gate-keeper of the key.

Per-kid backup: if Todd wants "parent-override recovery" (parent
can recover the kid even if the kid forgets the challenges), we store
a BACKUP_ON_CREATE edge recipe under the parent's
`EDGE_CREATION`/`PARENT_MANAGED` domain (§12), which essentially
Shamir-splits the answer-hash-derived seed such that the parent's
root key is one share. That would make the spec-level edge policy:

```
edgePolicy: 'PARENT_MANAGED'         // parent custodian
recoveryPolicy: 'BACKUP_ON_CREATE'   // recipe stored at create time
```

so the parent can always restore kid keys even without the challenge
answers. I'd recommend leaving this **off by default** and letting you
opt in per child; it's a real trade-off (stronger UX vs. the parent
becoming a single point of compromise for the kid's BSV).

## What changes in BitPiggy

### `docs/PIGGYBANK-BUILD-PLAN.md`

The "Identity tree" section moves from:

```
parent (email) ─┐
kid "Mia" (email=mia@family.local) ─┬─ device/PIGGYBANK
kid "Kai" (email=kai@family.local) ─┴─ device/PIGGYBANK
```

to:

```
parent (email=todd@…, plexus-anchored)
│
├── family/FAMILY_SYNC              (used to sign outbound sync)
│
├── gated-child:Mia (challenge set: …)          <-- local-only, no email
│   └── device/PIGGYBANK
│
└── gated-child:Kai (challenge set: …)          <-- local-only, no email
    └── device/PIGGYBANK
```

Kid challenge sets are captured in the iPad app when a kid identity is
first set up. Prompts should be things the kid can reliably answer but
wouldn't leak to a classmate ("what's the name of your stuffed
elephant?", "what was our old dog called?"). Todd enters the answers
during setup.

### `scripts/piggybank/provision-dryrun.ts`

Shape of the revised main function (as spec, not final code):

```ts
const sdk = new VendorSDK({ dbPath: ':memory:', salt, pbkdf2Iterations });
const parent = sdk.registerIdentity(parentEmail);

// Stand-in challenges for the dry-run. Real setup will capture these
// from the iPad app.
const miaChallenges = [
  { id: 'q1', prompt: 'Favourite dinosaur?', answer: 'triceratops' },
  { id: 'q2', prompt: 'Stuffed elephant name?', answer: 'peanut' },
  { id: 'q3', prompt: 'Favourite colour?', answer: 'purple' },
];

const miaSummary = sdk.createGatedChild({
  parentCertId: parent.certId,
  localName: 'Mia',
  challenges: miaChallenges.map(c => ({
    id: c.id,
    prompt: c.prompt,
    answerHash: hashAnswer(c.answer),
  })),
  resourceId: 'kid',
  domainFlag: PIGGYBANK,
});

// Unlock before provisioning
const mia = sdk.unlockGatedChild(
  miaSummary.certId,
  miaChallenges.map(c => ({ challengeId: c.id, answer: c.answer })),
);

// Provisioner now works against the handle, not the root SDK
const result = await runProvisioner({ socket, handle: mia, … });
```

### `scripts/piggybank/provision-parent.ts`

`ProvisionerConfig` loses `kidEmail`, `kidCertId`, and the
`salt`/`pbkdf2Iterations` fields (those are the parent SDK's business
now). It gains a `handle: GatedChildHandle` that exposes
`handle.deriveChild('device', PIGGYBANK)` and `handle.sign(...)`.

The `kidRootKey = deriveRootKey(kidEmail, salt, iterations)` block
disappears entirely — kids don't have a root key derivable from email.
The device key is derived off the handle's in-memory cached kid-root.

### Recovery story (end-to-end)

1. Todd replaces iPad. Installs BitPiggy, opens with a fresh
   VendorSDK.
2. VendorSDK runs canonical Plexus recovery: email OTP → parent
   challenges → metadata export → parent root reconstructed locally.
3. VendorSDK restores gated-child **summaries** (prompts, metadata) —
   but NOT the kid keys, since the challenge answers aren't stored
   anywhere server-side.
4. For each kid, Todd (or the kid) answers challenges locally. SDK
   rebuilds that kid's root key from `parentRootKey` +
   `combinedAnswerHash`.
5. Device keeps working because its privkey is stored PIN-wrapped in
   NVS on the XIAO-C6; LAN pairing re-negotiates only the edge. No
   re-flash needed.

If the `BACKUP_ON_CREATE` edge recipe was created at setup, step 4
can be skipped for a child — the parent can restore from the
edge recipe alone. This is the opt-in convenience mode.

## Open decisions

1. **Should `createGatedChild` require the parent root to be
   unlocked?** Yes — keeps the invariant that only the rightful
   parent can create kid slots.
2. **Where do kid challenges live on disk?** Local SQLite table
   `gated_children` on the iPad app only. Never synced to Plexus
   Cloud. Prompts can sync; answerHashes must not.
3. **What happens if an answer is misremembered?** Mirror §9:
   5 consecutive failures → subtree locked for N hours. Not account-
   wide, just that kid.
4. **Default `recoveryPolicy`?** Propose `NONE` (forgetting answers
   = losing the kid's on-device BSV; can always re-provision a new
   device from a freshly-created gated child). Todd opts into
   `BACKUP_ON_CREATE` per kid if he wants belt + suspenders.
5. **Plugging the device KID into the on-chain DAG.** The kid's cert
   ID is still a BRC-52 cert signed by the parent, so it registers
   into Plexus's canonical registry the same way a normal child would.
   The only thing private about it is the challenge gate.

## Next step

If this model looks right, the concrete changes that follow are:

- Add the methods above to `core/plexus-vendor-sdk/src/VendorSDK.ts`,
  a new `store.ts` table for gated children, and a `gated.ts` module
  for the hash + derivation helpers.
- Rewrite `scripts/piggybank/provision-parent.ts` to take a
  `GatedChildHandle`.
- Rewrite `scripts/piggybank/provision-dryrun.ts` to create + unlock
  Mia and Kai as gated children rather than email-registered
  identities.
- Update `docs/PIGGYBANK-BUILD-PLAN.md`'s identity-tree section to
  match.

I'll hold off on making those changes until you've sanity-checked the
API shape and the derivation rule.
