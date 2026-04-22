#!/usr/bin/env python3
"""
lef_inspect.py  --  robust LEF antenna inspector (v4)
    v4: Q_N / Y_N / QN classified as OUTPUT (inverted output pins)
        RESET / RESET_B / NCLK recognized as INPUT (not UNKNOWN)
    v3: PROPERTYDEFINITIONS, PROPERTY, bare END handling

Handles real-world LEF quirks:
  * PROPERTYDEFINITIONS block at file-top that uses "MACRO" as a type name
  * PROPERTY statements inside cell MACROs
  * Bare "END" closing nested blocks (PORT, LAYER, SPACING)
  * DIRECTION INOUT tagging (uses pin-name inference to figure out in/out)
  * Multi-layer antenna attributes per pin

Usage:
    python3 lef_inspect.py team2stdcells_final.lef
    python3 lef_inspect.py team2stdcells_final.lef --debug 2> debug.log > report.txt
"""

import re
import sys
from collections import OrderedDict, defaultdict


PIN_ANTENNA_ATTRS = {
    "ANTENNAMODEL",
    "ANTENNAGATEAREA",
    "ANTENNADIFFAREA",
    "ANTENNAAREARATIO",
    "ANTENNADIFFAREARATIO",
    "ANTENNACUMAREARATIO",
    "ANTENNACUMDIFFAREARATIO",
    "ANTENNAPARTIALMETALAREA",
    "ANTENNAPARTIALMETALSIDEAREA",
    "ANTENNAPARTIALCUTAREA",
    "ANTENNAMAXAREACAR",
    "ANTENNAMAXSIDEAREACAR",
    "ANTENNAMAXCUTCAR",
}


def tokenize(path):
    """Read file, strip comments, split into tokens with line numbers."""
    tokens = []
    with open(path, 'r') as f:
        for lineno, line in enumerate(f, 1):
            hash_pos = line.find('#')
            if hash_pos >= 0:
                line = line[:hash_pos]
            line = line.replace(';', ' ; ')
            for tok in line.split():
                tokens.append((tok, lineno))
    return tokens


def parse_lef(path, debug=False):
    """Token-based LEF parser with scope stack."""
    tokens = tokenize(path)
    macros = OrderedDict()
    scope_stack = []

    i = 0
    N = len(tokens)

    while i < N:
        tok, lineno = tokens[i]

        # Skip PROPERTYDEFINITIONS block.
        # The block uses MACRO as a type keyword, which would otherwise
        # trigger false MACRO scope pushes. Example:
        #   PROPERTYDEFINITIONS
        #     MACRO deviceLevel STRING ;
        #   END PROPERTYDEFINITIONS
        if tok == "PROPERTYDEFINITIONS":
            if debug:
                print("  [line %d] SKIP PROPERTYDEFINITIONS block" % lineno, file=sys.stderr)
            i += 1
            while i < N - 1:
                if tokens[i][0] == "END" and tokens[i + 1][0] == "PROPERTYDEFINITIONS":
                    if debug:
                        print("  [line %d] END PROPERTYDEFINITIONS" % tokens[i][1], file=sys.stderr)
                    i += 2
                    break
                i += 1
            continue

        # Skip PROPERTY <n> <value> ; statements (inside cell MACROs too)
        if tok == "PROPERTY":
            if debug:
                nxt = tokens[i + 1][0] if i + 1 < N else "?"
                print("  [line %d] SKIP PROPERTY %s" % (lineno, nxt), file=sys.stderr)
            i += 1
            while i < N and tokens[i][0] != ";":
                i += 1
            i += 1
            continue

        # MACRO <n>
        if tok == "MACRO" and i + 1 < N:
            name = tokens[i + 1][0]
            scope_stack.append(("MACRO", name, lineno))
            macros[name] = {"pins": OrderedDict()}
            if debug:
                print("  [line %d] PUSH MACRO %s  depth=%d" % (lineno, name, len(scope_stack)),
                      file=sys.stderr)
            i += 2
            continue

        # PIN <n> (only inside a MACRO)
        if (tok == "PIN" and i + 1 < N
                and scope_stack and scope_stack[-1][0] == "MACRO"):
            name = tokens[i + 1][0]
            cur_macro = scope_stack[-1][1]
            scope_stack.append(("PIN", name, lineno))
            macros[cur_macro]["pins"][name] = {
                "direction": None,
                "use":       None,
                "antenna":   [],
            }
            if debug:
                print("  [line %d] PUSH PIN %s in %s" % (lineno, name, cur_macro),
                      file=sys.stderr)
            i += 2
            continue

        # END handling
        if tok == "END":
            next_tok = tokens[i + 1][0] if i + 1 < N else None

            # Matches current scope - pop
            if scope_stack and next_tok == scope_stack[-1][1]:
                popped = scope_stack.pop()
                if debug:
                    print("  [line %d] POP %s %s" % (lineno, popped[0], popped[1]),
                          file=sys.stderr)
                i += 2
                continue

            # END LIBRARY - file end
            if next_tok == "LIBRARY":
                if debug:
                    print("  [line %d] END LIBRARY" % lineno, file=sys.stderr)
                i += 2
                continue

            # Bare END or END <unknown> - nested block close, consume only END
            if debug:
                print("  [line %d] END (nested block, next=%r)" % (lineno, next_tok),
                      file=sys.stderr)
            i += 1
            continue

        # DIRECTION/USE/antenna attrs (only inside PIN scope)
        if scope_stack and scope_stack[-1][0] == "PIN":
            cur_pin = scope_stack[-1][1]
            cur_macro = None
            for frame in reversed(scope_stack):
                if frame[0] == "MACRO":
                    cur_macro = frame[1]
                    break
            if cur_macro is None:
                i += 1
                continue
            pin = macros[cur_macro]["pins"][cur_pin]

            if tok == "DIRECTION" and i + 1 < N:
                pin["direction"] = tokens[i + 1][0]
                i += 2
                continue

            if tok == "USE" and i + 1 < N:
                pin["use"] = tokens[i + 1][0]
                i += 2
                continue

            if tok in PIN_ANTENNA_ATTRS:
                if tok == "ANTENNAMODEL":
                    mode = tokens[i + 1][0] if i + 1 < N else None
                    pin["antenna"].append((tok, None, mode))
                    i += 2
                    continue
                # <attr> <value> [LAYER <layer>] ;
                if i + 1 < N:
                    try:
                        val = float(tokens[i + 1][0])
                    except ValueError:
                        i += 1
                        continue
                    layer = None
                    for look in range(i + 2, min(i + 6, N)):
                        if tokens[look][0] == "LAYER" and look + 1 < N:
                            layer = tokens[look + 1][0]
                            break
                        if tokens[look][0] == ";":
                            break
                    pin["antenna"].append((tok, val, layer))
                    while i < N and tokens[i][0] != ";":
                        i += 1
                    i += 1
                    continue

        i += 1

    if scope_stack:
        print("WARN: scope stack not empty at EOF: %s" % scope_stack, file=sys.stderr)

    return macros, tokens


