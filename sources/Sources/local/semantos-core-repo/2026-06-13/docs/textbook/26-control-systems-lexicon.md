---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/docs/textbook/26-control-systems-lexicon.md
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.644211+00:00
---

# Chapter 26 — Control Systems / SCADA: Telemetry, Interlocks, Alarms

**Part VII — Domain Lexicons**

---

## Economic problem

Industrial control — SCADA systems, distributed control systems, safety-instrumented systems — operates under a constraint that most software domains do not share: the cost of a wrong action is not a bad user experience, it is equipment failure, environmental release, or human injury. An interlock does not recommend against opening a valve; it prevents the opening. An alarm does not suggest that something might be wrong; it asserts that a threshold has crossed and requires acknowledgement before the process continues.

The economic problem is that this vocabulary has no machine-readable semantic encoding that travels with the data. A pressure reading transmitted over Modbus is a 16-bit integer. The receiving system must know, from out-of-band configuration, that this integer is a measurement in bar, that its alarm threshold is 150, and that crossing that threshold activates an interlock prohibiting valve V-1001 from opening. When that configuration is spread across a PLC ladder diagram, a SCADA historian database, and an operator manual — each maintained by a different team — the gap between the domain's intent and the system's enforcement is a change-control problem that never fully closes.

The Semantos substrate does not replace the PLC. It provides a semantic layer — the Semantic IR (SIR) — in which the control vocabulary can be expressed with jural precision. A measurement is a declaration. An interlock is a prohibition. An alarm is an obligation that must be consumed by acknowledgement. A setpoint change is an exercise of power over a process parameter. Shift handover is a transfer of capability tokens. Each of these maps to one of the seven jural categories, and each jural category has a defined linearity, a defined lowering to the Opcode IR (OIR), and a defined enforcement mechanism in the cell engine.

This chapter walks through the Lean lexicon that encodes these mappings, explains how each control-domain concept aligns with a jural category, and closes with a worked program: an interlock policy expressed as a prohibition SIR program with logical negation, demonstrating how SCADA "must-not" semantics reach the cell engine as bytecode.

---

## Hohfeldian decomposition

Before the code, the analysis. The seven Lean categories in `ControlSystemsCategory` are not arbitrary domain labels — they are jural categories in the Hohfeldian sense, adapted for computational governance. This section maps each control-domain concept to its jural character.

### Measurement as declaration

A measurement is an assertion: the sensor at location PT-1001 observed pressure 142 bar at timestamp T. The sensor does not request permission to make this assertion; it makes it. The assertion does not obligate anyone immediately; it places a fact in evidence. In jural terms, this is a declaration — an assertion of fact or state.

The linearity of a telemetry measurement is AFFINE. The reading can be superseded by the next reading without leaving an obligation unfulfilled. Once it is superseded, the old reading is not destroyed — it remains in the evidence chain — but its role as "current value" has ended. A historian that stores measurements is accumulating a chain of declarations, each AFFINE in its currency, each RELEVANT in its evidentiary status.

This dual nature is important for compliance and incident investigation. When a safety incident is reviewed, the question is not "what is the current pressure" but "what was the pressure reading at 14:23:07." The declaration's evidentiary status — RELEVANT, cannot be destroyed — is what makes the historian legally significant, not just operationally useful.

### Setpoint as power

A setpoint is an operator's target state for an actuator. Setting a setpoint is an exercise of power — authority to change the operational state of the system. The power to change a setpoint is scoped to the operator's hat and role; not everyone with SCADA terminal access can change a setpoint on a running reactor. The linearity is LINEAR: the command is issued once and consumed by the equipment's acceptance.

### Actuation as power

An actuation — valve.open, motor.start, pump.stop — is also power, at the equipment level rather than the parameter level. Actuations are LINEAR: "open valve V-1001" is consumed by the valve's transition from closed to open.

The distinction between setpoint and actuation is operationally significant. Most SCADA safety frameworks treat these as separate authority classes: a process engineer may be able to change setpoints on a live process while actuation of a safety valve requires a higher-privilege hat.

### Interlock as prohibition

