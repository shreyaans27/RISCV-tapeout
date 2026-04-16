#!/usr/bin/env python3
"""
verify_lib.py — Liberty file regression test
Checks all cells for correct timing arcs, flags bad arcs, missing arcs.

Usage: python3 verify_lib.py <lib_file> [lib_file2 ...]

Checks:
  1. All expected cells are present
  2. Combinational cells have delay arcs for every input → output
  3. Flip-flops have: rising_edge, setup, hold, min_pulse_width
  4. Flip-flops with async pins have: recovery, removal, preset/clear
  5. No combinational arcs between Q and Q_N (dfsbp_1 bug)
  6. No 'clear' arcs in preset-only cells (dfsbp_1)
  7. No 'preset' arcs in clear-only cells (dfrtp_1)
  8. Latches have: combinational (D→Q), rising_edge (GATE→Q), setup, hold
"""
import sys
import re

# ============================================================
# Cell definitions: name → {type, inputs, outputs, clock, async, async_type}
# ============================================================
CELL_DEFS = {
    # Inverters
    "inv_1":    {"type": "combo", "inputs": ["A"], "outputs": ["Y"]},
    "inv_2":    {"type": "combo", "inputs": ["A"], "outputs": ["Y"]},
    "inv_4":    {"type": "combo", "inputs": ["A"], "outputs": ["Y"]},
    "inv_8":    {"type": "combo", "inputs": ["A"], "outputs": ["Y"]},
    "inv_16":   {"type": "combo", "inputs": ["A"], "outputs": ["Y"]},
    # Buffers
    "buf_1":    {"type": "combo", "inputs": ["A"], "outputs": ["Y"]},
    "buf_2":    {"type": "combo", "inputs": ["A"], "outputs": ["Y"]},
    "buf_4":    {"type": "combo", "inputs": ["A"], "outputs": ["Y"]},
    "buf_8":    {"type": "combo", "inputs": ["A"], "outputs": ["Y"]},
    "buf_16":   {"type": "combo", "inputs": ["A"], "outputs": ["Y"]},
    # NAND gates
    "nand2_1":  {"type": "combo", "inputs": ["A", "B"], "outputs": ["Y"]},
    "nand2_2":  {"type": "combo", "inputs": ["A", "B"], "outputs": ["Y"]},
    "nand2_4":  {"type": "combo", "inputs": ["A", "B"], "outputs": ["Y"]},
    "nand2_8":  {"type": "combo", "inputs": ["A", "B"], "outputs": ["Y"]},
    "nand2b_1": {"type": "combo", "inputs": ["A_N", "B"], "outputs": ["Y"]},
    "nand4_1":  {"type": "combo", "inputs": ["A", "B", "C", "D"], "outputs": ["Y"]},
    # NOR gates
    "nor2_1":   {"type": "combo", "inputs": ["A", "B"], "outputs": ["Y"]},
    "nor2_4":   {"type": "combo", "inputs": ["A", "B"], "outputs": ["Y"]},
    "nor2_8":   {"type": "combo", "inputs": ["A", "B"], "outputs": ["Y"]},
    # AOI gates
    "a21oi_1":  {"type": "combo", "inputs": ["A1", "A2", "B1"], "outputs": ["Y"]},
    "a21oi_2":  {"type": "combo", "inputs": ["A1", "A2", "B1"], "outputs": ["Y"]},
    "a21oi_4":  {"type": "combo", "inputs": ["A1", "A2", "B1"], "outputs": ["Y"]},
    "a21oi_8":  {"type": "combo", "inputs": ["A1", "A2", "B1"], "outputs": ["Y"]},
    "a211o_2":  {"type": "combo", "inputs": ["A1", "A2", "B1", "C1"], "outputs": ["X"]},
    # OAI gates
    "o21ai_1":  {"type": "combo", "inputs": ["A1", "A2", "B1"], "outputs": ["Y"]},
    "o21ai_2":  {"type": "combo", "inputs": ["A1", "A2", "B1"], "outputs": ["Y"]},
    "o21ai_4":  {"type": "combo", "inputs": ["A1", "A2", "B1"], "outputs": ["Y"]},
    "o21ai_8":  {"type": "combo", "inputs": ["A1", "A2", "B1"], "outputs": ["Y"]},
    # XOR
    "xor2_1":   {"type": "combo", "inputs": ["A", "B"], "outputs": ["X"]},
    # MUX
    "mux2":     {"type": "combo", "inputs": ["A0", "A1", "S"], "outputs": ["X"]},
    "mux2i":    {"type": "combo", "inputs": ["A0", "A1", "S"], "outputs": ["Y"]},
    # Flip-flops
    "dfrtp_1":  {"type": "dff", "inputs": ["D"], "outputs": ["Q"], "clock": "CLK",
                 "async": "RESET_B", "async_type": "clear"},
    "dfsbp_1":  {"type": "dff", "inputs": ["D"], "outputs": ["Q", "Q_N"], "clock": "CLK",
                 "async": "SET_B", "async_type": "preset"},
    "dfxtp_1":  {"type": "dff", "inputs": ["D"], "outputs": ["Q"], "clock": "CLK",
                 "async": None, "async_type": None},
    # Latch
    "dlxbp_1":  {"type": "latch", "inputs": ["D"], "outputs": ["Q", "Q_N"], "clock": "GATE",
                 "async": None, "async_type": None},
}


