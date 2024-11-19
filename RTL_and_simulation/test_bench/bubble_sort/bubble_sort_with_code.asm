00 0801000c    addi r1,r0,12
04 a8010000    sw 0(r0),r1
08 08010003    addi r1,r0,3
0C a8010004    sw 4(r0),r1
10 08010005    addi r1,r0,5
14 a8010008    sw 8(r0),r1
18 08010004    addi r1,r0,4
1C a801000c    sw 12(r0),r1
20 0801000a    addi r1,r0,10
24 a8010010    sw 16(r0),r1
28 08010006    addi r1,r0,6
2C a8010014    sw 20(r0),r1
30 08010007    addi r1,r0,7
34 a8010018    sw 24(r0),r1
38 08010000    addi r1,r0,0
3C a801001c    sw 28(r0),r1
40 08010018    addi r1,r0,24
44 a8010020    sw 32(r0),r1
48 08010010    addi r1,r0,16
4C a8010024    sw 36(r0),r1
50 08010000    addi r1,r0,0 ; external counter of iterations
54 08030024    addi r3,r0,36 ; limit for external iterations
label    loop_ext:
58 08020000        addi r2,r0,0 ; internal counter of iterations
5C 0061201a        sub r4,r3,r1 ; number of internal iterations
label    loop_int:
60 50450000            lw r5,0(r2) ; first value
64 50460004            lw r6,4(r2) ; second value
68 00a63810            sle r7,r5,r6 ; r7 is true if there is no need to perform the swap
6C 20e00008            bnez r7,already_sorted
70 a8460000                sw 0(r2),r6 ; write the second value in the first position
74 a8450004                sw 4(r2),r5 ; write the first value in the second position
label    already_sorted:
78 08420004            addi r2,r2,4
7C 0082381a            sub r7,r4,r2
80 20e0ffdc            bnez r7,loop_int
84 08210004        addi r1,r1,4
88 0061381a        sub r7,r3,r1
8C 20e0ffc8        bnez r7,loop_ext
label    forever:
90 27fffffc        j forever
94 00000400    exit