---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/28-build-your-first-adapter-kanban.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.652897+00:00
---

> **⚠ Reframed by Ch.37 (Wave Canonical-Cartridge, 2026-05-18).**
> What this chapter calls an "adapter" / "extension" is a **cartridge**
> (here, role `experience`); it installs via one `cartridge.json` (not
> the four-tier extension model), is owned by an affine PushDrop
> license UTXO, and is loaded by the Brain shell + PWA shell. The
> kanban **walkthrough mechanics** (cells, capability consumption,
> hash-chain audit) remain correct; read "adapter/extension" as
> "cartridge". See Ch.37 + `docs/design/CANONICAL-CARTRIDGE-MODEL.md`.

# Build your first adapter — kanban in 30 minutes

Part VIII of this textbook has established what the substrate provides: cells, the cell engine, jural-typed cells at the SIR layer, a hash chain as an evidence chain, capability tokens as the mechanism for authorised state change, hats as the signing principals, and the extension model as the installation path. This chapter connects those elements into one buildable thing: a kanban adapter.

A kanban board — columns, cards, movement — is the shortest route to a working adapter because it exercises every substrate primitive exactly once. One card is one cell. Moving a card across a column boundary is a capability token consumption. A comment on a card is a patch cell. The complete history of a board is a hash chain that constitutes a regulator-grade audit trail. The adapter installs as an extension via the four-tier model described in `docs/EXTENSIONS-VS-TYPES.md` and is packaged for distribution through the standard extension manifest.

The reader who completes this chapter will have: a typed `KanbanCard` cell definition; a column state machine with jural-category-typed transitions; a comment model that patches the card cell; an evidence chain covering the board's full history; and the deploy command. Where the deploy command invokes infrastructure that is scheduled under the Unification Matrix but not yet enforced in the current build, this chapter identifies those steps explicitly as future state.

This chapter assumes the reader has completed Chapter 27 (a running sovereign node) and Chapter 5 (hats and capability tokens). K1 — which states that a LINEAR cell must be consumed exactly once — governs card movement throughout and is the mechanical guarantee that a card cannot occupy two columns simultaneously.

---

## The problem

A conventional kanban tool stores card state in a mutable database row. Moving a card from "To Do" to "In Progress" is an UPDATE statement: the old state is overwritten, the before-image is gone unless an audit log was bolted on separately, and the audit log — if it exists — is outside the enforced data model. Two consequences follow. First, the audit log can be tampered with independently of the board state, because it is a separate table with no cryptographic link to the card record. Second, the authority model is advisory: the application layer checks whether the acting user has permission to move a card, but the storage layer does not enforce this structurally. A sufficiently privileged database operator can move any card without leaving a trace in the audit log.

The substrate inverts this. The card is a cell. Moving it is not an UPDATE; it is the creation of a successor cell that carries a `prevStateHash` pointing to its predecessor, signed by the hat that performed the move, with a capability token proving the hat held the authority to make that transition at the moment of signing. The audit trail is not a separate log; it is the hash chain itself. Tampering with any predecessor cell breaks every successor's `prevStateHash`, which the cell engine detects at K7 (cell immutability). The board's history is therefore evidence chain by construction, not by convention.

This is what makes the kanban domain suitable as a first adapter. It is small enough to build in thirty minutes, consequential enough to illustrate every substrate primitive, and structurally identical — at the adapter layer — to more complex verticals such as property management or CDM lifecycle processing. The column state machine here is simpler than a CDM novation chain, but the shape is the same.

---

## Cells and columns

### The KanbanCard cell

A cell is the primary unit handled by the cell engine: a 1024-byte binary structure with a 256-byte typed header followed by payload, plus optional continuation cells for overflow. For a kanban card the payload is small enough to fit without continuations.

The header carries, among other fields, the linearity class. K1 states that a LINEAR cell must be consumed exactly once. A kanban card is a LINEAR resource: it exists in exactly one column at any moment. A card that has been moved to "In Progress" cannot also remain in "To Do". The linearity class enforces this structurally at the bytecode gate, not by application convention.

The TypeScript type sketch for the card's payload:

```ts
/** KanbanCard payload — fits within the 768-byte cell payload limit. */
interface KanbanCardPayload {
  title: string;           // max 120 bytes UTF-8
  description: string;     // max 512 bytes UTF-8
  column: ColumnId;        // current column — the canonical position
  assignedHat: string;     // hat cert_id of the assignee (may be empty)
  priority: 0 | 1 | 2;    // 0 = low, 1 = normal, 2 = high
  dueAt?: string;          // ISO-8601 timestamp or absent
}

type ColumnId = 'backlog' | 'todo' | 'in-progress' | 'review' | 'done';
```

