addi r1,r0,12
sw 0(r0),r1
addi r1,r0,3
sw 4(r0),r1
addi r1,r0,5
sw 8(r0),r1
addi r1,r0,4
sw 12(r0),r1
addi r1,r0,10
sw 16(r0),r1
addi r1,r0,6
sw 20(r0),r1
addi r1,r0,7
sw 24(r0),r1
addi r1,r0,0
sw 28(r0),r1
addi r1,r0,24
sw 32(r0),r1
addi r1,r0,16
sw 36(r0),r1
addi r1,r0,0 ; external counter of iterations
addi r3,r0,36 ; limit for external iterations
loop_ext:
    addi r2,r0,0 ; internal counter of iterations
    sub r4,r3,r1 ; number of internal iterations
loop_int:
        lw r5,0(r2) ; first value
        lw r6,4(r2) ; second value
        sle r7,r5,r6 ; r7 is true if there is no need to perform the swap
        bnez r7,already_sorted
            sw 0(r2),r6 ; write the second value in the first position
            sw 4(r2),r5 ; write the first value in the second position
already_sorted:
        addi r2,r2,4
        sub r7,r4,r2
        bnez r7,loop_int
    addi r1,r1,4
    sub r7,r3,r1
    bnez r7,loop_ext
forever:
    j forever
exit

