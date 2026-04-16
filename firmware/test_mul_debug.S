.section .text
.globl _start

.equ RESULT_ADDR, 0x08000B20
.equ DONE_ADDR,   0x08000B28

_start:
    # Load operands
    li      t1, 7           # t1 = 7
    li      t2, 6           # t2 = 6
    
    # MUL t3, t1, t2 → t3 = 42
    mul     t3, t1, t2
    
    # Store result
    lui     s0, %hi(RESULT_ADDR)
    addi    s0, s0, %lo(RESULT_ADDR)
    lui     s1, %hi(DONE_ADDR)
    addi    s1, s1, %lo(DONE_ADDR)
    
    # Check result
    li      t4, 42
    bne     t3, t4, fail
    
    li      t0, 1
    sw      t0, 0(s0)
    li      t0, -1
    sw      t0, 0(s1)
    j       done

fail:
    sw      t3, 0(s0)      # store actual result for debug
    li      t0, -1
    sw      t0, 0(s1)

done:
    j       done
