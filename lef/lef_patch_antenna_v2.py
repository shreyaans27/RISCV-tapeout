#!/usr/bin/env python3
"""
lef_patch_antenna.py  --  patch missing antenna attributes based on Innovus IMPLF-200/201

Input:  a LEF file that has missing ANTENNAGATEAREA / ANTENNADIFFAREA entries
        on specific (cell, pin) pairs per Innovus's log

Output: a new LEF file with those entries added
        plus a plan report listing every insertion with source provenance
        plus a unified diff for review

Strategy per user instruction: "Same-cell other-pin"
  - For a cell's OUTPUT pin missing ANTENNAGATEAREA:
      copy ANTENNAGATEAREA (and its enclosing ANTENNAMODEL scope) from an
      input pin on the same cell
  - For an INPUT pin missing ANTENNADIFFAREA:
      copy ANTENNADIFFAREA from the OUTPUT pin on the same cell

This script does NOT attempt to fix input pins missing GATEAREA nor output
pins missing DIFFAREA -- those aren't reported as missing by Innovus, and the
hand-built donor/recipient assumption wouldn't hold.

Usage:
    python3 lef_patch_antenna.py <input.lef> <output.lef>
"""

import re
import sys
import argparse
import difflib
from collections import OrderedDict


# -----------------------------------------------------------------------------
# Pin I/O inference by name
# -----------------------------------------------------------------------------

# Cell output pin names — any pin whose name matches is treated as an OUTPUT.
# Covers Y/X/Z/Q and their inverted counterparts (QN, Q_N, YN, Y_N, etc.).
OUTPUT_PIN_NAMES = {
    "Y", "X", "Z", "Q", "CO",
    "QN", "YN", "XN", "ZN",
    "Q_N", "Y_N", "X_N", "Z_N",
}

def is_output_pin_name(pname):
    return pname.upper() in OUTPUT_PIN_NAMES

def is_signal_pin_use(pin_body_text):
    """A pin is a signal pin unless explicitly declared USE POWER or USE GROUND."""
    if re.search(r'^\s*USE\s+POWER\b', pin_body_text, re.MULTILINE):
        return False
    if re.search(r'^\s*USE\s+GROUND\b', pin_body_text, re.MULTILINE):
        return False
    return True

# NOTE: No hardcoded warning list. The patcher now auto-discovers missing
# attributes by scanning the LEF and applying the rule:
#   - every signal OUTPUT pin needs ANTENNAGATEAREA
#   - every signal INPUT pin needs ANTENNADIFFAREA
# Pins that already have the attribute are skipped (e.g. dfrtp_1.Q).


# -----------------------------------------------------------------------------
# LEF structure extraction
# -----------------------------------------------------------------------------

def read_cell_pin_boundaries(lef_path):
    """
    Walk the LEF and for every MACRO, record line ranges of each PIN block
    and the line index of the MACRO header.

    Returns:
        cells: OrderedDict[cell_name] = {
            "macro_start_line": int,
            "macro_end_line":   int,
            "pins": OrderedDict[pin_name] = {
                "start_line":       int,   # 'PIN <n>' line (0-indexed)
                "end_line":         int,   # 'END <n>' line
                "first_port_line":  int,   # where 'PORT' begins (insertion anchor)
                "antenna_lines":    [ (line_idx, raw_line), ... ],
            }
        }

    We skip PROPERTYDEFINITIONS block at file top (it uses MACRO as a type name)
    and any PROPERTY statements inside cells.
    """
    with open(lef_path, 'r') as f:
        lines = f.read().splitlines(keepends=False)

    cells = OrderedDict()
    i = 0
    N = len(lines)

    # 1. Skip PROPERTYDEFINITIONS block if present
    while i < N:
        s = lines[i].strip()
        if s.startswith("PROPERTYDEFINITIONS"):
            j = i + 1
            while j < N and not lines[j].strip().startswith("END PROPERTYDEFINITIONS"):
                j += 1
            i = j + 1
            break
        if s.startswith("MACRO "):
            break
        i += 1

    # 2. Walk real MACROs
    cur_macro = None
    cur_pin   = None

    while i < N:
        stripped = lines[i].strip()
        toks = stripped.split()

        if not toks:
            i += 1
            continue

        # MACRO <name>
        if toks[0] == "MACRO" and cur_macro is None and len(toks) >= 2:
            cur_macro = toks[1]
            cells[cur_macro] = {
                "macro_start_line": i,
                "macro_end_line":   None,
                "pins":             OrderedDict(),
            }
            i += 1
            continue

        # END <name> matching current macro
        if (toks[0] == "END" and len(toks) >= 2
                and cur_macro is not None and toks[1] == cur_macro):
            cells[cur_macro]["macro_end_line"] = i
            cur_macro = None
            cur_pin = None
            i += 1
            continue

        if cur_macro is None:
            i += 1
            continue

        # PIN <name>
        if toks[0] == "PIN" and len(toks) >= 2 and cur_pin is None:
            cur_pin = toks[1]
            cells[cur_macro]["pins"][cur_pin] = {
                "start_line":       i,
                "end_line":         None,
                "first_port_line":  None,
                "antenna_lines":    [],
            }
            i += 1
            continue

        # END <pin_name>
        if (toks[0] == "END" and len(toks) >= 2
                and cur_pin is not None and toks[1] == cur_pin):
            cells[cur_macro]["pins"][cur_pin]["end_line"] = i
            cur_pin = None
            i += 1
            continue

        if cur_pin is None:
            i += 1
            continue

        # First PORT statement within the pin
        if toks[0] == "PORT" and cells[cur_macro]["pins"][cur_pin]["first_port_line"] is None:
            cells[cur_macro]["pins"][cur_pin]["first_port_line"] = i

        # Track every line containing an ANTENNA attribute
        if "ANTENNA" in toks[0]:
            cells[cur_macro]["pins"][cur_pin]["antenna_lines"].append(
                (i, lines[i])
            )

        # Also catch the ANTENNAMODEL-scoped entries (indented one more level)
        # These start with ANTENNA... but after whitespace so toks[0] still works
        # -- already covered by the above check

        i += 1

    return cells, lines


