---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/31-extension-grammar.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.649273+00:00
---

> **⚠ Reframed by Ch.37 (Wave Canonical-Cartridge, 2026-05-18).**
> "Extension" is no longer a distinct concept — it is a **cartridge**
> (role `experience` or `grammar-lexicon`); the grammar/lexicon
> described here are *sections of the one `cartridge.json`*, and the
> canon lexicon registry is *rendered* from the cartridge's source, not
> a parallel truth. The grammar **mechanics** below remain correct;
> read "extension" as "cartridge". See Ch.37 +
> `docs/design/CANONICAL-CARTRIDGE-MODEL.md`.

# Extension Grammar

**Part IX — Verticals and the Grammar Layer**

The previous eight parts of this book built the substrate: identity, capability, linearity, the cell engine, the compilation pipeline, lexicons, and the intent pipeline. This part uses that substrate to show how domain-specific meaning gets into the system — how the abstract machinery of `SIRNode` categories, governance contexts, and taxonomy coordinates acquires the vocabulary of property maintenance, financial derivatives, industrial automation, or any other domain a connector author wants to attach.

The mechanism is the **extension grammar**. An extension grammar is a declarative description of how an external system's data shapes, field names, and API conventions map onto Semantos semantic types, linearity constraints, taxonomy coordinates, and governance obligations. It is the seam between the world as it is — REST APIs, database schemas, message queues — and the substrate as it reasons about meaning.

This chapter describes the two grammar formats, the governance model that controls how grammars evolve, and the anatomy of a complete grammar. Chapter 32 describes how utterances are reduced through a grammar into the Intent type. Chapter 33 describes how grammars can be generated automatically from API probing and Pask-backed inference.

---

## Why a grammar layer

The substrate knows how to express obligation, transfer, declaration, and the other jural categories. The substrate does not know what a maintenance job is, or what a property lease looks like, or how valve commands relate to interlocks. That vocabulary is vertical-specific and changes faster than the substrate.

The extension grammar separates these concerns. The substrate provides the formal machinery; the grammar provides the domain vocabulary. A grammar author does not need to modify the cell engine, the SIR type system, or the lexicons. They write a JSON document that says: this entity type in my domain corresponds to this taxonomy path; this field maps to this payload schema field; this API endpoint produces these semantic objects at this linearity class.

The grammar is not code. It is a declarative document that several runtime components consume: the extraction pipeline uses it to classify LLM output against the correct vocabulary; the intent reducer uses it to map structured facts to SIR constraints; the grammar-config bridge uses it to configure the loom's FlowRunner; and the governance engine uses it to enforce who can propose changes to the grammar's definition.

---

## Two grammar formats

The grammar layer has two formats with different purposes and different scopes.

### ExtensionGrammarSpec — the classifier grammar

The classifier grammar is the lightweight format consumed by the LLM extraction pipeline. It lives in `extensions/extraction/src/intent-adapters/` and is a TypeScript record, not JSON.

```ts
export interface ExtensionGrammarSpec {
  extensionId: string;
  domainFlag: number;
  lexicon: Lexicon;
  defaultTaxonomyWhat: string;
  actions: ReadonlyArray<ActionDefinition>;
  objectTypes: ReadonlyArray<{ name: string; description: string }>;
}
```

The `lexicon` field binds the grammar to one of the registered lexicons from `@semantos/semantos-sir`. The lexicon's `categories` array is used at construction time to generate the tool-schema's `category` enum for the LLM classifier. The consequence is structural: if the LLM returns a category that is not a member of the bound lexicon, the classifier output fails validation before it ever reaches the intent reducer. The grammar cannot be silently mismatched against its lexicon.

The `actions` array is the domain vocabulary. Each action has a `category` field that must be a member of the grammar's bound lexicon, an `authoredBy` field that names which roles can propose this action (tenant, landlord, operator, tradesperson), and a `description` string that the classifier sees in its system prompt.

The trades vertical uses `JuralLexicon` with categories `declaration`, `obligation`, `power`, `condition`, `transfer`. The SCADA vertical uses `ControlSystemsLexicon` with categories `measurement`, `setpoint`, `actuation`, `interlock`, `alarm`, `acknowledgement`, `calibration`. Same pipeline, same classifier factory, same tool-use machinery — different vocabulary, different trust-tier semantics. The grammar is the only thing that changes between verticals.

An important property follows from this design: adding a new domain does not require modifying the classifier code. It requires writing a grammar spec, choosing a lexicon (or requesting a new one in `@semantos/semantos-sir`), and defining the action vocabulary. The classifier factory is generic over `ExtensionGrammarSpec`.

### ExtensionGrammar — the connector grammar

The connector grammar is the full-stack format consumed by the extension loader, the loom, and the governance engine. It is validated JSON, defined by the `ExtensionGrammar` interface in `@semantos/protocol-types` and validated at load time by `validateExtensionGrammar()`.