The interlock is the control domain's most important safety mechanism and the one that maps most precisely to a jural category. An interlock states: under condition C, action A must not be taken. This is not a warning, not a recommendation, not a log entry — it is a standing constraint that the system enforces before any command is accepted.

The jural category is prohibition: a constraint that an action must not occur. The linearity is RELEVANT: the interlock does not get consumed by application. It persists until it is deliberately removed or the condition it monitors changes.

The Hohfeldian analysis: a prohibition is the correlate of a no-right. The operator at the SCADA terminal has no right to command valve.open while pressure exceeds 150 bar. The prohibition is not the operator's duty; it is the operator's incapacity. The system does not trust the operator to remember not to open the valve — it removes the right to do so.

This is the mapping that the OIR lowering makes concrete. A prohibition SIR node lowers to a constraint predicate followed by `logical_not`: the dangerous condition must evaluate to false before the command is permitted to proceed. The cell engine enforces this at the opcode level. The interlock is not advisory code; it is bytecode that the 2-PDA must evaluate before the actuation opcode can execute.

### Alarm as obligation

An alarm is a threshold-crossed notification that requires operator attention. The jural category is obligation: a duty that must be fulfilled. An alarm is LINEAR — it exists once and must be consumed by acknowledgement (or by escalation, if acknowledgement is not received within the required window).

The Hohfeldian analysis: the alarm creates an obligation on the operator to acknowledge. The correlative of this obligation is the system's claim-right: the system has a right to receive acknowledgement. If acknowledgement is not received, the obligation defaults — the alarm escalates, an automatic safe-state transition may be triggered, or a compliance record is generated indicating a missed alarm response.

This linearity has direct safety implications. An alarm that is not LINEAR — one that could be sent, ignored, and effectively discarded without the system being aware — is a safety vulnerability. The Semantos model treats alarm acknowledgement as the consumption of a LINEAR obligation, which means the system always knows whether the alarm has been consumed and can enforce consequences if it has not.

### Acknowledgement as power

Acknowledging an alarm is an exercise of power: it consumes the alarm obligation and records that the operator accepted responsibility for the state being signalled. The linearity is LINEAR — the acknowledgement happens once and consumes the alarm; an operator cannot acknowledge the same alarm twice.

The jural structure makes the audit trail legible. The alarm is created as a LINEAR obligation; the acknowledgement is a LINEAR power exercise that consumes it. The evidence chain records both events with the operator's hat identity and the timestamp of the acknowledgement.

### Calibration as power

A calibration — updating a sensor's reference point, zeroing a flow meter, adjusting a transmitter's span — is an exercise of power over the measurement infrastructure. Each calibration event is LINEAR; its effect is RELEVANT: the new reference persists until the next calibration replaces it.

Calibration sits at the boundary between operational and safety-critical actions. An incorrectly applied calibration that makes a pressure transmitter read 20% low means that an interlock set at 150 bar actually triggers at 180 bar. The jural model captures this: a calibration changes the taxonomy coordinates of all subsequent measurements from that sensor, which may in turn change the conditions under which interlocks activate.

---

## The Lean lexicon

The Lean file at `proofs/lean/Semantos/Lexicons/ControlSystems.lean` is the second concrete instance of the `Semantos.Substrate.Lexicon` typeclass. The first was the jural lexicon; the control-systems lexicon demonstrates that the substrate pattern generalises beyond legal vocabulary to any domain with a structured category set.

```lean
-- Semantos Plane — Control Systems Lexicon
--
-- Semantic-intent vocabulary for SCADA, process automation, and
-- safety-instrumented systems. The seven categories correspond to the
-- basic lifecycle of industrial control:
--
--   measurement      — an observed value from a sensor
--   setpoint         — an operator's target state for an actuator
--   actuation        — a command to change an actuator's state
--   interlock        — a structural safety constraint on transitions
--   alarm            — a threshold-crossed notification
--   acknowledgement  — operator accepts an alarm
--   calibration      — update of a sensor reference / zero point
--
-- Second concrete instance of `Semantos.Substrate.Lexicon`, demonstrating
-- that the substrate + lexicon pattern generalises beyond legal/jural
-- vocabulary. Same proof template as Jural: header function + 7×7
-- injectivity case analysis + `Lexicon` instance. All substrate theorems
-- (M1-M4, D1-D3, renderCard_*) apply at `Patch ControlSystemsCategory`
-- automatically.

import Semantos.Substrate.Lexicon

namespace Semantos.Lexicons

open Semantos.Substrate

inductive ControlSystemsCategory where
  | measurement
  | setpoint
  | actuation
  | interlock
  | alarm
  | acknowledgement
  | calibration
  deriving Repr, DecidableEq, BEq
```

