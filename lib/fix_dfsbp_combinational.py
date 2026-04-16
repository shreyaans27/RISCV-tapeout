#!/usr/bin/env python3
"""
fix_dfsbp_combinational.py
Removes combinational timing groups from dfsbp_1 cell in liberty files.
Also removes wrong 'clear' timing type arcs from dfsbp_1.
Usage: python3 fix_dfsbp_combinational.py <lib_file> [lib_file2 ...]
"""

import sys
import re
import shutil

BAD_TYPES = {"combinational", "combinational_rise", "combinational_fall", "combinational_rise"}

def fix_lib(filepath):
    print(f"\nProcessing: {filepath}")
    shutil.copy(filepath, filepath + ".bak")

    with open(filepath, "r") as f:
        lines = f.readlines()

    in_dfsbp = False
    in_timing_group = False
    brace_depth = 0
    timing_lines = []
    timing_start = None
    timing_type = None
    bad_timing_ranges = []  # list of (start, end) line indices to remove
    dfsbp_brace_depth = 0

    i = 0
    while i < len(lines):
        line = lines[i]

        # Detect entering dfsbp_1 cell
        if re.search(r'cell\s*\(dfsbp_1\)', line):
            in_dfsbp = True
            dfsbp_brace_depth = 0

        if in_dfsbp:
            # Track brace depth within dfsbp_1
            dfsbp_brace_depth += line.count('{') - line.count('}')
            if dfsbp_brace_depth <= 0 and i > 0:
                in_dfsbp = False

            # Detect timing group start
            if re.match(r'\s+timing\s*\(\s*\)\s*\{', line) and not in_timing_group:
                in_timing_group = True
                timing_start = i
                timing_lines = [line]
                brace_depth = 1
                i += 1
                continue

            # Inside timing group
            if in_timing_group:
                timing_lines.append(line)
                brace_depth += line.count('{') - line.count('}')

                # Check timing type
                m = re.search(r'timing_type\s*:\s*(\S+);', line)
                if m:
                    timing_type = m.group(1).strip()

                # Check related_pin — if related to Q or QN it's a loop arc
                rp = re.search(r'related_pin\s*:\s*"(\S+)"', line)
                if rp:
                    related = rp.group(1).strip().strip('"')

                # Timing group closed
                if brace_depth <= 0:
                    in_timing_group = False
                    timing_end = i

                    # Mark for removal if:
                    # 1. timing_type is combinational variant
                    # 2. timing_type is 'clear' (wrong for preset cell)
                    if timing_type in BAD_TYPES or timing_type == "clear":
                        bad_timing_ranges.append((timing_start, timing_end))
                        print(f"  Removing timing group: type={timing_type} lines {timing_start+1}-{timing_end+1}")

                    timing_type = None
                    timing_lines = []
                    timing_start = None

        i += 1

    # Build set of lines to remove
    remove_lines = set()
    for start, end in bad_timing_ranges:
        for ln in range(start, end + 1):
            remove_lines.add(ln)

    # Write cleaned file
    cleaned = [line for i, line in enumerate(lines) if i not in remove_lines]

    with open(filepath, "w") as f:
        f.writelines(cleaned)

    print(f"  Removed {len(remove_lines)} lines")
    print(f"  Backup saved as {filepath}.bak")

    # Verify
    with open(filepath, "r") as f:
        content = f.read()

    remaining = len(re.findall(r'combinational', content))
    print(f"  Remaining 'combinational' occurrences in dfsbp_1: {remaining}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 fix_dfsbp_combinational.py <lib_file> [lib_file2 ...]")
        sys.exit(1)

    for f in sys.argv[1:]:
        fix_lib(f)

    print("\nDone! Verify with:")
    print("  grep 'combinational' <lib_file>")