# -----------------------------------------------------------------------------
# Extraction helpers
# -----------------------------------------------------------------------------

GATEAREA_RE = re.compile(r'^\s*ANTENNAGATEAREA\s+([\d.]+)\s+LAYER\s+(\S+)\s*;')
DIFFAREA_RE = re.compile(r'^\s*ANTENNADIFFAREA\s+([\d.]+)\s+LAYER\s+(\S+)\s*;')
ANTENNAMODEL_RE = re.compile(r'^\s*ANTENNAMODEL\s+(\S+)\s*;')


def extract_gatearea_block_from_pin(pin_info, all_lines):
    """
    For a donor input pin that has GATEAREA attributes:
    Find the ANTENNAMODEL ... line and extract JUST the ANTENNAGATEAREA lines
    that follow it (until next top-level attr or PORT).

    Returns:  (antenna_model_line_text, [gatearea_line_texts...])  or (None, None)
    """
    model_line_idx = None
    for (idx, raw) in pin_info["antenna_lines"]:
        if ANTENNAMODEL_RE.match(raw):
            model_line_idx = idx
            model_line_text = raw
            break

    if model_line_idx is None:
        # Maybe the pin has GATEAREA without an ANTENNAMODEL wrapper?
        gate_lines = [raw for (_, raw) in pin_info["antenna_lines"]
                      if GATEAREA_RE.match(raw)]
        if gate_lines:
            return (None, gate_lines)
        return (None, None)

    # Collect GATEAREA lines following the model line
    gate_lines = []
    j = model_line_idx + 1
    while j < len(all_lines):
        stripped = all_lines[j].strip()
        if not stripped:
            j += 1
            continue
        # Stop when we hit PORT, END <pin>, or another top-level ANTENNA attr
        # (PARTIALMETALAREA, PARTIALMETALSIDEAREA etc., as seen by indent level)
        if stripped.startswith("PORT") or stripped.startswith("END "):
            break
        # GATEAREA entries - collect them
        if GATEAREA_RE.match(all_lines[j]):
            gate_lines.append(all_lines[j])
            j += 1
            continue
        # Any other ANTENNA attr that's not GATEAREA and not inside the model scope
        # -- determined by indent. Inside model scope, it's indented further.
        # The model-scoped attrs in your LEF are indented 6 spaces; outside is 4.
        if stripped.startswith("ANTENNA") and not all_lines[j].startswith("      "):
            # Outside of OXIDE1 scope -- we're done
            break
        # Otherwise (MAXAREACAR, MAXCUTCAR inside scope) -- skip over
        j += 1

    return (model_line_text, gate_lines)


def extract_diffarea_lines_from_pin(pin_info):
    """Return raw ANTENNADIFFAREA lines verbatim from a donor pin."""
    return [raw for (_, raw) in pin_info["antenna_lines"]
            if DIFFAREA_RE.match(raw)]