The `inductive ControlSystemsCategory` declaration defines a closed sum type over the seven control-domain categories. The `deriving` clause gives the type decidable equality and boolean equality for free — a requirement of the `Lexicon` typeclass, which needs to be able to compare category values at the type level.

```lean
def controlSystemsHeader : ControlSystemsCategory → String
  | .measurement     => "MEASUREMENT"
  | .setpoint        => "SETPOINT"
  | .actuation       => "ACTUATION"
  | .interlock       => "INTERLOCK"
  | .alarm           => "ALARM"
  | .acknowledgement => "ACK"
  | .calibration     => "CALIBRATION"
```

The header function maps each category to its canonical string label. This string appears in the rendered cell card — the human-readable summary of a cell's semantic type. The label "ACK" for acknowledgement follows the operational convention in SCADA systems where alarm acknowledgement is abbreviated as ACK in display systems.

The header function must be injective: no two distinct categories may map to the same string. This is enforced by the theorem:

```lean
theorem controlSystemsHeader_injective : ∀ c₁ c₂ : ControlSystemsCategory,
    controlSystemsHeader c₁ = controlSystemsHeader c₂ → c₁ = c₂ := by
  intro c₁ c₂ h
  cases c₁ <;> cases c₂ <;> simp_all [controlSystemsHeader]
```

The proof uses case exhaustion: for each of the 7×7 = 49 pairs of constructor combinations, `simp_all` reduces the equation to either a trivial equality (when c₁ = c₂) or a contradiction (when c₁ ≠ c₂ but their headers are equal — which is impossible by inspection of the distinct strings). The proof is structurally identical to the jural lexicon's injectivity proof, confirming that the proof template is reusable across domain lexicons.

```lean
instance : Lexicon ControlSystemsCategory where
  header          := controlSystemsHeader
  headerInjective := controlSystemsHeader_injective

end Semantos.Lexicons
```

The `Lexicon` instance registers the control-systems category type with the substrate. Once this instance exists, all substrate theorems that are stated for `∀ (α : Type) [Lexicon α]` apply automatically to `ControlSystemsCategory`. The substrate theorems (M1-M4, D1-D3, renderCard_*) cover cell monotonicity, declaration ordering, and card rendering — they hold for the control-systems domain without any domain-specific proofs.

### What the lexicon enables

The 56-line Lean file achieves the following:

1. It gives the substrate a closed, machine-checked vocabulary for the control domain.
2. It guarantees that the seven category labels are distinct (injectivity theorem), so that category-typed cells cannot be misclassified.
3. It makes all substrate theorems available at `Patch ControlSystemsCategory`, so that control-domain cells participate in the same monotonicity and ordering guarantees as jural cells.
4. It provides the type-level anchor for SIR programs that express control-domain intent: a SIR node with `taxonomy.what = "sensor.pressure.gauge"` and a control-systems category maps to a specific header string, which the cell engine can verify against the cell's type hash.

The lexicon is not a runtime library. It is a Lean module whose compilation is proof of semantic consistency. If the injectivity theorem fails — because someone added a category with a duplicate header string — the Lean build fails before any runtime artefact is produced.

---

## 30-min interlock demo

This section works through a complete interlock policy: a standing prohibition on opening valve V-1001 when upstream pressure exceeds 150 bar. The program starts from the domain requirement, moves through the jural decomposition, expresses the SIR program, shows the OIR lowering, and describes the bytes the cell engine evaluates.

### Domain requirement