def infer_io_from_name(pname):
    base = pname.split('[')[0].upper()
    # Outputs: Y/X/Z/Q/CO and their inverted variants (QN, Q_N, YN, etc)
    if base in {"Y", "X", "Z", "Q", "CO",
                "QN", "YN", "XN", "ZN",
                "Q_N", "Y_N", "X_N", "Z_N"}:
        return "OUTPUT_by_name"
    # Clock-like inputs
    if base in {"CLK", "CK", "CP", "NCLK", "CLK_N", "CLKN",
                "GATE", "GATE_N"}:
        return "INPUT_clock_by_name"
    # Reset/set inputs (async control)
    if base in {"RESET", "RESET_B", "RESETN", "RESET_N",
                "SET", "SET_B", "SETN", "SET_N",
                "CLR", "CLR_B", "CLRN",
                "EN", "EN_N", "ENABLE"}:
        return "INPUT_by_name"
    # Single-letter with optional digit / _N suffix
    if re.match(r'^[A-Z]\d*(_N)?$', base):
        return "INPUT_by_name"
    return "UNKNOWN_by_name"


def is_signal_pin(pin):
    return pin["use"] not in ("POWER", "GROUND")


def main():
    if len(sys.argv) not in (2, 3):
        print("usage: %s <lef_file> [--debug]" % sys.argv[0], file=sys.stderr)
        sys.exit(2)

    path = sys.argv[1]
    debug = (len(sys.argv) == 3 and sys.argv[2] == "--debug")

    macros, tokens = parse_lef(path, debug=debug)

    if len(macros) < 2:
        print("!" * 78, file=sys.stderr)
        print("PARSER BAIL: only %d macros parsed from %s" % (len(macros), path), file=sys.stderr)
        print("Macros parsed: %s" % list(macros.keys()), file=sys.stderr)
        print("First 60 tokens:", file=sys.stderr)
        for j, (t, ln) in enumerate(tokens[:60]):
            print("  token[%3d] line=%-4d %r" % (j, ln, t), file=sys.stderr)
        sys.exit(1)

    print("=" * 78)
    print("LEF INSPECTION REPORT  --  %s" % path)
    print("=" * 78)
    print()
    print("Total MACROs parsed: %d" % len(macros))
    print("MACRO names: %s" % sorted(macros.keys()))
    print()

    dir_hist = defaultdict(int)
    for m in macros.values():
        for p in m["pins"].values():
            if is_signal_pin(p):
                dir_hist[p["direction"] or "(none)"] += 1
    print("-" * 78)
    print("DIRECTION FIELD USAGE (signal pins only)")
    print("-" * 78)
    for d, n in sorted(dir_hist.items(), key=lambda x: -x[1]):
        print("  %-10s  %d pins" % (d, n))
    print()

    print("-" * 78)
    print("PER-CELL ANTENNA DATA PRESENCE")
    print("-" * 78)
    print()
    print("%-14s %-8s %-7s %-22s  ANTENNA_ATTRS" % ("CELL", "PIN", "DIR", "NAME_IMPLIES"))
    print("-" * 78)

    cell_output_pins = defaultdict(list)
    cell_input_pins = defaultdict(list)
    cell_output_missing_diff = defaultdict(list)
    cell_input_missing_gate = defaultdict(list)

    for cname, m in macros.items():
        for pname, p in m["pins"].items():
            if not is_signal_pin(p):
                continue
            direction = p["direction"] or "---"
            inferred = infer_io_from_name(pname)

            attr_summary = defaultdict(list)
            for (attr, val, layer) in p["antenna"]:
                if val is not None and layer is not None:
                    attr_summary[attr].append("%.4f@%s" % (val, layer))
                elif layer is not None:
                    attr_summary[attr].append(layer)

            if attr_summary:
                parts = "  ".join(
                    "%sx%d(%s)" % (a, len(vs), ",".join(vs))
                    for a, vs in sorted(attr_summary.items())
                )
            else:
                parts = "(no antenna attrs)"
            print("%-14s %-8s %-7s %-22s  %s" %
                  (cname, pname, direction, inferred, parts))

            if "OUTPUT" in inferred:
                cell_output_pins[cname].append(pname)
                if not any(a == "ANTENNADIFFAREA" for (a, _, _) in p["antenna"]):
                    cell_output_missing_diff[cname].append(pname)
            elif "INPUT" in inferred:
                cell_input_pins[cname].append(pname)
                if not any(a == "ANTENNAGATEAREA" for (a, _, _) in p["antenna"]):
                    cell_input_missing_gate[cname].append(pname)
        print()

    broken = []
    complete = []
    for cname in macros:
        mg = cell_input_missing_gate.get(cname, [])
        md = cell_output_missing_diff.get(cname, [])
        if mg or md:
            broken.append((cname, mg, md))
        elif cell_input_pins.get(cname) or cell_output_pins.get(cname):
            complete.append(cname)

    print("=" * 78)
    print("SUMMARY")
    print("=" * 78)
    print("Cells COMPLETE (%d):" % len(complete))
    for c in sorted(complete):
        print("  %s" % c)
    print()
    print("Cells MISSING data (%d):" % len(broken))
    for cname, mg, md in sorted(broken):
        bits = []
        if mg: bits.append("missing GATEAREA on inputs %s" % mg)
        if md: bits.append("missing DIFFAREA on outputs %s" % md)
        print("  %-14s  %s" % (cname, "; ".join(bits)))
    print()

    print("-" * 78)
    print("PATTERN HINT: attributes present on COMPLETE cells")
    print("-" * 78)
    comp_input_attrs = defaultdict(int)
    comp_output_attrs = defaultdict(int)
    for cname in complete:
        for pname, p in macros[cname]["pins"].items():
            if not is_signal_pin(p):
                continue
            inferred = infer_io_from_name(pname)
            attrs_here = set(a for (a, _, _) in p["antenna"])
            if "OUTPUT" in inferred:
                for a in attrs_here:
                    comp_output_attrs[a] += 1
            elif "INPUT" in inferred:
                for a in attrs_here:
                    comp_input_attrs[a] += 1

    print("  On INPUT pins of complete cells:")
    for a, n in sorted(comp_input_attrs.items(), key=lambda x: -x[1]):
        print("    %-30s  on %d pins" % (a, n))
    print()
    print("  On OUTPUT pins of complete cells:")
    for a, n in sorted(comp_output_attrs.items(), key=lambda x: -x[1]):
        print("    %-30s  on %d pins" % (a, n))
    print()

    print("-" * 78)
    print("FAMILY COMPARISON")
    print("-" * 78)
    families = defaultdict(list)
    for cname in macros:
        m = re.match(r'^(.+?)(?:_(\d+))?$', cname)
        fam = m.group(1) if m else cname
        families[fam].append(cname)

    for fam, cells in sorted(families.items()):
        print()
        print("  Family '%s': %s" % (fam, sorted(cells)))
        for cname in sorted(cells):
            per_pin = []
            for pname, p in macros[cname]["pins"].items():
                if not is_signal_pin(p):
                    continue
                inferred = infer_io_from_name(pname)
                attrs_here = sorted(set(a for (a, _, _) in p["antenna"]))
                dir_hint = ("OUT" if "OUTPUT" in inferred else
                            ("IN" if "INPUT" in inferred else "?"))
                per_pin.append("%s[%s]=%s" % (pname, dir_hint, attrs_here or "[]"))
            print("    %-14s  %s" % (cname, "  |  ".join(per_pin)))

    print()
    print("=" * 78)
    print("END OF REPORT")
    print("=" * 78)


if __name__ == "__main__":
    main()