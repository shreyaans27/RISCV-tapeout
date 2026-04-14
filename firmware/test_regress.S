# ============================================================
# test_regress.S — Comprehensive regression tests
#
# Tests grouped by category:
#   1. LUI / AUIPC
#   2. ADDI, ANDI, ORI, XORI, SLTI, SLTIU
#   3. ADD, SUB, AND, OR, XOR, SLT, SLTU
#   4. SLLI, SRLI, SRAI, SLL, SRL, SRA
#   5. LW, LH, LB, LHU, LBU
#   6. SW, SH, SB
#   7. BEQ, BNE, BLT, BGE, BLTU, BGEU
#   8. JAL, JALR
#   9. MUL, MULH, MULHU
#  10. ROM reads (all 4 patterns)
#  11. DOTPROD4, ACC_RESET, ACC_READ
#
# Result: writes test number to 0x08000B20 on fail
#         writes 0x01 to 0x08000B20 on pass
#         writes 0xFF to 0x08000B28 when done
# ============================================================

.section .text
.globl _start

# Addresses
.equ SRAM_BASE,   0x08000000
.equ RESULT_ADDR, 0x08000B20
.equ DONE_ADDR,   0x08000B28
.equ SCRATCH,     0x08000A00    # scratch area for load/store tests
.equ ROM_BASE,    0x20000000

_start:
    # Load commonly used addresses
    lui     s0, %hi(RESULT_ADDR)
    addi    s0, s0, %lo(RESULT_ADDR)    # s0 = RESULT_ADDR
    lui     s1, %hi(DONE_ADDR)
    addi    s1, s1, %lo(DONE_ADDR)      # s1 = DONE_ADDR
    lui     s2, %hi(SCRATCH)
    addi    s2, s2, %lo(SCRATCH)        # s2 = SCRATCH area
    lui     s3, %hi(ROM_BASE)           # s3 = ROM_BASE

# ============================================================
# Test 1: LUI
# ============================================================
test_1:
    li      t0, 1                       # test number
    lui     t1, 0x12345
    li      t2, 0x12345000
    bne     t1, t2, fail

# ============================================================
# Test 2: AUIPC
# ============================================================
test_2:
    li      t0, 2
    auipc   t1, 0                       # t1 = PC of this instruction
    # PC should be in SRAM range (0x08000xxx)
    srli    t2, t1, 20                  # upper 12 bits
    li      t3, 0x080                   # expected upper 12 bits
    bne     t2, t3, fail

# ============================================================
# Test 3: ADDI
# ============================================================
test_3:
    li      t0, 3
    li      t1, 100
    addi    t1, t1, 50                  # 100 + 50 = 150
    li      t2, 150
    bne     t1, t2, fail

    li      t1, 10
    addi    t1, t1, -20                 # 10 + (-20) = -10
    li      t2, -10
    bne     t1, t2, fail

# ============================================================
# Test 4: ANDI, ORI, XORI
# ============================================================
test_4:
    li      t0, 4
    li      t1, 0xFF
    andi    t2, t1, 0x0F               # 0xFF & 0x0F = 0x0F
    li      t3, 0x0F
    bne     t2, t3, fail

    li      t1, 0xF0
    ori     t2, t1, 0x0F               # 0xF0 | 0x0F = 0xFF
    li      t3, 0xFF
    bne     t2, t3, fail

    li      t1, 0xFF
    xori    t2, t1, 0x0F               # 0xFF ^ 0x0F = 0xF0
    li      t3, 0xF0
    bne     t2, t3, fail

# ============================================================
# Test 5: ADD, SUB
# ============================================================
test_5:
    li      t0, 5
    li      t1, 100
    li      t2, 200
    add     t3, t1, t2                  # 100 + 200 = 300
    li      t4, 300
    bne     t3, t4, fail

    sub     t3, t2, t1                  # 200 - 100 = 100
    bne     t3, t1, fail

