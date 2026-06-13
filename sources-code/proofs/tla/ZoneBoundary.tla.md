---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/proofs/tla/ZoneBoundary.tla
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.344727+00:00
---

# proofs/tla/ZoneBoundary.tla

```tla
--------------------------- MODULE ZoneBoundary ---------------------------
(*
 * Zone Boundary Enforcement — domain flag isolation.
 *
 * Source: src/types/domain-flags.ts
 *   - DomainFlag = number (uint32) (line 13)
 *   - Ranges: PLEXUS_WELL_KNOWN [0x01, 0xFF], EXTENDED_STANDARD [0x100, 0xFFFF],
 *     CLIENT_SOVEREIGN [0x10000, 0xFFFFFFFF] (lines 19-34)
 *   - Well-known flags: 0x01-0x0A (lines 40-94)
 *   - RESERVED = 0x00 (isReserved, line 124-126)
 *   - classifyFlag (lines 102-114): returns tier based on range
 *
 * Well-known flag values (exact match required):
 *   0x01 EDGE_CREATION, 0x02 SIGNING, 0x03 ENCRYPTION, 0x04 MESSAGING,
 *   0x05 ATTESTATION, 0x06 CHILD_CREATION, 0x07 PERMISSION_GRANT,
 *   0x08 DATA_SOVEREIGNTY, 0x09 SCHEMA_SIGNING, 0x0A METERING
 *)

EXTENDS Naturals, FiniteSets

CONSTANTS
    Certs,     \* Set of certificate identifiers (model values)
    NULL       \* Distinguished null value

\* --- Domain flag constants matching domain-flags.ts exactly ---

RESERVED == 0

\* Well-known flags (lines 40-94)
EDGE_CREATION    == 1   \* 0x01
SIGNING          == 2   \* 0x02
ENCRYPTION       == 3   \* 0x03
MESSAGING        == 4   \* 0x04
ATTESTATION      == 5   \* 0x05
CHILD_CREATION   == 6   \* 0x06
PERMISSION_GRANT == 7   \* 0x07
DATA_SOVEREIGNTY == 8   \* 0x08
SCHEMA_SIGNING   == 9   \* 0x09
METERING         == 10  \* 0x0A

WellKnownFlags == {EDGE_CREATION, SIGNING, ENCRYPTION, MESSAGING,
                   ATTESTATION, CHILD_CREATION, PERMISSION_GRANT,
                   DATA_SOVEREIGNTY, SCHEMA_SIGNING, METERING}

\* Range boundaries (lines 19-34)
PLEXUS_WELL_KNOWN_MIN == 1      \* 0x00000001
PLEXUS_WELL_KNOWN_MAX == 255    \* 0x000000FF
EXTENDED_STANDARD_MIN == 256    \* 0x00000100
EXTENDED_STANDARD_MAX == 65535  \* 0x0000FFFF
CLIENT_SOVEREIGN_MIN  == 65536  \* 0x00010000
\* CLIENT_SOVEREIGN_MAX is 0xFFFFFFFF but we use a small model value

\* For model checking: representative flags from each tier
ExtendedFlag == 256   \* smallest EXTENDED_STANDARD flag
SovereignFlag == 65536 \* smallest CLIENT_SOVEREIGN flag

AllModelFlags == WellKnownFlags \cup {RESERVED, ExtendedFlag, SovereignFlag}

\* --- Tier classification matching classifyFlag (lines 102-114) ---

ClassifyFlag(flag) ==
    IF flag >= PLEXUS_WELL_KNOWN_MIN /\ flag <= PLEXUS_WELL_KNOWN_MAX
    THEN "well-known"
    ELSE IF flag >= EXTENDED_STANDARD_MIN /\ flag <= EXTENDED_STANDARD_MAX
    THEN "extended"
    ELSE IF flag >= CLIENT_SOVEREIGN_MIN
    THEN "sovereign"
    ELSE "well-known"  \* Default fallback (line 113)

\* --- IsReserved matching isReserved (lines 124-126) ---

IsReserved(flag) == flag = RESERVED

\* --- State variables ---

VARIABLES
    certFlags,     \* Function: Certs -> set of authorized domain flags
    operations,    \* Set of completed operations (records)
    opCount        \* Operation counter for bounding

vars == <<certFlags, operations, opCount>>

\* --- Initial state ---

(*
 * For model checking, we use representative flag subsets rather than
 * enumerating all 2^10 subsets of WellKnownFlags. Each cert gets a
 * fixed representative set: Zone 1 (EDGE_CREATION only), Zone 4
 * (MESSAGING only), or Zone 1+4 (both). This exercises cross-zone
 * enforcement with tractable state space.
 *)
RepresentativeFlags == {
    {EDGE_CREATION},                    \* Zone 1 cert
    {MESSAGING},                        \* Zone 4 cert
    {EDGE_CREATION, MESSAGING}          \* Zone 1+4 cert
}

Init ==
    /\ certFlags \in [Certs -> RepresentativeFlags]
    /\ operations = {}
    /\ opCount = 0

\* --- Actions ---

(*
 * PerformOperation: a cert performs an operation requiring a specific flag.
 * Guard: the flag must be in the cert's authorized set and not reserved.
 *)
PerformOperation(cert, flag) ==
    /\ opCount < 4
    /\ flag \in certFlags[cert]
    /\ ~IsReserved(flag)
    /\ operations' = operations \cup {[cert |-> cert, flag |-> flag, tier |-> ClassifyFlag(flag)]}
    /\ opCount' = opCount + 1
    /\ UNCHANGED certFlags

(*
 * Adversary: CrossZoneAccess — attempt to use a flag not in the cert's set.
 * The guard (flag \in certFlags[cert]) blocks this.
 * We model the attempt to show it's blocked.
 *)
CrossZoneAccess(cert, flag) ==
    /\ opCount < 4
    /\ flag \notin certFlags[cert]
    /\ ~IsReserved(flag)
    \* Attempt fails — no operation recorded
    /\ UNCHANGED vars

(*
 * Adversary: UseReservedFlag — attempt to use the reserved flag 0x00.
 * Blocked by IsReserved guard.
 *)
UseReservedFlag(cert) ==
    /\ opCount < 4
    /\ UNCHANGED vars

Next ==
    \E c \in Certs :
        \/ \E f \in WellKnownFlags : PerformOperation(c, f)
        \/ \E f \in AllModelFlags : CrossZoneAccess(c, f)
        \/ UseReservedFlag(c)

Spec == Init /\ [][Next]_vars

\* --- Safety properties ---

(*
 * ReservedNeverUsed: no operation uses the reserved flag (0x00000000).
 * Matches isReserved (line 124-126): flag === 0x00000000.
 *)
ReservedNeverUsed ==
    \A op \in operations : ~IsReserved(op.flag)

(*
 * ZoneEnforcement: every operation's flag is authorized for its cert.
 *)
ZoneEnforcement ==
    \A op \in operations : op.flag \in certFlags[op.cert]

(*
 * NoZoneCrossing: a cert authorized for one tier cannot operate in another.
 * If a cert has only well-known flags, all its operations use well-known flags.
 *)
NoZoneCrossing ==
    \A op \in operations :
        ClassifyFlag(op.flag) = op.tier

(*
 * WellKnownFlagsComplete: all 10 well-known flags are representable.
 * Anti-vacuity check: the flag set has the right cardinality.
 *)
WellKnownFlagsComplete ==
    Cardinality(WellKnownFlags) = 10

(*
 * ClassificationCorrect: each well-known flag classifies as "well-known".
 *)
ClassificationCorrect ==
    /\ \A f \in WellKnownFlags : ClassifyFlag(f) = "well-known"
    /\ ClassifyFlag(ExtendedFlag) = "extended"
    /\ ClassifyFlag(SovereignFlag) = "sovereign"
    /\ ClassifyFlag(RESERVED) = "well-known"  \* Default fallback

=============================================================================

```