The connector grammar carries everything the classifier grammar does not: the source API's protocol, authentication scheme, rate limits, pagination strategy, entity endpoints, field shapes, and relationships; the semantic object types with their linearity classes and FSM phase declarations; the field-level mappings between source fields and target payload fields; the taxonomy coordinates for each entity; and optional migration rules for version upgrades.

The structural organisation follows a strict flow. The `source` block describes where the data comes from and how to authenticate. The `objectTypes` block describes what semantic objects this grammar produces, including their linearity (LINEAR, AFFINE, RELEVANT, FUNGIBLE), their phase FSM, and their payload schema. The `entityMappings` block bridges the two: for each source entity, it names the target object type and provides field-level `fieldMappings` with optional transforms (`concat`, `split`, `lookup`, `template`, `map_enum`, `compute`). The `capabilities` block declares what the host node must provide (network access, storage write, identity read). The `taxonomyExtensions` block declares new taxonomy nodes this grammar introduces.

A concrete example from the PropertyMe connector grammar:

```json
{
  "entityMappings": [
    {
      "sourceEntityId": "property",
      "targetObjectType": "property-management.property",
      "fieldMappings": [
        { "sourceField": "id", "targetField": "propertyId", "required": true },
        { "sourceField": "street_address", "targetField": "address", "required": true },
        { "sourceField": "bedrooms", "targetField": "bedrooms",
          "coerce": { "from": "number", "to": "number" }, "required": true },
        { "sourceField": "updated_at", "targetField": "updatedAt",
          "coerce": { "from": "datetime", "to": "datetime" }, "required": true }
      ],
      "taxonomy": {
        "what": "what.property.residential",
        "how": "how.technical.api.rest",
        "why": "why.integration.property-management"
      }
    }
  ]
}
```

The `taxonomy` block on each entity mapping assigns the three mandatory taxonomy axes — `what`, `how`, `why` — and the optional `where` axis. These coordinates are the same `TaxonomyCoordinates` that `SIRNode.taxonomy` carries; the grammar is declaring, at definition time, where in the taxonomy these objects live.

---

## The governance model

Extension grammars do not exist outside governance. Every grammar evolves under a three-level governance structure that flows constraints downward and escalates disputes upward.

### L0 — Platform policy

The platform governance policy (`GovernancePolicy`) is a RELEVANT-linearity object with `constitution: true`. Changes require a ballot with a quorum threshold defined in `breakingChangeBallotQuorum`. It controls:

- The minimum `metaSchemaVersion` any new grammar must target.
- The `taxonomyNamespaceReservations` — namespace prefixes reserved by the platform that grammar authors cannot claim (`governance`, `kernel`, `plexus`).
- The `marketplaceListingRequirements` — minimum author reputation score, minimum object count, and audit frequency for marketplace-listed grammars.
- The `emergencyDeprecationPolicy` — minimum notice before deprecation and whether a vote is required.

Grammar authors cannot bypass L0. The constraint engine enforces L0 at grammar load time; a grammar that violates a platform policy is rejected before activation.

### L1 — Author governance config

Each extension manifest carries a `ManifestGovernanceConfig` that controls how that grammar evolves:

```ts
interface ManifestGovernanceConfig {
  patchAcceptancePolicy: 'author_only' | 'contributor_ballot' | 'open_ballot';
  versionBumpRules: {
    major: 'author_only' | 'contributor_ballot';
    minor: 'author_only' | 'contributor_ballot';
    patch: 'author_only';
  };
  contributorHats: string[];
  deprecationTimelineMinDays: number;
  trustClass?: 'cosmetic' | 'interpretive' | 'authoritative';
  proofRequirement?: 'none' | 'attestation' | 'formal';
  executionAuthority?: 'local_facet' | 'hat_scoped' | 'delegated';
}
```

The `trustClass` and `proofRequirement` fields carry forward to every `GovernanceContext` produced by the intent reducer for objects under this grammar. An `authoritative` grammar requires `proofRequirement: 'formal'`; the constraint engine rejects any manifest that declares `trustClass: 'authoritative'` with a weaker proof requirement. This is the structural enforcement of the trust-tier invariant: authoritative economic claims cannot be authored without formal proof, and the grammar declares upfront whether it makes such claims.

The `executionAuthority` determines which hats can trigger execution on objects under this grammar. `local_facet` is the conservative default: only the owning facet. `hat_scoped` allows any facet holding the right hat cert. `delegated` is reserved for federation and is currently rejected by the constraint engine.

### L2 — Consumer binding

Each node that activates an extension creates a `GovernedConsumerBinding` for it. This is an AFFINE object, node-scoped, that pins the grammar version range, stores encrypted API credentials, and optionally adds local field overrides and taxonomy overrides without modifying the grammar itself.