The cell header fields relevant to the adapter:

| Header field    | Value for KanbanCard                        |
|-----------------|---------------------------------------------|
| `typeHash`      | SHA-256 of `"kanban.card.v1"` type string   |
| `linearity`     | `0` — LINEAR (K1-enforced, exactly once)    |
| `ownerCertId`   | `cert_id` of the creating hat               |
| `prevStateHash` | zero bytes on creation; prior cell's hash on each move |
| `pipelinePhase` | `0x02` — RELEVANT (card exists until done)  |

When the adapter creates a new card it packs the header, sets linearity to LINEAR, and signs the resulting cell under the creating hat's BRC-52 cert. The cell engine's K7 invariant (cell immutability) seals the cell after packing: the header fields, including linearity, are read-only thereafter. A cell cannot retroactively become non-LINEAR.

### Building the cell

```ts
import { packCell, CellHeader, Linearity, PipelinePhase } from '@semantos/cell-ops';
import { hashTypeString } from '@semantos/cell-engine';

const KANBAN_CARD_TYPE_HASH = hashTypeString('kanban.card.v1');

function createCard(
  payload: KanbanCardPayload,
  ownerCertId: string,
): Uint8Array {
  const header: CellHeader = {
    typeHash:      KANBAN_CARD_TYPE_HASH,
    linearity:     Linearity.LINEAR,           // K1: consumed exactly once
    pipelinePhase: PipelinePhase.RELEVANT,
    ownerCertId,
    version:       1,
    timestamp:     Date.now(),
    prevStateHash: new Uint8Array(32),         // zero on creation
    parentHash:    new Uint8Array(32),         // zero (no parent cell)
  };

  return packCell(header, encodePayload(payload));
}
```

`packCell` is provided by `@semantos/cell-ops`. It assembles the 256-byte header, validates field boundaries, computes the cell hash, and returns the sealed binary. The cell is ready to be placed in the VFS under an octave path derived from the board's governance domain.

### Column model

Columns are not cells. A column is a state in the card's state machine; the card's `column` payload field records which state the card currently occupies. This is the correct model: the card is the resource; its position in the column sequence is a property of the card, not a separate entity. Storing columns as separate cells would produce a many-to-many relationship that the LINEAR linearity class cannot enforce — a card could be referenced from multiple column cells without K1 detecting the violation, because K1 operates on the card cell, not on external references to it.

The column state machine for the standard five-column board:

```
[FIGURE — needs real graphic for layout pass]

  backlog ──► todo ──► in-progress ──► review ──► done
                ▲           │
                └───────────┘   (return from in-progress to todo: blocked)
```

ASCII representation:

```
backlog → todo → in-progress → review → done
                 in-progress → todo   (blocked path)
```

Permitted transitions and the jural category of each:

| From          | To            | Jural category | Capability required      |
|---------------|---------------|----------------|--------------------------|
| `backlog`     | `todo`        | power          | `cap.kanban.move`        |
| `todo`        | `in-progress` | power          | `cap.kanban.move`        |
| `in-progress` | `review`      | power          | `cap.kanban.move`        |
| `in-progress` | `todo`        | power          | `cap.kanban.move`        |
| `review`      | `done`        | power          | `cap.kanban.approve`     |
| `review`      | `in-progress` | power          | `cap.kanban.move`        |
| (any)         | (any invalid) | prohibition    | — (structurally refused) |

Moving a card is a power jural category: the acting hat exercises authority to change the card's legal position in the workflow. The `review → done` transition requires the elevated `cap.kanban.approve` capability token, because accepting work into done is a higher-authority act than moving a card through intermediate columns.

The prohibition row covers all transitions not listed. The SIR layer types the attempted transition as a prohibition, and the lower pass refuses to produce OIR for it. The cell engine never sees the request; it is rejected structurally before bytecode generation.

---

## Movement as capability token consumption

### The capability token

A capability token is a BRC-108-formatted UTXO bound to a BRC-52 cert subject that grants time-bounded authority to perform a specific action class. Spending the UTXO atomically revokes the capability — capability tokens are LINEAR resources (K1 governs them as surely as it governs the card cell itself).

For the kanban adapter, two capability token classes are relevant:

