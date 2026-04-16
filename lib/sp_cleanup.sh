#!/bin/bash
# sp_cleanup.sh — automate SP file preparation for Liberate
# Usage: ./sp_cleanup.sh <cell_name> [cell_name2 ...]

BASE="/home/home3/team2chips2026"
LVS_DIR="$BASE/TSMC_180_work/LVS"
NETLIST_DIR="$BASE/Liberate_work/trio_flow_stdcells2/gpdk/netlists"
CELLS_TCL="$BASE/Liberate_work/trio_flow_stdcells2/gpdk/cells.tcl"

cleanup_sp() {
    local cell=$1
    local src=""

    # Find source file
    if [ -f "$LVS_DIR/${cell}.sp" ]; then
        src="$LVS_DIR/${cell}.sp"
    elif [ -f "$LVS_DIR/${cell}_1.sp" ]; then
        src="$LVS_DIR/${cell}_1.sp"
    else
        echo "ERROR: cannot find ${cell}.sp or ${cell}_1.sp in $LVS_DIR"
        return 1
    fi

    local dst="$NETLIST_DIR/${cell}.sp"
    echo ""
    echo "── Processing: $cell ──"
    echo "  Source: $src"

    # Step 1: Remove PDK passive blocks using Python-style approach in awk
    # A PDK passive block starts with .SUBCKT <name> where name does NOT
    # match any of our known standard cells — we keep only subckts that
    # contain actual transistors (M lines) or X instance lines
    awk '
    /^\.SUBCKT/ {
        # Start collecting a new block
        block = $0 "\n"
        has_devices = 0
        in_block = 1
        next
    }
    in_block && /^\.ENDS/ {
        block = block $0 "\n"
        in_block = 0
        # Only print if block has real devices
        if (has_devices) {
            printf "%s", block
            print "***************************************"
        }
        block = ""
        next
    }
    in_block {
        block = block $0 "\n"
        # Check for transistor instances (M lines) or subcell instances (X lines)
        if ($0 ~ /^M/ || $0 ~ /^X/) {
            has_devices = 1
        }
        next
    }
    # Lines outside subckt blocks — print header comments only
    /^\*/ { print; next }
    /^\./ { next }  # skip other directives outside subckts
    { print }
    ' "$src" | awk -v cell="$cell" '
    BEGIN {
        # Build suffix from cell name — strip _1/_2/_4 drive strength suffix
        suffix = cell
        sub(/_[0-9]+$/, "", suffix)
    }
    # Fix N->nch and P->pch on transistor lines
    /^M/ {
        gsub(/ N L=/, " nch L=")
        gsub(/ P L=/, " pch L=")
        gsub(/ N$/, " nch")
        gsub(/ P$/, " pch")
        gsub(/\tN\tL=/, "\tnch\tL=")
        gsub(/\tP\tL=/, "\tpch\tL=")
    }
    # Rename subckt definitions — skip the top-level cell itself
    /^\.SUBCKT/ {
        subckt_name = $2
        if (subckt_name != cell) {
            new_name = subckt_name "_" suffix
            gsub(subckt_name, new_name)
            rename_map[subckt_name] = new_name
        }
    }
    # Rename X instance calls to match renamed subckts
    /^X/ {
        # Last field before parameters is the subckt type
        # Find and replace any known renamed subckt names
        for (orig in rename_map) {
            gsub(" " orig " ", " " rename_map[orig] " ")
            gsub(" " orig "$", " " rename_map[orig])
        }
    }
    # Skip pure separator lines (only asterisks)
    /^\*+$/ { next }
    { print }
    ' > "$dst"

    echo "  Written: $dst"

    # Show what subckts are in the output
    echo "  Subckt blocks kept:"
    grep "^\.SUBCKT" "$dst"
}

add_to_cells_tcl() {
    local cell=$1

    if grep -q "^${cell}$" "$CELLS_TCL" 2>/dev/null; then
        echo "  $cell already in cells.tcl"
        return
    fi

    sed -i "s/^}$/${cell}\n}/" "$CELLS_TCL"
    echo "  Added $cell to cells.tcl"
}

if [ $# -eq 0 ]; then
    echo "Usage: $0 <cell_name> [cell_name2 ...]"
    echo "Example: $0 inv_1 dfrtp_1 dfsbp_1"
    exit 1
fi

mkdir -p "$NETLIST_DIR"

for cell in "$@"; do
    cleanup_sp "$cell"
done

echo ""
echo "Check output files in: $NETLIST_DIR"
echo "Then copy to netlists dir and run Liberate"