Credentials are never stored in plaintext. The `credentialsEncrypted` field holds a base64-encoded ciphertext plus a reference to the node's encryption key. The `credentialFieldNames` field lists which fields are encrypted so the UI can display labels without decrypting. The plaintext is available only inside the extraction pipeline after the vault has decrypted it under the node's key.

The governance flow for disputes goes upward: a consumer dispute escalates from L2 to L1 (the grammar author); if unresolved, from L1 to L0 (platform ballot). The escalation conditions are: unresolved after a time window, critical security issue, or manifest deprecation. `dispute-escalator.ts` implements the escalation logic; no separate governance engine is required — the substrate's existing Ballot and Dispute object types handle the flows.

---

## Grammar linearity and the AFFINE → RELEVANT graduation path

Grammars begin as AFFINE drafts. A newly authored grammar has `manifestLinearity: 'AFFINE'`: it can be edited freely, the author can propose patches without governance overhead, and the grammar is not published to the marketplace.

Graduation to RELEVANT requires passing the constraint engine's L0 and L1 checks, a non-empty `validationResult.valid` from `validateExtensionGrammar`, and a governance ballot (for author-only policies) or contributor review (for ballot-based policies). Once a grammar is RELEVANT, patches require the `patchAcceptancePolicy` process to run; the grammar becomes an immutable version and the next change creates a semver increment.

The migration rules in `ExtensionGrammar.migrations` handle the version-to-version transition. Field renames, type changes, phase renames, and object type renames are declarative: the migration engine applies them at binding activation time, not at grammar authorship time, which means existing consumer bindings continue to function until they are explicitly upgraded.

---

## Authoring a grammar — the minimum viable spec

A grammar for a new domain needs four things: a lexicon, a domain flag, an action vocabulary, and at least one object type.

**Step 1: choose a lexicon.** The registered lexicons are: `jural`, `control-systems`, `circuit-commands`, `cdm`, `bills-of-lading`, `project-management`, `property-management`, `risk-assessment`, `calendar`, `trades`, `brap`. If none fits, a new lexicon requires a TypeScript `Lexicon<Cat>` definition in `@semantos/semantos-sir/src/lexicons.ts` and a corresponding Lean injectivity proof in `proofs/lean/Semantos/Lexicons/<Name>.lean`. The injectivity proof is not optional — it is the formal guarantee that the lexicon's `header` function is injective on its category set.

**Step 2: assign a domain flag.** The domain flag is the numeric identifier used by `OP_CHECKDOMAINFLAG` at the kernel layer. It must be unique within the deployment's domain namespace. The flag binds the grammar's SIR nodes to a governance domain at execution time.

**Step 3: define actions.** Each action has a name (the verb that appears on `Intent.action`), a category (must be in the chosen lexicon), an `authoredBy` list (the roles that can propose this action), and a description (the string the LLM classifier sees). Keep the action list narrow — add verbs only when real conversation corpora demand them. The classifier's category enum is generated from the lexicon, not the action list; an action with an invalid category will fail validation at grammar load time, not silently at runtime.

**Step 4: declare object types.** Each object type has a `typePath` (the taxonomy `what` coordinate this type occupies), a linearity class, a phase FSM, and a payload schema. The typePath must be within the grammar's declared `taxonomyNamespace`. The phase FSM names the legal states (phases) and the initial phase; transitions are declared in `TransitionDeclaration` and can carry guards of type `capability`, `value`, `time`, `relationship`, or `contextual`.

The grammar validator will reject a grammar that declares a phase transition to a phase not in the FSM, a field mapping to a source field not declared in `source.entities`, or a taxonomy path that violates the namespace reservation policy. Validation is exhaustive — there is no partial grammar; either it validates in full or it does not activate.

---

## What the grammar connects

A finished, validated grammar connects three layers of the system simultaneously:

1. **The extraction layer**: the classifier grammar (`ExtensionGrammarSpec`) constrains the LLM's output vocabulary and routes tagged facts to the correct lexicon and action set.

2. **The reducer layer**: the intent reducer uses the grammar spec to perform the trivium/quadrivium decomposition described in the next chapter — the grammar's `objectTypes` constrain `taxonomy.what`, the `actions` constrain the rhetoric pass, and the `domainFlag` feeds the astronomy pass's governance context.

3. **The loom layer**: the connector grammar (`ExtensionGrammar`) feeds `grammarToExtensionConfig()` which produces an `ExtensionConfig` consumed by the FlowRunner. The loom does not interpret source field names; it interprets semantic object types, linearity classes, and capability requirements. The grammar is what makes those interpretations domain-specific without modifying the loom.

The grammar is the vocabulary card of the system. Every domain that connects to Semantos produces one. The substrate speaks SIR; the grammar is the translation layer between a domain's native concepts and the substrate's semantic primitives.
