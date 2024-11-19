addi r1,r1,4
addi r2,r2,5
mul r3,r2,r1
add r4,r2,r1 ; mul and add are performed out of order; they write their results on different regs
div r5,r3,r4
add r5,r3,r4 ; div and add are performed out of order; only the add result should be written in r5
mul r5,r1,r5 ; check if the mul uses the result of the add as r5
mul r6,r2,r1 ; executed in parallel with the previous one
nop
nop
nop
nop
nop
nop
nop
nop
nop
nop
add r8,r1,r2
add r8,r1,r2
add r8,r1,r2
add r11,r3,r4
add r10,r3,r2 ; this add should compete with the mul for which instruction is able to leave the memory
add r9,r1,r4 
div r7,r3,r4 ; executed in parallel with the two previous mul
mul r4,r3,r0 ; should reset r4
beqz r4,label ; make sure the div terminates execution
sw 0(r0),r2 ; should not be executed
nop
label:
mul r5,r1,r3
sw 0(r0),r2
lw r4, 0(r0) ; verify that the lw stalls in memory until the sw is committed (which will happen after the mul terminates)
infinite_loop:
j infinite_loop
exit