def find_donor_input_pin(cell_info):
    """Pick the first input-ish pin (not Y/X/Z/Q) with ANTENNAGATEAREA."""
    output_names = {"Y", "X", "Z", "Q", "QN"}
    for pname, p in cell_info["pins"].items():
        if pname in output_names:
            continue
        # Check this pin has any GATEAREA
        has_gate = any(GATEAREA_RE.match(raw) for (_, raw) in p["antenna_lines"])
        if has_gate:
            return pname
    return None


def find_donor_output_pin(cell_info):
    """Pick the output pin (Y or X) with ANTENNADIFFAREA."""
    for pname in ("Y", "X", "Z", "Q"):
        if pname in cell_info["pins"]:
            p = cell_info["pins"][pname]
            has_diff = any(DIFFAREA_RE.match(raw) for (_, raw) in p["antenna_lines"])
            if has_diff:
                return pname
    return None


# -----------------------------------------------------------------------------
# Plan building
# -----------------------------------------------------------------------------

def build_patch_plan(cells, all_lines):
    """
    Auto-discover pins that need antenna attributes added.

    Rule:
      - Every signal OUTPUT pin (Y/X/Z/Q/CO/QN/Q_N/...) needs ANTENNAGATEAREA
      - Every signal INPUT pin (everything else with USE SIGNAL)  needs ANTENNADIFFAREA

    If a pin already has the required attribute, it's skipped (e.g. dfrtp_1.Q
    already has GATEAREA from abstracta due to its internal feedback path).

    For each missing pin, we copy values from another pin on the same cell:
      - OUTPUT missing GATEAREA -> copy from any INPUT pin that has GATEAREA
      - INPUT  missing DIFFAREA -> copy from an OUTPUT pin that has DIFFAREA

    Returns:
      plan: [ {
          "cell": str,
          "target_pin": str,
          "insert_at_line": int,
          "lines_to_insert": [str, ...],
          "source": str,
          "kind": "GATEAREA" | "DIFFAREA",
      }, ... ]

      errors: [ (cell, pin, reason), ... ]
    """
    plan = []
    errors = []

    for cname, cinfo in cells.items():
        for pname, pinfo in cinfo["pins"].items():
            # Skip power/ground pins -- they don't need antenna attributes
            antenna_raws = [raw for (_, raw) in pinfo["antenna_lines"]]
            # Check if this pin has a USE POWER/GROUND declaration
            # (we don't track `use` directly in the struct; re-derive from raw lines)
            # Easier: search the lines between start_line and end_line for USE POWER/GROUND
            start = pinfo["start_line"]
            end   = pinfo["end_line"] if pinfo["end_line"] is not None else start + 1
            pin_body = "\n".join(all_lines[start:end+1])
            if not is_signal_pin_use(pin_body):
                continue

            if pinfo["first_port_line"] is None:
                # Edge case: no PORT statement. Skip with a warning.
                errors.append((cname, pname, "no PORT statement; cannot find insertion anchor"))
                continue

            is_output = is_output_pin_name(pname)
            has_gate  = any(GATEAREA_RE.match(raw) for raw in antenna_raws)
            has_diff  = any(DIFFAREA_RE.match(raw) for raw in antenna_raws)

            if is_output:
                # Output pin: needs GATEAREA
                if has_gate:
                    continue  # Already has it (e.g. dfrtp_1.Q) - skip
                # Find donor input pin with GATEAREA
                donor_pin_name = find_donor_input_pin(cinfo)
                if donor_pin_name is None:
                    errors.append((cname, pname,
                        "no input pin with GATEAREA available as donor"))
                    continue
                donor_pin = cinfo["pins"][donor_pin_name]
                model_line, gate_lines = extract_gatearea_block_from_pin(donor_pin, all_lines)
                if not gate_lines:
                    errors.append((cname, pname,
                        f"donor pin '{donor_pin_name}' unexpectedly has no GATEAREA"))
                    continue
                # Build insertion block
                lines_to_insert = []
                if model_line is not None:
                    lines_to_insert.append(model_line)
                lines_to_insert.extend(gate_lines)

                plan.append({
                    "cell":            cname,
                    "target_pin":      pname,
                    "insert_at_line":  pinfo["first_port_line"],
                    "lines_to_insert": lines_to_insert,
                    "source":          f"{cname}.{donor_pin_name}",
                    "kind":            "GATEAREA",
                })
            else:
                # Input pin: needs DIFFAREA
                if has_diff:
                    continue  # Already has it (e.g. dfrtp_1.RESET) - skip
                donor_pin_name = find_donor_output_pin(cinfo)
                if donor_pin_name is None:
                    errors.append((cname, pname,
                        "no output pin with DIFFAREA available as donor"))
                    continue
                donor_pin = cinfo["pins"][donor_pin_name]
                diff_lines = extract_diffarea_lines_from_pin(donor_pin)
                if not diff_lines:
                    errors.append((cname, pname,
                        f"donor pin '{donor_pin_name}' unexpectedly has no DIFFAREA"))
                    continue

                plan.append({
                    "cell":            cname,
                    "target_pin":      pname,
                    "insert_at_line":  pinfo["first_port_line"],
                    "lines_to_insert": diff_lines,
                    "source":          f"{cname}.{donor_pin_name}",
                    "kind":            "DIFFAREA",
                })

    return plan, errors


