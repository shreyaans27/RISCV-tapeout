#!/usr/bin/env python3
"""Convert objcopy verilog hex to $readmemh format (32-bit words)"""
import sys

mem = {}

with open(sys.argv[1]) as f:
    addr = 0
    for line in f:
        line = line.strip()
        if line.startswith('@'):
            addr = int(line[1:], 16)
        else:
            for byte_str in line.split():
                mem[addr] = int(byte_str, 16)
                addr += 1

# Find base address (should be 0x08000000)
base = min(mem.keys())

# Output as 32-bit words, little-endian
max_addr = max(mem.keys())
word_addr = 0
while base + word_addr * 4 <= max_addr:
    b0 = mem.get(base + word_addr * 4 + 0, 0)
    b1 = mem.get(base + word_addr * 4 + 1, 0)
    b2 = mem.get(base + word_addr * 4 + 2, 0)
    b3 = mem.get(base + word_addr * 4 + 3, 0)
    word = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
    print(f"{word:08x}")
    word_addr += 1

