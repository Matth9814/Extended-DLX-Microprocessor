library IEEE;
use IEEE.std_logic_1164.all; 
use WORK.constants.all;

entity ND4 is
	Port (A: in	std_logic;
		B: in std_logic;
        C: in std_logic;
        D: in std_logic;
		Y: out std_logic);
end ND4;

-- Both the BEHAVIORAL descriptions use a NAND4 from the std. cell library we are using
-- so they are faster and less area consuming than the implementation using NAND2 and INV
architecture BEHAVIORAL of ND4 is
begin
	Y <= not( A and B and C and D);
end BEHAVIORAL;

architecture BEHAVIORAL2 of ND4 is
begin
    Y <= not(A nand B) nand not(C nand D);
end BEHAVIORAL2;

architecture STRUCTURAL of ND4 is
    component ND2 is
        Port(A:	in	std_logic;
            B:	in	std_logic;
            Y:	out	std_logic);
    end component;

    component IV is
        Port (A: in	std_logic;
            Y:  out	std_logic);
    end component;

    signal L0,L0_inv: std_logic;
    signal L1,L1_inv: std_logic;
begin
    NAND0: nd2 port map (A=>A,B=>B,Y=>L0);
    INV0: iv port map (A=>L0,Y=>L0_inv);
    NAND1: nd2 port map (A=>C,B=>D,Y=>L1);
    INV1: iv port map (A=>L1,Y=>L1_inv);
    NAND2: nd2 port map (A=>L0_inv,B=>L1_inv,Y=>Y);
end STRUCTURAL;

configuration CFG_ND4_BEHAV of ND4 is
	for BEHAVIORAL
	end for;
end CFG_ND4_BEHAV;

configuration CFG_ND4_BEHAV2 of ND4 is
	for BEHAVIORAL2
	end for;
end CFG_ND4_BEHAV2;

configuration CFG_ND4_STRUCTURAL of ND4 is
    for STRUCTURAL
        for NAND0 : nd2
            use configuration work.CFG_ND2_ARCH1;
        end for;
        for INV0 : iv
            use configuration work.CFG_IV_BEHAVIORAL;
        end for;
        for NAND1 : nd2
            use configuration work.CFG_ND2_ARCH1;
        end for;
        for INV1 : iv
            use configuration work.CFG_IV_BEHAVIORAL;
        end for;
        for NAND2 : nd2
            use configuration work.CFG_ND2_ARCH1;
        end for;
    end for;
end CFG_ND4_STRUCTURAL;