def extract_cells(filepath):
    """Parse lib file and extract cell blocks with their timing info."""
    with open(filepath, "r") as f:
        content = f.read()
        lines = content.split("\n")

    cells = {}
    i = 0
    while i < len(lines):
        # Find cell definition
        m = re.match(r'\s+cell\s*\((\S+)\)\s*\{', lines[i])
        if m:
            cell_name = m.group(1)
            brace_depth = 1
            cell_lines = [lines[i]]
            i += 1
            while i < len(lines) and brace_depth > 0:
                brace_depth += lines[i].count('{') - lines[i].count('}')
                cell_lines.append(lines[i])
                i += 1
            cells[cell_name] = "\n".join(cell_lines)
        else:
            i += 1
    return cells


def extract_timing_arcs(cell_text):
    """Extract all timing groups from a cell block."""
    arcs = []
    lines = cell_text.split("\n")
    i = 0
    while i < len(lines):
        if re.match(r'\s+timing\s*\(\s*\)\s*\{', lines[i]):
            brace_depth = 1
            timing_text = [lines[i]]
            i += 1
            while i < len(lines) and brace_depth > 0:
                brace_depth += lines[i].count('{') - lines[i].count('}')
                timing_text.append(lines[i])
                i += 1
            block = "\n".join(timing_text)

            # Extract timing_type
            tt_match = re.search(r'timing_type\s*:\s*(\S+)\s*;', block)
            timing_type = tt_match.group(1) if tt_match else "unknown"

            # Extract related_pin
            rp_match = re.search(r'related_pin\s*:\s*"(\S+)"', block)
            related_pin = rp_match.group(1) if rp_match else "unknown"

            arcs.append({"timing_type": timing_type, "related_pin": related_pin, "text": block})
        else:
            i += 1
    return arcs


def find_pin_for_timing(cell_text, timing_text):
    """Find which output pin a timing group belongs to by checking parent pin block."""
    lines = cell_text.split("\n")
    timing_start = cell_text.find(timing_text[:80])
    if timing_start < 0:
        return "unknown"

    # Search backwards from timing group to find parent pin
    before = cell_text[:timing_start]
    pin_matches = list(re.finditer(r'pin\s*\((\S+)\)\s*\{', before))
    if pin_matches:
        return pin_matches[-1].group(1)
    return "unknown"


def verify_cell(cell_name, cell_text, cell_def):
    """Verify a single cell's timing arcs."""
    errors = []
    warnings = []
    info = []

    arcs = extract_timing_arcs(cell_text)
    arc_types = [a["timing_type"] for a in arcs]
    arc_related = [(a["timing_type"], a["related_pin"]) for a in arcs]

    cell_type = cell_def["type"]

    if cell_type == "combo":
        # Check: each input should have delay arcs to each output
        # We check by looking for related_pin matching each input
        for inp in cell_def["inputs"]:
            has_arc = any(a["related_pin"] == inp for a in arcs
                        if a["timing_type"] not in ["min_pulse_width", "setup_rising",
                        "hold_rising", "setup_falling", "hold_falling"])
            if not has_arc:
                errors.append(f"Missing delay arc from input '{inp}'")

        # Check: no sequential timing types
        bad_seq = [t for t in arc_types if t in ["rising_edge", "falling_edge",
                   "setup_rising", "hold_rising", "preset", "clear"]]
        if bad_seq:
            errors.append(f"Combinational cell has sequential timing types: {bad_seq}")

    elif cell_type == "dff":
        # Required: rising_edge (CLK → Q)
        has_rising_edge = "rising_edge" in arc_types
        if not has_rising_edge:
            errors.append("Missing 'rising_edge' arc (CLK → Q delay)")

        # Required: setup and hold
        has_setup = any(t.startswith("setup") for t in arc_types)
        has_hold = any(t.startswith("hold") for t in arc_types)
        if not has_setup:
            errors.append("Missing 'setup' constraint arc")
        if not has_hold:
            errors.append("Missing 'hold' constraint arc")

        # Required: min_pulse_width
        has_mpw = "min_pulse_width" in arc_types
        if not has_mpw:
            errors.append("Missing 'min_pulse_width' arc")

        # Async pin checks
        async_pin = cell_def.get("async")
        async_type = cell_def.get("async_type")

        if async_pin:
            # Should have recovery and removal
            has_recovery = any(t.startswith("recovery") for t in arc_types)
            has_removal = any(t.startswith("removal") for t in arc_types)
            if not has_recovery:
                errors.append(f"Missing 'recovery' arc for async pin '{async_pin}'")
            if not has_removal:
                errors.append(f"Missing 'removal' arc for async pin '{async_pin}'")

            # Should have correct async type (preset or clear)
            if async_type == "preset":
                has_preset = "preset" in arc_types
                if not has_preset:
                    errors.append(f"Missing 'preset' arc for SET pin '{async_pin}'")
                # Should NOT have 'clear'
                has_clear = "clear" in arc_types
                if has_clear:
                    errors.append(f"BAD: 'clear' arc found in preset-only cell (async pin '{async_pin}')")

            elif async_type == "clear":
                has_clear = "clear" in arc_types
                if not has_clear:
                    errors.append(f"Missing 'clear' arc for RESET pin '{async_pin}'")
                # Should NOT have 'preset'
                has_preset = "preset" in arc_types
                if has_preset:
                    errors.append(f"BAD: 'preset' arc found in clear-only cell (async pin '{async_pin}')")

        # Check: no combinational arcs (Q ↔ Q_N loop)
        has_combo = "combinational" in arc_types
        if has_combo:
            errors.append("BAD: 'combinational' timing arc in flip-flop (Q ↔ Q_N loop?)")

    elif cell_type == "latch":
        # Required: combinational (D → Q, transparent path) — this IS correct for latches
        has_combo = "combinational" in arc_types
        if not has_combo:
            warnings.append("Missing 'combinational' arc (D → Q transparent path)")

        # Required: rising_edge (GATE → Q)
        has_rising_edge = "rising_edge" in arc_types
        if not has_rising_edge:
            errors.append("Missing 'rising_edge' arc (GATE → Q)")

        # Required: setup and hold
        has_setup = any(t.startswith("setup") for t in arc_types)
        has_hold = any(t.startswith("hold") for t in arc_types)
        if not has_setup:
            errors.append("Missing 'setup' constraint arc")
        if not has_hold:
            errors.append("Missing 'hold' constraint arc")

        # Required: min_pulse_width
        has_mpw = "min_pulse_width" in arc_types
        if not has_mpw:
            errors.append("Missing 'min_pulse_width' arc")

    # Count arcs
    info.append(f"Total timing arcs: {len(arcs)}")
    type_counts = {}
    for t in arc_types:
        type_counts[t] = type_counts.get(t, 0) + 1
    info.append(f"Arc types: {dict(type_counts)}")

    return errors, warnings, info


