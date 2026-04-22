#!/usr/bin/env python3
"""
Layer name renaming script for TSMC 180nm Innovus <-> QRC flow.
Usage:
  python3 rename_layers.py --forward  input.lef  output.lef
  python3 rename_layers.py --backward input.def  output.def
"""

import sys
import argparse

# Mapping: Innovus names -> QRC names
REPLACEMENTS = {
    "METAL6": "METAL_6",
    "METAL5": "METAL_5",
    "METAL4": "METAL_4",
    "METAL3": "METAL_3",
    "METAL2": "METAL_2",
    "METAL1": "METAL_1",
    "VIA56":  "VIA_5",
    "VIA45":  "VIA_4",
    "VIA34":  "VIA_3",
    "VIA23":  "VIA_2",
    "VIA12":  "VIA_1",
    "POLY1":  "POLY_1",
    "CONT":   "CONTACT",
}

def rename(input_file, output_file, forward=True):
    with open(input_file, "r") as f:
        content = f.read()

    if forward:
        mapping = REPLACEMENTS
    else:
        mapping = {v: k for k, v in REPLACEMENTS.items()}

    # Replace longer names first to avoid partial matches
    for old, new in sorted(mapping.items(), key=lambda x: -len(x[0])):
        content = content.replace(old, new)

    with open(output_file, "w") as f:
        f.write(content)

    print(f"Done: {input_file} -> {output_file} ({'forward' if forward else 'backward'})")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--forward",  action="store_true", help="Innovus -> QRC naming")
    parser.add_argument("--backward", action="store_true", help="QRC -> Innovus naming")
    parser.add_argument("input",  help="Input file")
    parser.add_argument("output", help="Output file")
    args = parser.parse_args()

    if not args.forward and not args.backward:
        print("Specify --forward or --backward")
        sys.exit(1)

    rename(args.input, args.output, forward=args.forward)
