08210004    addi r1,r1,4
08420005    addi r2,r2,5
00411818    mul r3,r2,r1
00412001    add r4,r2,r1 ; mul and add are performed out of order; they write their results on different regs
00642819    div r5,r3,r4
00642801    add r5,r3,r4 ; div and add are performed out of order; only the add result should be written in r5
00252818    mul r5,r1,r5 ; check if the mul uses the result of the add as r5
00413018    mul r6,r2,r1 ; executed in parallel with the previous one
00000000    nop
00000000    nop
00000000    nop
00000000    nop
00000000    nop
00000000    nop
00000000    nop
00000000    nop
00000000    nop
00000000    nop
00224001    add r8,r1,r2
00224001    add r8,r1,r2
00224001    add r8,r1,r2
00645801    add r11,r3,r4
00625001    add r10,r3,r2 ; this add should compete with the mul for which instruction is able to leave the memory
00244801    add r9,r1,r4 
00643819    div r7,r3,r4 ; stalls because the previous div is still executing
00602018    mul r4,r3,r0 ; should reset r4
14800008    beqz r4,label ; make sure the div terminates execution
a8020000    sw 0(r0),r2 ; should not be executed
00000000    nop
label       label:
00232818    mul r5,r1,r3
a8020000    sw 0(r0),r2
50040000    lw r4, 0(r0) ; verify that the lw stalls in memory until the sw is committed (which will happen after the mul terminates)
loop        infinite_loop:
27fffffc    j infinite_loop