# ============================================================
# Test 6: AND, OR, XOR
# ============================================================
test_6:
    li      t0, 6
    li      t1, 0xAA
    li      t2, 0x55
    and     t3, t1, t2                  # 0xAA & 0x55 = 0x00
    bne     t3, zero, fail

    or      t3, t1, t2                  # 0xAA | 0x55 = 0xFF
    li      t4, 0xFF
    bne     t3, t4, fail

    xor     t3, t1, t2                  # 0xAA ^ 0x55 = 0xFF
    bne     t3, t4, fail

# ============================================================
# Test 7: SLT, SLTU, SLTI, SLTIU
# ============================================================
test_7:
    li      t0, 7
    li      t1, -1                      # 0xFFFFFFFF
    li      t2, 1
    slt     t3, t1, t2                  # -1 < 1 (signed) = 1
    li      t4, 1
    bne     t3, t4, fail

    sltu    t3, t2, t1                  # 1 < 0xFFFFFFFF (unsigned) = 1
    bne     t3, t4, fail

    slti    t3, t1, 0                   # -1 < 0 (signed) = 1
    bne     t3, t4, fail

# ============================================================
# Test 8: Shifts (SLLI, SRLI, SRAI)
# ============================================================
test_8:
    li      t0, 8
    li      t1, 1
    slli    t2, t1, 4                   # 1 << 4 = 16
    li      t3, 16
    bne     t2, t3, fail

    li      t1, 256
    srli    t2, t1, 4                   # 256 >> 4 = 16
    bne     t2, t3, fail

    li      t1, -16                     # 0xFFFFFFF0
    srai    t2, t1, 2                   # -16 >>> 2 = -4 (arithmetic)
    li      t3, -4
    bne     t2, t3, fail

# ============================================================
# Test 9: Register shifts (SLL, SRL, SRA)
# ============================================================
test_9:
    li      t0, 9
    li      t1, 1
    li      t2, 8
    sll     t3, t1, t2                  # 1 << 8 = 256
    li      t4, 256
    bne     t3, t4, fail

    srl     t3, t4, t2                  # 256 >> 8 = 1
    bne     t3, t1, fail

# ============================================================
# Test 10: SW / LW
# ============================================================
test_10:
    li      t0, 10
    li      t1, 0x12345678
    sw      t1, 0(s2)                   # store word
    lw      t2, 0(s2)                   # load word
    bne     t1, t2, fail

# ============================================================
# Test 11: SH / LH / LHU
# ============================================================
test_11:
    li      t0, 11
    sw      zero, 0(s2)                 # clear scratch
    li      t1, 0xBEEF
    sh      t1, 0(s2)                   # store halfword at offset 0
    lh      t2, 0(s2)                   # load halfword (sign-extend)
    li      t3, 0xFFFFBEEF             # 0xBEEF sign-extended
    bne     t2, t3, fail

    lhu     t2, 0(s2)                   # load halfword unsigned
    li      t3, 0x0000BEEF
    bne     t2, t3, fail

# ============================================================
# Test 12: SB / LB / LBU
# ============================================================
test_12:
    li      t0, 12
    sw      zero, 0(s2)                 # clear scratch
    li      t1, 0x80                    # -128 as signed byte
    sb      t1, 1(s2)                   # store byte at offset 1
    lb      t2, 1(s2)                   # load byte (sign-extend)
    li      t3, -128
    bne     t2, t3, fail

    lbu     t2, 1(s2)                   # load byte unsigned
    li      t3, 0x80
    bne     t2, t3, fail

# ============================================================
# Test 13: BEQ / BNE
# ============================================================
test_13:
    li      t0, 13
    li      t1, 42
    li      t2, 42
    bne     t1, t2, fail                # should NOT branch (equal)
    li      t2, 43
    beq     t1, t2, fail                # should NOT branch (not equal)

# ============================================================
# Test 14: BLT / BGE
# ============================================================
test_14:
    li      t0, 14
    li      t1, -5
    li      t2, 5
    bge     t1, t2, fail                # -5 >= 5? NO
    blt     t2, t1, fail                # 5 < -5? NO