```
INTERLOCK IL-001
  Tag:       PT-1001 (upstream pressure transmitter)
  Condition: PT-1001.PV > 150.0 bar
  Action:    Prohibit ACTUATION of V-1001 (valve.open)
  Class:     Safety interlock, SIL-2
  Linearity: RELEVANT (standing constraint, persists until
             explicitly removed or condition clears)
```

This is the engineering requirement. The economic interpretation: any operator action to open V-1001 while PT-1001 reads above 150 bar must be blocked before execution. The interlock is not a post-execution check — it is a pre-execution gate.

### Jural decomposition

The interlock IL-001 is a prohibition. The prohibition is:

- **Category:** prohibition
- **Action prohibited:** actuation of V-1001 (valve.open)
- **Condition:** PT-1001.PV > 150.0 bar — this is the interlock condition, not the negation
- **Negation:** the prohibition is satisfied (the action is blocked) when the condition evaluates to true
- **Linearity:** RELEVANT — the prohibition persists; it is not consumed by blocking one command
- **Governance context:** trustClass `authoritative`, proofRequirement `formal`, executionAuthority `hat_scoped`

The SIR lowering rule for prohibition (from §5.1 of the SIR architecture document) is:

```
prohibition(action, constraint) →
  OIR: $0 = evaluate(constraint)
       $1 = logical_not($0)   -- prohibition: dangerous condition must NOT hold
       VERIFY($1)
```

The `logical_not` is the key semantic operator: the prohibition does not check that the condition is false directly; it checks that the dangerous condition holds (the comparison), then negates — because the prohibition is about what must not be allowed, and the cell engine's VERIFY opcode succeeds only when the result is true. So "valve.open is prohibited when pressure > 150" becomes "VERIFY that NOT (pressure > 150)" — i.e., VERIFY that pressure is at or below 150.

### SIR program

```json
{
  "nodes": [
    {
      "id": "$s0",
      "category": "prohibition",
      "taxonomy": {
        "what": "sensor.pressure.gauge",
        "how": "interlock.pre-actuation",
        "why": "safety-interlock"
      },
      "identity": {
        "subject": { "type": "role", "name": "interlock-engine" }
      },
      "governance": {
        "trustClass": "authoritative",
        "proofRequirement": "formal",
        "executionAuthority": "hat_scoped",
        "linearity": "RELEVANT",
        "allowedEmitOps": ["comparison", "logical"]
      },
      "action": "prohibit",
      "constraint": {
        "kind": "composite",
        "op": "not",
        "children": [
          {
            "kind": "value",
            "field": "PT-1001.PV",
            "op": ">",
            "value": 150.0
          }
        ]
      },
      "target": {
        "equipmentId": "V-1001",
        "typePath": "control-systems/actuation/valve.open"
      },
      "provenance": {
        "source": "manual",
        "expressedAt": "2026-04-26T00:00:00Z",
        "trustAtExpression": "authoritative"
      }
    }
  ],
  "primaryNodeId": "$s0",
  "programGovernance": {
    "trustClass": "authoritative",
    "proofRequirement": "formal",
    "executionAuthority": "hat_scoped",
    "linearity": "RELEVANT"
  }
}
```

Several fields are worth examining.

`allowedEmitOps: ["comparison", "logical"]` — this whitelist in the governance context constrains the OIR lowering pass. The interlock policy may only emit comparison opcodes (to evaluate the pressure reading) and logical opcodes (to apply the negation). It may not emit `hostCall`, `capability`, or `transfer` opcodes. This is the structural enforcement of §4.3 of the SIR architecture: a SCADA interlock that accidentally emits a host call or a transfer is a governance violation that the lower pass rejects before any bytes are produced.

`linearity: "RELEVANT"` — the prohibition is not consumed by evaluation. The interlock is checked before every valve.open command, and it persists until the policy is explicitly removed. Contrast with the alarm obligation (LINEAR, consumed by acknowledgement): the interlock does not get consumed.

`trustClass: "authoritative"`, `proofRequirement: "formal"` — a safety interlock is an authoritative expression. The lower pass will reject this node if the proof requirement is not `formal`. In practice, this means the interlock policy cell must carry a formal attestation before the cell engine will enforce it. A cosmetic or interpretive interlock policy is a governance violation — interlock policies at SIL-2 are not advisory.

