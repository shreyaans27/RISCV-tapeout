.section .text
.globl _start

.equ RESULT_ADDR, 0x08000B20
.equ DONE_ADDR,   0x08000B28

_start:
    li      t1, 7
    li      t2, 6
    mul     t3, t1, t2
    lui     s0, %hi(RESULT_ADDR)
    addi    s0, s0, %lo(RESULT_ADDR)
    lui     s1, %hi(DONE_ADDR)
    addi    s1, s1, %lo(DONE_ADDR)
    li      t4, 42
    bne     t3, t4, fail
    li      t0, 1
    sw      t0, 0(s0)
    li      t0, -1
    sw      t0, 0(s1)
    j       done
fail:
    li      t0, -1
    sw      t0, 0(s1)
done:
    j       done