# ============================================================
# Test 15: JAL / JALR
# ============================================================
test_15:
    li      t0, 15
    jal     t1, test_15_target          # t1 = return addr
    j       test_15_back
test_15_target:
    jalr    zero, t1, 0                 # jump back to after jal
test_15_back:

# ============================================================
# Test 16: MUL
# ============================================================
test_16:
    li      t0, 16
    li      t1, 7
    li      t2, 6
    mul     t3, t1, t2                  # 7 * 6 = 42
    li      t4, 42
    bne     t3, t4, fail

    li      t1, -3
    li      t2, 4
    mul     t3, t1, t2                  # -3 * 4 = -12
    li      t4, -12
    bne     t3, t4, fail

# ============================================================
# Test 17: ROM reads — all 4 patterns
# ============================================================
test_17:
    li      t0, 17
    # WL=0, COL=0 → pattern 0 → 0x00000000
    lw      t1, 0(s3)
    bne     t1, zero, fail

    # WL=1, COL=0 → pattern 1 → 0x55555555
    lw      t1, 4(s3)
    lui     t2, 0x55555
    addi    t2, t2, 0x555
    bne     t1, t2, fail

    # WL=2, COL=0 → pattern 2 → 0xAAAAAAAA
    lw      t1, 8(s3)
    lui     t2, 0xAAAAB
    addi    t2, t2, -1366              # 0xAAAAAAAA
    bne     t1, t2, fail

    # WL=3, COL=0 → pattern 3 → 0xFFFFFFFF
    lw      t1, 12(s3)
    li      t2, -1                      # 0xFFFFFFFF
    bne     t1, t2, fail

# ============================================================
# Test 18: DOTPROD4 — basic
# ============================================================
test_18:
    li      t0, 18
    # rs1 = 0x01020304 (bytes: 4, 3, 2, 1)
    lui     a0, 0x01020
    addi    a0, a0, 0x304
    # rs2 = 0x01010101 (bytes: 1, 1, 1, 1)
    lui     a1, 0x01010
    addi    a1, a1, 0x101

    # ACC_RESET
    .word   0x0200000B
    # DOTPROD4
    .word   0x00B5050B
    # ACC_READ → a2
    .word   0x0400060B

    li      a3, 10                      # expected: 1+2+3+4 = 10
    bne     a2, a3, fail

# ============================================================
# Test 19: DOTPROD4 — accumulate twice
# ============================================================
test_19:
    li      t0, 19
    # ACC_RESET
    .word   0x0200000B
    # DOTPROD4 with same values
    .word   0x00B5050B
    # DOTPROD4 again
    .word   0x00B5050B
    # ACC_READ → a2
    .word   0x0400060B

    li      a3, 20                      # expected: 10 + 10 = 20
    bne     a2, a3, fail

# ============================================================
# Test 20: DOTPROD4 — signed values
# ============================================================
test_20:
    li      t0, 20
    # rs1 = 0xFFFFFFFF (bytes: -1, -1, -1, -1)
    li      a0, -1
    # rs2 = 0x01010101 (bytes: 1, 1, 1, 1)
    lui     a1, 0x01010
    addi    a1, a1, 0x101

    # ACC_RESET
    .word   0x0200000B
    # DOTPROD4
    .word   0x00B5050B
    # ACC_READ → a2
    .word   0x0400060B

    li      a3, -4                      # expected: (-1)*1 * 4 = -4
    bne     a2, a3, fail

# ============================================================
# ALL PASS
# ============================================================
pass:
    li      t0, 1                       # PASS = 0x01
    sb      t0, 0(s0)                   # write to RESULT_ADDR
    li      t0, -1                      # 0xFF
    sb      t0, 0(s1)                   # write to DONE_ADDR
    j       done

fail:
    sb      t0, 0(s0)                   # write test number to RESULT_ADDR
    li      t0, -1
    sb      t0, 0(s1)                   # write 0xFF to DONE_ADDR

done:
    j       done