### OIR lowering

The lower pass takes the SIR node `$s0` and produces OIR bindings:

```
$0 = comparison(PT-1001.PV, >, 150.0)
       -- evaluate whether pressure exceeds the threshold

$1 = logical_not($0)
       -- negate: the prohibition holds when the dangerous condition does NOT hold
       -- equivalently: the gate passes when pressure is at or below 150

result: $1
```

The OIR is in administrative normal form (ANF): each binding is a named intermediate result, no sub-expression appears twice, and the final result is a single binding name. The cell engine's 2-PDA evaluates these bindings in order.

The `allowedEmitOps` check: the lower pass confirms that every binding emitted — `comparison` and `logical_not` — is in the `["comparison", "logical"]` whitelist. If the lower pass attempted to emit a `domainCheck` or `capability` binding, it would raise a `LoweringError` before producing any bytes.

### Cell engine evaluation

The bytes emitted for this OIR program are (schematically):

```
[PUSH PT-1001.PV field offset]   -- push the sensor reading onto the stack
[PUSH 150.0]                     -- push the threshold
[OP_COMPARE_GT]                  -- compare: push 1 if > 150, 0 otherwise
[OP_NOT]                         -- negate: push 0 if was 1, push 1 if was 0
[OP_VERIFY]                      -- verify: fail execution if top of stack is 0
```

When PT-1001.PV = 142 bar:
- `OP_COMPARE_GT` pushes 0 (142 is not > 150)
- `OP_NOT` pushes 1
- `OP_VERIFY` succeeds
- The valve.open command proceeds

When PT-1001.PV = 163 bar:
- `OP_COMPARE_GT` pushes 1 (163 > 150)
- `OP_NOT` pushes 0
- `OP_VERIFY` fails — the cell engine rejects the command, and the valve.open actuation does not execute

The failure at `OP_VERIFY` is not a software exception. The 2-PDA enters a failure state; the command transaction is aborted without partial execution. The valve stays closed. The evidence chain records the attempted actuation and its rejection, with the timestamp, the operator's hat identity, and the interlock policy cell that blocked it.

### The prohibition structure in full

The worked example demonstrates the semantic structure of a prohibition in the Semantos model:

```
Domain requirement:  pressure > 150 → prohibit valve.open
                         │
                         ▼
Jural category:      prohibition (RELEVANT, authoritative, formal)
                         │
                         ▼
SIR program:         constraint: NOT (PT-1001.PV > 150)
                     action: prohibit
                     allowedEmitOps: [comparison, logical]
                         │
                    lower pass (trust-tier enforced)
                         │
                         ▼
OIR bindings:        $0 = comparison(PT-1001.PV, >, 150)
                     $1 = logical_not($0)
                     result: $1
                         │
                    emit (OIR → bytes)
                         │
                         ▼
Cell engine:         PUSH field | PUSH 150 | OP_COMPARE_GT | OP_NOT | OP_VERIFY
                         │
                         ▼
Enforcement:         valve.open blocked when pressure > 150
                     evidence chain records the blocked attempt
```

Every level carries the semantic intent forward. The jural category — prohibition — is not discarded at the OIR boundary; it determines the structure of the lowering (comparison + negation + VERIFY) and constrains what opcodes can be emitted. The interlock is not a configuration file that the application reads. It is bytecode that the cell engine evaluates before the command executes.

### Running the demo

The 30-minute scope covers the following steps:

1. Express the interlock as a SIR program (the JSON above — ~5 minutes).
2. `semantos sir lower interlock-il001.sir.json` — produces the OIR bindings as a text listing.
3. `semantos sir emit interlock-il001.sir.json --format hex` — produces the byte sequence.
4. `semantos publish interlock-il001.cell` — transitions the cell to RELEVANT linearity and anchors it in the evidence chain.
5. `semantos scada simulate --tag PT-1001.PV=163 --command valve.open V-1001` — the simulator evaluates the cell engine bytes and returns a VERIFY failure with the interlock cell hash.
6. Repeat with `PT-1001.PV=142` — VERIFY succeeds, valve.open proceeds.
7. `semantos cell history --equipment V-1001` — shows both simulated attempts with operator hat identity, sensor reading, and interlock cell hash.

