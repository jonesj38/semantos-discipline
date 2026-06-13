---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/core/cell-engine/mutations/run-mutations.sh
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:17.955305+00:00
---

# core/cell-engine/mutations/run-mutations.sh

```sh
#!/bin/bash
# Phase 12 D12.2: Mutation testing
# Applies 10 mutations to the Zig source, runs tests, verifies each is caught.
# Usage: cd packages/cell-engine && bash mutations/run-mutations.sh

set -euo pipefail

PASS=0
FAIL=0
TOTAL=10
RESULTS=()

run_mutation() {
    local id="$1"
    local file="$2"
    local description="$3"
    local sed_cmd="$4"
    local revert_cmd="$5"

    echo "──────────────────────────────────────────"
    echo "M${id}: ${description}"
    echo "  File: ${file}"

    # Verify file exists
    if [ ! -f "$file" ]; then
        echo "  ERROR: File not found"
        FAIL=$((FAIL + 1))
        RESULTS+=("M${id}: SKIPPED (file not found)")
        return
    fi

    # Take backup
    cp "$file" "${file}.bak"

    # Apply mutation
    eval "$sed_cmd"

    # Verify file changed
    if diff -q "$file" "${file}.bak" > /dev/null 2>&1; then
        echo "  WARNING: sed did not change file — mutation may not match"
        cp "${file}.bak" "$file"
        rm "${file}.bak"
        FAIL=$((FAIL + 1))
        RESULTS+=("M${id}: SURVIVED (mutation did not apply)")
        return
    fi

    # Run tests — expect failure
    echo "  Running tests..."
    if zig build test 2>/dev/null; then
        echo "  SURVIVED — tests passed with mutation! This is a gap."
        FAIL=$((FAIL + 1))
        RESULTS+=("M${id}: SURVIVED — ${description}")
    else
        echo "  KILLED — tests correctly caught the mutation."
        PASS=$((PASS + 1))
        RESULTS+=("M${id}: KILLED — ${description}")
    fi

    # Revert
    cp "${file}.bak" "$file"
    rm "${file}.bak"

    # Verify revert is clean
    if ! diff -q "$file" <(git show HEAD:"$file") > /dev/null 2>&1; then
        echo "  WARNING: revert may not be clean, restoring from git"
        git checkout -- "$file"
    fi
}

echo "╔══════════════════════════════════════════╗"
echo "║  Phase 12 Mutation Testing — 10 Targets  ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# M1: Remove cannot_duplicate_linear → allow LINEAR DUP
run_mutation 1 "src/linearity.zig" \
    "Remove cannot_duplicate_linear (allow LINEAR DUP)" \
    "sed -i.tmp 's/\.duplicate => return error\.cannot_duplicate_linear,/.duplicate => {},/' src/linearity.zig && rm -f src/linearity.zig.tmp" \
    ""

# M2: Remove cannot_discard_linear → allow LINEAR DROP
run_mutation 2 "src/linearity.zig" \
    "Remove cannot_discard_linear (allow LINEAR DROP)" \
    "sed -i.tmp 's/\.discard => return error\.cannot_discard_linear,/.discard => {},/' src/linearity.zig && rm -f src/linearity.zig.tmp" \
    ""

# M3: Remove cannot_duplicate_affine → allow AFFINE DUP
run_mutation 3 "src/linearity.zig" \
    "Remove cannot_duplicate_affine (allow AFFINE DUP)" \
    "sed -i.tmp 's/\.duplicate => return error\.cannot_duplicate_affine,/.duplicate => {},/' src/linearity.zig && rm -f src/linearity.zig.tmp" \
    ""

# M4: Remove cannot_discard_relevant → allow RELEVANT DROP
run_mutation 4 "src/linearity.zig" \
    "Remove cannot_discard_relevant (allow RELEVANT DROP)" \
    "sed -i.tmp 's/\.discard => return error\.cannot_discard_relevant,/.discard => {},/' src/linearity.zig && rm -f src/linearity.zig.tmp" \
    ""

# M5: OP_CHECKDOMAINFLAG always passes (skip flag comparison)
run_mutation 5 "src/opcodes/plexus.zig" \
    "CHECKDOMAINFLAG always TRUE (skip flag comparison)" \
    "sed -i.tmp 's/if (actual_flag != expected_flag) return error\.domain_flag_mismatch;/\/\/ MUTATION: flag check removed/' src/opcodes/plexus.zig && rm -f src/opcodes/plexus.zig.tmp" \
    ""

# M6: OP_CHECKTYPEHASH always passes (skip hash comparison)
run_mutation 6 "src/opcodes/plexus.zig" \
    "CHECKTYPEHASH always TRUE (skip hash comparison)" \
    "sed -i.tmp '/if (!std.mem.eql(u8, \&actual_hash, \&expected_hash)) return error.type_hash_mismatch;/s/.*/    \/\/ MUTATION: hash check removed/' src/opcodes/plexus.zig && rm -f src/opcodes/plexus.zig.tmp" \
    ""

# M7: OP_CHECKIDENTITY always passes (skip owner comparison)
run_mutation 7 "src/opcodes/plexus.zig" \
    "CHECKIDENTITY always TRUE (skip owner comparison)" \
    "sed -i.tmp '/if (!std.mem.eql(u8, \&actual_id, \&expected_id)) return error.owner_id_mismatch;/s/.*/    \/\/ MUTATION: owner check removed/' src/opcodes/plexus.zig && rm -f src/opcodes/plexus.zig.tmp" \
    ""

# M8: Change MAIN_STACK_CELLS from 1024 to 2048
run_mutation 8 "src/constants.zig" \
    "Change MAIN_STACK_CELLS from 1024 to 2048" \
    "sed -i.tmp 's/pub const MAIN_STACK_CELLS: u32 = 1024;/pub const MAIN_STACK_CELLS: u32 = 2048;/' src/constants.zig && rm -f src/constants.zig.tmp" \
    ""

# M9: Remove opcount limit check (infinite execution)
run_mutation 9 "src/executor.zig" \
    "Remove opcount limit check (allow infinite execution)" \
    "sed -i.tmp 's/if (ctx.pda.opcount >= ctx.pda.max_ops) return error.execution_limit;/\/\/ MUTATION: opcount check removed/' src/executor.zig && rm -f src/executor.zig.tmp" \
    ""

# M10: Break atomicity in CHECKCAPABILITY — pop before validation
# Change "peek both" to "pop then check" so failure leaves stack modified
run_mutation 10 "src/opcodes/plexus.zig" \
    "Break CHECKCAPABILITY atomicity (pop before validation)" \
    "sed -i.tmp 's/const cap_item = try p.speekAt(0);/const cap_pop = try p.spop(); const cap_item_data = cap_pop.data; const cap_item = .{ .data = @as(*const pda_mod.Cell, cap_item_data), .len = cap_pop.len };/' src/opcodes/plexus.zig && rm -f src/opcodes/plexus.zig.tmp" \
    ""

# ── Results ──
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  Results: ${PASS}/${TOTAL} killed, ${FAIL}/${TOTAL} survived  ║"
echo "╚══════════════════════════════════════════╝"
echo ""
for r in "${RESULTS[@]}"; do
    echo "  $r"
done
echo ""

if [ "$PASS" -eq "$TOTAL" ]; then
    echo "Kill rate: 100% — all mutations caught."
    exit 0
else
    echo "Kill rate: $((PASS * 100 / TOTAL))% — ${FAIL} mutations survived!"
    exit 1
fi

```