def verify_lib(filepath):
    """Run all checks on a liberty file."""
    print(f"\n{'='*70}")
    print(f"  Verifying: {filepath}")
    print(f"{'='*70}")

    cells = extract_cells(filepath)
    total_errors = 0
    total_warnings = 0
    total_pass = 0

    # Check 1: All expected cells present
    print(f"\n--- Cell Presence Check ---")
    missing = []
    extra = []
    for name in CELL_DEFS:
        if name not in cells:
            missing.append(name)
    for name in cells:
        if name not in CELL_DEFS:
            extra.append(name)

    if missing:
        print(f"  MISSING cells ({len(missing)}): {', '.join(sorted(missing))}")
        total_errors += len(missing)
    if extra:
        print(f"  EXTRA cells (not in checklist): {', '.join(sorted(extra))}")
    print(f"  Found {len(cells)} cells, expected {len(CELL_DEFS)}")

    # Check 2: Verify each cell
    print(f"\n--- Per-Cell Timing Arc Check ---")
    for cell_name in sorted(CELL_DEFS.keys()):
        if cell_name not in cells:
            continue

        cell_def = CELL_DEFS[cell_name]
        errors, warnings, info = verify_cell(cell_name, cells[cell_name], cell_def)

        if errors:
            print(f"\n  FAIL  {cell_name} ({cell_def['type']})")
            for e in errors:
                print(f"    ERROR: {e}")
            for w in warnings:
                print(f"    WARN:  {w}")
            for i in info:
                print(f"    info:  {i}")
            total_errors += len(errors)
        elif warnings:
            print(f"\n  WARN  {cell_name} ({cell_def['type']})")
            for w in warnings:
                print(f"    WARN:  {w}")
            for i in info:
                print(f"    info:  {i}")
            total_warnings += len(warnings)
        else:
            total_pass += 1

    # Summary
    print(f"\n{'='*70}")
    print(f"  SUMMARY: {filepath}")
    print(f"{'='*70}")
    print(f"  Cells: {len(cells)} found / {len(CELL_DEFS)} expected")
    print(f"  PASS:     {total_pass}")
    print(f"  WARNINGS: {total_warnings}")
    print(f"  ERRORS:   {total_errors}")

    if total_errors == 0:
        print(f"\n  *** ALL CHECKS PASSED ***")
    else:
        print(f"\n  *** {total_errors} ERROR(S) FOUND — FIX BEFORE SYNTHESIS ***")

    print(f"{'='*70}\n")
    return total_errors


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 verify_lib.py <lib_file> [lib_file2 ...]")
        print("Verifies timing arcs for all standard cells in a Liberty file.")
        sys.exit(1)

    total = 0
    for f in sys.argv[1:]:
        total += verify_lib(f)

    if total == 0:
        print("ALL FILES PASSED VERIFICATION")
        sys.exit(0)
    else:
        print(f"TOTAL ERRORS ACROSS ALL FILES: {total}")
        sys.exit(1)