Steps 2–7 run in approximately 15 minutes, leaving time to read the emitted bytes against the OIR listing.

---

## Extensions next

The control-systems lexicon in its current form establishes the seven-category vocabulary and the Lean `Lexicon` instance. Several extensions would make it operationally complete.

### SCADA-specific SIR constraints

The SIR constraint vocabulary (`SIRConstraint`) currently includes `value`, `capability`, `domain`, `temporal`, `state`, and `composite` kinds. For control systems, additional constraint kinds would be useful:

- `{ kind: "tag", tagName: string, op: ComparisonOp, value: number }` — a named process variable comparison, where the tag name is resolved against the SCADA historian at evaluation time rather than encoding a field offset
- `{ kind: "mode", requiredMode: "AUTO" | "MANUAL" | "CASCADE" | "OVERRIDE" }` — a process mode prerequisite, matching the `Condition` jural category for SCADA mode checks
- `{ kind: "interlock", policyId: string }` — a reference to a published interlock policy cell, allowing composite interlocks to reference each other by cell identity

These would be defined in a `scada-ops` extension grammar, following the same pattern as `host-ops.json` — object types, capability definitions, governance configuration.

### Emergency shutdown as combined power and prohibition

The emergency shutdown (ESD) action is the one control-domain operation that simultaneously exercises power (commanding all actuators to safe position) and prohibition (blocking all further operations until a deliberate restart procedure is completed). The SIR representation would be a composite program:

- A `power` node that commands the ESD sequence (LINEAR, consumed by execution)
- A `prohibition` node (RELEVANT) that blocks all further actuations until the prohibition is explicitly removed by an authorised operator via a defined restart procedure

The prohibition created by ESD is distinct from a pre-actuation interlock: it is not condition-based, it does not persist on a sensor reading, and it requires a deliberate human action to remove. Encoding this in the SIR requires the prohibition to reference the ESD event as its activation cause, and to require a `power` exercise of a specific category (restart authorisation) as its removal condition.

### Shift handover as transfer

Shift handover — the transfer of operational responsibility from one operator team to the next — maps to the transfer jural category. The capability tokens that authorise actuation commands are LINEAR: they exist in one hat at a time. The handover event transfers these tokens from the outgoing operator's hat to the incoming operator's hat.

A `ShiftHandoverReceipt` cell would be a LINEAR transfer node: sender is the outgoing hat, receiver is the incoming hat, the transferred objects are the capability tokens for each process unit. The transfer is not complete until the incoming operator's hat has accepted the tokens — an acceptance that could itself require a power exercise (the incoming operator confirming they have received briefing).

### Calibration audit trail

A calibration event is a power exercise that updates the sensor's calibration state cell. The audit trail requirement — a complete chain of calibrations, each referencing its predecessor — is exactly the cell hash-chain property: each calibration cell carries `prevStateHash` pointing to its predecessor, forming an unbroken chain from commissioning to present. A `CalibrationRecord` object type with `prevCalibrationCellId`, `newZero`, `newSpan`, and `authorisedBy` fields, gated by the calibration technician's hat, is the natural extension.

### Formal verification of interlock coverage

The current Lean lexicon proves injectivity of the header function. A richer proof set would cover: every published interlock cell is RELEVANT; no actuation for a given equipment tag can execute without evaluating all published interlocks for that tag; the composite of two prohibition cells is itself a valid prohibition. These theorems, stated over `Patch ControlSystemsCategory`, become the formal equivalent of a HAZOP completeness check — achievable once a `scada-ops` extension grammar defines the interlock library protocol.

---

*The control-systems lexicon maps seven control-domain concepts to the seven jural categories, grounds each in a Lean `Lexicon` instance that carries all substrate theorems, and demonstrates how SCADA "must-not" semantics — interlock IL-001, pressure > 150 bar prohibits valve.open — become bytecode evaluated by the cell engine. The prohibition SIR program with logical negation is the structural bridge between the engineering requirement and the enforcement that runs on the 2-PDA.*