- `cap.kanban.move` — authorises any non-approval column transition. Held by any hat assigned to a card or listed as a board member.
- `cap.kanban.approve` — authorises the `review → done` transition. Held by hats designated as reviewers in the board's governance domain configuration.

A capability token in the conventional sense of "permission" would be advisory — the application could check it, or not, and the storage layer would not notice either way. Under BRC-108 the token is a UTXO: the hat that performs the move submits a transaction that spends the capability UTXO. Spending it atomically records the move on-chain (via the MFP metering path, gated by the board's governance domain flag) and revokes that particular token instance. A fresh token must be issued for the next move.

This is the K1 / BRC-108 combination: the card cell is LINEAR (cannot be duplicated); the capability token is LINEAR (cannot be spent twice). Both constraints are enforced by the cell engine's 2-PDA bytecode gate and by the UTXO's unspent-status check at the Verifier Sidecar. No additional application-level guard is required.

### The move operation

When a hat initiates a card move, the adapter constructs a SIR program of category `power`, lowers it to OIR, emits bytecode, and submits it to the cell engine alongside the signed-bundle carrying the capability token proof.

```ts
import { buildSIRPower } from '@semantos/sir';
import { lowerSIR }      from '@semantos/sir/lower';
import { emit }          from '@semantos/ir/emit';
import { SignedBundle }  from '@semantos/mesh';

interface MoveIntent {
  cardCellId: string;
  from: ColumnId;
  to: ColumnId;
  actingHat: { certId: string; capabilityProof: BRC108Proof };
}

async function moveCard(intent: MoveIntent): Promise<Uint8Array> {
  // 1. Validate the transition is permitted.
  assertTransitionPermitted(intent.from, intent.to);

  // 2. Build the SIR program for a power act over the card.
  const sir = buildSIRPower({
    subject:   { certId: intent.actingHat.certId },
    action:    'kanban.card.move',
    taxonomy:  {
      what: 'kanban.card',
      how:  `transition.${intent.from}-to-${intent.to}`,
      why:  'workflow-progression',
    },
    governance: {
      trustClass:         'interpretive',
      proofRequirement:   'attestation',
      executionAuthority: 'hat_scoped',
      linearity:          'LINEAR',
    },
    constraint: {
      kind: 'composite', op: 'and', children: [
        { kind: 'capability', required: CAP_KANBAN_MOVE, name: 'cap.kanban.move' },
        { kind: 'domain',     flag: BOARD_DOMAIN_FLAG },
      ],
    },
  });

  // 3. Lower SIR → OIR → bytes.
  const oir   = lowerSIR(sir);          // trust-tier enforcement at this boundary
  const bytes = emit(oir);

  // 4. Create the successor card cell (prevStateHash = hash of current cell).
  const successor = createSuccessorCard(intent.cardCellId, { column: intent.to });

  // 5. Wrap in a SignedBundle, attach capability proof, submit.
  const bundle: SignedBundle<KanbanMovePayload> = {
    payload:         { program: bytes, successorCell: successor },
    capabilityProof: intent.actingHat.capabilityProof,
    // BRC-100 fields populated by the mesh transport layer.
  };

  return submitBundle(bundle);
}
```

The successor card cell carries `prevStateHash` set to the SHA-256 of the consumed (predecessor) card cell. This is the hash chain step. The predecessor cell is not deleted — cells are immutable by K7 — but the card's canonical current state is the successor. The column state machine is the sequence of successor cells chained by `prevStateHash`.

The Verifier Sidecar checks, at the adapter boundary, that the BRC-100 signature on the signed bundle is valid, that the BRC-52 cert of the acting hat is authentic, that the cert's identity binding matches the signing key, and that the capability token UTXO is currently unspent (verified via SPV). All four checks must pass before the cell engine sees the program bytes. The checks are not re-implemented in the adapter; they are substrate guarantees that the adapter inherits.

---

## Comments as patches

### The patch model

A comment on a kanban card is a patch: a declaration that adds new information to the card's record without changing the card's position in the state machine. The jural category of a comment is declaration — it asserts a fact (the text of the comment, the identity of the commenter, the timestamp) — and its linearity class is RELEVANT: a comment, once made, cannot be destroyed. RELEVANT cells are used at least once and persist.

This models the real-world expectation: a comment in a work-tracking context is a permanent part of the record. Deleting a comment is a separate act (a prohibition exercise that revokes the comment's visibility), not an erasure of its existence. The RELEVANT cell carries the comment content; a subsequent prohibition-category cell records the deletion decision if one occurs; both cells remain in the evidence chain.

```ts
interface KanbanCommentPayload {
  cardCellId:   string;   // the cell this comment is attached to
  text:         string;   // max 600 bytes UTF-8
  authorHatId:  string;   // cert_id of the commenting hat
  at:           string;   // ISO-8601 timestamp
}
```

The comment cell header:

| Header field    | Value for KanbanComment                              |
|-----------------|------------------------------------------------------|
| `typeHash`      | SHA-256 of `"kanban.comment.v1"` type string         |
| `linearity`     | `2` — RELEVANT (used at least once, persists)        |
| `parentHash`    | hash of the card cell being commented on             |
| `prevStateHash` | hash of the prior comment on this card (or zero)     |

The `parentHash` field links the comment cell to the card cell it annotates. This is not a foreign key in the relational sense; it is a cryptographic reference. Any reader who holds the card cell and the comment cell can verify the link by recomputing the card cell's hash and comparing it to the comment's `parentHash`. No central index is required.

A series of comments on a card forms a secondary hash chain rooted at the card cell, with each comment's `prevStateHash` pointing to the prior comment. This chain is independently verifiable and cannot be reordered without breaking the hash links.

### Posting a comment

```ts
import { packCell, Linearity, PipelinePhase } from '@semantos/cell-ops';

function postComment(
  cardCellId:    string,
  priorCommentHash: Uint8Array | null,
  payload:       KanbanCommentPayload,
  authorCertId:  string,
): Uint8Array {
  const header: CellHeader = {
    typeHash:      hashTypeString('kanban.comment.v1'),
    linearity:     Linearity.RELEVANT,           // persists; at least once
    pipelinePhase: PipelinePhase.RELEVANT,
    ownerCertId:   authorCertId,
    version:       1,
    timestamp:     Date.now(),
    prevStateHash: priorCommentHash ?? new Uint8Array(32),
    parentHash:    hexToBytes(cardCellId),       // link to the card
  };

  return packCell(header, encodeCommentPayload(payload));
}
```

No capability token is consumed for a comment in the default board configuration. The adapter's governance domain policy may require one — for example, a compliance-regulated board where external commentary must be credentialed — but the default is that any hat with board-member status may comment. Board-member status is verified by the Verifier Sidecar against the BRC-52 cert's domain flag, not by the adapter itself.

The SIR program for a comment is category declaration, linearity RELEVANT, trust class interpretive (the assertion is made under the commenter's hat identity without formal proof requirement). The lower pass emits an identity check and a domain flag check; the cell engine verifies both and seals the comment cell into the VFS.

---

## Evidence chain

### What the chain is

The evidence chain for a kanban board is the complete set of hash-linked cells that record the board's history:

1. The original card cells, created when cards are first added to the board.
2. The successor card cells, created on each column transition, each carrying `prevStateHash` pointing to the prior card state.
3. The comment cells, carrying `parentHash` linking them to the card cell they annotate and `prevStateHash` linking them to the prior comment in sequence.
4. The capability token spending records, anchored on-chain by the BSV transactions that consumed the BRC-108 UTXOs on each approved move.

These four layers are independently verifiable and mutually linked. A verifier who holds the board's domain flag can:

- Enumerate all cells in the VFS whose domain flag matches the board's governance domain.
- Follow the `prevStateHash` chains to reconstruct the full history of each card.
- Verify the `parentHash` links between comment cells and card cells.
- Present the SPV proofs from the capability token spending transactions to confirm that each recorded transition was authorised at the time it occurred.

The result is an audit trail that requires no separate audit log, no trust in an application-layer logging system, and no cooperation from the database operator. The trail exists in the substrate by construction.

### Dispatch envelope pattern

For boards that cross organisational boundaries — where a card transitions between a client organisation's "review" column and a service provider's "done" column — the dispatch envelope model applies. A dispatch envelope is a single semantic object referenced by multiple organisations, on which each participant attaches per-hat RELEVANT or AFFINE patches. The card cell is the dispatch envelope; the client organisation's acceptance decision is a RELEVANT patch (a declaration that the client considers the work done); the service provider's completion assertion is a separate RELEVANT patch. Neither organisation can forge the other's patch, because each patch is signed under the signing hat's BRC-52 cert.

This is the property management leaky-tap pattern applied to a workflow domain: two organisations, one shared object, no point-to-point integration, full cryptographic accountability. Chapter 25 covers the dispatch envelope in depth for the property management lexicon; the kanban application is a direct structural parallel.

### Verification from the shell

Once the adapter is installed and a board has accumulated history, the shell can verify the evidence chain:

```bash
semantos verify board --domain 0x00050001 --from <card-cell-id>
```

The verifier follows the `prevStateHash` chain from the specified root, checks each cell's BRC-100 signature, confirms each capability token's SPV proof against the chain, and outputs a structured report:

```
Board evidence chain: VALID
  Cells traced:        47
  Transitions verified: 12
  Comments verified:   35
  Capability proofs:   12 / 12 SPV-valid
  Chain intact:        yes (no hash breaks)
  Oldest cell:         2026-04-01T09:14:22Z
  Newest cell:         2026-04-26T14:02:11Z
```

The cell engine's K6 invariant (hash-chain integrity, model-checked in TLA+) guarantees that the chain traced by the verifier is the same chain that the cell engine enforced at write time. A chain that the verifier reports as intact is a chain that was intact when each cell was written; there is no gap between the enforcement point and the verification point.

---

## Install and run

### Extension manifest

The kanban adapter is an extension in the four-tier model. It sits at the top tier — installable, shareable, concurrent with other extensions — and composes substrate primitives: the cell type definitions, the SIR programs for card movement, the capability token classes, the VFS octave paths for the board's cells.

The extension manifest sketch:

```ts
// extensions/kanban/manifest.ts
export const kanbanManifest = {
  id:          'kanban',
  version:     '0.1.0',
  types: [
    { name: 'kanban.card.v1',    linearity: 'LINEAR',   category: 'power' },
    { name: 'kanban.comment.v1', linearity: 'RELEVANT', category: 'declaration' },
  ],
  flows: [
    { id: 'card.move',    sir: 'power',       capability: 'cap.kanban.move' },
    { id: 'card.approve', sir: 'power',       capability: 'cap.kanban.approve' },
    { id: 'card.comment', sir: 'declaration', capability: null },
  ],
  hat_affinity: ['project-manager', 'developer', 'reviewer'],
  capability_scopes: {
    'cap.kanban.move':    { allowedTransitions: 'all-except-approve' },
    'cap.kanban.approve': { allowedTransitions: 'review-to-done' },
  },
  tier_3_weights: {
    Manage:   ['kanban.card.v1'],
    Transact: ['kanban.card.v1'],
  },
  views: [
    { id: 'board',    template: 'kanban-board' },
    { id: 'timeline', template: 'card-evidence-chain' },
  ],
  dependencies: [],
  publication_channels: [
    'kanban.card.moved',
    'kanban.card.commented',
    'kanban.card.approved',
  ],
} as const;
```

The manifest declares types (which register in the type registry as shared primitives), flows (which link SIR program templates to capability scopes), hat affinities (which suggest default hat assignments), capability scopes (which the Verifier Sidecar enforces at the adapter boundary), tier-3 weights (which re-weight the Helm popover contents when this extension is active), views (which Helm renders), dependencies (none for this adapter), and publication channels (which the mesh uses for multicast subscription).

### The install command

The deploy command for the extension:

```bash
semantos install extension kanban
```

**Current state:** this command is defined in the extension loader but its full enforcement path — in particular, the capability token minting step that allocates `cap.kanban.move` and `cap.kanban.approve` UTXOs to the board's governance domain — requires the Verifier Sidecar's D-V1 deliverable to be fully deployed and the capability domain's BRC-108 minting flow to be active across all adapter boundaries. Both are scheduled under the Unification Matrix. The install command in the current build will register the extension manifest, create the VFS octave paths for the board, and enable the SIR programs; it will not yet mint the BRC-108 UTXOs or enforce them at the cell engine boundary.

**Future state under the Matrix:** when D-V1 (Verifier Sidecar integration) and the capability domain deliverables complete, `semantos install extension kanban` will additionally:

1. Allocate a governance domain flag from the client sovereignty namespace for the board.
2. Mint `cap.kanban.move` BRC-108 UTXOs for each listed board-member hat.
3. Mint `cap.kanban.approve` BRC-108 UTXOs for each listed reviewer hat.
4. Register the board's domain flag with the cell engine so that `OP_CHECKDOMAINFLAG` enforces domain isolation (K3) on all card cells.

Until those deliverables complete, the adapter operates in a mode where the SIR and OIR programs are generated and the cell hash chain is maintained, but the BRC-108 UTXO enforcement is advisory rather than structural. This is an honest representation of the current enforcement boundary: the substrate runs through boot step 7 (`kernel_set_enforcement(1)`); the BRC-108 capability token integration is a step-8 through step-11 concern gated by the Unification Matrix.

### Creating a board and a first card

Once the extension is installed:

```bash
# Initialise a board in the current governance domain.
semantos kanban board create --name "Sprint 42" --domain 0x00050001

# Create a card.
semantos kanban card create \
  --board sprint-42 \
  --title "Implement adapter manifest validation" \
  --priority normal \
  --assign alice@developer

# List the board.
semantos kanban board view sprint-42
```

Output:

```
Board: Sprint 42  (domain: 0x00050001)

BACKLOG (1)
  [abc123] Implement adapter manifest validation   [alice@developer]

TODO (0)
IN-PROGRESS (0)
REVIEW (0)
DONE (0)
```

Moving the card:

```bash
semantos kanban card move abc123 --to todo --hat alice@developer
semantos kanban card move abc123 --to in-progress --hat alice@developer
```

Each `move` command: builds the SIR power program, lowers to OIR, emits bytecode, creates a successor card cell with `prevStateHash` pointing to the current cell, wraps in a SignedBundle signed under the acting hat's BRC-52 cert, submits to the cell engine, and writes the successor cell to the VFS. The predecessor cell is sealed in the VFS at its octave path; the successor cell becomes the canonical current state.

### Verifying the audit trail

```bash
semantos kanban card history abc123
```

Output:

```
Card: abc123 — Implement adapter manifest validation
  2026-04-26T09:01:00Z  CREATED      alice@developer      (cell: abc123)
  2026-04-26T09:14:00Z  backlog→todo alice@developer      (cell: def456, prev: abc123)
  2026-04-26T10:33:00Z  todo→in-prog alice@developer      (cell: ghi789, prev: def456)
  Hash chain: VALID (3 cells, 0 breaks)
```

The `VALID` status is the cell engine's K6 guarantee applied at read time. The adapter does not maintain a separate history table; it follows the `prevStateHash` chain from the most recent cell back to the origin and reports what it finds. Tampering with any intermediate cell in the chain would break the hash link and the verifier would report `INVALID` at the broken cell.

---

## What the adapter sketch demonstrates

This chapter has assembled a complete kanban adapter from substrate primitives. The structural properties that the sketch delivers:

- **K1 enforcement** — kanban cards are LINEAR cells. A card cannot be in two columns simultaneously because the cell engine's K1 invariant (proved in Lean 4) structurally refuses duplication. No application-level guard is needed.
- **Capability token consumption** — each authorised column transition spends a `cap.kanban.move` or `cap.kanban.approve` BRC-108 UTXO. Spending is atomic and verifiable via SPV. The token cannot be spent twice.
- **Hash chain as evidence** — the `prevStateHash` chain across successor card cells is the audit trail. It is constructed by the cell packing step, verified by the cell engine at write time (K7, K6), and readable by any verifier with access to the VFS and the board's domain flag.
- **Comments as RELEVANT declarations** — comment cells are RELEVANT, persisting by structural guarantee. The `parentHash` field links each comment to its card cell without a relational join. The comment chain is independently verifiable.
- **Extension manifest** — the adapter declares its types, flows, capability scopes, hat affinities, and Helm popover weights in a single manifest. The four-tier model (extension → types → contexts → Helm) means the kanban types become shared primitives reusable by other extensions once installed, while the board workflow remains the extension's own concern.
- **Deploy path** — `semantos install extension kanban` is the install command. The BRC-108 UTXO minting and K3 domain flag enforcement are explicitly flagged as future state under the Unification Matrix, contingent on D-V1 and the capability domain deliverables.

The same adapter shape — cells per entity, column or phase as a state machine over the cell's payload, transitions as power jural categories consuming capability tokens, comments as RELEVANT declaration patches, history as the prevStateHash chain — applies to CDM lifecycle processing (Chapter 24), property maintenance dispatch (Chapter 25), and SCADA alarm management (Chapter 26). The substrate makes every vertical structurally identical at this level. The domain lexicon changes; the adapter shape does not.

Chapter 29 covers cross-vertical dispatch: how a kanban card that represents a maintenance job can reference a property management dispatch envelope, how the mesh carries the signed bundles across organisational boundaries, and when to anchor a cell on-chain versus keeping it within the local VFS. That chapter extends the adapter pattern built here into the federated case.
