# ============================================================
# test_mem_timing.S — Memory timing verification
#
# Simple sequence to observe SRAM and ROM waveforms:
#   1. SW to SRAM (write)
#   2. LW from SRAM (read back)
#   3. LW from ROM (read)
#   4. Another SW to SRAM
#   5. Done
# ============================================================

.section .text
.globl _start

.equ SRAM_BASE,   0x08000000
.equ SCRATCH,     0x08000A00
.equ ROM_BASE,    0x20000000
.equ RESULT_ADDR, 0x08000B20
.equ DONE_ADDR,   0x08000B28

_start:
    # Load addresses
    lui     s0, %hi(RESULT_ADDR)
    addi    s0, s0, %lo(RESULT_ADDR)
    lui     s1, %hi(DONE_ADDR)
    addi    s1, s1, %lo(DONE_ADDR)
    lui     s2, %hi(SCRATCH)
    addi    s2, s2, %lo(SCRATCH)
    lui     s3, %hi(ROM_BASE)

    # --- SRAM Write ---
    li      t1, 0x12345678
    sw      t1, 0(s2)               # SW to scratch area

    # --- SRAM Read ---
    lw      t2, 0(s2)               # LW from scratch area
    bne     t1, t2, fail            # verify readback

    # --- ROM Read (WL=0, COL=0 → 0x00000000) ---
    lw      t3, 0(s3)
    bne     t3, zero, fail

    # --- ROM Read (WL=1, COL=0 → 0x55555555) ---
    lw      t4, 4(s3)
    beq     t4, zero, fail          # should be non-zero

    # --- Another SRAM Write ---
    li      t5, 0xDEADBEEF
    sw      t5, 4(s2)               # SW to scratch+4

    # --- SRAM Read back ---
    lw      t6, 4(s2)
    bne     t5, t6, fail

    # PASS
    li      t0, 1
    sw      t0, 0(s0)
    li      t0, -1
    sw      t0, 0(s1)
    j       done

fail:
    li      t0, 0xFF
    sw      t0, 0(s0)
    li      t0, -1
    sw      t0, 0(s1)

done:
    j       done