# -----------------------------------------------------------------------------
# Applying the plan
# -----------------------------------------------------------------------------

def apply_plan(all_lines, plan):
    """
    Apply all insertions. Because each insertion shifts subsequent line numbers,
    we process them from HIGHEST line number to LOWEST -- that way earlier
    insertion points stay valid.
    """
    # Sort by insert_at_line descending
    sorted_plan = sorted(plan, key=lambda e: -e["insert_at_line"])

    new_lines = list(all_lines)
    for entry in sorted_plan:
        insert_idx = entry["insert_at_line"]
        # NOTE: no inline LEF comment -- '#' is not a portable LEF comment syntax.
        # Provenance is captured in the plan report instead.
        block = list(entry["lines_to_insert"])
        # Insert before the PORT line
        new_lines[insert_idx:insert_idx] = block

    return new_lines


# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("input_lef")
    ap.add_argument("output_lef")
    ap.add_argument("--plan-report", default=None,
                    help="Write human-readable plan to this path")
    ap.add_argument("--diff", default=None,
                    help="Write unified diff to this path")
    args = ap.parse_args()

    print(f"Reading {args.input_lef} ...")
    cells, all_lines = read_cell_pin_boundaries(args.input_lef)
    print(f"  Parsed {len(cells)} MACROs, {sum(len(c['pins']) for c in cells.values())} pins total")

    print("Building patch plan ...")
    plan, errors = build_patch_plan(cells, all_lines)

    print(f"  Plan: {len(plan)} insertions")
    print(f"  Errors: {len(errors)}")

    if errors:
        print("\nERRORS encountered -- these will NOT be patched:")
        for (c, p, reason) in errors:
            print(f"  {c}.{p}: {reason}")

    # Plan report
    if args.plan_report:
        with open(args.plan_report, 'w') as f:
            f.write(f"Patch plan: {len(plan)} insertions\n")
            f.write("=" * 70 + "\n\n")
            for entry in plan:
                f.write(f"[{entry['cell']}.{entry['target_pin']}]  ")
                f.write(f"insert {entry['kind']} at line {entry['insert_at_line']+1} ")
                f.write(f"(from {entry['source']})\n")
                for L in entry["lines_to_insert"]:
                    f.write(f"    | {L}\n")
                f.write("\n")
            if errors:
                f.write("\nERRORS:\n")
                for (c, p, reason) in errors:
                    f.write(f"  {c}.{p}: {reason}\n")
        print(f"Plan report: {args.plan_report}")

    # Apply
    new_lines = apply_plan(all_lines, plan)

    # Write output
    with open(args.output_lef, 'w') as f:
        f.write("\n".join(new_lines))
        # Preserve trailing newline if original had it
        with open(args.input_lef, 'r') as orig:
            if orig.read().endswith("\n"):
                f.write("\n")
    print(f"Patched LEF: {args.output_lef}")

    # Diff
    if args.diff:
        orig = open(args.input_lef).read().splitlines()
        new  = open(args.output_lef).read().splitlines()
        d = difflib.unified_diff(orig, new,
                                  fromfile=args.input_lef,
                                  tofile=args.output_lef,
                                  n=3)
        with open(args.diff, 'w') as f:
            f.writelines(line + "\n" for line in d)
        print(f"Diff: {args.diff}")

    print(f"\nSummary:")
    print(f"  Original lines: {len(all_lines)}")
    print(f"  Patched lines:  {len(new_lines)}  (+{len(new_lines) - len(all_lines)})")


if __name__ == "__main__":
    main()
